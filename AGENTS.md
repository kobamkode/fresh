# fresh

Fedora workstation provisioning, in one repo: `bootstrap.sh` installs packages,
tools and agent packages, then stows `bash/` and `config/` into `$HOME`.
Fedora-only (dnf, copr, flatpak); no other distro is supported or tested.

## How to run

```sh
./bootstrap.sh            # all sections, ~20 min, safe to re-run
./bootstrap.sh dotfiles   # just stow + nvim, seconds
```

Sections: `packages` (dnf/copr/flatpak, docker, tailscale, login shell),
`dotfiles` (stow, nvim), `tools` (mise, depsguard, capture, summarize), `agents`
(pi, ponytail, caveman, beads, skills). A section assumes the earlier ones ran
on this machine at least once — `agents` needs the node that `tools` installs.

Check shell edits before running anything:

```sh
bash -n bootstrap.sh bash/.bashrc.d/*.sh
```

## Rules that keep re-runs working

- **Every step must no-op when already current, and never prompt.** Guard with
  a version compare (depsguard, dbeaver) or `command -v`/`-x`; prefer the
  upstream update path (`pi update`, `mise use --global`, `npm install -g`)
  over blind reinstall. The run is unattended after `sudo -v`, which is why
  sudo's timestamp is kept alive for the whole run.
- **Install what tracked config calls.** If `bash/.bashrc.d/*` or a stowed
  config invokes a binary, bootstrap must install it (`ytraw` → `summarize`).
- **Agent packages are pi-only.** Skills use `npx … -a pi`; never the
  all-harness default, which symlinks into every detected agent directory.
- **Stow can't overwrite a real file.** `--no-folding` links one file per
  tracked file, so the stow step deletes every path `git ls-files` reports under
  `config/` and `bash/` first. That list is derived, never hand-maintained, and
  it leaves untracked siblings alone (COSMIC writes other settings inside the
  same versioned directories).
- **Keep the `# ponytail:` comments.** Each one records why a non-obvious
  decision exists; they are documentation, not leftovers.
- **Track inputs, not derived output.** `config/cosmic` holds what was chosen by
  hand (panel layout, shortcuts, comp, background, time/idle, theme `accent`).
  The rest of `CosmicTheme.*/v2` is recomputed by COSMIC from `accent`, so
  snapshotting it only adds ~40 files of churn and values that go stale when
  COSMIC changes its derivation.
- **Nothing identity- or secret-shaped gets tracked** (`.gitconfig`, `.ssh`,
  API keys); `$HOME` config is the machine's, not the repo's.

## Layout

- `bootstrap.sh` — the whole install, in run order. Steps print `==> name`.
- `bash/.bashrc.d/` — stowed to `~/.bashrc.d/`, sourced in filename order:
  `00-env` (env vars, PATH), `10-options` (interactive-only shell options),
  `20-aliases` (aliases, `update`, `ytraw`), `30-tools` (mise/starship/zoxide,
  tmux auto-attach).
- `config/{ghostty,tmux,cosmic}/` — stowed to `~/.config`.
