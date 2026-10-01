#!/usr/bin/env python3
"""Render a normalized AgWise-IWMI payload as a plain-language advisory."""

import argparse
import json
from datetime import date

LABELS = {
    "rainfall": "Historical JFM rainfall anomaly composite (Limpopo domain)",
    "et_fraction": "ET fraction",
    "irrigation": "Irrigation context",
    "water_stress": "Water-stress index",
}


def format_date(value):
    if not value:
        return "an unspecified date"
    parsed = date.fromisoformat(value)
    return f"{parsed.day} {parsed.strftime('%B')} {parsed.year}"


def has_value(measure):
    return (
        isinstance(measure, dict)
        and measure.get("status") == "available"
        and measure.get("value") is not None
    )


def format_measure(name, measure):
    label = LABELS[name]
    if measure.get("status") != "available":
        return f"- {label}: unavailable"

    role = measure.get("temporal_role")
    period = measure.get("period", {})
    period_text = ""
    if period.get("start") and period.get("end"):
        period_text = f"period {period['start'][:10]} to {period['end'][:10]}"
    role_text = role.replace("_", " ") if role else ""
    details = ", ".join(part for part in (period_text, role_text) if part)

    if measure.get("value") is None:
        found = measure.get("item_id") or measure.get("collection") or "product"
        suffix = f" ({details})" if details else ""
        return f"- {label}: product located ({found}){suffix}, value not sampled"

    value = measure["value"]
    value_text = f"{value:.2f}" if isinstance(value, float) else value
    unit = measure.get("unit", "value")
    inner = ", ".join(part for part in (unit, details) if part)
    raw = measure.get("raw_value")
    scale = measure.get("scale")
    encoding = (
        f"; raw raster value {raw:g}, scale {scale:g}"
        if raw is not None and scale is not None and scale != 1
        else ""
    )
    return f"- {label}: {value_text} ({inner}{encoding})"


def interpret_water_context(iwmi):
    statements = []
    rainfall = iwmi.get("rainfall", {})
    if has_value(rainfall) and isinstance(rainfall["value"], (int, float)):
        statements.append(
            f"The rainfall product is a January to March composite for 1950 to 2022 "
            f"({rainfall['value']:+.1f}%). Its metadata describes a single cell covering "
            "the whole Limpopo domain, so it is not a local measurement and not a "
            "forecast or observation for this season."
        )

    if has_value(iwmi.get("et_fraction", {})):
        statements.append(
            "The ET value is scale-decoded and reported as a percentage under the "
            "ODC product definition. The linked COG also contains Green ET "
            "metadata, so that catalogue conflict is retained as a provenance "
            "warning rather than given an agronomic interpretation."
        )
    if has_value(iwmi.get("irrigation", {})):
        statements.append(
            "The irrigation layer uses the probability asset where available. "
            "Its value remains a contextual probability, not a binary "
            "irrigated/not-irrigated classification."
        )
    if has_value(iwmi.get("water_stress", {})):
        statements.append(
            "The water-stress index is scale-decoded. The IWMI product metadata "
            "does not publish validated thresholds or a directional legend, so "
            "no stress category is assigned and the DSSAT ranking is unchanged."
        )
    return statements


def build_advisory(payload):
    request = payload["request"]
    location = request["location"]["name"]
    crop = request["crop"].lower()
    recommendation = payload.get("recommendations", [])
    if not recommendation:
        raise ValueError("The payload contains no recommendations.")

    ranked = sorted(recommendation, key=lambda item: item["rank"])
    best = ranked[0]
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
            f"using the {best['cultivar_id']} cultivar."
        ),
        f"Highest {best.get('yield_metric', 'simulated')} simulated yield: "
        f"{best['yield_kg_ha']:,.0f} kg/ha.",
    ]

    p10, p90 = best.get("yield_p10_kg_ha"), best.get("yield_p90_kg_ha")
    if p10 is not None and p90 is not None:
        n = best.get("n_simulations")
        basis = f" across {n} grid cells" if n else ""
        lines.append(
            f"Spatial range of simulated yield (10th to 90th percentile): "
            f"{p10:,.0f} to {p90:,.0f} kg/ha{basis}."
        )
    failure = best.get("maturity_failure_rate_pct")
    if failure:
        lines.append(
            f"Warning: the crop failed to reach maturity in {failure:.0f}% "
            f"of simulations."
        )

    if len(ranked) > 1:
        lines.extend(["", "Other simulated options", "-----------------------"])
        for item in ranked[1:5]:
            lines.append(
                f"- {format_date(item['planting_date'])}, {item['cultivar_id']}: "
                f"{item['yield_kg_ha']:,.0f} kg/ha"
            )
    lines.append("")

    if iwmi_status == "available":
        sampled = any(
            has_value(measure) for measure in iwmi.values() if isinstance(measure, dict)
        )
        lines.extend(["Water context", "-------------"])
        if sampled:
            lines.append(
                "IWMI water-context values were sampled for this location. "
                "Use them to distinguish how the result may apply to "
                "rainfed and irrigated fields."
            )
        else:
            lines.append(
                "IWMI products were located for this site, but their values were "
                "not sampled, so no water-context numbers are shown. Rerun with "
                "--sample-raster to add them."
            )
        for name in LABELS:
            if name in iwmi:
                lines.append(format_measure(name, iwmi[name]))
        statements = interpret_water_context(iwmi)
        if statements:
            lines.extend(["", "Interpretation", "--------------"])
            lines.extend(f"- {statement}" for statement in statements)
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