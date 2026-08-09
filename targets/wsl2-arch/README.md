# wsl2-arch

Shell-only Arch Linux inside WSL2. No GUI, no display server, no system
provisioning beyond packages — Windows owns the kernel and the desktop.

Run `./bootstrap.sh` to install the CLI package set from `pkg.txt`, build
yay from the AUR, and print the yadm commands for the user layer
(class `wsl` in the [rice](https://github.com/0n3W4y7ick3t/rice) repo).
The yadm clone is done manually, the script only echoes the steps.

Hostname (optional): the fleet convention is `localhost` everywhere,
machines are told apart by yadm class. On WSL2 that means editing
`/etc/wsl.conf` by hand:

```ini
[network]
hostname = localhost
```

