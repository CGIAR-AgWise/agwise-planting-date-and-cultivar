This version focuses only on:

CHIRPS v3 rainfall download and preprocessing
CHIRTS-ERA5 Tmax/Tmin download and preprocessing
AgERA TEMP and SRAD from existing local landing folders
Africa crop
variable renaming to AGRO.*
annual parallel preprocessing
final multi-year NetCDF merge
metadata manifests
QC summary

This matches the historical observation part of your planned workflow, where files should be downloaded once, harmonized spatially and temporally, renamed to AgWise conventions, merged, documented, and QC-checked. It also keeps the same historical baseline as your R workflow: 1984–2024, Africa bbox, final names such as Daily_PRCP_1984_2024.nc, and variables AGRO.PRCP, AGRO.TMAX, AGRO.TMIN, AGRO.TEMP, and AGRO.SRAD.

Run it like this:

python common_data/agwise_historical_earthkit_parallel.py \
  --data-root agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData \
  --start-year 1984 \
  --end-year 2024 \
  --workers 8 \
  --run-downloads \
  --run-processing \
  --run-qc \
  --require-complete-years

For processing only:

python common_data/agwise_historical_earthkit_parallel.py \
  --data-root agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData \
  --start-year 1984 \
  --end-year 2024 \
  --workers 8 \
  --run-processing \
  --run-qc

Recommended location in your repo:

agwise-datasourcing/dataops/datasourcing/common_data/agwise_historical_earthkit_parallel.py

Expected outputs:

Data/Global_GeoData/Processed/Africa/CDO_Harmonized/
  Daily_PRCP_1984_2024.nc
  Daily_TMAX_1984_2024.nc
  Daily_TMIN_1984_2024.nc
  Daily_TEMP_1984_2024.nc
  Daily_SRAD_1984_2024.nc

It also writes:

Data/Global_GeoData/metadata/
  historical_run_config_1984_2024.json
  historical_variable_mapping.csv
  historical_download_manifest_1984_2024.csv
  historical_preprocess_manifest_1984_2024.csv
  historical_merge_manifest_1984_2024.csv
  historical_data_manifest_1984_2024.csv
  historical_qc_summary_1984_2024.csv