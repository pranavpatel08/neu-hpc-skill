#!/bin/bash
# Job array: run the same script over many inputs/parameters.
# Submit with: sbatch job_array.sbatch
#
# CRITICAL: every resource directive below applies PER TASK, not to the array.
# --mem=8G with %20 concurrency means up to 20 x 8G = 160G in flight.
#
# Limits on Explorer:
#   - 50 concurrently RUNNING array tasks per user-account (throttle with %N)
#   - MaxArraySize = 1001, so indices must stay below 1001

#SBATCH --job-name=sweep
#SBATCH --partition=short
#SBATCH --array=1-600%20               # 600 tasks, at most 20 running at once
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=2G
#SBATCH --time=02:00:00
#SBATCH --output=logs/%x-%A_%a.out     # %A = array job ID, %a = task index
#SBATCH --error=logs/%x-%A_%a.err

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
echo "==> task ${SLURM_ARRAY_TASK_ID} of array ${SLURM_ARRAY_JOB_ID} on $(hostname)"

# Pass the task index into your program. In Python read it with
#   os.environ["SLURM_ARRAY_TASK_ID"]
# (NOT sys.getenv, which does not exist.)
python run_one.py --index "${SLURM_ARRAY_TASK_ID}"

# Alternative: map the index to a line in a parameter file.
#   PARAM=$(sed -n "${SLURM_ARRAY_TASK_ID}p" params.txt)
#   python run_one.py $PARAM

# Other index forms:
#   --array=1-5            5 tasks
#   --array=1,2,3,5,8      explicit list
#   --array=1-200%5        200 tasks, 5 at a time
