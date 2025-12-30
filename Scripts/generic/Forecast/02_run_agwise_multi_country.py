"""
AgWise Multi-Country daill S2S Seasonal forecast ensemble Data Preparation
==========================================================================

This script provides a unified orchestration layer for downloading and preparing
seasonal forecasts and agro-meteorological indicators across multiple countries.
It wraps the core AgWise_Download module with a higher-level workflow that allows
countries to be selected dynamically, ensures consistent preprocessing across
domains, and supports scalable execution through Dask parallelism.

Concept
-------
The purpose of this wrapper is to operationalize a repeatable, transparent,
and country-agnostic data acquisition pipeline for the AgWise / AgWISE_Forecast
system. It abstracts operational complexity by:

- Managing country-specific configuration (spatial extent, initialization month,
  climatological years, variables, forecast horizons, etc.).
- Executing harmonized workflows for observation downloads and seasonal model
  retrievals (hindcast + forecast).
- Ensuring consistent directory structure, naming conventions, and data hygiene
  across all countries.
- Enabling scalable multi-country processing using Dask, supporting both
  research-grade and operational environments.

This script functions as the operational bridge between the AgWise data
generation engine and downstream national advisory systems, making it easier to
run large-scale, multi-country agro-climate workflows in a controlled and
reproducible manner.

Usage
-----
 python run_agwise_multi_country.py --countries GHA ETH
 

Author
------
Jemal Seid Ahmed, Wuletaw Abera  
Alliance of Bioversity International & CIAT (CGIAR)  
Email: jemal.ahmed@cgiar.org

Date: 25 June 2025
Version: 1.5
"""



from dask.distributed import LocalCluster, Client
from AgWise_download.py import *
import datetime
from pathlib import Path
import warnings
import gc
import argparse
import os

warnings.filterwarnings("ignore")

# ---------------------------------------------------------------------
# 1. Country configuration
#    - Add/modify entries here for each country.
# ---------------------------------------------------------------------
COUNTRY_CONFIGS = {
    "GHA": {  # Ghana
        "dir_s2s": "/Users/jemal/AgWISE/S2S_forecast/GHA",
        # [North, West, South, East] for OBS (CDS area argument)
        "extent_obs": [11.5, -3.5, 4.5, 1.5],
        # [North, West, South, East] for MODELS (CDS area argument)
        # (example: adjust to your preferred Ghana or West Africa domain)
        "extent_model": [11.5, -3.5, 4.5, 1.5],
        "year_start_obs": 1985,
        "year_end_obs": 2024,
        # Hindcast period for models
        "year_start_model": 2014,
        "year_end_model": 2016,
        # Forecast target year
        "forecast_year": 2025,
        # Initialization month/day (as integers)
        "init_month": 9,    # September
        "init_day": 1,
        # Variables
        "center_variable": ['ECMWF_51.PRCP', 'ECMWF_51.TMAX', 'ECMWF_51.TMIN', 'ECMWF_51.SRAD'],
    },

    # Example template for another country:
    "ETH": {  # Ethiopia (placeholder, adjust values)
        "dir_s2s": "/Users/jemal/AgWISE/S2S_forecast/ETH",
        "extent_obs": [16, 34, 8, 40],       # [N, W, S, E] – example
        "extent_model": [16, 34, 8, 40],     # [N, W, S, E] – example
        "year_start_obs": 1985,
        "year_end_obs": 2024,
        "year_start_model": 1993,
        "year_end_model": 2016,
        "forecast_year": 2025,
        "init_month": 6,     # June example
        "init_day": 1,
        "center_variable": ['ECMWF_51.PRCP', 'ECMWF_51.TMAX', 'ECMWF_51.TMIN', 'ECMWF_51.SRAD'],
    },

    # Add more countries (KEN, ZMB, etc.) as needed
}


# ---------------------------------------------------------------------
# 2. Helper: run pipeline for a single country
# ---------------------------------------------------------------------
def run_country_pipeline(country_code: str, nb_cores: int = 10):
    """
    Run the AgWise download pipeline for a given country code
    (as defined in COUNTRY_CONFIGS).
    """
    if country_code not in COUNTRY_CONFIGS:
        raise ValueError(f"Country '{country_code}' not found in COUNTRY_CONFIGS")

    cfg = COUNTRY_CONFIGS[country_code]

    # -----------------------------------------------------------------
    # 2.1 Setup directory structure per country
    # -----------------------------------------------------------------
    dir_s2s = Path(cfg["dir_s2s"])
    os.makedirs(dir_s2s, exist_ok=True)

    # Consolidated containers (placeholder if you later store scores, etc.)
    hdcst_consolidated = {}
    fcst_consolidated = {}
    scores_consolidated = {}

    # Directories for scores and forecasts
    dir_save_score = dir_s2s / "scores"
    dir_save_score.mkdir(parents=True, exist_ok=True)

    dir_to_forecast = dir_s2s / "forecasts"
    dir_to_forecast.mkdir(parents=True, exist_ok=True)

    # -----------------------------------------------------------------
    # 2.2 Initialize downloader
    # -----------------------------------------------------------------
    downloader = AgWise_Download()

    # Observation variables
    variables_obs = [key for key in downloader.AgroObsName().keys()]

    # Observation settings
    year_start_obs = cfg["year_start_obs"]
    year_end_obs = cfg["year_end_obs"]
    extent_obs = cfg["extent_obs"]  # [N, W, S, E] for CDS

    # Directory to save observations
    dir_to_save_obs = dir_s2s / "Observation"
    dir_to_save_obs.mkdir(parents=True, exist_ok=True)

    # -----------------------------------------------------------------
    # 2.3 Download Observations (historical + current year)
    # -----------------------------------------------------------------
    print(f"\n=== [{country_code}] Downloading Observation Data ===")
    # Plot extent for sanity check
    plot_map(
        [extent_obs[1], extent_obs[3], extent_obs[2], extent_obs[0]],
        title=f"{country_code} Observation Area"
    )

    force_download = False

    # Historical
    downloader.AgWise_Download_AgroIndicators_daily(
        dir_to_save=dir_to_save_obs,
        variables=variables_obs,
        year_start=year_start_obs,
        year_end=year_end_obs,
        area=extent_obs,
        force_download=force_download,
    )

    # Current year (e.g. for near-real-time updates)
    current_year = datetime.datetime.now().year
    downloader.AgWise_Download_AgroIndicators_daily(
        dir_to_save=dir_to_save_obs,
        variables=variables_obs,
        year_start=current_year,
        year_end=current_year,
        area=extent_obs,
        force_download=force_download,
    )

    # -----------------------------------------------------------------
    # 2.4 Download Model Data (hindcast + forecast)
    # -----------------------------------------------------------------
    print(f"\n=== [{country_code}] Downloading Model Data ===")

    center_variable = cfg["center_variable"]
    dir_to_save_model = dir_s2s / "daily_model_data"
    dir_to_save_model.mkdir(parents=True, exist_ok=True)

    month_of_initialization = cfg["init_month"]      # int
    day_of_initialization = cfg["init_day"]          # int

    leadtime_hour = [str(i) for i in range(24, 5161, 24)]  # 24h to 5160h

    year_start_model = cfg["year_start_model"]
    year_end_model = cfg["year_end_model"]

    extent_model = cfg["extent_model"]  # [N, W, S, E] for CDS

    # Ensemble mean setting (fixed tuple bug: no trailing comma)
    ensemble_mean = "mean"

    # Hindcast
    print(f"\n--- [{country_code}] Hindcast Download ---")
    file_path_hdcst = downloader.AgWise_Download_Models_Daily(
        dir_to_save=dir_to_save_model,
        center_variable=center_variable,
        month_of_initialization=month_of_initialization,
        day_of_initialization=day_of_initialization,
        leadtime_hour=leadtime_hour,
        year_start_hindcast=year_start_model,
        year_end_hindcast=year_end_model,
        area=extent_model,
        year_forecast=None,
        ensemble_mean=ensemble_mean,
        force_download=force_download,
    )

    # Forecast (single year)
    print(f"\n--- [{country_code}] Forecast Download ({cfg['forecast_year']}) ---")
    forecast_year = cfg["forecast_year"]
    file_path_fcst = downloader.AgWise_Download_Models_Daily(
        dir_to_save=dir_to_save_model,
        center_variable=center_variable,
        month_of_initialization=month_of_initialization,
        day_of_initialization=day_of_initialization,
        leadtime_hour=leadtime_hour,
        year_start_hindcast=year_start_model,  # not used when year_forecast != None
        year_end_hindcast=year_end_model,
        area=extent_model,
        year_forecast=forecast_year,
        ensemble_mean=ensemble_mean,
        force_download=force_download,
    )

    # If you want, you can store paths into consolidated dicts here
    hdcst_consolidated[country_code] = file_path_hdcst
    fcst_consolidated[country_code] = file_path_fcst

    # Garbage collect (just to be safe in large runs)
    gc.collect()

    print(f"\n=== [{country_code}] Completed ===")
    return {
        "hindcast_files": file_path_hdcst,
        "forecast_files": file_path_fcst,
    }


# ---------------------------------------------------------------------
# 3. Main entry point with optional CLI arguments
# ---------------------------------------------------------------------
def parse_args():
    parser = argparse.ArgumentParser(
        description="Run AgWise multi-country seasonal data downloads."
    )
    parser.add_argument(
        "--countries",
        nargs="+",
        default=list(COUNTRY_CONFIGS.keys()),
        help=(
            "Country codes to run (space-separated). "
            "Default: all configured countries."
        ),
    )
    parser.add_argument(
        "--cores",
        type=int,
        default=10,
        help="Number of local cores (workers) for Dask LocalCluster.",
    )
    return parser.parse_args()


def main():
    args = parse_args()

    # -----------------------------------------------------------------
    # Dask cluster setup (shared across all countries)
    # -----------------------------------------------------------------
    print(f"Starting Dask LocalCluster with {args.cores} workers...")
    cluster = LocalCluster(n_workers=args.cores, threads_per_worker=1)
    client = cluster.get_client()
    print(client)

    # Run pipeline per country
    for country in args.countries:
        print(f"\n############################")
        print(f"# Running pipeline for {country}")
        print(f"############################")
        run_country_pipeline(country_code=country, nb_cores=args.cores)

    print("\nAll requested countries processed.")


if __name__ == "__main__":
    main()

