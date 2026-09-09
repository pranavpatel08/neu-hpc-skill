#!/bin/bash
# Annotated single-GPU job template.
# Adapt: job-name, partition, gres GPU type, cpus/mem/time, module versions, paths.

#SBATCH --job-name=my-job
#SBATCH --partition=gpu
#SBATCH --gres=gpu:h200:1
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=08:00:00
#SBATCH --output=/scratch/<netid>/<project>/logs/%x-%j.out
#SBATCH --error=/scratch/<netid>/<project>/logs/%x-%j.err

set -euo pipefail

module load anaconda3/2024.06
module load cuda/12.8.0
module load cuDNN/9.10.2
source /scratch/<netid>/<project>/venv/bin/activate

cd /scratch/<netid>/<project>/code
mkdir -p logs results

echo "==> job start $(date)"
nvidia-smi -L

PYTHONUNBUFFERED=1 python train.py --your-args-here

echo "==> job done $(date)"
