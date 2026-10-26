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

### Установка

Одной командой, на любой архитектуре — скрипт сам выберет файл по архитектуре Termux, сверит SHA256 и поставит `go2rtc` в `$PREFIX/bin`:

```sh
pkg install curl resolv-conf ffmpeg termux-services
curl -fsSL https://raw.githubusercontent.com/artt652/go2rtc-android/main/install.sh | sh
```

В конце скрипт выводит `go2rtc version 1.9.15… android/arm64` (или `arm`, `amd64`). `ffmpeg` нужен для источников `ffmpeg:` и перекодирования, `termux-services` — для службы ниже.

Конкретный релиз или другой каталог: `… | sh -s -- v1.9.15-android2` или `… | sh -s -- latest ~/bin`.

Вручную — тот же порядок: выбрать файл по `dpkg --print-architecture`, скачать его и `SHA256SUMS` из [последнего релиза](../../releases/latest) (`https://github.com/artt652/go2rtc-android/releases/latest/download/<файл>`), `sha256sum -c SHA256SUMS --ignore-missing`, положить в `$PREFIX/bin/go2rtc`, `chmod +x`.

### Конфиг

Конфиг — `~/go2rtc/go2rtc.yaml`. Вместо `192.168.1.10` подставьте IP телефона:

```sh
curl -s -o /dev/null -w '%{local_ip}\n' http://1.1.1.1
```

Это адрес, с которого телефон выходит в сеть: при включённом Wi-Fi — адрес в домашней сети (с VPN — адрес VPN). Нужен интернет. Без интернета, если установлен PHP:

```sh
php -r '$s=stream_socket_client("udp://8.8.8.8:53");echo strtok(stream_socket_get_name($s,false),":"),"\n";'
```

(UDP-сокет только выбирает маршрут, пакеты не уходят.) Или в настройках Android: Wi-Fi → ваша сеть → IP-адрес. Команды `ip` и `ifconfig` на Android 10–11+ адрес не покажут: приложениям закрыты netlink и `/proc/net/dev`.

```sh
mkdir -p ~/go2rtc
cat > ~/go2rtc/go2rtc.yaml <<'EOF'
api:
  listen: ":1984"
rtsp:
  listen: ":8554"
webrtc:
  listen: ":8555"
  candidates:
    - 192.168.1.10:8555

streams:
  test: ffmpeg:virtual?video&size=720#video=h264
  test_av: exec:ffmpeg -re -f lavfi -i testsrc=size=1280x720:rate=25 -f lavfi -i sine=frequency=880:beep_factor=4 -map 0:v -map 1:a -map 1:a -c:v libx264 -profile:v baseline -preset superfast -tune zerolatency -g 50 -pix_fmt yuv420p -c:a:0 libopus -ar:a:0 48000 -c:a:1 aac -ar:a:1 44100 -rtsp_transport tcp -f rtsp {output}
  test_aac: ffmpeg:test_av#video=copy#audio=aac
EOF
```

| Порт | Зачем |
|---|---|
| 1984 (TCP) | веб-интерфейс, API, WebRTC через WHEP (`/api/webrtc?src=…`), снимки (`/api/frame.jpeg?src=…`) |
| 8554 (TCP) | RTSP-сервер: `rtsp://IP:8554/<поток>` |
| 8555 (TCP и UDP) | медиапоток WebRTC |

`candidates` задаёт адрес для WebRTC явно, чтобы не зависеть от автоопределения на Android. Если порт уже занят другой программой, поменяйте его в конфиге.

Тестовые потоки не нагружают телефон, пока их никто не смотрит: ffmpeg запускается только при подключении.

| Поток | Что в нём | Для чего |
|---|---|---|
| `test` | таблица с таймером, H.264, без звука | проверка видео |
| `test_av` | таблица и писк раз в секунду; H.264 baseline, звук Opus и AAC | проверка звука и синхронности через WebRTC |
| `test_aac` | то же, звук только AAC | проверка звука через RTSP: RTSP-клиент получает только первую звуковую дорожку |

Настоящая камера — строка вида `door: rtsp://логин:пароль@192.168.1.20:554/stream2`. Подпись и время в кадре даёт `drawtext`, но это перекодирование на телефоне и заметная нагрузка на процессор:

```yaml
  door_text: ffmpeg:door#video=h264#drawtext=x=10:y=10:fontsize=28:fontcolor=white:box=1:boxcolor=black@0.5:fontfile=/system/fonts/Roboto-Regular.ttf:text='Входная дверь %{localtime\:%H\:%M\:%S}'
```

go2rtc читает конфиг только при старте: после правки — `sv restart go2rtc` или «Save» в веб-интерфейсе (go2rtc завершится и служба запустит его заново — см. «Патчи»).

### Служба termux-services

go2rtc работает как служба runit: запускается вместе с Termux и поднимается заново, если завершился.

1. Проверить, что службы запущены:

   ```sh
   echo $SVDIR
   pgrep -a runsvdir
   ```

   Если обе команды ничего не вывели (Termux не перезапускали после установки `termux-services`), полностью закройте Termux (Exit в уведомлении) и откройте снова. Для текущей сессии можно и так: `source $PREFIX/etc/profile.d/start-services.sh`.

2. Остановить go2rtc, запущенный вручную (иначе служба не займёт порты), и создать службу:

   ```sh
   pkill -x go2rtc
   mkdir -p $PREFIX/var/service/go2rtc/log
   cat > $PREFIX/var/service/go2rtc/run <<'EOF'
   #!/data/data/com.termux/files/usr/bin/sh
   cd ~/go2rtc
   exec go2rtc -c go2rtc.yaml 2>&1
   EOF
   chmod +x $PREFIX/var/service/go2rtc/run
   ln -sf $PREFIX/share/termux-services/svlogger $PREFIX/var/service/go2rtc/log/run
   ```

3. Включить и проверить (если `sv` ответит `unable to open supervise/ok`, подождите 5 секунд):

   ```sh
   sv-enable go2rtc
   sv status go2rtc
   ```

   Должно быть `run: go2rtc: (pid …) …s; run: log: (pid …) …s`.

4. Чтобы Android не усыплял Termux: `termux-wake-lock` и отключённая оптимизация батареи для Termux в настройках Android. На Android 12+ система может завершать фоновые процессы Termux — в настройках для разработчиков есть «Отключить ограничения дочерних процессов» (Android 14+).

| Команда | Действие |
|---|---|
| `sv restart go2rtc` | перезапуск после правки конфига |
| `sv down go2rtc` / `sv up go2rtc` | остановить / запустить |
| `sv-disable go2rtc` / `sv-enable go2rtc` | убрать из автозапуска / вернуть |
| `tail -f $PREFIX/var/log/sv/go2rtc/current` | журнал в реальном времени |
| `curl -X POST "http://127.0.0.1:1984/api/exit?code=0"` | перезапуск через API (служба поднимет go2rtc заново) |

### Проверка

1. В браузере откройте `http://192.168.1.10:1984` и нажмите на поток `test`: должна идти таблица с бегущим счётчиком. Звук `test_av` в браузере включается значком динамика: плеер go2rtc сам выключает звук, если браузер запрещает автозапуск со звуком.
2. В журнале не должно быть `netlinkrib`: `grep netlinkrib $PREFIX/var/log/sv/go2rtc/current`.
3. RTSP — любым плеером: `rtsp://192.168.1.10:8554/test_aac`.

### Обновление

Тот же скрипт ставит последний релиз поверх прежнего, конфиг и служба не меняются:

```sh
curl -fsSL https://raw.githubusercontent.com/artt652/go2rtc-android/main/install.sh | sh && sv restart go2rtc
```

### Удаление

```sh
sv down go2rtc                         # остановить
sv-disable go2rtc                      # убрать из автозапуска
rm -rf $PREFIX/var/service/go2rtc      # удалить службу (runsvdir сам остановит её надзор)
rm -rf $PREFIX/var/log/sv/go2rtc       # журнал службы
rm -f $PREFIX/bin/go2rtc               # программа
rm -rf ~/go2rtc                        # конфиг — если больше не нужен
```

Если служба не создавалась, достаточно `pkill -x go2rtc` и двух последних строк. `termux-services`, `ffmpeg` и `resolv-conf` удаляются обычным `pkg uninstall`, если они не нужны другим программам.

### Сборка из исходников в Termux (необязательно)

Если нужна своя сборка — тем же способом, что и в релизах, прямо в Termux. Занимает несколько минут и несколько сотен МБ на время работы.

```sh
pkg install golang git
cd ~ && rm -rf go2rtc-src
git clone --depth 1 --branch v1.9.15 https://github.com/AlexxIT/go2rtc go2rtc-src
cd go2rtc-src
curl -fsSL https://raw.githubusercontent.com/artt652/go2rtc-android/main/patches/restart.patch | git apply -v
CGO_ENABLED=1 go build -trimpath -ldflags "-s -w -checklinkname=0" -o $PREFIX/bin/go2rtc .
go2rtc -version
```

Ожидаемый ответ: `go2rtc version 1.9.15+dirty.… android/arm64`. Пометка `dirty` значит только, что исходники изменены патчем. До v1.9.15 перед сборкой нужно ещё `rm pkg/alsa/device/asound_arch.c pkg/v4l2/device/videodev2_arch.c` (у них не было `//go:build ignore`). После сборки место освобождает `go clean -modcache`.

| Флаг | Зачем |
|---|---|
| `CGO_ENABLED=1` | без cgo библиотека anet не определяет версию Android, и WebRTC падает с `netlinkrib: permission denied`; DNS — через систему |
| `-checklinkname=0` | anet обращается к `net.zoneCache` через `go:linkname`; Go 1.23+ без флага останавливает сборку: `invalid reference to net.zoneCache` |
| `-s -w`, `-trimpath` | меньше размер, без отладочной информации и локальных путей |

### Типичные ошибки

| Ошибка | Причина | Решение |
|---|---|---|
| `has unexpected e_type: 2` | запущен релизный `go2rtc_linux_arm64` | поставить сборку отсюда |
| удалённые потоки по имени хоста не открываются | сборка без cgo, не находит DNS | поставить сборку отсюда; в Termux — пакет `resolv-conf` |
| `failed to create network: route ip+net: netlinkrib: permission denied` | сборка без cgo: anet не определил версию Android | поставить сборку отсюда или собрать с `CGO_ENABLED=1` |
| `link: github.com/wlynxg/anet: invalid reference to net.zoneCache` | своя сборка: Go 1.23+ запрещает `go:linkname` к внутренним символам | флаг `-ldflags "-checklinkname=0"` |
| `C source files not allowed when not using cgo or SWIG: asound_arch.c` | своя сборка до v1.9.15 | удалить два `.c`-файла (см. выше) |
| `fail: go2rtc: unable to change to service directory` | не задана `SVDIR`, не запущен `runsvdir` | перезапустить Termux или `source $PREFIX/etc/profile.d/start-services.sh` |
| `[api] restart … failed, exiting error="permission denied"` | Android запрещает go2rtc перезапустить себя | это не ошибка: go2rtc завершается, служба запускает его заново |
| после правки конфига ничего не изменилось | конфиг читается только при старте | `sv restart go2rtc` |
| WebRTC: окно пустое, а снимки есть | не тот адрес в `candidates` или закрыт UDP 8555 | проверить `candidates` и журнал go2rtc |
| нет звука через RTSP | RTSP-клиент получает только первую звуковую дорожку (Opus) | отдельный поток с `#audio=aac` |

## KSWEB

С общей памяти (`/storage/emulated/0`) Android программы не запускает, а приложениям под Android 10+ нельзя запускать файлы из своего каталога напрямую. Бинарник кладётся во внутренний каталог KSWEB (`/data/data/ru.kslabs.ksweb/files/…`) и запускается через системный загрузчик:

```sh
/system/bin/linker64 /data/data/ru.kslabs.ksweb/files/go2rtc/go2rtc -c go2rtc.yaml   # arm64, amd64
/system/bin/linker   /data/data/ru.kslabs.ksweb/files/go2rtc/go2rtc -c go2rtc.yaml   # arm
```

Файл — по разрядности PHP KSWEB (см. выше); загрузчик — `linker64` для 64-битной сборки, `linker` для 32-битной. В KSWEB нет терминала, поэтому скачивать и раскладывать файл удобнее из программы, которая будет управлять go2rtc (например, PHP-скриптом на сайте).

## Патчи

| Патч | Что делает |
|---|---|
| [`restart.patch`](patches/restart.patch) | Android не даёт процессу перезапустить себя через `execve` (`permission denied`), и «Save» в веб-интерфейсе молча не применяет конфиг. Патч пишет ошибку в журнал и завершает go2rtc — его запускает заново служба (termux-services или другая программа, которая следит за go2rtc). |

## Как собирается

[`.github/workflows/build.yml`](.github/workflows/build.yml):

- **Когда:** раз в сутки — если вышел новый релиз go2rtc, а у нас его ещё нет; вручную (Actions → Build go2rtc for Android → Run workflow: любой тег, «force» — пересобрать); при изменении патчей, скриптов или workflow — пересборка последнего релиза. GitHub выключает расписание после 60 дней без активности в репозитории — тогда хватит ручного запуска.
- **Как:** исходники `AlexxIT/go2rtc` по тегу, патчи, Go из `go.mod` go2rtc, `CC` — clang из Android NDK для своей архитектуры (API 24), `-trimpath -ldflags "-s -w -checklinkname=0"`, сегменты по 16 КБ. `-checklinkname=0` нужен библиотеке anet (обращается к `net.zoneCache`).
- **Проверка без устройства** ([`scripts/check-elf.sh`](scripts/check-elf.sh)): PIE, интерпретатор `/system/bin/linker64` (`linker` для arm), зависимости — только системные библиотеки Android, нет TEXTREL, выравнивание сегментов 64-битных сборок ≥ 16 КБ.
- Если патч не наложился на новую версию go2rtc, сборка падает и релиз не выходит.

Запуск на устройстве в сборке не проверяется — на машинах GitHub нет Android.

## Лицензия

Скрипты и патчи — MIT (`LICENSE`). go2rtc — MIT, © Alexey Khit ([`LICENSE`](https://github.com/AlexxIT/go2rtc/blob/master/LICENSE)), копия прикладывается к каждому релизу.
