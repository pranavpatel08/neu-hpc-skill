#!/usr/bin/env bash
# Build a GPU-capable conda environment on Explorer, the way NEU RC supports.
#
# Run this ON A COMPUTE NODE, not the login node:
#   srun --partition=gpu-interactive --nodes=1 --gres=gpu:v100-sxm2:1 \
#        --cpus-per-task=2 --mem=10GB --time=02:00:00 --pty /bin/bash
#   bash conda_setup.sh
#
# Why /projects and not /home: /home is capped at 75 GB and cannot be raised.
# A couple of deep-learning envs will fill it and then Open OnDemand apps start
# failing with "Disk quota exceeded".
set -euo pipefail

GROUP=CHANGEME                                 # your PI's /projects directory name
if [[ "$GROUP" == CHANGEME* ]]; then
  echo "Edit GROUP at the top of $0 first." >&2; exit 1
fi

ENV_PATH=/projects/${GROUP}/envs/torch
PY_VERSION=3.12
CUDA_MODULE=cuda/12.1.1                        # must match the wheel index below
TORCH_INDEX=https://download.pytorch.org/whl/cu121

# `explorer` provides the http_proxy that compute nodes need to reach the internet,
# plus check-quota/gpu-logs/historical-seff/project on PATH. If you ever `module purge`,
# reload it or pip will hang with no explanation.
module load explorer
module load anaconda3/2024.06 "${CUDA_MODULE}"

echo "==> creating ${ENV_PATH}"
mkdir -p "$(dirname "${ENV_PATH}")"
conda create --prefix="${ENV_PATH}" -c conda-forge python="${PY_VERSION}" -y

# `source activate`, not `conda activate`: conda is not initialised in your shell
# (and it should not be, see below).
source activate "${ENV_PATH}"

echo "==> installing PyTorch against ${CUDA_MODULE}"
pip install --quiet torch torchvision torchaudio --index-url "${TORCH_INDEX}"

echo "==> verifying GPU visibility"
python - <<'PY'
import torch
print(f"torch   {torch.__version__}")
print(f"cuda    {torch.version.cuda}")
print(f"visible {torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"device  {torch.cuda.get_device_name(0)}")
else:
    raise SystemExit("CUDA not visible: check you are on a GPU node and the cuda module matches the wheel")
PY

echo "==> done. Activate later with:"
echo "    module load anaconda3/2024.06 ${CUDA_MODULE}"
echo "    source activate ${ENV_PATH}"

# NEVER run `conda init`. It writes a '# >>> conda initialize >>>' block into
# ~/.bashrc that breaks Open OnDemand apps and mixes environments across jobs.
# If you already have one, delete that block from ~/.bashrc.
#
# Housekeeping when /home fills up:
#   conda clean --all
#   conda env list
#   conda remove -p /path/envname --all
#   mv ~/.local ~/.local-off          # stray `pip install --user` packages
