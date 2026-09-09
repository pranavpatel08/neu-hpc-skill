---
name: neu-hpc
description: "End-to-end guide to running jobs on Northeastern University's Explorer HPC cluster with Slurm: SSH login, module system, conda/PyTorch environments, partitions and QOS limits, sbatch/srun, GPU jobs (H200/A100/V100), job arrays, dependencies, monitoring (seff/gpu-logs/historical-seff), storage quotas, data transfer via xfer node, containers, checkpointing, and troubleshooting. Use for any question about Explorer, NEU Research Computing, rc-docs.northeastern.edu, or submitting Slurm batch jobs."
trigger: /neu-hpc
---

# Northeastern Explorer HPC + Slurm

Everything needed to go from zero to a running GPU job on **Explorer**, Northeastern's HPC cluster, without reading the official docs first. Written against the live cluster (verified by direct `sinfo`/`sacctmgr`/`module` queries) and the official docs at `rc-docs.northeastern.edu`.

**Cluster at a glance**: Rocky Linux 9, Slurm 23.11.6, ~45,000 CPU cores, 525+ GPUs, 6 PB storage, InfiniBand (100/200 Gbps) on some nodes. Free to all NU faculty and students.

> **Numbers drift.** Partition limits, GPU inventory, and module versions change. Everything marked *(live)* was verified on **2026-09-08**. Before relying on a specific limit, run `templates/verify_cluster.sh` (or the commands in [§13](#13-verify-current-reality)). Treat this file as the map, not the territory.

---

## 1. Connect

```bash
ssh <username>@login.explorer.northeastern.edu        # <username> = first part of your NU email
ssh -Y <username>@login.explorer.northeastern.edu     # add -Y for X11 (MATLAB, Maestro GUIs)
```

Your password is your normal Northeastern password. You land on a login node (`explorer-01`/`explorer-02`).

**Set up passwordless SSH** (required for GUI apps to launch cleanly, and for any scripted or agent-driven workflow):

```bash
# On your laptop:
ssh-keygen -t rsa                 # press Enter at every prompt, no passphrase
ssh-copy-id -i ~/.ssh/id_rsa.pub <username>@login.explorer.northeastern.edu

# Then ON the cluster (separate step, needed for X11/GUI apps between cluster nodes):
ssh-keygen -t rsa
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
```

**Open OnDemand** (browser GUI: JupyterLab, RStudio, VSCode, MATLAB, Gaussian, Maestro, Unix Desktop): <https://ood.explorer.northeastern.edu>

:warning: **Never run compute on the login node.** Bots monitor login-node CPU use and email both you and RC. Get a compute node first (see [§5](#5-interactive-jobs-srun)).

---

## 2. Storage and quotas

| Path | Quota | Backed up? | Purpose |
|---|---|---|---|
| `/home/<username>` | **75 GB**, fixed, cannot be raised | Yes | Scripts, source, small files. Not data, not conda envs. |
| `/scratch/<username>` | Large (see Scratch Policy) | **No**, purged **monthly** | Temp/intermediate job output. Move anything you need out promptly. |
| `/projects/<name>` | Up to 35 TB free per PI | Yes | Group research data, conda envs, containers. PI must request it. |
| `/courses/<course>` | Course-managed | - | Course materials |

`/projects/foo` on Explorer is the same storage as `/work/foo` on Discovery.

**Check quotas** (run from a compute node, these are I/O heavy):

```bash
srun -p short --constraint=ib --pty bash      # get a compute node first
check-quota /home/$USER
check-quota /scratch/$USER
check-quota /projects/<dir>
```

**Find what is eating your home quota:**

```bash
du -shc .[^.]* ~/*        # per-file/dir sizes incl. hidden, total on last line
```

Usual culprits, in order:
1. `~/.local` from `pip install` outside a conda env. Fix: `mv ~/.local ~/.local-off` (check `squeue -u $USER` is empty first).
2. `~/.conda` environments. Fix: `conda clean --all`, and build future envs in `/projects` with `--prefix`.
3. `~/.apptainer` / `~/.singularity` container cache. Fix: `apptainer cache clean all`, set `APPTAINER_TMPDIR` to a `/projects` path.
4. `~/.cache`. Safe to clear when `squeue -u $USER` shows nothing running.

**A full `/home` is the single most common cause of weird failures**, especially Open OnDemand jobs that flip straight to `Completed` or throw "Disk quota exceeded".

---

## 3. Modules (software)

```bash
module avail                  # everything available
module avail cuda             # filter
module show cuda/12.8.0       # what it sets, and its dependencies
module load anaconda3/2024.06 cuda/12.8.0 cuDNN/9.10.2
module list                   # what is loaded now
module unload <mod>
module purge                  # unloads EVERYTHING (see warning)
module swap <a> <b>
```

:rotating_light: **`module purge` breaks internet access and the NEU helper commands.** The always-loaded `explorer/1.0` module sets `http_proxy`/`https_proxy` (compute nodes reach the internet only through that proxy) **and** puts `check-quota`, `gpu-logs`, `historical-seff`, `project`, `nodestat` on your `PATH`. If you purge, immediately run:

```bash
module load explorer
```

Always pin versions (`module load cuda/12.8.0`, not `module load cuda`); defaults change under you.

**Selected available modules** *(live, 2026-09-08)*:
`anaconda3/2024.06`, `miniconda3/24.11.1`, `miniconda3/25.9.1`, `python/3.13.5`, `cuda/12.1.1`, `cuda/12.3.0`, `cuda/12.8.0`, `cuda/13.2.0`, `cuDNN/9.10.2`, `OpenMPI/4.1.6`, `intel/compilers-2025.0.4`, `R/4.4.1`, `matlab/R2025b`, `gurobi/12.0.2`, `job-assist/1.0`, `rclone/1.72.0`, `code-server/4.109.5` (VSCode), `git/2.52.0`, `jq/1.7.1`, `ROCm/6.3.0`.

**Do not put `module load` lines in `.bashrc`.** They conflict with Open OnDemand apps and with other jobs. Put them in your sbatch script, or in a sourced env file:

```bash
# myenv.sh
module load anaconda3/2024.06 cuda/12.8.0 cuDNN/9.10.2
source activate /projects/<group>/envs/myenv
```
```bash
# inside your sbatch script
source myenv.sh
```

---

## 4. Python environments

**Build conda envs in `/projects`, not `/home`** (75 GB fills fast).

```bash
srun -p short --pty /bin/bash                 # compute node first
module load anaconda3/2024.06
conda create --prefix=/projects/<group>/envs/myenv python=3.11
source activate /projects/<group>/envs/myenv  # `source activate`, not `conda activate`
```

:rotating_light: **Never run `conda init`, and remove any `# >>> conda initialize >>>` block from `.bashrc`.** It breaks Open OnDemand apps and mixes environments. Activate inside the job instead.

**PyTorch with GPU support** (the officially supported path; the wheel index must match the CUDA module):

```bash
srun --partition=gpu-interactive --nodes=1 --gres=gpu:v100-sxm2:1 \
     --cpus-per-task=2 --mem=10GB --time=02:00:00 --pty /bin/bash
module load explorer anaconda3/2024.06 cuda/12.1.1
conda create --prefix=/projects/<group>/envs/torch -c conda-forge python=3.12 -y
source activate /projects/<group>/envs/torch
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
python -c 'import torch; print(torch.__version__, torch.cuda.is_available())'   # want True
```

TensorFlow:
```bash
pip install tensorflow[and-cuda]
python -c 'import tensorflow as tf; print(bool(tf.config.list_physical_devices("GPU")))'
```

Housekeeping: `conda env list`, `conda list --prefix <path>`, `conda clean --all`, `conda remove -p /path/envname --all`.

If an environment already works, **do not casually reinstall torch into it**; you can silently swap a working CUDA build for a CPU-only wheel. Re-run the `torch.cuda.is_available()` check after any change.

---

## 5. Interactive jobs (`srun`)

The standard "give me a compute node" incantation:

```bash
srun -p short --constraint=ib --pty bash
```

`--constraint=ib` requests an InfiniBand node (faster I/O, and RC's docs require it for `check-quota`, `historical-seff`, `gpu-logs`, and `project`).

More shaped requests:

```bash
# 1 node, 1 task, 30 min, 2 GB, with X11
srun --partition=short --nodes=1 --ntasks=1 --x11 --mem=2G --time=00:30:00 --pty /bin/bash

# 20 cores (10 tasks x 2 cpus), 40 GB, 1 hour
srun --partition=short --nodes=1 --ntasks=10 --cpus-per-task=2 --mem=40G --time=01:00:00 --pty /bin/bash

# Interactive GPU (use gpu-interactive, not gpu)
srun --partition=gpu-interactive --nodes=1 --ntasks=1 --gres=gpu:h200:1 \
     --mem=4GB --time=01:00:00 --pty /bin/bash
```

**`job-assist`** is an RC-built menu wizard that writes `srun`/`sbatch` commands for you:

```bash
module load job-assist
job-assist          # 1) default srun  2) interactive builder  3) generate an sbatch script
```

Interactive sessions die if your laptop sleeps or the network drops. For anything long, use `sbatch`.

---

## 6. Batch jobs (`sbatch`)

```bash
sbatch my_job.sbatch              # submit
sbatch --parsable my_job.sbatch   # print only the job ID (for scripting)
```

Annotated template:

```bash
#!/bin/bash
#SBATCH --job-name=my-job
#SBATCH --partition=short                 # short is the DEFAULT partition
#SBATCH --nodes=1                         # only >1 if your code is genuinely multi-node
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G                         # K/M/G/T. Default is only 2 GB per core
#SBATCH --time=04:00:00                   # HH:MM:SS. Job is killed at this limit
#SBATCH --constraint=ib                   # optional: InfiniBand node
#SBATCH --output=logs/%x-%j.out           # %x = job name, %j = job ID
#SBATCH --error=logs/%x-%j.err
#SBATCH --mail-user=<username>@northeastern.edu
#SBATCH --mail-type=END,FAIL              # or ALL

set -euo pipefail                         # so a Python crash fails the job instead of "COMPLETED"

module load anaconda3/2024.06
source activate /projects/<group>/envs/myenv

mkdir -p logs
python train.py
```

Key points:
- Default memory is **2 GB per allocated core**. Ask explicitly if you need more.
- `set -euo pipefail` matters: without it a mid-script failure still exits 0 and Slurm reports COMPLETED.
- Requesting more nodes/CPUs/time than you need makes you wait *longer* and does not speed anything up.
- Create the log directory before submitting, or Slurm silently drops output.

---

## 7. Partitions and limits

From the official partition tables plus live `sacctmgr`/`scontrol` values *(live, 2026-09-08)*.

### CPU partitions

| Partition | Approval | Time (default/max) | Running jobs | Submitted | Notes |
|---|---|---|---|---|---|
| `short` | No | 4 h / **48 h** | 50 | 1000 | **Default partition.** Max 2 nodes, 1024 cores, 25 TB RAM per user. |
| `long` | **Yes** | 1 d / 5 d | 25 | 1000 | Must show your code cannot checkpoint. |
| `sharing` | No | 30 m / 60 m | 2 | 4 | Huge node pool, tiny walltime. Good for quick tests. |
| `courses` | Course members | 4 h / 1 d | - | - | Course accounts only. |
| `debug`, `express` | No | 20 m / 60 m | 10 / 50 | - | Very short, high priority. |

### GPU partitions

| Partition | Approval | Time (default/max) | Running/Submitted | GPUs per job | GPUs per user |
|---|---|---|---|---|---|
| `gpu-short` | No | 1 h / **2 h** | 2 / 4 | 1 | 1 (live QOS shows 2) |
| `gpu-interactive` | No | 1 h / **2 h** | 2 / 4 | 1 | 1 |
| `gpu` | No | 4 h / **8 h** | 4 / 8 | **1** | 4 |
| `multigpu` | **Yes** | 4 h / **24 h** | 4 / 8 | 8 | 8 |
| `sharing` | No | 30 m / 60 m | 2 / 4 | 1 | 2 |

:rotating_light: **On `gpu`, `gpu-short`, and `gpu-interactive` you get exactly 1 GPU per job.** Asking for `--gres=gpu:2` makes the submission fail. Multi-GPU needs the `multigpu` partition, which needs approval.

You also **cannot request all the CPUs on a GPU node**; the rest are reserved for that node's other GPUs.

**GPU types** *(live)*. In the general `gpu` partition: `h200` (8/node, 144 GB), `a100` (3-4/node), `v100-sxm2` (3-4/node), `v100-pcie` (2/node), `t4` (4/node). The `sharing` partition adds `h100`, `a6000`, `a5000`, `l40`, `l40s`, `rtx6000`, `quadro`, `a30`, `p100`, `mi50` (AMD/ROCm).

Request a type with `--gres=gpu:<type>:1`, e.g. `--gres=gpu:h200:1`. Naming a type can mean a longer queue wait; omitting it (`--gres=gpu:1`) gets whatever frees up first.

### Getting `multigpu` or `long` access

Submit the HPC Partition Request form (<https://bit.ly/NURC-PartitionAccess>) and be ready to show scaling data. RC grants a temporary reservation, you time your job on 1/2/4/8 GPUs, and you must show **scaling efficiency above ~0.5** at your maximum GPU count. Test on V100s where you can: if it scales on V100s it will scale on A100s, and that conserves A100 time for everyone.

Under a reservation:
```bash
scontrol show reservation=<reservation_name>
srun -p reservation --reservation=<name> --gres=gpu:v100-sxm2:4 --time=24:00:00 -N 1 --pty /bin/bash
```

---

## 8. GPU jobs

```bash
#!/bin/bash
#SBATCH --job-name=gpu-train
#SBATCH --partition=gpu
#SBATCH --gres=gpu:h200:1          # exactly 1 on the gpu partition
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G                  # CPU RAM, not GPU VRAM
#SBATCH --time=08:00:00            # 8 h is the hard max on `gpu`
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err

set -euo pipefail
module load anaconda3/2024.06 cuda/12.8.0 cuDNN/9.10.2
source activate /projects/<group>/envs/torch

nvidia-smi -L                      # confirm you got the GPU you asked for
python train.py
```

**Find idle GPUs before queueing:**
```bash
sinfo -p gpu --Format=nodes,cpus,memory,features,statecompact,nodelist,gres
sinfo -p gpu -t idle --Format=gres,nodes
```

**Watch a running job's GPU:**
```bash
srun --jobid=<JID> --overlap nvidia-smi
```

### IdleBot will cancel your job

RC runs an **IdleBot** on all public GPU nodes. If your GPU sits under-utilized for **15 minutes** you get a warning email; at **1 hour** the job is **cancelled** to free the GPU.

This bites hardest in two cases: holding an interactive GPU session while you do something else, and a data-loading bottleneck starving the GPU. After a kill, a utilization plot lands in `/scratch/<user>/idle_bot_graphs/<job_id>.png`.

If utilization is low, fix the input pipeline (larger batch, `num_workers>0`, `pin_memory=True`, mixed precision) rather than hoping the bot does not notice.

---

## 9. Job arrays

The right tool for "same script, many inputs", and the sanctioned way around wall-time limits.

```bash
#!/bin/bash
#SBATCH --partition=short
#SBATCH --job-name=sweep
#SBATCH --array=1-600%20           # 600 tasks, at most 20 running at once
#SBATCH --output=logs/%A_%a.out    # %A = array job ID, %a = task index
#SBATCH --error=logs/%A_%a.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=2G

python run_one.py --index "$SLURM_ARRAY_TASK_ID"
```

:rotating_light: **Every `#SBATCH` resource directive applies per task, not to the array as a whole.** `--mem=128G` with 20 concurrent tasks means up to 20 x 128 GB in flight, not 128 GB shared.

- Max **50** concurrently running array tasks per user-account. Throttle with `%N`.
- `MaxArraySize` is 1001 *(live)*, so indices must stay below 1001.
- Index forms: `--array=1-5`, `--array=1,2,3,5,8`, `--array=1-200%5`.
- In Python, read the index with `os.environ["SLURM_ARRAY_TASK_ID"]`. (The official docs show `sys.getenv(...)`, which is not valid Python; `sys` has no `getenv`.)

---

## 10. Monitoring, efficiency, cancelling

```bash
squeue -u $USER                                                  # my queue
squeue -u $USER --format='%.10i %.18j %.10P %.6t %.10M %R'       # readable, with pending reason
squeue -p gpu                                                    # whole partition
sinfo -p gpu                                                     # node states

sacct -j <JID> --format=JobID,JobName,State,ExitCode,Start,End,Elapsed -X
sacct -u $USER --starttime 2026-09-01 --format=JobID,JobName,State,Elapsed -X

scancel <JID>
scancel -u $USER            # cancels ALL your jobs; think first
```

**Efficiency tooling** (RC-built; run the last two from a compute node):

```bash
seff <JID>                                     # CPU/memory efficiency of a finished job
historical-seff                                # this month's jobs: CPU, mem, GPU utilization
historical-seff --starttime 2026-08-01 --endtime 2026-09-01
gpu-logs <JID>                                 # per-5-min GPU utilization, last 7 days only
```

Run `seff` after any job you intend to repeat. Memory efficiency of 3% means you are requesting 30x the RAM you need and queueing far longer for it.

---

## 11. Dependencies and multi-stage pipelines

```bash
J1=$(sbatch --parsable stage1.sbatch)
J2=$(sbatch --parsable --dependency=afterok:$J1 stage2.sbatch)
```

Two traps that bite on Explorer specifically:

**1. Dependencies on aged-out job IDs fail.** `afterok:<JID>` needs the target still in the active queue. Completed jobs age out of `squeue` within hours, and a later `--dependency=afterok:<that ID>` is rejected with "Job dependency problem" even though the job succeeded. Resolve dependencies against `sacct` (not `squeue`) before submitting: drop `COMPLETED` targets entirely, and convert still-active ones to `afterany` so a TIMEOUT job that already wrote usable output does not block everything downstream. `templates/submit_phased.sh` implements this.

**2. QOS submit limits reject the tail of a large batch.** With `gpu` capped at 8 submitted / 4 running, firing a 10-job DAG at once gets the overflow rejected outright. Submit in phases, with a saved state file mapping job name to job ID.

If `squeue` shows `job violates accounting/QOS policy` while you are under your own limit, your whole **Slurm account** has hit the hard 10,000-job ceiling. Wait for jobs to drain.

---

## 12. Moving data

:rotating_light: **Laptop-to-cluster transfers must go through the dedicated transfer node**, not the login node:

```
<username>@xfer.discovery.neu.edu
```

(The hostname says "discovery"; it is the correct transfer node for Explorer too.)

```bash
# laptop -> cluster
scp data.csv <username>@xfer.discovery.neu.edu:/scratch/<username>/
rsync -avz ./mydir/ <username>@xfer.discovery.neu.edu:/scratch/<username>/mydir/

# cluster -> laptop
scp -r <username>@xfer.discovery.neu.edu:/scratch/<username>/results .
```

**Moving data *within* the cluster** needs a compute node (not the login node), ideally on InfiniBand:

```bash
srun -p short --constraint=ib --pty /bin/bash
rsync -av /scratch/$USER/out/ /projects/<group>/keep/
```

Other options: **Globus** for large or scheduled transfers (strongly recommended for anything big), `module load rclone/1.72.0` for Dropbox/Google Drive, OOD's File Explorer, and MobaXterm or FileZilla via SFTP to `xfer.discovery.neu.edu` on port 22.

:warning: **`rsync --delete` pushing laptop to cluster will delete cluster-only files.** Checkpoints, results, and logs generated on the cluster do not exist locally, so `--delete` removes them. Exclude generated directories from any `--delete` push: push code, never state. See `templates/transfer.sh`.

---

## 13. Verify current reality

Limits and inventory change. These commands regenerate every number in this file:

```bash
sinfo -o "%20P %5a %12l %10D %15G %10m %C"                    # partitions, time limits, GRES
scontrol show partition <name>                                 # authoritative per-partition config
sacctmgr show qos -P format=Name,MaxWall,MaxJobsPU,MaxSubmitPU,MaxTRESPU,MaxTRESPerJob,Priority
sacctmgr show assoc user=$USER -P format=Account,Partition,QOS,MaxJobs,MaxSubmit
sinfo -h -o "%G" | tr ',' '\n' | sort -u                       # every GPU type on the cluster
module avail                                                   # current software
scontrol show config | grep -iE "MaxArraySize|MaxJobCount"
```

`templates/verify_cluster.sh` runs all of these and prints a dated report.

Where the official docs and the live cluster disagree (for example `gpu-short` GPUs-per-user: docs say 1, live QOS says 2), the **live values decide what Slurm will actually accept**, but RC's published limits are what they support and may re-tighten.

---

## 14. Beating the wall clock: checkpointing

The `gpu` partition caps at 8 hours. Longer training must checkpoint and resume. The sanctioned pattern is a **serial job array**: N tasks, one at a time, each resuming from the last checkpoint.

```bash
#SBATCH --array=1-10%1        # 10 tasks, strictly one at a time
#SBATCH --time=08:00:00       # each task gets the full limit
```

Your script writes a checkpoint periodically and, on start, loads the most recent one if it exists. For PyTorch that means saving `model.state_dict()`, optimizer state, epoch, and RNG state, then reloading when a checkpoint file is present. `templates/checkpoint_array.sbatch` has a working skeleton.

Also: `/scratch` is purged monthly, so a long-running job writing checkpoints only to `/scratch` can lose its own restart state. Write checkpoints to `/projects`.

---

## 15. Containers

Apptainer is installed system-wide on every node (no module needed; `apptainer` and `singularity` are interchangeable).

```bash
srun -p short --constraint=ib --pty /bin/bash
apptainer run -B "/projects:/projects,/scratch:/scratch" \
  /shared/container_repository/explorer/<tool>/<image>.sif
```

Prebuilt images live in `/shared/container_repository/explorer/` (afni, amber, angsd, delft3d, fastsurfer, freesurfer, fsl, star, and more). Always `--bind` the filesystems you need; nothing outside the container is visible by default.

Pulling your own image fills `~/.apptainer` and your home quota. Redirect the cache first:

```bash
mkdir -p /projects/<group>/apptainer_tmp
export APPTAINER_TMPDIR=/projects/<group>/apptainer_tmp
export APPTAINER_CACHEDIR=/projects/<group>/apptainer_tmp
apptainer pull docker://<image>
```

---

## 16. Maintenance windows

- **Routine maintenance: the first Tuesday of every month.**
- **MGHPCC annual shutdown**: roughly 4 days, everything down, announced in advance.

Size `--time` so your job completes before a maintenance window starts; Slurm will not start a job that cannot finish first. Status updates are posted on the RC site.

---

## 17. Managing `/projects` membership (PIs and delegates)

Run from a compute node on `short`:

```bash
srun -p short --constraint=ib --pty bash
project <project_name> view members
project <project_name> add members <user1,user2>          # comma-separated, no spaces
project <project_name> remove members <user1>
project <project_name> view delegates|guests|groupemail|ttl
```

After being added to a project, **log out and back in**; Unix groups are assigned at login. Confirm with `groups`.

---

## 18. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| OOD job goes straight to `Completed`, or "Disk quota exceeded" | `/home` over 75 GB, or conda init in `.bashrc` | `check-quota /home/$USER`; clear `~/.local`, `~/.conda`, `~/.cache`; remove the conda init block |
| `pip`/`conda` hangs or cannot reach the internet on a compute node | `module purge` dropped the proxy | `module load explorer` |
| `check-quota: command not found` | Same as above | `module load explorer` |
| GPU request fails immediately | Asked for >1 GPU on `gpu`/`gpu-short`/`gpu-interactive` | Use `--gres=gpu:<type>:1`, or apply for `multigpu` |
| `QOSMaxSubmitJobPerUserLimit` | Over the partition's submitted-jobs cap | Submit in phases; see `templates/submit_phased.sh` |
| `job violates accounting/QOS policy` while under your limit | Slurm account hit the 10,000-job ceiling | Wait for jobs to drain |
| "Job dependency problem" on a job that succeeded | `afterok` target aged out of `squeue` | Resolve deps via `sacct` first |
| GPU job killed after ~1 h with no error | IdleBot cancelled it for low utilization | Check `/scratch/$USER/idle_bot_graphs/<jid>.png`; fix the input pipeline |
| `MODULE NOT FOUND` | Stale Discovery-era `module load` in `.bashrc` | Remove module loads from `.bashrc` |
| Job reports COMPLETED but produced nothing | No `set -e`; script failed but exited 0 | Add `set -euo pipefail` |
| Output file missing entirely | `--output` directory does not exist | `mkdir -p logs` before submitting |
| `Error: unable to open display` | Passwordless SSH not set up on the cluster itself | Regenerate keys, append to `~/.ssh/authorized_keys` on the cluster |
| OOD 504 error | Cached session | Open OOD in an incognito window, or clear cookies |
| OOD app will not launch | Web server wedged | "Restart Web Server" under the `?`/Develop menu in OOD |
| Job pending forever | Scarce GPU type, too many nodes, or too much time requested | Drop the type constraint, request less, check `sinfo -p <part> -t idle` |

**Getting help**: <rchelp@northeastern.edu> - RC office hours Wed 3-4 pm and Thu 11 am-12 pm (Teams) - docs at <https://rc-docs.northeastern.edu>

---

## Templates

| File | Purpose |
|---|---|
| `templates/gpu_job.sbatch` | Single-GPU training job on the `gpu` partition |
| `templates/cpu_job.sbatch` | CPU job on `short` |
| `templates/job_array.sbatch` | Parameter sweep with throttling |
| `templates/checkpoint_array.sbatch` | Serial array that resumes from checkpoints, to beat the 8 h GPU limit |
| `templates/conda_setup.sh` | Build a GPU-capable conda env in `/projects` the supported way |
| `templates/transfer.sh` | Safe push/pull through the xfer node |
| `templates/submit_phased.sh` | Multi-stage pipeline: `sacct` dependency resolution plus QOS-safe phasing |
| `templates/verify_cluster.sh` | Re-derive every limit in this document from the live cluster |

Replace `<username>`, `<group>`, and module versions before use.
