#!/usr/bin/env python3
"""Build and verify deterministic Battle Pets RBXLX, RBXL, and ZIP artifacts."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from typing import Iterable, Optional
import xml.etree.ElementTree as ET
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parents[1]
TOOLS = Path(__file__).resolve().parent
MAGIC = b"<roblox!\x89\xff\r\n\x1a\n"
ZIP_ENTRY = "BATTLE_PETS.rbxlx"
ZIP_TIME = (1980, 1, 1, 0, 0, 0)


class ReleaseError(RuntimeError):
    """Raised when a release input or generated artifact is not exact."""


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def atomic_write(path: Path, data: bytes) -> None:
    if not path.parent.is_dir():
        raise ReleaseError(f"output directory does not exist: {path.parent}")
    temporary: Optional[Path] = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb", dir=path.parent, prefix=f".{path.name}.", suffix=".tmp", delete=False
        ) as handle:
            temporary = Path(handle.name)
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        temporary = None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def _fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def publish_release_set(output_dir: Path, artifacts: dict[str, bytes]) -> None:
    """Stage every artifact, publish manifest-last, and roll back handled failures."""
    staged: dict[str, Optional[Path]] = {}
    backups: dict[str, Optional[Path]] = {}
    committed: list[str] = []
    names = list(artifacts)
    if not names or not names[-1].endswith("_SHA256SUMS.txt"):
        raise ReleaseError("release provenance manifest must be published last")
    try:
        for name, data in artifacts.items():
            target = output_dir / name
            if target.exists() and (target.is_symlink() or not target.is_file()):
                raise ReleaseError(f"release target is not a regular file: {target}")
            with tempfile.NamedTemporaryFile(
                mode="wb", dir=output_dir, prefix=f".{name}.", suffix=".stage", delete=False
            ) as handle:
                stage = Path(handle.name)
                handle.write(data)
                handle.flush()
                os.fsync(handle.fileno())
            staged[name] = stage

        for name in artifacts:
            target = output_dir / name
            backup: Optional[Path] = None
            if target.exists():
                with tempfile.NamedTemporaryFile(
                    dir=output_dir, prefix=f".{name}.", suffix=".backup", delete=False
                ) as handle:
                    backup = Path(handle.name)
                backup.unlink()
                os.link(target, backup, follow_symlinks=False)
            backups[name] = backup

        _fsync_directory(output_dir)
        for name in artifacts:
            target = output_dir / name
            stage = staged[name]
            if stage is None:
                raise ReleaseError(f"missing staged release artifact: {name}")
            os.replace(stage, target)
            staged[name] = None
            committed.append(name)
        _fsync_directory(output_dir)
    except BaseException as publish_error:
        rollback_errors = []
        for name in reversed(committed):
            target = output_dir / name
            backup = backups.get(name)
            try:
                if backup is None:
                    target.unlink(missing_ok=True)
                else:
                    os.replace(backup, target)
                    backups[name] = None
            except OSError as rollback_error:
                rollback_errors.append(f"{name}: {rollback_error}")
        try:
            _fsync_directory(output_dir)
        except OSError as rollback_error:
            rollback_errors.append(f"directory fsync: {rollback_error}")
        if rollback_errors:
            raise ReleaseError(
                "release publication failed and rollback was incomplete: "
                + "; ".join(rollback_errors)
            ) from publish_error
        raise
    finally:
        for path in list(staged.values()) + list(backups.values()):
            if path is not None:
                path.unlink(missing_ok=True)


def run_checked(command: list[str], *, cwd: Path) -> subprocess.CompletedProcess[bytes]:
    result = subprocess.run(command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode != 0:
        stdout = result.stdout.decode("utf-8", "replace")
        stderr = result.stderr.decode("utf-8", "replace")
        raise ReleaseError(
            f"command failed ({result.returncode}): {' '.join(command)}\n{stdout}{stderr}"
        )
    return result


def platform_key() -> str:
    systems = {"linux": "linux", "darwin": "darwin", "win32": "windows"}
    machines = {
        "x86_64": "amd64",
        "amd64": "amd64",
        "i386": "386",
        "i686": "386",
        "x86": "386",
    }
    system = systems.get(sys.platform)
    machine = machines.get(platform.machine().lower())
    if not system or not machine:
        raise ReleaseError(f"unsupported rbxmk host: {sys.platform}/{platform.machine()}")
    return f"{system}-{machine}"


def load_lock(project_root: Path) -> dict:
    path = project_root / "tools/rbxmk.lock.json"
    try:
        lock = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ReleaseError(f"invalid rbxmk lock: {error}") from error
    if set(lock) != {"schemaVersion", "version", "descriptor", "platforms"}:
        raise ReleaseError("rbxmk lock has unexpected fields")
    if lock["schemaVersion"] != 1 or not isinstance(lock["version"], str):
        raise ReleaseError("unsupported rbxmk lock schema")
    if lock["descriptor"] is not None:
        raise ReleaseError("QOF-21 canonical build intentionally requires descriptor=null")
    if not isinstance(lock["platforms"], dict):
        raise ReleaseError("rbxmk lock platforms must be an object")
    return lock


def resolve_rbxmk(value: Optional[Path]) -> Path:
    candidate = str(value) if value is not None else os.environ.get("RBXMK")
    if not candidate:
        candidate = shutil.which("rbxmk")
    if not candidate:
        raise ReleaseError("rbxmk not found; pass --rbxmk or set RBXMK")
    path = Path(candidate).expanduser().resolve()
    if not path.is_file():
        raise ReleaseError(f"rbxmk is not a regular file: {path}")
    return path


def verify_rbxmk(rbxmk: Path, project_root: Path) -> tuple[str, str, str]:
    lock = load_lock(project_root)
    result = run_checked([str(rbxmk), "version"], cwd=project_root)
    version = result.stdout.decode("utf-8", "strict").strip()
    if version != lock["version"]:
        raise ReleaseError(f"rbxmk version mismatch: expected {lock['version']}, found {version}")
    key = platform_key()
    platform_lock = lock["platforms"].get(key)
    if not isinstance(platform_lock, dict) or set(platform_lock) != {"sha256"}:
        raise ReleaseError(f"rbxmk host is not pinned in lock: {key}")
    digest = sha256_file(rbxmk)
    if digest != platform_lock["sha256"]:
        raise ReleaseError(
            f"rbxmk SHA-256 mismatch for {key}: expected {platform_lock['sha256']}, found {digest}"
        )
    return version, digest, key


def source_tree_digest(project_root: Path) -> str:
    source_root = project_root / "src"
    if not source_root.is_dir():
        raise ReleaseError(f"missing source root: {source_root}")
    digest = hashlib.sha256()
    files = sorted(path for path in source_root.rglob("*") if path.is_file())
    if not files:
        raise ReleaseError("source tree is empty")
    for path in files:
        if path.is_symlink():
            raise ReleaseError(f"source tree contains a symbolic link: {path}")
        relative = path.relative_to(project_root).as_posix().encode("utf-8")
        data = path.read_bytes()
        digest.update(len(relative).to_bytes(4, "big"))
        digest.update(relative)
        digest.update(len(data).to_bytes(8, "big"))
        digest.update(data)
    return digest.hexdigest()


def generate_xml(project_root: Path, output: Path) -> bytes:
    generator = project_root / "tools/generate_rbxlx.py"
    run_checked(
        [
            sys.executable,
            str(generator),
            "--project-root",
            str(project_root),
            "--output",
            str(output),
        ],
        cwd=project_root,
    )
    return output.read_bytes()


def verify_place(project_root: Path, place: Path) -> None:
    run_checked(
        [sys.executable, str(project_root / "tests/verify_generated_place.py"), str(place)],
        cwd=project_root,
    )


def canonical_place_tree(data: bytes) -> tuple:
    """Return a referent-normalized semantic tree for complete-place comparison."""
    try:
        root = ET.fromstring(data)
    except ET.ParseError as error:
        raise ReleaseError(f"invalid Roblox XML during semantic comparison: {error}") from error
    if root.tag != "roblox" or root.attrib.get("version") != "4":
        raise ReleaseError("semantic comparison requires a Roblox XML v4 document")

    referent_paths: dict[str, tuple[int, ...]] = {}

    def index_items(parent: ET.Element, parent_path: tuple[int, ...]) -> None:
        item_index = 0
        for child in parent:
            if child.tag != "Item":
                continue
            path = parent_path + (item_index,)
            item_index += 1
            referent = child.attrib.get("referent")
            if referent:
                if referent in referent_paths:
                    raise ReleaseError(f"duplicate Roblox referent: {referent}")
                referent_paths[referent] = path
            index_items(child, path)

    index_items(root, ())

    def canonical_value(element: ET.Element) -> tuple:
        attributes = tuple(sorted(element.attrib.items()))
        if element.attrib.get("name") == "Source" and element.tag in {"ProtectedString", "string"}:
            value = element.text or ""
            try:
                source_bytes = value.encode("latin-1")
            except UnicodeEncodeError:
                source_bytes = value.encode("utf-8")
            return "Source", (("name", "Source"),), source_bytes, ()
        if element.tag in {"Content", "string"}:
            children = tuple(element)
            if len(children) > 1:
                raise ReleaseError(
                    f"unsupported multi-value Roblox {element.tag} property: {element.attrib!r}"
                )
            if children and children[0].tag not in {"null", "url"}:
                raise ReleaseError(
                    f"unsupported Roblox Content child: {children[0].tag}"
                )
            value = (children[0].text or "") if children and children[0].tag == "url" else (element.text or "")
            return "TextValue", attributes, value, ()
        if element.tag == "Ref":
            value = (element.text or "").strip()
            if value not in ("", "null", "nil"):
                if value not in referent_paths:
                    raise ReleaseError(f"dangling Roblox Ref property: {value}")
                value = "/".join(str(index) for index in referent_paths[value])
            text: object = value
        elif element.tag == "ProtectedString":
            value = element.text or ""
            try:
                text = value.encode("latin-1")
            except UnicodeEncodeError:
                text = value.encode("utf-8")
        else:
            text = (element.text or "").strip() if len(element) == 0 else ""
            float32_tags = {
                "float", "X", "Y", "Z", "R", "G", "B", "S", "O",
                "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22",
            }
            if text and element.tag in float32_tags:
                try:
                    text = struct.pack(">f", float(text))
                except (OverflowError, ValueError):
                    pass
            elif text and element.tag == "double":
                try:
                    text = struct.pack(">d", float(text))
                except (OverflowError, ValueError):
                    pass
        children = tuple(canonical_value(child) for child in element if child.tag != "Item")
        return element.tag, attributes, text, children

    def is_materialized_default(value: tuple) -> bool:
        tag, attributes, text, children = value
        property_name = dict(attributes).get("name")
        return (
            property_name == "Transparency"
            and tag == "float"
            and text == struct.pack(">f", 0.0)
            and children == ()
        )

    def canonical_item(item: ET.Element) -> tuple:
        properties_node = item.find("Properties")
        properties = ()
        if properties_node is not None:
            canonical_properties = (
                canonical_value(property_node) for property_node in properties_node
            )
            properties = tuple(
                sorted(
                    (value for value in canonical_properties if not is_materialized_default(value)),
                    key=repr,
                )
            )
        children = tuple(
            sorted(
                (canonical_item(child) for child in item if child.tag == "Item"),
                key=repr,
            )
        )
        return item.attrib.get("class", ""), properties, children

    metadata = tuple(
        sorted(
            (canonical_value(child) for child in root if child.tag != "Item"),
            key=repr,
        )
    )
    items = tuple(
        sorted((canonical_item(child) for child in root if child.tag == "Item"), key=repr)
    )
    return metadata, items


def verify_complete_roundtrip(original: bytes, roundtrip: bytes) -> None:
    original_tree = canonical_place_tree(original)
    roundtrip_tree = canonical_place_tree(roundtrip)
    if original_tree != roundtrip_tree:
        def first_difference(left: object, right: object, path: str = "root") -> str:
            if type(left) is not type(right):
                return f"{path}: type {type(left).__name__} != {type(right).__name__}"
            if isinstance(left, tuple) and isinstance(right, tuple):
                if len(left) != len(right):
                    left_only = [value for value in left if value not in right]
                    right_only = [value for value in right if value not in left]
                    return (
                        f"{path}: tuple length {len(left)} != {len(right)}; "
                        f"left-only={repr(left_only)[:800]}; right-only={repr(right_only)[:800]}"
                    )
                for index, (left_value, right_value) in enumerate(zip(left, right)):
                    if left_value != right_value:
                        return first_difference(left_value, right_value, f"{path}[{index}]")
            return f"{path}: {left!r} != {right!r}"

        original_digest = sha256_bytes(repr(original_tree).encode("utf-8"))
        roundtrip_digest = sha256_bytes(repr(roundtrip_tree).encode("utf-8"))
        raise ReleaseError(
            "RBXL roundtrip changed the complete place semantic tree: "
            f"original={original_digest}, roundtrip={roundtrip_digest}; "
            + first_difference(original_tree, roundtrip_tree)
        )


def convert_place(
    rbxmk: Path,
    project_root: Path,
    temporary_root: Path,
    source: Path,
    output: Path,
) -> bytes:
    converter = project_root / "tools/convert_place.rbxmk.lua"
    run_checked(
        [
            str(rbxmk),
            "run",
            "--include-root",
            str(project_root),
            "--include-root",
            str(temporary_root),
            str(converter.relative_to(project_root)),
            str(source),
            str(output),
        ],
        cwd=project_root,
    )
    if not output.is_file():
        raise ReleaseError(f"rbxmk did not create {output}")
    return output.read_bytes()


def deterministic_zip(payload: bytes) -> bytes:
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
    with ZipFile(io.BytesIO(data), "r") as archive:
        infos = archive.infolist()
        if len(infos) != 1:
            raise ReleaseError(f"ZIP must have exactly one entry, found {len(infos)}")
        info = infos[0]
        if info.filename != ZIP_ENTRY or info.is_dir():
            raise ReleaseError(f"invalid ZIP entry: {info.filename!r}")
        if info.compress_type != ZIP_DEFLATED:
            raise ReleaseError("ZIP entry must use DEFLATE")
        if info.date_time != ZIP_TIME or info.create_system != 3:
            raise ReleaseError("ZIP entry metadata is not canonical")
        if (info.external_attr >> 16) != 0o100644 or info.extra or info.comment:
            raise ReleaseError("ZIP permissions, extra fields, or comment are not canonical")
        if archive.comment:
            raise ReleaseError("ZIP archive comment must be empty")
        payload = archive.read(info)
        if payload != expected_payload:
            raise ReleaseError("ZIP payload differs from BATTLE_PETS.rbxlx")


def release_names(qof: str) -> tuple[str, str, str, str]:
    prefix = f"BATTLE_PETS_QOF-{qof}"
    return (
        "BATTLE_PETS.rbxlx",
        f"{prefix}_TEST.rbxl",
        f"{prefix}_RBXLX.zip",
        f"{prefix}_SHA256SUMS.txt",
    )


def provenance(
    qof: str,
    artifacts: dict[str, bytes],
    project_root: Path,
    version: str,
    executable_hash: str,
    host_key: str,
) -> bytes:
    lines = [
        "# Battle Pets deterministic release provenance v1",
        f"# qof: {qof}",
        f"# source-tree-sha256: {source_tree_digest(project_root)}",
        f"# generator-sha256: {sha256_file(project_root / 'tools/generate_rbxlx.py')}",
        f"# runtime-inventory-sha256: {sha256_file(project_root / 'tools/runtime_inventory.py')}",
        f"# release-builder-sha256: {sha256_file(project_root / 'tools/build_release.py')}",
        f"# converter-sha256: {sha256_file(project_root / 'tools/convert_place.rbxmk.lua')}",
        f"# rbxmk-lock-sha256: {sha256_file(project_root / 'tools/rbxmk.lock.json')}",
        f"# rbxmk-version: {version}",
        f"# rbxmk-platform: {host_key}",
        f"# rbxmk-sha256: {executable_hash}",
        "# descriptor: none",
        "# zip: deflate-9; timestamp=1980-01-01T00:00:00; unix-mode=100644",
    ]
    for name in sorted(artifacts):
        lines.append(f"{sha256_bytes(artifacts[name])}  {name}")
    return ("\n".join(lines) + "\n").encode("utf-8")


def build_release(project_root: Path, qof: str, rbxmk: Path) -> dict[str, bytes]:
    version, executable_hash, host_key = verify_rbxmk(rbxmk, project_root)
    xml_name, rbxl_name, zip_name, sums_name = release_names(qof)
    with tempfile.TemporaryDirectory(prefix="battle-pets-release-") as temporary:
        temp = Path(temporary)
        first = temp / "first"
        second = temp / "second"
        first.mkdir()
        second.mkdir()

        xml_first = generate_xml(project_root, first / xml_name)
        xml_second = generate_xml(project_root, second / xml_name)
        if xml_first != xml_second:
            raise ReleaseError("two clean generator runs produced different RBXLX bytes")
        verify_place(project_root, first / xml_name)

        rbxl_first = convert_place(
            rbxmk, project_root, temp, first / xml_name, first / rbxl_name
        )
        rbxl_second = convert_place(
            rbxmk, project_root, temp, second / xml_name, second / rbxl_name
        )
        if rbxl_first != rbxl_second:
            raise ReleaseError("two clean rbxmk runs produced different RBXL bytes")
        if len(rbxl_first) <= len(MAGIC) or rbxl_first[: len(MAGIC)] != MAGIC:
            raise ReleaseError(f"RBXL has invalid binary signature: {rbxl_first[:len(MAGIC)]!r}")

        roundtrip = first / "ROUNDTRIP.rbxlx"
        roundtrip_xml = convert_place(rbxmk, project_root, temp, first / rbxl_name, roundtrip)
        verify_place(project_root, roundtrip)
        verify_complete_roundtrip(xml_first, roundtrip_xml)
        roundtrip_binary = first / "ROUNDTRIP.rbxl"
        rebuilt_rbxl = convert_place(
            rbxmk, project_root, temp, roundtrip, roundtrip_binary
        )
        if rebuilt_rbxl != rbxl_first:
            raise ReleaseError("RBXL -> RBXLX -> RBXL roundtrip changed binary bytes")

        zip_first = deterministic_zip(xml_first)
        zip_second = deterministic_zip(xml_second)
        if zip_first != zip_second:
            raise ReleaseError("two clean ZIP builds produced different bytes")
        verify_zip(zip_first, xml_first)

        artifacts = {
            xml_name: xml_first,
            rbxl_name: rbxl_first,
            zip_name: zip_first,
        }
        artifacts[sums_name] = provenance(
            qof, artifacts, project_root, version, executable_hash, host_key
        )
        return artifacts


def publish_or_check(output_dir: Path, artifacts: dict[str, bytes], check: bool) -> None:
    if not output_dir.is_dir():
        raise ReleaseError(f"output directory does not exist: {output_dir}")
    failures = []
    if check:
        for name, expected in artifacts.items():
            target = output_dir / name
            if not target.is_file():
                failures.append(f"missing: {name}")
            elif target.read_bytes() != expected:
                failures.append(f"stale: {name}")
    else:
        publish_release_set(output_dir, artifacts)
    if failures:
        raise ReleaseError("release drift detected: " + ", ".join(failures))


def parse_args(argv: Optional[Iterable[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qof", default="21", help="artifact QOF suffix, e.g. 21 or 20-21")
    parser.add_argument("--project-root", type=Path, default=ROOT)
    parser.add_argument(
        "--output-dir",
        type=Path,
        help="artifact directory (default: project root)",
    )
    parser.add_argument("--rbxmk", type=Path)
    parser.add_argument(
        "--check", action="store_true", help="verify tracked artifacts without modifying them"
    )
    args = parser.parse_args(argv)
    if re.fullmatch(r"[0-9]+(?:-[0-9]+)?", args.qof) is None:
        parser.error("--qof must contain one number or a numeric range")
    return args


def main(argv: Optional[Iterable[str]] = None) -> int:
    args = parse_args(argv)
    project_root = args.project_root.resolve()
    output_dir = (args.output_dir or project_root).resolve()
    try:
        rbxmk = resolve_rbxmk(args.rbxmk)
        artifacts = build_release(project_root, args.qof, rbxmk)
        publish_or_check(output_dir, artifacts, args.check)
    except (OSError, ReleaseError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    mode = "verified" if args.check else "built"
    print(f"PASS: QOF-{args.qof} release {mode} deterministically")
    for name, data in artifacts.items():
        print(f"  {name}: {len(data)} bytes, sha256={sha256_bytes(data)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
