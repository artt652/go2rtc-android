#!/bin/sh
# Установка go2rtc для Android (Termux) с выбором архитектуры:
#   curl -fsSL https://raw.githubusercontent.com/artt652/go2rtc-android/main/install.sh | sh
#   curl -fsSL …/install.sh | sh -s -- v1.9.15-android2      # конкретный релиз
#   curl -fsSL …/install.sh | sh -s -- latest ~/bin           # другой каталог установки
#
# Архитектура — по самому Termux (dpkg --print-architecture), а не по процессору: на ТВ-приставке
# процессор 64-битный, а Termux может быть 32-битным. Без dpkg — по uname -m.
# Файл сверяется по SHA256SUMS релиза; ставится как go2rtc в $PREFIX/bin (или во второй аргумент).
set -eu

REPO=artt652/go2rtc-android
VERSION=${1:-latest}
DEST=${2:-${PREFIX:-/data/data/com.termux/files/usr}/bin}

arch=""
if command -v dpkg >/dev/null 2>&1; then
  arch=$(dpkg --print-architecture 2>/dev/null || true)
fi
[ -n "$arch" ] || arch=$(uname -m)

case "$arch" in
  aarch64|arm64) asset=go2rtc_android_arm64 ;;
  arm|armv7l|armv8l|armhf|armel) asset=go2rtc_android_arm ;;
  x86_64|amd64) asset=go2rtc_android_amd64 ;;
  *) echo "go2rtc-android: архитектура «$arch» не поддерживается (есть arm64, arm, x86_64)" >&2; exit 1 ;;
esac

if [ "$VERSION" = "latest" ]; then
  url="https://github.com/$REPO/releases/latest/download"
else
  url="https://github.com/$REPO/releases/download/$VERSION"
fi

tmp=$(mktemp -d "${TMPDIR:-/data/data/com.termux/files/usr/tmp}/go2rtc.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM

get() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$2" "$1"
  else
    wget -q -O "$2" "$1"
  fi
}

echo "go2rtc-android: $arch → $asset ($VERSION)"
get "$url/$asset" "$tmp/$asset"
get "$url/SHA256SUMS" "$tmp/SHA256SUMS"
(cd "$tmp" && grep " $asset\$" SHA256SUMS | sha256sum -c -)

mkdir -p "$DEST"
cp "$tmp/$asset" "$DEST/go2rtc"
chmod 755 "$DEST/go2rtc"
echo "go2rtc-android: установлено в $DEST/go2rtc"
"$DEST/go2rtc" -version || echo "go2rtc-android: не запускается здесь (это не Android?)" >&2
