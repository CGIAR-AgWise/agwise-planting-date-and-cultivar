#!/usr/bin/env python3
"""
AgWise parallel Earthkit datasourcing workflow
=============================================

Purpose
-------
One-time parallel download, crop, variable standardization, temporal harmonization,
merge, and QC for historical observations and optional model hindcast NetCDF/GRIB files.

Designed for the AgWise seasonal forecast-to-DSSAT dataops workflow.

Author      : Dr. Jemal Seid Ahmed
Affiliation : Alliance of Bioversity International and CIAT
Program     : CGIAR Climate Action Science Program
Email       : J.Ahmed@cgiar.org

Default period: 1984-2024
Default domain: Africa bbox = -25,60,-40,40  meaning lon_min,lon_max,lat_min,lat_max

Key design
----------
- earthkit-data is used first for data ingestion and conversion to xarray.
- xarray/Dask are used for scalable NetCDF manipulation and writing.
- earthkit-transforms is used when daily temporal aggregation is requested.
- ThreadPoolExecutor is used for network downloads.
- ProcessPoolExecutor is used for independent annual/member preprocessing jobs.
- Final merge is done per variable after yearly standardized temporary files are written.

Install example
---------------
micromamba create -n agwise-earthkit -c conda-forge \
  python=3.11 xarray dask netcdf4 h5netcdf pandas numpy requests \
  earthkit-data earthkit-transforms cfgrib eccodes
micromamba activate agwise-earthkit

Basic use
---------
python common_data/agwise_parallel_earthkit_datasourcing.py \
  --data-root agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData \
  --start-year 1984 --end-year 2024 \
  --workers 8 \
  --run-downloads --run-processing --run-qc

Processing only
---------------
python common_data/agwise_parallel_earthkit_datasourcing.py \
  --data-root agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData \
  --start-year 1984 --end-year 2024 \
  --workers 8 \
  --run-processing --run-qc

Optional hindcast config
------------------------
python common_data/agwise_parallel_earthkit_datasourcing.py \
  --data-root agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData \
  --start-year 1984 --end-year 2024 \
  --hindcast-config common_data/hindcast_config.json \
  --workers 8 --run-downloads --run-processing --run-qc

Example hindcast_config.json
----------------------------
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
"""

from __future__ import annotations

import argparse
import csv
import json
import logging
import os
import shutil
import sys
import tempfile
import time
import traceback
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor, as_completed
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import numpy as np
import pandas as pd
import xarray as xr

try:
    import earthkit.data as ekd
except Exception:  # pragma: no cover - optional dependency at import time
    ekd = None

try:
    import earthkit.transforms as ekt
except Exception:  # pragma: no cover - optional dependency at import time
    ekt = None


# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------

LOG = logging.getLogger("agwise-earthkit")


def setup_logging(verbose: bool = False) -> None:
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s | %(levelname)-8s | %(processName)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )


# -----------------------------------------------------------------------------
# Dataset specification
# -----------------------------------------------------------------------------


@dataclass
class DatasetSpec:
    """Configuration for one variable stack."""

    dataset_type: str
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
    source_filename_template: Optional[str] = None
    unit_conversion: Optional[str] = None
    daily_aggregation: Optional[str] = None
    compression_level: int = 4
    dtype: str = "float32"
    metadata: Dict[str, Any] = field(default_factory=dict)

    def input_path(self, data_root: Path, year: int) -> Path:
        base = data_root / self.input_dir
        if "{year}" in self.file_pattern:
            return base / self.file_pattern.format(year=year)
        # If a wildcard pattern is supplied, pick a file containing the year.
        matches = sorted(base.glob(self.file_pattern))
        year_matches = [p for p in matches if str(year) in p.name]
        if year_matches:
            return year_matches[0]
        return base / f"{year}.nc"

    def standardized_path(self, data_root: Path, year: int) -> Path:
        safe = self.target_var.replace(".", "_")
        return data_root / self.standardized_dir / f"{year}_{safe}_africa_standardized.nc"

    def output_path(self, data_root: Path, start: int, end: int) -> Path:
        return data_root / self.output_dir / self.output_template.format(
            short_name=self.short_name,
            start=start,
            end=end,
            name=self.name,
            target_var=self.target_var.replace(".", "_"),
        )

    def url_for_year(self, year: int) -> Optional[str]:
        if not self.url_template:
            return None
        return self.url_template.format(year=year)



def default_historical_specs() -> List[DatasetSpec]:
    """Default AgWise historical observation stacks."""

    return [
        DatasetSpec(
            dataset_type="historical",
            name="CHIRPS_v3_RNL",
            short_name="PRCP",
            target_var="AGRO.PRCP",
            source_vars=["precipitation_flux", "precip", "precipitation", "rainfall"],
            input_dir="Landing/Rainfall/chirps_v3",
            standardized_dir="Processed/Africa/CDO_Harmonized/tmp_earthkit/PRCP",
            output_dir="Processed/Africa/CDO_Harmonized",
            file_pattern="{year}.nc",
            output_template="Daily_PRCP_{start}_{end}.nc",
            url_template=(
                "https://data.chc.ucsb.edu/products/CHIRPS/v3.0/daily/final/rnl/"
                "netcdf/byYear/chirps-v3.0.rnl.{year}.days_p05.nc"
            ),
            unit_conversion=None,
            daily_aggregation=None,
            metadata={
                "long_name": "Daily precipitation flux",
                "source_dataset": "UCSB CHC CHIRPS v3.0 RNL",
                "units": "mm/day",
            },
        ),
        DatasetSpec(
            dataset_type="historical",
            name="CHIRTS_ERA5_TMAX",
            short_name="TMAX",
            target_var="AGRO.TMAX",
            source_vars=["Tmax", "tmax", "maximum_temperature", "2m_temperature"],
            input_dir="Landing/TemperatureMax/CHIRTS-ERA5",
            standardized_dir="Processed/Africa/CDO_Harmonized/tmp_earthkit/TMAX",
            output_dir="Processed/Africa/CDO_Harmonized",
            file_pattern="{year}.nc",
            output_template="Daily_TMAX_{start}_{end}.nc",
            url_template=(
                "https://data.chc.ucsb.edu/experimental/CHIRTS-ERA5/tmax/netcdf/"
                "daily/CHIRTS-ERA5.daily_Tmax.{year}.nc"
            ),
            unit_conversion=None,
            daily_aggregation=None,
            metadata={
                "long_name": "Daily maximum 2m air temperature",
                "source_dataset": "UCSB CHC CHIRTS-ERA5",
                "units": "degC",
                "aggregation": "24_hour_maximum",
            },
        ),
        DatasetSpec(
            dataset_type="historical",
            name="CHIRTS_ERA5_TMIN",
            short_name="TMIN",
            target_var="AGRO.TMIN",
            source_vars=["Tmin", "tmin", "minimum_temperature", "2m_temperature"],
            input_dir="Landing/TemperatureMin/CHIRTS-ERA5",
            standardized_dir="Processed/Africa/CDO_Harmonized/tmp_earthkit/TMIN",
            output_dir="Processed/Africa/CDO_Harmonized",
            file_pattern="{year}.nc",
            output_template="Daily_TMIN_{start}_{end}.nc",
            url_template=(
                "https://data.chc.ucsb.edu/experimental/CHIRTS-ERA5/tmin/netcdf/"
                "daily/CHIRTS-ERA5.daily_Tmin.{year}.nc"
            ),
            unit_conversion=None,
            daily_aggregation=None,
            metadata={
                "long_name": "Daily minimum 2m air temperature",
                "source_dataset": "UCSB CHC CHIRTS-ERA5",
                "units": "degC",
                "aggregation": "24_hour_minimum",
            },
        ),
        DatasetSpec(
            dataset_type="historical",
            name="AgERA5_TEMP",
            short_name="TEMP",
            target_var="AGRO.TEMP",
            source_vars=["temperature", "temp", "tmean", "Tmean", "2m_temperature"],
            input_dir="Landing/TemperatureMean/AgEra",
            standardized_dir="Processed/Africa/CDO_Harmonized/tmp_earthkit/TEMP",
            output_dir="Processed/Africa/CDO_Harmonized",
            file_pattern="{year}.nc",
            output_template="Daily_TEMP_{start}_{end}.nc",
            url_template=None,
            unit_conversion=None,
            daily_aggregation=None,
            metadata={
                "long_name": "Daily mean 2m air temperature",
                "source_dataset": "AgERA5",
                "units": "degC",
                "aggregation": "24_hour_mean",
            },
        ),
        DatasetSpec(
            dataset_type="historical",
            name="AgERA5_SRAD",
            short_name="SRAD",
            target_var="AGRO.SRAD",
            source_vars=["solar_radiation_flux", "solar_radiation", "srad", "SRAD", "ssrd"],
            input_dir="Landing/SolarRadiation/AgEra",
            standardized_dir="Processed/Africa/CDO_Harmonized/tmp_earthkit/SRAD",
            output_dir="Processed/Africa/CDO_Harmonized",
            file_pattern="{year}.nc",
            output_template="Daily_SRAD_{start}_{end}.nc",
            url_template=None,
            unit_conversion=None,
            daily_aggregation=None,
            metadata={
                "long_name": "Daily solar radiation flux",
                "source_dataset": "AgERA5",
                "units": "MJ m-2 day-1",
            },
        ),
    ]


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------


def parse_bbox(value: str) -> Tuple[float, float, float, float]:
    parts = [float(x.strip()) for x in value.split(",")]
    if len(parts) != 4:
        raise ValueError("bbox must contain lon_min,lon_max,lat_min,lat_max")
    lon_min, lon_max, lat_min, lat_max = parts
    if lon_min >= lon_max:
        raise ValueError("bbox lon_min must be < lon_max")
    if lat_min >= lat_max:
        raise ValueError("bbox lat_min must be < lat_max")
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


# -----------------------------------------------------------------------------
# Download
# -----------------------------------------------------------------------------


def download_one(url: str, dest: Path, overwrite: bool = False, retries: int = 5, timeout: int = 120) -> Dict[str, Any]:
    ensure_dir(dest.parent)

    if file_nonzero(dest) and not overwrite:
        return {"path": str(dest), "url": url, "status": "skipped_exists", "size": dest.stat().st_size}

    remove_zero_byte(dest)

    tmp = dest.with_suffix(dest.suffix + ".part")
    if tmp.exists():
        tmp.unlink()

    last_error = None
    for attempt in range(1, retries + 1):
        try:
            LOG.info("Downloading [%s/%s]: %s", attempt, retries, url)
            request = Request(url, headers={"User-Agent": "AgWise-Earthkit-Datasourcing/1.0"})
            with urlopen(request, timeout=timeout) as response, tmp.open("wb") as out:
                shutil.copyfileobj(response, out, length=1024 * 1024)
            tmp.replace(dest)
            return {"path": str(dest), "url": url, "status": "downloaded", "size": dest.stat().st_size}
        except (HTTPError, URLError, TimeoutError, OSError) as exc:
            last_error = repr(exc)
            LOG.warning("Download failed attempt %s for %s: %s", attempt, url, exc)
            if tmp.exists():
                tmp.unlink(missing_ok=True)
            time.sleep(min(60, 2 * attempt))

    return {"path": str(dest), "url": url, "status": "failed", "error": last_error}


def build_download_jobs(specs: Sequence[DatasetSpec], data_root: Path, years: Sequence[int]) -> List[Tuple[str, Path]]:
    jobs: List[Tuple[str, Path]] = []
    for spec in specs:
        if not spec.url_template:
            LOG.info("No URL template for %s; assuming files already exist in %s", spec.short_name, data_root / spec.input_dir)
            continue
        for year in years:
            url = spec.url_for_year(year)
            if url is None:
                continue
            jobs.append((url, spec.input_path(data_root, year)))
    return jobs


def run_downloads(specs: Sequence[DatasetSpec], data_root: Path, years: Sequence[int], workers: int, overwrite: bool) -> List[Dict[str, Any]]:
    jobs = build_download_jobs(specs, data_root, years)
    if not jobs:
        LOG.info("No download jobs to run.")
        return []

    LOG.info("Starting %s download jobs with %s workers", len(jobs), workers)
    rows: List[Dict[str, Any]] = []
    with ThreadPoolExecutor(max_workers=workers) as executor:
        futures = [executor.submit(download_one, url, dest, overwrite) for url, dest in jobs]
        for future in as_completed(futures):
            row = future.result()
            rows.append(row)
            LOG.info("Download result: %s | %s", row.get("status"), row.get("path"))
    return rows


# -----------------------------------------------------------------------------
# Earthkit/xarray manipulation
# -----------------------------------------------------------------------------


def open_with_earthkit(path: Path, chunks: Optional[Dict[str, int]] = None) -> xr.Dataset:
    """Open using earthkit-data first; fall back to xarray for robust NetCDF chunking."""

    if ekd is not None:
        try:
            obj = ekd.from_source("file", str(path))
            ds = obj.to_xarray()
            if isinstance(ds, xr.DataArray):
                ds = ds.to_dataset(name=ds.name or "variable")
            if chunks:
                possible_chunks = {k: v for k, v in chunks.items() if k in ds.dims}
                if possible_chunks:
                    ds = ds.chunk(possible_chunks)
            return ds
        except Exception as exc:
            LOG.debug("earthkit-data could not open %s; falling back to xarray: %s", path, exc)

    try:
        return xr.open_dataset(path, chunks=chunks or {})
    except Exception:
        # GRIB fallback if cfgrib/eccodes are installed.
        return xr.open_dataset(path, engine="cfgrib", chunks=chunks or {})


def standardize_coord_names(ds: xr.Dataset) -> xr.Dataset:
    rename: Dict[str, str] = {}

    lon_candidates = ["longitude", "lon", "LONGITUDE", "x", "X"]
    lat_candidates = ["latitude", "lat", "LATITUDE", "y", "Y"]
    time_candidates = ["valid_time", "time", "TIME", "date"]

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
    # Rename valid_time only if it is a dimension. For seasonal hindcasts, time+step may need to remain as-is.
    for name in time_candidates:
        if name in ds.dims:
            if name != "time":
                rename[name] = "time"
            break

    if rename:
        ds = ds.rename(rename)

    return ds


def normalize_longitude(ds: xr.Dataset) -> xr.Dataset:
    if "lon" not in ds.coords:
        return ds
    lon = ds["lon"]
    try:
        lon_min = float(lon.min())
        lon_max = float(lon.max())
    except Exception:
        return ds

    # Convert 0..360 to -180..180 when needed.
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
        "lat_bnds", "lon_bnds", "time_bnds", "latitude_bnds", "longitude_bnds",
        "spatial_ref", "crs", "rotated_pole", "forecast_reference_time", "height",
    }
    candidates = [v for v in ds.data_vars if v not in ignored]
    if len(candidates) == 1:
        return candidates[0]
    if candidates:
        LOG.warning("No alias matched. Using first data variable: %s from %s", candidates[0], candidates)
        return candidates[0]
    raise ValueError("No data variable found in dataset")


def apply_unit_conversion(da: xr.DataArray, conversion: Optional[str]) -> xr.DataArray:
    if not conversion:
        return da
    conversion = conversion.lower()
    if conversion in {"k_to_c", "kelvin_to_celsius"}:
        da = da - 273.15
        da.attrs["units"] = "degC"
    elif conversion in {"m_to_mm", "metre_to_mm", "meter_to_mm"}:
        da = da * 1000.0
        da.attrs["units"] = "mm"
    elif conversion in {"kg_m2_s_to_mm_day", "flux_to_mm_day"}:
        da = da * 86400.0
        da.attrs["units"] = "mm/day"
    elif conversion in {"j_m2_to_mj_m2", "j_to_mj"}:
        da = da / 1_000_000.0
        da.attrs["units"] = "MJ m-2"
    else:
        raise ValueError(f"Unsupported unit_conversion: {conversion}")
    da.attrs["agwise_unit_conversion"] = conversion
    return da


def apply_daily_aggregation(ds: xr.Dataset, aggregation: Optional[str]) -> xr.Dataset:
    """Apply daily aggregation with earthkit-transforms first; xarray fallback."""

    if not aggregation:
        return ds

    aggregation = aggregation.lower()
    if aggregation not in {"daily_mean", "daily_min", "daily_max", "daily_sum"}:
        raise ValueError(f"Unsupported daily_aggregation: {aggregation}")

    if "time" not in ds.dims and "time" not in ds.coords:
        LOG.warning("daily_aggregation=%s requested but no time coordinate found; skipping", aggregation)
        return ds

    if ekt is not None:
        try:
            func = getattr(ekt.temporal, aggregation)
            return func(ds)
        except Exception as exc:
            LOG.warning("earthkit-transforms %s failed; falling back to xarray resample: %s", aggregation, exc)

    how = aggregation.replace("daily_", "")
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


def set_common_attrs(ds: xr.Dataset, spec: DatasetSpec, start_year: int, end_year: int, bbox: Tuple[float, float, float, float]) -> xr.Dataset:
    ds.attrs.update(
        {
            "title": f"AgWise standardized {spec.short_name} climate data",
            "institution": "Alliance of Bioversity International and CIAT / CGIAR Climate Action Science Program",
            "dataset_type": spec.dataset_type,
            "source_dataset": spec.metadata.get("source_dataset", spec.name),
            "agwise_variable": spec.target_var,
            "period": f"{start_year}-{end_year}",
            "spatial_domain": "Africa",
            "bbox_lon_min_lon_max_lat_min_lat_max": ",".join(map(str, bbox)),
            "processing_note": "Opened with ECMWF earthkit-data when available; manipulated with xarray/Dask; temporal aggregation uses earthkit-transforms when requested.",
            "history": f"Created by agwise_parallel_earthkit_datasourcing.py on {pd.Timestamp.utcnow().isoformat()}",
        }
    )
    return ds


def encoding_for(ds: xr.Dataset, compression_level: int, dtype: str = "float32") -> Dict[str, Dict[str, Any]]:
    enc: Dict[str, Dict[str, Any]] = {}
    for var in ds.data_vars:
        if np.issubdtype(ds[var].dtype, np.floating):
            enc[var] = {
                "zlib": True,
                "complevel": int(compression_level),
                "shuffle": True,
                "dtype": dtype,
                "_FillValue": np.float32(np.nan) if dtype == "float32" else np.nan,
            }
        else:
            enc[var] = {"zlib": True, "complevel": int(compression_level), "shuffle": True}
    return enc


def preprocess_one_year(
    spec_dict: Dict[str, Any],
    data_root_str: str,
    year: int,
    bbox: Tuple[float, float, float, float],
    start_year: int,
    end_year: int,
    overwrite: bool = False,
) -> Dict[str, Any]:
    """Worker-safe preprocessing function."""

    spec = DatasetSpec(**spec_dict)
    data_root = Path(data_root_str)
    infile = spec.input_path(data_root, year)
    outfile = spec.standardized_path(data_root, year)
    ensure_dir(outfile.parent)

    if file_nonzero(outfile) and not overwrite:
        return {
            "dataset": spec.name,
            "variable": spec.target_var,
            "year": year,
            "input": str(infile),
            "output": str(outfile),
            "status": "skipped_exists",
        }

    if not file_nonzero(infile):
        return {
            "dataset": spec.name,
            "variable": spec.target_var,
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

        # Keep only the selected variable, renamed to AGRO convention.
        out = da.to_dataset(name=spec.target_var)

        # Preserve important coordinates if present.
        out = standardize_coord_names(out)
        out = normalize_longitude(out)
        out = crop_bbox(out, bbox)

        if "time" in out.coords:
            try:
                out = out.sortby("time")
            except Exception:
                pass
        if "lat" in out.coords:
            try:
                out = out.sortby("lat")
            except Exception:
                pass
        if "lon" in out.coords:
            try:
                out = out.sortby("lon")
            except Exception:
                pass

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

        # Remove impossible all-empty crops early.
        if "lat" in out.dims and out.dims["lat"] == 0:
            raise ValueError(f"Latitude crop produced zero rows for bbox={bbox}")
        if "lon" in out.dims and out.dims["lon"] == 0:
            raise ValueError(f"Longitude crop produced zero columns for bbox={bbox}")

        out.to_netcdf(tmp_out, engine="netcdf4", encoding=encoding_for(out, spec.compression_level, spec.dtype))
        tmp_out.replace(outfile)
        try:
            ds.close()
            out.close()
        except Exception:
            pass

        return {
            "dataset": spec.name,
            "variable": spec.target_var,
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
            "variable": spec.target_var,
            "year": year,
            "input": str(infile),
            "output": str(outfile),
            "status": "failed",
            "error": repr(exc),
            "traceback": traceback.format_exc(limit=8),
        }


# -----------------------------------------------------------------------------
# Merge and QC
# -----------------------------------------------------------------------------


def merge_standardized_years(
    spec: DatasetSpec,
    data_root: Path,
    years: Sequence[int],
    start_year: int,
    end_year: int,
    bbox: Tuple[float, float, float, float],
    overwrite: bool = False,
) -> Dict[str, Any]:
    files = [spec.standardized_path(data_root, y) for y in years]
    files = [p for p in files if file_nonzero(p)]
    outfile = spec.output_path(data_root, start_year, end_year)
    ensure_dir(outfile.parent)

    if file_nonzero(outfile) and not overwrite:
        return {
            "dataset": spec.name,
            "variable": spec.target_var,
            "output": str(outfile),
            "status": "skipped_exists",
            "n_files": len(files),
        }

    if not files:
        return {
            "dataset": spec.name,
            "variable": spec.target_var,
            "output": str(outfile),
            "status": "failed_no_standardized_files",
            "n_files": 0,
        }

    LOG.info("Merging %s files for %s -> %s", len(files), spec.target_var, outfile)
    tmp_out = outfile.with_suffix(outfile.suffix + ".part")
    if tmp_out.exists():
        tmp_out.unlink()

    try:
        ds = xr.open_mfdataset(
            [str(p) for p in files],
            combine="by_coords",
            parallel=True,
            chunks={"time": 365},
            decode_times=True,
        )
        ds = standardize_coord_names(ds)
        if "time" in ds.coords:
            ds = ds.sortby("time")
            # Drop duplicated timestamps if any.
            index = ds.indexes.get("time")
            if index is not None and index.has_duplicates:
                _, unique_idx = np.unique(index.values, return_index=True)
                ds = ds.isel(time=np.sort(unique_idx))

        ds = set_common_attrs(ds, spec, start_year, end_year, bbox)
        ds.to_netcdf(tmp_out, engine="netcdf4", encoding=encoding_for(ds, spec.compression_level, spec.dtype))
        tmp_out.replace(outfile)
        ds.close()
        return {
            "dataset": spec.name,
            "variable": spec.target_var,
            "output": str(outfile),
            "status": "merged",
            "n_files": len(files),
            "size_bytes": outfile.stat().st_size,
        }
    except Exception as exc:
        if tmp_out.exists():
            tmp_out.unlink(missing_ok=True)
        return {
            "dataset": spec.name,
            "variable": spec.target_var,
            "output": str(outfile),
            "status": "failed",
            "n_files": len(files),
            "error": repr(exc),
            "traceback": traceback.format_exc(limit=8),
        }


def qc_one_file(spec: DatasetSpec, path: Path) -> Dict[str, Any]:
    row: Dict[str, Any] = {
        "dataset": spec.name,
        "dataset_type": spec.dataset_type,
        "variable": spec.target_var,
        "path": str(path),
        "exists": path.exists(),
        "size_bytes": path.stat().st_size if path.exists() else 0,
    }
    if not file_nonzero(path):
        row["status"] = "missing_or_empty"
        return row

    try:
        ds = xr.open_dataset(path, decode_times=True)
        row["data_vars"] = ";".join(list(ds.data_vars))
        row["dims"] = json.dumps({k: int(v) for k, v in ds.dims.items()})
        if spec.target_var in ds:
            arr = ds[spec.target_var]
            row["missing_count"] = int(arr.isnull().sum().values) if arr.size < 100_000_000 else "not_counted_large_array"
            row["units"] = arr.attrs.get("units", "")
        if "time" in ds.coords:
            times = pd.to_datetime(ds["time"].values)
            if len(times) > 0:
                row["time_start"] = str(times.min())
                row["time_end"] = str(times.max())
                row["n_time"] = len(times)
        if "lat" in ds.coords:
            row["lat_min"] = float(ds["lat"].min())
            row["lat_max"] = float(ds["lat"].max())
            row["n_lat"] = int(ds.dims.get("lat", ds["lat"].size))
        if "lon" in ds.coords:
            row["lon_min"] = float(ds["lon"].min())
            row["lon_max"] = float(ds["lon"].max())
            row["n_lon"] = int(ds.dims.get("lon", ds["lon"].size))
        row["status"] = "ok"
        ds.close()
    except Exception as exc:
        row["status"] = "failed"
        row["error"] = repr(exc)
    return row


# -----------------------------------------------------------------------------
# Config loading
# -----------------------------------------------------------------------------


def load_extra_specs(config_path: Optional[Path]) -> List[DatasetSpec]:
    if not config_path:
        return []
    payload = json.loads(config_path.read_text(encoding="utf-8"))
    specs = []
    for item in payload.get("datasets", []):
        specs.append(DatasetSpec(**item))
    return specs


def write_default_config(path: Path) -> None:
    specs = [asdict(s) for s in default_historical_specs()]
    write_json(path, {"datasets": specs})


# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------


def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Parallel Earthkit/xarray datasourcing workflow for AgWise historical and hindcast data."
    )
    parser.add_argument("--data-root", required=True, help="Path to Data/Global_GeoData")
    parser.add_argument("--start-year", type=int, default=1984)
    parser.add_argument("--end-year", type=int, default=2024)
    parser.add_argument("--bbox", default="-25,60,-40,40", help="lon_min,lon_max,lat_min,lat_max")
    parser.add_argument("--workers", type=int, default=max(1, min(8, os.cpu_count() or 2)))
    parser.add_argument("--run-downloads", action="store_true")
    parser.add_argument("--run-processing", action="store_true")
    parser.add_argument("--run-qc", action="store_true")
    parser.add_argument("--overwrite-downloads", action="store_true")
    parser.add_argument("--overwrite-processing", action="store_true")
    parser.add_argument("--overwrite-merge", action="store_true")
    parser.add_argument("--require-complete-years", action="store_true")
    parser.add_argument("--clean-temp", action="store_true")
    parser.add_argument("--hindcast-config", type=Path, default=None, help="Optional JSON config for hindcast/model datasets")
    parser.add_argument("--only", nargs="*", default=None, help="Optional variables to run, e.g. PRCP TMAX TMIN")
    parser.add_argument("--write-default-config", type=Path, default=None, help="Write default config JSON and exit")
    parser.add_argument("--verbose", action="store_true")
    return parser.parse_args(argv)


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = parse_args(argv)
    setup_logging(args.verbose)

    if args.write_default_config:
        write_default_config(args.write_default_config)
        LOG.info("Wrote default config: %s", args.write_default_config)
        return 0

    data_root = Path(args.data_root).expanduser().resolve()
    bbox = parse_bbox(args.bbox)
    years = list(range(args.start_year, args.end_year + 1))
    ensure_dir(data_root)

    specs = default_historical_specs() + load_extra_specs(args.hindcast_config)
    if args.only:
        only = {x.upper() for x in args.only}
        specs = [s for s in specs if s.short_name.upper() in only or s.target_var.upper() in only]

    if not specs:
        LOG.error("No dataset specs selected.")
        return 2

    metadata_dir = data_root / "metadata"
    ensure_dir(metadata_dir)

    LOG.info("Data root : %s", data_root)
    LOG.info("Years     : %s-%s", args.start_year, args.end_year)
    LOG.info("BBOX      : %s", args.bbox)
    LOG.info("Workers   : %s", args.workers)
    LOG.info("Datasets  : %s", ", ".join([f"{s.short_name}({s.name})" for s in specs]))

    # Save run config for reproducibility.
    write_json(
        metadata_dir / f"run_config_{args.start_year}_{args.end_year}.json",
        {
            "args": vars(args),
            "data_root": str(data_root),
            "bbox": bbox,
            "specs": [asdict(s) for s in specs],
        },
    )

    if args.run_downloads:
        download_rows = run_downloads(specs, data_root, years, args.workers, args.overwrite_downloads)
        write_csv(metadata_dir / f"download_manifest_{args.start_year}_{args.end_year}.csv", download_rows)

    process_rows: List[Dict[str, Any]] = []
    if args.run_processing:
        LOG.info("Starting preprocessing jobs")
        jobs = []
        spec_dicts = [asdict(s) for s in specs]
        with ProcessPoolExecutor(max_workers=args.workers) as executor:
            for spec_dict in spec_dicts:
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
                LOG.info("Process result: %s | %s | %s", row.get("status"), row.get("variable"), row.get("year"))

        write_csv(metadata_dir / f"preprocess_manifest_{args.start_year}_{args.end_year}.csv", process_rows)

        if args.require_complete_years:
            bad = [r for r in process_rows if r.get("status") in {"missing_input", "failed"}]
            if bad:
                LOG.error("Missing/failed yearly files found and --require-complete-years was set.")
                write_csv(metadata_dir / f"preprocess_failed_{args.start_year}_{args.end_year}.csv", bad)
                return 3

        merge_rows = []
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
        write_csv(metadata_dir / f"merge_manifest_{args.start_year}_{args.end_year}.csv", merge_rows)

    if args.run_qc:
        qc_rows = []
        for spec in specs:
            qc_rows.append(qc_one_file(spec, spec.output_path(data_root, args.start_year, args.end_year)))
        write_csv(metadata_dir / f"qc_summary_{args.start_year}_{args.end_year}.csv", qc_rows)
        LOG.info("QC summary written: %s", metadata_dir / f"qc_summary_{args.start_year}_{args.end_year}.csv")

    if args.clean_temp:
        for spec in specs:
            tmp_dir = data_root / spec.standardized_dir
            if tmp_dir.exists():
                LOG.info("Cleaning temporary standardized directory: %s", tmp_dir)
                shutil.rmtree(tmp_dir)

    LOG.info("Workflow completed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
