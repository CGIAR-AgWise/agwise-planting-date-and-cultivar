#!/usr/bin/env python3
"""Build and print an advisory from a DSSAT summary and IWMI context."""

import argparse
import csv
import json
from datetime import date, datetime
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


def first_value(row, names):
    for name in names:
        if name in row and row[name] not in ("", None):
            return row[name]
    raise ValueError(f"DSSAT summary is missing one of: {', '.join(names)}")


def parse_date(value):
    value = value.strip()
    for pattern in ("%Y-%m-%d", "%d/%m/%Y", "%m/%d/%Y"):
        try:
            return date.fromisoformat(value) if pattern == "%Y-%m-%d" else datetime.strptime(value, pattern).date()
        except ValueError:
            continue
    if value.isdigit() and len(value) == 7:
        return date(int(value[:4]), 1, 1).replace(day=1)
    raise ValueError(f"Unsupported DSSAT planting date: {value}")


def load_recommendations(path, limit):
    with open(path, newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        raise ValueError(f"DSSAT summary contains no rows: {path}")

    parsed = []
    for row in rows:
        planting_date = parse_date(first_value(row, ("PDAT", "planting_date", "Planting_Date")))
        cultivar = first_value(row, ("Cultivar", "CULTIVAR", "INGENO", "cultivar_id"))
        yield_value = float(first_value(row, ("HWAH", "yield_kg_ha", "Yield")))
        parsed.append((yield_value, planting_date, cultivar))
    parsed.sort(key=lambda item: item[0], reverse=True)
    return [
        {
            "rank": rank,
            "planting_date": planting_date.isoformat(),
            "cultivar_id": str(cultivar),
            "yield_kg_ha": yield_value,
        }
        for rank, (yield_value, planting_date, cultivar) in enumerate(parsed[:limit], 1)
    ]


def resolve_location(name, country_code, latitude, longitude, locations_path):
    if latitude is not None and longitude is not None:
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
    recommendations = load_recommendations(args.dssat_summary, args.top)
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
            "generated_at": None,
            "iwmi_sources": [],
            "limitations": [
                "DSSAT results are interpreted from the supplied summary CSV",
                "IWMI context is contextual and does not re-rank DSSAT options",
            ],
        },
    }

    try:
        payload["iwmi"] = {"status": "available"}
        for name, collection in COLLECTIONS.items():
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
        payload["provenance"]["iwmi_sources"] = [
            f"{args.stac_catalog.rstrip('/')}/collections/{collection}"
            for collection in COLLECTIONS.values()
        ]
    except Exception as error:
        if not args.allow_missing:
            raise
        payload["iwmi"] = {"status": "unavailable", "errors": [str(error)]}
        payload["provenance"]["limitations"].append(
            "IWMI context could not be retrieved for this run"
        )
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
