# go2rtc для Android

Готовые сборки [go2rtc](https://github.com/AlexxIT/go2rtc) для Android 7+ — Termux и KSWEB. Код go2rtc берётся из оригинала по тегу релиза, без изменений, кроме патчей из [`patches/`](patches). Собирает GitHub Actions; сборки — в [Releases](../../releases).

## Зачем, если у go2rtc есть `go2rtc_linux_arm64`

Релизная сборка рассчитана на обычный Linux. На Android у неё три проблемы:

1. **Не запускается через системный загрузчик.** Это статический исполняемый файл (не PIE), сжатый UPX. Termux на новых Android и KSWEB запускают программы через `/system/bin/linker64`, а он принимает только PIE: `unexpected e_type: 2`.
2. **Не работает DNS.** Сборка без cgo ищет `/etc/resolv.conf`, которого на Android нет, — удалённые потоки по имени хоста не открываются.
3. **Не работает WebRTC.** С Android 11 запрос списка сетевых интерфейсов запрещён (`netlinkrib: permission denied`), go2rtc не знает свой IP. Обход есть в библиотеке [wlynxg/anet](https://github.com/wlynxg/anet), но только в сборке под Android с cgo.

Здесь: `GOOS=android`, `CGO_ENABLED=1`, Android NDK, API 24 — PIE на системных библиотеках Android, поиск адресов через систему.

## Файлы релиза

| Файл | Архитектура Android | Где встречается |
|---|---|---|
| `go2rtc_android_arm64` | arm64-v8a | большинство телефонов и планшетов |
| `go2rtc_android_arm` | armeabi-v7a | старые телефоны, ТВ-приставки с 32-битной системой |
| `go2rtc_android_amd64` | x86_64 | эмуляторы, Android на ПК |
| `SHA256SUMS` | | контрольные суммы |
| `LICENSE-go2rtc` | | лицензия go2rtc (MIT) |

Архитектуру выбирайте по разрядности приложения, которое запускает go2rtc (Termux, KSWEB), а не процессора: на ТВ-приставке процессор 64-битный, а приложение может быть 32-битным — и `getprop ro.product.cpu.abi`, и `uname -m` покажут 64 бита. В Termux его архитектура — `dpkg --print-architecture` (`aarch64` → arm64, `arm` → arm, `x86_64` → amd64; `i686` не собирается). В KSWEB — разрядность его PHP: `<?php echo PHP_INT_SIZE * 8;` (64 → arm64 или amd64, 32 → arm).

Теги релизов: `<тег go2rtc>-android<N>`, например `v1.9.15-android2`; `N` растёт при пересборке той же версии (изменился патч или сборка).

## Termux

Одной командой, на любой архитектуре — скрипт сам выберет файл по архитектуре Termux, сверит SHA256 и поставит `go2rtc` в `$PREFIX/bin`:

```sh
curl -fsSL https://raw.githubusercontent.com/artt652/go2rtc-android/main/install.sh | sh
go2rtc -version   # go2rtc version 1.9.15+dirty.… android/arm64
```

Конкретный релиз или другой каталог: `… | sh -s -- v1.9.15-android2` или `… | sh -s -- latest ~/bin`. Для службы и связки с ffmpeg: `pkg install resolv-conf ffmpeg termux-services`.

Вручную — тот же порядок: выбрать файл по `dpkg --print-architecture`, скачать его и `SHA256SUMS` из [последнего релиза](../../releases/latest) (`https://github.com/artt652/go2rtc-android/releases/latest/download/<файл>`), `sha256sum -c SHA256SUMS --ignore-missing`, положить в `$PREFIX/bin/go2rtc`, `chmod +x`.

Конфиг, служба `termux-services`, тестовые потоки и PiPup — как в инструкции по сборке в Termux; шаги сборки при этом не нужны.

## KSWEB

С общей памяти (`/storage/emulated/0`) Android программы не запускает, а приложениям под Android 10+ нельзя запускать файлы из своего каталога напрямую. Бинарник кладётся во внутренний каталог KSWEB (`/data/data/ru.kslabs.ksweb/files/…`) и запускается через системный загрузчик:

```sh
/system/bin/linker64 /data/data/ru.kslabs.ksweb/files/go2rtc/go2rtc -c go2rtc.yaml   # arm64, amd64
/system/bin/linker   /data/data/ru.kslabs.ksweb/files/go2rtc/go2rtc -c go2rtc.yaml   # arm
```

Файл — по разрядности PHP KSWEB (см. выше); загрузчик — `linker64` для 64-битной сборки, `linker` для 32-битной. Скачивать и раскладывать вручную в KSWEB неудобно (нет терминала) — это будет делать модуль MajorDoMo.

## Патчи

| Патч | Что делает |
|---|---|
| [`restart.patch`](patches/restart.patch) | Android не даёт процессу перезапустить себя через `execve` (`permission denied`), и «Save» в веб-интерфейсе молча не применяет конфиг. Патч пишет ошибку в журнал и завершает go2rtc — его запускает заново служба (termux-services, модуль MajorDoMo). |

## Как собирается

[`.github/workflows/build.yml`](.github/workflows/build.yml):

- **Когда:** раз в сутки — если вышел новый релиз go2rtc, а у нас его ещё нет; вручную (Actions → Build go2rtc for Android → Run workflow: любой тег, «force» — пересобрать); при изменении патчей, скриптов или workflow — пересборка последнего релиза. GitHub выключает расписание после 60 дней без активности в репозитории — тогда хватит ручного запуска.
- **Как:** исходники `AlexxIT/go2rtc` по тегу, патчи, Go из `go.mod` go2rtc, `CC` — clang из Android NDK для своей архитектуры (API 24), `-trimpath -ldflags "-s -w -checklinkname=0"`, сегменты по 16 КБ. `-checklinkname=0` нужен библиотеке anet (обращается к `net.zoneCache`).
- **Проверка без устройства** ([`scripts/check-elf.sh`](scripts/check-elf.sh)): PIE, интерпретатор `/system/bin/linker64` (`linker` для arm), зависимости — только системные библиотеки Android, нет TEXTREL, выравнивание сегментов 64-битных сборок ≥ 16 КБ.
- Если патч не наложился на новую версию go2rtc, сборка падает и релиз не выходит.

Запуск на устройстве в сборке не проверяется — на машинах GitHub нет Android.

## Лицензия

Скрипты и патчи — MIT (`LICENSE`). go2rtc — MIT, © Alexey Khit ([`LICENSE`](https://github.com/AlexxIT/go2rtc/blob/master/LICENSE)), копия прикладывается к каждому релизу.
