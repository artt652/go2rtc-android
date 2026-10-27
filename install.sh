#!/bin/sh
# go2rtc для Android (Termux): установка, автозапуск, удаление.
#
#   curl -fsSL https://raw.githubusercontent.com/artt652/go2rtc-android/main/install.sh | sh
#
# Без параметров: если есть терминал — спросит, как запускать go2rtc (по умолчанию — как сейчас,
# при первой установке — вручную, простая установка); без терминала — оставит как сейчас (обновление).
# Параметры (… | sh -s -- ПАРАМЕТРЫ):
#   --simple            только программа: запуск и остановка вручную
#   --service           + служба termux-services (запуск с Termux, перезапуск при падении)
#   --boot              + запуск при загрузке телефона через Termux:Boot
#   --uninstall         остановить go2rtc, убрать службу и автозапуск, удалить программу
#   --purge             вместе с --uninstall: удалить и каталог ~/go2rtc (конфиг, журнал)
#   --version vX.Y.Z-androidN   конкретный релиз (по умолчанию — последний)
#   --dir КАТАЛОГ       куда ставить программу (по умолчанию $PREFIX/bin)
# Прежняя форма тоже работает: … | sh -s -- vX.Y.Z-androidN [КАТАЛОГ]
#
# Архитектура — по самому Termux (dpkg --print-architecture), а не по процессору: на ТВ-приставке
# процессор 64-битный, а Termux может быть 32-битным. Без dpkg — по uname -m.
# Файл сверяется по SHA256SUMS релиза. Конфиг и рабочий каталог — ~/go2rtc (go2rtc.yaml).
set -eu

REPO=artt652/go2rtc-android
PREFIX=${PREFIX:-/data/data/com.termux/files/usr}
WORKDIR="$HOME/go2rtc"
SVC="$PREFIX/var/service/go2rtc"
BOOT="$HOME/.termux/boot/go2rtc"
VERSION=latest
DEST="$PREFIX/bin"
MODE=""
PURGE=0

say() { echo "go2rtc-android: $*"; }
die() { echo "go2rtc-android: $*" >&2; exit 1; }

pos=0
while [ $# -gt 0 ]; do
  case "$1" in
    --simple) MODE=simple ;;
    --service) MODE=service ;;
    --boot) MODE=boot ;;
    --uninstall) MODE=uninstall ;;
    --purge) PURGE=1 ;;
    --version) shift; VERSION=${1:?--version: нужен тег} ;;
    --version=*) VERSION=${1#*=} ;;
    --dir) shift; DEST=${1:?--dir: нужен каталог} ;;
    --dir=*) DEST=${1#*=} ;;
    -h|--help) echo "… | sh -s -- [--simple|--service|--boot|--uninstall [--purge]] [--version vX.Y.Z-androidN] [--dir КАТАЛОГ]"; exit 0 ;;
    -*) die "неизвестный параметр $1 (--help)" ;;
    *) pos=$((pos + 1)); if [ $pos -eq 1 ]; then VERSION=$1; else DEST=$1; fi ;;
  esac
  shift
done

# остановить go2rtc, где бы он ни был запущен: служба, Termux:Boot, вручную
stop_go2rtc() {
  if [ -d "$SVC" ] && command -v sv >/dev/null 2>&1; then
    sv down go2rtc >/dev/null 2>&1 || true
  fi
  pkill -f 'go2rtc-loop.sh' >/dev/null 2>&1 || true
  # имя процесса может быть linker64 (запуск через системный загрузчик) — ищем по командной строке
  pkill -f 'go2rtc -c' >/dev/null 2>&1 || true
}

remove_service() {
  if [ -d "$SVC" ]; then
    command -v sv >/dev/null 2>&1 && sv down go2rtc >/dev/null 2>&1 || true
    command -v sv-disable >/dev/null 2>&1 && sv-disable go2rtc >/dev/null 2>&1 || true
    rm -rf "$SVC" "$PREFIX/var/log/sv/go2rtc"
    say "служба termux-services удалена"
  fi
}

remove_boot() {
  if [ -e "$BOOT" ] || [ -e "$WORKDIR/go2rtc-loop.sh" ]; then
    pkill -f 'go2rtc-loop.sh' >/dev/null 2>&1 || true
    rm -f "$BOOT" "$WORKDIR/go2rtc-loop.sh"
    say "автозапуск Termux:Boot удалён"
  fi
}

if [ "$MODE" = uninstall ]; then
  stop_go2rtc
  remove_service
  remove_boot
  for f in "$DEST/go2rtc" "$PREFIX/bin/go2rtc"; do
    [ -e "$f" ] && rm -f "$f" && say "удалено: $f"
  done
  if [ "$PURGE" = 1 ]; then
    rm -rf "$WORKDIR" && say "удалён каталог $WORKDIR"
  else
    [ -d "$WORKDIR" ] && say "конфиг оставлен: $WORKDIR (удалить вместе с ним — --uninstall --purge)"
  fi
  say "готово"
  exit 0
fi

# способ запуска сейчас: служба, Termux:Boot или вручную
current=simple
[ -d "$SVC" ] && current=service
[ -e "$BOOT" ] && current=boot

# способ запуска: спросить, если есть терминал (curl … | sh — вопрос идёт через /dev/tty);
# Enter — как сейчас (при первой установке — вручную)
if [ -z "$MODE" ]; then
  MODE=$current
  case "$current" in service) def=2 ;; boot) def=3 ;; *) def=1 ;; esac
  if [ -r /dev/tty ] && [ -w /dev/tty ] && (exec </dev/tty) 2>/dev/null; then
    {
      echo "Как запускать go2rtc?"
      echo "  1) вручную — простая установка"
      echo "  2) служба termux-services: запуск вместе с Termux, перезапуск при падении"
      echo "  3) Termux:Boot: запуск при загрузке телефона (нужно приложение Termux:Boot)"
      [ "$current" != simple ] && echo "  (сейчас: $def)"
      printf "Выбор [%s]: " "$def"
    } >/dev/tty
    read -r answer </dev/tty || answer=""
    case "${answer:-$def}" in
      2) MODE=service ;;
      3) MODE=boot ;;
      *) MODE=simple ;;
    esac
  fi
fi

arch=""
if command -v dpkg >/dev/null 2>&1; then
  arch=$(dpkg --print-architecture 2>/dev/null || true)
fi
[ -n "$arch" ] || arch=$(uname -m)

case "$arch" in
  aarch64|arm64) asset=go2rtc_android_arm64 ;;
  arm|armv7l|armv8l|armhf|armel) asset=go2rtc_android_arm ;;
  x86_64|amd64) asset=go2rtc_android_amd64 ;;
  *) die "архитектура «$arch» не поддерживается (есть arm64, arm, x86_64)" ;;
esac

if [ "$VERSION" = "latest" ]; then
  url="https://github.com/$REPO/releases/latest/download"
else
  url="https://github.com/$REPO/releases/download/$VERSION"
fi

tmp=$(mktemp -d "${TMPDIR:-$PREFIX/tmp}/go2rtc.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM

# get URL ФАЙЛ [progress]: с полосой прогресса для большого файла; ожидание соединения 20 с, 3 повтора
get() {
  if command -v curl >/dev/null 2>&1; then
    if [ "${3:-}" = progress ]; then
      curl -fL --connect-timeout 20 --retry 3 --retry-delay 2 --progress-bar -o "$2" "$1"
    else
      curl -fsSL --connect-timeout 20 --retry 3 --retry-delay 2 -o "$2" "$1"
    fi
  else
    if [ "${3:-}" = progress ]; then
      wget -q --show-progress -T 20 -t 3 -O "$2" "$1"
    else
      wget -q -T 20 -t 3 -O "$2" "$1"
    fi
  fi
}

say "архитектура $arch → $asset, релиз $VERSION, запуск: $MODE"
say "контрольные суммы…"
get "$url/SHA256SUMS" "$tmp/SHA256SUMS"
say "скачиваю $asset (~20 МБ) с $url"
get "$url/$asset" "$tmp/$asset" progress
say "проверка SHA256…"
(cd "$tmp" && grep " $asset\$" SHA256SUMS | sha256sum -c -)

mkdir -p "$DEST" "$WORKDIR"
cp "$tmp/$asset" "$DEST/go2rtc.new"
chmod 755 "$DEST/go2rtc.new"
mv -f "$DEST/go2rtc.new" "$DEST/go2rtc"
say "установлено в $DEST/go2rtc"
"$DEST/go2rtc" -version || say "не запускается здесь (это не Android?)"

BIN="$DEST/go2rtc"

case "$MODE" in
  simple)
    # способ запуска сменили — прежний автозапуск убрать
    remove_service
    remove_boot
    cat <<EOF

Запуск вручную (конфиг — $WORKDIR/go2rtc.yaml):
  cd ~/go2rtc && go2rtc -c go2rtc.yaml                                   # в этом окне, остановка — Ctrl+C
  cd ~/go2rtc && nohup go2rtc -c go2rtc.yaml > go2rtc.log 2>&1 &        # в фоне, журнал — ~/go2rtc/go2rtc.log
Остановка фонового:
  curl -X POST "http://127.0.0.1:1984/api/exit?code=0"   # или: pkill -f 'go2rtc -c'
EOF
    ;;

  service)
    remove_boot
    if ! command -v sv-enable >/dev/null 2>&1; then
      die "нет termux-services: pkg install termux-services, перезапустите Termux и повторите с --service"
    fi
    stop_go2rtc
    mkdir -p "$SVC/log"
    cat > "$SVC/run" <<EOF
#!$PREFIX/bin/sh
cd "$WORKDIR"
exec "$BIN" -c go2rtc.yaml 2>&1
EOF
    chmod 755 "$SVC/run"
    ln -sf "$PREFIX/share/termux-services/svlogger" "$SVC/log/run"
    if [ -z "${SVDIR:-}" ] || ! pgrep -f runsvdir >/dev/null 2>&1; then
      say "служба создана, но службы Termux не запущены: закройте Termux полностью (Exit в уведомлении),"
      say "откройте снова и выполните: sv-enable go2rtc"
    else
      sv-enable go2rtc || true
      sleep 3
      sv status go2rtc || true
      say "служба включена"
    fi
    cat <<EOF

Служба: sv restart go2rtc | sv down go2rtc | sv up go2rtc | sv-disable go2rtc
Журнал: tail -f $PREFIX/var/log/sv/go2rtc/current
Чтобы Android не усыплял Termux: termux-wake-lock и без оптимизации батареи для Termux.
EOF
    ;;

  boot)
    remove_service
    stop_go2rtc
    # go2rtc завершается после «Save» в веб-интерфейсе (на Android он не может перезапустить себя) —
    # цикл запускает его снова; остановка цикла — pkill -f go2rtc-loop.sh
    cat > "$WORKDIR/go2rtc-loop.sh" <<EOF
#!$PREFIX/bin/sh
cd "$WORKDIR"
while :; do
  "$BIN" -c go2rtc.yaml >> go2rtc.log 2>&1
  sleep 3
done
EOF
    chmod 755 "$WORKDIR/go2rtc-loop.sh"
    mkdir -p "$(dirname "$BOOT")"
    cat > "$BOOT" <<EOF
#!$PREFIX/bin/sh
termux-wake-lock
nohup "$WORKDIR/go2rtc-loop.sh" >/dev/null 2>&1 &
EOF
    chmod 755 "$BOOT"
    nohup "$WORKDIR/go2rtc-loop.sh" >/dev/null 2>&1 &
    say "автозапуск Termux:Boot создан ($BOOT), go2rtc запущен"
    cat <<EOF

Нужно приложение Termux:Boot (из того же источника, что и Termux), один раз открыть его после установки.
Журнал: tail -f ~/go2rtc/go2rtc.log
Остановить: pkill -f go2rtc-loop.sh && pkill -f 'go2rtc -c'
Запустить снова: nohup ~/go2rtc/go2rtc-loop.sh >/dev/null 2>&1 &
Чтобы Android не усыплял Termux: без оптимизации батареи для Termux.
EOF
    ;;
esac
