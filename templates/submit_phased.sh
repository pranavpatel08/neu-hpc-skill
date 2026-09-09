#!/usr/bin/env bash
# Multi-stage Slurm pipeline driver for Explorer.
#
# Solves the two failure modes that break naive `sbatch --dependency` pipelines here:
#
#   1. QOS SUBMIT LIMITS. The `gpu` partition allows only 8 submitted and 4 running
#      jobs per user (`gpu-short`/`gpu-interactive`: 4 and 2). Firing a whole DAG at
#      once gets the tail rejected with QOSMaxSubmitJobPerUserLimit. This script
#      submits in small phases instead.
#
#   2. DEPENDENCIES ON AGED-OUT JOB IDS. `--dependency=afterok:<JID>` is rejected with
#      "Job dependency problem" once the target has aged out of the active queue,
#      which happens within hours of completion even for jobs that succeeded.
#      resolve_dep() checks sacct and drops or downgrades each dependency instead of
#      passing raw IDs through.
#
# Usage:
#   bash submit_phased.sh 1        # submit phase 1
#   bash submit_phased.sh 2        # submit phase 2 (once phase 1 has finished)
#   bash submit_phased.sh one B1   # re-run a single job with no dependencies
#   bash submit_phased.sh status   # saved job IDs + current queue
#   bash submit_phased.sh clean    # scancel everything saved, clear state
#
# Adapt ROOT, the job-name -> script mapping, and the phase cases at the bottom.
set -euo pipefail

PROJECT=CHANGEME             # your project dir under /scratch/$USER/
if [[ "$PROJECT" == CHANGEME* ]]; then
  echo "Edit PROJECT at the top of $0 first." >&2; exit 1
fi

ROOT=/scratch/${USER}/${PROJECT}
SLURM_DIR=${ROOT}/slurm
STATE=${ROOT}/.submit_state

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

get_id() { grep -E "^$1=" "$STATE" 2>/dev/null | tail -1 | cut -d= -f2; }
set_id() { echo "$1=$2" >> "$STATE"; }

need_id() {
  local id
  id=$(get_id "$1")
  if [[ -z $id ]]; then
    echo -e "${RED}  ERROR: no saved $1 id in $STATE. Run the earlier phase first.${NC}" >&2
    exit 1
  fi
  echo "$id"
}

sacct_state() { sacct -j "$1" -o State -X -n -P 2>/dev/null | head -1 | awk '{print $1}'; }

# "afterok:J1:J2" -> a dependency string Slurm will actually accept.
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
        echo "    dep $jid: no sacct record (aged out) -> drop" >&2 ;;
      PENDING|RUNNING|SUSPENDED|REQUEUED|RESIZING|CONFIGURING|COMPLETING)
        keep+=("$jid") ;;
      *)
        # FAILED / TIMEOUT / CANCELLED / OUT_OF_MEMORY: drop and warn. Downstream
        # scripts should gate on whether their input exists on disk, and a TIMEOUT
        # job often wrote usable output before being killed.
        echo "    dep $jid: state=$st -> drop (downstream must check its input on disk)" >&2 ;;
    esac
  done
  if [[ ${#keep[@]} -eq 0 ]]; then
    echo ""
  else
    local joined
    joined=$(IFS=:; echo "${keep[*]}")
    # afterany, not afterok: a TIMEOUT job that still produced output should not
    # permanently block the rest of the pipeline.
    echo "afterany:$joined"
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
  echo -e "  ${GREEN}$name${NC} = $jid   ($script)   deps=${deps:-none}"
}

show_status() {
  echo -e "${YELLOW}==> Saved job IDs:${NC}"
  [[ -f $STATE ]] && cat "$STATE" || echo "  (no state file yet)"
  echo
  echo -e "${YELLOW}==> Current queue:${NC}"
  squeue -u "${USER}" --format='%.10i %.20j %.16P %.8T %.10M %.10l %R' || true
}

clean_state() {
  if [[ -f $STATE ]]; then
    local ids
    ids=$(cut -d= -f2 "$STATE" | tr '\n' ' ')
    if [[ -n ${ids// /} ]]; then
      echo -e "${YELLOW}==> scancel $ids${NC}"
      scancel $ids || true
    fi
    rm -f "$STATE"
    echo -e "${GREEN}  state cleared.${NC}"
  else
    echo "  no state file."
  fi
}

# job name -> sbatch script
script_for() {
  case "$1" in
    A)  echo "${SLURM_DIR}/a_prepare.sbatch" ;;
    B1) echo "${SLURM_DIR}/b1_train.sbatch" ;;
    B2) echo "${SLURM_DIR}/b2_train.sbatch" ;;
    C)  echo "${SLURM_DIR}/c_evaluate.sbatch" ;;
    *)  return 1 ;;
  esac
}

case "${1:-}" in
  1)
    : > "$STATE"                                   # phase 1 starts a fresh run
    echo -e "${YELLOW}==> Phase 1: A${NC}"
    submit A "" "$(script_for A)"
    echo "   When A completes: bash $0 2"
    ;;
  2)
    A=$(need_id A)
    echo -e "${YELLOW}==> Phase 2: B1, B2 (after A=$A)${NC}"
    submit B1 "afterok:$A" "$(script_for B1)"
    submit B2 "afterok:$A" "$(script_for B2)"
    echo "   When B1/B2 complete: bash $0 3"
    ;;
  3)
    B1=$(need_id B1); B2=$(need_id B2)
    echo -e "${YELLOW}==> Phase 3: C (after B1=$B1, B2=$B2)${NC}"
    submit C "afterok:$B1:$B2" "$(script_for C)"
    ;;
  one)
    name=${2:-}
    script=$(script_for "$name") || { echo -e "${RED}usage: $0 one <A|B1|B2|C>${NC}"; exit 1; }
    echo -e "${YELLOW}==> Re-running $name with no dependencies${NC}"
    submit "$name" "" "$script"
    ;;
  status) show_status ;;
  clean)  clean_state ;;
  *)
    cat <<USAGE
Usage: bash submit_phased.sh <1|2|3|one <JOB>|status|clean>

  1        submit phase 1
  2        submit phase 2 (after phase 1 finishes)
  3        submit phase 3
  one <J>  re-run a single job with no dependencies
  status   saved job IDs + squeue
  clean    scancel saved jobs and clear state

State file: $STATE
USAGE
    exit 1
    ;;
esac
