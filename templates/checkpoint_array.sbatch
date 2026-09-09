#!/bin/bash
# Train for longer than the 8 h GPU limit: a serial array where each segment
# resumes from the last checkpoint. Submit with: sbatch checkpoint_array.sbatch
#
# --array=1-10%1 runs 10 segments strictly one at a time, 8 h each, so ~80 h total.
# Slurm queues the next segment automatically when one ends.
#
# train.py must load the newest checkpoint on start if one exists, and save
# periodically. Write checkpoints to /projects, not /scratch: /scratch is purged
# monthly and a long chain can outlive a purge and lose its own restart state.

#SBATCH --job-name=ckpt-train
#SBATCH --partition=gpu
#SBATCH --gres=gpu:h200:1
#SBATCH --array=1-10%1
#SBATCH --nodes=1
#SBATCH --mem=24G
#SBATCH --time=8:00:00
#SBATCH --output=ckpt_%A_%a.out

module load anaconda3/2024.06
module load cuda/12.3.0
module load cuDNN/9.10.2

source /scratch/$USER/myproject/venv/bin/activate
cd /scratch/$USER/myproject || exit 1

python train.py --ckpt-dir /projects/mygroup/checkpoints/$SLURM_JOB_NAME --max-hours 7.5

# Minimal resume pattern inside train.py:
#   ckpts = sorted(glob.glob(os.path.join(ckpt_dir, "ckpt_*.pt")))
#   if ckpts:
#       state = torch.load(ckpts[-1], map_location="cuda", weights_only=True)
#       model.load_state_dict(state["model"]); opt.load_state_dict(state["optim"])
#       start_epoch = state["epoch"] + 1
#   torch.save({...}, tmp); os.replace(tmp, final)   # atomic, so a kill mid-save
#                                                    # cannot leave a truncated file
