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
sudo dnf group install -y "Development Tools"
sudo dnf install -y \
    git gh neovim tmux ripgrep fd-find fzf ghostty lazygit zoxide
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
# updates it — re-running bootstrap is the update path. Fix this URL if
# DBeaver renames the `-latest-` file scheme on their CDN.
sudo dnf install -y https://dbeaver.io/files/dbeaver-ce-latest-linux-x86_64.rpm

echo "==> docker"
[ -f /etc/yum.repos.d/docker-ce.repo ] || \
    sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
echo "==> adding $(id -un) to docker group"
sudo usermod -aG docker "$(id -un)"

echo "==> neovim config"
[ -d "$HOME/.config/nvim" ] || \
    git clone https://github.com/nvim-lua/kickstart.nvim.git "$HOME/.config/nvim"

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

echo "done. re-login for the docker group to take effect."