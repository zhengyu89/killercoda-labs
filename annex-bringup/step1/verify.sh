#!/bin/bash
#
# Every exit path below says why. Killercoda only reads the exit code, so the
# explanation is written to /root/.check and the learner reads it with `why`.
LOG=/root/.check
STEP="Step 1 · Kernel prep that survives a reboot"
: > "$LOG"
fail() { { echo "x $STEP"; echo; printf '%s\n' "$@"; } | tee "$LOG"; exit 1; }
pass() { echo "OK $STEP -- passed." | tee "$LOG"; exit 0; }
R=""

MODF=/etc/modules-load.d/annex.conf
SYSF=/etc/sysctl.d/90-annex.conf
KEYS="vm.max_map_count=262144
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=524288
net.bridge.bridge-nf-call-ip6tables=1"

# Every key=value a file sets, whitespace and comments stripped.
settings() { sed -E 's/[#;].*//; s/[[:space:]]//g' "$1" 2>/dev/null | grep '='; }
runtime() { sysctl -n "$1" 2>/dev/null; }

for _ in $(seq 1 6); do
  [ -s "$MODF" ] || { R="nomodf"; sleep 5; continue; }
  MODS=$(sed -E 's/#.*//; s/[[:space:]]//g' "$MODF" | grep -v '^$')
  MISSMOD=""
  for M in overlay br_netfilter; do echo "$MODS" | grep -qx "$M" || MISSMOD="$MISSMOD $M"; done
  [ -z "$MISSMOD" ] || { R="modlist"; sleep 5; continue; }
  UNLOADED=""
  for M in overlay br_netfilter; do [ -d "/sys/module/$M" ] || UNLOADED="$UNLOADED $M"; done
  [ -z "$UNLOADED" ] || { R="modload"; sleep 5; continue; }

  [ -s "$SYSF" ] || { R="nosysf"; sleep 5; continue; }
  INFILE=$(settings "$SYSF")
  MISSFILE=""
  while read -r KV; do echo "$INFILE" | grep -qx "$KV" || MISSFILE="${MISSFILE}  ${KV}"$'\n'; done <<< "$KEYS"
  [ -z "$MISSFILE" ] || { R="filevals"; sleep 5; continue; }

  # Now, before simulating a reboot: were the values actually applied?
  NOTNOW=""
  while read -r KV; do
    K=${KV%%=*}; V=${KV#*=}
    [ "$(runtime "$K")" == "$V" ] || NOTNOW="${NOTNOW}  ${K} is $(runtime "$K"), want ${V}"$'\n'
  done <<< "$KEYS"
  [ -z "$NOTNOW" ] || { R="notapplied"; sleep 5; continue; }

  # A reboot, as far as sysctl is concerned: every drop-in, in boot order.
  # The output names each file before its settings, so the last file to set a
  # key is the one that wins it.
  BOOT=$(sysctl --system 2>&1)
  LOST=""
  while read -r KV; do
    K=${KV%%=*}; V=${KV#*=}
    if [ "$(runtime "$K")" != "$V" ]; then
      WINNER=$(echo "$BOOT" | awk -v k="$K" '
        /^\* Applying / { f=$3; sub(/ \.\.\.$/, "", f) }
        { line=$0; gsub(/[[:space:]]/, "", line); if (index(line, k "=") == 1) w=f }
        END { print w }')
      LOST="${LOST}  ${K} = $(runtime "$K") after boot, set last by ${WINNER:-<unknown>}"$'\n'
    fi
  done <<< "$KEYS"
  [ -z "$LOST" ] || { R="lostonboot"; break; }

  pass
done

case "$R" in
  nomodf) fail \
    "$MODF does not exist or is empty." \
    "" \
    "One module name per line:" \
    "  printf 'overlay\\nbr_netfilter\\n' > $MODF" ;;
  modlist) fail \
    "$MODF does not list:${MISSMOD}" \
    "" \
    "  cat $MODF" ;;
  modload) fail \
    "Listed for boot, but not loaded right now:${UNLOADED}" \
    "" \
    "The file only takes effect at the next boot. Load them now too:" \
    "  modprobe overlay; modprobe br_netfilter" ;;
  nosysf) fail \
    "$SYSF does not exist or is empty." \
    "" \
    "The task asks for this exact file -- not /etc/sysctl.conf, and not another" \
    "name in /etc/sysctl.d/." ;;
  filevals) fail \
    "$SYSF does not set:" \
    "" \
    "$MISSFILE" \
    "Format: one 'key = value' per line." ;;
  notapplied) fail \
    "The file is right, but the running system does not have these values yet:" \
    "" \
    "$NOTNOW" \
    "Writing a file changes nothing until it is loaded:" \
    "  sysctl --system" ;;
  lostonboot) fail \
    "Your values were in effect -- but a reboot would undo them." \
    "" \
    "This check just ran 'sysctl --system', which loads every drop-in in the same" \
    "order the boot process does, and then read the values back:" \
    "" \
    "$LOST" \
    "Files are applied in order of file name, and the last one to set a key wins." \
    "Remove the stale settings from that file (or remove the file), then:" \
    "  sysctl --system" \
    "" \
    "(The check has left the running values as a reboot would -- that is why" \
    "'sysctl vm.max_map_count' now shows the old value too.)" ;;
  *) fail "Unexpected state -- rerun the check." ;;
esac
