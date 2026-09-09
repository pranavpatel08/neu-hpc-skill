#!/bin/bash
# Single-GPU job. Edit the paths and the python line, then: sbatch gpu_job.sbatch
# Output lands in slurm-<jobid>.out in the directory you submit from.
#
# partition=gpu is 4 h default / 8 h max and gives exactly 1 GPU per job.
# For quick runs use gpu-short (2 h max, higher priority, shorter queue).
# GPU types: h200 (144 GB), a100 (40 or 80 GB), v100-sxm2 / v100-pcie (16 or 32 GB), t4 (16 GB).

#SBATCH --job-name=train
#SBATCH --partition=gpu
#SBATCH --gres=gpu:h200:1
#SBATCH --nodes=1
#SBATCH --mem=24G
#SBATCH --time=7:00:00

module load anaconda3/2024.06
module load cuda/12.3.0
module load cuDNN/9.10.2

source /scratch/$USER/myproject/venv/bin/activate
cd /scratch/$USER/myproject || exit 1

python train.py
