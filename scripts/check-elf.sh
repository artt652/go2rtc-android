#!/usr/bin/env bash
# Проверка Android-сборки go2rtc без устройства: так ли она устроена, чтобы её запустил системный
# загрузчик Android (Termux, KSWEB через /system/bin/linker64):
#   - PIE (ELF type DYN): статический EXEC загрузчик отвергает («unexpected e_type: 2»);
#   - интерпретатор — системный загрузчик Android;
#   - зависимости — только системные библиотеки Android;
#   - нет перемещений в коде (TEXTREL);
#   - 64 бита: сегменты LOAD выровнены не меньше 16 КБ (устройства со страницами 16 КБ).
#
#   scripts/check-elf.sh ФАЙЛ ИНТЕРПРЕТАТОР
set -euo pipefail

f="${1:?usage: check-elf.sh FILE INTERPRETER}"
want_interp="${2:?}"
fail=0
err() { echo "::error::$f: $*"; fail=1; }

hdr=$(readelf -h "$f")
type=$(awk -F: '/Type:/ {gsub(/^ +/, "", $2); print $2; exit}' <<<"$hdr")
class=$(awk -F: '/Class:/ {gsub(/ /, "", $2); print $2; exit}' <<<"$hdr")
machine=$(awk -F: '/Machine:/ {gsub(/^ +/, "", $2); print $2; exit}' <<<"$hdr")
echo "$f: $class, $machine, $type"
case "$type" in DYN*) ;; *) err "не PIE: $type" ;; esac

interp=$(readelf -l "$f" | sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p')
echo "  interpreter: ${interp:-нет}"
[ "$interp" = "$want_interp" ] || err "интерпретатор ${interp:-нет}, нужен $want_interp"

needed=$(readelf -d "$f" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' | tr '\n' ' ')
echo "  needed: $needed"
for lib in $needed; do
  case "$lib" in libc.so|libm.so|libdl.so|liblog.so) ;; *) err "лишняя зависимость $lib" ;; esac
done

if readelf -d "$f" | grep -q TEXTREL; then err "есть TEXTREL"; fi

if [ "$class" = "ELF64" ]; then
  while read -r align; do
    [ -z "$align" ] && continue
    if [ $((align)) -lt 16384 ]; then err "сегмент LOAD выровнен по $align (< 16 КБ)"; fi
  done < <(readelf -lW "$f" | awk '$1 == "LOAD" {print $NF}')
  echo "  LOAD align: $(readelf -lW "$f" | awk '$1 == "LOAD" {print $NF}' | sort -u | tr '\n' ' ')"
fi

ls -l "$f" | awk '{print "  size: " $5}'
exit $fail
