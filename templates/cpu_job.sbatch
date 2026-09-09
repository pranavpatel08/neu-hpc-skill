#!/bin/bash
# CPU job on Explorer's `short` partition (the default partition).
# Submit with: sbatch cpu_job.sbatch
#
# Partition choice:
#   short    4 h default / 48 h max, max 2 nodes, 50 running jobs   <- default choice
#   debug    20 min max, high priority                              <- quick sanity checks
#   express  60 min max, high priority
#   sharing  60 min max, huge node pool                             <- when short is busy
#   long     1 d / 5 d, REQUIRES APPROVAL (must show you cannot checkpoint)

#SBATCH --job-name=cpu-job
#SBATCH --partition=short
#SBATCH --nodes=1                      # only >1 if your code is genuinely multi-node
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G                      # default is only 2G per allocated core
#SBATCH --time=04:00:00
#SBATCH --constraint=ib                # InfiniBand node: faster I/O
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err
#SBATCH --mail-user=CHANGEME@northeastern.edu   # your NU email
#SBATCH --mail-type=END,FAIL

set -euo pipefail

# ---------------- EDIT THIS ----------------
GROUP=CHANGEME              # your PI's /projects directory name, e.g. mylab -> /projects/mylab
# -------------------------------------------
if [[ "$GROUP" == CHANGEME* ]]; then
  echo "Edit GROUP at the top of $0 before submitting." >&2; exit 1
fi


module load anaconda3/2024.06
source activate /projects/${GROUP}/envs/myenv

mkdir -p logs
echo "==> start $(date) on $(hostname)"

python my_script.py

echo "==> done $(date)"
# Afterwards: `seff $SLURM_JOB_ID`. If memory efficiency is a few percent, request less
# next time; over-requesting only makes you queue longer.
