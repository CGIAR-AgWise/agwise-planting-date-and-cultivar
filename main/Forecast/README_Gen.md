What the script does
common_data/agwise_parallel_earthkit_datasourcing.py

It supports:

parallel one-time download of CHIRPS v3 rainfall;
parallel one-time download of CHIRTS-ERA5 Tmax/Tmin;
support for existing AgERA mean temperature and solar radiation folders;
optional model hindcast processing through a JSON config;
Earthkit-based file ingestion where available;
xarray/Dask-based spatial crop, coordinate standardization, variable renaming, and NetCDF writing;
Africa bounding-box crop;
AGRO.PRCP, AGRO.TMAX, AGRO.TMIN, AGRO.TEMP, AGRO.SRAD naming;
annual-file preprocessing in parallel;
final multi-year merge;
metadata writing;
QC summary CSV;
download manifest, preprocessing manifest, merge manifest, and run configuration.
Install environment
micromamba create -n agwise-earthkit -c conda-forge \
  python=3.11 \
  xarray dask netcdf4 h5netcdf pandas numpy requests \
  earthkit-data earthkit-transforms cfgrib eccodes

micromamba activate agwise-earthkit
Recommended location

Put the script here:

agwise-datasourcing/dataops/datasourcing/common_data/agwise_parallel_earthkit_datasourcing.py
Run full historical workflow
python common_data/agwise_parallel_earthkit_datasourcing.py \
  --data-root agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData \
  --start-year 1984 \
  --end-year 2024 \
  --workers 8 \
  --run-downloads \
  --run-processing \
  --run-qc \
  --require-complete-years
Run processing only
python common_data/agwise_parallel_earthkit_datasourcing.py \
  --data-root agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData \
  --start-year 1984 \
  --end-year 2024 \
  --workers 8 \
  --run-processing \
  --run-qc
Run only selected variables
python common_data/agwise_parallel_earthkit_datasourcing.py \
  --data-root agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData \
  --start-year 1984 \
  --end-year 2024 \
  --workers 8 \
  --only PRCP TMAX TMIN \
  --run-downloads \
  --run-processing \
  --run-qc
Expected outputs
Data/Global_GeoData/Processed/Africa/CDO_Harmonized/
  Daily_PRCP_1984_2024.nc
  Daily_TMAX_1984_2024.nc
  Daily_TMIN_1984_2024.nc
  Daily_TEMP_1984_2024.nc
  Daily_SRAD_1984_2024.nc

Metadata and QC files:

Data/Global_GeoData/metadata/
  run_config_1984_2024.json
  download_manifest_1984_2024.csv
  preprocess_manifest_1984_2024.csv
  merge_manifest_1984_2024.csv
  qc_summary_1984_2024.csv
Optional hindcast config

For model hindcasts, create a config like:

{
  "datasets": [
    {
      "dataset_type": "hindcast",
      "name": "SEAS5",
      "short_name": "PRCP",
      "target_var": "AGRO.PRCP",
      "source_vars": ["tp", "precipitation", "total_precipitation"],
      "input_dir": "Landing/Hindcast/SEAS5/PRCP/raw",
      "standardized_dir": "Landing/Hindcast/SEAS5/PRCP/standardized",
      "output_dir": "Processed/Africa/Hindcast_Harmonized",
      "file_pattern": "*.nc",
      "output_template": "SEAS5_Daily_PRCP_{start}_{end}_lead01.nc",
      "url_template": null,
      "unit_conversion": "m_to_mm",
      "daily_aggregation": "daily_sum",
      "compression_level": 4
    }
  ]
}

Run it with:

python common_data/agwise_parallel_earthkit_datasourcing.py \
  --data-root agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData \
  --start-year 1984 \
  --end-year 2024 \
  --hindcast-config common_data/hindcast_config.json \
  --workers 8 \
  --run-processing \
  --run-qc