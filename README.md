# neu-hpc-skill

A complete, working guide to running jobs on **Explorer**, Northeastern University's HPC
cluster, packaged as a [Claude Code](https://claude.com/claude-code) skill so an AI agent
can drive the cluster for you without being fed the docs first.

It is also just a good cheat-sheet. Read [`SKILL.md`](./SKILL.md) directly if you do not
use Claude Code.

Every partition limit, GPU type, and module version here was **verified against the live
cluster** (`sinfo`, `sacctmgr`, `scontrol`, `module avail`) on 2026-09-08, then
cross-checked against the official docs at
[rc-docs.northeastern.edu](https://rc-docs.northeastern.edu). Where the two disagree, the
file says so. The CUDA and driver claims come from **real GPU jobs** run on a T4 node and
an H200 node, not from reading docs.

## Install

```bash
git clone https://github.com/pranavpatel08/neu-hpc-skill.git
bash neu-hpc-skill/install.sh
```

That copies `SKILL.md` and `templates/` into `~/.claude/skills/neu-hpc/`. Start a new
Claude Code session and either type `/neu-hpc` or just ask a question ("how do I get an
H200 for 6 hours?") and it will load automatically.

Uninstall: `rm -rf ~/.claude/skills/neu-hpc`

## What it covers

Connecting with the RC-issued SSH key (required since 2026-11-06) - storage layout and the 75 GB `/home` quota - the module
system - conda and venv environments, GPU-enabled PyTorch, and what the `cuda` modules do
and do not affect - partitions, QOS limits and which one to pick - `srun` and `sbatch` -
GPU jobs, GPU type selection, VRAM sizes and `--constraint` - job arrays - job
dependencies - monitoring with `squeue`/`sacct`/`seff`/`historical-seff`/`gpu-logs` -
data transfer through the `xfer` node - Apptainer containers - checkpointing to beat the
8 hour GPU limit - the `courses`/`courses-gpu` partitions and the `/courses` layout for
instructors and students - maintenance windows - a troubleshooting table for the errors
people actually hit.

## Templates

| File | Purpose |
|---|---|
| [`gpu_job.sbatch`](./templates/gpu_job.sbatch) | Single-GPU job on the `gpu` partition |
| [`cpu_job.sbatch`](./templates/cpu_job.sbatch) | CPU job on `short` |
| [`courses_job.sbatch`](./templates/courses_job.sbatch) | Job on `courses` / `courses-gpu` |
| [`job_array.sbatch`](./templates/job_array.sbatch) | Parameter sweep with concurrency throttling |
| [`checkpoint_array.sbatch`](./templates/checkpoint_array.sbatch) | Serial array that resumes from checkpoints, for runs longer than 8 h |
| [`conda_setup.sh`](./templates/conda_setup.sh) | Build a GPU-capable conda env in `/projects` the supported way |
| [`transfer.sh`](./templates/transfer.sh) | Safe push/pull through `xfer.discovery.neu.edu` |
| [`submit_phased.sh`](./templates/submit_phased.sh) | Multi-stage pipelines: `sacct` dependency resolution plus QOS-safe phasing |
| [`verify_cluster.sh`](./templates/verify_cluster.sh) | Re-derive every limit in the docs from the live cluster |

The `.sbatch` templates are deliberately minimal (directives, modules, activate, `cd`, run)
and use `$USER` so paths work unedited. The helper `.sh` scripts have a `CHANGEME` block at
the top and refuse to run until you edit it.

[`reference/cluster_snapshot_2026-09-08.txt`](./reference/cluster_snapshot_2026-09-08.txt)
is the raw output of `verify_cluster.sh`, kept so you can diff the cluster against a known
state later.

## Check the numbers yourself

Limits get retuned and hardware gets retired. Before trusting a specific number:

```bash
ssh <username>@login.explorer.northeastern.edu 'bash -l -s' < templates/verify_cluster.sh
```

## Things that cost people the most time

A short version of what is in the troubleshooting table:

- **`/home` is capped at 75 GB and cannot be raised.** A full home breaks Open OnDemand in
  confusing ways. Conda envs belong in `/projects`, not `/home`.
- **`module purge` kills internet access on compute nodes.** The `explorer` module carries
  the HTTP proxy and the `check-quota`/`gpu-logs` helpers. `module load explorer` to fix.
- **You get exactly 1 GPU per job** on `gpu`, `gpu-short`, and `gpu-interactive`. More
  needs the `multigpu` partition, which needs an approved application.
- **IdleBot cancels idle GPU jobs after an hour.** Do not park an interactive GPU session.
- **Transfers go through `xfer.discovery.neu.edu`,** not the login node.
- **`/scratch` is purged monthly** and is not backed up. If your conda env or venv lives
  there, the purge deletes it and your job scripts start failing in a confusing way:
  `source .../bin/activate` on a missing path fails quietly and `python` falls back to the
  module interpreter. Keep environments in `/projects`.
- **The `cuda` module version does not decide whether your GPU works.** Measured: a
  pip-installed torch wheel ran fine on the GPU with `cuda/12.1.1`, `12.3.0`, `12.8.0`,
  `13.2.0`, and with no cuda module at all. What binds is the driver (`570.86.15`, CUDA
  ≤12.8), so use `cu121`/`cu124`/`cu128` wheels and **not** `cu13x`.

## Contributing

Corrections welcome, especially when RC changes limits. If a number here is stale, run
`verify_cluster.sh` and open a PR with the new value.

Not an official Northeastern Research Computing product. For support, email
<rchelp@northeastern.edu>.

## License

MIT
