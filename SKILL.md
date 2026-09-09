---
name: hpc-slurm
description: "Submit, monitor, and debug Slurm batch jobs on academic HPC clusters (SSH login nodes, module system, sbatch/squeue/sacct, GPU partitions, job dependencies, QOS limits, rsync sync patterns). Reference implementation: Northeastern University's Explorer cluster, but the concepts generalize to any Slurm cluster."
trigger: /hpc-slurm
---

# /hpc-slurm

A field-tested reference for working with Slurm-based academic HPC clusters — written from real experience running GPU training pipelines on **Northeastern University's Explorer cluster**, but the workflow (module system, sbatch anatomy, dependency chains, QOS limits, rsync patterns) generalizes to most Slurm clusters (XSEDE/ACCESS, university clusters, etc.).

Use this when you need to: SSH into a login node, request GPU/CPU resources, write an sbatch script, chain jobs with dependencies, avoid the QOS submit-limit trap, sync code/data to scratch, or debug why a job silently produced stale results.

## 1. Connecting

```bash
ssh <netid>@login.explorer.northeastern.edu   # NEU Explorer; swap hostname for your cluster
```

Set up key-based auth (`ssh-copy-id` or paste your pubkey into the cluster's account portal) so scripts and CI don't need interactive passwords.

**Filesystem layout convention** (true on most academic clusters):
- `/home/<netid>/` — small quota, backed up, NOT for large data or checkpoints.
- `/scratch/<netid>/` — large quota, NOT backed up, purged after inactivity (Explorer: ~30-90 days). This is where your actual project, venv, checkpoints, and results should live.

## 2. Environment setup

Academic clusters expose software via **environment modules**, not system packages:

```bash
module avail                       # list everything installable
module load anaconda3/2024.06      # exact version strings vary by cluster/date
module load cuda/12.8.0
module load cuDNN/9.10.2
```

**Golden rule: never `pip install` or reinstall `torch`/`tensorflow` inside a module-managed env.** The cluster's GPU framework build is compiled against a specific CUDA module version. A PyPI reinstall silently breaks GPU support (falls back to CPU, or ImportErrors on the compiled ops). If you need extra Python packages, create/activate a venv on top of the module's Python and `pip install` only the packages you need — verify torch still sees the GPU afterward:

```bash
python -c "import torch; print(torch.__version__, torch.cuda.is_available())"
```

See `templates/setup_env.sh` for a defensive pattern: probe each dependency, install only what's missing, treat torch specially (fail loudly, never auto-reinstall), and run a final smoke-test import of everything your code needs.

## 3. Anatomy of an sbatch script

```bash
#!/bin/bash
#SBATCH --job-name=my-job
#SBATCH --partition=gpu                    # cluster-specific partition name
#SBATCH --gres=gpu:h200:1                  # request 1 GPU of a specific type
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=08:00:00                    # HH:MM:SS — jobs get killed at this wall time
#SBATCH --output=/scratch/<netid>/proj/logs/%x-%j.out
#SBATCH --error=/scratch/<netid>/proj/logs/%x-%j.err

set -euo pipefail
module load anaconda3/2024.06 cuda/12.8.0 cuDNN/9.10.2
source /scratch/<netid>/proj/venv/bin/activate
cd /scratch/<netid>/proj/code

nvidia-smi -L                              # sanity: confirm you got the GPU you asked for
python train.py --args...
```

Notes:
- `%x` = job name, `%j` = job ID — use both in log paths so logs from different runs/jobs don't clobber each other.
- `set -euo pipefail` so a mid-script Python crash actually fails the job instead of Slurm reporting COMPLETED on a partial run.
- Always run `nvidia-smi -L` (or `-L` + `nvidia-smi` after your framework initializes) early — confirms both that you got a GPU and which type, since `--gres` typos fail silently on some cluster configs.

Check available partitions and GPU types for your account — they're cluster- and allocation-specific:

```bash
sinfo -o "%P %G %D %l"     # partitions, GRES (GPU types), node count, time limit
```

## 4. Submitting and monitoring

```bash
sbatch my_job.sbatch                  # submit
sbatch --parsable my_job.sbatch       # submit, print only the job ID (for scripting)

squeue -u <netid>                                              # your jobs
squeue -u <netid> --format='%.10i %.18j %.10P %.6t %.10M %R'   # readable columns

sacct -u <netid> --starttime 2026-09-01 --format=JobID,JobName,State,Elapsed -X   # history
sacct -j <JID> --format=JobID,JobName,State,ExitCode,Start,End,Elapsed -X          # one job

scancel <JID>                          # kill a job
scancel -u <netid>                     # kill ALL your jobs — confirm before running this

# Attach to a running job's GPU for live debugging (Slurm overlap):
srun --jobid=<JID> --overlap nvidia-smi
```

## 5. Job dependencies (chaining a pipeline)

```bash
J1=$(sbatch --parsable stage1.sbatch)
J2=$(sbatch --parsable --dependency=afterok:$J1 stage2.sbatch)
```

**Trap: `afterok`/`afterany` deps require the target job ID to still be in the active queue.** Completed jobs age out of `squeue` within hours (cluster-dependent); a `--dependency=afterok:<JID>` referencing an aged-out ID fails immediately with "Job dependency problem" — even though the job actually completed successfully.

**Mitigation pattern**: before submitting a dependent job, check the target's state via `sacct` (not `squeue`) and resolve accordingly:
- `COMPLETED` → drop the dependency entirely (nothing to wait for).
- `PENDING`/`RUNNING`/etc. → keep it, but as `afterany` rather than `afterok` — this way a job that hit its time limit but still wrote a usable partial result doesn't permanently block downstream stages that check for output-on-disk anyway.
- `FAILED`/`TIMEOUT`/`CANCELLED`/no sacct record → drop with a warning; let the downstream script's own "does my input file exist" check be the real gate.

See `templates/submit_phased.sh` for a full working implementation of this (`resolve_dep()` function) plus a state file that survives across separate `bash submit.sh <phase>` invocations, so you can drive a multi-stage pipeline without keeping a single long-lived script alive.

## 6. QOS / submit limits

Most academic clusters cap **concurrent submitted+pending+running jobs per user** (`QOSMaxSubmitJobPerUserLimit` or similar). Firing off a 10+ job DAG at once gets the tail rejected outright.

**Pattern**: submit in phases of ≤3-5 jobs, gated on the previous phase's completion, using a saved state file (job name → job ID) so each phase can look up what it depends on. Check your limit empirically — `sacct`/cluster docs rarely state it explicitly; you usually discover it the first time a submission is rejected mid-batch.

## 7. Syncing code/data (rsync)

```bash
# push (local → HPC scratch)
rsync -avz --delete \
  --exclude 'checkpoints/' --exclude 'results/' --exclude '__pycache__/' \
  ./code/ <netid>@login.explorer.northeastern.edu:/scratch/<netid>/proj/code/

# pull (HPC → local)
rsync -avz \
  <netid>@login.explorer.northeastern.edu:/scratch/<netid>/proj/code/results/ ./results/
```

**Trap: `rsync --delete` on push deletes HPC-only artifacts your local copy never had** — checkpoints, results, and logs that only ever existed on the cluster (generated there, never pulled down) get nuked because `--delete` treats "not present locally" as "should be deleted remotely." This can destroy hours of GPU compute in one sync.

**Always exclude generated-on-cluster directories from a `--delete` push**: checkpoints, results, logs, any experiment output directory. Push should sync *code*, not *state*.

## 8. Common traps checklist

Generalized from repeated real incidents — read before a rerun, not after:

1. **SKIP-on-exists silently returns stale results.** A common pattern is `if output_path.exists(): skip`. If you ever stage reference/placeholder outputs (e.g., a collaborator's prior results as fallback), a fresh rerun will see the file, skip, and silently keep the old numbers. Before trusting "fast" job completion, check output file *mtimes* against your expected run date. If a script writes multiple artifacts per unit of work, the skip-gate must check **all** of them, not just the first — a script that "completed" but only wrote json and not npz will silently short-circuit the npz-dependent step on the next run.
2. **GPU defaults leave the card idle.** Small `batch_size`, `num_workers=0`, no mixed precision (`autocast`/`GradScaler`) on modern GPUs (H100/H200/A100) can leave utilization under 40% and VRAM under 5%. Bump batch size, set `num_workers>0` with `pin_memory=True`, and enable AMP — verify the accuracy delta is within your run-to-run variance before trusting the speedup.
3. **Expensive shared computations deserve a disk cache.** If multiple jobs in a pipeline recompute the same baseline/preprocessing step, write it once to disk with an atomic pattern (`write to .tmp.<pid>`, then `os.replace`) so concurrent jobs don't race or corrupt a partial write.
4. **Import-order and `try/except ImportError` fallbacks fail silently.** A module-swap pattern (saving/restoring `sys.modules[...]`) is order-sensitive — importing things in a different order than the original author assumed can silently substitute the wrong module. Similarly, a `try: import optional_dep / except ImportError: skip` branch means a missing package in the venv silently disables a whole code path with no error — just a quieter result. Grep for `except ImportError` in any pipeline you didn't write yourself and check each one is either loud or provably harmless.
5. **Smoke tests at toy scale miss target-scale numerical failures.** A test with `y ~ N(0, 1)` can pass while production data at `y ~ O(10^4)` overflows an exponential, a softmax, or an unscaled loss term. Write smoke tests using realistic target magnitudes, not convenient toy ones.
6. **`stage`/one-time setup steps are not idempotent-safe to rerun.** If a setup step stages reference artifacts with `cp -n` (no-clobber), rerunning it after you've already produced fresh results does nothing harmful — but rerunning a *non*-`-n` variant, or one that also re-copies environment files, can silently revert local edits. Know which of your setup steps are safe to rerun and which are one-time-only.

## 9. Quick reference

```bash
# Queue + state
squeue -u <netid> --format='%.10i %.18j %.10P %.6t %.10M %R'
sacct -u <netid> --starttime <YYYY-MM-DD> --format=JobID,JobName,State,Elapsed -X

# Live GPU check on a running job
srun --jobid=<JID> --overlap nvidia-smi

# Partitions/GPU types available to your account
sinfo -o "%P %G %D %l"

# Cancel
scancel <JID>
```

## Templates

- `templates/example.sbatch` — annotated single-GPU job template.
- `templates/setup_env.sh` — defensive venv/module dependency check-and-install pattern.
- `templates/submit_phased.sh` — phased multi-job submission with `sacct`-based dependency resolution, QOS-safe batching, and a persistent state file.
- `templates/sync.sh` — push/pull rsync wrapper with safe excludes.

These are starting points, not drop-in scripts — cluster names, partitions, GPU types, module versions, and paths are specific to your allocation and must be adapted.
