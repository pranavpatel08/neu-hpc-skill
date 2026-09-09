#!/bin/bash
# Job array: same script, many inputs. Submit with: sbatch job_array.sbatch
#
# %20 caps how many run at once. Every resource line below applies PER TASK,
# so --mem=8G with %20 means up to 160 GB in flight, not 8 GB shared.
# Max 50 running array tasks per user-account. Indices must stay below 1001.
# Read the index in Python with os.environ["SLURM_ARRAY_TASK_ID"].

#SBATCH --job-name=sweep
#SBATCH --partition=short
#SBATCH --array=1-600%20
#SBATCH --nodes=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=2G
#SBATCH --time=2:00:00
#SBATCH --output=array_%A_%a.out

module load anaconda3/2024.06

source /scratch/$USER/myproject/venv/bin/activate
cd /scratch/$USER/myproject || exit 1

python run_one.py --index "$SLURM_ARRAY_TASK_ID"
