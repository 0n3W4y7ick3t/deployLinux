# input methods (fcitx5, wayland)

Chinese and Japanese under Hyprland. ibus is not used anywhere here — it
does not work with Chrome.

## Packages

All in the `@hyprland` set (`targets/gentoo/portage/sets/hyprland`), so
`20-world.sh` installs them:

| package | for |
| :--- | :--- |
| `app-i18n/fcitx:5` | the daemon |
| `app-i18n/fcitx-chinese-addons` | Chinese (pinyin) |
| `app-i18n/mozc` | Japanese — needs USE `fcitx5`, **not** `ibus` |
| `app-i18n/fcitx-gtk`, `fcitx-qt` | toolkit IM modules |
| `app-i18n/fcitx-configtool` | the settings GUI |

`media-fonts/noto-cjk` is in the base world list. Without it Japanese
renders as tofu — `wqy-microhei` only covers Chinese.

`L10N="en zh ja"` in `make.conf.shared` builds the matching locale data,
and `/etc/locale.gen` needs `ja_JP.UTF-8 UTF-8` alongside the others.

## Environment

Owned by the **rice** repo (`.config/shell/profile`), not this one —
Hyprland is exec'd from the login shell on tty1, so it inherits it:

```
export XMODIFIERS=@im=fcitx
```

That is the only variable set, deliberately. Wayland-native clients use
the `text-input-v3`
protocol and go through fcitx5 without any environment variable;
forcing `GTK_IM_MODULE=fcitx` or `QT_IM_MODULE=fcitx` makes GTK4 and
Qt6 apps take the X11 path instead and is a common cause of "the popup
does not follow the cursor". `XMODIFIERS` is still needed because
XWayland clients have no other way to find the IM.

The X11-era `eval "$(dbus-launch --sh-syntax --exit-with-session)"` is
not needed: elogind provides the session bus.

## Autostart

fcitx5 has to be started by the compositor — Hyprland does not read
`/etc/xdg/autostart`. Already in the **rice** repo's `hyprland.conf`:

```
exec-once = fcitx5 -d
```

Verify after login: `fcitx5-diagnose | head -40`, then Ctrl+Space to
switch engines. `fcitx5-configtool` adds Pinyin and Mozc to the input
method list — they are installed but not enabled by default.
