#!/usr/bin/env python3
"""
CLI to upload a file or a whole directory tree to an Azure Blob Storage container.

Connection string is read from AZURE_STORAGE_CONNECTION_STRING, falling back
to BLOB_STRING (the name ~/secrets.env uses - see _blob_env.sh). You can still
pass --connection-string explicitly.

Examples
--------
# Akilimo: Nigeria maize results to forecasting-simulations/Nigeria/pdates-cultivar/
python3 main/azure_blob/upload_to_blob.py \
    --container forecasting-simulations \
    --path data/usecases/useCase_Nigeria_full/Maize/result/DSSAT/AOI/ISRIC_useCase_Nigeria_full_Maize_AOI_season_1.RDS \
    --prefix "Nigeria/pdates-cultivar"

# Datasourcing cache: everything staged under ~/blob_stage/ by the stage_*.sh
# scripts, keeping its Processed/ and Landing/ layout under the agwise-cache/
# prefix (see stage_bias_correction_data.sh for why the layout must match)
source main/azure_blob/_blob_env.sh
python3 main/azure_blob/upload_to_blob.py \
    --container agwise-cache --create-container \
    --path ~/blob_stage --preserve-structure --base ~/blob_stage \
    --prefix agwise-cache

# Upload a single file, keeping just its filename as the blob name
python3 main/azure_blob/upload_to_blob.py \
    --container forecasting-simulations \
    --path data/usecases/useCase_Nigeria_full/Maize/result/DSSAT/AOI/ISRIC_useCase_Nigeria_full_Maize_AOI_season_1.RDS

# Upload a single file, preserving its folder structure as a virtual path in blob storage
python3 main/azure_blob/upload_to_blob.py \
    --container forecasting-simulations \
    --path data/usecases/useCase_Nigeria_full/Maize/result/DSSAT/AOI/ISRIC_useCase_Nigeria_full_Maize_AOI_season_1.RDS \
    --preserve-structure --base data

# Upload every file inside a folder (recursively), preserving structure
python3 main/azure_blob/upload_to_blob.py \
    --container forecasting-simulations \
    --path data/usecases/useCase_Nigeria_full \
    --preserve-structure --base data

# Add a prefix ("subfolder") inside the container
python3 main/azure_blob/upload_to_blob.py \
    --container forecasting-simulations \
    --path data/usecases/useCase_Nigeria_full \
    --preserve-structure --base data \
    --prefix nigeria_maize_run1

# Dry run - see what WOULD be uploaded without actually uploading anything
python3 main/azure_blob/upload_to_blob.py \
    --container forecasting-simulations \
    --path data/usecases/useCase_Nigeria_full \
    --preserve-structure --base data \
    --dry-run
"""

import argparse
import os
import sys


def get_connection_string(cli_value: str | None) -> str:
    if cli_value:
        return cli_value
    env_value = os.environ.get("AZURE_STORAGE_CONNECTION_STRING") or os.environ.get("BLOB_STRING")
    if env_value:
        return env_value
    sys.exit(
        "No connection string found.\n"
        "Either set it in your environment:\n"
        "    export AZURE_STORAGE_CONNECTION_STRING='your-connection-string-here'\n"
        "or pass it directly with --connection-string 'your-connection-string-here'"
    )


def collect_files(path: str) -> list[str]:
    """Return a list of file paths. Works whether `path` is a file or a directory."""
    if os.path.isfile(path):
        return [path]
    if os.path.isdir(path):
        collected = []
        for root, _dirs, files in os.walk(path):
            for f in files:
                collected.append(os.path.join(root, f))
        return sorted(collected)
    sys.exit(f"Path not found: {path}")


def blob_name_for(file_path: str, base: str | None, preserve_structure: bool, prefix: str | None) -> str:
    """Work out what the blob's name (virtual path) inside the container should be."""
    if preserve_structure:
        base_dir = base if base else os.path.dirname(file_path)
        rel_path = os.path.relpath(file_path, start=base_dir)
        # normalize to forward slashes for blob storage's virtual folder display
        name = rel_path.replace(os.sep, "/")
    else:
        name = os.path.basename(file_path)

    if prefix:
        name = f"{prefix.strip('/')}/{name}"

    return name


def main():
    parser = argparse.ArgumentParser(
        description="Upload a file or directory to an Azure Blob Storage container.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--path", required=True, help="File or directory to upload.")
    parser.add_argument("--container", required=True, help="Target container name, e.g. forecasting-simulations")
    parser.add_argument(
        "--connection-string",
        default=None,
        help="Azure Storage connection string. If omitted, reads AZURE_STORAGE_CONNECTION_STRING from the environment.",
    )
    parser.add_argument(
        "--preserve-structure",
        action="store_true",
        help="Preserve the folder structure of the uploaded path as a virtual path inside the container.",
    )
    parser.add_argument(
        "--base",
        default=None,
        help="Base directory that relative paths are computed from when --preserve-structure is used. "
        "Defaults to the parent directory of --path.",
    )
    parser.add_argument(
        "--prefix",
        default=None,
        help="Optional prefix ('subfolder') to prepend to every blob name inside the container.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be uploaded without actually uploading anything.",
    )
    parser.add_argument(
        "--create-container",
        action="store_true",
        help="Create the container if it doesn't exist yet.",
    )
    parser.add_argument(
        "--no-overwrite",
        action="store_true",
        help="Fail instead of overwriting if a blob with the same name already exists.",
    )

    args = parser.parse_args()

    files = collect_files(args.path)
    if not files:
        sys.exit(f"No files found under: {args.path}")

    print(f"Found {len(files)} file(s) to upload.\n")

    plan = [
        (fp, blob_name_for(fp, args.base, args.preserve_structure, args.prefix))
        for fp in files
    ]

    for file_path, blob_name in plan:
        size_kb = os.path.getsize(file_path) / 1024
        print(f"  {file_path}  ->  {args.container}/{blob_name}  ({size_kb:.1f} KB)")

    if args.dry_run:
        print("\nDry run only - nothing was uploaded.")
        return

    # Imported here so --help and --dry-run work without the library.
    try:
        from azure.storage.blob import BlobServiceClient
    except ImportError:
        sys.exit(
            "Missing dependency: azure-storage-blob.\n"
            "Install it with:  pip install azure-storage-blob"
        )

    connection_string = get_connection_string(args.connection_string)
    blob_service_client = BlobServiceClient.from_connection_string(connection_string)
    container_client = blob_service_client.get_container_client(args.container)
    if args.create_container and not container_client.exists():
        print(f"Creating container '{args.container}'...")
        container_client.create_container()

    print()
    for file_path, blob_name in plan:
        with open(file_path, "rb") as data:
            container_client.upload_blob(
                name=blob_name,
                data=data,
                overwrite=not args.no_overwrite,
            )
        print(f"  Uploaded: {blob_name}")

    print(f"\nDone. {len(plan)} file(s) uploaded to container '{args.container}'.")


if __name__ == "__main__":
    main()