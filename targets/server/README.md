# server

Generic terminal-only setup for homelab servers. Distro-agnostic:
`bootstrap.sh` detects pacman, apt or emerge and installs the core CLI
set (zsh, neovim, tmux, git, fzf, ripgrep, fd, lf, bat, curl) plus yadm.

It does not touch GUI packages, services, storage or networking — system
provisioning stays with whatever manages the box. The user layer comes
from the [rice](https://github.com/0n3W4y7ick3t/rice) repo via yadm with
class `server` and a sparse checkout; the script prints those commands
instead of running them.
