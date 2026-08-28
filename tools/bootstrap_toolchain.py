#!/usr/bin/env python3
"""Install and verify the pinned Battle Pets Linux toolchain.

Archives are authenticated before any member is read. By default they are
fetched from the exact upstream release URLs in tools/toolchain.lock.json.
Pass --archive-dir for a network-free install from pre-downloaded archives.
"""

from __future__ import annotations

import argparse
import atexit
from contextlib import contextmanager
import ctypes
import errno
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import re
import secrets
import stat
import subprocess
import sys
import tempfile
from typing import Iterable, Iterator, Optional
import urllib.error
import urllib.parse
import urllib.request
from zipfile import BadZipFile, ZipFile
import zlib

ROOT = Path(__file__).resolve().parents[1]
LOCK_PATH = ROOT / "tools/toolchain.lock.json"
DEFAULT_INSTALL_DIR = ROOT / ".tools/qof22"
MAX_ARCHIVE_BYTES = 32 * 1024 * 1024
MAX_ENTRY_BYTES = 32 * 1024 * 1024
SHA256_PATTERN = re.compile(r"[0-9a-f]{64}")
TOOL_NAMES = ("rbxmk", "luau", "selene")
OFFICIAL_REPOSITORIES = {
    "rbxmk": ("Anaminus", "rbxmk"),
    "luau": ("luau-lang", "luau"),
    "selene": ("Kampfkarren", "selene"),
}
DOWNLOAD_REDIRECT_HOSTS = {
    "github.com",
    "objects.githubusercontent.com",
    "release-assets.githubusercontent.com",
}
RENAME_NOREPLACE = 1
DIRECTORY_FLAGS = (
    os.O_RDONLY
    | getattr(os, "O_CLOEXEC", 0)
    | getattr(os, "O_DIRECTORY", 0)
    | getattr(os, "O_NOFOLLOW", 0)
)
FILE_FLAGS = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)


class ToolchainError(RuntimeError):
    """Raised when the host, lock, archive, binary, or smoke test is invalid."""


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_descriptor(descriptor: int) -> str:
    os.lseek(descriptor, 0, os.SEEK_SET)
    digest = hashlib.sha256()
    while True:
        chunk = os.read(descriptor, 1024 * 1024)
        if not chunk:
            break
        digest.update(chunk)
    os.lseek(descriptor, 0, os.SEEK_SET)
    return digest.hexdigest()


def lexical_absolute(path: Path) -> Path:
    """Return an absolute lexical path without following any filesystem entry."""
    return Path(os.path.abspath(str(path.expanduser())))


def open_absolute_directory(path: Path, *, create: bool = False) -> int:
    """Open an absolute directory by walking from / with retained no-follow FDs."""
    absolute = lexical_absolute(path)
    descriptor = os.open("/", DIRECTORY_FLAGS)
    try:
        for part in absolute.parts[1:]:
            try:
                child = os.open(part, DIRECTORY_FLAGS, dir_fd=descriptor)
            except FileNotFoundError:
                if not create:
                    raise ToolchainError(f"directory does not exist: {absolute}")
                try:
                    os.mkdir(part, 0o700, dir_fd=descriptor)
                except FileExistsError:
                    pass
                try:
                    child = os.open(part, DIRECTORY_FLAGS, dir_fd=descriptor)
                except OSError as error:
                    raise ToolchainError(
                        f"directory path component is unsafe: {absolute} ({error})"
                    ) from error
            except OSError as error:
                raise ToolchainError(
                    f"directory path component is unsafe: {absolute} ({error})"
                ) from error
            os.close(descriptor)
            descriptor = child
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def open_absolute_regular_file(path: Path) -> int:
    """Open a regular file through a descriptor-anchored, no-follow parent walk."""
    absolute = lexical_absolute(path)
    if absolute.name in {"", ".", ".."}:
        raise ToolchainError(f"file path has no safe leaf: {absolute}")
    parent_descriptor = open_absolute_directory(absolute.parent)
    try:
        try:
            descriptor = os.open(absolute.name, FILE_FLAGS, dir_fd=parent_descriptor)
        except OSError as error:
            raise ToolchainError(f"file path is unsafe: {absolute} ({error})") from error
    finally:
        os.close(parent_descriptor)
    metadata = os.fstat(descriptor)
    if not stat.S_ISREG(metadata.st_mode):
        os.close(descriptor)
        raise ToolchainError(f"not a regular file: {absolute}")
    return descriptor


def close_descriptors(descriptors: Iterable[int]) -> None:
    first_error: Optional[OSError] = None
    for descriptor in descriptors:
        try:
            os.close(descriptor)
        except OSError as error:
            if first_error is None:
                first_error = error
    if first_error is not None:
        raise first_error


def sha256_file(path: Path) -> str:
    descriptor = open_absolute_regular_file(path)
    try:
        return sha256_descriptor(descriptor)
    finally:
        os.close(descriptor)


TRUSTED_ROOT_DESCRIPTOR = open_absolute_directory(ROOT)
try:
    TRUSTED_TOOLS_DESCRIPTOR = os.open(
        "tools", DIRECTORY_FLAGS, dir_fd=TRUSTED_ROOT_DESCRIPTOR
    )
except BaseException:
    os.close(TRUSTED_ROOT_DESCRIPTOR)
    raise


def _close_trust_anchors() -> None:
    close_descriptors((TRUSTED_TOOLS_DESCRIPTOR, TRUSTED_ROOT_DESCRIPTOR))


atexit.register(_close_trust_anchors)


def _exact_keys(value: object, keys: set[str], label: str) -> dict:
    if not isinstance(value, dict) or set(value) != keys:
        actual = sorted(value) if isinstance(value, dict) else type(value).__name__
        raise ToolchainError(f"{label} has unexpected fields: {actual}")
    return value


def _valid_text(value: object, label: str) -> str:
    if not isinstance(value, str) or not value or "\x00" in value:
        raise ToolchainError(f"{label} must be a non-empty string")
    return value


def _validate_release_urls(tool_name: str, tool: dict) -> None:
    owner, repository = OFFICIAL_REPOSITORIES[tool_name]
    tag = urllib.parse.quote(tool["tag"], safe=".-_")
    archive_name = urllib.parse.quote(tool["archive"]["name"], safe=".-_")
    expected_release = f"https://github.com/{owner}/{repository}/releases/tag/{tag}"
    expected_archive = (
        f"https://github.com/{owner}/{repository}/releases/download/{tag}/{archive_name}"
    )
    if tool["releaseUrl"] != expected_release or tool["archive"]["url"] != expected_archive:
        raise ToolchainError(f"{tool_name} release URLs do not match the approved upstream")


def load_lock() -> dict:
    try:
        descriptor = os.open("toolchain.lock.json", FILE_FLAGS, dir_fd=TRUSTED_TOOLS_DESCRIPTOR)
        try:
            metadata = os.fstat(descriptor)
            if not stat.S_ISREG(metadata.st_mode) or not 0 < metadata.st_size <= 1024 * 1024:
                raise ToolchainError("toolchain lock is not a bounded regular file")
            chunks = []
            remaining = metadata.st_size
            while remaining:
                chunk = os.read(descriptor, remaining)
                if not chunk:
                    raise ToolchainError("toolchain lock ended while reading")
                chunks.append(chunk)
                remaining -= len(chunk)
            if os.read(descriptor, 1):
                raise ToolchainError("toolchain lock changed while reading")
            raw = b"".join(chunks)
        finally:
            os.close(descriptor)
        lock = json.loads(raw.decode("utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ToolchainError(f"invalid toolchain lock: {error}") from error
    if not raw.endswith(b"\n") or b"\r" in raw:
        raise ToolchainError("toolchain lock must use UTF-8/LF and end with LF")
    _exact_keys(lock, {"schemaVersion", "platform", "python", "zlib", "tools"}, "lock")
    if lock["schemaVersion"] != 1 or lock["platform"] != "linux-amd64":
        raise ToolchainError("unsupported toolchain lock schema or platform")
    python_lock = _exact_keys(lock["python"], {"implementation", "version"}, "python lock")
    zlib_lock = _exact_keys(
        lock["zlib"], {"compileVersion", "runtimeVersion"}, "zlib lock"
    )
    for key, value in python_lock.items():
        _valid_text(value, f"python.{key}")
    for key, value in zlib_lock.items():
        _valid_text(value, f"zlib.{key}")

    tools = lock["tools"]
    if not isinstance(tools, dict) or tuple(tools) != TOOL_NAMES:
        raise ToolchainError(f"tools must appear in canonical order {TOOL_NAMES}")
    installed_names: set[str] = set()
    for tool_name in TOOL_NAMES:
        tool = _exact_keys(
            tools[tool_name],
            {"version", "tag", "commit", "releaseUrl", "archive", "entries", "install"},
            f"tool {tool_name}",
        )
        for key in ("version", "tag", "releaseUrl"):
            _valid_text(tool[key], f"{tool_name}.{key}")
        if re.fullmatch(r"[0-9a-f]{40}", str(tool["commit"])) is None:
            raise ToolchainError(f"{tool_name}.commit is not an exact Git commit")
        archive = _exact_keys(
            tool["archive"], {"name", "url", "size", "sha256"}, f"{tool_name} archive"
        )
        for key in ("name", "url"):
            _valid_text(archive[key], f"{tool_name}.archive.{key}")
        if Path(archive["name"]).name != archive["name"] or not archive["name"].endswith(".zip"):
            raise ToolchainError(f"{tool_name} archive name is unsafe")
        if not isinstance(archive["size"], int) or not 0 < archive["size"] <= MAX_ARCHIVE_BYTES:
            raise ToolchainError(f"{tool_name} archive size is invalid")
        if SHA256_PATTERN.fullmatch(str(archive["sha256"])) is None:
            raise ToolchainError(f"{tool_name} archive SHA-256 is invalid")
        entries = tool["entries"]
        if not isinstance(entries, dict) or not entries:
            raise ToolchainError(f"{tool_name} entries must be a non-empty object")
        for entry_name, digest in entries.items():
            if Path(entry_name).name != entry_name or not entry_name:
                raise ToolchainError(f"{tool_name} contains an unsafe archive entry")
            if SHA256_PATTERN.fullmatch(str(digest)) is None:
                raise ToolchainError(f"{tool_name}.{entry_name} SHA-256 is invalid")
        install_names = tool["install"]
        if (
            not isinstance(install_names, list)
            or not install_names
            or len(set(install_names)) != len(install_names)
            or any(name not in entries for name in install_names)
        ):
            raise ToolchainError(f"{tool_name} install list is invalid")
        overlap = installed_names.intersection(install_names)
        if overlap:
            raise ToolchainError(f"duplicate installed binary names: {sorted(overlap)}")
        installed_names.update(install_names)
        _validate_release_urls(tool_name, tool)
    if installed_names != {"rbxmk", "luau", "luau-compile", "selene"}:
        raise ToolchainError(f"unexpected installed binary set: {sorted(installed_names)}")
    lock["_lockSha256"] = sha256_bytes(raw)
    return lock


def verify_host(lock: dict) -> None:
    if sys.platform != "linux" or platform.machine().lower() not in {"x86_64", "amd64"}:
        raise ToolchainError(f"unsupported host: {sys.platform}/{platform.machine()}")
    expected_python = lock["python"]
    implementation = platform.python_implementation()
    version = platform.python_version()
    if implementation != expected_python["implementation"] or version != expected_python["version"]:
        raise ToolchainError(
            "external Python prerequisite mismatch: expected "
            f"{expected_python['implementation']} {expected_python['version']}, "
            f"found {implementation} {version}"
        )
    expected_zlib = lock["zlib"]
    if (
        zlib.ZLIB_VERSION != expected_zlib["compileVersion"]
        or zlib.ZLIB_RUNTIME_VERSION != expected_zlib["runtimeVersion"]
    ):
        raise ToolchainError(
            "external zlib prerequisite mismatch: expected "
            f"{expected_zlib['compileVersion']}/{expected_zlib['runtimeVersion']}, "
            f"found {zlib.ZLIB_VERSION}/{zlib.ZLIB_RUNTIME_VERSION}"
        )


def _read_local_archive(
    archive_directory_descriptor: int, name: str, expected_size: int
) -> bytes:
    try:
        descriptor = os.open(name, FILE_FLAGS, dir_fd=archive_directory_descriptor)
    except OSError as error:
        raise ToolchainError(f"archive path is unsafe: {name} ({error})") from error
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode):
            raise ToolchainError(f"archive is not a regular file: {name}")
        if metadata.st_size != expected_size or metadata.st_size > MAX_ARCHIVE_BYTES:
            raise ToolchainError(
                f"archive size mismatch: expected {expected_size}, found {metadata.st_size}"
            )
        chunks = []
        remaining = expected_size
        while remaining:
            chunk = os.read(descriptor, min(1024 * 1024, remaining))
            if not chunk:
                raise ToolchainError(f"archive ended early: {name}")
            chunks.append(chunk)
            remaining -= len(chunk)
        if os.read(descriptor, 1):
            raise ToolchainError(f"archive grew while reading: {name}")
        return b"".join(chunks)
    finally:
        os.close(descriptor)


def read_archive(tool_name: str, tool: dict, archive_directory_descriptor: Optional[int]) -> bytes:
    archive = tool["archive"]
    if archive_directory_descriptor is not None:
        data = _read_local_archive(
            archive_directory_descriptor, archive["name"], archive["size"]
        )
    else:
        request = urllib.request.Request(
            archive["url"], headers={"User-Agent": "Battle-Pets-QOF-22-Toolchain/1"}
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                final = urllib.parse.urlparse(response.geturl())
                if final.scheme != "https" or final.hostname not in DOWNLOAD_REDIRECT_HOSTS:
                    raise ToolchainError(f"{tool_name} redirected to an unapproved host")
                length = response.headers.get("Content-Length")
                if length is not None and int(length) != archive["size"]:
                    raise ToolchainError(f"{tool_name} response size differs from the lock")
                data = response.read(MAX_ARCHIVE_BYTES + 1)
        except (OSError, urllib.error.URLError, ValueError) as error:
            raise ToolchainError(f"failed to download {tool_name}: {error}") from error
    if len(data) != archive["size"]:
        raise ToolchainError(
            f"{tool_name} archive size mismatch: expected {archive['size']}, found {len(data)}"
        )
    digest = sha256_bytes(data)
    if digest != archive["sha256"]:
        raise ToolchainError(
            f"{tool_name} archive SHA-256 mismatch: expected {archive['sha256']}, found {digest}"
        )
    return data


def authenticated_entries(tool_name: str, tool: dict, data: bytes) -> dict[str, bytes]:
    expected = tool["entries"]
    try:
        with ZipFile(io.BytesIO(data), "r") as archive:
            infos = archive.infolist()
            names = [info.filename for info in infos]
            if len(names) != len(set(names)) or set(names) != set(expected):
                raise ToolchainError(
                    f"{tool_name} archive entries differ: expected {sorted(expected)}, "
                    f"found {sorted(names)}"
                )
            output = {}
            for info in infos:
                if info.is_dir() or Path(info.filename).name != info.filename:
                    raise ToolchainError(f"{tool_name} archive contains an unsafe member")
                if info.file_size <= 0 or info.file_size > MAX_ENTRY_BYTES:
                    raise ToolchainError(f"{tool_name}/{info.filename} has an invalid size")
                payload = archive.read(info)
                digest = sha256_bytes(payload)
                if digest != expected[info.filename]:
                    raise ToolchainError(
                        f"{tool_name}/{info.filename} SHA-256 mismatch: "
                        f"expected {expected[info.filename]}, found {digest}"
                    )
                output[info.filename] = payload
            return output
    except BadZipFile as error:
        raise ToolchainError(f"{tool_name} archive is not a valid ZIP") from error


def expected_binaries(lock: dict) -> dict[str, str]:
    output = {}
    for tool_name in TOOL_NAMES:
        tool = lock["tools"][tool_name]
        for name in tool["install"]:
            output[name] = tool["entries"][name]
    return output


def expected_state(lock: dict) -> dict:
    return {
        "schemaVersion": 1,
        "lockSha256": lock["_lockSha256"],
        "platform": lock["platform"],
    }


def _open_directory_at(parent_descriptor: int, name: str, label: str) -> int:
    try:
        return os.open(name, DIRECTORY_FLAGS, dir_fd=parent_descriptor)
    except FileNotFoundError:
        raise
    except OSError as error:
        raise ToolchainError(f"{label} is missing or unsafe ({error})") from error


def _read_small_regular_file(parent_descriptor: int, name: str, label: str) -> bytes:
    try:
        descriptor = os.open(name, FILE_FLAGS, dir_fd=parent_descriptor)
    except OSError as error:
        raise ToolchainError(f"{label} is missing or unsafe ({error})") from error
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > 64 * 1024:
            raise ToolchainError(f"{label} is not a small regular file")
        chunks = []
        remaining = metadata.st_size
        while remaining:
            chunk = os.read(descriptor, remaining)
            if not chunk:
                raise ToolchainError(f"{label} ended while reading")
            chunks.append(chunk)
            remaining -= len(chunk)
        if os.read(descriptor, 1):
            raise ToolchainError(f"{label} changed while reading")
        return b"".join(chunks)
    finally:
        os.close(descriptor)


def verify_install_descriptor(
    lock: dict, install_descriptor: int, display_path: Path
) -> dict[str, int]:
    if set(os.listdir(install_descriptor)) != {"bin", "toolchain-state.json"}:
        raise ToolchainError(
            f"unexpected toolchain root entries: {sorted(os.listdir(install_descriptor))}"
        )
    state_bytes = _read_small_regular_file(
        install_descriptor, "toolchain-state.json", "toolchain state"
    )
    try:
        state = json.loads(state_bytes.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ToolchainError(f"invalid toolchain state: {error}") from error
    if state != expected_state(lock):
        raise ToolchainError("toolchain state does not match the current lock")

    bin_descriptor = _open_directory_at(install_descriptor, "bin", "toolchain bin directory")
    binaries: dict[str, int] = {}
    try:
        wanted = expected_binaries(lock)
        actual = set(os.listdir(bin_descriptor))
        if actual != set(wanted):
            raise ToolchainError(f"unexpected toolchain binaries: {sorted(actual)}")
        for name, expected in wanted.items():
            try:
                descriptor = os.open(name, FILE_FLAGS, dir_fd=bin_descriptor)
            except OSError as error:
                raise ToolchainError(f"missing safe tool binary: {name} ({error})") from error
            try:
                metadata = os.fstat(descriptor)
                if not stat.S_ISREG(metadata.st_mode):
                    raise ToolchainError(f"tool binary is not regular: {name}")
                if stat.S_IMODE(metadata.st_mode) != 0o500:
                    raise ToolchainError(f"tool binary mode is not 0500: {name}")
                digest = sha256_descriptor(descriptor)
                if digest != expected:
                    raise ToolchainError(
                        f"{name} SHA-256 mismatch: expected {expected}, found {digest}"
                    )
                binaries[name] = descriptor
            except BaseException:
                os.close(descriptor)
                raise
        if stat.S_IMODE(os.fstat(install_descriptor).st_mode) != 0o500:
            raise ToolchainError(f"toolchain root mode is not 0500: {display_path}")
        if stat.S_IMODE(os.fstat(bin_descriptor).st_mode) != 0o500:
            raise ToolchainError("toolchain bin directory mode is not 0500")
        state_descriptor = os.open("toolchain-state.json", FILE_FLAGS, dir_fd=install_descriptor)
        try:
            if stat.S_IMODE(os.fstat(state_descriptor).st_mode) != 0o400:
                raise ToolchainError("toolchain state mode is not 0400")
        finally:
            os.close(state_descriptor)
        return binaries
    except BaseException:
        close_descriptors(binaries.values())
        raise
    finally:
        os.close(bin_descriptor)


def run_checked(
    executable_descriptor: int, arguments: list[str], cwd: Path
) -> subprocess.CompletedProcess[str]:
    executable = f"/proc/self/fd/{executable_descriptor}"
    result = subprocess.run(
        [executable, *arguments],
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        pass_fds=(executable_descriptor,),
    )
    if result.returncode != 0:
        raise ToolchainError(
            f"command failed ({result.returncode}): {arguments}\n"
            f"{result.stdout}{result.stderr}"
        )
    return result


def smoke_test(lock: dict, binaries: dict[str, int]) -> None:
    rbxmk_version = run_checked(binaries["rbxmk"], ["version"], ROOT).stdout.strip()
    if rbxmk_version != lock["tools"]["rbxmk"]["version"]:
        raise ToolchainError(f"rbxmk version mismatch: {rbxmk_version}")
    selene_version = run_checked(binaries["selene"], ["--version"], ROOT).stdout.strip()
    if selene_version != f"selene {lock['tools']['selene']['version']}":
        raise ToolchainError(f"selene version mismatch: {selene_version}")
    with tempfile.TemporaryDirectory(prefix="qof22-smoke-") as temporary:
        smoke_root = Path(temporary)
        run_source = smoke_root / "runner.luau"
        compile_source = smoke_root / "compile.luau"
        run_source.write_text('print("QOF22_LUAU_OK")\n', encoding="utf-8")
        compile_source.write_text(
            "local value: number = 1\nreturn value\n", encoding="utf-8"
        )
        output = run_checked(
            binaries["luau"], [str(run_source)], ROOT
        ).stdout.strip()
        if output != "QOF22_LUAU_OK":
            raise ToolchainError(f"Luau runner smoke output is invalid: {output!r}")
        run_checked(
            binaries["luau-compile"], ["--binary", str(compile_source)], ROOT
        )


def _write_new_file(parent_descriptor: int, name: str, payload: bytes, mode: int) -> None:
    flags = (
        os.O_WRONLY
        | os.O_CREAT
        | os.O_EXCL
        | getattr(os, "O_CLOEXEC", 0)
        | getattr(os, "O_NOFOLLOW", 0)
    )
    descriptor = os.open(name, flags, mode, dir_fd=parent_descriptor)
    try:
        view = memoryview(payload)
        while view:
            written = os.write(descriptor, view)
            view = view[written:]
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _freeze_install(lock: dict, install_descriptor: int) -> None:
    bin_descriptor = _open_directory_at(install_descriptor, "bin", "staged bin directory")
    try:
        for name in expected_binaries(lock):
            descriptor = os.open(name, FILE_FLAGS, dir_fd=bin_descriptor)
            try:
                os.fchmod(descriptor, 0o500)
            finally:
                os.close(descriptor)
        state_descriptor = os.open("toolchain-state.json", FILE_FLAGS, dir_fd=install_descriptor)
        try:
            os.fchmod(state_descriptor, 0o400)
        finally:
            os.close(state_descriptor)
        os.fchmod(bin_descriptor, 0o500)
        os.fchmod(install_descriptor, 0o500)
    finally:
        os.close(bin_descriptor)


def build_staged_install(
    lock: dict, staging_descriptor: int, archive_directory_descriptor: Optional[int]
) -> None:
    os.mkdir("install", 0o700, dir_fd=staging_descriptor)
    install_descriptor = _open_directory_at(
        staging_descriptor, "install", "staged install directory"
    )
    try:
        os.mkdir("bin", 0o700, dir_fd=install_descriptor)
        bin_descriptor = _open_directory_at(install_descriptor, "bin", "staged bin directory")
        try:
            for tool_name in TOOL_NAMES:
                tool = lock["tools"][tool_name]
                entries = authenticated_entries(
                    tool_name,
                    tool,
                    read_archive(tool_name, tool, archive_directory_descriptor),
                )
                for name in tool["install"]:
                    _write_new_file(bin_descriptor, name, entries[name], 0o700)
        finally:
            os.close(bin_descriptor)
        state_bytes = (
            json.dumps(expected_state(lock), indent=2, sort_keys=True) + "\n"
        ).encode("utf-8")
        _write_new_file(install_descriptor, "toolchain-state.json", state_bytes, 0o600)
        _freeze_install(lock, install_descriptor)
        binaries = verify_install_descriptor(lock, install_descriptor, Path("<staging>/install"))
        try:
            smoke_test(lock, binaries)
        finally:
            close_descriptors(binaries.values())
    finally:
        os.close(install_descriptor)


def rename_no_replace(
    source_directory_descriptor: int,
    source_name: str,
    target_directory_descriptor: int,
    target_name: str,
) -> None:
    libc = ctypes.CDLL(None, use_errno=True)
    renameat2 = getattr(libc, "renameat2", None)
    if renameat2 is None:
        raise ToolchainError("renameat2(RENAME_NOREPLACE) is unavailable on this Linux host")
    renameat2.argtypes = [
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_uint,
    ]
    renameat2.restype = ctypes.c_int
    result = renameat2(
        source_directory_descriptor,
        os.fsencode(source_name),
        target_directory_descriptor,
        os.fsencode(target_name),
        RENAME_NOREPLACE,
    )
    if result == 0:
        return
    error_number = ctypes.get_errno()
    if error_number == errno.EEXIST:
        raise ToolchainError(f"toolchain target appeared during promotion: {target_name}")
    raise ToolchainError(
        f"atomic no-replace promotion failed: {os.strerror(error_number)}"
    )


def _cleanup_generated_staging(
    parent_descriptor: int, staging_name: str, staging_descriptor: int
) -> None:
    try:
        install_descriptor = _open_directory_at(
            staging_descriptor, "install", "staged install directory"
        )
    except FileNotFoundError:
        install_descriptor = None
    if install_descriptor is not None:
        try:
            os.fchmod(install_descriptor, 0o700)
            try:
                bin_descriptor = _open_directory_at(
                    install_descriptor, "bin", "staged bin directory"
                )
            except FileNotFoundError:
                bin_descriptor = None
            if bin_descriptor is not None:
                try:
                    os.fchmod(bin_descriptor, 0o700)
                    for name in ("rbxmk", "luau", "luau-compile", "selene"):
                        try:
                            os.unlink(name, dir_fd=bin_descriptor)
                        except FileNotFoundError:
                            pass
                finally:
                    os.close(bin_descriptor)
                os.rmdir("bin", dir_fd=install_descriptor)
            try:
                os.unlink("toolchain-state.json", dir_fd=install_descriptor)
            except FileNotFoundError:
                pass
        finally:
            os.close(install_descriptor)
        os.rmdir("install", dir_fd=staging_descriptor)
    os.rmdir(staging_name, dir_fd=parent_descriptor)


@contextmanager
def staging_directory(parent_descriptor: int, prefix: str) -> Iterator[tuple[str, int]]:
    while True:
        name = f".{prefix}.stage-{secrets.token_hex(8)}"
        try:
            os.mkdir(name, 0o700, dir_fd=parent_descriptor)
            break
        except FileExistsError:
            continue
    try:
        descriptor = _open_directory_at(parent_descriptor, name, "private staging directory")
    except BaseException as open_error:
        try:
            os.rmdir(name, dir_fd=parent_descriptor)
        except OSError as cleanup_error:
            raise ToolchainError(
                "failed to open the created staging directory and could not remove it: "
                f"open={open_error}; cleanup={cleanup_error}"
            ) from open_error
        raise
    try:
        yield name, descriptor
    finally:
        try:
            _cleanup_generated_staging(parent_descriptor, name, descriptor)
        finally:
            os.close(descriptor)


@contextmanager
def install_lock(install_dir: Path, *, exclusive: bool) -> Iterator[int]:
    install_dir = lexical_absolute(install_dir)
    if install_dir.name in {"", ".", ".."}:
        raise ToolchainError(f"install path has no safe leaf: {install_dir}")
    parent_descriptor = open_absolute_directory(install_dir.parent, create=True)
    lock_name = f".{install_dir.name}.install.lock"
    flags = (
        os.O_CREAT
        | os.O_RDWR
        | getattr(os, "O_CLOEXEC", 0)
        | getattr(os, "O_NOFOLLOW", 0)
    )
    try:
        descriptor = os.open(lock_name, flags, 0o600, dir_fd=parent_descriptor)
        try:
            metadata = os.fstat(descriptor)
            if not stat.S_ISREG(metadata.st_mode):
                raise ToolchainError("install lock is not a regular file")
            fcntl.flock(descriptor, fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH)
            try:
                yield parent_descriptor
            finally:
                fcntl.flock(descriptor, fcntl.LOCK_UN)
        finally:
            os.close(descriptor)
    finally:
        os.close(parent_descriptor)


def install(
    lock: dict,
    parent_descriptor: int,
    install_name: str,
    archive_directory_descriptor: Optional[int],
) -> None:
    with staging_directory(parent_descriptor, install_name) as (_, staging_descriptor):
        build_staged_install(lock, staging_descriptor, archive_directory_descriptor)
        rename_no_replace(staging_descriptor, "install", parent_descriptor, install_name)


def parse_args(argv: Optional[Iterable[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--install-dir", type=Path, default=DEFAULT_INSTALL_DIR)
    parser.add_argument("--archive-dir", type=Path)
    parser.add_argument("--check", action="store_true", help="verify only; do not download or install")
    return parser.parse_args(argv)


def main(argv: Optional[Iterable[str]] = None) -> int:
    archive_directory_descriptor: Optional[int] = None
    try:
        args = parse_args(argv)
        lock = load_lock()
        verify_host(lock)
        install_dir = lexical_absolute(args.install_dir)
        archive_dir = lexical_absolute(args.archive_dir) if args.archive_dir else None
        if args.check and archive_dir is not None:
            raise ToolchainError("--archive-dir cannot be combined with --check")
        if archive_dir is not None:
            archive_directory_descriptor = open_absolute_directory(archive_dir)
        with install_lock(install_dir, exclusive=not args.check) as parent_descriptor:
            try:
                install_descriptor = _open_directory_at(
                    parent_descriptor, install_dir.name, "toolchain install"
                )
            except FileNotFoundError:
                if args.check:
                    raise ToolchainError(f"toolchain install does not exist: {install_dir}")
                install(
                    lock,
                    parent_descriptor,
                    install_dir.name,
                    archive_directory_descriptor,
                )
                install_descriptor = _open_directory_at(
                    parent_descriptor, install_dir.name, "toolchain install"
                )
            try:
                binaries = verify_install_descriptor(lock, install_descriptor, install_dir)
                try:
                    smoke_test(lock, binaries)
                finally:
                    close_descriptors(binaries.values())
            finally:
                os.close(install_descriptor)
    except (OSError, ToolchainError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    finally:
        if archive_directory_descriptor is not None:
            os.close(archive_directory_descriptor)
    print("PASS: pinned Battle Pets toolchain bytes are verified and executable")
    print(f"  lock: {LOCK_PATH.relative_to(ROOT)} sha256={lock['_lockSha256']}")
    print(f"  install: {install_dir}")
    print(f"  rbxmk: {lock['tools']['rbxmk']['version']}")
    print(
        "  luau/luau-compile: "
        f"{lock['tools']['luau']['version']} ({lock['tools']['luau']['commit']})"
    )
    print(f"  selene: {lock['tools']['selene']['version']}")
    print(f"  external python prerequisite: {platform.python_implementation()} {platform.python_version()}")
    print(f"  external zlib prerequisite: {zlib.ZLIB_VERSION}/{zlib.ZLIB_RUNTIME_VERSION}")
    print(f"  PATH prefix: {install_dir / 'bin'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
