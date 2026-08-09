# deployLinux

Root/system layer for my machines: install runbooks, portage and kernel
config, and idempotent provisioning scripts. One target per machine type,
everything on this single main branch.

## Bootstrapping a new machine

Three guides take a blank disk to the full environment:

1. [Install the OS](docs/install-os.md) — the shortest possible base
   install, Gentoo or Arch, one command per step.
2. [Bootstrap Gentoo](docs/bootstrap-gentoo.md) — the primary path:
   profiles, provisioning scripts, kernel policy, yadm, first-boot checks.
3. [Bootstrap Arch](docs/bootstrap-arch.md) — the alternative path:
   one hardware-detecting script, then the same yadm handoff.

## Targets

| target | machine | entry point |
| :--- | :--- | :--- |
| [gentoo](targets/gentoo/) | the Gentoo fleet — profiles: `pc` (9800X3D / RTX 5080 desktop, binhost server) and `x13` (ThinkPad X13 Gen4 AMD, binhost client) | [guide](docs/bootstrap-gentoo.md), `runbook.md`, `provision.sh --profile <name> --hostname localhost` |
| [arch](targets/arch/) | generic Arch for either machine (alternative OS, hardware auto-detected) | [guide](docs/bootstrap-arch.md), `bootstrap.sh` |
| [server](targets/server/) | generic homelab servers, terminal only | `bootstrap.sh` |
| [wsl2-arch](targets/wsl2-arch/) | Arch inside WSL2, shell only | `bootstrap.sh` |

The gentoo target is profile-driven: shared scripts plus hardware
detection, machine specifics live in `targets/gentoo/profiles/<name>/`.
Adding a Gentoo machine means adding a profile directory, not scripts.
keyd swaps Caps Lock and Escape on every machine.

## Relationship to the rice repo

This repo is the **system layer** (root-owned files, packages, services).
The **user layer** — dotfiles, desktop configs — lives in
[rice](https://github.com/0n3W4y7ick3t/rice) and is deployed with yadm.
Machines are told apart by yadm classes, never by hostname: hostnames may
all be `localhost`.

## Vendored assets

`common/` deliberately vendors things that should not depend on the
network at install time: a rEFInd bootloader tree, FiraCode Nerd fonts,
and small misc configs. `common/lib.sh` is the shared shell library the
scripts source, `common/detect.sh` detects the hardware (GPU, CPU vendor,
chassis, bluetooth, wifi — `sh common/detect.sh --report`), and
`common/keyd-default.conf` is the fleet-wide key remap.

## Branch history

Old per-machine branches (`arch`, `gentoo-x13`, `gentoo-g7`) are retired;
their useful content was migrated into `targets/` on main. The desktop is
Hyprland-only now, the dwm/st/dmenu era is over.
