#!/usr/bin/env python3
"""Compare DSSAT-only and IWMI-adjusted advisory recommendations."""

import argparse
import json
from pathlib import Path


def load_payload(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def treatment_key(item):
    return (item["planting_date"], item["cultivar_id"])


def compare_payloads(baseline, experimental):
    baseline_items = {
        treatment_key(item): item for item in baseline.get("recommendations", [])
    }
    experimental_items = {
        treatment_key(item): item
        for item in experimental.get("recommendations", [])
    }
    treatments = []
    for key in sorted(set(baseline_items) | set(experimental_items)):
        before = baseline_items.get(key, {})
        after = experimental_items.get(key, {})
        treatments.append(
            {
                "planting_date": key[0],
                "cultivar_id": key[1],
                "baseline_rank": before.get("rank"),
                "experimental_rank": after.get("rank"),
                "rank_change": (
                    before.get("rank") - after.get("rank")
                    if before.get("rank") is not None
                    and after.get("rank") is not None
                    else None
                ),
                "dssat_yield_kg_ha": after.get(
                    "dssat_yield_kg_ha", before.get("yield_kg_ha")
                ),
                "experimental_score_kg_ha": after.get("yield_kg_ha"),
                "adjustment_fraction": after.get("iwmi_ranking_effect", {}).get(
                    "adjustment_fraction"
                ),
            }
        )

    baseline_best = baseline.get("recommendations", [{}])[0]
    experimental_best = experimental.get("recommendations", [{}])[0]
    best_changed = treatment_key(baseline_best) != treatment_key(experimental_best)
    return {
        "location": baseline["request"]["location"]["name"],
        "crop": baseline["request"]["crop"],
        "season": baseline["request"]["season"],
        "baseline": {
            "mode": "dssat",
            "best": {
                "planting_date": baseline_best.get("planting_date"),
                "cultivar_id": baseline_best.get("cultivar_id"),
                "score_kg_ha": baseline_best.get("yield_kg_ha"),
            },
        },
        "experimental": {
            "mode": experimental.get("provenance", {})
            .get("iwmi_ranking", {})
            .get("mode", "unknown"),
            "policy_id": experimental.get("provenance", {})
            .get("iwmi_ranking", {})
            .get("policy_id"),
            "best": {
                "planting_date": experimental_best.get("planting_date"),
                "cultivar_id": experimental_best.get("cultivar_id"),
                "score_kg_ha": experimental_best.get("yield_kg_ha"),
            },
        },
        "best_recommendation_changed": best_changed,
        "treatments": treatments,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", required=True)
    parser.add_argument("--experimental", required=True)
    parser.add_argument("--output")
    args = parser.parse_args()

    comparison = compare_payloads(
        load_payload(args.baseline), load_payload(args.experimental)
    )
    rendered = json.dumps(comparison, indent=2) + "\n"
    if args.output:
        Path(args.output).write_text(rendered, encoding="utf-8")
    print(rendered, end="")


if __name__ == "__main__":
    main()
