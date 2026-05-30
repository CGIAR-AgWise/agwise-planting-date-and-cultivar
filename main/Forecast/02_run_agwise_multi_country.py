#!/usr/bin/env python3
"""
AgWise Multi-Country daily S2S Seasonal forecast ensemble Data Preparation
==========================================================================

This script orchestrates downloading and preparing observation + model data
(hindcast + forecast) across multiple countries.

Key improvement:
- COUNTRY_CONFIGS is no longer hard-coded in Python.
- Configs are auto-discovered from R-generated JSON files:
    <data_dir>/**/**_config_agwise.json

CLI:
  python 02_run_agwise_multi_country.py --data-dir /path/to/data
  python 02_run_agwise_multi_country.py --data-dir /path/to/data --countries ETH GHA
  python 02_run_agwise_multi_country.py --data-dir /path/to/data --season DJFM

Author: Jemal S. Ahmed
Email: jemal.ahmed@cgiar.org
Institution: Alliance of Bioversity International and CIAT (CGIAR)
Date: 2026-05-29
"""

from __future__ import annotations

# from dask.distributed import LocalCluster, Client, as_completed  # not used

from AgWise_download import *   # provides AgWise_Download, plot_map, etc.
import datetime
from pathlib import Path
import warnings
import gc
import argparse
import os
import json
from typing import Dict, Any, Optional, List, Tuple

warnings.filterwarnings("ignore")

CONFIG_SUFFIX = "_config_agwise.json"

# Global config container used by run_country_pipeline (populated in main)
COUNTRY_CONFIGS: Dict[str, Dict[str, Any]] = {}


# ---------------------------------------------------------------------
# 0. Auto-discover + load country configs from JSON
# ---------------------------------------------------------------------
def _season_from_filename(p: Path) -> Optional[str]:
    """
    Heuristic: ETH_DJFM_config_agwise.json -> DJFM
    Returns None if not matchable.
    """
    name = p.name
    if not name.endswith(CONFIG_SUFFIX):
        return None
    core = name[: -len(CONFIG_SUFFIX)]  # e.g. ETH_DJFM
    parts = core.split("_")
    if len(parts) >= 2:
        return parts[1]
    return None


def get_country_configs(data_dir: str, countries: Optional[List[str]] = None, season: Optional[str] = None,pick: str = "latest",) -> Dict[str, Dict[str, Any]]:
    """
    Auto-discover and load AgWISE country configuration JSON files.

    Parameters
    ----------
    data_dir : str
        Base AgWISE data directory containing country folders.
    countries : list[str], optional
        ISO3 codes to load (e.g. ["ETH","GHA"]). If None, load all discovered.
    season : str, optional
        Season filter based on filename (e.g. "DJFM", "JJAS").
    pick : {"latest","all"}
        If multiple configs exist per country:
          - "latest": choose most recently modified config file (default)
          - "all": last one wins (not recommended unless you know why)

    Returns
    -------
    dict: { "ETH": { ... }, "GHA": { ... }, ... }
    Same structure as your old hard-coded COUNTRY_CONFIGS.
    """
    base = Path(data_dir)
    if not base.exists():
        raise FileNotFoundError(f"Data directory not found: {base}")

    files = [p for p in base.rglob(f"*{CONFIG_SUFFIX}") if not p.name.startswith("._")]
    if not files:
        raise RuntimeError(f"No config files found under: {base} (pattern *{CONFIG_SUFFIX})")

    countries_set = None
    if countries:
        countries_set = {c.strip().upper() for c in countries if c.strip()}

    # Collect candidate configs per country
    candidates: Dict[str, List[Tuple[Path, Dict[str, Any]]]] = {}

    for p in files:
        if season:
            s = _season_from_filename(p)
            if s != season:
                continue

        try:
            with p.open("r", encoding="utf-8") as f:
                obj = json.load(f)
        except Exception as e:
            print(f"[WARN] Skipping unreadable JSON: {p} ({e})")
            continue

        if not isinstance(obj, dict) or len(obj) == 0:
            print(f"[WARN] Skipping invalid JSON structure (expected dict): {p}")
            continue

        for cc, cfg in obj.items():
            ccU = str(cc).upper()

            if countries_set and ccU not in countries_set:
                continue

            if not isinstance(cfg, dict):
                print(f"[WARN] Skipping {p}: config for {ccU} is not a dict")
                continue

            # provenance for debugging (harmless to pipeline)
            cfg.setdefault("_config_path", str(p))

            candidates.setdefault(ccU, []).append((p, cfg))

    if not candidates:
        raise RuntimeError(
            "No matching configs found after applying filters. "
            f"(countries={countries}, season={season})"
        )

    # Resolve duplicates per country
    out: Dict[str, Dict[str, Any]] = {}
    for cc, items in candidates.items():
        if pick == "all":
            # last one wins in iteration order (not recommended)
            for _, cfg in items:
                out[cc] = cfg
        else:
            # latest by mtime
            latest_p, latest_cfg = max(items, key=lambda t: t[0].stat().st_mtime)
            out[cc] = latest_cfg

    # If user requested specific countries, verify all found
    if countries_set:
        missing = countries_set - set(out.keys())
        if missing:
            raise KeyError(f"Requested countries not found in discovered configs: {sorted(missing)}")

    return out


def _validate_cfg(cc: str, cfg: Dict[str, Any]) -> None:
    """Minimal schema checks so the pipeline fails fast with a clear message."""
    required = [
        "dir_s2s",
        "extent_obs",
        "extent_model",
        "year_start_obs",
        "year_end_obs",
        "forecast_year",
        "init_month",
        "init_day",
        "center_variable",
    ]
    for k in required:
        if k not in cfg:
            raise KeyError(f"[{cc}] Missing required key '{k}' in config file: {cfg.get('_config_path','?')}")

    ext = cfg["extent_obs"]
    if not (isinstance(ext, list) and len(ext) == 4):
        raise ValueError(f"[{cc}] extent_obs must be a list of 4 numbers [N,W,S,E], got: {ext}")
    N, W, S, E = ext
    if not (N > S and E > W):
        raise ValueError(f"[{cc}] extent_obs invalid (need N>S and E>W), got: {ext}")


# ---------------------------------------------------------------------
# 1. CLI
# ---------------------------------------------------------------------
def parse_args():
    parser = argparse.ArgumentParser(
        description="Run AgWISE pipeline using auto-discovered country configs"
    )

    parser.add_argument(
        "--data-dir",
        required=True,
        help="Base AgWISE data directory (contains country folders)"
    )

    parser.add_argument(
        "--countries",
        nargs="*",
        default=None,
        help="Optional ISO3 country codes (e.g. ETH GHA). Default: all discovered"
    )

    parser.add_argument(
        "--season",
        default=None,
        help="Optional season filter based on filename (e.g. DJFM, JJAS)"
    )

    parser.add_argument(
        "--pick",
        choices=["latest", "all"],
        default="latest",
        help="If multiple configs per country, pick latest (default) or all"
    )

    parser.add_argument(
        "--nb-cores",
        type=int,
        default=10,
        help="Number of cores (passed to pipeline steps that accept it). Default=10"
    )

    parser.add_argument(
        "--force-download",
        action="store_true",
        help="Re-download/reprocess observation and model files even if outputs already exist"
    )

    return parser.parse_args()


# ---------------------------------------------------------------------
# 2. Helper: run pipeline for a single country (your logic kept)
# ---------------------------------------------------------------------
def run_country_pipeline(country_code: str, nb_cores: int = 10, force_download: bool = False):
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

    hdcst_consolidated = {}
    fcst_consolidated = {}
    scores_consolidated = {}

    dir_save_score = Path(cfg["dir_save_score"]) #dir_s2s / "scores"
    dir_save_score.mkdir(parents=True, exist_ok=True)

    dir_to_downloads = Path(cfg.get("dir_downloads", dir_s2s / "forecast" / "downloads"))
    dir_to_downloads.mkdir(parents=True, exist_ok=True)

    # -----------------------------------------------------------------
    # 2.2 Initialize downloader
    # -----------------------------------------------------------------
    downloader = AgWise_Download()

    variables_obs = [key for key in downloader.AgroObsName().keys()]

    year_start_obs = cfg["year_start_obs"]
    year_end_obs = cfg["year_end_obs"]
    extent_obs = cfg["extent_obs"]  # [N, W, S, E] for CDS

    dir_to_save_obs = Path(cfg["dir_to_save_obs"]) #dir_s2s / "Observation"
    dir_to_save_obs.mkdir(parents=True, exist_ok=True)

    # -----------------------------------------------------------------
    # 2.3 Download Observations (historical + current year)
    # -----------------------------------------------------------------
    print(f"\n=== [{country_code}] Downloading Observation Data ===")
    #plot_map(
    #    [extent_obs[1], extent_obs[3], extent_obs[2], extent_obs[0]],
    #    title=f"{country_code} Observation Area"
    #)

    downloader.AgWise_Download_AgroIndicators_daily(
        dir_to_save=dir_to_save_obs,
        variables=variables_obs,
        year_start=year_start_obs,
        year_end=year_end_obs,
        area=extent_obs,
        force_download=force_download,
    )

    season_year = int(cfg.get("forecast_year", datetime.datetime.now().year))
    target_obs_year = max(season_year, int(cfg.get("forecast_init_year", season_year)))
    downloader.AgWise_Download_AgroIndicators_daily(
        dir_to_save=dir_to_save_obs,
        variables=variables_obs,
        year_start=target_obs_year,
        year_end=target_obs_year,
        area=extent_obs,
        force_download=force_download,
    )

    # -----------------------------------------------------------------
    # 2.4 Download Model Data (hindcast + forecast)
    # -----------------------------------------------------------------
    print(f"\n=== [{country_code}] Downloading Model Data ===")

    center_variable = cfg["center_variable"]
    dir_to_save_model = Path(cfg["dir_to_save_model"]) # dir_s2s / "forecast" / "raw"
    dir_to_save_model.mkdir(parents=True, exist_ok=True)

    season_year = int(cfg["forecast_year"])
    forecast_init_year = int(cfg.get("forecast_init_year", season_year))
    month_of_initialization = int(cfg.get("forecast_init_month", cfg["init_month"]))
    day_of_initialization = int(cfg.get("forecast_init_day", cfg["init_day"]))

    leadtime_hour = [str(i) for i in range(24, 5161, 24)]  # 24h to 5160h

    year_start_model = int(cfg.get("year_hndS", 1994))
    year_end_model = int(cfg.get("year_hndE", 2016))

    extent_model = cfg["extent_model"]  # [N, W, S, E] for CDS

    ensemble_mean = "mean"

    print(
        f"\n--- [{country_code}] Hindcast Download "
        f"(init {month_of_initialization:02d}/{day_of_initialization:02d}, "
        f"lead={cfg.get('forecast_lead_months', 0)} month(s)) ---"
    )
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

    print(
        f"\n--- [{country_code}] Forecast Download "
        f"(season year {season_year}, init year {forecast_init_year}) ---"
    )
    file_path_fcst = downloader.AgWise_Download_Models_Daily(
        dir_to_save=dir_to_save_model,
        center_variable=center_variable,
        month_of_initialization=month_of_initialization,
        day_of_initialization=day_of_initialization,
        leadtime_hour=leadtime_hour,
        year_start_hindcast=None,
        year_end_hindcast=None,
        area=extent_model,
        year_forecast=forecast_init_year,
        ensemble_mean=ensemble_mean,
        force_download=force_download,
    )

    # Try to keep memory stable for multi-country runs
    gc.collect()

    return {
        "hindcast_files": file_path_hdcst,
        "forecast_files": file_path_fcst,
        "scores": scores_consolidated,
    }


# ---------------------------------------------------------------------
# 3. Main
# ---------------------------------------------------------------------
def main():
    global COUNTRY_CONFIGS

    args = parse_args()

    COUNTRY_CONFIGS = get_country_configs(
        data_dir=args.data_dir,
        countries=args.countries,
        season=args.season,
        pick=args.pick,
    )

    # Validate early
    for cc, cfg in COUNTRY_CONFIGS.items():
        _validate_cfg(cc, cfg)

    print("\nDiscovered configs:")
    for cc, cfg in COUNTRY_CONFIGS.items():
        print(f" - {cc}: {cfg.get('_config_path','?')}")

    results = {}

    for country in COUNTRY_CONFIGS.keys():
        print(f"\n############################")
        print(f"# Running pipeline for {country}")
        print(f"############################")
        results[country] = run_country_pipeline(
            country_code=country,
            nb_cores=args.nb_cores,
            force_download=args.force_download,
        )

    print("\nAll requested countries processed.")
    for c, r in results.items():
        print(
            f"- {c}: hindcast={bool(r.get('hindcast_files'))}, "
            f"forecast={bool(r.get('forecast_files'))}"
        )


if __name__ == "__main__":
    main()
