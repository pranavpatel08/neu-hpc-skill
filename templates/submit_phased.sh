#!/usr/bin/env bash
# Phased Slurm submission with sacct-based dependency resolution.
#
# Solves two real problems:
#   1. QOS submit limits — most clusters cap concurrent submitted+pending+
#      running jobs per user. Submitting a full DAG at once gets the tail
#      rejected. This script submits in small phases instead.
#   2. `--dependency=afterok:<JID>` fails with "Job dependency problem" once
#      the target JID ages out of the active queue (hours after completion,
#      even though the job succeeded). resolve_dep() checks sacct and drops/
#      converts dependencies instead of blindly passing raw job IDs.
#
# Usage:
#   bash submit_phased.sh 1        # submit phase 1
#   bash submit_phased.sh 2        # submit phase 2 (after phase 1 completes)
#   bash submit_phased.sh status   # show saved job IDs + squeue
#   bash submit_phased.sh clean    # scancel everything saved + clear state
#
# Adapt: ROOT, USER_NAME, and the phase cases at the bottom to your own DAG.
set -euo pipefail

ROOT=/scratch/<netid>/<project>
STATE=$ROOT/.submit_state
USER_NAME=<netid>

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

get_id() { grep -E "^$1=" "$STATE" 2>/dev/null | tail -1 | cut -d= -f2; }
set_id() { echo "$1=$2" >> "$STATE"; }

need_id() {
  local name=$1
  local id=$(get_id "$name")
  if [[ -z $id ]]; then
    echo -e "${RED}  ERROR: no saved $name id in $STATE. Run the prior phase first.${NC}" >&2
    exit 1
  fi
  echo "$id"
}

sacct_state() {
  sacct -j "$1" -o State -X -n -P 2>/dev/null | head -1 | awk '{print $1}'
}

# Resolve "afterok:J1:J2:J3" -> a dep string safe against aged-out job IDs.
resolve_dep() {
  local raw=$1
  [[ -z $raw ]] && { echo ""; return; }
  local ids=${raw#*:}
  local keep=()
  local IFS=':'
  for jid in $ids; do
    [[ -z $jid ]] && continue
    local st
    st=$(sacct_state "$jid")
    case "$st" in
      COMPLETED)
        echo "    dep $jid: COMPLETED -> drop" >&2 ;;
      ""|UNKNOWN)
        echo "    dep $jid: no sacct record -> drop (assume terminal)" >&2 ;;
      PENDING|RUNNING|SUSPENDED|REQUEUED|RESIZING|CONFIGURING|COMPLETING)
        keep+=("$jid") ;;
      *)
        echo "    dep $jid: state=$st -> drop (downstream should check output-on-disk)" >&2 ;;
    esac
  done
  if [[ ${#keep[@]} -eq 0 ]]; then
    echo ""
  else
    local joined
    joined=$(IFS=:; echo "${keep[*]}")
    echo "afterany:$joined"   # afterany, not afterok: a TIMEOUT job may still have written usable output
  fi
}

submit() {
  local name=$1 raw_deps=$2 script=$3
  local deps
  deps=$(resolve_dep "$raw_deps")
  local args=(--parsable)
  [[ -n $deps ]] && args+=(--dependency="$deps")
  args+=("$script")
  local jid
  if ! jid=$(sbatch "${args[@]}" 2>&1); then
    echo -e "${RED}  $name FAILED: $jid${NC}" >&2
    return 1
  fi
  set_id "$name" "$jid"
  echo "  $name = $jid   ($script)   deps=${deps:-none}"
}

show_status() {
  echo -e "${YELLOW}==> Saved job IDs:${NC}"
  [[ -f $STATE ]] && cat "$STATE" || echo "  (no state file yet)"
  echo
  echo -e "${YELLOW}==> Current queue:${NC}"
  squeue -u "$USER_NAME" --format='%.10i %.18j %.10P %.6t %.10M %.10l %R' || true
}

clean_state() {
  if [[ -f $STATE ]]; then
    ids=$(cut -d= -f2 "$STATE" | tr '\n' ' ')
    [[ -n $ids ]] && { echo -e "${YELLOW}==> scancel $ids${NC}"; scancel $ids || true; }
    rm -f "$STATE"
    echo -e "${GREEN}  state cleared.${NC}"
  else
    echo "  no state file."
  fi
}

# ─── Example DAG — replace with your own phases/scripts ─────────────────────
phase=${1:-}
case "$phase" in
  1)
    : > "$STATE"
    submit STAGE1 "" stage1.sbatch
    ;;
  2)
    S1=$(need_id STAGE1)
    submit STAGE2A "afterok:$S1" stage2a.sbatch
    submit STAGE2B "afterok:$S1" stage2b.sbatch
    ;;
  3)
    S2A=$(need_id STAGE2A); S2B=$(need_id STAGE2B)
    submit STAGE3 "afterok:$S2A:$S2B" stage3.sbatch
    ;;
  status) show_status ;;
  clean)  clean_state ;;
  *)
    cat <<USAGE
Usage: bash submit_phased.sh <1|2|3|status|clean>
Edit the phase cases above to match your own job DAG.
USAGE
    exit 1
    ;;
esac
