#!/usr/bin/env python3
"""Independently verify tracked QOF release artifacts and optional reproduction."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import sys
from typing import Optional
import xml.etree.ElementTree as ET
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parents[1]
MAGIC = b"<roblox!\x89\xff\r\n\x1a\n"
ZIP_ENTRY = "BATTLE_PETS.rbxlx"
ZIP_TIME = (1980, 1, 1, 0, 0, 0)
ZIP_CONTRACT = "deflate-9; timestamp=1980-01-01T00:00:00; unix-mode=100644"
PROVENANCE_FIELDS = (
    "qof",
    "source-tree-sha256",
    "generator-sha256",
    "runtime-inventory-sha256",
    "release-builder-sha256",
    "converter-sha256",
    "rbxmk-lock-sha256",
    "rbxmk-version",
    "rbxmk-platform",
    "rbxmk-sha256",
    "descriptor",
    "zip",
)


class VerificationError(RuntimeError):
    """Raised when release bytes or provenance violate the independent contract."""


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_digest(path: Path) -> str:
    return digest(path.read_bytes())


def release_names(qof: str) -> tuple[str, str, str, str]:
    prefix = f"BATTLE_PETS_QOF-{qof}"
    return (
        "BATTLE_PETS.rbxlx",
        f"{prefix}_TEST.rbxl",
        f"{prefix}_RBXLX.zip",
        f"{prefix}_SHA256SUMS.txt",
    )


def source_tree_digest(project_root: Path) -> str:
    source_root = project_root / "src"
    if source_root.is_symlink() or not source_root.is_dir():
        raise VerificationError(f"invalid source root: {source_root}")
    files = sorted(path for path in source_root.rglob("*") if path.is_file())
    if not files:
        raise VerificationError("source tree is empty")
    result = hashlib.sha256()
    for path in files:
        if path.is_symlink():
            raise VerificationError(f"source tree contains a symbolic link: {path}")
        relative = path.relative_to(project_root).as_posix().encode("utf-8")
        data = path.read_bytes()
        result.update(len(relative).to_bytes(4, "big"))
        result.update(relative)
        result.update(len(data).to_bytes(8, "big"))
        result.update(data)
    return result.hexdigest()


def load_lock(project_root: Path) -> dict:
    path = project_root / "tools/rbxmk.lock.json"
    try:
        lock = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise VerificationError(f"invalid rbxmk lock: {error}") from error
    if set(lock) != {"schemaVersion", "version", "descriptor", "platforms"}:
        raise VerificationError("rbxmk lock has unexpected fields")
    if lock["schemaVersion"] != 1 or not isinstance(lock["version"], str):
        raise VerificationError("unsupported rbxmk lock schema")
    if lock["descriptor"] is not None or not isinstance(lock["platforms"], dict):
        raise VerificationError("rbxmk lock must pin descriptor=null and platforms")
    for platform_name, platform_value in lock["platforms"].items():
        if not isinstance(platform_name, str) or not isinstance(platform_value, dict):
            raise VerificationError("invalid rbxmk platform lock")
        if set(platform_value) != {"sha256"} or re.fullmatch(
            r"[0-9a-f]{64}", str(platform_value["sha256"])
        ) is None:
            raise VerificationError(f"invalid rbxmk platform hash: {platform_name}")
    return lock


def parse_manifest(data: bytes) -> tuple[dict[str, str], dict[str, str]]:
    if not data.endswith(b"\n") or b"\r" in data:
        raise VerificationError("SHA256SUMS manifest must be UTF-8 with final LF and no CR")
    try:
        lines = data.decode("utf-8").splitlines()
    except UnicodeDecodeError as error:
        raise VerificationError("SHA256SUMS manifest is not UTF-8") from error
    if not lines or lines[0] != "# Battle Pets deterministic release provenance v1":
        raise VerificationError("SHA256SUMS provenance header is not exact v1")
    if len(lines) != 1 + len(PROVENANCE_FIELDS) + 3:
        raise VerificationError("SHA256SUMS manifest has an unexpected line count")

    provenance: dict[str, str] = {}
    for expected_key, line in zip(PROVENANCE_FIELDS, lines[1 : 1 + len(PROVENANCE_FIELDS)]):
        match = re.fullmatch(r"# ([a-z0-9-]+): (.+)", line)
        if not match:
            raise VerificationError(f"invalid provenance line: {line!r}")
        key, value = match.groups()
        if key != expected_key or key in provenance:
            raise VerificationError(
                f"unexpected provenance field: expected {expected_key!r}, found {key!r}"
            )
        provenance[key] = value

    entries: dict[str, str] = {}
    entry_lines = lines[1 + len(PROVENANCE_FIELDS) :]
    for line in entry_lines:
        match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9_.-]+)", line)
        if not match:
            raise VerificationError(f"invalid SHA256SUMS line: {line!r}")
        checksum, name = match.groups()
        if name in entries:
            raise VerificationError(f"duplicate SHA256SUMS entry: {name}")
        entries[name] = checksum
    if [line.split("  ", 1)[1] for line in entry_lines] != sorted(entries):
        raise VerificationError("SHA256SUMS artifact entries are not sorted")
    return provenance, entries


def canonical_zip(payload: bytes) -> bytes:
    output = io.BytesIO()
    info = ZipInfo(ZIP_ENTRY, ZIP_TIME)
    info.compress_type = ZIP_DEFLATED
    info.create_system = 3
    info.external_attr = 0o100644 << 16
    info.extra = b""
    info.comment = b""
    with ZipFile(output, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
        archive.comment = b""
        archive.writestr(info, payload, compress_type=ZIP_DEFLATED, compresslevel=9)
    return output.getvalue()


def verify_zip(data: bytes, expected_payload: bytes) -> None:
    try:
        with ZipFile(io.BytesIO(data), "r") as archive:
            infos = archive.infolist()
            if len(infos) != 1:
                raise VerificationError(f"ZIP must contain exactly one entry, found {len(infos)}")
            info = infos[0]
            if info.filename != ZIP_ENTRY or info.is_dir():
                raise VerificationError(f"invalid ZIP entry: {info.filename!r}")
            if info.compress_type != ZIP_DEFLATED or info.date_time != ZIP_TIME:
                raise VerificationError("ZIP compression or timestamp is not canonical")
            if info.create_system != 3 or (info.external_attr >> 16) != 0o100644:
                raise VerificationError("ZIP platform or Unix mode is not canonical")
            if info.extra or info.comment or archive.comment or (info.flag_bits & 1):
                raise VerificationError("ZIP extras, comments, or encryption are forbidden")
            if archive.read(info) != expected_payload:
                raise VerificationError("ZIP payload differs from BATTLE_PETS.rbxlx")
    except VerificationError:
        raise
    except Exception as error:
        raise VerificationError(f"invalid ZIP: {error}") from error
    if data != canonical_zip(expected_payload):
        raise VerificationError("ZIP bytes differ from independent deflate-9 canonical encoding")


def expected_provenance(project_root: Path, qof: str, lock: dict, actual: dict[str, str]) -> dict[str, str]:
    platform_name = actual.get("rbxmk-platform", "")
    platform_lock = lock["platforms"].get(platform_name)
    if not isinstance(platform_lock, dict):
        raise VerificationError(f"manifest rbxmk platform is not pinned: {platform_name!r}")
    return {
        "qof": qof,
        "source-tree-sha256": source_tree_digest(project_root),
        "generator-sha256": file_digest(project_root / "tools/generate_rbxlx.py"),
        "runtime-inventory-sha256": file_digest(project_root / "tools/runtime_inventory.py"),
        "release-builder-sha256": file_digest(project_root / "tools/build_release.py"),
        "converter-sha256": file_digest(project_root / "tools/convert_place.rbxmk.lua"),
        "rbxmk-lock-sha256": file_digest(project_root / "tools/rbxmk.lock.json"),
        "rbxmk-version": lock["version"],
        "rbxmk-platform": platform_name,
        "rbxmk-sha256": platform_lock["sha256"],
        "descriptor": "none",
        "zip": ZIP_CONTRACT,
    }


def verify(project_root: Path, artifact_dir: Path, qof: str) -> None:
    xml_name, rbxl_name, zip_name, sums_name = release_names(qof)
    paths = {name: artifact_dir / name for name in (xml_name, rbxl_name, zip_name, sums_name)}
    missing = [name for name, path in paths.items() if path.is_symlink() or not path.is_file()]
    if missing:
        raise VerificationError("missing or non-regular release artifacts: " + ", ".join(missing))

    xml = paths[xml_name].read_bytes()
    rbxl = paths[rbxl_name].read_bytes()
    archive = paths[zip_name].read_bytes()
    try:
        root = ET.fromstring(xml)
    except ET.ParseError as error:
        raise VerificationError(f"BATTLE_PETS.rbxlx is invalid XML: {error}") from error
    if root.tag != "roblox" or root.attrib.get("version") != "4":
        raise VerificationError("BATTLE_PETS.rbxlx is not a Roblox XML v4 document")
    if len(rbxl) <= len(MAGIC) or rbxl[: len(MAGIC)] != MAGIC:
        raise VerificationError(f"invalid RBXL binary signature: {rbxl[:len(MAGIC)]!r}")
    verify_zip(archive, xml)

    subprocess.run(
        [sys.executable, str(project_root / "tests/verify_generated_place.py"), str(paths[xml_name])],
        cwd=project_root,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    provenance, entries = parse_manifest(paths[sums_name].read_bytes())
    expected_names = {xml_name, rbxl_name, zip_name}
    if set(entries) != expected_names:
        raise VerificationError(
            f"SHA256SUMS entries differ: expected {sorted(expected_names)}, found {sorted(entries)}"
        )
    for name in expected_names:
        actual_digest = digest(paths[name].read_bytes())
        if entries[name] != actual_digest:
            raise VerificationError(
                f"SHA-256 mismatch for {name}: expected {entries[name]}, found {actual_digest}"
            )

    lock = load_lock(project_root)
    expected = expected_provenance(project_root, qof, lock, provenance)
    if provenance != expected:
        differences = [
            f"{key}: expected {expected.get(key)!r}, found {provenance.get(key)!r}"
            for key in PROVENANCE_FIELDS
            if provenance.get(key) != expected.get(key)
        ]
        raise VerificationError("provenance mismatch: " + "; ".join(differences))

    print(f"PASS: QOF-{qof} RBXL signature is exact")
    print(f"PASS: QOF-{qof} ZIP is independently canonical and payload-exact")
    print(f"PASS: QOF-{qof} provenance and all 3 artifact hashes are independently verified")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qof", default="21")
    parser.add_argument("--project-root", type=Path, default=ROOT)
    parser.add_argument(
        "--artifact-dir",
        type=Path,
        help="directory containing release artifacts (default: project root)",
    )
    parser.add_argument("--fresh-build", action="store_true")
    parser.add_argument("--rbxmk", type=Path)
    args = parser.parse_args()
    if re.fullmatch(r"[0-9]+(?:-[0-9]+)?", args.qof) is None:
        parser.error("--qof must contain one number or a numeric range")
    if args.fresh_build and args.rbxmk is None:
        parser.error("--fresh-build requires --rbxmk")
    return args


def main() -> int:
    args = parse_args()
    project_root = args.project_root.resolve()
    artifact_dir = (args.artifact_dir or project_root).resolve()
    try:
        verify(project_root, artifact_dir, args.qof)
        if args.fresh_build:
            command = [
                sys.executable,
                str(project_root / "tools/build_release.py"),
                "--qof",
                args.qof,
                "--project-root",
                str(project_root),
                "--output-dir",
                str(artifact_dir),
                "--rbxmk",
                str(args.rbxmk.resolve()),
                "--check",
            ]
            subprocess.run(command, cwd=project_root, check=True)
            print(f"PASS: QOF-{args.qof} fresh deterministic build matches tracked bytes")
    except (OSError, VerificationError, subprocess.CalledProcessError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
