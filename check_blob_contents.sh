#!/usr/bin/env bash
# Run this ON CGLabs (or anywhere ~/secrets.env exists).
#
# Lists Azure Blob containers, or the blobs inside one (optionally filtered
# by a name prefix).
#
# Usage:
#   ./check_blob_contents.sh                              # list all containers
#   ./check_blob_contents.sh agwise-cache                 # list all blobs in it
#   ./check_blob_contents.sh agwise-cache agwise-cache    # filter by prefix
set -euo pipefail

CONTAINER="${1:-}"
PREFIX="${2:-}"

python3 -m venv "$HOME/blob_upload_venv" 2>/dev/null || true
source "$HOME/blob_upload_venv/bin/activate"
pip install --quiet azure-storage-blob

# Your own secret file, never shared/committed:
#   echo 'BLOB_STRING="<connection string>"' > ~/secrets.env
#   (quotes around the value matter - this file gets `source`d as bash, and
#   an unquoted connection string's `;` separators get parsed as separate
#   commands, silently truncating BLOB_STRING at the first one)
#   chmod 600 ~/secrets.env
set -a
source "$HOME/secrets.env"
set +a

python3 - "$CONTAINER" "$PREFIX" <<'PY'
import os
import sys
from azure.storage.blob import BlobServiceClient

container = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else None
prefix = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None

conn_str = os.environ["BLOB_STRING"]
client = BlobServiceClient.from_connection_string(conn_str)

if not container:
    print("Containers:")
    for c in client.list_containers():
        print(" -", c.name)
    sys.exit(0)

cc = client.get_container_client(container)
if not cc.exists():
    print(f"Container '{container}' does not exist.")
    sys.exit(1)

blobs = list(cc.list_blobs(name_starts_with=prefix))
label = f"{container}/{prefix or ''}"
print(f"{label}: {len(blobs)} blobs")
total_mb = 0.0
for b in blobs:
    mb = b.size / 1024 / 1024
    total_mb += mb
    print(f"  {b.name}  ({mb:.1f} MB)")
print(f"Total: {total_mb:.1f} MB")
PY

deactivate
