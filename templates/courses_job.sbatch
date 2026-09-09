#!/bin/bash
# Job on the course partitions. Submit with: sbatch courses_job.sbatch
#
# courses      4 h default / 24 h max, 50 running jobs, 256 GB RAM cap
# courses-gpu  4 h default /  8 h max,  2 running jobs,  12 GB RAM cap, --gres=gpu:1
#
# The 12 GB cap on courses-gpu is CPU memory, not GPU memory, and it is the usual
# reason a student's job dies. Keep dataloader workers and batch prefetch modest.
#
# See what the term's allocation actually is:
#   sinfo -p courses-gpu --Format=nodes,cpus,gres,statecompact

#SBATCH --job-name=hw1
#SBATCH --partition=courses-gpu
#SBATCH --gres=gpu:1
#SBATCH --nodes=1
#SBATCH --mem=12G
#SBATCH --time=4:00:00

module load anaconda3/2024.06

# Shared class environment built by the instructor, or your own under students/.
source activate /courses/CS7150.202710/shared/envs/classenv
cd /courses/CS7150.202710/students/$USER || exit 1

python assignment.py

# Cancel interactive sessions when you finish. Only 2 GPU jobs run per user and the
# term allocation is shared with the whole class.
