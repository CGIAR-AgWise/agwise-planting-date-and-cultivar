#!/usr/bin/env python3
"""List the items each IWMI collection offers at the Chokwe point."""

from urllib.parse import urlencode

from iwmi_adapter import fetch_json
from run_advisory import COLLECTIONS

LAT, LON = -24.500676, 33.001806
CATALOG = "https://odc-explorer.iwmi.org/stac"

for name, collection in COLLECTIONS.items():
    query = urlencode(
        {
            "collections": collection,
            "bbox": f"{LON - 0.01},{LAT - 0.01},{LON + 0.01},{LAT + 0.01}",
            "limit": 100,
        }
    )
    payload = fetch_json(f"{CATALOG}/search?{query}", 30)
    items = payload.get("features", [])
    has_next = any(link.get("rel") == "next" for link in payload.get("links", []))
    print(f"\n{name} ({collection}): {len(items)} items, more pages: {has_next}")
    spans = sorted(
        (
            item.get("properties", {}).get("start_datetime") or "",
            item.get("properties", {}).get("end_datetime") or "",
        )
        for item in items
    )
    for start, end in spans[:2] + spans[-3:]:
        print(f"  {start[:10]} to {end[:10]}")