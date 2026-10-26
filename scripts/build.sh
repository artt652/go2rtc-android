#!/usr/bin/env bash
# Сборка go2rtc для Android — одна и та же в GitHub Actions и в Termux:
#
#   scripts/build.sh КАТАЛОГ_ИСХОДНИКОВ_GO2RTC ВЫХОДНОЙ_ФАЙЛ
#
# 1. patches/go2rtc/*.patch — в исходники go2rtc (git apply; уже наложенный пропускается).
# 2. patches/go/*.patch — в стандартную библиотеку Go, но не в сам Go: изменённые копии файлов
#    подставляются через go build -overlay, установленный Go не меняется.
# 3. go build: GOOS=android, CGO_ENABLED=1 (по умолчанию), -checklinkname=0, сегменты по 16 КБ.
#
# Окружение: GOARCH, GOARM, CC — как для обычной кросс-сборки (в Termux не нужны: всё своё).
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
src=$(cd "${1:?usage: build.sh GO2RTC_SRC OUT}" && pwd)
out="${2:?usage: build.sh GO2RTC_SRC OUT}"
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac

export GOOS="${GOOS:-android}"
export CGO_ENABLED="${CGO_ENABLED:-1}"

cd "$src"

# 1. патчи go2rtc
for p in "$here"/patches/go2rtc/*.patch; do
  [ -e "$p" ] || continue
  if git apply --reverse --check "$p" 2>/dev/null; then
    echo "== $p: уже наложен"
  else
    echo "== $p"
    git apply --verbose "$p"
  fi
done
# до v1.9.15 у этих вспомогательных файлов не было «//go:build ignore», и сборка с cgo на них падала
for f in pkg/alsa/device/asound_arch.c pkg/v4l2/device/videodev2_arch.c; do
  if [ -f "$f" ] && ! grep -q 'go:build ignore' "$f"; then rm -v "$f"; fi
done

# 2. патчи стандартной библиотеки Go — через -overlay
goroot=$(go env GOROOT)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/goroot"
replace=""
for p in "$here"/patches/go/*.patch; do
  [ -e "$p" ] || continue
  echo "== $p (Go $(go env GOVERSION), через -overlay)"
  files=$(sed -n 's#^+++ b/##p' "$p")
  for f in $files; do
    if [ -f "$goroot/$f" ] && [ ! -f "$tmp/goroot/$f" ]; then
      mkdir -p "$(dirname "$tmp/goroot/$f")"
      cp "$goroot/$f" "$tmp/goroot/$f"
    fi
  done
  git -C "$tmp/goroot" apply --verbose "$p"
  for f in $files; do
    replace="$replace${replace:+,}\"$goroot/$f\":\"$tmp/goroot/$f\""
  done
done
overlay=()
if [ -n "$replace" ]; then
  printf '{"Replace":{%s}}\n' "$replace" > "$tmp/overlay.json"
  overlay=(-overlay "$tmp/overlay.json")
fi

# 3. сборка
# -checklinkname=0: библиотека wlynxg/anet (обход запрета netlink на Android 11+) обращается к net.zoneCache;
# сегменты по 16 КБ — для устройств с такими страницами памяти (Android 15+)
go version
go build -trimpath "${overlay[@]}" \
  -ldflags "-s -w -checklinkname=0 -extldflags=-Wl,-z,max-page-size=16384" \
  -o "$out" .
echo "== $out"
