# AgWise Historical Observation Data Sourcing Workflow

Production-ready workflow for one-time download, spatial preprocessing, variable harmonization, multi-year merging, and quality control of historical observation datasets used in the AgWise seasonal forecast-to-DSSAT pipeline.

This README documents the historical observation workflow only. Model hindcast processing will be added later as a separate workflow after the historical baseline is stable.

---

## 1. Purpose

The AgWise seasonal forecasting and crop-modeling workflow requires consistent historical climate observations for:

- bias correction and downscaling;
- seasonal forecast skill assessment;
- agroclimate index calculation;
- DSSAT weather preparation;
- planting date and cultivar optimization;
- downstream advisory generation.

The goal of this workflow is to download and preprocess historical observation datasets once, then reuse the standardized outputs across countries, use cases, and modeling tasks.

The workflow standardizes historical datasets by:

- downloading missing annual files where public URL templates are available;
- skipping files that already exist;
- cropping data to the Africa domain;
- standardizing coordinate names;
- harmonizing variable names to the AgWise `AGRO.*` convention;
- merging annual files into multi-year NetCDF products;
- writing metadata and QC tables;
- preparing clean inputs for bias correction, agroclimate indices, and DSSAT handoff.

---

## 2. Main script

Recommended script location:

```bash
agwise-datasourcing/dataops/datasourcing/common_data/agwise_historical_earthkit_parallel.py
```

The script uses:

- `earthkit-data` for ECMWF-style data access and ingestion where available;
- `xarray` and `Dask` for scalable NetCDF manipulation;
- Python multiprocessing for annual-file preprocessing;
- Python threading for parallel downloads.

Although the output folder keeps the existing name `CDO_Harmonized` for compatibility with the current AgWise folder structure, this Python workflow does **not** require CDO.

---

## 3. Historical datasets

| Short name | Target variable | Source dataset | Input folder | Notes |
|---|---|---|---|---|
| `PRCP` | `AGRO.PRCP` | CHIRPS v3.0 RNL | `Landing/Rainfall/chirps_v3/` | Downloaded automatically if missing |
| `TMAX` | `AGRO.TMAX` | CHIRTS-ERA5 Tmax | `Landing/TemperatureMax/CHIRTS-ERA5/` | Downloaded automatically if missing |
| `TMIN` | `AGRO.TMIN` | CHIRTS-ERA5 Tmin | `Landing/TemperatureMin/CHIRTS-ERA5/` | Downloaded automatically if missing |
| `TEMP` | `AGRO.TEMP` | AgERA5 mean temperature | `Landing/TemperatureMean/AgEra/` | Expected to already exist locally |
| `SRAD` | `AGRO.SRAD` | AgERA5 solar radiation | `Landing/SolarRadiation/AgEra/` | Expected to already exist locally |

Default processing period:

```bash
1984-2024
```

Default Africa bounding box:

```bash
-25,60,-40,40
```

This means:

```bash
lon_min,lon_max,lat_min,lat_max
```

---

## 4. Expected input folder structure

The script expects the following structure under `Data/Global_GeoData`:

```bash
Data/Global_GeoData/
  Landing/
    Rainfall/
      chirps_v3/
        1984.nc
        1985.nc
        ...
    TemperatureMax/
      CHIRTS-ERA5/
        1984.nc
        1985.nc
        ...
    TemperatureMin/
      CHIRTS-ERA5/
        1984.nc
        1985.nc
        ...
    TemperatureMean/
      AgEra/
        1984.nc
        1985.nc
        ...
    SolarRadiation/
      AgEra/
        1984.nc
        1985.nc
        ...
```

For CHIRPS and CHIRTS-ERA5, the script can download missing annual files automatically.

For AgERA5 TEMP and SRAD, the script assumes the annual files already exist locally because download sources and authentication can vary by implementation.

---

## 5. Environment setup using `uv`

From the datasourcing folder:

```bash
cd agwise-datasourcing/dataops/datasourcing
```

Create a Python environment:

```bash
uv venv .venv --python 3.11
```

Activate the environment:

```bash
source .venv/bin/activate
```

Install required packages:

```bash
uv pip install \
  earthkit-data \
  earthkit-transforms \
  xarray \
  dask \
  netcdf4 \
  h5netcdf \
  pandas \
  numpy \
  requests \
  tqdm \
  cfgrib \
  eccodes
```

Save the environment:

```bash
uv pip freeze > requirements.txt
```

Recreate the same environment later:

```bash
uv venv .venv --python 3.11
source .venv/bin/activate
uv pip install -r requirements.txt
```

---

## 6. Optional `pyproject.toml`

A project-style setup is recommended for GitHub.

Create `pyproject.toml` in:

```bash
agwise-datasourcing/dataops/datasourcing/
```

Example:

```toml
[project]
name = "agwise-historical-datasourcing"
version = "0.1.0"
description = "Historical observation data sourcing workflow for AgWise using Earthkit, xarray, and Dask"
requires-python = ">=3.11"
dependencies = [
  "earthkit-data",
  "earthkit-transforms",
  "xarray",
  "dask",
  "netcdf4",
  "h5netcdf",
  "pandas",
  "numpy",
  "requests",
  "tqdm",
  "cfgrib",
  "eccodes"
]
```

Then run:

```bash
uv sync
```

---

## 7. Basic usage

### Full download, processing, merge, and QC

Run from:

```bash
agwise-datasourcing/dataops/datasourcing/
```

Command:

```bash
uv run python common_data/agwise_historical_earthkit_parallel.py \
  --data-root Data/Global_GeoData \
  --start-year 1984 \
  --end-year 2024 \
  --workers 8 \
  --run-downloads \
  --run-processing \
  --run-qc \
  --require-complete-years
```

---

### Processing only

Use this if annual files already exist in the landing folders:

```bash
uv run python common_data/agwise_historical_earthkit_parallel.py \
  --data-root Data/Global_GeoData \
  --start-year 1984 \
  --end-year 2024 \
  --workers 8 \
  --run-processing \
  --run-qc \
  --require-complete-years
```

---

### Run selected variables only

Example for rainfall and CHIRTS-ERA5 temperature only:

```bash
uv run python common_data/agwise_historical_earthkit_parallel.py \
  --data-root Data/Global_GeoData \
  --start-year 1984 \
  --end-year 2024 \
  --workers 8 \
  --only PRCP TMAX TMIN \
  --run-downloads \
  --run-processing \
  --run-qc \
  --require-complete-years
```

Example for AgERA5 variables only:

```bash
uv run python common_data/agwise_historical_earthkit_parallel.py \
  --data-root Data/Global_GeoData \
  --start-year 1984 \
  --end-year 2024 \
  --workers 8 \
  --only TEMP SRAD \
  --run-processing \
  --run-qc \
  --require-complete-years
```

---

## 8. Main command-line options

| Option | Description | Default |
|---|---|---|
| `--data-root` | Path to `Data/Global_GeoData` | inferred from script location |
| `--start-year` | First year to process | `1984` |
| `--end-year` | Last year to process | `2024` |
| `--bbox` | Crop domain as `lon_min,lon_max,lat_min,lat_max` | `-25,60,-40,40` |
| `--workers` | Number of parallel workers | up to `8` by default |
| `--run-downloads` | Download missing CHIRPS and CHIRTS-ERA5 files | off unless provided |
| `--run-processing` | Crop, rename, standardize, and merge files | off unless provided |
| `--run-qc` | Generate QC summary | off unless provided |
| `--only` | Process selected variables only | all variables |
| `--require-complete-years` | Stop if required years are missing or failed | off unless provided |
| `--overwrite-downloads` | Redownload existing files | off |
| `--overwrite-processing` | Recreate annual standardized files | off |
| `--overwrite-merge` | Recreate final merged files | off |
| `--clean-temp` | Remove temporary standardized annual files after completion | off |
| `--verbose` | Print detailed logs | off |

---

## 9. Expected final outputs

Final standardized NetCDF files are written to:

```bash
Data/Global_GeoData/Processed/Africa/CDO_Harmonized/
```

Expected files:

```bash
Daily_PRCP_1984_2024.nc
Daily_TMAX_1984_2024.nc
Daily_TMIN_1984_2024.nc
Daily_TEMP_1984_2024.nc
Daily_SRAD_1984_2024.nc
```

These files are intended for downstream:

- bias correction;
- downscaling;
- forecast verification;
- agroclimate index calculation;
- DSSAT weather preparation;
- planting window and cultivar optimization;
- advisory generation.

---

## 10. Metadata and QC outputs

Metadata and QC files are written to:

```bash
Data/Global_GeoData/metadata/
```

Expected files:

```bash
historical_run_config_1984_2024.json
historical_variable_mapping.csv
historical_download_manifest_1984_2024.csv
historical_preprocess_manifest_1984_2024.csv
historical_merge_manifest_1984_2024.csv
historical_data_manifest_1984_2024.csv
historical_qc_summary_1984_2024.csv
```

### Important QC fields

The QC summary reports:

- file existence;
- file size;
- variable names;
- dimensions;
- time coverage;
- expected number of days;
- longitude and latitude extent;
- units;
- source variable;
- missing-value counts where feasible.

---

## 11. Temporary annual standardized files

During processing, annual cropped and standardized files are written under:

```bash
Data/Global_GeoData/Processed/Africa/CDO_Harmonized/tmp_earthkit/
```

Example:

```bash
Data/Global_GeoData/Processed/Africa/CDO_Harmonized/tmp_earthkit/PRCP/
Data/Global_GeoData/Processed/Africa/CDO_Harmonized/tmp_earthkit/TMAX/
Data/Global_GeoData/Processed/Africa/CDO_Harmonized/tmp_earthkit/TMIN/
Data/Global_GeoData/Processed/Africa/CDO_Harmonized/tmp_earthkit/TEMP/
Data/Global_GeoData/Processed/Africa/CDO_Harmonized/tmp_earthkit/SRAD/
```

To remove temporary files after the final merge, add:

```bash
--clean-temp
```

For operational runs, it is often safer to keep temporary files until QC has been reviewed.

---

## 12. Data handling logic

### Downloads

The script downloads only datasets with public URL templates:

- CHIRPS v3.0 RNL rainfall;
- CHIRTS-ERA5 Tmax;
- CHIRTS-ERA5 Tmin.

The script skips existing non-empty files unless `--overwrite-downloads` is used.

### Processing

For each selected variable and year, the script:

1. opens the annual NetCDF file;
2. standardizes coordinate names to `time`, `lat`, and `lon` where possible;
3. normalizes longitudes to the `-180` to `180` range where needed;
4. crops to the requested bounding box;
5. selects the source variable using known aliases;
6. renames the variable to the AgWise `AGRO.*` convention;
7. writes a compressed annual standardized NetCDF file;
8. merges annual standardized files into a final multi-year product.

---

## 13. Troubleshooting

### Missing AgERA5 files

If `TEMP` or `SRAD` fails with `missing_input`, check that annual files exist here:

```bash
Data/Global_GeoData/Landing/TemperatureMean/AgEra/
Data/Global_GeoData/Landing/SolarRadiation/AgEra/
```

The script does not download AgERA5 TEMP or SRAD automatically.

---

### Incomplete year coverage

If the workflow stops because of missing years, inspect:

```bash
Data/Global_GeoData/metadata/historical_preprocess_failed_1984_2024.csv
```

To allow partial processing, remove:

```bash
--require-complete-years
```

However, complete years are recommended for bias correction and DSSAT workflows.

---

### Existing output is not overwritten

By default, the script skips existing outputs.

To force recreation:

```bash
--overwrite-processing --overwrite-merge
```

To force redownload:

```bash
--overwrite-downloads
```

---

### Too much memory use

Reduce workers:

```bash
--workers 4
```

or:

```bash
--workers 2
```

Large Africa-wide NetCDF merges can be memory intensive, especially for high-resolution daily datasets.

---

## 14. Recommended operational workflow

### First run

```bash
uv run python common_data/agwise_historical_earthkit_parallel.py \
  --data-root Data/Global_GeoData \
  --start-year 1984 \
  --end-year 2024 \
  --workers 8 \
  --run-downloads \
  --run-processing \
  --run-qc \
  --require-complete-years
```

### Review QC

Open:

```bash
Data/Global_GeoData/metadata/historical_qc_summary_1984_2024.csv
```

Check:

- all files exist;
- all files have expected time coverage;
- variables are named correctly;
- units are documented;
- spatial extent matches the Africa domain;
- no unexpected missing years are present.

### Clean temporary files only after QC

```bash
uv run python common_data/agwise_historical_earthkit_parallel.py \
  --data-root Data/Global_GeoData \
  --start-year 1984 \
  --end-year 2024 \
  --only PRCP TMAX TMIN TEMP SRAD \
  --clean-temp
```

---

## 15. Relationship to hindcast workflow

This workflow intentionally focuses on historical observations only.

The next workflow should handle model hindcasts separately, including:

- model name;
- ensemble member;
- initialization date;
- lead time;
- forecast variable;
- temporal alignment with observations;
- regridding or grid matching;
- bias correction readiness;
- forecast skill assessment readiness.

Keeping historical observations and hindcasts separate at this stage makes the system easier to test, document, and maintain.

---

## 16. Author and affiliation

**Author:** Dr. Jemal Seid Ahmed  
**Affiliation:** Alliance of Bioversity International and CIAT  
**Program:** CGIAR Climate Action Science Program  
**Email:** J.Ahmed@cgiar.org

---

## 17. Status

Historical observation workflow: active development  
Hindcast workflow: planned next step
