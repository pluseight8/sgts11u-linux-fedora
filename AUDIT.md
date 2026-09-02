# Полный аудит Fedora Shell

Дата среза: **2026-09-02**.

Документ описывает проверяемое состояние рабочей копии проекта и границы того,
что можно сделать на обычном Android без root. Изменения в этом репозитории не
считаются установленными на планшете, пока control tree не скопирован на него и
не выполнен повторный acceptance-тест.

## Итог

Установка Fedora в предоставленных журналах завершалась успешно. Чёрный экран
возникает позже, на этапе nested display: GNOME Shell создаёт Wayland-сессию,
но GTK Devkit viewer завершается, после чего supervisor правильно прекращает
сессию как невидимую. Это не ошибка скачивания Fedora-пакетов.

В старой схеме был опасный fallback с прямым запуском `mutter-devkit`. По
официальному коду Mutter standalone viewer получает launch environment от
уже запущенного compositor-owned объекта `org.gnome.Mutter.Devkit`; сам по себе
он это окружение создать не может. Исправленная схема сохраняет RPM binary,
устанавливает Fedora-only shim только внутри гостя, ждёт официальный D-Bus
объект/`Env`, задаёт viewer backend `x11` для внешнего Termux:X11 и затем
передаёт управление исходному binary. GNOME Shell при этом остаётся Wayland
композитором; Android не участвует в этой подмене.

Критичная граница: рабочая копия сейчас подготовлена и проверена статически,
но APK не собран и изменения не опубликованы в удалённый Git из этой среды.
Поэтому старый `git pull` на планшете не получит эти правки автоматически.

## Данные целевого устройства

Из журналов владельца подтверждены:

| Параметр | Наблюдение |
| --- | --- |
| Модель | Samsung `SM-X930` |
| Android | 16 / API 36 |
| Архитектура | `aarch64` |
| Платформа | codename `gts11uwifi`, board/SoC `MT6991` |
| Kernel | `6.6.102-android15-8-abogkiX930XXU5BZE3-4k` |
| RAM | `11788036 KiB`, то есть примерно 12 GiB |
| Fedora | `fedora:44`, ARM64 |
| GNOME/Mutter | 50.4 |
| Termux:X11 | `1.03.01-6` |

Аппаратное ускорение, S Pen pressure/tilt, реальная частота панели, SELinux и
доступность Android API из конкретной прошивки нельзя считать подтверждёнными
по одному установочному выводу. Их нужно измерять на планшете redacted-отчётом.

## Что исправлено

### Display и чёрный экран

* убран standalone fallback, который не может создать официальный Devkit
  launch environment;
* добавлен ограниченный ожиданием shim на точном Fedora-пути
  `/usr/libexec/mutter-devkit`;
* оригинальный binary сохраняется с owner marker и восстанавливается перед
  `dnf`, после обновления устанавливается shim заново;
* backend viewer явно разделён с backend GNOME Shell: viewer использует
  внешний X11 surface, Shell — Wayland;
* включены проверки живого процесса, zombie-процесса, Wayland socket и
  видимого viewer; ложный успешный запуск больше не объявляется готовым;
* stale runtime-сокеты и Fedora session state обрабатываются только внутри
  project-owned runtime directory;
* при повторном запуске уже активной сессии не создаётся вторая копия PRoot.

### D-Bus, portals и необязательные сервисы

* для Fedora/PRoot используется отдельный private session bus;
* `DBUS_SYSTEM_BUS_ADDRESS` не подменяется session bus-ом;
* при недоступном `/dev/fuse` portals не запускаются автоматически;
* фильтруется только Fedora-owned activation catalog: Android D-Bus и
  Android SystemUI не затрагиваются;
* отключение portal не создаёт фальшивых service-файлов `org.freedesktop.*`;
* calendar/search/keyring/audio helpers в low-профиле не запускаются без
  необходимости.

### Безопасность файлового control plane

* state, PID, log и request/response-файлы пишутся атомарно;
* запросы Android bridge являются данными, а не shell-кодом: они не
  `source`-ятся;
* добавлены проверки абсолютных путей, dot-компонентов, symlink и безопасного
  родителя;
* destructive host operations ограничены дочерними каталогами Termux home и
  не могут целиться в checkout;
* копирование проекта и guest integration не принимает symlink как source;
* broker имеет bounded polling, bounded response и cleanup только собственных
  файлов.

## Android-приложения в Fedora

Полностью встроить произвольную Android Activity как Wayland window внутрь
Mutter без системного compositor/Android framework API нельзя. Реализованный
и честно обозначенный вариант — foreground hand-off:

```text
GNOME desktop entry
  → Fedora Android bridge
  → Android PackageManager/launcher через узкий validated request
  → Android Activity / SurfaceFlinger поверх Termux:X11 Activity
  → Back/переход назад возвращает предыдущую Android surface
```

Bridge поддерживает:

* read-only список пользовательских (`-3`) пакетов и launchable activities;
* динамические Fedora `.desktop` entries с точной проверкой package name;
* запуск выбранного пакета через `am`, когда Android разрешает запуск;
* foreground fallback через URI контроллера Fedora Shell, если Android 16
  отклоняет background shell start;
* private shared-tmp broker, когда PRoot не видит `/system/bin/am`;
* статический allowlist для фиксированных intent actions.

Bridge намеренно не умеет устанавливать/удалять APK, менять default Home,
менять AppOps, останавливать пакеты, читать чужие private app data или
поднимать network listener. При невозможности безопасно получить каталог
предыдущие entries сохраняются.

### Home и Android UI

Android controller является только кандидатом `ROLE_HOME`; выбор Fedora Shell
делает пользователь системным экраном Android. One UI Home остаётся
установленным и не отключается. Автовозобновление выключено по умолчанию.

Контроллер скрывает только постоянную status bar в своей Activity и использует
transient-bars-by-swipe. Нижняя gesture/navigation область сохраняется. Volume
panel, notification shade, Back/Home и другие защищённые поверхности принадлежат
Android SystemUI: обычное приложение не может и не должно их блокировать.
Termux:X11 должен быть настроен пользователем без fullscreen-настройки, если
нужны нижний свайп и штатные кнопки Android.

### Клавиатура

Для Linux Mode добавлен отдельный Linux-only профиль фокуса
`FEDORA_KEYBOARD_MODE=linux`. Он не является Android hook: обычная клавиша
попадает в сфокусированную Activity Termux:X11, затем во внешний транспорт и
Wayland/Mutter/GNOME. Контроллер не регистрирует Accessibility/IME/overlay и не
пишет Android preferences. Android Mode не затрагивается.

Ограничение принципиальное: Home/Back, громкость, уведомления, скриншоты, DeX
и другие защищённые глобальные сочетания могут оставаться у SystemUI. Публичный
SDK обычного приложения не даёт права глобально украсть и переназначить их.
Проверка выполняется скриптом `input/keyboard-mode.sh status`; полный вводной
гайд находится в [input/README.md](input/README.md).

## Память и RAM Plus

Для 12 GiB автоматически выбирается Fedora low-профиль, но это оптимизация
Fedora/Termux userspace, а не Android RAM cleaner. Он:

* не меняет LMKD, memcg, zRAM, kernel parameters, Android settings или
  Samsung packages;
* не делает `kill -9`, `pkill`, `killall` и не трогает Android critical
  processes;
* выключает Fedora search indexing и необязательные idle helpers;
* запускает минимальный PipeWire display transport без полной аудио-цепочки,
  когда audio выключен;
* уменьшает virtual nested monitor и allocator fragmentation;
* по умолчанию отключает inner Xwayland в low-профиле, оставляя внешний
  Termux:X11 transport;
* измеряет `MemAvailable`, Android/Fedora RSS/PSS, PSI, major faults и swap/
  zRAM counters там, где unprivileged API их раскрывает.

Android остаётся владельцем общей физической памяти. `RAM Plus` — настройка
Samsung/Android, поэтому проект её не включает, не меняет размер и не
пытается выдавать `/proc/swaps` за точное состояние этой функции. Доступные
счётчики показываются как косвенное наблюдение. Page cache и свободная RAM не
интерпретируются как единственная цель; важнее отсутствие thrashing,
перезапусков приложений и рывков GNOME.

Профили `balanced`, `linux-focused` и `maximum-linux` меняют только Fedora
параметры и интенсивность read-only отчёта. Каталог Android-приложений по
умолчанию использует scope `all` и показывает launchable system/user packages;
`FEDORA_ANDROID_APPS_SCOPE=user` возвращает third-party-only режим. Это область
перечисления, а не allowlist для безусловного force-stop или package disable.
Файл allowlist Android остаётся только метаданными отчёта. Это намеренно
соответствует требованию «не модифицировать Android».

Deep sleep остаётся ручным действием в штатном Samsung UI. Fedora Shell может
открыть опубликованный Samsung список, но не выбирает приложения и не меняет
AppOps/background policy: [официальная справка Samsung о Sleeping/Deep sleeping
apps](https://www.samsung.com/us/support/answer/ANS10003442/).

## Состояние проверок

В рабочей копии выполнены:

```text
bash tests/static.sh                 PASS
bash tests/android-bridge.sh        PASS
bash -n по всем *.sh                 PASS
XML manifest validation              PASS (если xmllint установлен)
JSON allowlist validation             PASS (если jq установлен)
```

Также проверены отрицательные сценарии: отказ Android background start не
маскируется под успех, ошибка resolver не переключается на ложный URI fallback,
symlinked request/desktop/state paths отклоняются, повторный broker не
запускается, а старые Android desktop entries не удаляются при неудачном
refresh.

Не выполнено в этой среде:

* визуальный acceptance-тест на SM-X930 после установки новой рабочей копии;
* сборка APK — отсутствуют Android SDK, JDK и Gradle;
* подтверждение аппаратного GPU, S Pen, аудио, RAM Plus UI и Android API 36
  behavior на конкретной прошивке;
* публикация изменений в Git remote — локальная копия не содержит `.git`.

## Рекомендуемый acceptance-тест на планшете

После доставки этой рабочей копии на устройство:

1. открыть совместимый Termux:X11 APK вручную;
2. выполнить `bash scripts/install.sh --yes --memory-profile low`;
3. запустить Fedora с `FEDORA_GPU_MODE=software`, сначала без portals/audio;
4. проверить, что виден GNOME и `echo "$XDG_SESSION_TYPE"` даёт `wayland`;
5. открыть Android application через динамический Fedora entry и нажать Back;
6. проверить нижний свайп, Volume, notification shade и возврат в Android;
7. выполнить `bash scripts/diagnostics.sh --full --redact --frame-pacing`;
8. только после успешного low-профиля отдельно сравнить balanced.

Если viewer снова исчезает, следующий шаг — приложить redacted
`fedora-session.log` и diagnostics; не следует расширять права Android или
включать случайные system settings.

## Только официальные источники

* [Android: Memory management overview](https://developer.android.com/topic/performance/memory-management)
* [Android: System-wide memory management](https://developer.android.com/topic/performance/memory/guide/system-wide-memory)
* [Android: Reclaiming memory](https://developer.android.com/topic/performance/memory/guide/reclaim)
* [Android: Memory management concepts](https://developer.android.com/topic/performance/memory/guide/concepts)
* [Android: Background activity launch security](https://developer.android.com/guide/components/activities/secure-bal)
* [Android: Storage Access Framework](https://developer.android.com/guide/topics/providers/document-provider)
* [Samsung: RAM Plus](https://www.samsung.com/sg/support/mobile-devices/what-is-ram-plus-and-how-to-use-it/)
* [Samsung: Sleeping apps / Deep sleeping apps](https://www.samsung.com/us/support/answer/ANS10003442/)
* [GNOME Mutter: building and running](https://github.com/GNOME/mutter/blob/main/doc/building-and-running.md)
* [GNOME 50 developer notes](https://release.gnome.org/50/developers/index.html)
* [PRoot-Distro official repository](https://github.com/termux/proot-distro)
* [Termux:X11 official repository](https://github.com/termux/termux-x11)

Неподтверждённые research candidates и непервичные обсуждения не используются
как основание для production-решений.
