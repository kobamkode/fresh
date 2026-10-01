#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
    echo "Run as a regular user, not root." >&2
    exit 1
fi

sudo -v

echo "==> enabling copr repos"
sudo dnf copr enable -y scottames/ghostty
sudo dnf copr enable -y dejan/lazygit
sudo dnf copr enable -y komapro/nerd-fonts

echo "==> upgrading system"
sudo dnf upgrade -y

echo "==> installing packages"
sudo dnf group install -y development-tools
sudo dnf install -y \
    git gh neovim tmux ripgrep fd-find fzf ghostty lazygit zoxide stow
grep -q 'zoxide init' "$HOME/.bashrc" || \
    echo 'eval "$(zoxide init bash --cmd cd)"' >> "$HOME/.bashrc"
grep -q 'fzf/shell/key-bindings.bash' "$HOME/.bashrc" || \
    echo '[ -f /usr/share/fzf/shell/key-bindings.bash ] && source /usr/share/fzf/shell/key-bindings.bash' >> "$HOME/.bashrc"
grep -q 'alias wm=' "$HOME/.bashrc" || \
    cat >> "$HOME/.bashrc" <<'EOF'
alias wm="workmux"
alias ll="ls -al --color=auto"
alias tks="tmux kill-server"
alias t="tmux"
alias ta="tmux a"
alias lg="lazygit"
alias ld="lazydocker"
alias update="sudo dnf -y update && flatpak -y update"
export EDITOR=nvim
EOF
sudo dnf install -y nodejs22 nodejs22-npm || \
    sudo dnf install -y nodejs npm
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

echo "==> stow dotfiles"
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# ponytail: stow refuses to overwrite a real file, so drop any pre-existing
# copy of a config we own before linking. Back these up yourself if you keep
# local edits in $HOME.
rm -f "$HOME/.config/tmux/tmux.conf" "$HOME/.config/ghostty/config.ghostty"
stow --no-folding -d "$DOTFILES_DIR" -t "$HOME/.config" config

echo "==> neovim config"
if [ -d "$HOME/.config/nvim/.git" ]; then
    git -C "$HOME/.config/nvim" pull --ff-only
elif [ ! -d "$HOME/.config/nvim" ]; then
    git clone https://github.com/nvim-lua/kickstart.nvim.git "$HOME/.config/nvim"
fi

echo "==> rust"
if [ -x "$HOME/.cargo/bin/cargo" ]; then
    "$HOME/.cargo/bin/rustup" update || true
else
    curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path
fi
grep -q '.cargo/env' "$HOME/.bashrc" || \
    echo '. "$HOME/.cargo/env"' >> "$HOME/.bashrc"

echo "==> opencode"
curl -fsSL https://opencode.ai/install | bash

echo "==> workmux"
[ -x "$HOME/.local/bin/workmux" ] || \
    curl -fsSL https://raw.githubusercontent.com/raine/workmux/main/scripts/install.sh | bash

echo "==> opencode plugins"
export PATH="$HOME/.opencode/bin:$PATH"
opencode plugin -g @dietrichgebert/ponytail
curl -fsSL https://raw.githubusercontent.com/JuliusBrussee/caveman/main/install.sh \
    | bash -s -- --only opencode --non-interactive

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
echo "done. re-login for the docker group to take effect."
