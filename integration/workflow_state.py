#!/usr/bin/env python3
"""Manage safe, content-keyed checkpoints for the integrated workflow."""

import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def digest_inputs(inputs):
    digest = hashlib.sha256()
    for value in inputs:
        path = Path(value)
        digest.update(str(value).encode("utf-8"))
        digest.update(b"\0")
        if path.is_file():
            digest.update(path.read_bytes())
        else:
            digest.update(b"<value>")
        digest.update(b"\0")
    return digest.hexdigest()


def output_is_ready(value):
    path = Path(value)
    if path.is_file():
        return path.stat().st_size > 0
    if path.is_dir():
        return any(child.is_file() for child in path.rglob("*"))
    return False


def read_state(path):
    try:
        with path.open(encoding="utf-8") as handle:
            state = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return None
    return state if isinstance(state, dict) else None


def check(args):
    state_path = Path(args.state)
    state = read_state(state_path)
    expected_key = digest_inputs(args.inputs)
    valid = (
        state is not None
        and state.get("key") == expected_key
        and all(output_is_ready(output) for output in args.outputs)
    )
    if valid:
        print(f"Checkpoint valid: {state_path}")
        return 0
    print(f"Checkpoint missing or stale: {state_path}")
    return 1


def write(args):
    state_path = Path(args.state)
    state_path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "key": digest_inputs(args.inputs),
        "inputs": args.inputs,
        "outputs": args.outputs,
        "written_at": datetime.now(timezone.utc).isoformat(),
    }
    temporary_path = state_path.with_suffix(state_path.suffix + ".tmp")
    with temporary_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")
    temporary_path.replace(state_path)
    print(f"Checkpoint written: {state_path}")
    return 0


def status(args):
    state = read_state(Path(args.state))
    if state is None:
        print(f"No checkpoint: {args.state}")
        return 0
    print(json.dumps(state, indent=2))
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    for name in ("check", "write"):
        subparser = subparsers.add_parser(name)
        subparser.add_argument("--state", required=True)
        subparser.add_argument("--inputs", nargs="+", required=True)
        subparser.add_argument("--outputs", nargs="+", required=True)
        subparser.set_defaults(handler=check if name == "check" else write)

    status_parser = subparsers.add_parser("status")
    status_parser.add_argument("--state", required=True)
    status_parser.set_defaults(handler=status)

    args = parser.parse_args()
    try:
        return args.handler(args)
    except OSError as error:
        print(f"Workflow checkpoint error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
