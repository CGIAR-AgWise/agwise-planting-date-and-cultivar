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


def format_measure(name, measure):
    labels = {
        "rainfall": "Rainfall anomaly",
        "et_fraction": "ET fraction",
        "irrigation": "Irrigation context",
        "water_stress": "Water-stress index",
    }
    if measure.get("status") != "available" or measure.get("value") is None:
        return f"- {labels[name]}: unavailable"
    unit = measure.get("unit", "value")
    role = measure.get("temporal_role")
    period = measure.get("period", {})
    period_text = ""
    if period.get("start") and period.get("end"):
        period_text = f", period {period['start'][:10]} to {period['end'][:10]}"
    role_text = f", {role.replace('_', ' ')}" if role else ""
    return f"- {labels[name]}: {measure['value']} ({unit}{period_text}{role_text})"


def interpret_water_context(iwmi):
    statements = []
    rainfall = iwmi.get("rainfall", {})
    if rainfall.get("status") == "available" and isinstance(
        rainfall.get("value"), (int, float)
    ):
        value = rainfall["value"]
        if value < 0:
            statements.append(
                f"The rainfall product indicates a below-average anomaly ({value:.1f}%)."
            )
        elif value > 0:
            statements.append(
                f"The rainfall product indicates an above-average anomaly (+{value:.1f}%)."
            )
        else:
            statements.append("The rainfall product is close to its reference average.")

    if iwmi.get("et_fraction", {}).get("status") == "available":
        statements.append(
            "The ET fraction is reported, but its product-specific scale must be "
            "confirmed before calling it low or high."
        )
    if iwmi.get("irrigation", {}).get("status") == "available":
        statements.append(
            "The irrigation layer reports a mapped product value; it should not "
            "be treated as a probability without the IWMI product legend."
        )
    if iwmi.get("water_stress", {}).get("status") == "available":
        statements.append(
            "The water-stress value is shown for context, but no threshold is "
            "applied to change the DSSAT ranking."
        )
    return statements


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
            ]
        )
        for name in ("rainfall", "et_fraction", "irrigation", "water_stress"):
            if name in iwmi:
                lines.append(format_measure(name, iwmi[name]))
        lines.extend(["", "Interpretation", "--------------"])
        lines.extend(f"- {statement}" for statement in interpret_water_context(iwmi))
        lines.append("")
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
    roles = {
        measure.get("temporal_role")
        for measure in iwmi.values()
        if isinstance(measure, dict) and measure.get("temporal_role")
    }
    if "historical_reference" in roles or "static_spatial_context" in roles:
        lines.append(
            "- Some IWMI layers are historical references or static spatial context, "
            "not direct observations for this season."
        )
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
