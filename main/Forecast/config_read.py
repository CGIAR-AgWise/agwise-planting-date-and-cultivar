"""
Script: config_read.py
Purpose: Discover and load AgWISE country JSON configuration files.

Author: Jemal S. Ahmed
Email: jemal.ahmed@cgiar.org
Institution: Alliance of Bioversity International and CIAT (CGIAR)
Date: 2026-05-29
"""

import json
from pathlib import Path
from typing import Dict, Any, Optional, List


def get_country_configs(data_dir: str,
    countries: Optional[List[str]] = None,
    season: Optional[str] = None,
    pick: str = "latest",
) -> Dict[str, Dict[str, Any]]:
    """
    Auto-discover and load AgWISE country configuration JSON files.

    Parameters
    ----------
    data_dir : str
        Base AgWISE data directory (contains country subfolders).
    countries : list[str], optional
        ISO3 country codes to load (e.g. ["ETH","GHA"]). If None, load all found.
    season : str, optional
        Season filter based on filename (e.g. "DJFM", "JJAS").
    pick : {"latest","all"}
        If multiple configs exist per country:
          - "latest": use most recently modified file (default)
          - "all": last one wins (not usually recommended)

    Returns
    -------
    COUNTRY_CONFIGS : dict
        Dictionary identical in structure to the old hard-coded COUNTRY_CONFIGS.
    """

    data_dir = Path(data_dir)
    if not data_dir.exists():
        raise FileNotFoundError(f"Data directory not found: {data_dir}")

    suffix = "_config_agwise.json"
    files = [p for p in data_dir.rglob(f"*{suffix}") if not p.name.startswith("._")]
    if not files:
        raise RuntimeError(f"No config files found under {data_dir}")

    # Normalize country filter
    if countries:
        countries = {c.upper() for c in countries}

    candidates = {}

    for p in files:
        # Optional season filter (from filename)
        if season:
            name = p.name.replace(suffix, "")
            parts = name.split("_")
            if len(parts) < 2 or parts[1] != season:
                continue

        with p.open("r", encoding="utf-8") as f:
            obj = json.load(f)

        for cc, cfg in obj.items():
            cc = cc.upper()
            if countries and cc not in countries:
                continue

            cfg["_config_path"] = str(p)  # provenance, harmless
            candidates.setdefault(cc, []).append((p, cfg))

    if not candidates:
        raise RuntimeError("No matching country configs found.")

    COUNTRY_CONFIGS = {}

    for cc, items in candidates.items():
        if pick == "all":
            for _, cfg in items:
                COUNTRY_CONFIGS[cc] = cfg
        else:  # latest
            latest_p, latest_cfg = max(items, key=lambda t: t[0].stat().st_mtime)
            COUNTRY_CONFIGS[cc] = latest_cfg

    return COUNTRY_CONFIGS
