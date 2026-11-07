#!/bin/bash
# Starts tools/local/sync.sh as a systemd user service:
#  - keeps running if the terminal or session that started it goes away
#  - blocks sleep, idle suspend and lid-close suspend while it runs
#  - restarts it if it ever exits with an error
# Follow it with:  tail -f ~/aera-lexus/src-sync.log
# Stop it with:    systemctl --user stop aera-sync
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/log.sh"
here="$(dirname "$(readlink -f "$0")")"

if systemctl --user is-active --quiet aera-sync; then
  warn "aera-sync is already running"; systemctl --user status aera-sync --no-pager | head -5; exit 0
fi
systemctl --user reset-failed aera-sync 2>/dev/null || true

act "starting aera-sync"
systemd-run --user --unit=aera-sync --collect \
  -p Restart=on-failure -p RestartSec=60 \
  -E PATH="$HOME/.local/bin:$PATH" -E HOME="$HOME" \
  ${SRC:+-E SRC="$SRC"} ${JOBS:+-E JOBS="$JOBS"} ${BRANCH:+-E BRANCH="$BRANCH"} ${SOURCE:+-E SOURCE="$SOURCE"} \
  systemd-inhibit --what=sleep:idle:handle-lid-switch --who="aera-sync" \
    --why="downloading Android source" --mode=block \
  "$here/sync.sh"
ok "running. log: tail -f ${SRC:-$HOME/aera-lexus/src}/../src-sync.log"
