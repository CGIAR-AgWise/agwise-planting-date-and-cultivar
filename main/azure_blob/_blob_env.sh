# Sourced (not run) by the scripts in this folder.
#
# Activates an isolated venv with azure-storage-blob (so the shared
# agwise_data conda env is untouched) and loads the connection string from
# your own secret file, never shared/committed:
#   echo 'BLOB_STRING="<connection string>"' > ~/secrets.env
#   (quotes around the value matter - this file gets `source`d as bash, and
#   an unquoted connection string's `;` separators get parsed as separate
#   commands, silently truncating BLOB_STRING at the first one)
#   chmod 600 ~/secrets.env
# BLOB_STRING is also exported as AZURE_STORAGE_CONNECTION_STRING, the name
# upload_to_blob.py reads.

python3 -m venv "$HOME/blob_upload_venv" 2>/dev/null || true
source "$HOME/blob_upload_venv/bin/activate"
pip install --quiet azure-storage-blob

set -a
source "$HOME/secrets.env"
set +a
export AZURE_STORAGE_CONNECTION_STRING="${AZURE_STORAGE_CONNECTION_STRING:-$BLOB_STRING}"
