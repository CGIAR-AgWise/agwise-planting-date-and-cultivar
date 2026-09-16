#!/usr/bin/env python3
"""Render a normalized AgWise-IWMI payload as a plain-language advisory."""

import argparse
import json
from datetime import date


def format_date(value):
    if not value:
        return "an unspecified date"
    parsed = date.fromisoformat(value)
    return f"{parsed.day} {parsed.strftime('%B')} {parsed.year}"


def build_advisory(payload):
    request = payload["request"]
    location = request["location"]["name"]
    crop = request["crop"].lower()
    recommendation = payload.get("recommendations", [])
    if not recommendation:
        raise ValueError("The payload contains no recommendations.")

    best = min(recommendation, key=lambda item: item["rank"])
    iwmi = payload.get("iwmi", {})
    iwmi_status = iwmi.get("status", "not_requested")

    lines = [
        "",
        "AGWISE + IWMI TECHNICAL ADVISORY",
        "================================",
        f"Location: {location}, {request['country_code']}",
        f"Crop: {crop}",
        f"Season: {request['season']['year']}",
        "",
        "Recommendation",
        "--------------",
        (
            f"Based on the current AgWise forecast and DSSAT simulation, "
            f"plant {crop} around {format_date(best['planting_date'])} "
            f"using cultivar {best['cultivar_id']}."
        ),
        f"Highest simulated yield: {best['yield_kg_ha']:,.0f} kg/ha.",
        "",
    ]

    if iwmi_status == "available":
        lines.extend(
            [
                "Water context",
                "-------------",
                (
                    "IWMI water-context data were retrieved for this location. "
                    "Use them to distinguish how the result may apply to "
                    "rainfed and irrigated fields."
                ),
                "",
            ]
        )
    elif iwmi_status == "unavailable":
        lines.extend(
            [
                "Water context",
                "-------------",
                (
                    "IWMI data were requested, but one or more water-context "
                    "sources were unavailable. The recommendation is based "
                    "on AgWise and DSSAT only."
                ),
                "",
            ]
        )
    else:
        lines.extend(
            [
                "Water context",
                "-------------",
                (
                    "IWMI water-context data have not yet been sampled. "
                    "This recommendation is based on AgWise and DSSAT only."
                ),
                "",
            ]
        )

    lines.extend(
        [
            "Important limitations",
            "---------------------",
            "This is a technical demonstration, not a validated farm instruction.",
        ]
    )
    for limitation in payload.get("provenance", {}).get("limitations", []):
        lines.append(f"- {limitation}")
    lines.extend(
        [
            "",
            "The recommendation should be reviewed with local agronomic "
            "knowledge before operational use.",
            "",
        ]
    )
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Print a normalized advisory payload in plain language."
    )
    parser.add_argument("payload", help="Path to a normalized advisory JSON file.")
    args = parser.parse_args()
    with open(args.payload, encoding="utf-8") as handle:
        payload = json.load(handle)
    print(build_advisory(payload))


if __name__ == "__main__":
    main()
