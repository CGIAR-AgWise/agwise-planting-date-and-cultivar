#!/usr/bin/env python3
"""Build and print an advisory from a DSSAT summary and IWMI context."""

import argparse
import csv
import json
from datetime import date, datetime, timezone
from pathlib import Path

from advisory import build_advisory
from iwmi_adapter import add_raster_value, fetch_stac_item


COLLECTIONS = {
    "rainfall": "limpopo_jfm_rainfall",
    "et_fraction": "et_fraction_africa",
    "irrigation": "irrigated_areas_limpopo",
    "water_stress": "evaporative_stress_index_africa",
}
DEFAULT_LOCATIONS = Path(__file__).with_name("locations.json")

RANK_COLUMNS = {"median": "HWAH_median", "mean": "HWAH_mean", "p10": "HWAH_p10"}
EXTRA_FIELDS = {
    "yield_p10_kg_ha": "HWAH_p10",
    "yield_p90_kg_ha": "HWAH_p90",
    "yield_cv_pct": "HWAH_cv_pct",
    "n_simulations": "n_simulations",
    "maturity_failure_rate_pct": "maturity_failure_rate_pct",
}


def first_value(row, names):
    for name in names:
        if name in row and row[name] not in ("", None):
            return row[name]
    raise ValueError(f"DSSAT summary is missing one of: {', '.join(names)}")


def parse_date(value):
    value = str(value).strip()
    # ISO 8601, with or without time and trailing Z, e.g. 2025-11-09T00:00:00Z
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).date()
    except ValueError:
        pass
    if value.isdigit() and len(value) == 7:  # YYYYDDD, e.g. 2025313
        return datetime.strptime(value, "%Y%j").date()
    if value.isdigit() and len(value) == 5:  # YYDDD, e.g. 25313
        return datetime.strptime(value, "%y%j").date()
    for pattern in ("%d/%m/%Y", "%m/%d/%Y"):
        try:
            return datetime.strptime(value, pattern).date()
        except ValueError:
            continue
    raise ValueError(f"Unsupported DSSAT planting date: {value}")


def optional_float(row, column):
    value = row.get(column)
    return float(value) if value not in ("", None) else None


def load_recommendations(path, limit, rank_by="median"):
    with open(path, newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        raise ValueError(f"DSSAT summary contains no rows: {path}")

    parsed = []
    for row in rows:
        entry = {
            "planting_date": parse_date(
                first_value(row, ("PDAT", "planting_date", "Planting_Date"))
            ).isoformat(),
            "cultivar_id": str(
                first_value(row, ("Cultivar", "CULTIVAR", "INGENO", "cultivar_id"))
            ),
            "yield_kg_ha": float(
                first_value(row, (RANK_COLUMNS[rank_by], "HWAH", "yield_kg_ha", "Yield"))
            ),
            "yield_metric": rank_by,
        }
        for field, column in EXTRA_FIELDS.items():
            value = optional_float(row, column)
            if value is not None:
                entry[field] = int(value) if field == "n_simulations" else value
        parsed.append(entry)

    parsed.sort(key=lambda item: item["yield_kg_ha"], reverse=True)
    return [{"rank": rank, **entry} for rank, entry in enumerate(parsed[:limit], 1)]


def resolve_location(name, country_code, latitude, longitude, locations_path):
    if latitude is not None and longitude is not None:
        if not country_code:
            raise ValueError(
                "--country-code is required when coordinates are given explicitly."
            )
        return {
            "name": name,
            "country_code": country_code,
            "latitude": latitude,
            "longitude": longitude,
        }
    if not locations_path.exists():
        raise ValueError(
            f"Location registry not found: {locations_path}. "
            "Provide --latitude and --longitude."
        )
    with open(locations_path, encoding="utf-8") as handle:
        locations = json.load(handle)
    record = locations.get(name.lower())
    if record is None:
        available = ", ".join(sorted(locations))
        raise ValueError(
            f"Location '{name}' is not registered. Available locations: {available}. "
            "Provide --latitude and --longitude for a new location."
        )
    if country_code and country_code != record["country_code"]:
        raise ValueError(
            f"Location '{name}' belongs to {record['country_code']}, "
            f"not {country_code}."
        )
    return record


def build_payload(args):
    season_start = date.fromisoformat(args.season_start)
    season_end = date.fromisoformat(args.season_end)
    recommendations = load_recommendations(args.dssat_summary, args.top, args.rank_by)
    location = resolve_location(
        args.location,
        args.country_code,
        args.latitude,
        args.longitude,
        Path(args.locations_file),
    )
    payload = {
        "contract_version": "1.0",
        "request": {
            "country_code": location["country_code"],
            "location": {
                "name": location["name"],
                "latitude": location["latitude"],
                "longitude": location["longitude"],
            },
            "crop": args.crop,
            "season": {
                "year": season_start.year,
                "start_date": season_start.isoformat(),
                "length_months": args.season_length_months,
            },
        },
        "agwise": {
            "status": "available",
            "forecast": {
                "variables": ["PRCP", "TMAX", "TMIN", "SRAD"],
                "lead_months": args.lead_months,
            },
            "dssat": {
                "status": "available",
                "metric": "HWAH",
                "recommendation_count": len(recommendations),
            },
        },
        "iwmi": {"status": "unavailable"},
        "recommendations": recommendations,
        "provenance": {
            "run_id": Path(args.dssat_summary).stem,
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "iwmi_sources": [],
            "limitations": [
                "DSSAT results are interpreted from the supplied summary CSV",
                "IWMI context is contextual and does not re-rank DSSAT options",
                f"Yields are the {args.rank_by} across the simulations for each planting date and cultivar",
            ],
        },
    }

    payload["iwmi"] = {"status": "available"}
    errors = []
    for name, collection in COLLECTIONS.items():
        try:
            measure = fetch_stac_item(
                args.stac_catalog,
                collection,
                location["latitude"],
                location["longitude"],
                args.timeout,
                season_start.isoformat(),
                season_end.isoformat(),
            )
            if args.sample_raster:
                measure = add_raster_value(
                    measure, name, location["latitude"], location["longitude"]
                )
            payload["iwmi"][name] = measure
        except RuntimeError as error:
            if not args.allow_missing:
                raise
            errors.append(f"{name}: {error}")
            payload["iwmi"][name] = {"status": "unavailable", "source": collection}

    if errors:
        payload["iwmi"]["errors"] = errors
        payload["provenance"]["limitations"].append(
            "One or more IWMI layers could not be retrieved for this run"
        )
        if all(
            payload["iwmi"][name]["status"] == "unavailable" for name in COLLECTIONS
        ):
            payload["iwmi"]["status"] = "unavailable"

    payload["provenance"]["iwmi_sources"] = [
        f"{args.stac_catalog.rstrip('/')}/collections/{collection}"
        for collection in COLLECTIONS.values()
    ]
    return payload


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dssat-summary", required=True)
    parser.add_argument("--country-code")
    parser.add_argument("--location", required=True)
    parser.add_argument("--crop", required=True)
    parser.add_argument("--latitude", type=float)
    parser.add_argument("--longitude", type=float)
    parser.add_argument(
        "--locations-file",
        default=str(DEFAULT_LOCATIONS),
        help="Location registry JSON used when coordinates are omitted.",
    )
    parser.add_argument("--season-start", required=True)
    parser.add_argument("--season-end", required=True)
    parser.add_argument("--season-length-months", type=int, default=4)
    parser.add_argument("--lead-months", type=int, default=1)
    parser.add_argument("--top", type=int, default=5)
    parser.add_argument("--rank-by", choices=sorted(RANK_COLUMNS), default="median")
    parser.add_argument("--stac-catalog", default="https://odc-explorer.iwmi.org/stac")
    parser.add_argument("--timeout", type=float, default=30)
    parser.add_argument("--sample-raster", action="store_true")
    parser.add_argument("--allow-missing", action="store_true")
    parser.add_argument("--output")
    args = parser.parse_args()

    payload = build_payload(args)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2)
            handle.write("\n")
    print(build_advisory(payload))


if __name__ == "__main__":
    main()