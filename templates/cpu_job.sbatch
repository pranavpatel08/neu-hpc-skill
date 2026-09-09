#!/bin/bash
# CPU job on `short`, the default partition (4 h default / 48 h max, max 2 nodes).
# Submit with: sbatch cpu_job.sbatch
#
# --cpus-per-task defaults to 1. Memory defaults to 2 GB per allocated core,
# so ask explicitly if you need more.

#SBATCH --job-name=cpu-job
#SBATCH --partition=short
#SBATCH --nodes=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=4:00:00

module load anaconda3/2024.06

source /scratch/$USER/myproject/venv/bin/activate
cd /scratch/$USER/myproject || exit 1

python my_script.py
