#!/usr/bin/env bash
# Re-derive every partition/QOS/GPU/module fact in SKILL.md from the live cluster.
# Run this before trusting any specific number in the docs: RC retunes limits and
# retires hardware without warning.
#
# On the cluster (login node is fine, everything here is read-only and cheap):
#   bash verify_cluster.sh
#
# From your laptop, without copying the file over:
#   ssh <username>@login.explorer.northeastern.edu 'bash -l -s' < verify_cluster.sh
#
# Save a dated snapshot to compare against later:
#   bash verify_cluster.sh > cluster_$(date +%Y-%m-%d).txt

echo "########## SNAPSHOT $(date -u +%Y-%m-%dT%H:%M:%SZ) ##########"
echo "host: $(hostname)   user: ${USER}"
cat /etc/redhat-release 2>/dev/null
sinfo --version

echo
echo "########## PARTITIONS: availability, time limit, GPUs, memory, cores ##########"
sinfo -o "%20P %5a %12l %10D %15G %10m %C"

echo
echo "########## PARTITION CONFIG (defaults, max time, node caps) ##########"
scontrol show partition 2>/dev/null | grep -E "PartitionName|Default=|DefaultTime|MaxTime|MaxNodes|TotalNodes|State="

echo
echo "########## QOS LIMITS (the caps that actually reject your sbatch) ##########"
echo "MaxJobsPU = max running per user | MaxSubmitPU = max queued+running per user"
echo "MaxTRESPU = max resources across your jobs | MaxTRES = max per single job"
sacctmgr show qos -P format=Name,MaxWall,MaxJobsPU,MaxSubmitPU,MaxTRESPU,MaxTRESPerJob,Priority

echo
echo "########## MY ACCOUNTS AND ASSOCIATIONS ##########"
sacctmgr show assoc user="${USER}" -P format=Account,User,Partition,QOS,MaxJobs,MaxSubmit,GrpTRES
echo "unix groups: $(groups)"

echo
echo "########## GPU TYPES PRESENT ON THE CLUSTER ##########"
sinfo -h -o "%G" | tr ',' '\n' | sed 's/(.*)//' | sort -u | grep -v '^(null)$'

echo
echo "########## GPU NODES BY PARTITION ##########"
sinfo -N -o "%20N %16P %6c %10m %28f %24G" | grep -v "(null)" | sort -k6

echo
echo "########## IDLE GPU NODES RIGHT NOW ##########"
for p in gpu gpu-short gpu-interactive; do
  echo "--- $p ---"
  sinfo -p "$p" -t idle --Format=nodelist:20,gres:24,statecompact:10 2>/dev/null | head -12
done

echo
echo "########## SCHEDULER LIMITS ##########"
scontrol show config 2>/dev/null | grep -iE "MaxArraySize|MaxJobCount|SchedulerType|SelectType|PriorityType|GresTypes"

echo
echo "########## STORAGE ##########"
df -h /home /scratch 2>/dev/null
echo "(run check-quota /home/\$USER from a compute node for real quota numbers:"
echo "  srun -p short --constraint=ib --pty bash )"

echo
echo "########## KEY MODULES ##########"
module avail anaconda3 miniconda3 python cuda cuDNN 2>&1 | grep -v "^$"

echo
echo '########## RC HELPER COMMANDS (provided by the explorer module) ##########'
for t in check-quota historical-seff gpu-logs project nodestat seff sacct sinfo apptainer; do
  p=$(command -v "$t" 2>/dev/null) && echo "  present: $t -> $p" || echo "  MISSING: $t  (try: module load explorer)"
done

echo
echo "########## MY CURRENT JOBS ##########"
squeue -u "${USER}" --format='%.10i %.20j %.16P %.8T %.10M %.10l %R' 2>/dev/null

echo
echo "########## END SNAPSHOT ##########"
