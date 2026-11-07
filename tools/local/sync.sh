#!/bin/bash
# Resumable, unattended AERA source sync for local builds.
# Normally started through tools/local/start-sync.sh (systemd user service, no
# sleep while it runs). Safe to rerun at any time: repo resumes.
#
#   SRC     source root          (default ~/aera-lexus/src)
#   BRANCH  manifest branch      (default aera-16.0)
#   JOBS    parallel fetches     (default 4; gentle on a weak connection)
#   NET_CONN NetworkManager connection to re-bring up (default: the active one)
#   LOG     log file             (default $SRC/../src-sync.log)
set -uo pipefail

SRC="${SRC:-$HOME/aera-lexus/src}"
BRANCH="${BRANCH:-aera-16.0}"
JOBS="${JOBS:-4}"
LOG="${LOG:-$(dirname "$SRC")/src-sync.log}"
REPO="$HOME/.local/bin/repo"
NET_CONN="${NET_CONN:-$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | awk -F: '$2 != "loopback" {print $1; exit}')}"

mkdir -p "$SRC" "$(dirname "$LOG")"
# Everything to the log, one timestamp per line (and to stdout for journald)
exec > >(while IFS= read -r l; do printf '%s %s\n' "$(date '+%F %T')" "$l"; done | tee -a "$LOG") 2>&1
# After the redirect: the log is not a terminal, so no colour codes end up in it
. "$(dirname "$(readlink -f "$0")")/../lib/log.sh"

netup() {
  curl -fsS -m 15 -o /dev/null https://android.googlesource.com/ 2>/dev/null \
    || curl -fsS -m 15 -o /dev/null https://github.com/ 2>/dev/null
}

# Background watchdog: checks every 30 s. After ~3 min down, re-brings the
# connection up through NetworkManager, then again every ~10 min while down.
watchdog() {
  local down=0
  while sleep 30; do
    if netup; then
      [ "$down" -gt 0 ] && ok "network back after ~$((down * 30))s"
      down=0
    else
      down=$((down + 1))
      warn "network check failed ($down in a row)"
      if [ "$down" -eq 6 ] || { [ "$down" -gt 6 ] && [ $(( (down - 6) % 20 )) -eq 0 ]; }; then
        if [ -n "$NET_CONN" ]; then
          act "re-bringing up '$NET_CONN' (nmcli radio wifi on; connection up)"
          nmcli radio wifi on 2>&1 | sed 's/^/     /'
          nmcli connection up "$NET_CONN" 2>&1 | tail -1 | sed 's/^/     /'
        else
          err "no NetworkManager connection known to re-bring up"
        fi
      fi
    fi
  done
}

wait_for_net() {
  until netup; do warn "waiting for network before retrying"; sleep 30; done
}

progress() {
  local start total fetched checked
  start=$(date +%s); total="$1"
  while sleep 60; do
    fetched=$(find .repo/project-objects -name '*.git' -type d -prune 2>/dev/null | wc -l)
    checked=$(find . -path ./.repo -prune -o -name .git -prune -print 2>/dev/null | wc -l)
    info "$(( ($(date +%s) - start) / 60 )) min | .repo $(du -sh .repo 2>/dev/null | cut -f1) | fetched $fetched/$total | checked out $checked/$total | free $(df -h . | awk 'NR==2{print $4}')"
  done
}

# repo treats a project with a gitdir but no `shallow` file as "manually
# unshallowed" and fetches its FULL history (project.py: `if depth and not
# is_new and not self._HasShallow(): depth = None`). A first shallow fetch that
# dies mid-transfer leaves exactly that state: on 2026-11-07 it turned
# prebuilts/rust and prebuilts/sdk into 50+ GB. Before each retry, reset such
# projects so they count as new again. Tiny repos with a single commit also lack
# a shallow file legitimately, hence the size floor.
reset_unshallowed() {
  local g od sz p
  while IFS= read -r g; do
    [ -f "$g/shallow" ] && continue
    od="$(readlink -f "$g/objects" 2>/dev/null)"; od="${od%/objects}"
    [ -n "$od" ] && [ -d "$od" ] || continue
    sz=$(du -sm "$od" 2>/dev/null | cut -f1)
    [ "${sz:-0}" -ge "${UNSHALLOW_RESET_MB:-300}" ] || continue
    p="${g#.repo/projects/}"; p="${p%.git}"
    warn "resetting $p: no shallow marker after a failed fetch, ${sz} MB of objects (would refetch full history)"
    rm -rf -- "$g" "$od" "$p"
  done < <(find .repo/projects -name '*.git' -type d -prune 2>/dev/null)
}

cleanup() { kill "${wd:-}" "${pg:-}" 2>/dev/null || true; }
trap cleanup EXIT

hdr "aera source sync -> $SRC"
info "branch $BRANCH, $JOBS parallel fetches, watching connection '${NET_CONN:-<none>}'"
watchdog & wd=$!

if [ ! -x "$REPO" ]; then
  wait_for_net
  act "installing repo launcher -> $REPO"
  mkdir -p "$(dirname "$REPO")"
  curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o "$REPO.tmp" && chmod +x "$REPO.tmp" && mv "$REPO.tmp" "$REPO" \
    || die "could not download the repo launcher"
fi
export PATH="$(dirname "$REPO"):$PATH"

cd "$SRC"
if [ ! -d .repo/manifests ]; then
  wait_for_net
  act "repo init (depth 1)"
  until repo init -u https://github.com/AERA-Recovery/android_manifest.git -b "$BRANCH" --depth=1 --no-clone-bundle; do
    warn "repo init failed, retrying in 60s"; sleep 60; wait_for_net
  done
fi

total=$(repo manifest 2>/dev/null | grep -c '<project ' || echo '?')
progress "$total" & pg=$!

attempt=0
force=""
until repo sync -c --no-tags --no-clone-bundle --optimized-fetch --retry-fetches=5 $force -j"$JOBS"; do
  attempt=$((attempt + 1))
  backoff=$(( attempt * 60 > 600 ? 600 : attempt * 60 ))
  err "repo sync failed (attempt $attempt); retrying in ${backoff}s"
  # After a failure, let repo replace any project left in a broken state
  force="--force-sync"
  reset_unshallowed
  sleep "$backoff"
  wait_for_net
done

touch .sync-complete
ok "SYNC COMPLETE after $attempt retries: $(du -sh . | cut -f1) in $SRC"
