#!/usr/bin/env bash
# Run this ON CGLabs.
#
# Deletes every blob under a given prefix in a container. Use to clean up
# stale/superseded uploads - e.g. the old flat "harmonized/" prefix from
# before the Processed//Landing/ restructure.
#
# Usage:
#   ./delete_blob_prefix.sh <container> <prefix>
# Example:
#   ./delete_blob_prefix.sh agwise-cache harmonized/
set -euo pipefail

CONTAINER="${1:?Usage: $0 <container> <prefix>}"
PREFIX="${2:?Usage: $0 <container> <prefix>}"

python3 -m venv "$HOME/blob_upload_venv" 2>/dev/null || true
source "$HOME/blob_upload_venv/bin/activate"
pip install --quiet azure-storage-blob

set -a
source "$HOME/secrets.env"
set +a

python3 - "$CONTAINER" "$PREFIX" <<'PY'
import os
import sys
from azure.storage.blob import BlobServiceClient

container_name = sys.argv[1]
prefix = sys.argv[2]

conn_str = os.environ["BLOB_STRING"]
client = BlobServiceClient.from_connection_string(conn_str)
cc = client.get_container_client(container_name)

blobs = list(cc.list_blobs(name_starts_with=prefix))
print(f"Found {len(blobs)} blobs under '{container_name}/{prefix}'")
for b in blobs:
    cc.delete_blob(b.name)
    print("  deleted:", b.name)

print("Done.")
PY

deactivate
