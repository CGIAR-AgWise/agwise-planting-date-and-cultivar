"""
AgWise dailly Seasonal & Agro-Meteorological Data Acquisition Module
====================================================================
Author: Jemal S. Ahmed
Email: jemal.ahmed@cgiar.org
Institution: Alliance of Bioversity International and CIAT (CGIAR)
Date: 2026-05-29

This script provides a unified, reproducible framework for downloading,
standardizing, and preparing agro-climate datasets used in the AgWise and
AgWISE_Forecast workflows. It operationalizes access to Copernicus Climate
Data Store (CDS) resources—supporting both seasonal forecast systems and
agro-meteorological indicators—and ensures that all outputs are transformed
into analysis-ready, quality-controlled NetCDF formats suitable for modelling,
forecast translation, and advisory generation.

Core concept
------------
The module is designed around the principle of *consistent, automated, and
scientifically transparent* data preparation. It abstracts the complexities of
multiple forecast systems, variable conventions, initialization rules, lead-time
structures, and CDS metadata differences into a coherent interface that:

- Harmonizes naming across centres, systems, and variables.
- Applies scientifically appropriate unit conversions and temporal corrections.
- Constructs continuous valid-time coordinates from forecast metadata.
- Produces standardized, downstream-ready climate datasets for analytics,
  DSSAT workflows, skill assessment, and operational advisory services.

This script functions as a foundational component within broader national and
regional digital agro-climate ecosystems, where reliability, repeatability, and
traceability of climate input data are essential.

Author
------
Jemal Seid Ahmed  
Alliance of Bioversity International & CIAT (CGIAR)  
Email: jemal.ahmed@cgiar.org

Date: 12 Jun 2025
Version: 1.5
"""

import logging
import os
import math
import cdsapi
import urllib3
import calendar
from calendar import month_abbr
import xarray as xr
import zipfile
import io
import pandas as pd
from pathlib import Path
import tempfile
import xarray as xr
from datetime import timedelta
from datetime import date
from datetime import datetime
import os
from dask.diagnostics import ProgressBar
import cdsapi
import netCDF4
import h5netcdf
import numpy as np

_cache_dir = Path(tempfile.gettempdir()) / "agwise-cache"
_cache_dir.mkdir(parents=True, exist_ok=True)
os.environ.setdefault("MPLCONFIGDIR", str(_cache_dir / "matplotlib"))
os.environ.setdefault("XDG_CACHE_HOME", str(_cache_dir))

import matplotlib.pyplot as plt
import cartopy.crs as ccrs
import cartopy.feature as cfeature
import requests
from tqdm import tqdm
#from AgWise_utils import *
import rioxarray as rioxr

# Suppress warnings
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
logging.getLogger("cdsapi").setLevel(logging.ERROR)


class AgWise_Download:
    def __init__(self):
        """Initialize the AgWise_Download class."""
        pass

    def ModelsName(
        self,
        centre={
            "ECMWF_51": "ecmwf",
            "UKMO_604": "ukmo",
            "UKMO_603": "ukmo",
            "METEOFRANCE_8": "meteo_france",
            "DWD_21": "dwd", # month of initialization available for forecast are Jan to Mar
            "DWD_22": "dwd", # month of initialization available for forecast are Apr to __ 
            "CMCC_35": "cmcc",
            "NCEP_2": "ncep",
            "JMA_3": "jma",
            "ECCC_4": "eccc",
            "ECCC_5": "eccc",
            "CFSV2_1": "cfsv2",
        },
        variables_1={
            "PRCP": "total_precipitation",
            "TEMP": "2m_temperature",
            "UGRD10": "10m_u_component_of_wind",
            "VGRD10": "10m_v_component_of_wind",
            "SST": "sea_surface_temperature",
            "SLP": "mean_sea_level_pressure",
            "SRAD": "surface_solar_radiation_downwards",
            "DLWR": "surface_thermal_radiation_downwards",
        },
        variables_2={
            "HUSS_1000": "specific_humidity",
            "HUSS_925": "specific_humidity",
            "HUSS_850": "specific_humidity",
            "UGRD_1000": "u_component_of_wind",
            "UGRD_925": "u_component_of_wind",
            "UGRD_850": "u_component_of_wind",
            "VGRD_1000": "v_component_of_wind",
            "VGRD_925": "v_component_of_wind",
            "VGRD_850": "v_component_of_wind",
        },
    ):
        """
        Generate a combined dictionary of model names and variables. 
        For more information on C3S, browse the `MetaData <https://confluence.ecmwf.int/display/CKB/Description+of+the+C3S+seasonal+multi-system>`_.
        For more information on NMME, browse the `MetaData <https://confluence.ecmwf.int/display/CKB/Description+of+the+C3S+seasonal+multi-system>`_.

        Parameters:
            centre (dict): Mapping of model identifiers to model names.
            variables_1 (dict): Mapping of variable short names to full names for category 1.
            variables_2 (dict): Mapping of variable short names to full names for category 2.

        Returns:
            dict: A combined dictionary with keys as model.variable combinations and values as tuples (model name, variable name).
        """
        combined_dict1 = {
            f"{c}.{v}": (centre[c], variables_1[v]) for c in centre for v in variables_1
        }
        combined_dict2 = {
            f"{c}.{v}": (centre[c], variables_2[v]) for c in centre for v in variables_2
        }
        combined_dict = {**combined_dict1, **combined_dict2}
        return combined_dict

    def AgroObsName(
        self,
        variables={
            "AGRO.PRCP": ("precipitation_flux", None),
            "AGRO.TMAX": ("2m_temperature", "24_hour_maximum"),
            "AGRO.TEMP": ("2m_temperature", "24_hour_mean"),
            "AGRO.TMIN": ("2m_temperature", "24_hour_minimum"),
            "AGRO.SRAD": ("solar_radiation_flux", None),
        },
    ):
        """
        Generate a dictionary for agro-meteorological observation variables.

        Parameters:
            variables (dict): Mapping of agro variable short names to full names.

        Returns:
            dict: A dictionary mapping agro variables to their corresponding full names.
        """
        return variables

    @staticmethod
    def _daily_increment_by_lead(ds, lead_dim="forecast_period"):
        """
        Convert ECMWF accumulated lead-time totals into daily increments.

        ECMWF accumulated fields such as total precipitation and surface solar
        radiation are running totals from forecast step zero. DSSAT needs the
        isolated 24-hour value for each lead step, so use:

            day_n = accumulated_step_n - accumulated_step_(n-24h)

        The first requested lead uses an explicit zero baseline.
        """
        if lead_dim not in ds.dims:
            raise ValueError(f"Cannot compute daily increments: missing dimension {lead_dim!r}.")
        if ds.sizes.get(lead_dim, 0) < 1:
            raise ValueError("Cannot compute daily increments from an empty lead-time dimension.")

        data_attrs = {name: ds[name].attrs.copy() for name in ds.data_vars}
        global_attrs = ds.attrs.copy()
        ds_sorted = ds.sortby(lead_dim)

        lead_values = ds_sorted[lead_dim]
        if np.issubdtype(lead_values.dtype, np.timedelta64):
            zero_lead = np.timedelta64(0, "ns")
        else:
            zero_lead = 0

        baseline = xr.zeros_like(ds_sorted.isel({lead_dim: [0]}))
        baseline = baseline.assign_coords({lead_dim: [zero_lead]})
        daily = xr.concat([baseline, ds_sorted], dim=lead_dim).diff(dim=lead_dim)
        daily = daily.assign_coords({lead_dim: lead_values})

        for name in daily.data_vars:
            if bool((daily[name] < 0).any()):
                min_value = float(daily[name].min(skipna=True))
                print(
                    f"Warning: negative daily increment detected for {name} "
                    f"(minimum {min_value}). Clipping to zero for DSSAT-ready daily totals."
                )
                daily[name] = daily[name].where(daily[name] >= 0, 0)

        daily.attrs.update(global_attrs)
        for name, attrs in data_attrs.items():
            if name in daily:
                daily[name].attrs.update(attrs)
        return daily

    @staticmethod
    def _cds_area(area):
        """Return CDS [N, W, S, E] area rounded outward to 0.01 degrees."""
        if area is None:
            return None
        if len(area) != 4:
            raise ValueError(f"CDS area must be [North, West, South, East], got: {area}")
        north, west, south, east = [float(x) for x in area]
        return [
            round(min(90.0, math.ceil(north * 100.0) / 100.0), 2),
            round(max(-180.0, math.floor(west * 100.0) / 100.0), 2),
            round(max(-90.0, math.floor(south * 100.0) / 100.0), 2),
            round(min(180.0, math.ceil(east * 100.0) / 100.0), 2),
        ]

    def AgWise_Download_AgroIndicators_daily(
        self,
        dir_to_save,
        variables,
        year_start,
        year_end,
        area,
        force_download=False,
    ):
        """
        Download daily agro-meteorological indicators for specified variables and years.
    
        Parameters:
            dir_to_save (str): Directory to save the downloaded files.
            variables (list): List of shorthand variables to download (e.g., ["AGRO.PRCP", "AGRO.TMAX"]).
            year_start (int): Start year for the data to download.
            year_end (int): End year for the data to download.
            area (list): Bounding box as [North, West, South, East] for clipping.
            force_download (bool): If True, forces download even if file exists.
        """
        dir_to_save = Path(dir_to_save)
        os.makedirs(dir_to_save, exist_ok=True)
        days = [f"{day:02}" for day in range(1, 32)]
        months = [f"{month:02}" for month in range(1, 13)]
        version = "1_1"
    
        # Updated variable mapping with statistic
        variable_mapping = {
            "AGRO.PRCP": ("precipitation_flux", None, "Precipitation_Flux"),
            "AGRO.TMAX": ("2m_temperature", "24_hour_maximum", "Temperature_Air_2m_Max_24h"),
            "AGRO.TEMP": ("2m_temperature", "24_hour_mean", "Temperature_Air_2m_Mean_24h"),
            "AGRO.TMIN": ("2m_temperature", "24_hour_minimum", "Temperature_Air_2m_Min_24h"),
            "AGRO.SRAD": ("solar_radiation_flux", None, "Solar_Radiation_Flux"),
        }
    
        for var in variables:
            if var not in variable_mapping:
                print(f"Unknown variable: {var}. Skipping.")
                continue
                
    
            cds_variable, statistic, nc_var = variable_mapping[var]
            var_short = var.split(".")[1]
            output_path = dir_to_save / f"Daily_{var.split('.')[1]}_{year_start}_{year_end}.nc"
    
            if not force_download and os.path.exists(output_path):
                print(f"{output_path} already exists. Skipping download.") 
        
            else:
                combined_datasets = []
                for year in range(year_start, year_end + 1):
                    zip_file_path = dir_to_save / f"Daily_{var.split('.')[1]}_{year}.zip"
                
                    dataset = "sis-agrometeorological-indicators"
                    request = {
                        "variable": cds_variable,
                        "year": str(year),
                        "month": months,
                        "day": days,
                        "version": version,
                        #'grid': [0.1, 0.1],
                        "area": self._cds_area(area),
                    }
    
                    # Include the statistic parameter if specified
                    if statistic:
                        request["statistic"] = [statistic]
    
                    try:
                        client = cdsapi.Client()
                        print(f"Downloading {cds_variable} ({statistic}) data for {year}...")
                        client.retrieve(dataset, request).download(str(zip_file_path))
                        print(f"Downloaded: {zip_file_path}")
                    except Exception as e:
                        print(f"Failed to download {cds_variable} ({statistic}) data for {year}: {e}")
                        continue
    
                    # Extract NetCDF files from the ZIP archive
                    with zipfile.ZipFile(zip_file_path, 'r') as zip_ref:
                        for netcdf_file_name in zip_ref.namelist():
                            with zip_ref.open(netcdf_file_name) as file:
                                ds = xr.open_dataset(io.BytesIO(file.read()))
                                combined_datasets.append(ds)
    
                    os.remove(zip_file_path)
                    print(f"Deleted ZIP file: {zip_file_path}")
    
                # Concatenate all daily datasets into a single file
                if combined_datasets:
                    combined_ds = xr.concat(combined_datasets, dim="time")
                    combined_ds = combined_ds.rename_vars({nc_var: var.split('.')[1]})
                    # Convert temperature data from Kelvin to Celsius if needed
                    if var in ["AGRO.TMIN", "AGRO.TEMP", "AGRO.TMAX"]:
                        combined_ds = combined_ds - 273.15  # Convert from Kelvin to Celsius

                    # Convert solarradiation data from  m-2 day-1 to MJ m−2 day−1 if needed
                    if var in ["AGRO.SRAD"]:
                        combined_ds = combined_ds / 1000000  # Convert from J m-2 day-1 to MJ m−2 day−1
    
                    # Rename dimensions and save to NetCDF
                    #combined_ds = combined_ds.rename({"lon": "X", "lat": "Y", "time": "T"})
                    combined_ds = combined_ds.isel(lat=slice(None, None, -1))
                    combined_ds.to_netcdf(output_path)
                    print(f"File downloaded and combined dataset for {var} is saved to {output_path}")

    def AgWise_Download_Models_Daily(
        self,
        dir_to_save,
        center_variable,         # e.g. ["ECMWF_51.PRCP", "UKMO_603.TEMP", ...]
        month_of_initialization, # int: e.g. 2 for February
        day_of_initialization,   # int: e.g. 1 for the 1st day
        leadtime_hour,           # list of strings: e.g. ["24","48",..., "5160"]
        year_start_hindcast,
        year_end_hindcast,
        area,
        year_forecast=None,
        ensemble_mean=None,
        force_download=False,
    ):
        """
        Download daily/sub-daily seasonal forecast model data (original)
        using 'seasonal-original-single-levels' from the CDS.
    
        Parameters:
            dir_to_save (str or Path): Directory to save the downloaded files.
            center_variable (list): Each element e.g. "ECMWF_51.PRCP"
                - left side of '.' is model (ECMWF_51),
                - right side is variable short code (PRCP).
            month_of_initialization (int): Initialization month (1-12).
            day_of_initialization (int): Initialization day (1-31).
            leadtime_hour (list of str): e.g. ["24", "48", ..., "5160"].
            year_start_hindcast (int): Start year for hindcast data.
            year_end_hindcast (int): End year for hindcast data.
            area (list): Bounding box as [North, West, South, East].
            year_forecast (int, optional): If provided, downloads that single
                forecast year. Otherwise downloads hindcast for the specified range.
            ensemble_mean (str, optional): e.g. "mean", "median", or None.
            force_download (bool): Force download if True, even if file exists.
        """
    
        # 1. Determine whether we are downloading hindcast or forecast.
        if year_forecast is None:
            # Hindcast range
            years = [str(y) for y in range(year_start_hindcast, year_end_hindcast + 1)]
            file_prefix = "hindcast"
        else:
            # Single forecast year
            years = [str(year_forecast)]
            file_prefix = "forecast"
    
        # 2. Build standard dictionaries for center/system/variables
        centre = {
            "ECMWF_51": "ecmwf",
            "UKMO_604": "ukmo", # month of initialization available for forecast are Apr to __
            "UKMO_603": "ukmo", # month of initialization available for forecast are Jan to Mar
            "METEOFRANCE_8": "meteo_france",
            "DWD_21": "dwd",
            "DWD_22": "dwd",
            "CMCC_35": "cmcc",
            "NCEP_2": "ncep",
            "JMA_3": "jma",
            "ECCC_4": "eccc",
            "ECCC_5": "eccc",
        }
    
        system = {
            "ECMWF_51": "51",
            "UKMO_604": "604",
            "UKMO_603": "603",
            "METEOFRANCE_8": "8",
            "DWD_21": "21",
            "DWD_22": "22",
            "CMCC_35": "35",
            "NCEP_2": "2",
            "JMA_3": "3",
            "ECCC_4": "4",
            "ECCC_5": "5",
        }
    
        variables_1 = {
            "PRCP":  ["total_precipitation", "tp"],
            "TEMP":  ["2m_temperature", "t2m"],
            "TMAX":  ["maximum_2m_temperature_in_the_last_24_hours", "mx2t24"],
            "TMIN":  ["minimum_2m_temperature_in_the_last_24_hours", "mn2t24"],
            "UGRD10":["10m_u_component_of_wind", "u10"],
            "VGRD10":["10m_v_component_of_wind", "v10"],
            "SST":   ["sea_surface_temperature", "sst"],
            "SLP":   ["mean_sea_level_pressure", "msl"],
            "SRAD":  ["surface_solar_radiation_downwards", "ssrd"],
            "DLWR":  ["surface_thermal_radiation_downwards", "strd"],
        }
        variables_2 = {
            "HUSS_1000": "specific_humidity",
            "HUSS_925":  "specific_humidity",
            "HUSS_850":  "specific_humidity",
            "UGRD_1000": "u_component_of_wind",
            "UGRD_925":  "u_component_of_wind",
            "UGRD_850":  "u_component_of_wind",
            "VGRD_1000": "v_component_of_wind",
            "VGRD_925":  "v_component_of_wind",
            "VGRD_850":  "v_component_of_wind",
        }

        ### Particularity for day of initialization NCEP and JMA
        init_day_dict_jma = {
            "01":"16", "02":"10", "03":"12", "04":"11", "05":"16", "06":"15",
            "07":"15", "08":"14", "09":"13", "10":"13", "11":"12", "12":"12"
        }

        init_day_dict_ncep = {
            "01":"01", "02":"05", "03":"02", "04":"01", "05":"01", "06":"05",
            "07":"05", "08":"04", "09":"03", "10":"03", "11":"02", "12":"02"
        }
        
    
        # 3. Ensure the output directory exists
        dir_to_save = Path(dir_to_save)
        dir_to_save.mkdir(parents=True, exist_ok=True)
        store_file_path = {}
        # 4. Loop over each center-variable combination
        for cv in center_variable:
            # Example: "ECMWF_51.PRCP"
            c = cv.split(".")[0]  # e.g. "ECMWF_51"
            v = cv.split(".")[1]  # e.g. "PRCP"
    
            # Map to the Copernicus naming
            cent = centre[c]
            syst = system[c]
            if v in variables_1:
                var_cds = variables_1[v][0]
                nc_var = variables_1[v][1]
            elif v in variables_2:
                var_cds = variables_2[v]
            else:
                print(f"Unknown variable code: {v}, skipping.")
                continue
    
            # Build a single output path
            abb_mont_ini = month_abbr[int(month_of_initialization)]
            
            # E.g. "hindcast_ecmwf51_PRCP_Feb01_1981-2016_24-5160.nc"
            years_str = f"{years[0]}_{years[-1]}" if len(years) > 1 else years[0]
            lead_str  = f"{leadtime_hour[0]}-{leadtime_hour[-1]}" if len(leadtime_hour) > 1 else leadtime_hour[0]
    
            output_file = (
                dir_to_save /
                f"{file_prefix}_{cent}{syst}_{v}_{abb_mont_ini}{day_of_initialization}_{years_str}_{lead_str}.nc"
            )
    
            if not force_download and output_file.exists():
                print(f"{output_file} already exists. Skipping download.")
                store_file_path[f"{cent}{syst}"] = output_file
                continue

            if cent == "jma" and year_forecast is None:
                day_of_initialization = init_day_dict_jma[month_of_initialization]
            if cent == "ncep" and year_forecast is None:
                day_of_initialization = init_day_dict_ncep[month_of_initialization]
                    
            # 5. Prepare the request for 'seasonal-original-single-levels'
            dataset = "seasonal-original-single-levels"
            request = {
                "originating_centre": cent,
                "system": syst,
                "variable": [var_cds],
                "year": years,  # list of strings
                "month": [f"{int(month_of_initialization):02}"],
                "day":   [f"{int(day_of_initialization):02}"],
                "leadtime_hour": leadtime_hour,  # e.g. ["24","48",..., "5160"]
                "data_format": "netcdf",
                #'grid': [0.1, 0.1],
                "area": self._cds_area(area),   # e.g. [90, -180, -90, 180]
            }
    
            # Temporary file to download
            temp_file = dir_to_save / f"temp_{cent}{syst}_{v}.nc"
    
            # 6. Download from CDS
            client = cdsapi.Client()
            try:
                print(f"Requesting data from '{dataset}' for {cv}...")
                client.retrieve(dataset, request).download(str(temp_file))
                print(f"Downloaded: {temp_file}")
            except Exception as e:
                print(f"Failed to download data for {cv}: {e}")
                continue
    
            # 7. Post-process with xarray
            try:
                ##########################################################
                # Take in account level pressure for some variables in this part
                ##########################################################
                 
                ds = xr.open_dataset(temp_file)
                if v in ["PRCP", "SRAD", "DLWR"]:
                    ds = self._daily_increment_by_lead(ds)
                time = (ds['forecast_reference_time'] + ds['forecast_period']).data
                ds = ds.assign_coords(time=(('forecast_reference_time', 'forecast_period'), time))
                ds = ds.stack(time=('forecast_reference_time', 'forecast_period'))
                ds = ds.drop_vars(['forecast_reference_time', 'forecast_period'])
                ds = ds.rename({"valid_time":"time"})
                ds = ds.rename_vars({nc_var: v})
    
                # If there's an ensemble dimension, apply ensemble mean/median if requested
                if ensemble_mean in ["mean", "median"] and "number" in ds.dims:
                    ds = getattr(ds, ensemble_mean)(dim="number")
    
                # For example, flip latitude if needed
                if "latitude" in ds.coords:
                    ds = ds.isel(latitude=slice(None, None, -1))

                if v in ["TMIN","TEMP","TMAX","SST"]:
                    ds = ds - 273.15
                if v == "PRCP":
                    ds = ds * 1000  # Convert from m/day to mm/day.
                if v in ["SRAD", "DLWR"]:
                    ds = ds / 1000000  # Convert from J m-2 day-1 to MJ m-2 day-1.

                # Finally, rename the coords to X, Y, T to match my style
                if "longitude" in ds.coords:
                    ds = ds.rename({"longitude": "lon"})
                if "latitude" in ds.coords:
                    ds = ds.rename({"latitude": "lat"})
                #if "time" in ds.coords:
                #    ds = ds.rename({"time": "T"})
    
                # 8. Save the processed data
                ds.to_netcdf(output_file)
                ds.close()
                print(f"Saved processed data to: {output_file}")
                store_file_path[f"{cent}{syst}"] = output_file
        
            except Exception as e:
                print(f"Error reading or processing {temp_file}: {e}")
    
            finally:
                # Remove the temporary file
                if temp_file.exists():
                    os.remove(temp_file)
                    print(f"Deleted temp file: {temp_file}")
        return store_file_path
        

    # -------------------------------------------------------------------------
    # Helper for Reanalysis cross-year post-processing (optional)
    # -------------------------------------------------------------------------
    def _postprocess_reanalysis(self, ds, var_name):
        """
        Drop extra coords, rename dims, flip lat, etc.
        Adjust as needed for your MERRA2 or ERA5 quirks.
        """
        # Drop some known extraneous coords
        drop_list = []
        for extra in ["number", "expver", "pressure_level"]:
            if extra in ds.coords or extra in ds.variables:
                drop_list.append(extra)

        ds = ds.drop_vars(drop_list, errors="ignore").squeeze()

        # Flip latitude if it exists
        if "latitude" in ds.coords:
            ds = ds.isel(latitude=slice(None, None, -1))
            # rename directly to X, Y
            #ds = ds.rename({"latitude": "Y", "longitude": "X"})

        # If "valid_time" is present, rename it to "time"
        if "valid_time" in ds.coords:
            ds = ds.assign_coords(valid_time=pd.to_datetime(ds.valid_time.values))
            ds = ds.rename({"valid_time": "time"})

        return ds


    def _aggregate_crossyear(self, ds, season_months, var_name):
        """s
        Group ds by a custom 'season_year' coordinate so that all months
        in 'season_months' belong to one group that may cross Dec→Jan.
    
        Parameters:
            ds (xarray.Dataset or DataArray): The data to aggregate (daily, monthly, etc.).
            season_months (list[int]): e.g. [11,12,1] for NDJ.
            var_name (str): e.g. "AGRO.PRCP", "TEMP", "TMIN", etc. 
                           Used to decide 'mean' vs 'sum'.
    
        Returns:
            ds_out (xarray.Dataset or DataArray): Aggregated by season, 
                          dimension renamed from 'season_year' to 'time'.
        """

        if "time" not in ds.coords:
            raise ValueError("Dataset must have a 'time' dimension for aggregation.")
    
        pivot = season_months[0]
    
        # 1) Tag each time with the "season_year"
        # If month >= pivot => same year's label, else => year - 1
        season_year = ds["time"].dt.year.where(ds["time"].dt.month >= pivot,
                                               ds["time"].dt.year - 1)
    
        ds = ds.assign_coords(season_year=season_year)
        
        # 2) Keep only the months we actually want
        ds = ds.where(ds["time"].dt.month.isin(season_months), drop=True)
    
        # 3) Decide mean or sum based on var_name 

        if any(x in var_name for x in ["TEMP","TMIN","TMAX","SST","SLP"]):
            ds_out = ds.groupby("season_year").mean("time")
        elif any(x in var_name for x in ["PRCP","SRAD","DLWR"]):
            ds_out = ds.groupby("season_year").sum("time")
        else:
            ds_out = ds.groupby("season_year").mean("time")
    
        # 4) Rename "season_year" to "time", 
        #    so we end up with a time dimension (representing each seasonal year).
        ds_out = ds_out.rename({"season_year": "time"})
    
        return ds_out

####

def plot_map(extent, title="Map"): # [west, east, south, north]
    """
    Plots a map with specified geographic extent.

    Parameters:
    - extent: list of float, specifying [west, east, south, north]
    - title: str, title of the map
    """
    # Create figure and axis for the map
    fig, ax = plt.subplots(subplot_kw={"projection": ccrs.PlateCarree()}, figsize=(3, 2))

    # Set the geographic extent
    ax.set_extent(extent) 
    
    # Add map features
    ax.coastlines()
    ax.add_feature(cfeature.BORDERS, linestyle=":")
    ax.add_feature(cfeature.LAND, edgecolor="black")
    ax.add_feature(cfeature.OCEAN, facecolor="lightblue")
    
    # Set title
    ax.set_title(title)
    
    # Show plot
    plt.tight_layout()
    plt.show()
