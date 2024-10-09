# input methods (fcitx)
Works with all applicants, tested under gentoo X11

## Why fcitx

I tested ibus but that doesn't work with chrome.

## Install
```
# gentoo, anthy for Japanese and rime for Chinese
# see [gentoo wiki](https://wiki.gentoo.org/wiki/Fcitx) for other languages
emerge -av fcitx-configtool fcitx-rime fcitx-anthy fcitx-chinese-addons

```

## Settings
```
# IMPORTANT: add next line if you don't use systemd, [source](https://fcitx-im.org/wiki/Setup_Fcitx_5)
eval "$(dbus-launch --sh-syntax --exit-with-session)"
fcitx5 & # or fcitx
export XMODIFIERS="@im=fcitx"
export QT_IM_MODULE=fcitx
export GTK_IM_MODULE=fcitx

```
