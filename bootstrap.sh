#!/usr/bin/env bash
set -euo pipefail

# Bootstrap for a Fedora workstation. Sections rerun on their own — a config
# edit needs only `./bootstrap.sh dotfiles`, which takes seconds — but a
# section assumes the earlier ones ran on this machine at least once
# (tools before agents: agents need mise's node).
#
#   all       everything, in order (new machine)
#   packages  dnf/copr/flatpak installs, docker, login shell
#   dotfiles  stow links, neovim config
#   tools     mise tools, depsguard, capture, summarize
#   agents    pi and its packages, beads, skills

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# mise shims carry npm/cargo/go installed below; ~/go/bin carries `go install`
# binaries and ~/.local/bin the curl installers.
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$HOME/go/bin:$PATH"

packages() {
    sudo -v
    # keep the sudo timestamp alive for the whole run: a system upgrade plus the
    # package installs can outlast sudo's 5-minute window, which would otherwise
    # stall an unattended run at a password prompt. `sudo -n true` refreshes it.
    (
        while sudo -n true 2>/dev/null; do sleep 60; done
    ) &
    sudo_keepalive=$!
    trap 'kill "$sudo_keepalive" 2>/dev/null || true' EXIT

    echo "==> enabling copr repos"
    sudo dnf copr enable -y scottames/ghostty
    sudo dnf copr enable -y komapro/nerd-fonts

    echo "==> upgrading system"
    sudo dnf upgrade -y

    echo "==> installing packages"
    sudo dnf group install -y development-tools
    sudo dnf install -y \
        git gh neovim tmux ripgrep fd-find fzf bash-completion ghostty git-delta zoxide stow glances tealdeer
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

    echo "==> tailscale"
    # Fedora has no tailscale package; its own repo is the update path. Only the
    # daemon is installed here — `tailscale up` needs an interactive login.
    [ -f /etc/yum.repos.d/tailscale.repo ] || \
        sudo dnf config-manager addrepo --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
    sudo dnf install -y tailscale
    sudo systemctl enable --now tailscaled

    echo "==> login shell"
    [ "$(basename "$(getent passwd "$(id -un)" | cut -d: -f7)")" = bash ] || \
        sudo chsh -s "$(command -v bash)" "$(id -un)"

    echo "==> flatpak"
    sudo flatpak remote-add --if-not-exists flathub \
        https://flathub.org/repo/flathub.flatpakrepo
    flatpak install -y --noninteractive --or-update flathub io.github.CyberTimon.RapidRAW md.obsidian.Obsidian
}

dotfiles() {
    echo "==> git identity"
    # ponytail: seed only, never override. A repo or machine that already answers
    # for itself keeps its identity, and per-repo user.* still outranks these
    # globals. The literals live here because a fresh box cannot commit until an
    # identity exists and bootstrap never prompts; they are the same two values
    # every commit in this repo already carries.
    git config --global user.name >/dev/null || git config --global user.name "Mario Wibisono"
    git config --global user.email >/dev/null || git config --global user.email "kobamkode@gmail.com"

    echo "==> stow dotfiles"
    # ponytail: stow refuses to overwrite a real file, so drop every path this repo
    # tracks before linking. Deriving the list from git keeps it from drifting as
    # configs are added or removed, and leaves untracked neighbours alone (COSMIC
    # writes sibling settings in the same versioned directories).
    while IFS= read -r rel; do
        case $rel in
        config/*) target="$HOME/.config/${rel#config/}" ;;
        bash/*) target="$HOME/${rel#bash/}" ;;
        esac
        rm -f "$target"
    done < <(git -C "$DOTFILES_DIR" ls-files config bash)
    stow --no-folding -d "$DOTFILES_DIR" -t "$HOME/.config" config
    stow --no-folding -d "$DOTFILES_DIR" -t "$HOME" bash

    echo "==> neovim config"
    if [ -d "$HOME/.config/nvim/.git" ]; then
        git -C "$HOME/.config/nvim" pull --rebase --autostash || {
            echo "warning: nvim config diverged, skipped update" >&2
            git -C "$HOME/.config/nvim" rebase --abort 2>/dev/null || true
        }
    elif [ ! -d "$HOME/.config/nvim" ]; then
        git clone https://github.com/kobamkode/kickstart.nvim.git "$HOME/.config/nvim"
    fi
    echo "==> installing neovim plugins"
    nvim --headless '+qa'
}

tools() {
    echo "==> dev tools (mise)"
    # ponytail: mise.run is upstream's recommended Linux install and keeps the
    # binary when it is the same release or newer, so re-runs are a no-op.
    curl -fsSL https://mise.run | sh
    # node at 24: summarize (ytraw's dependency) requires >=24; the rest float.
    mise use --global node@24 go hugo-extended bun rust starship@latest lazygit lazydocker
    mise upgrade

    echo "==> depsguard"
    # Fedora has no package and the TUI cannot be scripted, so this only installs
    # the binary; run `depsguard` to apply fixes. crates.io is the update path, so
    # rebuild only when a newer version is published. The URL is the sparse index
    # layout: first two and next two characters of the crate name.
    dg_latest=$(curl -fsSL https://index.crates.io/de/ps/depsguard \
        | sed -n 's/.*"vers":"\([^"]*\)".*/\1/p' | tail -1)
    # ponytail: test -x before running depsguard. With set -o pipefail, a
    # missing binary here makes the pipeline (and so this assignment) exit 127,
    # which set -e turns into a silent abort of the whole run — case and capture
    # below would never install.
    dg_current=
    if [ -x "$HOME/.cargo/bin/depsguard" ]; then
        dg_current=$("$HOME/.cargo/bin/depsguard" --version | awk '{print $2}')
    fi
    if [ -z "$dg_current" ] || [ "$dg_latest" != "$dg_current" ]; then
        cargo install --locked depsguard
    fi

    echo "==> capture"
    go install github.com/kobamkode/capture@latest

    echo "==> summarize (ytraw)"
    # ytraw in .bashrc.d/20-aliases.sh shells out to summarize; npm global is the
    # upstream install and update path, and the prebuilt bin lands on the mise shim.
    npm install -g @steipete/summarize
}

agents() {
    echo "==> pi"
    # pi update is the supported update path and no-ops when current; the
    # installer only runs on a machine where pi is missing. The installer has no
    # --yes flag and reads its action menu and "Start pi now?" prompt straight
    # from /dev/tty, so run it under setsid: stdin is the curl pipe and the new
    # session has no controlling terminal, which makes it take the unattended
    # defaults (its node/npm prompt is moot because mise installed node above).
    if command -v pi >/dev/null 2>&1; then
        pi update --no-approve
    else
        # ponytail: a dead ~/.local/bin/pi link (what an interrupted earlier run
        # leaves behind) makes the installer install to ~/.pi/agent/bin instead
        # and exit 0 saying "installed successfully", but PATH still resolves to
        # the broken link, so every pi step below fails. Clear the link first so
        # the installer owns that path again, and verify rather than trust.
        if [ -L "$HOME/.local/bin/pi" ] && [ ! -e "$HOME/.local/bin/pi" ]; then
            rm -f "$HOME/.local/bin/pi"
        fi
        curl -fsSL https://pi.dev/install.sh | setsid sh
        command -v pi >/dev/null 2>&1 || {
            echo "pi installer finished but pi is not on PATH" >&2
            echo "check $HOME/.local/bin/pi and $HOME/.pi/agent/bin/pi" >&2
            exit 1
        }
    fi

    echo "==> ponytail (pi package)"
    # ponytail ships a pi extension plus its six skills, and `pi install` is also
    # the update path: re-running refreshes the clone and no-ops when current.
    # --no-approve keeps a project-local .pi/settings.json from being trusted here.
    pi install git:github.com/DietrichGebert/ponytail --no-approve

    echo "==> caveman (pi extension + voice skills)"
    # npm global install is also the update path, and `caveman enable pi` no-ops
    # once the native extension is wired. Both target pi only.
    npm install -g @caveman-ai/cli
    # ponytail: `enable pi` exits non-zero while ~/.caveman/bin is empty, which
    # `set -e` would turn into the whole agents section dying before the skills,
    # so fetch the binaries (checksum-verified, no-op once current) first.
    caveman setup --install
    caveman enable pi

    echo "==> beads (bd)"
    # official installer: verifies release checksum, installs to ~/.local/bin
    [ -x "$HOME/.local/bin/bd" ] || \
        curl -fsSL https://raw.githubusercontent.com/gastownhall/beads/main/scripts/install.sh | bash

    echo "==> beads viewer (bv)"
    # bv --update is the supported update path, verifies the release checksum, and
    # no-ops when current. install.sh only runs where bv is missing; pinned to a
    # reviewed commit because curl|bash runs whatever that URL serves, and it
    # installs into ~/.local/bin.
    if [ -x "$HOME/.local/bin/bv" ]; then
        "$HOME/.local/bin/bv" --update --yes
    else
        curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/beads_viewer/9f7d0b703d845f2c050e6fdcd68887414e2b1a3f/install.sh" | bash
    fi

    echo "==> matt pocock skills (engineering + productivity)"
    # ponytail: run every time so skills added to this list below reach machines
    # that already have a lock file; `add` is idempotent. npx -y also skips its own
    # "install skills?" prompt, which would otherwise block an unattended run.
    # -a pi keeps the skills pi-only: no links are written into other harnesses.
    npx -y skills@latest add mattpocock/skills \
        --skill ask-matt --skill grill-with-docs --skill triage \
        --skill improve-codebase-architecture --skill setup-matt-pocock-skills \
        --skill to-spec --skill to-tickets --skill implement --skill implement-spec \
        --skill wayfinder --skill retro --skill prototype --skill diagnosing-bugs \
        --skill research --skill tdd --skill domain-modeling --skill codebase-design \
        --skill code-review --skill pr --skill wizard \
        --skill grill-me --skill handoff --skill teach --skill to-questionnaire \
        --skill wait-what --skill grilling --skill writing-for-agents \
        -g -a pi -y

    echo "==> josjis skill (grill-to-PR chain)"
    # ponytail: josjis only chains the matt pocock skills above, so it installs
    # after them and adds no dependency of its own. Same idempotent `add` path.
    npx -y skills@latest add kobamkode/kobamkode-skill \
        --skill josjis \
        -g -a pi -y
}

main() {
    if [[ $EUID -eq 0 ]]; then
        echo "Run as a regular user, not root." >&2
        exit 1
    fi

    # repos live under ~/dev (aliases and vault paths assume it). capture
    # refuses a missing vault or a missing CAPTURE_DAILY_DIR and never creates
    # either, so both get made on every run, whichever section was asked for.
    mkdir -p "$HOME/dev" "$HOME/vaults/journal/daily"

    case ${1:-all} in
    all)
        packages
        dotfiles
        tools
        agents
        echo "done. re-login for bash and the docker group to take effect."
        ;;
    packages | dotfiles | tools | agents) "$1" ;;
    *)
        echo "usage: $(basename "$0") [all|packages|dotfiles|tools|agents]" >&2
        exit 2
        ;;
    esac
}

main "$@"
