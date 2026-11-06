# shellcheck shell=bash
# Shared log helpers for tools/*.sh. Cosmetic only: nothing here changes control
# flow except die(), which every script already used as "print + exit 1".
#
#   [*] info   [+] ok/verified   [?] warning, needs a human look
#   [>] action that touches the phone   [!!] error (stderr)
#
# Messages stay lowercase; uppercase is reserved for things that matter
# (NOT REBOOTING, INCOMPLETE, ...). Colour only on a terminal, never with NO_COLOR.

# Decide once, here: inside $(...) stdout is always a pipe, so testing per call
# would never colour stdout.
_tty1=0; _tty2=0
if [ -z "${NO_COLOR:-}" ]; then [ -t 1 ] && _tty1=1; [ -t 2 ] && _tty2=1; fi
_c() { local t="_tty$1"; if [ "${!t}" = 1 ]; then printf '\033[%sm' "$2"; fi; }
_r() { _c "$1" 0; }

info() { printf '%s[*]%s %s\n'  "$(_c 1 34)"   "$(_r 1)" "$*"; }
ok()   { printf '%s[+]%s %s\n'  "$(_c 1 32)"   "$(_r 1)" "$*"; }
warn() { printf '%s[?]%s %s\n'  "$(_c 1 33)"   "$(_r 1)" "$*"; }
act()  { printf '%s[>]%s %s\n'  "$(_c 1 36)"   "$(_r 1)" "$*"; }
err()  { printf '%s[!!]%s %s\n' "$(_c 2 '1;31')" "$(_r 2)" "$*" >&2; }
die()  { err "$*"; exit 1; }

# Indented "key  value" detail line under a tagged line
kv()   { printf '     %s%-24s%s %s\n' "$(_c 1 2)" "$1" "$(_r 1)" "$2"; }
# Section header
hdr()  { printf '\n%s── %s ──%s\n' "$(_c 1 1)" "$*" "$(_r 1)"; }
