# hpc-slurm

A field-tested reference for submitting, monitoring, and debugging Slurm batch jobs on
academic HPC clusters — SSH login nodes, the module system, `sbatch`/`squeue`/`sacct`,
GPU partitions, job dependency chains, QOS submit limits, and `rsync` sync patterns.

Written from real experience on **Northeastern University's Explorer cluster**, but the
workflow generalizes to most Slurm clusters (other universities, XSEDE/ACCESS, etc.) —
swap the hostname, module versions, and partition names for your own.

## Install as a Claude Code skill

```bash
git clone https://github.com/pranavpatel08/hpc-slurm-notes.git
bash hpc-slurm-notes/install.sh
```

This copies `SKILL.md` and `templates/` into `~/.claude/skills/hpc-slurm/`. Start a new
Claude Code session and invoke it with `/hpc-slurm`, or just ask Claude an HPC/Slurm
question — it's discoverable automatically once installed.

No Claude Code? The content is plain markdown — just read [`SKILL.md`](./SKILL.md) directly,
or copy the scripts in [`templates/`](./templates) and adapt the placeholders
(`<netid>`, `<project>`, module versions, partition/GPU names) to your cluster.

## What's in here

- [`SKILL.md`](./SKILL.md) — the full reference: connecting, environment/module setup,
  sbatch anatomy, submitting/monitoring, dependency chains, QOS limits, rsync sync
  patterns, and a checklist of common traps that cost real GPU-hours to discover.
- [`templates/example.sbatch`](./templates/example.sbatch) — annotated single-GPU job template.
- [`templates/setup_env.sh`](./templates/setup_env.sh) — defensive venv dependency
  check-and-install pattern (never touches the cluster's torch/CUDA build).
- [`templates/submit_phased.sh`](./templates/submit_phased.sh) — phased multi-job
  submission with `sacct`-based dependency resolution (works around jobs aging out of
  `squeue` and QOS submit-limit rejections).
- [`templates/sync.sh`](./templates/sync.sh) — push/pull `rsync` wrapper with safe
  excludes (won't let a `--delete` push nuke cluster-only checkpoints/results).

## Why this exists

Slurm's own docs explain the commands; they don't explain the failure modes you only
discover after losing hours of GPU time — a stale-results skip-gate, an `afterok`
dependency that ages out, a `--delete` rsync eating a checkpoint. This is the trap list,
written down once so the next project doesn't relearn it.

## License

MIT — use, adapt, share.
