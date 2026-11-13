#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
    echo "Run as a regular user, not root." >&2
    exit 1
fi

sudo -v

echo "==> enabling copr repos"
sudo dnf copr enable -y scottames/ghostty
sudo dnf copr enable -y komapro/nerd-fonts

echo "==> upgrading system"
sudo dnf upgrade -y

echo "==> installing packages"
sudo dnf group install -y development-tools
sudo dnf install -y \
    git gh neovim tmux ripgrep fd-find fzf bash-completion ghostty git-delta zoxide stow glances
sudo dnf install -y jetbrainsmono-nerd-font
fc-cache -f
# ponytail: DBeaver has no official Fedora RPM repo, so `dnf upgrade` never
# updates it — re-running bootstrap is the update path. Compare the CDN's
# `-latest-` redirect version against the installed one so a current install
# skips the full RPM download. Fix this URL if DBeaver renames the file scheme.
DBEAVER_URL=https://dbeaver.io/files/dbeaver-ce-latest-linux-x86_64.rpm
dbeaver_latest=$(curl -fsSI "$DBEAVER_URL" \
    | sed -n 's#^[Ll]ocation:.*/dbeaver-ce-\([0-9][^/]*\)-linux.*#\1#p' | tr -d '\r')
dbeaver_current=$(rpm -q --qf '%{VERSION}' dbeaver-ce 2>/dev/null || true)
if [ "$dbeaver_latest" != "$dbeaver_current" ]; then
    sudo dnf install -y "$DBEAVER_URL"
fi

echo "==> docker"
[ -f /etc/yum.repos.d/docker-ce.repo ] || \
    sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker "$(id -un)"

echo "==> login shell"
[ "$(basename "$(getent passwd "$(id -un)" | cut -d: -f7)")" = bash ] || \
    sudo chsh -s "$(command -v bash)" "$(id -un)"

echo "==> stow dotfiles"
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# ponytail: stow refuses to overwrite a real file, so drop any pre-existing
# copy of a config we own before linking. Back these up yourself if you keep
# local edits in $HOME.
rm -f "$HOME/.config/tmux/tmux.conf" "$HOME/.config/ghostty/config.ghostty" \
    "$HOME/.config/opencode/opencode.json"
# COSMIC keeps one small file per setting; these directories are tracked
# whole, so replacing them is safe.
rm -rf "$HOME/.config/cosmic/com.system76.CosmicComp/v1" \
    "$HOME/.config/cosmic/com.system76.CosmicSettings.Shortcuts/v1" \
    "$HOME/.config/cosmic/com.system76.CosmicAppletTime/v1" \
    "$HOME/.config/cosmic/com.system76.CosmicIdle/v1" \
    "$HOME/.config/cosmic/com.system76.CosmicPanel/v1" \
    "$HOME/.config/cosmic/com.system76.CosmicPanel.Panel/v1" \
    "$HOME/.config/cosmic/com.system76.CosmicPanel.Dock/v1" \
    "$HOME/.config/cosmic/com.system76.CosmicTheme.Dark/v2" \
    "$HOME/.config/cosmic/com.system76.CosmicTheme.Light/v2"
rm -f "$HOME/.config/cosmic/com.system76.CosmicBackground/v1/all"
stow --no-folding -d "$DOTFILES_DIR" -t "$HOME/.config" config
stow --no-folding -d "$DOTFILES_DIR" -t "$HOME" bash

echo "==> neovim config"
if [ -d "$HOME/.config/nvim/.git" ]; then
    git -C "$HOME/.config/nvim" pull --rebase --autostash || {
        echo "warning: nvim config diverged, skipped update" >&2
        git -C "$HOME/.config/nvim" rebase --abort 2>/dev/null || true
    }
elif [ ! -d "$HOME/.config/nvim" ]; then
    git clone https://github.com/nvim-lua/kickstart.nvim.git "$HOME/.config/nvim"
fi

echo "==> dev tools (mise)"
# ponytail: mise.run is upstream's recommended Linux install and keeps the
# binary when it is the same release or newer, so re-runs are a no-op.
curl -fsSL https://mise.run | sh
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
# node pinned at 22 to match the old nodejs22 package; the rest float.
mise use --global node@22 go hugo-extended bun rust starship@latest lazygit lazydocker
mise upgrade

echo "==> devvm"
# devvm upgrade is the supported update path and no-ops when current; the
# installer only runs on a machine where devvm is missing. --yes agrees to
# the Lima, QEMU and /dev/kvm setup its doctor asks for.
if command -v devvm >/dev/null 2>&1; then
    devvm upgrade --force
else
    curl -fsSL https://github.com/devvmhq/devvm/releases/latest/download/install.sh \
        | bash -s -- --yes
fi

echo "==> capture"
go install github.com/kobamkode/capture@latest

echo "==> opencode v2"
# ponytail: the upstream installer always re-downloads and rewrites the
# binary, so compare versions first and only install when missing or stale.
# Re-running bootstrap is the update path.
oc_latest=$(curl -fsSL https://opencode.ai/update/api/latest/cli/npm \
    | sed -n 's/.*"version":"\([^"]*\)".*/\1/p' | tr -d '\r')
oc_current=$("$HOME/.opencode/bin/opencode" --version 2>/dev/null || true)
oc_current="${oc_current##* }"
oc_current="${oc_current#v}"
if [ "$oc_latest" != "$oc_current" ]; then
    # --no-modify-path: PATH lives in the stowed ~/.bashrc.d.
    curl -fsSL https://opencode.ai/v2/install | bash -s -- --no-modify-path
fi

echo "==> pi"
# pi update is the supported update path and no-ops when current; the
# installer only runs on a machine where pi is missing.
if command -v pi >/dev/null 2>&1; then
    pi update --no-approve
else
    curl -fsSL https://pi.dev/install.sh | sh
fi

echo "==> beads (bd)"
# official installer: verifies release checksum, installs to ~/.local/bin
[ -x "$HOME/.local/bin/bd" ] || \
    curl -fsSL https://raw.githubusercontent.com/gastownhall/beads/main/scripts/install.sh | bash

echo "==> opencode plugins"
export PATH="$HOME/.opencode/bin:$PATH"
# V2: opencode plugin add installs into the global config; skip when the
# entry already exists so a re-run does not duplicate it.
grep -q '@dietrichgebert/ponytail' "$HOME/.config/opencode/opencode.json" 2>/dev/null || \
    opencode plugin add @dietrichgebert/ponytail
# caveman: upstream still ships the V1 plugin API, which does not run on
# OpenCode V2 (see https://opencode.ai/v2/docs/build/plugins/migrate-v1).
# The config entry is removed until upstream ships a V2 entrypoint
# ({ id, setup }) in src/plugins/opencode/. Re-add "./plugins/caveman" then.

echo "==> matt pocock skills (engineering + productivity)"
# ponytail: the lock file is written per-skill, so a half-failed add can leave
# gaps this guard skips. rm ~/.agents/.skill-lock.json to force a full re-add.
[ -f "$HOME/.agents/.skill-lock.json" ] || \
    npx skills add mattpocock/skills \
        --skill ask-matt --skill grill-with-docs --skill triage \
        --skill improve-codebase-architecture --skill setup-matt-pocock-skills \
        --skill to-spec --skill to-tickets --skill implement --skill implement-spec \
        --skill wayfinder --skill retro --skill prototype --skill diagnosing-bugs \
        --skill research --skill tdd --skill domain-modeling --skill codebase-design \
        --skill code-review --skill pr --skill wizard \
        --skill grill-me --skill handoff --skill teach --skill to-questionnaire \
        --skill wait-what --skill grilling --skill writing-for-agents \
        -g -y

echo "==> flatpak"
sudo flatpak remote-add --if-not-exists flathub \
    https://flathub.org/repo/flathub.flatpakrepo
flatpak install -y --noninteractive --or-update flathub io.github.CyberTimon.RapidRAW md.obsidian.Obsidian

echo "==> adding $(id -un) to docker group"
echo "done. re-login for bash and the docker group to take effect."
