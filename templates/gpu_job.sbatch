#!/bin/bash
# Single-GPU job on Northeastern's Explorer cluster.
# Submit with: sbatch gpu_job.sbatch
#
# Partition choice:
#   gpu             4 h default / 8 h max, 1 GPU per job, 4 GPUs per user  <- most training
#   gpu-short       1 h / 2 h, higher priority, shorter queue              <- quick runs
#   gpu-interactive 1 h / 2 h, for srun sessions and Open OnDemand
#   multigpu        4 h / 24 h, up to 8 GPUs, REQUIRES APPROVAL
#
# GPU types on the `gpu` partition: h200, a100, v100-sxm2, v100-pcie, t4.
# Drop the type (--gres=gpu:1) to take whatever frees up first.

#SBATCH --job-name=gpu-train
#SBATCH --partition=gpu
#SBATCH --gres=gpu:h200:1              # exactly 1: >1 fails on the gpu partition
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8              # do NOT request all CPUs on the node
#SBATCH --mem=64G                      # CPU RAM, not GPU VRAM. Default is 2G per core
#SBATCH --time=08:00:00                # hard max on the gpu partition
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
                      # without this, a Python crash still reports COMPLETED

module load anaconda3/2024.06 cuda/12.8.0 cuDNN/9.10.2
source activate /projects/${GROUP}/envs/torch

mkdir -p logs
echo "==> start $(date) on $(hostname)"
nvidia-smi -L                          # confirm the GPU you asked for

python -c 'import torch; assert torch.cuda.is_available(), "no CUDA"; print(torch.cuda.get_device_name(0))'

python train.py

echo "==> done $(date)"
# Afterwards: `seff $SLURM_JOB_ID` for CPU/mem efficiency, `gpu-logs $SLURM_JOB_ID` for GPU use.
# Keep the GPU busy: IdleBot warns at 15 min idle and cancels the job at 1 hour.
