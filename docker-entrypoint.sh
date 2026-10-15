#!/usr/bin/env bash
# Entrypoint wrapper: mounts the shared Azure Blob cache via blobfuse2 (two
# separate mounts, matching CGLabs's own Global_GeoData/{Processed,Landing}
# sibling layout - see agwise-data-naming/containerization-status notes),
# then execs the real pipeline entrypoint.
#
# Needs BLOB_NAME + BLOB_STRING (a connection string) in the environment,
# and the container run with FUSE privileges:
#   --cap-add SYS_ADMIN --security-opt apparmor:unconfined --device /dev/fuse
# (confirmed sufficient locally - no need for full --privileged)
#
# If BLOB_NAME/BLOB_STRING aren't set, skips mounting entirely and just runs
# the pipeline against whatever AGWISE_DATA_ROOT/AGWISE_LOCAL_ROOT already
# point at (e.g. a local bind mount, or nothing - matching current
# no-blob-mount default behavior).
set -euo pipefail

BLOB_CONTAINER="${BLOB_CONTAINER:-agwise-cache}"
BLOB_PREFIX="${BLOB_PREFIX:-agwise-cache}"

mount_blob_subdir() {
  local subdir="$1" mount_point="$2" label="$3"
  mkdir -p "$mount_point" "/mnt/fuse_cache_$label" /var/log
  cat > "/tmp/bf2_${label}.yaml" <<EOF
logging:
  type: base
  level: log_debug
  file-path: /var/log/blobfuse2_${label}.log
components: [libfuse, file_cache, attr_cache, azstorage]
file_cache:
  path: /mnt/fuse_cache_$label
  timeout-sec: 120
azstorage:
  type: block
  account-name: $BLOB_NAME
  container: $BLOB_CONTAINER
  mode: key
  account-key: $ACCOUNT_KEY
  subdirectory: $subdir
EOF
  blobfuse2 mount "$mount_point" --config-file="/tmp/bf2_${label}.yaml"
  echo "Mounted $subdir at $mount_point (log: /var/log/blobfuse2_${label}.log)" >&2
}

if [ -n "${BLOB_NAME:-}" ] && [ -n "${BLOB_STRING:-}" ]; then
  ACCOUNT_KEY=$(echo "$BLOB_STRING" | grep -oE "AccountKey=[^;]+" | cut -d= -f2-)

  DATA_MOUNT="${AGWISE_DATA_ROOT:-/mnt/agwise_data_root}"
  LOCAL_MOUNT="${AGWISE_LOCAL_ROOT:-/mnt/agwise_local_root}"

  mount_blob_subdir "$BLOB_PREFIX/Processed" "$DATA_MOUNT" "data_root"
  mount_blob_subdir "$BLOB_PREFIX/Landing" "$LOCAL_MOUNT" "local_root"

  export AGWISE_DATA_ROOT="$DATA_MOUNT"
  export AGWISE_LOCAL_ROOT="$LOCAL_MOUNT"
else
  echo "BLOB_NAME/BLOB_STRING not set - skipping blob mount, running against local paths only" >&2
  export AGWISE_DATA_ROOT="${AGWISE_DATA_ROOT:-/mnt/agwise_data_root}"
  export AGWISE_LOCAL_ROOT="${AGWISE_LOCAL_ROOT:-/mnt/agwise_local_root}"
fi

START_EPOCH=$(date +%s)
echo "=== Pipeline starting at $(date -u) ===" >&2

set +e
Rscript usecases/run_usecase.R "$@"
RC=$?
set -e

END_EPOCH=$(date +%s)
echo "=== Pipeline finished at $(date -u), exit code $RC, elapsed $((END_EPOCH - START_EPOCH))s ===" >&2

for log in /var/log/blobfuse2_data_root.log /var/log/blobfuse2_local_root.log; do
  if [ -f "$log" ]; then
    echo "--- $log: $(wc -l < "$log") lines, op counts: ---" >&2
    grep -oE '\] [A-Za-z]+::[A-Za-z]+' "$log" | sort | uniq -c | sort -rn | head -20 >&2
  fi
done

exit "$RC"
