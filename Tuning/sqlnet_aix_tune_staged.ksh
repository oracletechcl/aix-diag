#!/usr/bin/ksh
# sqlnet_aix_tune_staged.ksh
#
# Staged AIX TCP tuning script (safe, reversible, engagement-proof).
# - Captures baseline + before/after values to an output directory
# - Applies tuning in explicit stages
# - Optional persistence (ODM) and rollback support
#
# NOTE:
# - Run as root.
# - Apply stages one at a time, validate with your tcpdump+awk pipeline after each stage.
#
# Tested assumptions:
# - AIX provides: /usr/sbin/no, /usr/sbin/chdev, /usr/sbin/lsattr
#
# Usage examples:
#   ./sqlnet_aix_tune_staged.ksh --baseline --iface en1 --out /var/tmp/sqlnet_tune
#   ./sqlnet_aix_tune_staged.ksh --stage 1 --iface en1 --out /var/tmp/sqlnet_tune
#   ./sqlnet_aix_tune_staged.ksh --stage 2 --iface en1 --out /var/tmp/sqlnet_tune
#   ./sqlnet_aix_tune_staged.ksh --all     --iface en1 --out /var/tmp/sqlnet_tune
#   ./sqlnet_aix_tune_staged.ksh --rollback --out /var/tmp/sqlnet_tune
#
# Persistence:
#   By default applies runtime only (no -o / chdev immediate).
#   Use --persist to also persist changes:
#     - AIX "no -p -o" for network tunables
#     - For interface attrs, chdev updates ODM by default (behavior can vary); we log before/after.
#

set -u

PATH=/usr/sbin:/usr/bin:/bin

# -----------------------------
# Defaults (override via flags)
# -----------------------------
IFACE="en1"
OUTDIR="/var/tmp/sqlnet_aix_tune"
STATEFILE=""           # will be set to $OUTDIR/state.env
LOGFILE=""             # will be set to $OUTDIR/run.log
PERSIST=0
DRYRUN=0

# Stage targets (override via flags)
TARGET_REMMTU="1500"
TARGET_TCP_SENDSPACE="262144"
TARGET_TCP_RECVSPACE="262144"
TARGET_SB_MAX="4194304"
TARGET_SACK="1"
TARGET_TCP_PMTU_DISCOVER="1"

# Stages:
#   0 = baseline capture only
#   1 = MTU/PMTU normalization: remmtu
#   2 = loss recovery: sack + tcp_pmtu_discover
#   3 = socket buffers: tcp_sendspace + tcp_recvspace (global)
#   4 = buffer ceiling: sb_max
#
# IMPORTANT: Apply one stage at a time, validate, then proceed.

# -----------------------------
# Helpers
# -----------------------------
die() { print -- "ERROR: $*" >&2; exit 1; }

need_cmd() {
  typeset c="$1"
  command -v "$c" >/dev/null 2>&1 || die "Required command not found in PATH: $c"
}

is_root() {
  [ "$(id -u 2>/dev/null)" = "0" ]
}

ts() { date "+%Y-%m-%d %H:%M:%S%z"; }

log() {
  print -- "[$(ts)] $*" | tee -a "$LOGFILE"
}

run() {
  # Log command, then run it unless dry-run.
  log "CMD: $*"
  if [ "$DRYRUN" -eq 1 ]; then
    return 0
  fi
  "$@" >>"$LOGFILE" 2>&1
  return $?
}

mk_outdir() {
  [ -d "$OUTDIR" ] || mkdir -p "$OUTDIR" || die "Cannot create OUTDIR: $OUTDIR"
  STATEFILE="$OUTDIR/state.env"
  LOGFILE="$OUTDIR/run.log"
  touch "$LOGFILE" || die "Cannot write log: $LOGFILE"
}

# Extract "name = value" from `no -a` style output.
no_get() {
  typeset key="$1"
  /usr/sbin/no -a 2>/dev/null | awk -v k="$key" '
    $1==k {print $3; exit}
  '
}

# Set via "no" (runtime), optionally persist
no_set() {
  typeset key="$1"
  typeset val="$2"

  typeset cur
  cur="$(no_get "$key" || true)"
  if [ -n "$cur" ] && [ "$cur" = "$val" ]; then
    log "SKIP: no $key already $val"
    return 0
  fi

  run /usr/sbin/no -o "${key}=${val}" || die "Failed to set ${key}=${val} (runtime)"
  if [ "$PERSIST" -eq 1 ]; then
    run /usr/sbin/no -p -o "${key}=${val}" || die "Failed to persist ${key}=${val}"
  fi
}

# Get interface attribute via lsattr
iface_get() {
  typeset iface="$1"
  typeset attr="$2"
  /usr/sbin/lsattr -El "$iface" 2>/dev/null | awk -v a="$attr" '
    $1==a {print $2; exit}
  '
}

# Set interface attribute via chdev
iface_set() {
  typeset iface="$1"
  typeset attr="$2"
  typeset val="$3"

  typeset cur
  cur="$(iface_get "$iface" "$attr" || true)"
  if [ -n "$cur" ] && [ "$cur" = "$val" ]; then
    log "SKIP: $iface $attr already $val"
    return 0
  fi

  # chdev typically updates ODM and current device if possible; behavior can be attr-dependent.
  # We log and verify after.
  run /usr/sbin/chdev -l "$iface" -a "${attr}=${val}" || die "Failed to set ${iface}:${attr}=${val}"
}

# Baseline snapshot (stored under OUTDIR)
capture_baseline() {
  typeset tag="$1"  # "pre" or "post" or "baseline"
  typeset dir="$OUTDIR/$tag"
  [ -d "$dir" ] || mkdir -p "$dir" || die "Cannot create baseline dir: $dir"

  log "Capturing baseline snapshot => $dir"

  # System + date
  ( print -- "timestamp=$(ts)"; uname -a; oslevel -s 2>/dev/null ) >"$dir/system.txt" 2>/dev/null

  # Interface attributes
  /usr/sbin/lsattr -El "$IFACE" >"$dir/lsattr_${IFACE}.txt" 2>&1 || true

  # Network tunables (full + focused)
  /usr/sbin/no -a >"$dir/no_all.txt" 2>&1 || true
  /usr/sbin/no -a | egrep '^(sack|tcp_pmtu_discover|tcp_sendspace|tcp_recvspace|sb_max|rfc1323) ' \
    >"$dir/no_focus.txt" 2>&1 || true

  # Optional (light): protocol stats snapshot (useful for before/after deltas)
  /usr/sbin/netstat -s >"$dir/netstat_s.txt" 2>&1 || true

  log "Baseline captured."
}

# Save current values for rollback
save_state_if_missing() {
  if [ -f "$STATEFILE" ]; then
    log "State file already exists: $STATEFILE (will not overwrite)"
    return 0
  fi

  log "Saving rollback state to: $STATEFILE"

  # Interface
  typeset cur_mtu cur_remmtu
  cur_mtu="$(iface_get "$IFACE" "mtu" || true)"
  cur_remmtu="$(iface_get "$IFACE" "remmtu" || true)"

  # no(1) tunables
  typeset cur_sack cur_pmtu cur_send cur_recv cur_sbmax
  cur_sack="$(no_get sack || true)"
  cur_pmtu="$(no_get tcp_pmtu_discover || true)"
  cur_send="$(no_get tcp_sendspace || true)"
  cur_recv="$(no_get tcp_recvspace || true)"
  cur_sbmax="$(no_get sb_max || true)"

  cat >"$STATEFILE" <<EOF
# Generated $(ts)
IFACE=${IFACE}
mtu=${cur_mtu}
remmtu=${cur_remmtu}
sack=${cur_sack}
tcp_pmtu_discover=${cur_pmtu}
tcp_sendspace=${cur_send}
tcp_recvspace=${cur_recv}
sb_max=${cur_sbmax}
EOF

  log "Rollback state saved."
}

load_state_or_die() {
  [ -f "$STATEFILE" ] || die "Missing state file for rollback: $STATEFILE"
  . "$STATEFILE" || die "Failed to source state: $STATEFILE"
}

rollback_all() {
  load_state_or_die
  log "ROLLBACK: Applying values from $STATEFILE"

  # Use the IFACE from state, not current arg overrides
  IFACE="${IFACE:-$IFACE}"

  capture_baseline "rollback_pre"

  # Interface remmtu (only if present)
  if [ -n "${remmtu:-}" ]; then
    iface_set "$IFACE" "remmtu" "$remmtu"
  fi

  # Restore no tunables if present
  [ -n "${sack:-}" ] && no_set "sack" "$sack"
  [ -n "${tcp_pmtu_discover:-}" ] && no_set "tcp_pmtu_discover" "$tcp_pmtu_discover"
  [ -n "${tcp_sendspace:-}" ] && no_set "tcp_sendspace" "$tcp_sendspace"
  [ -n "${tcp_recvspace:-}" ] && no_set "tcp_recvspace" "$tcp_recvspace"
  [ -n "${sb_max:-}" ] && no_set "sb_max" "$sb_max"

  capture_baseline "rollback_post"

  log "ROLLBACK complete."
}

# -----------------------------
# Stage implementations
# -----------------------------
stage_1_remmtu() {
  log "STAGE 1: Set remmtu on $IFACE => $TARGET_REMMTU"
  capture_baseline "stage1_pre"
  iface_set "$IFACE" "remmtu" "$TARGET_REMMTU"
  capture_baseline "stage1_post"
}

stage_2_loss_recovery() {
  log "STAGE 2: Enable SACK/PMTU discovery (sack=$TARGET_SACK tcp_pmtu_discover=$TARGET_TCP_PMTU_DISCOVER)"
  capture_baseline "stage2_pre"
  no_set "sack" "$TARGET_SACK"
  no_set "tcp_pmtu_discover" "$TARGET_TCP_PMTU_DISCOVER"
  capture_baseline "stage2_post"
}

stage_3_tcp_spaces() {
  log "STAGE 3: Set tcp_sendspace/tcp_recvspace => ${TARGET_TCP_SENDSPACE}/${TARGET_TCP_RECVSPACE}"
  capture_baseline "stage3_pre"
  no_set "tcp_sendspace" "$TARGET_TCP_SENDSPACE"
  no_set "tcp_recvspace" "$TARGET_TCP_RECVSPACE"
  capture_baseline "stage3_post"
}

stage_4_sbmax() {
  log "STAGE 4: Set sb_max => $TARGET_SB_MAX"
  capture_baseline "stage4_pre"
  no_set "sb_max" "$TARGET_SB_MAX"
  capture_baseline "stage4_post"
}

run_stage() {
  typeset s="$1"
  case "$s" in
    0) capture_baseline "baseline" ;;
    1) stage_1_remmtu ;;
    2) stage_2_loss_recovery ;;
    3) stage_3_tcp_spaces ;;
    4) stage_4_sbmax ;;
    *) die "Invalid stage: $s (expected 0..4)" ;;
  esac
}

# -----------------------------
# CLI
# -----------------------------
usage() {
  cat <<'EOF'
sqlnet_aix_tune_staged.ksh

Required:
  --out <dir>         Output directory for logs/state/baselines (default: /var/tmp/sqlnet_aix_tune)
  --iface <enX>       Interface name to tune (default: en1)

Actions (choose one):
  --baseline          Capture baseline only (stage 0)
  --stage <N>         Apply stage N (1..4) with before/after snapshots
  --all               Apply stages 1..4 sequentially (baseline captured before each stage)
  --rollback          Revert to values saved in state.env

Options:
  --persist           Persist changes (no -p -o for tunables; interface changes via chdev as available)
  --dry-run           Print commands only, do not apply
  --remmtu <val>      Stage 1 target remmtu (default: 1500)
  --sendspace <val>   Stage 3 target tcp_sendspace (default: 262144)
  --recvspace <val>   Stage 3 target tcp_recvspace (default: 262144)
  --sbmax <val>       Stage 4 target sb_max (default: 4194304)
  --sack <0|1>        Stage 2 target sack (default: 1)
  --pmtu <0|1>        Stage 2 target tcp_pmtu_discover (default: 1)

Notes:
- First run should be --baseline to create OUTDIR and inspect current values.
- Any tuning run will create a rollback state file on first modification: OUTDIR/state.env
- Validate after each stage using your tcpdump+awk and notebook.
EOF
}

ACTION=""
STAGE=""

# Parse args
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUTDIR="$2"; shift 2 ;;
    --iface) IFACE="$2"; shift 2 ;;
    --persist) PERSIST=1; shift ;;
    --dry-run) DRYRUN=1; shift ;;
    --baseline) ACTION="baseline"; shift ;;
    --stage) ACTION="stage"; STAGE="$2"; shift 2 ;;
    --all) ACTION="all"; shift ;;
    --rollback) ACTION="rollback"; shift ;;
    --remmtu) TARGET_REMMTU="$2"; shift 2 ;;
    --sendspace) TARGET_TCP_SENDSPACE="$2"; shift 2 ;;
    --recvspace) TARGET_TCP_RECVSPACE="$2"; shift 2 ;;
    --sbmax) TARGET_SB_MAX="$2"; shift 2 ;;
    --sack) TARGET_SACK="$2"; shift 2 ;;
    --pmtu) TARGET_TCP_PMTU_DISCOVER="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown arg: $1 (use --help)" ;;
  esac
done

[ -n "$ACTION" ] || { usage; exit 2; }

# Preconditions
need_cmd no
need_cmd chdev
need_cmd lsattr
need_cmd netstat
is_root || die "Must run as root."

mk_outdir
log "START: action=$ACTION iface=$IFACE outdir=$OUTDIR persist=$PERSIST dryrun=$DRYRUN"

# Validate interface exists
/usr/sbin/lsattr -El "$IFACE" >/dev/null 2>&1 || die "Interface not found or not queryable: $IFACE"

# Save state for rollback before any changes (except pure baseline/rollback)
case "$ACTION" in
  baseline) : ;;
  rollback) : ;;
  *) save_state_if_missing ;;
esac

case "$ACTION" in
  baseline)
    run_stage 0
    ;;
  stage)
    [ -n "$STAGE" ] || die "--stage requires a number (1..4)"
    run_stage "$STAGE"
    ;;
  all)
    # Apply 1..4, capturing a baseline before each stage for clean comparisons.
    run_stage 1
    run_stage 2
    run_stage 3
    run_stage 4
    ;;
  rollback)
    rollback_all
    ;;
  *)
    die "Unsupported action: $ACTION"
    ;;
esac

log "DONE."
exit 0
