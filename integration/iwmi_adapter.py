#!/usr/bin/env python3
"""Fetch and normalize IWMI context for the AgWise advisory contract."""

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from urllib.parse import urlencode
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


CONTEXT_NAMES = ("rainfall", "et_fraction", "irrigation", "water_stress")
VALUE_KEYS = (
    "value",
    "values",
    "data",
    "result",
    "results",
    "items",
)
UNITS = {
    "rainfall": "percent anomaly",
    "et_fraction": "fraction",
    "irrigation": "product-specific class or probability",
    "water_stress": "index",
}


def parse_endpoint(value):
    name, separator, url = value.partition("=")
    if not separator or name not in CONTEXT_NAMES or not url:
        raise ValueError(
            "Endpoint must use NAME=URL where NAME is one of: "
            + ", ".join(CONTEXT_NAMES)
        )
    return name, url


def fetch_json(url, timeout):
    headers = {"Accept": "application/json"}
    bearer_token = os.getenv("IWMI_BEARER_TOKEN")
    if bearer_token:
        headers["Authorization"] = f"Bearer {bearer_token}"
    headers["User-Agent"] = "AgWise-IWMI-adapter/1.0"
    request = Request(url, headers=headers)
    try:
        with urlopen(request, timeout=timeout) as response:
            body = response.read().decode("utf-8")
            return json.loads(body)
    except HTTPError as error:
        raise RuntimeError(f"IWMI request failed with HTTP {error.code}: {url}") from error
    except URLError as error:
        raise RuntimeError(f"IWMI request failed: {url}: {error.reason}") from error
    except json.JSONDecodeError as error:
        raise RuntimeError(f"IWMI response was not valid JSON: {url}") from error


def fetch_stac_item(catalog, collection, latitude, longitude, timeout):
    query = urlencode(
        {
            "collections": collection,
            "bbox": f"{longitude - 0.01},{latitude - 0.01},{longitude + 0.01},{latitude + 0.01}",
            "limit": 1,
        }
    )
    url = f"{catalog.rstrip('/')}/search?{query}"
    payload = fetch_json(url, timeout)
    features = payload.get("features", [])
    if not features:
        raise RuntimeError(f"IWMI STAC collection returned no item: {collection}")
    item = features[0]
    assets = item.get("assets", {})
    data_asset = next(
        (asset for asset in assets.values() if "data" in asset.get("roles", [])),
        next(iter(assets.values()), {}),
    )
    return {
        "status": "available",
        "value": None,
        "collection": collection,
        "item_id": item.get("id"),
        "asset_url": data_asset.get("href"),
        "period": {
            "start": item.get("properties", {}).get("start_datetime"),
            "end": item.get("properties", {}).get("end_datetime"),
        },
        "source": url,
    }


def raster_url(asset_url):
    if asset_url.startswith("/vsicurl/"):
        return asset_url[len("/vsicurl/") :]
    if asset_url.startswith("s3://"):
        bucket, _, key = asset_url[5:].partition("/")
        return f"https://{bucket}.s3.af-south-1.amazonaws.com/{key}"
    return asset_url


def sample_raster(asset_url, latitude, longitude):
    try:
        import rasterio
    except ImportError as error:
        raise RuntimeError(
            "Raster sampling requires rasterio. Install it with: python -m pip install rasterio"
        ) from error

    url = raster_url(asset_url)
    try:
        with rasterio.open(url) as dataset:
            sample = next(dataset.sample([(longitude, latitude)]))
            value = float(sample[0])
            nodata = dataset.nodata
            if value != value or (nodata is not None and value == nodata):
                raise RuntimeError("sampled raster cell contains no data")
            return value, dataset.crs.to_string() if dataset.crs else None
    except Exception as error:
        if isinstance(error, RuntimeError):
            raise
        raise RuntimeError(f"Could not sample IWMI raster asset: {url}: {error}") from error


def add_raster_value(measure, name, latitude, longitude):
    value, crs = sample_raster(measure["asset_url"], latitude, longitude)
    measure["value"] = value
    measure["unit"] = UNITS.get(name, "product-specific")
    measure["sample"] = {
        "latitude": latitude,
        "longitude": longitude,
        "crs": crs,
        "method": "nearest raster cell",
    }
    return measure


def extract_value(payload):
    if not isinstance(payload, dict):
        return payload
    for key in VALUE_KEYS:
        if key in payload:
            return payload[key]
    return payload


def normalize_measure(name, url, payload):
    return {
        "status": "available",
        "value": extract_value(payload),
        "source": url,
    }


def build_context(endpoints, timeout, allow_missing):
    context = {"status": "available"}
    failures = []
    for name, url in endpoints.items():
        try:
            context[name] = normalize_measure(name, url, fetch_json(url, timeout))
        except RuntimeError as error:
            if not allow_missing:
                raise
            failures.append(str(error))
            context[name] = {"status": "unavailable", "source": url}

    if failures:
        context["status"] = "unavailable"
        context["errors"] = failures
    return context


def main():
    parser = argparse.ArgumentParser(
        description="Fetch IWMI endpoints into the AgWise-IWMI advisory payload."
    )
    parser.add_argument(
        "--endpoint",
        action="append",
        default=[],
        metavar="NAME=URL",
        help="IWMI endpoint; repeat for rainfall, et_fraction, irrigation, or water_stress.",
    )
    parser.add_argument(
        "--stac-collection",
        action="append",
        default=[],
        metavar="NAME=COLLECTION",
        help="Live IWMI STAC collection name, using the default public catalog.",
    )
    parser.add_argument(
        "--stac-catalog",
        default="https://odc-explorer.iwmi.org/stac",
        help="IWMI STAC catalog URL.",
    )
    parser.add_argument("--input", required=True, help="AgWise advisory JSON payload.")
    parser.add_argument("--output", required=True, help="Output normalized advisory JSON.")
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--latitude", type=float)
    parser.add_argument("--longitude", type=float)
    parser.add_argument(
        "--sample-raster",
        action="store_true",
        help="Sample the matching IWMI raster at the supplied coordinates.",
    )
    parser.add_argument(
        "--allow-missing",
        action="store_true",
        help="Write unavailable context instead of stopping on an endpoint failure.",
    )
    args = parser.parse_args()

    endpoints = dict(parse_endpoint(item) for item in args.endpoint)
    stac_collections = dict(parse_endpoint(item) for item in args.stac_collection)
    if not endpoints and not stac_collections:
        parser.error("provide at least one --endpoint or --stac-collection")
    with open(args.input, encoding="utf-8") as handle:
        payload = json.load(handle)

    payload["iwmi"] = build_context(endpoints, args.timeout, args.allow_missing)
    if stac_collections:
        if args.latitude is None or args.longitude is None:
            parser.error("--latitude and --longitude are required with --stac-collection")
        for name, collection in stac_collections.items():
            try:
                payload["iwmi"][name] = fetch_stac_item(
                    args.stac_catalog, collection, args.latitude, args.longitude, args.timeout
                )
                if args.sample_raster:
                    payload["iwmi"][name] = add_raster_value(
                        payload["iwmi"][name], name, args.latitude, args.longitude
                    )
            except RuntimeError as error:
                if not args.allow_missing:
                    raise
                payload["iwmi"][name] = {"status": "unavailable", "source": collection}
                payload["iwmi"].setdefault("errors", []).append(str(error))
        payload["iwmi"]["status"] = (
            "available"
            if all(payload["iwmi"][name]["status"] == "available" for name in stac_collections)
            else "unavailable"
        )
    payload.setdefault("provenance", {}).setdefault("iwmi_sources", [])
    payload["provenance"]["iwmi_sources"] = list(endpoints.values()) + [
        f"{args.stac_catalog.rstrip('/')}/collections/{collection}"
        for collection in stac_collections.values()
    ]
    payload["provenance"]["generated_at"] = datetime.now(timezone.utc).isoformat()
    if args.sample_raster:
        payload["provenance"]["limitations"] = [
            limitation
            for limitation in payload.get("provenance", {}).get("limitations", [])
            if limitation != "IWMI context not yet requested"
        ]
        payload["provenance"]["limitations"].append(
            "IWMI values are sampled from product rasters and are not yet used to re-rank DSSAT options"
        )

    with open(args.output, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")

    if payload["iwmi"]["status"] != "available":
        print("IWMI context completed with unavailable sources.", file=sys.stderr)


if __name__ == "__main__":
    main()
