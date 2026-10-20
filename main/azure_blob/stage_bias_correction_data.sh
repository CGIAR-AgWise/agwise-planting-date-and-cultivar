#!/usr/bin/env bash
# Run this ON CGLabs, in the agwise_data conda env.
#
# Stages the 4 bias-correction variables (chirps_v3 PRCP; agera5 TMAX/TMIN/
# SRAD) for ONE already-resolved rg_* domain into
# ~/blob_stage/Processed/harmonized/ - mirroring CGLabs's own
# Global_GeoData/Processed/harmonized/ layout exactly (Processed/ is a
# sibling of Landing/ - see stage_soil_data.sh for the Landing/ side), ready
# to upload to blob via upload_to_blob.py (command in its docstring).
#
# Why the layout must match: the upload puts the staged tree under the
# "agwise-cache/" prefix of the agwise-cache container (a shared cache for
# several AgWise pipelines, each under its own prefix; this DSSAT repo's own
# results would go under "agwise-planting-date-and-cultivar/"), e.g.
#   ~/blob_stage/Processed/harmonized/chirps_v3/rg_27_m4_32_0/PRCP/Daily_PRCP_1993.nc
#     -> agwise-cache/Processed/harmonized/chirps_v3/rg_27_m4_32_0/PRCP/Daily_PRCP_1993.nc
# Once "agwise-cache/Processed" is mounted as AGWISE_DATA_ROOT and
# "agwise-cache/Landing" as AGWISE_LOCAL_ROOT (two blobfuse2 mounts using
# its `subdirectory` option), config.py's harmonized_path()/local_file()
# must find files at exactly these paths with zero translation.
#
# Assumes the same rg_* domain applies to all 4 variables - confirmed true
# for Rwanda via the _resolve_region/_effective_domain check; re-verify per
# country before assuming it holds there too:
#
#   python3 - <<'PY'
#   from agwise_data.config import Config
#   from agwise_data.api import _resolve_region, _effective_domain
#   config = Config.load()
#   gdf, bbox, tag = _resolve_region(config, "<Country>", None, 0, None, None)
#   years = list(range(1993, 2017))
#   for src, var in [("chirps_v3","AGRO.PRCP"), ("agera5","AGRO.TMAX"),
#                     ("agera5","AGRO.TMIN"), ("agera5","AGRO.SRAD")]:
#       print(src, var, _effective_domain(config, src, var, years, bbox, None))
#   PY
#
# Usage:
#   ./stage_bias_correction_data.sh <rg_domain_folder> [start_year] [end_year]
# Example:
#   ./stage_bias_correction_data.sh rg_27_m4_32_0 1993 2016
set -euo pipefail

DOMAIN="${1:?Usage: $0 <rg_domain_folder> [start_year] [end_year]}"
START_YEAR="${2:-1993}"
END_YEAR="${3:-2016}"

HARMONIZED=~/agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData/Processed/harmonized
STAGE=~/blob_stage/Processed/harmonized

copy_var() {
  local source_dir="$1" var="$2"
  local src="$HARMONIZED/$source_dir/$DOMAIN/$var"
  local dest="$STAGE/$source_dir/$DOMAIN/$var"

  if [ ! -d "$src" ]; then
    echo "  SKIP: $src does not exist"
    return
  fi

  mkdir -p "$dest"
  for f in "$src"/Daily_${var}_*.nc; do
    [ -e "$f" ] || continue
    year=$(basename "$f" | grep -oE '[0-9]{4}' | tail -1)
    if [ "$year" -ge "$START_YEAR" ] && [ "$year" -le "$END_YEAR" ]; then
      cp "$f" "$dest/"
      echo "  copied: $source_dir/$DOMAIN/$var/$(basename "$f")"
    fi
  done
}

echo "Staging domain $DOMAIN for years $START_YEAR-$END_YEAR..."
copy_var chirps_v3 PRCP
copy_var agera5 TMAX
copy_var agera5 TMIN
copy_var agera5 SRAD

echo ""
echo "Done. Staged size so far:"
du -sh "$STAGE"
