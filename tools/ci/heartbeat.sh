#!/bin/bash
# Usage: heartbeat.sh <source-root> [interval-seconds]
# Prints one status line per interval until killed. For CI build steps whose
# tools stay silent for a long time (soong_build analysis, kati).
#
#   [*] 14 min | soong_build: analysing Android.bp | rss 9.8G | mem 13/15G swap 4/16G load 3.9 | soong.log: <last line>
root="${1:?source root}"; every="${2:-120}"
start=$(date +%s)

phase() {
  if pgrep -x soong_build >/dev/null; then echo "soong_build: analysing Android.bp"
  elif pgrep -f 'ckati' >/dev/null;     then echo "kati: reading makefiles"
  elif pgrep -x ninja >/dev/null;       then echo "ninja: compiling"
  elif pgrep -f 'soong_ui' >/dev/null;  then echo "soong_ui: between phases"
  else echo "no build process"; fi
}

rss_of() { # largest RSS among processes named $1, in GB
  ps -C "$1" -o rss= 2>/dev/null | sort -n | tail -1 | awk '{if ($1) printf "%.1fG", $1/1048576; else print "-"}'
}

while sleep "$every"; do
  p=$(phase)
  case "$p" in
    soong_build*) rss=$(rss_of soong_build) ;;
    kati*)        rss=$(rss_of ckati) ;;
    ninja*)       rss=$(rss_of ninja) ;;
    *)            rss=- ;;
  esac
  mem=$(free -g | awk '/^Mem/{print $3"/"$2"G"}')
  swp=$(free -g | awk '/^Swap/{print $3"/"$2"G"}')
  load=$(cut -d' ' -f1 /proc/loadavg)
  last=$(tail -1 "$root/out/soong.log" 2>/dev/null | cut -c1-110)
  echo "[*] $(( ($(date +%s) - start) / 60 )) min | $p | rss $rss | mem $mem swap $swp load $load | soong.log: ${last:-<none yet>}"
  # Swap close to full means the OOM killer is next
  used=$(free -m | awk '/^Swap/{print $3}'); tot=$(free -m | awk '/^Swap/{print $2}')
  if [ "${tot:-0}" -gt 0 ] && [ $(( used * 100 / tot )) -ge 85 ]; then
    echo "[?] swap is over 85% full; an OOM kill is likely if this keeps growing"
  fi
done
