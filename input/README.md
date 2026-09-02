# Клавиатура в Linux Mode

В Linux Mode проект включает только Linux-профиль фокуса: обычная аппаратная
клавиатура должна быть направлена в сфокусированную Android Activity
Termux:X11, откуда событие попадает во внешний X11-транспорт и далее в
Wayland/Mutter/GNOME. В `fedora-session` этот профиль передаётся как
`FEDORA_KEYBOARD_MODE=linux`; при наличии гостевого каталога XKB задаётся
только Fedora-переменная `XKB_CONFIG_ROOT=/usr/share/X11/xkb`.

Это не глобальный перехват Android. Публичный Android SDK позволяет обычной
Activity получать key events, когда она сфокусирована, но не даёт ей права
украсть защищённые сочетания у SystemUI или переназначить Home, Back, громкость,
шторку уведомлений, скриншоты или DeX. Поэтому Android Mode не меняется, а
системные клавиши остаются Android-owned.

Практика на планшете:

1. Откройте совместимый Termux:X11 и оставьте его Activity видимой.
2. Тапните по поверхности Fedora перед вводом сочетания.
3. Для нижнего свайпа Home/Overview и Back выключите в Termux:X11
   `Fullscreen on device display`; проект эту настройку не записывает.
4. Диагностика без изменений Android:

   ```bash
   bash "$HOME/.local/share/fedora-shell/input/keyboard-mode.sh" status --read-preferences
   bash "$HOME/.local/share/fedora-shell/input/keyboard-mode.sh" guide
   ```

`termux-x11-preference list` вызывается только с явным `--read-preferences` и
только для чтения. Проект не меняет `termux.properties`, Termux:X11
preferences, IME, Accessibility, overlay или Android keymap.

Источники:

- [Android input events](https://developer.android.com/develop/ui/views/touch-and-input/input-events)
- [Android keyboard commands](https://developer.android.com/develop/ui/views/touch-and-input/keyboard-input/commands)
- [Android `KeyEvent`](https://developer.android.com/reference/android/view/KeyEvent)
- [Android window focus flags](https://developer.android.com/reference/android/view/WindowManager.LayoutParams)
- [официальный Termux:X11](https://github.com/termux/termux-x11)
- [официальная документация Termux](https://github.com/termux/termux-tools/blob/master/doc/termux.1.md.in)
