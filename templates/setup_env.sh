#!/usr/bin/env bash
# Defensive dependency setup for a Slurm-cluster venv.
#
# Strategy:
#   1. Load cluster modules, activate the venv.
#   2. NEVER touch torch/tensorflow — they're paired with the CUDA module.
#      Reinstalling from PyPI risks silently breaking (or downgrading) GPU support.
#   3. For every other required package: check if importable; if not, pip
#      install it into the venv.
#   4. Finish with a smoke-test import of everything the project needs.
#
# Adapt: ROOT, module versions, the DEPS list, and the final smoke-test import list.
set -euo pipefail

ROOT=/scratch/<netid>/<project>
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

module load anaconda3/2024.06 cuda/12.8.0 cuDNN/9.10.2 2>/dev/null || true
source "$ROOT/venv/bin/activate"

echo -e "${YELLOW}==> Probing existing env...${NC}"
python --version

# (import name, pip spec)
DEPS=(
  "numpy       numpy>=1.24,<2.3"
  "pandas      pandas>=2.0"
  "scipy       scipy>=1.10"
  "sklearn     scikit-learn>=1.3"
  "matplotlib  matplotlib>=3.7"
)

echo
echo -e "${YELLOW}==> Torch check (NEVER auto-reinstalled — managed by the cluster's CUDA module)${NC}"
if python -c "import torch; print(f'  torch={torch.__version__} cuda={torch.cuda.is_available()}')" 2>/dev/null; then
  echo -e "  ${GREEN}torch OK${NC}"
else
  echo -e "  ${RED}torch MISSING or broken — STOP. Do not pip install torch here; get cluster support.${NC}"
  exit 1
fi

echo
echo -e "${YELLOW}==> Checking other deps...${NC}"
for entry in "${DEPS[@]}"; do
  mod=$(echo "$entry" | awk '{print $1}')
  pkg=$(echo "$entry" | awk '{print $2}')
  if python -c "import $mod" 2>/dev/null; then
    echo -e "  ${GREEN}present:${NC} $mod"
  else
    echo -e "  ${RED}missing:${NC} $mod — installing $pkg"
    pip install --quiet "$pkg"
  fi
done

echo
echo -e "${YELLOW}==> Final smoke test...${NC}"
python - <<'EOF'
fail = []
for m in ["numpy", "pandas", "scipy", "sklearn", "matplotlib", "torch"]:
    try:
        __import__(m)
    except Exception as e:
        fail.append((m, str(e)))
if fail:
    for m, e in fail:
        print(f"  FAIL {m}: {e}")
    raise SystemExit(1)
print("  All required modules import cleanly.")
EOF

echo -e "${GREEN}==> Environment ready.${NC}"
