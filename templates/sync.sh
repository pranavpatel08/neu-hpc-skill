#!/usr/bin/env bash
# rsync push/pull wrapper for a local <-> HPC-scratch workflow.
#
# Trap this avoids: `rsync --delete` on push deletes HPC-only artifacts
# (checkpoints, results, logs) that were generated on the cluster and never
# existed locally — because --delete treats "not present locally" as "should
# be deleted remotely." Excluding generated-on-cluster dirs from the push is
# the fix; push should sync *code*, never *state*.
#
# Adapt: HOST, REMOTE_ROOT, LOCAL_ROOT, and the exclude list.
set -euo pipefail

HOST=<netid>@login.explorer.northeastern.edu
REMOTE_ROOT=/scratch/<netid>/<project>
LOCAL_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

usage() { echo "Usage: $0 <push|pull>"; exit 1; }
[[ $# -eq 1 ]] || usage

case "$1" in
  push)
    rsync -avz --delete \
      --exclude 'checkpoints/' \
      --exclude 'checkpoints_*/' \
      --exclude 'results/' \
      --exclude 'logs/' \
      --exclude '__pycache__/' \
      --exclude '.git/' \
      "$LOCAL_ROOT/code/" "$HOST:$REMOTE_ROOT/code/"
    ;;
  pull)
    rsync -avz \
      "$HOST:$REMOTE_ROOT/code/results/" "$LOCAL_ROOT/results/"
    rsync -avz \
      "$HOST:$REMOTE_ROOT/code/logs/" "$LOCAL_ROOT/logs/hpc/"
    ;;
  *) usage ;;
esac
