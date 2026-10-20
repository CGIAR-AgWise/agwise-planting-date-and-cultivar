#!/usr/bin/env bash
# Run this ON CGLabs.
#
# Stages the raw SoilGrids Landing tree into ~/blob_stage/Landing/Soil/
# soilGrids/profile/ - mirroring CGLabs's own Global_GeoData/Landing/
# layout exactly (Landing/ is a sibling of Processed/ - see
# stage_bias_correction_data.sh for the Processed/ side), ready to upload
# to blob via upload_to_blob.py (command in its docstring).
#
# Unlike the climate data (per-year, per-country, huge over decades), this
# is global, static, and small (~2.5GB total for all 12 properties x 6
# depths) - see catalog/soil.yaml's `type: local` access entry:
#   path: "Soil/soilGrids/profile/{var}_{depth}_mean_30s.tif"
# So it's staged WHOLESALE, not per-country/per-domain: once uploaded and
# mounted as AGWISE_LOCAL_ROOT, the pipeline's existing local-reuse driver
# clips on demand for ANY country automatically, with zero per-country
# staging needed here or later - unlike AGWISE_DATA_ROOT's harmonized
# cache, which needed exact rg_* domain resolution per country.
#
# Usage:
#   ./stage_soil_data.sh
set -euo pipefail

LANDING=~/agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData/Landing/Soil/soilGrids/profile
STAGE=~/blob_stage/Landing/Soil/soilGrids/profile

mkdir -p "$STAGE"

echo "Staging SoilGrids raw rasters..."
count=0
for f in "$LANDING"/*.tif; do
  [ -e "$f" ] || continue
  cp "$f" "$STAGE/"
  count=$((count + 1))
done

echo ""
echo "Done. Staged $count files."
du -sh "$STAGE"
