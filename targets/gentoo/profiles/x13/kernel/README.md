# x13 kernel

Hardware: ThinkPad X13 Gen4 AMD — Ryzen 7040-series CPU with integrated
Radeon graphics (amdgpu), Qualcomm/MediaTek wifi + Bluetooth, NVMe.
`config-6.11.6` is the known-good config currently running on the laptop
(bluetooth, wifi, amdgpu, docker, wireguard all enabled).

## Migrating to a newer kernel

```
cp config-6.11.6 /usr/src/linux/.config
cd /usr/src/linux
make olddefconfig    # accept defaults for new options
make menuconfig      # review anything olddefconfig picked
```

## Verify after olddefconfig

- `CONFIG_DRM_AMDGPU=m` — display
- container options: `NAMESPACES`, `CGROUPS`, `OVERLAY_FS`, netfilter
  (docker is already in world)
- `CONFIG_WIREGUARD`, `CONFIG_TUN` — VPNs
- `CONFIG_INPUT_UINPUT` — wayland tools (wtype, keyd) need it
- keep `SWAP` and the `I2C` modules enabled
