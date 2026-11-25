#!/usr/bin/env bash
# Move data between your laptop and Explorer.
#
# RULE: laptop <-> cluster transfers go through the DEDICATED TRANSFER NODE,
#       xfer.discovery.neu.edu, never the login node. (The hostname says
#       "discovery"; it is the correct transfer node for Explorer too.)
#
# For cluster-internal copies, get a compute node first (never the login node):
#       srun -p short --constraint=ib --pty /bin/bash
#       rsync -av /scratch/$USER/out/ /projects/${GROUP}/keep/
#
# For very large or scheduled transfers, use Globus instead of this script.
#
# Usage: ./transfer.sh push | pull
set -euo pipefail

# ---------------- EDIT THESE ----------------
USERNAME=CHANGEME            # your NU username (first part of your northeastern.edu email)
PROJECT=CHANGEME             # your project dir under /scratch/<username>/
# --------------------------------------------
if [[ "$USERNAME" == CHANGEME* || "$PROJECT" == CHANGEME* ]]; then
  echo "Edit USERNAME and PROJECT at the top of $0 first." >&2; exit 1
fi

# Needs the RC-issued key via ~/.ssh/config (SKILL.md §1); passwords and self-made keys stopped working 2026-11-06.
XFER=${USERNAME}@xfer.discovery.neu.edu
REMOTE_CODE=/scratch/${USERNAME}/${PROJECT}/code
REMOTE_RESULTS=/scratch/${USERNAME}/${PROJECT}/results
LOCAL_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

usage() { echo "Usage: $0 <push|pull>"; exit 1; }
[[ $# -eq 1 ]] || usage

case "$1" in
  push)
    # --delete keeps the remote tree identical to local. That is exactly why the
    # excludes below are mandatory: checkpoints, results and logs are generated ON
    # the cluster and never exist locally, so without excludes --delete erases them.
    # Push code, never state.
    rsync -avz --delete \
      --exclude 'checkpoints/' \
      --exclude 'checkpoints_*/' \
      --exclude 'results/' \
      --exclude 'logs/' \
      --exclude '__pycache__/' \
      --exclude '.git/' \
      --exclude '*.pt' \
      --exclude '*.ckpt' \
      "${LOCAL_ROOT}/code/" "${XFER}:${REMOTE_CODE}/"
    ;;
  pull)
    mkdir -p "${LOCAL_ROOT}/results" "${LOCAL_ROOT}/logs/hpc"
    rsync -avz "${XFER}:${REMOTE_RESULTS}/"                       "${LOCAL_ROOT}/results/"
    rsync -avz "${XFER}:/scratch/${USERNAME}/${PROJECT}/logs/"     "${LOCAL_ROOT}/logs/hpc/"
    ;;
  *) usage ;;
esac

# Single files:
#   scp data.csv ${XFER}:/scratch/${USERNAME}/
#   scp -r ${XFER}:/scratch/${USERNAME}/results .
#
# Remember /scratch is purged MONTHLY and is not backed up. Anything you need to
# keep belongs in /projects.
