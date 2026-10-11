# dotfiles

Personal layer on top of [Omarchy](https://omarchy.org), managed with [chezmoi](https://chezmoi.io).
Used both on an Omarchy host and inside devpods.

- **Omarchy host**: only my changes on top of Omarchy defaults (keybindings, input, tmux, nvim, git, ...).
- **Devpod / container**: portable subset (nvim, bash, git, mise); tmux and vi stay stock to mirror servers.

The target is detected automatically (`.chezmoi.toml.tmpl`: `omarchy`, `container`).
