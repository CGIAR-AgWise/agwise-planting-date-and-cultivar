#!/usr/bin/env python3
"""Fetch and normalize IWMI context for the AgWise advisory contract."""

import argparse
import json
import os
import sys
from datetime import datetime, timezone
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
    parser.add_argument(
        "--allow-missing",
        action="store_true",
        help="Write unavailable context instead of stopping on an endpoint failure.",
    )
    args = parser.parse_args()

    endpoints = dict(parse_endpoint(item) for item in args.endpoint)
    for item in args.stac_collection:
        name, collection = parse_endpoint(item)
        endpoints[name] = f"{args.stac_catalog.rstrip('/')}/collections/{collection}"
    if not endpoints:
        parser.error("provide at least one --endpoint or --stac-collection")
    with open(args.input, encoding="utf-8") as handle:
        payload = json.load(handle)

    payload["iwmi"] = build_context(endpoints, args.timeout, args.allow_missing)
    payload.setdefault("provenance", {}).setdefault("iwmi_sources", [])
    payload["provenance"]["iwmi_sources"] = list(endpoints.values())
    payload["provenance"]["generated_at"] = datetime.now(timezone.utc).isoformat()

    with open(args.output, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")

    if payload["iwmi"]["status"] != "available":
        print("IWMI context completed with unavailable sources.", file=sys.stderr)


if __name__ == "__main__":
    main()
