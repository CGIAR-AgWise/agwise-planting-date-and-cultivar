#!/usr/bin/env bash
# Run this ON CGLabs.
#
# Uploads whatever is staged under ~/blob_stage/ (built by
# stage_bias_correction_data.sh and/or stage_soil_data.sh) to Azure Blob,
# under a PREFIX - not at the container's bare root - since this is a shared
# account with other unrelated containers/data. The container is a general
# shared cache ("agwise-cache") holding multiple AgWise pipelines' data,
# each grouped under its own prefix: this data_sourcing upload defaults to
# the "agwise-cache" prefix too, while this DSSAT repo's own inputs/outputs/
# results (a later, separate upload) use "agwise-planting-date-and-cultivar/"
# instead - kept separate since other DSSAT pipelines may exist later.
#
# The relative path AFTER the prefix mirrors CGLabs's own
# Global_GeoData/ layout exactly - Processed/ and Landing/ as siblings:
#   ~/blob_stage/Processed/harmonized/chirps_v3/rg_27_m4_32_0/PRCP/Daily_PRCP_1993.nc
#     -> agwise-cache/Processed/harmonized/chirps_v3/rg_27_m4_32_0/PRCP/Daily_PRCP_1993.nc
#   ~/blob_stage/Landing/Soil/soilGrids/profile/clay_0-5cm_mean_30s.tif
#     -> agwise-cache/Landing/Soil/soilGrids/profile/clay_0-5cm_mean_30s.tif
# That match matters: once "agwise-cache/Processed" is mounted as
# AGWISE_DATA_ROOT and "agwise-cache/Landing" as AGWISE_LOCAL_ROOT
# (blobfuse2's `subdirectory` option mounts a prefix as the filesystem
# root, not necessarily the whole container - two separate mounts, one per
# env var), config.py's harmonized_path()/local_file() need to find files
# at exactly these paths with zero translation.
#
# Usage:
#   ./upload_blob_stage.sh [container_name] [prefix]
# Defaults: container "agwise-cache" (created if it doesn't exist yet - a
# NEW, dedicated container, not one of the pre-existing ones), prefix
# "agwise-cache" (same name - deliberate, see above).
set -euo pipefail

STAGE_ROOT="$HOME/blob_stage"
CONTAINER="${1:-agwise-cache}"
PREFIX="${2:-agwise-cache}"

# --- isolated venv so we don't touch the shared agwise_data conda env ---
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

python3 - "$STAGE_ROOT" "$CONTAINER" "$PREFIX" <<'PY'
import os
import sys
from pathlib import Path
from azure.storage.blob import BlobServiceClient

local_root = Path(sys.argv[1])
container_name = sys.argv[2]
prefix = sys.argv[3]

conn_str = os.environ["BLOB_STRING"]
client = BlobServiceClient.from_connection_string(conn_str)

container_client = client.get_container_client(container_name)
if not container_client.exists():
    print(f"Creating container '{container_name}'...")
    container_client.create_container()

files = [f for f in local_root.rglob("*") if f.is_file()]
print(f"Uploading {len(files)} files to '{container_name}/{prefix}/'...")

for f in files:
    blob_path = f"{prefix}/{f.relative_to(local_root).as_posix()}"
    with open(f, "rb") as data:
        container_client.upload_blob(name=blob_path, data=data, overwrite=True)
    print("  uploaded:", blob_path)

print("Done.")
PY

deactivate
