#!/usr/bin/env python3
"""
AgWise historical observation Earthkit parallel preprocessing workflow
=====================================================================

Purpose
-------
One-time parallel download, spatial crop, coordinate standardization, variable
harmonization, annual-to-multi-year merge, metadata writing, and QC for
historical observation datasets used by the AgWise seasonal forecast-to-DSSAT
workflow.

This script intentionally focuses only on HISTORICAL OBSERVATIONS.
Model hindcast download and preprocessing should be added as a separate script
or later extension after this historical baseline is stable.

Author      : Dr. Jemal Seid Ahmed
Affiliation : Alliance of Bioversity International and CIAT
Program     : CGIAR Climate Action Science Program
Email       : J.Ahmed@cgiar.org

Default period: 1984-2024
Default domain: Africa bbox = -25,60,-40,40
Meaning       : lon_min, lon_max, lat_min, lat_max

Historical datasets
-------------------
1. PRCP : CHIRPS v3.0 RNL daily precipitation
2. TMAX : CHIRTS-ERA5 daily maximum temperature
3. TMIN : CHIRTS-ERA5 daily minimum temperature
4. TEMP : AgERA daily mean temperature, expected to already exist locally
5. SRAD : AgERA daily solar radiation, expected to already exist locally

Expected input landing folders under Data/Global_GeoData
--------------------------------------------------------
Landing/Rainfall/chirps_v3/<YEAR>.nc
Landing/TemperatureMax/CHIRTS-ERA5/<YEAR>.nc
Landing/TemperatureMin/CHIRTS-ERA5/<YEAR>.nc
Landing/TemperatureMean/AgEra/<YEAR>.nc
Landing/SolarRadiation/AgEra/<YEAR>.nc

Expected final outputs
----------------------
Processed/Africa/CDO_Harmonized/Daily_PRCP_1984_2024.nc
Processed/Africa/CDO_Harmonized/Daily_TMAX_1984_2024.nc
Processed/Africa/CDO_Harmonized/Daily_TMIN_1984_2024.nc
Processed/Africa/CDO_Harmonized/Daily_TEMP_1984_2024.nc
Processed/Africa/CDO_Harmonized/Daily_SRAD_1984_2024.nc

Install example
---------------
micromamba create -n agwise-earthkit -c conda-forge \
  python=3.11 \
  earthkit-data earthkit-transforms \
  xarray dask netcdf4 h5netcdf pandas numpy requests cfgrib eccodes

micromamba activate agwise-earthkit

Basic use from datasourcing folder
----------------------------------
python common_data/agwise_historical_earthkit_parallel.py \
  --start-year 1984 --end-year 2024 \
  --workers 8 \
  --run-downloads --run-processing --run-qc \
  --require-complete-years

Explicit data root
------------------
python common_data/agwise_historical_earthkit_parallel.py \
  --data-root agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData \
  --start-year 1984 --end-year 2024 \
  --workers 8 \
  --run-downloads --run-processing --run-qc

Processing only
---------------
python common_data/agwise_historical_earthkit_parallel.py \
  --data-root agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData \
  --start-year 1984 --end-year 2024 \
  --workers 8 \
  --run-processing --run-qc

Selected variables only
-----------------------
python common_data/agwise_historical_earthkit_parallel.py \
  --data-root agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData \
  --only PRCP TMAX TMIN \
  --workers 8 \
  --run-downloads --run-processing --run-qc
"""

from __future__ import annotations

import argparse
import csv
import json
import logging
import os
import shutil
import sys
import time
import traceback
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor, as_completed
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import numpy as np
import pandas as pd
import xarray as xr

try:
    import earthkit.data as ekd
except Exception:  # earthkit-data is optional at import time; xarray fallback is used.
    ekd = None

try:
    import earthkit.transforms as ekt
except Exception:  # earthkit-transforms is optional; xarray fallback is used.
    ekt = None


LOG = logging.getLogger("agwise-historical-earthkit")


# =============================================================================
# Dataset specification
# =============================================================================


@dataclass
class HistoricalDatasetSpec:
    """Specification for one historical observation variable stack."""

    name: str
    short_name: str
    target_var: str
    source_vars: List[str]
    input_dir: str
    standardized_dir: str
    output_dir: str
    file_pattern: str = "{year}.nc"
    output_template: str = "Daily_{short_name}_{start}_{end}.nc"
    url_template: Optional[str] = None
    unit_conversion: Optional[str] = None
    daily_aggregation: Optional[str] = None
    compression_level: int = 4
    dtype: str = "float32"
    metadata: Dict[str, Any] = field(default_factory=dict)

    def input_path(self, data_root: Path, year: int) -> Path:
        return data_root / self.input_dir / self.file_pattern.format(year=year)

    def standardized_path(self, data_root: Path, year: int) -> Path:
        safe = self.target_var.replace(".", "_")
        return data_root / self.standardized_dir / f"{year}_{safe}_africa_standardized.nc"

    def output_path(self, data_root: Path, start_year: int, end_year: int) -> Path:
        return data_root / self.output_dir / self.output_template.format(
            short_name=self.short_name,
            start=start_year,
            end=end_year,
            target_var=self.target_var.replace(".", "_"),
        )

    def url_for_year(self, year: int) -> Optional[str]:
        if not self.url_template:
            return None
        return self.url_template.format(year=year)


def historical_specs() -> List[HistoricalDatasetSpec]:
    """Default historical observation datasets used by the AgWise workflow."""

    return [
        HistoricalDatasetSpec(
            name="CHIRPS_v3_RNL",
            short_name="PRCP",
            target_var="AGRO.PRCP",
            source_vars=["AGRO.PRCP", "precipitation_flux", "precip", "precipitation", "rainfall", "prcp"],
            input_dir="Landing/Rainfall/chirps_v3",
            standardized_dir="Processed/Africa/CDO_Harmonized/tmp_earthkit/PRCP",
            output_dir="Processed/Africa/CDO_Harmonized",
            url_template=(
                "https://data.chc.ucsb.edu/products/CHIRPS/v3.0/daily/final/rnl/"
                "netcdf/byYear/chirps-v3.0.rnl.{year}.days_p05.nc"
            ),
            metadata={
                "long_name": "Daily precipitation flux",
                "source_dataset": "UCSB CHC CHIRPS v3.0 RNL",
                "source_variable_standard_name": "precipitation_flux",
                "units": "mm/day",
            },
        ),
        HistoricalDatasetSpec(
            name="CHIRTS_ERA5_TMAX",
            short_name="TMAX",
            target_var="AGRO.TMAX",
            source_vars=["AGRO.TMAX", "Tmax", "tmax", "maximum_temperature", "2m_temperature", "tasmax"],
            input_dir="Landing/TemperatureMax/CHIRTS-ERA5",
            standardized_dir="Processed/Africa/CDO_Harmonized/tmp_earthkit/TMAX",
            output_dir="Processed/Africa/CDO_Harmonized",
            url_template=(
                "https://data.chc.ucsb.edu/experimental/CHIRTS-ERA5/tmax/netcdf/"
                "daily/CHIRTS-ERA5.daily_Tmax.{year}.nc"
            ),
            metadata={
                "long_name": "Daily maximum 2m air temperature",
                "source_dataset": "UCSB CHC CHIRTS-ERA5",
                "source_variable_standard_name": "2m_temperature",
                "aggregation": "24_hour_maximum",
                "units": "degC",
            },
        ),
        HistoricalDatasetSpec(
            name="CHIRTS_ERA5_TMIN",
            short_name="TMIN",
            target_var="AGRO.TMIN",
            source_vars=["AGRO.TMIN", "Tmin", "tmin", "minimum_temperature", "2m_temperature", "tasmin"],
            input_dir="Landing/TemperatureMin/CHIRTS-ERA5",
            standardized_dir="Processed/Africa/CDO_Harmonized/tmp_earthkit/TMIN",
            output_dir="Processed/Africa/CDO_Harmonized",
            url_template=(
                "https://data.chc.ucsb.edu/experimental/CHIRTS-ERA5/tmin/netcdf/"
                "daily/CHIRTS-ERA5.daily_Tmin.{year}.nc"
            ),
            metadata={
                "long_name": "Daily minimum 2m air temperature",
                "source_dataset": "UCSB CHC CHIRTS-ERA5",
                "source_variable_standard_name": "2m_temperature",
                "aggregation": "24_hour_minimum",
                "units": "degC",
            },
        ),
        HistoricalDatasetSpec(
            name="AgERA5_TEMP",
            short_name="TEMP",
            target_var="AGRO.TEMP",
            source_vars=["AGRO.TEMP", "temperature", "temp", "tmean", "Tmean", "Tavg", "2m_temperature", "tas"],
            input_dir="Landing/TemperatureMean/AgEra",
            standardized_dir="Processed/Africa/CDO_Harmonized/tmp_earthkit/TEMP",
            output_dir="Processed/Africa/CDO_Harmonized",
            url_template=None,
            metadata={
                "long_name": "Daily mean 2m air temperature",
                "source_dataset": "AgERA5",
                "source_variable_standard_name": "2m_temperature",
                "aggregation": "24_hour_mean",
                "units": "degC",
            },
        ),
        HistoricalDatasetSpec(
            name="AgERA5_SRAD",
            short_name="SRAD",
            target_var="AGRO.SRAD",
            source_vars=["AGRO.SRAD", "solar_radiation_flux", "solar_radiation", "srad", "SRAD", "ssrd", "radiation"],
            input_dir="Landing/SolarRadiation/AgEra",
            standardized_dir="Processed/Africa/CDO_Harmonized/tmp_earthkit/SRAD",
            output_dir="Processed/Africa/CDO_Harmonized",
            url_template=None,
            metadata={
                "long_name": "Daily solar radiation flux",
                "source_dataset": "AgERA5",
                "source_variable_standard_name": "solar_radiation_flux",
                "units": "MJ m-2 day-1",
            },
        ),
    ]


# =============================================================================
# General helpers
# =============================================================================


def setup_logging(verbose: bool = False) -> None:
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(asctime)s | %(levelname)-8s | %(processName)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )


def parse_bbox(value: str) -> Tuple[float, float, float, float]:
    parts = [float(x.strip()) for x in value.split(",")]
    if len(parts) != 4:
        raise ValueError("--bbox must contain lon_min,lon_max,lat_min,lat_max")
    lon_min, lon_max, lat_min, lat_max = parts
    if lon_min >= lon_max:
        raise ValueError("bbox lon_min must be less than lon_max")
    if lat_min >= lat_max:
        raise ValueError("bbox lat_min must be less than lat_max")
    return lon_min, lon_max, lat_min, lat_max


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def file_nonzero(path: Path) -> bool:
    return path.exists() and path.stat().st_size > 0


def remove_zero_byte(path: Path) -> None:
    if path.exists() and path.stat().st_size == 0:
        LOG.warning("Removing zero-byte file: %s", path)
        path.unlink()


def write_json(path: Path, payload: Dict[str, Any]) -> None:
    ensure_dir(path.parent)
    with path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, sort_keys=True, default=str)


def write_csv(path: Path, rows: Sequence[Dict[str, Any]]) -> None:
    ensure_dir(path.parent)
    if not rows:
        path.write_text("", encoding="utf-8")
        return

    fields: List[str] = []
    for row in rows:
        for key in row.keys():
            if key not in fields:
                fields.append(key)

    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def infer_data_root(script_path: Path) -> Path:
    """Infer Data/Global_GeoData when script is located in common_data."""

    # Expected script location:
    # datasourcing/common_data/agwise_historical_earthkit_parallel.py
    # Data root:
    # datasourcing/Data/Global_GeoData
    candidate = script_path.resolve().parent.parent / "Data" / "Global_GeoData"
    return candidate


def expected_days(start_year: int, end_year: int) -> int:
    start = pd.Timestamp(f"{start_year}-01-01")
    end = pd.Timestamp(f"{end_year}-12-31")
    return int((end - start).days + 1)


# =============================================================================
# Parallel download
# =============================================================================


def download_one(
    url: str,
    dest: Path,
    overwrite: bool = False,
    retries: int = 5,
    timeout: int = 120,
) -> Dict[str, Any]:
    ensure_dir(dest.parent)

    if file_nonzero(dest) and not overwrite:
        return {
            "url": url,
            "path": str(dest),
            "status": "skipped_exists",
            "size_bytes": dest.stat().st_size,
        }

    remove_zero_byte(dest)
    tmp = dest.with_suffix(dest.suffix + ".part")
    if tmp.exists():
        tmp.unlink()

    last_error = None
    for attempt in range(1, retries + 1):
        try:
            LOG.info("Downloading [%s/%s]: %s", attempt, retries, url)
            req = Request(url, headers={"User-Agent": "AgWise-Historical-Earthkit/1.0"})
            with urlopen(req, timeout=timeout) as response, tmp.open("wb") as out:
                shutil.copyfileobj(response, out, length=1024 * 1024)
            tmp.replace(dest)
            return {
                "url": url,
                "path": str(dest),
                "status": "downloaded",
                "size_bytes": dest.stat().st_size,
            }
        except (HTTPError, URLError, TimeoutError, OSError) as exc:
            last_error = repr(exc)
            LOG.warning("Download failed attempt %s for %s: %s", attempt, url, exc)
            if tmp.exists():
                tmp.unlink(missing_ok=True)
            time.sleep(min(60, 3 * attempt))

    return {
        "url": url,
        "path": str(dest),
        "status": "failed",
        "error": last_error,
    }


def build_download_jobs(
    specs: Sequence[HistoricalDatasetSpec],
    data_root: Path,
    years: Sequence[int],
) -> List[Tuple[str, Path]]:
    jobs: List[Tuple[str, Path]] = []
    for spec in specs:
        if not spec.url_template:
            LOG.info(
                "No download URL for %s. Assuming local annual files already exist in: %s",
                spec.short_name,
                data_root / spec.input_dir,
            )
            continue
        for year in years:
            url = spec.url_for_year(year)
            if url:
                jobs.append((url, spec.input_path(data_root, year)))
    return jobs


def run_downloads(
    specs: Sequence[HistoricalDatasetSpec],
    data_root: Path,
    years: Sequence[int],
    workers: int,
    overwrite: bool,
) -> List[Dict[str, Any]]:
    jobs = build_download_jobs(specs, data_root, years)
    if not jobs:
        LOG.info("No download jobs were created.")
        return []

    LOG.info("Starting %s download jobs using %s workers", len(jobs), workers)
    rows: List[Dict[str, Any]] = []
    with ThreadPoolExecutor(max_workers=workers) as executor:
        futures = [executor.submit(download_one, url, dest, overwrite) for url, dest in jobs]
        for future in as_completed(futures):
            row = future.result()
            rows.append(row)
            LOG.info("Download result: %s | %s", row.get("status"), row.get("path"))
    return rows


# =============================================================================
# Earthkit / xarray manipulation
# =============================================================================


def open_with_earthkit(path: Path, chunks: Optional[Dict[str, int]] = None) -> xr.Dataset:
    """
    Open through earthkit-data first, then fall back to xarray.

    Earthkit is useful because it provides a common ECMWF data interface across
    file types. For this historical NetCDF workflow, xarray/Dask remain the main
    manipulation engine after data are opened.
    """

    if ekd is not None:
        try:
            obj = ekd.from_source("file", str(path))
            ds = obj.to_xarray()
            if isinstance(ds, xr.DataArray):
                ds = ds.to_dataset(name=ds.name or "variable")
            if chunks:
                valid_chunks = {k: v for k, v in chunks.items() if k in ds.dims}
                if valid_chunks:
                    ds = ds.chunk(valid_chunks)
            return ds
        except Exception as exc:
            LOG.debug("earthkit-data could not open %s; using xarray fallback. Reason: %s", path, exc)

    return xr.open_dataset(path, chunks=chunks or {}, decode_times=True)


def standardize_coord_names(ds: xr.Dataset) -> xr.Dataset:
    rename: Dict[str, str] = {}

    lon_candidates = ["longitude", "lon", "LONGITUDE", "x", "X"]
    lat_candidates = ["latitude", "lat", "LATITUDE", "y", "Y"]
    time_candidates = ["valid_time", "time", "TIME", "date", "day"]

    for name in lon_candidates:
        if name in ds.coords or name in ds.dims:
            if name != "lon":
                rename[name] = "lon"
            break

    for name in lat_candidates:
        if name in ds.coords or name in ds.dims:
            if name != "lat":
                rename[name] = "lat"
            break

    for name in time_candidates:
        if name in ds.coords or name in ds.dims:
            if name != "time":
                rename[name] = "time"
            break

    if rename:
        ds = ds.rename(rename)
    return ds


def normalize_longitude(ds: xr.Dataset) -> xr.Dataset:
    if "lon" not in ds.coords:
        return ds

    try:
        lon_min = float(ds["lon"].min())
        lon_max = float(ds["lon"].max())
    except Exception:
        return ds

    if lon_max > 180.0:
        ds = ds.assign_coords(lon=(((ds["lon"] + 180) % 360) - 180))
        ds = ds.sortby("lon")
    elif lon_min < -180.0 or lon_max > 180.0:
        ds = ds.sortby("lon")

    return ds


def crop_bbox(ds: xr.Dataset, bbox: Tuple[float, float, float, float]) -> xr.Dataset:
    lon_min, lon_max, lat_min, lat_max = bbox

    if "lon" in ds.coords:
        ds = ds.sel(lon=slice(lon_min, lon_max))

    if "lat" in ds.coords:
        lat_values = ds["lat"].values
        if lat_values.size > 1 and lat_values[0] > lat_values[-1]:
            ds = ds.sel(lat=slice(lat_max, lat_min))
        else:
            ds = ds.sel(lat=slice(lat_min, lat_max))

    return ds


def select_source_variable(ds: xr.Dataset, aliases: Sequence[str]) -> str:
    for candidate in aliases:
        if candidate in ds.data_vars:
            return candidate

    ignored = {
        "lat_bnds",
        "lon_bnds",
        "time_bnds",
        "latitude_bnds",
        "longitude_bnds",
        "spatial_ref",
        "crs",
        "rotated_pole",
        "height",
    }
    candidates = [v for v in ds.data_vars if v not in ignored]
    if len(candidates) == 1:
        return candidates[0]
    if candidates:
        LOG.warning("No alias matched. Using first data variable %s from %s", candidates[0], candidates)
        return candidates[0]

    raise ValueError("No data variable found in dataset")


def apply_unit_conversion(da: xr.DataArray, conversion: Optional[str]) -> xr.DataArray:
    if not conversion:
        return da

    key = conversion.lower()
    if key in {"k_to_c", "kelvin_to_celsius"}:
        da = da - 273.15
        da.attrs["units"] = "degC"
    elif key in {"m_to_mm", "metre_to_mm", "meter_to_mm"}:
        da = da * 1000.0
        da.attrs["units"] = "mm"
    elif key in {"kg_m2_s_to_mm_day", "flux_to_mm_day"}:
        da = da * 86400.0
        da.attrs["units"] = "mm/day"
    elif key in {"j_m2_to_mj_m2", "j_to_mj"}:
        da = da / 1_000_000.0
        da.attrs["units"] = "MJ m-2"
    else:
        raise ValueError(f"Unsupported unit conversion: {conversion}")

    da.attrs["agwise_unit_conversion"] = key
    return da


def apply_daily_aggregation(ds: xr.Dataset, aggregation: Optional[str]) -> xr.Dataset:
    if not aggregation:
        return ds

    key = aggregation.lower()
    if key not in {"daily_mean", "daily_min", "daily_max", "daily_sum"}:
        raise ValueError(f"Unsupported daily aggregation: {aggregation}")

    if "time" not in ds.coords and "time" not in ds.dims:
        LOG.warning("daily_aggregation=%s requested, but no time coordinate was found. Skipping.", key)
        return ds

    if ekt is not None:
        try:
            # Works when earthkit-transforms exposes temporal helpers with these names.
            func = getattr(ekt.temporal, key)
            return func(ds)
        except Exception as exc:
            LOG.debug("earthkit-transforms aggregation failed; falling back to xarray. Reason: %s", exc)

    how = key.replace("daily_", "")
    resampler = ds.resample(time="1D")
    if how == "mean":
        return resampler.mean(keep_attrs=True)
    if how == "min":
        return resampler.min(keep_attrs=True)
    if how == "max":
        return resampler.max(keep_attrs=True)
    if how == "sum":
        return resampler.sum(keep_attrs=True)

    return ds


def set_common_attrs(
    ds: xr.Dataset,
    spec: HistoricalDatasetSpec,
    start_year: int,
    end_year: int,
    bbox: Tuple[float, float, float, float],
) -> xr.Dataset:
    ds.attrs.update(
        {
            "title": f"AgWise standardized historical observation {spec.short_name}",
            "dataset_type": "historical_observation",
            "source_dataset": spec.metadata.get("source_dataset", spec.name),
            "agwise_variable": spec.target_var,
            "period": f"{start_year}-{end_year}",
            "spatial_domain": "Africa",
            "bbox_lon_min_lon_max_lat_min_lat_max": ",".join(map(str, bbox)),
            "institution": "Alliance of Bioversity International and CIAT / CGIAR Climate Action Science Program",
            "author": "Jemal S. Ahmed",
            "email": "J.Ahmed@cgiar.org",
            "history": f"Created by AgWise Planting Module team on {pd.Timestamp.utcnow().isoformat()}",
        }
    )
    return ds


def encoding_for(ds: xr.Dataset, compression_level: int, dtype: str = "float32") -> Dict[str, Dict[str, Any]]:
    encoding: Dict[str, Dict[str, Any]] = {}
    for var in ds.data_vars:
        if np.issubdtype(ds[var].dtype, np.floating):
            encoding[var] = {
                "zlib": True,
                "complevel": int(compression_level),
                "shuffle": True,
                "dtype": dtype,
                "_FillValue": np.float32(np.nan) if dtype == "float32" else np.nan,
            }
        else:
            encoding[var] = {
                "zlib": True,
                "complevel": int(compression_level),
                "shuffle": True,
            }
    return encoding


def preprocess_one_year(
    spec_dict: Dict[str, Any],
    data_root_str: str,
    year: int,
    bbox: Tuple[float, float, float, float],
    start_year: int,
    end_year: int,
    overwrite: bool,
) -> Dict[str, Any]:
    """Worker-safe annual preprocessing function."""

    spec = HistoricalDatasetSpec(**spec_dict)
    data_root = Path(data_root_str)
    infile = spec.input_path(data_root, year)
    outfile = spec.standardized_path(data_root, year)
    ensure_dir(outfile.parent)

    if file_nonzero(outfile) and not overwrite:
        return {
            "dataset": spec.name,
            "variable": spec.short_name,
            "agwise_variable": spec.target_var,
            "year": year,
            "input": str(infile),
            "output": str(outfile),
            "status": "skipped_exists",
        }

    if not file_nonzero(infile):
        return {
            "dataset": spec.name,
            "variable": spec.short_name,
            "agwise_variable": spec.target_var,
            "year": year,
            "input": str(infile),
            "output": str(outfile),
            "status": "missing_input",
        }

    tmp_out = outfile.with_suffix(outfile.suffix + ".part")
    if tmp_out.exists():
        tmp_out.unlink()

    try:
        ds = open_with_earthkit(infile, chunks={"time": 365})
        ds = standardize_coord_names(ds)
        ds = normalize_longitude(ds)
        ds = crop_bbox(ds, bbox)
        ds = apply_daily_aggregation(ds, spec.daily_aggregation)

        src_var = select_source_variable(ds, spec.source_vars)
        da = ds[src_var]
        da = apply_unit_conversion(da, spec.unit_conversion)

        out = da.to_dataset(name=spec.target_var)
        out = standardize_coord_names(out)
        out = normalize_longitude(out)
        out = crop_bbox(out, bbox)

        for coord in ["time", "lat", "lon"]:
            if coord in out.coords:
                try:
                    out = out.sortby(coord)
                except Exception:
                    pass

        if "lat" in out.dims and out.sizes["lat"] == 0:
            raise ValueError(f"Latitude crop produced zero rows for bbox={bbox}")
        if "lon" in out.dims and out.sizes["lon"] == 0:
            raise ValueError(f"Longitude crop produced zero columns for bbox={bbox}")

        out = set_common_attrs(out, spec, start_year, end_year, bbox)
        out[spec.target_var].attrs.update(
            {
                "long_name": spec.metadata.get("long_name", spec.target_var),
                "source_variable": src_var,
                "agwise_variable": spec.target_var,
            }
        )
        for key, value in spec.metadata.items():
            if value is not None:
                out[spec.target_var].attrs[str(key)] = str(value)

        out.to_netcdf(
            tmp_out,
            engine="netcdf4",
            encoding=encoding_for(out, spec.compression_level, spec.dtype),
        )
        tmp_out.replace(outfile)

        try:
            ds.close()
            out.close()
        except Exception:
            pass

        return {
            "dataset": spec.name,
            "variable": spec.short_name,
            "agwise_variable": spec.target_var,
            "year": year,
            "input": str(infile),
            "output": str(outfile),
            "status": "processed",
            "source_variable": src_var,
            "size_bytes": outfile.stat().st_size,
        }
    except Exception as exc:
        if tmp_out.exists():
            tmp_out.unlink(missing_ok=True)
        return {
            "dataset": spec.name,
            "variable": spec.short_name,
            "agwise_variable": spec.target_var,
            "year": year,
            "input": str(infile),
            "output": str(outfile),
            "status": "failed",
            "error": repr(exc),
            "traceback": traceback.format_exc(limit=8),
        }


def merge_standardized_years(
    spec: HistoricalDatasetSpec,
    data_root: Path,
    years: Sequence[int],
    start_year: int,
    end_year: int,
    bbox: Tuple[float, float, float, float],
    overwrite: bool,
) -> Dict[str, Any]:
    outfile = spec.output_path(data_root, start_year, end_year)
    ensure_dir(outfile.parent)

    if file_nonzero(outfile) and not overwrite:
        return {
            "dataset": spec.name,
            "variable": spec.short_name,
            "agwise_variable": spec.target_var,
            "output": str(outfile),
            "status": "skipped_exists",
        }

    files = [spec.standardized_path(data_root, year) for year in years]
    existing_files = [path for path in files if file_nonzero(path)]

    if not existing_files:
        return {
            "dataset": spec.name,
            "variable": spec.short_name,
            "agwise_variable": spec.target_var,
            "output": str(outfile),
            "status": "failed_no_standardized_files",
            "n_files": 0,
        }

    tmp_out = outfile.with_suffix(outfile.suffix + ".part")
    if tmp_out.exists():
        tmp_out.unlink()

    try:
        LOG.info("Merging %s annual files for %s", len(existing_files), spec.short_name)
        ds = xr.open_mfdataset(
            [str(path) for path in existing_files],
            combine="by_coords",
            parallel=True,
            chunks={"time": 365},
            decode_times=True,
        )
        ds = standardize_coord_names(ds)

        if "time" in ds.coords:
            ds = ds.sortby("time")
            index = ds.indexes.get("time")
            if index is not None and index.has_duplicates:
                _, unique_idx = np.unique(index.values, return_index=True)
                ds = ds.isel(time=np.sort(unique_idx))

            # Keep exactly requested period if possible.
            ds = ds.sel(time=slice(f"{start_year}-01-01", f"{end_year}-12-31"))

        ds = set_common_attrs(ds, spec, start_year, end_year, bbox)
        ds.to_netcdf(
            tmp_out,
            engine="netcdf4",
            encoding=encoding_for(ds, spec.compression_level, spec.dtype),
        )
        tmp_out.replace(outfile)
        ds.close()

        return {
            "dataset": spec.name,
            "variable": spec.short_name,
            "agwise_variable": spec.target_var,
            "output": str(outfile),
            "status": "merged",
            "n_files": len(existing_files),
            "size_bytes": outfile.stat().st_size,
        }
    except Exception as exc:
        if tmp_out.exists():
            tmp_out.unlink(missing_ok=True)
        return {
            "dataset": spec.name,
            "variable": spec.short_name,
            "agwise_variable": spec.target_var,
            "output": str(outfile),
            "status": "failed",
            "n_files": len(existing_files),
            "error": repr(exc),
            "traceback": traceback.format_exc(limit=8),
        }


# =============================================================================
# QC and metadata tables
# =============================================================================


def qc_one_file(
    spec: HistoricalDatasetSpec,
    path: Path,
    start_year: int,
    end_year: int,
) -> Dict[str, Any]:
    row: Dict[str, Any] = {
        "dataset": spec.name,
        "dataset_type": "historical_observation",
        "variable": spec.short_name,
        "agwise_variable": spec.target_var,
        "path": str(path),
        "exists": path.exists(),
        "size_bytes": path.stat().st_size if path.exists() else 0,
        "expected_days": expected_days(start_year, end_year),
    }

    if not file_nonzero(path):
        row["status"] = "missing_or_empty"
        return row

    try:
        ds = xr.open_dataset(path, decode_times=True)
        row["data_vars"] = ";".join(list(ds.data_vars))
        row["dims"] = json.dumps({k: int(v) for k, v in ds.sizes.items()})

        if spec.target_var in ds:
            arr = ds[spec.target_var]
            row["units"] = arr.attrs.get("units", "")
            row["long_name"] = arr.attrs.get("long_name", "")
            row["source_variable"] = arr.attrs.get("source_variable", "")
            if arr.size <= 100_000_000:
                row["missing_count"] = int(arr.isnull().sum().values)
            else:
                row["missing_count"] = "not_counted_large_array"

        if "time" in ds.coords:
            times = pd.to_datetime(ds["time"].values)
            if len(times) > 0:
                row["time_start"] = str(times.min())
                row["time_end"] = str(times.max())
                row["n_time"] = len(times)
                row["time_coverage_ok"] = len(times) == expected_days(start_year, end_year)

        if "lat" in ds.coords:
            row["lat_min"] = float(ds["lat"].min())
            row["lat_max"] = float(ds["lat"].max())
            row["n_lat"] = int(ds.sizes.get("lat", ds["lat"].size))

        if "lon" in ds.coords:
            row["lon_min"] = float(ds["lon"].min())
            row["lon_max"] = float(ds["lon"].max())
            row["n_lon"] = int(ds.sizes.get("lon", ds["lon"].size))

        row["status"] = "ok"
        ds.close()
    except Exception as exc:
        row["status"] = "failed"
        row["error"] = repr(exc)

    return row


def variable_mapping_rows(specs: Sequence[HistoricalDatasetSpec]) -> List[Dict[str, Any]]:
    rows = []
    for spec in specs:
        rows.append(
            {
                "short_name": spec.short_name,
                "agwise_variable": spec.target_var,
                "source_dataset": spec.metadata.get("source_dataset", spec.name),
                "source_variable_standard_name": spec.metadata.get("source_variable_standard_name", ""),
                "accepted_source_variable_aliases": ";".join(spec.source_vars),
                "long_name": spec.metadata.get("long_name", ""),
                "units": spec.metadata.get("units", ""),
                "aggregation": spec.metadata.get("aggregation", ""),
                "input_dir": spec.input_dir,
                "output_template": spec.output_template,
            }
        )
    return rows


def data_manifest_rows(
    specs: Sequence[HistoricalDatasetSpec],
    data_root: Path,
    start_year: int,
    end_year: int,
) -> List[Dict[str, Any]]:
    rows = []
    for spec in specs:
        out = spec.output_path(data_root, start_year, end_year)
        rows.append(
            {
                "dataset_type": "historical_observation",
                "dataset": spec.name,
                "variable": spec.short_name,
                "agwise_variable": spec.target_var,
                "source_dataset": spec.metadata.get("source_dataset", spec.name),
                "start_year": start_year,
                "end_year": end_year,
                "input_dir": str(data_root / spec.input_dir),
                "standardized_dir": str(data_root / spec.standardized_dir),
                "final_output": str(out),
                "exists": out.exists(),
                "size_bytes": out.stat().st_size if out.exists() else 0,
            }
        )
    return rows


# =============================================================================
# CLI
# =============================================================================


def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Parallel Earthkit/xarray workflow for AgWise historical observation climate datasets."
    )
    parser.add_argument(
        "--data-root",
        default=None,
        help=(
            "Path to Data/Global_GeoData. If omitted, the script assumes it is running from "
            "datasourcing/common_data and uses ../Data/Global_GeoData."
        ),
    )
    parser.add_argument("--start-year", type=int, default=1984)
    parser.add_argument("--end-year", type=int, default=2024)
    parser.add_argument("--bbox", default="-25,60,-40,40", help="lon_min,lon_max,lat_min,lat_max")
    parser.add_argument("--workers", type=int, default=max(1, min(8, os.cpu_count() or 2)))
    parser.add_argument("--run-downloads", action="store_true", help="Download CHIRPS/CHIRTS files with URL templates.")
    parser.add_argument("--run-processing", action="store_true", help="Crop, rename, standardize, and merge annual files.")
    parser.add_argument("--run-qc", action="store_true", help="Generate QC summary for final merged files.")
    parser.add_argument("--overwrite-downloads", action="store_true")
    parser.add_argument("--overwrite-processing", action="store_true")
    parser.add_argument("--overwrite-merge", action="store_true")
    parser.add_argument("--require-complete-years", action="store_true")
    parser.add_argument("--clean-temp", action="store_true")
    parser.add_argument("--only", nargs="*", default=None, help="Optional variable subset, e.g. PRCP TMAX TMIN TEMP SRAD")
    parser.add_argument("--write-default-config", type=Path, default=None, help="Write resolved historical dataset specs to JSON and exit.")
    parser.add_argument("--verbose", action="store_true")
    return parser.parse_args(argv)


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = parse_args(argv)
    setup_logging(args.verbose)

    if args.start_year > args.end_year:
        LOG.error("--start-year must be <= --end-year")
        return 2

    script_path = Path(__file__)
    data_root = Path(args.data_root).expanduser().resolve() if args.data_root else infer_data_root(script_path).resolve()
    bbox = parse_bbox(args.bbox)
    years = list(range(args.start_year, args.end_year + 1))

    specs = historical_specs()
    if args.only:
        selected = {x.upper() for x in args.only}
        specs = [
            spec
            for spec in specs
            if spec.short_name.upper() in selected or spec.target_var.upper() in selected
        ]

    if not specs:
        LOG.error("No historical dataset specs selected.")
        return 2

    if args.write_default_config:
        write_json(args.write_default_config, {"datasets": [asdict(spec) for spec in specs]})
        LOG.info("Wrote historical config: %s", args.write_default_config)
        return 0

    ensure_dir(data_root)
    metadata_dir = ensure_dir(data_root / "metadata")

    LOG.info("Historical observation workflow only. Hindcast processing is intentionally excluded.")
    LOG.info("Data root : %s", data_root)
    LOG.info("Years     : %s-%s", args.start_year, args.end_year)
    LOG.info("BBOX      : %s", args.bbox)
    LOG.info("Workers   : %s", args.workers)
    LOG.info("Datasets  : %s", ", ".join([f"{s.short_name}({s.name})" for s in specs]))

    write_json(
        metadata_dir / f"historical_run_config_{args.start_year}_{args.end_year}.json",
        {
            "args": vars(args),
            "data_root": str(data_root),
            "bbox": bbox,
            "earthkit_data_available": ekd is not None,
            "earthkit_transforms_available": ekt is not None,
            "specs": [asdict(spec) for spec in specs],
        },
    )
    write_csv(metadata_dir / "historical_variable_mapping.csv", variable_mapping_rows(specs))

    if args.run_downloads:
        download_rows = run_downloads(specs, data_root, years, args.workers, args.overwrite_downloads)
        write_csv(metadata_dir / f"historical_download_manifest_{args.start_year}_{args.end_year}.csv", download_rows)

        failed_downloads = [row for row in download_rows if row.get("status") == "failed"]
        if failed_downloads and args.require_complete_years:
            LOG.error("Some downloads failed and --require-complete-years was set.")
            write_csv(metadata_dir / f"historical_download_failed_{args.start_year}_{args.end_year}.csv", failed_downloads)
            return 3

    process_rows: List[Dict[str, Any]] = []
    if args.run_processing:
        LOG.info("Starting annual preprocessing jobs")
        jobs = []
        with ProcessPoolExecutor(max_workers=args.workers) as executor:
            for spec in specs:
                spec_dict = asdict(spec)
                for year in years:
                    jobs.append(
                        executor.submit(
                            preprocess_one_year,
                            spec_dict,
                            str(data_root),
                            year,
                            bbox,
                            args.start_year,
                            args.end_year,
                            args.overwrite_processing,
                        )
                    )

            for future in as_completed(jobs):
                row = future.result()
                process_rows.append(row)
                LOG.info(
                    "Preprocess result: %s | %s | %s",
                    row.get("status"),
                    row.get("variable"),
                    row.get("year"),
                )

        write_csv(metadata_dir / f"historical_preprocess_manifest_{args.start_year}_{args.end_year}.csv", process_rows)

        bad_process = [row for row in process_rows if row.get("status") in {"missing_input", "failed"}]
        if bad_process and args.require_complete_years:
            LOG.error("Missing or failed annual files found and --require-complete-years was set.")
            write_csv(metadata_dir / f"historical_preprocess_failed_{args.start_year}_{args.end_year}.csv", bad_process)
            return 4

        merge_rows: List[Dict[str, Any]] = []
        for spec in specs:
            row = merge_standardized_years(
                spec,
                data_root,
                years,
                args.start_year,
                args.end_year,
                bbox,
                overwrite=args.overwrite_merge,
            )
            merge_rows.append(row)
            LOG.info("Merge result: %s | %s", row.get("status"), row.get("output"))

        write_csv(metadata_dir / f"historical_merge_manifest_{args.start_year}_{args.end_year}.csv", merge_rows)
        write_csv(metadata_dir / f"historical_data_manifest_{args.start_year}_{args.end_year}.csv", data_manifest_rows(specs, data_root, args.start_year, args.end_year))

        failed_merge = [row for row in merge_rows if str(row.get("status", "")).startswith("failed")]
        if failed_merge and args.require_complete_years:
            LOG.error("Some merge jobs failed and --require-complete-years was set.")
            return 5

    if args.run_qc:
        qc_rows = [qc_one_file(spec, spec.output_path(data_root, args.start_year, args.end_year), args.start_year, args.end_year) for spec in specs]
        write_csv(metadata_dir / f"historical_qc_summary_{args.start_year}_{args.end_year}.csv", qc_rows)
        LOG.info("QC summary written: %s", metadata_dir / f"historical_qc_summary_{args.start_year}_{args.end_year}.csv")

    if args.clean_temp:
        for spec in specs:
            tmp_dir = data_root / spec.standardized_dir
            if tmp_dir.exists():
                LOG.info("Cleaning temporary standardized directory: %s", tmp_dir)
                shutil.rmtree(tmp_dir)

    LOG.info("Historical observation workflow completed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
