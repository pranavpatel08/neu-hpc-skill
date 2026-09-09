#!/bin/bash
# Beat the wall clock: a SERIAL job array where each task resumes from the last
# checkpoint. This is the sanctioned way to run training longer than a partition's
# time limit (8 h on `gpu`) without applying for the `long`/`multigpu` partitions.
#
# --array=1-10%1 means 10 tasks run strictly one after another, each up to 8 h,
# giving ~80 h of cumulative training. Slurm queues the next task automatically.
#
# Submit with: sbatch checkpoint_array.sbatch

#SBATCH --job-name=ckpt-train
#SBATCH --partition=gpu
#SBATCH --gres=gpu:h200:1
#SBATCH --array=1-10%1                 # 10 sequential segments, ONE at a time
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=08:00:00                # per task
#SBATCH --output=logs/%x-%A_%a.out
#SBATCH --error=logs/%x-%A_%a.err

set -euo pipefail

# ---------------- EDIT THIS ----------------
GROUP=CHANGEME              # your PI's /projects directory name, e.g. mylab -> /projects/mylab
# -------------------------------------------
if [[ "$GROUP" == CHANGEME* ]]; then
  echo "Edit GROUP at the top of $0 before submitting." >&2; exit 1
fi


module load anaconda3/2024.06 cuda/12.8.0 cuDNN/9.10.2
source activate /projects/${GROUP}/envs/torch

# Write checkpoints to /projects, NOT /scratch: /scratch is purged monthly and a
# long chain of segments can outlive a purge and lose its own restart state.
CKPT_DIR=/projects/${GROUP}/checkpoints/${SLURM_JOB_NAME}
mkdir -p "$CKPT_DIR" logs

echo "==> segment ${SLURM_ARRAY_TASK_ID} starting $(date)"
nvidia-smi -L

# train.py must:
#   1. On start, load the newest file in --ckpt-dir if one exists, else start fresh.
#   2. Periodically save model + optimizer + epoch + RNG state.
#   3. Exit 0 when its time budget is nearly spent (leave a margin so the save completes),
#      or simply exit when the epoch budget for this segment is done.
python train.py --ckpt-dir "$CKPT_DIR" --max-hours 7.5

echo "==> segment ${SLURM_ARRAY_TASK_ID} done $(date)"

# Minimal PyTorch pattern inside train.py:
#
#   import os, glob, torch
#   ckpts = sorted(glob.glob(os.path.join(ckpt_dir, "ckpt_*.pt")))
#   start_epoch = 0
#   if ckpts:
#       state = torch.load(ckpts[-1], map_location="cuda", weights_only=True)
#       model.load_state_dict(state["model"])
#       optimizer.load_state_dict(state["optim"])
#       start_epoch = state["epoch"] + 1
#       torch.set_rng_state(state["rng"])
#   ...
#   torch.save({"model": model.state_dict(), "optim": optimizer.state_dict(),
#               "epoch": epoch, "rng": torch.get_rng_state()},
#              os.path.join(ckpt_dir, f"ckpt_{epoch:04d}.pt"))
#
# Write to a temp file and os.replace() it so a job killed mid-save cannot leave
# a truncated checkpoint that breaks the next segment.
