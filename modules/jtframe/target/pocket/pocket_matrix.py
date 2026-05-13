#!/usr/bin/env python3
"""Audit and operate the public Analogue Pocket core matrix.

The markdown matrix stays human-readable, but this tool makes it checkable:
it parses CORE_MATRIX.md, verifies coverage against cores/*, optionally scans
an SD card for bitstream hashes and ROM payloads, and can run export/build jobs
for an explicit core list.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[4]
POCKET_DIR = ROOT / "modules" / "jtframe" / "target" / "pocket"
DEFAULT_MATRIX = POCKET_DIR / "CORE_MATRIX.md"
DEFAULT_JSON = POCKET_DIR / "CORE_MATRIX.json"
DEFAULT_ASSET_ROOT = Path(os.environ.get(
    "POCKET_ASSET_ROOT",
    str(ROOT / "assets" / "pocket"),
))
DEFAULT_APFSIM = Path(os.environ.get(
    "APFSIM",
    shutil.which("apfsim") or "apfsim",
))

SECTION_KEYS = {
    "Working On Hardware": "hardware_ok",
    "Hardware Issues": "hardware_issues",
    "Build OK / Needs Hardware Test": "build_ok_needs_hw_test",
    "Blocked / Failed": "blocked_failed",
    "No RTL / Schematic Only": "no_rtl",
}

PAYLOAD_EXTS = {".rom", ".ngp", ".ngc"}
RUNTIME_COLLATERAL_NAMES = {
    "6801.uc",
    "collut.hex",
    "dsp16fw_lsb.hex",
    "dsp16fw_msb.hex",
    "exp2.hex",
    "fir20k.hex",
    "fir2_69.hex",
    "firjt49.hex",
    "font0.hex",
    "j68_dec.mem",
    "j68_dec_c.mem",
    "kabuki.hex",
    "log2.hex",
    "microrom.mem",
    "nanorom.mem",
    "tilebank.hex",
}
RUNTIME_COLLATERAL_SUFFIXES = {".uc"}
RUNTIME_COLLATERAL_SKIP = {
    "msg.bin",
    "msg.hex",
}


def split_row(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def strip_md(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == "`" and value[-1] == "`":
        return value[1:-1]
    return value


def sha1_file(path: Path) -> str:
    digest = hashlib.sha1()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_matrix(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    status: dict[str, dict[str, Any]] = {}
    coverage: dict[str, dict[str, Any]] = {}
    current_section: str | None = None
    in_coverage = False
    matrix_date = None

    for line in lines:
        if line.startswith("Last updated:"):
            matrix_date = line.split(":", 1)[1].strip()
            continue

        if line.startswith("## "):
            title = line[3:].strip()
            current_section = title if title in SECTION_KEYS else None
            in_coverage = title == "Coverage Summary"
            continue

        if in_coverage and line.startswith("| ") and not line.startswith("| ---"):
            cells = split_row(line)
            if len(cells) >= 3 and cells[0] != "Bucket":
                try:
                    count = int(cells[1])
                except ValueError:
                    continue
                coverage[cells[0]] = {"count": count, "notes": cells[2]}
            continue

        if current_section is None:
            continue
        if not line.startswith("| `"):
            continue

        cells = split_row(line)
        core = strip_md(cells[0])
        bucket = SECTION_KEYS[current_section]
        row: dict[str, Any] = {
            "core": core,
            "bucket": bucket,
            "section": current_section,
        }

        if bucket == "hardware_ok":
            row.update(
                {
                    "pocket_folder": strip_md(cells[1]),
                    "result": cells[2],
                    "artifact_hash": strip_md(cells[3]),
                    "notes": cells[4] if len(cells) > 4 else "",
                }
            )
        elif bucket == "hardware_issues":
            row.update(
                {
                    "pocket_folder": strip_md(cells[1]),
                    "result": cells[2],
                    "artifact_hash": strip_md(cells[3]),
                    "notes": cells[4] if len(cells) > 4 else "",
                    "next_action": cells[5] if len(cells) > 5 else "",
                }
            )
        elif bucket == "build_ok_needs_hw_test":
            row.update(
                {
                    "pocket_folder": strip_md(cells[1]),
                    "artifact_hash": strip_md(cells[2]),
                    "notes": cells[3] if len(cells) > 3 else "",
                }
            )
        else:
            row.update(
                {
                    "status": cells[1],
                    "failure": cells[2] if len(cells) > 2 else "",
                    "next_action": cells[3] if len(cells) > 3 else "",
                }
            )

        status[core] = row

    return {
        "matrix_path": str(path.relative_to(ROOT)),
        "matrix_last_updated": matrix_date,
        "coverage_summary": coverage,
        "cores": status,
    }


def repo_core_names() -> list[str]:
    return sorted(p.name for p in (ROOT / "cores").iterdir() if p.is_dir())


def section_counts(cores: dict[str, dict[str, Any]]) -> dict[str, int]:
    counts: dict[str, int] = {v: 0 for v in SECTION_KEYS.values()}
    for row in cores.values():
        counts[row["bucket"]] = counts.get(row["bucket"], 0) + 1
    return counts


def scan_sd(sd_root: Path, cores: dict[str, dict[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {
        "sd_root": str(sd_root),
        "available": sd_root.exists(),
        "cores": {},
    }
    if not sd_root.exists():
        return result

    for core, row in sorted(cores.items()):
        pocket_folder = row.get("pocket_folder")
        if not pocket_folder:
            continue
        asset_folder = pocket_folder.split(".")[-1]
        core_dir = sd_root / "Cores" / pocket_folder
        assets_dir = sd_root / "Assets" / asset_folder
        bitstream = core_dir / "bitstream.rbf_r"
        expected_hash = row.get("artifact_hash")
        actual_hash = sha1_file(bitstream) if bitstream.exists() else None

        json_count = 0
        payloads: list[str] = []
        if assets_dir.exists():
            for path in assets_dir.rglob("*"):
                if not path.is_file():
                    continue
                suffix = path.suffix.lower()
                if suffix == ".json":
                    json_count += 1
                elif suffix in PAYLOAD_EXTS:
                    payloads.append(str(path.relative_to(assets_dir)))

        result["cores"][core] = {
            "pocket_folder": pocket_folder,
            "core_dir_present": core_dir.exists(),
            "bitstream_present": bitstream.exists(),
            "bitstream_sha1": actual_hash,
            "expected_sha1": expected_hash,
            "hash_matches_matrix": bool(actual_hash and expected_hash and actual_hash == expected_hash),
            "assets_dir_present": assets_dir.exists(),
            "instance_json_count": json_count,
            "payload_count": len(payloads),
            "payloads": sorted(payloads),
        }
    return result


def scan_asset_root(asset_root: Path, cores: dict[str, dict[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {
        "asset_root": str(asset_root),
        "available": asset_root.exists(),
        "cores": {},
    }
    if not asset_root.exists():
        return result

    for core, row in sorted(cores.items()):
        pocket_folder = row.get("pocket_folder")
        if not pocket_folder:
            continue
        asset_folder = pocket_folder.split(".")[-1]
        assets_dir = asset_root / asset_folder
        json_count = 0
        payloads: list[str] = []
        if assets_dir.exists():
            for path in assets_dir.rglob("*"):
                if not path.is_file():
                    continue
                suffix = path.suffix.lower()
                if suffix == ".json":
                    json_count += 1
                elif suffix in PAYLOAD_EXTS:
                    payloads.append(str(path.relative_to(assets_dir)))
        result["cores"][core] = {
            "pocket_folder": pocket_folder,
            "asset_folder": asset_folder,
            "assets_dir_present": assets_dir.exists(),
            "instance_json_count": json_count,
            "payload_count": len(payloads),
            "payloads": sorted(payloads),
        }
    return result


def audit(matrix: Path, sd_root: Path | None = None, asset_root: Path | None = None) -> dict[str, Any]:
    data = parse_matrix(matrix)
    cores = data["cores"]
    repo_cores = repo_core_names()
    matrix_cores = sorted(cores)
    data["generated_at"] = _dt.datetime.now(_dt.timezone.utc).replace(microsecond=0).isoformat()
    data["repo_core_count"] = len(repo_cores)
    data["matrix_core_count"] = len(matrix_cores)
    data["section_counts"] = section_counts(cores)
    data["missing_from_matrix"] = sorted(set(repo_cores) - set(matrix_cores))
    data["unknown_in_matrix"] = sorted(set(matrix_cores) - set(repo_cores))
    if sd_root is not None:
        data["sd_scan"] = scan_sd(sd_root, cores)
    if asset_root is not None:
        data["asset_scan"] = scan_asset_root(asset_root, cores)
    return data


def check_audit(data: dict[str, Any], include_sd: bool) -> list[str]:
    errors: list[str] = []
    if data["missing_from_matrix"]:
        errors.append("cores missing from matrix: " + ", ".join(data["missing_from_matrix"]))
    if data["unknown_in_matrix"]:
        errors.append("matrix rows without cores/* directory: " + ", ".join(data["unknown_in_matrix"]))

    expected = {
        "Hardware OK": data["section_counts"].get("hardware_ok", 0),
        "Hardware issue / hardware asset blocker": data["section_counts"].get("hardware_issues", 0),
        "Build OK / Needs HW test": data["section_counts"].get("build_ok_needs_hw_test", 0),
        "Blocked or build failed": data["section_counts"].get("blocked_failed", 0),
        "No RTL / Schematic Only": data["section_counts"].get("no_rtl", 0),
        "Not yet attempted": len(data["missing_from_matrix"]),
    }
    for bucket, count in expected.items():
        recorded = data["coverage_summary"].get(bucket, {}).get("count")
        if recorded is not None and recorded != count:
            errors.append(f"coverage count mismatch for {bucket}: matrix={recorded} actual={count}")

    if include_sd and data.get("sd_scan", {}).get("available"):
        for core, row in data["sd_scan"]["cores"].items():
            expected_hash = row.get("expected_sha1")
            if expected_hash and row["bitstream_present"] and not row["hash_matches_matrix"]:
                errors.append(f"SD bitstream hash mismatch for {core}")
    return errors


def write_json(path: Path, data: dict[str, Any]) -> None:
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def print_summary(data: dict[str, Any]) -> None:
    print(f"matrix: {data['matrix_path']}")
    print(f"repo cores: {data['repo_core_count']}")
    print(f"matrix cores: {data['matrix_core_count']}")
    for key, value in sorted(data["section_counts"].items()):
        print(f"{key}: {value}")
    if data["missing_from_matrix"]:
        print("missing: " + ", ".join(data["missing_from_matrix"]))
    if data["unknown_in_matrix"]:
        print("unknown: " + ", ".join(data["unknown_in_matrix"]))

    sd = data.get("sd_scan")
    if sd and sd.get("available"):
        mismatches = [
            core for core, row in sd["cores"].items()
            if row["bitstream_present"] and row.get("expected_sha1") and not row["hash_matches_matrix"]
        ]
        missing_payloads = [
            core for core, row in sd["cores"].items()
            if row["assets_dir_present"] and row["payload_count"] == 0
        ]
        print(f"sd root: {sd['sd_root']}")
        print(f"sd bitstream hash mismatches: {len(mismatches)}")
        if mismatches:
            print("sd hash mismatch cores: " + ", ".join(mismatches))
        print(f"sd cores with no detected ROM/cart payloads: {len(missing_payloads)}")
        if missing_payloads:
            print("sd no-payload cores: " + ", ".join(missing_payloads))

    assets = data.get("asset_scan")
    if assets and assets.get("available"):
        available_payloads = [
            core for core, row in assets["cores"].items()
            if row["payload_count"] > 0
        ]
        missing_payloads = [
            core for core, row in assets["cores"].items()
            if row["assets_dir_present"] and row["payload_count"] == 0
        ]
        print(f"asset root: {assets['asset_root']}")
        print(f"asset cores with ROM/cart payloads: {len(available_payloads)}")
        print(f"asset cores with asset dir but no payloads: {len(missing_payloads)}")
        if missing_payloads:
            print("asset no-payload cores: " + ", ".join(missing_payloads))


def copy_asset_payloads(asset_root: Path, dest_root: Path, core: str, row: dict[str, Any]) -> dict[str, Any]:
    pocket_folder = row.get("pocket_folder")
    if not pocket_folder:
        return {"core": core, "copied": 0, "skipped": True, "reason": "matrix row has no pocket folder"}
    asset_folder = pocket_folder.split(".")[-1]
    src_dir = asset_root / asset_folder
    dst_dir = dest_root / "Assets" / asset_folder
    copied: list[str] = []
    if not src_dir.exists():
        return {"core": core, "asset_folder": asset_folder, "copied": 0, "missing_source": True}
    for src in sorted(src_dir.rglob("*")):
        if not src.is_file() or src.suffix.lower() not in PAYLOAD_EXTS:
            continue
        rel = src.relative_to(src_dir)
        dst = dst_dir / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        copied.append(str(rel))
    platform_src = asset_root.parent / "Platforms" / f"{asset_folder}.json"
    platform_dst = dest_root / "Platforms" / f"{asset_folder}.json"
    platform_copied = False
    if platform_src.exists():
        platform_dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(platform_src, platform_dst)
        platform_copied = True
    return {
        "core": core,
        "asset_folder": asset_folder,
        "copied": len(copied),
        "files": copied,
        "platform_copied": platform_copied,
    }


def copy_assets(args: argparse.Namespace) -> int:
    data = parse_matrix(args.matrix)
    cores = data["cores"]
    results = []
    for core in args.cores:
        row = cores.get(core)
        if row is None:
            results.append({"core": core, "copied": 0, "error": "core is not in matrix"})
            continue
        results.append(copy_asset_payloads(args.asset_root, args.dest_root, core, row))
    output = {"asset_root": str(args.asset_root), "dest_root": str(args.dest_root), "results": results}
    if args.write:
        write_json(args.write, output)
    print(json.dumps(output, indent=2))
    return 1 if any("error" in row for row in results) else 0


def find_first_payload(root: Path) -> Path | None:
    for path in sorted(root.rglob("*")):
        if path.is_file() and path.suffix.lower() in PAYLOAD_EXTS:
            return path
    return None


def unquote_yaml(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        value = value[1:-1]
    return value.replace('\\"', '"').replace("\\\\", "\\")


def resolve_profile_path(value: str, root: Path, profile_dir: Path, apfsim: Path) -> Path:
    apfsim_dir = apfsim.resolve().parents[1] if len(apfsim.resolve().parents) > 1 else apfsim.resolve().parent
    text = unquote_yaml(value)
    text = text.replace("{root}", str(root))
    text = text.replace("{profile_dir}", str(profile_dir))
    text = text.replace("{apfsim}", str(apfsim_dir))
    return Path(text)


def scenario_boot_payload(scenario_path: Path, root: Path, profile_dir: Path, apfsim: Path) -> Path | None:
    if not scenario_path.exists():
        return None
    slots: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    in_data_slots = False
    for raw in scenario_path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if raw[:1] not in {" ", "\t", "-"} and line.endswith(":"):
            in_data_slots = line == "data_slots:"
            current = None
            continue
        if not in_data_slots:
            continue
        if line.startswith("- id:"):
            current = {"id": line.split(":", 1)[1].strip()}
            slots.append(current)
            continue
        if current is None or ":" not in line:
            continue
        key, value = [part.strip() for part in line.split(":", 1)]
        if key in {"file", "deferload", "nonvolatile"}:
            current[key] = value
    candidates = [
        slot for slot in slots
        if slot.get("file") and slot.get("deferload", "false").lower() != "true"
        and slot.get("nonvolatile", "false").lower() != "true"
    ]
    if not candidates:
        return None
    selected = next((slot for slot in candidates if str(slot.get("id")) == "1"), candidates[0])
    path = resolve_profile_path(str(selected["file"]), root, profile_dir, apfsim)
    return path if path.exists() else None


def fnv1a64_bytes(data: bytes) -> int:
    h = 0xCBF29CE484222325
    for byte in data:
        h ^= byte
        h = (h * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return h


def scenario_slot_records(lines: list[str]) -> list[dict[str, Any]]:
    slots: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    in_data_slots = False
    for index, raw in enumerate(lines):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if raw[:1] not in {" ", "\t", "-"} and line.endswith(":"):
            in_data_slots = line == "data_slots:"
            current = None
            continue
        if not in_data_slots:
            continue
        if line.startswith("- id:"):
            current = {"id": line.split(":", 1)[1].strip(), "start": index, "end": len(lines)}
            if slots:
                slots[-1]["end"] = index
            slots.append(current)
            continue
        if current is None or ":" not in line:
            continue
        key, value = [part.strip() for part in line.split(":", 1)]
        current[key] = value
        current[f"{key}_line"] = index
    return slots


def scenario_path_token(path: Path, root: Path) -> str:
    try:
        return "{root}/" + str(path.relative_to(root))
    except ValueError:
        return str(path)


def scenario_expected_total_loaded_bytes(lines: list[str], root: Path, profile_dir: Path, apfsim: Path) -> int | None:
    total = 0
    found = False
    for slot in scenario_slot_records(lines):
        file_text = slot.get("file")
        if not file_text:
            continue
        if str(slot.get("setup_only", "false")).lower() == "true":
            continue
        if str(slot.get("deferload", "false")).lower() == "true":
            continue
        if str(slot.get("nonvolatile", "false")).lower() == "true":
            continue
        path = resolve_profile_path(str(file_text), root, profile_dir, apfsim)
        if not path.exists():
            continue
        total += path.stat().st_size
        found = True
    return total if found else None


def update_expected_total_loaded_bytes(
    lines: list[str],
    total: int | None,
    changes: list[dict[str, Any]],
) -> list[str]:
    if total is None:
        return lines
    for index, raw in enumerate(lines):
        if raw.strip().startswith("expected_total_loaded_bytes:"):
            old_value = raw.split(":", 1)[1].strip()
            new_line = f"    expected_total_loaded_bytes: {total}"
            if raw != new_line:
                lines[index] = new_line
                changes.append({
                    "expect": "expected_total_loaded_bytes",
                    "old_value": old_value,
                    "new_value": total,
                })
            break
    return lines


def asset_core_root_for(setup_path: Path) -> Path | None:
    for parent in setup_path.parents:
        if parent.parent.name == "Assets":
            return parent
    return None


def load_instance_json(path: Path) -> dict[str, Any] | None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    instance = data.get("instance")
    return instance if isinstance(instance, dict) else None


def find_instance_payload(asset_root: Path, filename: str) -> Path | None:
    candidates = sorted(asset_root.rglob(filename))
    if not candidates:
        return None
    return next((path for path in candidates if path.parent.name == "common"), candidates[0])


def instance_payloads_available(asset_root: Path, instance: dict[str, Any]) -> tuple[bool, dict[str, Path], list[str]]:
    payloads: dict[str, Path] = {}
    missing: list[str] = []
    for ref in instance.get("data_slots", []):
        slot_id = str(ref.get("id", ""))
        filename = ref.get("filename")
        if not slot_id or not filename:
            continue
        suffix = Path(str(filename)).suffix.lower()
        if suffix in {".sav", ".hi"}:
            # Nonvolatile slots are optional for bring-up; apfsim can seed them
            # with a generated/mock save instead of requiring archived saves.
            continue
        payload = find_instance_payload(asset_root, str(filename))
        if payload is None:
            missing.append(str(filename))
            continue
        payloads[slot_id] = payload
    return not missing and bool(payloads), payloads, missing


def instance_json_sort_key(path: Path, current: Path) -> tuple[int, int, str]:
    if path == current:
        return (0, 0, str(path))
    return (1, 1 if "_alternatives" in path.parts else 0, str(path))


def instance_json_matches(path: Path, instance: dict[str, Any], selector: str) -> bool:
    needle = selector.casefold()
    haystacks = [path.stem]
    for key in ("name", "setname", "id"):
        value = instance.get(key)
        if value is not None:
            haystacks.append(str(value))
    for ref in instance.get("data_slots", []):
        if not isinstance(ref, dict):
            continue
        filename = ref.get("filename")
        if filename is not None:
            haystacks.append(str(filename))
    return any(needle in haystack.casefold() for haystack in haystacks)


def normalize_apfsim_diagnostics(summary: dict[str, Any], diagnostics: Any) -> None:
    if not isinstance(diagnostics, dict):
        return
    diag_list = diagnostics.get("diagnostics")
    if not isinstance(diag_list, list):
        return

    for diag in diag_list:
        if not isinstance(diag, dict):
            continue
        if diag.get("code") != "BOOT_TIMEOUT":
            continue
        message = " ".join(
            str(value)
            for value in (
                diag.get("summary"),
                diag.get("observed", {}).get("message") if isinstance(diag.get("observed"), dict) else None,
            )
            if value
        ).casefold()
        if "total loaded byte count mismatch" not in message:
            continue

        diag["code"] = "DATA_LOADED_BYTE_COUNT_MISMATCH"
        diag["summary"] = "Loaded data byte count did not match the scenario expectation."
        diag["likely_causes"] = [
            "selected instance JSON points at a different payload set than the scenario expects",
            "asset copy or setup-slot repair changed which payloads are loaded",
            "scenario expected_total_loaded_bytes is stale for this instance",
        ]
        diag["repairs"] = [
            {
                "kind": "data_slot_diagnostic",
                "confidence": 0.7,
                "description": "Compare scenario data slots against the selected instance JSON and loaded byte counts.",
            }
        ]

        if summary.get("first_error_code") == "BOOT_TIMEOUT":
            summary["first_error_code"] = "DATA_LOADED_BYTE_COUNT_MISMATCH"
        blocking_codes = summary.get("blocking_codes")
        if isinstance(blocking_codes, list):
            summary["blocking_codes"] = [
                "DATA_LOADED_BYTE_COUNT_MISMATCH" if code == "BOOT_TIMEOUT" else code
                for code in blocking_codes
            ]


def select_available_instance_json(
    setup_path: Path,
    asset_root: Path,
    instance_match: str | None = None,
) -> tuple[Path, dict[str, Any], dict[str, Path], list[str], dict[str, Any]]:
    current_instance = load_instance_json(setup_path)
    candidates = sorted(
        (path for path in asset_root.rglob("*.json") if path.is_file()),
        key=lambda path: instance_json_sort_key(path, setup_path),
    )

    if instance_match:
        matched: list[tuple[Path, dict[str, Any]]] = []
        for candidate in candidates:
            instance = load_instance_json(candidate)
            if instance is None or not instance_json_matches(candidate, instance, instance_match):
                continue
            matched.append((candidate, instance))

        best_missing: list[str] = []
        for candidate, instance in matched:
            available, payloads, missing = instance_payloads_available(asset_root, instance)
            if available:
                return candidate, instance, payloads, missing, {
                    "instance_match": instance_match,
                    "matched": True,
                    "selected": str(candidate.relative_to(asset_root)),
                }
            if not best_missing and missing:
                best_missing = missing

        return setup_path, current_instance or {}, {}, best_missing, {
            "instance_match": instance_match,
            "matched": False,
            "matched_candidates": [str(path.relative_to(asset_root)) for path, _ in matched],
            "reason": "no matching instance JSON with all payloads available",
        }

    if current_instance is not None:
        available, payloads, missing = instance_payloads_available(asset_root, current_instance)
        if available:
            return setup_path, current_instance, payloads, missing, {
                "selected": str(setup_path.relative_to(asset_root)),
                "reason": "current setup payloads available",
            }

    best_missing = missing if current_instance is not None else []
    for candidate in candidates:
        instance = load_instance_json(candidate)
        if instance is None:
            continue
        available, payloads, missing = instance_payloads_available(asset_root, instance)
        if available:
            return candidate, instance, payloads, missing, {
                "selected": str(candidate.relative_to(asset_root)),
                "reason": "first available instance payloads",
            }
        if not best_missing and missing:
            best_missing = missing

    return setup_path, current_instance or {}, {}, best_missing, {
        "selected": str(setup_path.relative_to(asset_root)),
        "reason": "no instance JSON with all payloads available",
    }


def patch_scenario_instance_slots(
    scenario_path: Path,
    root: Path,
    profile_dir: Path,
    apfsim: Path,
    instance_match: str | None = None,
) -> dict[str, Any]:
    if not scenario_path.exists():
        return {"patched": False, "reason": f"scenario missing: {scenario_path}"}
    original = scenario_path.read_text(encoding="utf-8")
    lines = original.splitlines()
    slots = scenario_slot_records(lines)
    by_id = {str(slot.get("id")): slot for slot in slots}
    changes: list[dict[str, Any]] = []
    updates: list[dict[str, Any]] = []
    selections: list[dict[str, Any]] = []

    for setup_slot in slots:
        setup_file = setup_slot.get("file")
        setup_file_text = unquote_yaml(str(setup_file)) if setup_file else ""
        if not setup_file_text or not setup_file_text.lower().endswith(".json"):
            continue
        if str(setup_slot.get("setup_only", "false")).lower() != "true" and str(setup_slot.get("deferload", "false")).lower() != "true":
            continue
        setup_path = resolve_profile_path(setup_file_text, root, profile_dir, apfsim)
        if not setup_path.exists():
            continue
        asset_root = asset_core_root_for(setup_path)
        if asset_root is None:
            continue
        selected_setup, instance, payloads, missing, selection = select_available_instance_json(
            setup_path,
            asset_root,
            instance_match,
        )
        selections.append(selection)
        if not payloads:
            changes.append({
                "slot": int(setup_slot.get("id", 0)),
                "old_file": setup_file_text,
                "missing_payloads": missing,
            })
            continue
        if selected_setup != setup_path:
            file_line = setup_slot.get("file_line")
            if file_line is not None:
                new_setup_file = scenario_path_token(selected_setup, root)
                lines[int(file_line)] = f"    file: \"{new_setup_file}\""
                changes.append({
                    "slot": int(setup_slot.get("id", 0)),
                    "old_file": setup_file_text,
                    "new_file": new_setup_file,
                })
        for ref in instance.get("data_slots", []):
            slot_id = str(ref.get("id", ""))
            filename = ref.get("filename")
            target_slot = by_id.get(slot_id)
            if not slot_id or not filename or target_slot is None:
                continue
            selected = payloads.get(slot_id)
            if selected is None:
                continue
            old_file = unquote_yaml(str(target_slot.get("file", "")))
            new_file = scenario_path_token(selected, root)
            if old_file == new_file:
                continue
            file_line = target_slot.get("file_line")
            if file_line is None:
                continue
            checksum = fnv1a64_bytes(selected.read_bytes())
            updates.append({
                "file_line": int(file_line),
                "checksum_line": target_slot.get("expected_checksum_line"),
                "new_file": new_file,
                "checksum": checksum,
            })
            changes.append({"slot": int(slot_id), "old_file": old_file, "new_file": new_file})

    for update in sorted(updates, key=lambda item: int(item["file_line"]), reverse=True):
        file_line = int(update["file_line"])
        lines[file_line] = f"    file: \"{update['new_file']}\""
        checksum = int(update["checksum"])
        checksum_line = update.get("checksum_line")
        if checksum_line is None:
            lines.insert(file_line + 1, f"    expected_checksum: 0x{checksum:016X}")
        else:
            lines[int(checksum_line)] = f"    expected_checksum: 0x{checksum:016X}"

    lines = update_expected_total_loaded_bytes(
        lines,
        scenario_expected_total_loaded_bytes(lines, root, profile_dir, apfsim),
        changes,
    )

    updated = "\n".join(lines) + "\n"
    if updated == original:
        return {"patched": False, "changes": changes, "selections": selections}
    scenario_path.write_text(updated, encoding="utf-8")
    return {
        "patched": True,
        "scenario": str(scenario_path.relative_to(ROOT)) if scenario_path.is_relative_to(ROOT) else str(scenario_path),
        "changes": changes,
        "selections": selections,
    }


def platform_id_for(core: str, row: dict[str, Any]) -> str:
    pocket_folder = row.get("pocket_folder")
    if pocket_folder:
        return pocket_folder.split(".")[-1]
    return f"jt{core}"


def stage_existing_bitstream(core: str, dist_root: Path, platform_id: str) -> dict[str, Any]:
    target = dist_root / "Cores" / f"jotego.{platform_id}" / "bitstream.rbf_r"
    if target.exists():
        return {
            "present": True,
            "path": str(target.relative_to(ROOT)),
            "sha1": sha1_file(target),
        }

    search_root = ROOT / ".apc"
    if not search_root.exists():
        return {"present": False, "copied": False, "reason": "no .apc build cache"}

    candidates = []
    for candidate in search_root.glob(f"{core}-*/dist/Cores/jotego.{platform_id}/bitstream.rbf_r"):
        if candidate.resolve() == target.resolve():
            continue
        candidates.append(candidate)
    candidates.sort(key=lambda path: path.stat().st_mtime, reverse=True)
    if not candidates:
        return {
            "present": False,
            "copied": False,
            "reason": f"no cached bitstream for jotego.{platform_id}",
            "target": str(target.relative_to(ROOT)),
        }

    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(candidates[0], target)
    return {
        "present": True,
        "copied": True,
        "source": str(candidates[0].relative_to(ROOT)),
        "target": str(target.relative_to(ROOT)),
        "sha1": sha1_file(target),
    }


def qsf_top(export_dir: Path) -> str | None:
    qsf = export_dir / "src" / "fpga" / "ap_core.qsf"
    if not qsf.exists():
        return None
    top_re = re.compile(r"set_global_assignment\s+-name\s+TOP_LEVEL_ENTITY\s+(\S+)")
    for line in qsf.read_text(encoding="utf-8").splitlines():
        match = top_re.search(line)
        if match:
            return match.group(1)
    return None


def patch_apfsim_profile_top(profile_path: Path, top: str | None) -> dict[str, Any]:
    if not profile_path.exists():
        return {"patched": False, "reason": f"profile missing: {profile_path}"}
    profile = json.loads(profile_path.read_text(encoding="utf-8"))
    wrapper = profile.get("wrapper_generation", {}).get("jtframe_pocket_logical_wrapper")
    if wrapper:
        return {
            "patched": False,
            "top": profile.get("top"),
            "reason": "profile uses generated JTFRAME logical APF wrapper",
        }
    if not top:
        return {"patched": False, "reason": "no TOP_LEVEL_ENTITY found in ap_core.qsf"}
    old_top = profile.get("top")
    if old_top == top:
        return {"patched": False, "top": top, "reason": "profile already used QSF top"}
    profile["top"] = top
    profile_path.write_text(json.dumps(profile, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return {"patched": True, "old_top": old_top, "top": top}


def stage_apfsim_runtime_collateral(profile_path: Path, root: Path) -> dict[str, Any]:
    if not profile_path.exists():
        return {"patched": False, "reason": f"profile missing: {profile_path}"}
    source_dir = root / "src" / "fpga"
    if not source_dir.exists():
        return {"patched": False, "reason": f"runtime source dir missing: {source_dir}"}

    runtime_dir = profile_path.parent / "runtime"
    if runtime_dir.exists():
        shutil.rmtree(runtime_dir)
    runtime_dir.mkdir(parents=True, exist_ok=True)

    copied: list[str] = []
    skipped: list[str] = []
    copied_names: set[str] = set()
    for source in sorted(source_dir.iterdir()):
        if not source.is_file():
            continue
        name = source.name
        if name in RUNTIME_COLLATERAL_SKIP:
            skipped.append(name)
            continue
        if name not in RUNTIME_COLLATERAL_NAMES and source.suffix.lower() not in RUNTIME_COLLATERAL_SUFFIXES:
            continue
        shutil.copy2(source, runtime_dir / name)
        copied.append(name)
        copied_names.add(name)

    for name in sorted(RUNTIME_COLLATERAL_NAMES - copied_names):
        if name in RUNTIME_COLLATERAL_SKIP:
            continue
        for search_root in (ROOT / "modules", ROOT / "cores"):
            matches = sorted(path for path in search_root.rglob(name) if path.is_file())
            if not matches:
                continue
            shutil.copy2(matches[0], runtime_dir / name)
            copied.append(name)
            copied_names.add(name)
            break

    if not copied:
        shutil.rmtree(runtime_dir)
        return {
            "patched": False,
            "reason": "no safe runtime collateral found",
            "skipped": skipped,
        }

    profile = json.loads(profile_path.read_text(encoding="utf-8"))
    old_runtime_cwd = profile.get("runtime_cwd")
    new_runtime_cwd = "{profile_dir}/runtime"
    profile["runtime_cwd"] = new_runtime_cwd
    profile_path.write_text(json.dumps(profile, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return {
        "patched": old_runtime_cwd != new_runtime_cwd,
        "old_runtime_cwd": old_runtime_cwd,
        "runtime_cwd": new_runtime_cwd,
        "copied": copied,
        "skipped": skipped,
    }


def patch_input_video_gate_scenario(
    scenario_path: Path,
    *,
    window_frames: int,
    min_changed_frames: int,
    min_changed_pixels: int,
) -> dict[str, Any]:
    if not scenario_path.exists():
        return {"patched": False, "reason": f"scenario missing: {scenario_path}"}

    original = scenario_path.read_text(encoding="utf-8")
    lines = original.splitlines()
    patched = lines[:]

    def top_level_index(name: str) -> int | None:
        target = f"{name}:"
        for index, line in enumerate(patched):
            if line == target:
                return index
        return None

    insert_at = top_level_index("run")
    if insert_at is None:
        insert_at = len(patched)

    inserted_sections: list[str] = []
    if top_level_index("inputs") is None:
        input_block = [
            "inputs:",
            "  - frame: 2",
            "    player: 1",
            "    button: Select",
            "    hold_frames: 2",
            "  - frame: 4",
            "    player: 1",
            "    button: Start",
            "    hold_frames: 2",
        ]
        patched[insert_at:insert_at] = input_block
        insert_at += len(input_block)
        inserted_sections.append("inputs")

    if top_level_index("phases") is None and top_level_index("video_phases") is None:
        phase_block = [
            "phases:",
            "  - name: post_input",
            "    after_input: true",
            f"    duration_frames: {window_frames}",
            "    require_changed: true",
            f"    min_changed_frames: {min_changed_frames}",
            f"    min_changed_pixels: {min_changed_pixels}",
        ]
        patched[insert_at:insert_at] = phase_block
        inserted_sections.append("phases")

    video_index: int | None = None
    for index, line in enumerate(patched):
        if line == "  video:":
            video_index = index
            break
    if video_index is None:
        return {"patched": False, "reason": f"scenario has no expect.video block: {scenario_path}"}

    text = "\n".join(patched)
    inserted_expect: list[str] = []
    expect_lines = [
        ("require_change_after_input", "true"),
        ("input_response_window_frames", str(window_frames)),
        ("min_changed_frames_after_input", str(min_changed_frames)),
        ("min_changed_pixels_after_input", str(min_changed_pixels)),
    ]
    for key, value in reversed(expect_lines):
        if f"    {key}:" in text:
            continue
        patched.insert(video_index + 1, f"    {key}: {value}")
        inserted_expect.append(key)

    updated = "\n".join(patched) + "\n"
    if updated == original:
        return {"patched": False, "reason": "scenario already had input video gate"}
    scenario_path.write_text(updated, encoding="utf-8")
    return {
        "patched": True,
        "scenario": str(scenario_path.relative_to(ROOT)) if scenario_path.is_relative_to(ROOT) else str(scenario_path),
        "inserted_sections": inserted_sections,
        "inserted_expect": sorted(inserted_expect),
    }


def patch_input_audio_gate_scenario(
    scenario_path: Path,
    *,
    window_frames: int,
    min_samples: int,
    min_nonzero_samples: int,
    min_peak: int,
) -> dict[str, Any]:
    if not scenario_path.exists():
        return {"patched": False, "reason": f"scenario missing: {scenario_path}"}

    original = scenario_path.read_text(encoding="utf-8")
    patched = original.splitlines()

    def top_level_index(name: str) -> int | None:
        target = f"{name}:"
        for index, line in enumerate(patched):
            if line == target:
                return index
        return None

    insert_at = top_level_index("run")
    if insert_at is None:
        insert_at = len(patched)

    inserted_sections: list[str] = []
    if top_level_index("inputs") is None:
        input_block = [
            "inputs:",
            "  - frame: 2",
            "    player: 1",
            "    button: Select",
            "    hold_frames: 2",
            "  - frame: 4",
            "    player: 1",
            "    button: Start",
            "    hold_frames: 2",
        ]
        patched[insert_at:insert_at] = input_block
        inserted_sections.append("inputs")

    audio_index: int | None = None
    expect_index = top_level_index("expect")
    for index, line in enumerate(patched):
        if line == "  audio:":
            audio_index = index
            break
    if audio_index is None:
        if expect_index is None:
            return {"patched": False, "reason": f"scenario has no expect block: {scenario_path}"}
        insert_audio_at = expect_index + 1
        while insert_audio_at < len(patched) and patched[insert_audio_at].startswith("  ") and not patched[insert_audio_at].startswith("  audio:"):
            insert_audio_at += 1
        patched.insert(insert_audio_at, "  audio:")
        audio_index = insert_audio_at
        inserted_sections.append("expect.audio")

    text = "\n".join(patched)
    inserted_expect: list[str] = []
    expect_lines = [
        ("require_activity_after_input", "true"),
        ("input_response_window_frames", str(window_frames)),
        ("min_samples_after_input", str(min_samples)),
        ("min_nonzero_samples_after_input", str(min_nonzero_samples)),
        ("min_peak_after_input", str(min_peak)),
    ]
    for key, value in reversed(expect_lines):
        if f"    {key}:" in text:
            continue
        patched.insert(audio_index + 1, f"    {key}: {value}")
        inserted_expect.append(key)

    updated = "\n".join(patched) + "\n"
    if updated == original:
        return {"patched": False, "reason": "scenario already had input audio gate"}
    scenario_path.write_text(updated, encoding="utf-8")
    return {
        "patched": True,
        "scenario": str(scenario_path.relative_to(ROOT)) if scenario_path.is_relative_to(ROOT) else str(scenario_path),
        "inserted_sections": inserted_sections,
        "inserted_expect": sorted(inserted_expect),
    }


def apfsim_env() -> dict[str, str]:
    env = os.environ.copy()
    env.setdefault("JTCORES_ROOT", str(ROOT))
    return env


def pocket_export_env(args: argparse.Namespace | None = None) -> dict[str, str]:
    env = os.environ.copy()
    if args is not None and getattr(args, "allow_legacy_cps", False):
        env["JTFRAME_POCKET_ALLOW_LEGACY_CPS"] = "1"
    return env


def apfsim_summary(outdir: Path) -> dict[str, Any]:
    summary_path = next(
        (path for path in (outdir / "bringup" / "run" / "summary.json", outdir / "bringup" / "summary.json") if path.exists()),
        outdir / "bringup" / "run" / "summary.json",
    )
    diagnostics_path = next(
        (path for path in (outdir / "bringup" / "run" / "diagnostics.json", outdir / "bringup" / "diagnostics.json") if path.exists()),
        outdir / "bringup" / "run" / "diagnostics.json",
    )
    package_path = next(
        (path for path in (outdir / "bringup" / "run" / "package_check.json", outdir / "package_check.json") if path.exists()),
        outdir / "package_check.json",
    )
    result: dict[str, Any] = {}
    summary: dict[str, Any] = {}
    diagnostics: Any = None
    if summary_path.exists():
        try:
            summary = json.loads(summary_path.read_text(encoding="utf-8")).get("row", {})
            result["summary"] = summary
        except json.JSONDecodeError:
            result["summary_parse_error"] = str(summary_path)
    if diagnostics_path.exists():
        try:
            diagnostics = json.loads(diagnostics_path.read_text(encoding="utf-8"))
            result["diagnostics"] = diagnostics.get("diagnostics", diagnostics)
        except json.JSONDecodeError:
            result["diagnostics_parse_error"] = str(diagnostics_path)
    normalize_apfsim_diagnostics(summary, diagnostics)
    if package_path.exists():
        try:
            package = json.loads(package_path.read_text(encoding="utf-8"))
            result["package_ok"] = package.get("ok")
            result["package_errors"] = package.get("package_errors", [])
        except json.JSONDecodeError:
            result["package_parse_error"] = str(package_path)
    return result


def run_sim_job(core: str, args: argparse.Namespace) -> dict[str, Any]:
    outdir = ROOT / args.out_root / f"{core}-matrix-sim"
    export_dir = outdir / "export"
    dist_root = export_dir / "dist"
    package_check = outdir / "package_check.json"
    outdir.mkdir(parents=True, exist_ok=True)

    export_cmd = [str(POCKET_DIR / "export_apc_project.sh"), core, str(export_dir)]
    export_proc = subprocess.run(export_cmd, cwd=ROOT, env=pocket_export_env(args), text=True, capture_output=True)
    row: dict[str, Any] = {
        "core": core,
        "stage": "sim",
        "outdir": str(outdir.relative_to(ROOT)),
        "export_returncode": export_proc.returncode,
        "export_stdout_tail": export_proc.stdout.splitlines()[-40:],
        "export_stderr_tail": export_proc.stderr.splitlines()[-80:],
    }
    if export_proc.returncode != 0:
        row["returncode"] = export_proc.returncode
        return row

    matrix = parse_matrix(args.matrix)
    core_row = matrix["cores"].get(core, {})
    asset_copy = copy_asset_payloads(args.asset_root, dist_root, core, core_row)
    row["asset_copy"] = asset_copy
    expected_platform = platform_id_for(core, core_row)
    row["expected_platform_id"] = expected_platform
    row["bitstream"] = stage_existing_bitstream(core, dist_root, expected_platform)

    apfsim = args.apfsim
    if not apfsim.exists():
        row["returncode"] = 127
        row["stderr_tail"] = [f"missing apfsim binary: {apfsim}"]
        return row

    package_cmd = [
        str(apfsim),
        "package-check",
        "--root",
        str(dist_root),
        "--expected-platform-id",
        expected_platform,
        "--json-out",
        str(package_check),
        "--strict",
    ]
    env = apfsim_env()
    package_proc = subprocess.run(package_cmd, cwd=ROOT, env=env, text=True, capture_output=True)
    row["package_returncode"] = package_proc.returncode
    row["package_stdout_tail"] = package_proc.stdout.splitlines()[-40:]
    row["package_stderr_tail"] = package_proc.stderr.splitlines()[-80:]
    if package_proc.returncode != 0 or args.package_only:
        row["returncode"] = package_proc.returncode
        row.update(apfsim_summary(outdir))
        return row

    fallback_rom = find_first_payload(dist_root / "Assets" / expected_platform)
    if fallback_rom is None:
        row["returncode"] = 2
        row["stderr_tail"] = [f"no ROM/cart payload found under {dist_root / 'Assets' / expected_platform}"]
        return row

    profile_out = outdir / "bringup" / "generated-profile"
    generate_cmd = [
        str(apfsim),
        "generate-profile",
        "--root",
        str(export_dir),
        "--name",
        core,
        "--output",
        str(profile_out),
        "--force",
        "--json",
    ]
    generate_proc = subprocess.run(generate_cmd, cwd=ROOT, env=env, text=True, capture_output=True)
    row["profile_generate_returncode"] = generate_proc.returncode
    if generate_proc.returncode != 0:
        row["profile_generate_stdout_tail"] = generate_proc.stdout.splitlines()[-80:]
    row["profile_generate_stderr_tail"] = generate_proc.stderr.splitlines()[-80:]
    if generate_proc.returncode != 0:
        row["returncode"] = generate_proc.returncode
        return row

    profile_path = profile_out / core / f"{core}.json"
    try:
        generated = json.loads(generate_proc.stdout)
        profile_path = Path(generated.get("paths", {}).get("profile", profile_path))
        row["profile_generate_report"] = {
            "output_dir": generated.get("output_dir"),
            "warnings": generated.get("warnings", []),
            "risks": generated.get("risks", []),
            "selected_shims": generated.get("selected_shims", []),
        }
    except json.JSONDecodeError:
        row["profile_generate_parse_error"] = True
    row["profile"] = str(profile_path)
    row["profile_top"] = patch_apfsim_profile_top(profile_path, qsf_top(export_dir))
    row["profile_runtime_cwd"] = stage_apfsim_runtime_collateral(profile_path, export_dir)
    scenario_path = profile_path.parent / "scenario.yml"
    row["scenario_instance_binding"] = patch_scenario_instance_slots(
        scenario_path,
        export_dir,
        profile_path.parent,
        apfsim,
        instance_match=args.instance_match,
    )
    if args.input_video_gate:
        row["input_video_gate"] = patch_input_video_gate_scenario(
            scenario_path,
            window_frames=args.input_video_window_frames,
            min_changed_frames=args.input_video_min_changed_frames,
            min_changed_pixels=args.input_video_min_changed_pixels,
        )
    if args.input_audio_gate:
        row["input_audio_gate"] = patch_input_audio_gate_scenario(
            scenario_path,
            window_frames=args.input_audio_window_frames,
            min_samples=args.input_audio_min_samples,
            min_nonzero_samples=args.input_audio_min_nonzero_samples,
            min_peak=args.input_audio_min_peak,
        )
    scenario_rom = scenario_boot_payload(scenario_path, export_dir, profile_path.parent, apfsim)
    rom = scenario_rom or fallback_rom
    row["rom_binding"] = "scenario" if scenario_rom else "fallback_override"

    bringup_cmd = [
        str(apfsim),
        "bringup",
        "--profile",
        str(profile_path),
        "--root",
        str(export_dir),
        "--expected-platform-id",
        expected_platform,
        "--out",
        str(outdir / "bringup"),
        "--repair",
        "--frames",
        str(args.frames),
        "--timeout-cycles",
        str(args.timeout_cycles),
        "--timeout",
        str(args.timeout),
    ]
    if scenario_rom is None:
        bringup_cmd.extend(["--rom", str(rom)])
    if args.sim_no_build:
        bringup_cmd.append("--no-build")
    bringup_proc = subprocess.run(bringup_cmd, cwd=ROOT, env=env, text=True, capture_output=True)
    row["returncode"] = bringup_proc.returncode
    row["rom"] = str(rom)
    row["stdout_tail"] = bringup_proc.stdout.splitlines()[-80:]
    row["stderr_tail"] = bringup_proc.stderr.splitlines()[-120:]
    row.update(apfsim_summary(outdir))
    return row


def run_jobs(args: argparse.Namespace) -> int:
    if args.stage == "sim":
        results = []
        for core in args.cores:
            print(f"+ apfsim bringup {core}", flush=True)
            row = run_sim_job(core, args)
            results.append(row)
            print(json.dumps(row, indent=2), flush=True)
            if row.get("returncode") != 0 and not args.keep_going:
                if args.write:
                    write_json(args.write, {"runs": results})
                return int(row.get("returncode") or 1)
        if args.write:
            write_json(args.write, {"runs": results})
        return 0 if all(row.get("returncode") == 0 for row in results) else 1

    script = POCKET_DIR / ("build_with_apc.sh" if args.stage == "build" else "export_apc_project.sh")
    results = []
    for core in args.cores:
        outdir = ROOT / args.out_root / f"{core}-matrix-{args.stage}"
        cmd = [str(script), core, str(outdir)]
        print("+ " + " ".join(cmd), flush=True)
        proc = subprocess.run(cmd, cwd=ROOT, env=pocket_export_env(args), text=True, capture_output=True)
        bitstream = outdir / "dist" / "Cores"
        bitstreams = sorted(bitstream.glob("*/bitstream.rbf_r")) if bitstream.exists() else []
        row = {
            "core": core,
            "stage": args.stage,
            "outdir": str(outdir.relative_to(ROOT)),
            "returncode": proc.returncode,
            "stdout_tail": proc.stdout.splitlines()[-40:],
            "stderr_tail": proc.stderr.splitlines()[-80:],
            "bitstream_sha1": sha1_file(bitstreams[0]) if bitstreams else None,
        }
        results.append(row)
        print(json.dumps(row, indent=2), flush=True)
        if proc.returncode != 0 and not args.keep_going:
            if args.write:
                write_json(args.write, {"runs": results})
            return proc.returncode
    if args.write:
        write_json(args.write, {"runs": results})
    return 0 if all(row["returncode"] == 0 for row in results) else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    audit_p = sub.add_parser("audit", help="parse and audit CORE_MATRIX.md")
    audit_p.add_argument("--matrix", type=Path, default=DEFAULT_MATRIX)
    audit_p.add_argument("--sd-root", type=Path)
    audit_p.add_argument("--asset-root", type=Path)
    audit_p.add_argument("--write", type=Path)
    audit_p.add_argument("--quiet", action="store_true")

    check_p = sub.add_parser("check", help="audit and exit nonzero on inconsistencies")
    check_p.add_argument("--matrix", type=Path, default=DEFAULT_MATRIX)
    check_p.add_argument("--sd-root", type=Path)
    check_p.add_argument("--asset-root", type=Path)
    check_p.add_argument("--write", type=Path)

    gen_p = sub.add_parser("generate-json", help="write the machine-readable matrix JSON")
    gen_p.add_argument("--matrix", type=Path, default=DEFAULT_MATRIX)
    gen_p.add_argument("--output", type=Path, default=DEFAULT_JSON)

    assets_p = sub.add_parser("copy-assets", help="copy ROM/cart payloads from an asset cache into a package or SD root")
    assets_p.add_argument("--matrix", type=Path, default=DEFAULT_MATRIX)
    assets_p.add_argument("--asset-root", type=Path, default=DEFAULT_ASSET_ROOT)
    assets_p.add_argument("--dest-root", type=Path, required=True)
    assets_p.add_argument("--write", type=Path)
    assets_p.add_argument("cores", nargs="+")

    run_p = sub.add_parser("run", help="run Pocket export, APC build, or apfsim bring-up for explicit cores")
    run_p.add_argument("--stage", choices=["export", "build", "sim"], default="export")
    run_p.add_argument("--out-root", type=Path, default=Path(".apc"))
    run_p.add_argument("--matrix", type=Path, default=DEFAULT_MATRIX)
    run_p.add_argument("--asset-root", type=Path, default=DEFAULT_ASSET_ROOT)
    run_p.add_argument("--apfsim", type=Path, default=DEFAULT_APFSIM)
    run_p.add_argument("--package-only", action="store_true", help="for --stage sim, stop after apfsim package-check")
    run_p.add_argument("--sim-no-build", action="store_true", help="for --stage sim, pass --no-build to apfsim bringup")
    run_p.add_argument("--allow-legacy-cps", action="store_true", help="allow diagnostic CPS1/CPS1.5/CPS2 legacy-top export")
    run_p.add_argument("--instance-match", help="for --stage sim, prefer an instance JSON whose path/name contains this text")
    run_p.add_argument("--input-video-gate", action="store_true", help="for --stage sim, add coin/start input and require post-input video movement")
    run_p.add_argument("--input-video-window-frames", type=int, default=12)
    run_p.add_argument("--input-video-min-changed-frames", type=int, default=1)
    run_p.add_argument("--input-video-min-changed-pixels", type=int, default=1)
    run_p.add_argument("--input-audio-gate", action="store_true", help="for --stage sim, add coin/start input and require post-input audio activity")
    run_p.add_argument("--input-audio-window-frames", type=int, default=12)
    run_p.add_argument("--input-audio-min-samples", type=int, default=1)
    run_p.add_argument("--input-audio-min-nonzero-samples", type=int, default=1)
    run_p.add_argument("--input-audio-min-peak", type=int, default=1)
    run_p.add_argument("--frames", type=int, default=30)
    run_p.add_argument("--timeout-cycles", type=int, default=250_000_000)
    run_p.add_argument("--timeout", type=int, default=600, help="apfsim subprocess timeout in seconds")
    run_p.add_argument("--write", type=Path)
    run_p.add_argument("--keep-going", action="store_true")
    run_p.add_argument("cores", nargs="+")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.cmd == "run":
        return run_jobs(args)

    if args.cmd == "copy-assets":
        return copy_assets(args)

    if args.cmd == "generate-json":
        data = audit(args.matrix)
        write_json(args.output, data)
        print(f"wrote {args.output}")
        return 0

    data = audit(args.matrix, args.sd_root, getattr(args, "asset_root", None))
    if args.write:
        write_json(args.write, data)
    if not getattr(args, "quiet", False):
        print_summary(data)
    if args.cmd == "check":
        errors = check_audit(data, include_sd=args.sd_root is not None)
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1 if errors else 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
