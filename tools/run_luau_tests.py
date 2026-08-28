#!/usr/bin/env python3
"""Run the repository's existing specs with the pinned Luau CLI.

Official Luau sandboxes require() modules and expose a read-only _G, while the
legacy specs intentionally inject Roblox mocks through _G. This launcher keeps
the specs unchanged: it embeds project modules, gives them a mutable isolated
environment, and preserves the intended require-cache semantics.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
from typing import Iterable, Optional

import bootstrap_toolchain as toolchain

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LUAU = ROOT / ".tools/qof22/bin/luau"
SPEC_BLOCK = re.compile(r"local specFiles = \{(?P<body>.*?)\n\}", re.DOTALL)
QUOTED_PATH = re.compile(r'\"([^\"]+)\"')


class RunnerError(RuntimeError):
    """Raised when the runner contract or generated harness is invalid."""


def luau_literal(value: str) -> str:
    level = 0
    while True:
        closing = "]" + ("=" * level) + "]"
        if closing not in value:
            return "[" + ("=" * level) + "[" + value + closing
        level += 1


def discover_specs(runner_source: str) -> list[Path]:
    match = SPEC_BLOCK.search(runner_source)
    if match is None:
        raise RunnerError("tests/run_tests.lua has no canonical specFiles block")
    logical_paths = QUOTED_PATH.findall(match.group("body"))
    if not logical_paths or len(logical_paths) != len(set(logical_paths)):
        raise RunnerError("specFiles must be a non-empty duplicate-free list")
    paths = [ROOT / f"{logical}.lua" for logical in logical_paths]
    missing = [str(path.relative_to(ROOT)) for path in paths if not path.is_file()]
    if missing:
        raise RunnerError(f"listed specs are missing: {missing}")
    actual = set((ROOT / "tests").rglob("*.spec.lua"))
    listed = set(paths)
    if listed != actual:
        raise RunnerError(
            "specFiles differs from recursive tests/**/*.spec.lua: "
            f"missing={sorted(str(path.relative_to(ROOT)) for path in actual - listed)}, "
            f"unexpected={sorted(str(path.relative_to(ROOT)) for path in listed - actual)}"
        )
    return paths


def discover_modules() -> dict[str, str]:
    modules = {}
    for path in sorted((ROOT / "src").rglob("*.lua")):
        if path.is_symlink() or not path.is_file():
            raise RunnerError(f"runtime module is not a regular file: {path}")
        relative = path.relative_to(ROOT).as_posix()
        key = relative[:-4]
        try:
            source = path.read_bytes().decode("utf-8")
        except UnicodeDecodeError as error:
            raise RunnerError(f"runtime module is not UTF-8: {relative}") from error
        if "\r" in source:
            raise RunnerError(f"runtime module does not use LF line endings: {relative}")
        modules[key] = source
    if not modules:
        raise RunnerError("no runtime modules discovered")
    return modules


def build_harness(*, reverse: bool = False) -> str:
    runner_path = ROOT / "tests/run_tests.lua"
    runner_source = runner_path.read_text(encoding="utf-8")
    marker = "-- Export globals for spec files"
    if marker not in runner_source:
        raise RunnerError(f"{runner_path.relative_to(ROOT)} is missing the prelude marker")
    prelude = runner_source.split(marker, 1)[0]
    specs = discover_specs(runner_source)
    if reverse:
        specs.reverse()
    modules = discover_modules()

    lines = [prelude]
    lines.append("local __moduleSources = {\n")
    for key, source in modules.items():
        lines.append(f"\t[{json.dumps(key)}] = {luau_literal(source)},\n")
    lines.append("}\n")
    lines.append(
        r'''
local __baseEnvironment = getfenv()
local __mainThread = coroutine.running()

local function __copyLibrary(source)
	local output = {}
	for key, value in source do
		output[key] = value
	end
	return output
end

local function __newSpecEnvironment()
	local coroutineCompatibility = __copyLibrary(coroutine)
	coroutineCompatibility.running = function()
		local thread = coroutine.running()
		return thread, thread == __mainThread
	end
	local sharedEnvironment = setmetatable({
		coroutine = coroutineCompatibility,
		math = __copyLibrary(math),
		os = __copyLibrary(os),
	}, { __index = __baseEnvironment })
	sharedEnvironment._G = sharedEnvironment
	sharedEnvironment.describe = describe
	sharedEnvironment.it = it
	sharedEnvironment.expect = expect
	local moduleCache = {}
	local loading = {}

	local function normalizeModulePath(path)
		if type(path) ~= "string" then
			error("project require expected a string path", 2)
		end
		local normalized = string.gsub(path, "^%./", "")
		normalized = string.gsub(normalized, "%.lua$", "")
		return normalized
	end

	local function projectRequire(path)
		local key = normalizeModulePath(path)
		if moduleCache[key] ~= nil then
			return moduleCache[key]
		end
		if loading[key] then
			error("cyclic project require: " .. key, 2)
		end
		local source = __moduleSources[key]
		if source == nil then
			error("unknown project module: " .. key, 2)
		end
		local chunk, compileError = loadstring(source, "@" .. key .. ".lua")
		if chunk == nil then
			error(compileError, 2)
		end
		local moduleEnvironment = setmetatable({ _G = sharedEnvironment }, {
			__index = sharedEnvironment,
		})
		moduleEnvironment.require = sharedEnvironment.require
		setfenv(chunk, moduleEnvironment)
		loading[key] = true
		local ok, result = pcall(chunk)
		loading[key] = nil
		if not ok then
			error(result, 2)
		end
		if result == nil then
			result = true
		end
		moduleCache[key] = result
		return result
	end

	sharedEnvironment.require = projectRequire
	return sharedEnvironment
end
'''
    )
    lines.append("local __specs = {\n")
    for path in specs:
        relative = path.relative_to(ROOT).as_posix()
        source = path.read_text(encoding="utf-8")
        if "\r" in source:
            raise RunnerError(f"spec does not use LF line endings: {relative}")
        lines.append(
            "\t{ name = "
            + json.dumps(relative)
            + ", source = "
            + luau_literal(source)
            + " },\n"
        )
    lines.append("}\n")
    lines.append(
        r'''
for _, spec in ipairs(__specs) do
	print("\nRunning: " .. spec.name)
	local environment = __newSpecEnvironment()
	local chunk, compileError = loadstring(spec.source, "@" .. spec.name)
	if chunk == nil then
		print("  ERROR compiling spec: " .. tostring(compileError))
		totalFailed = totalFailed + 1
	else
		setfenv(chunk, environment)
		local ok, runError = pcall(chunk)
		if not ok then
			print("  ERROR loading spec: " .. tostring(runError))
			totalFailed = totalFailed + 1
		end
	end
end

print("\n========================================")
print(string.format("Results: %d passed, %d failed", totalPassed, totalFailed))
print("========================================\n")
if totalFailed > 0 then
	error("Tests failed")
end
'''
    )
    return "".join(lines)


def parse_args(argv: Optional[Iterable[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luau", type=Path, default=DEFAULT_LUAU)
    parser.add_argument("--keep-harness", type=Path)
    parser.add_argument(
        "--reverse", action="store_true", help="run the complete canonical spec list in reverse"
    )
    return parser.parse_args(argv)


def write_kept_harness(path: Path, harness: str) -> Path:
    output = toolchain.lexical_absolute(path)
    parent_descriptor = toolchain.open_absolute_directory(output.parent)
    flags = (
        os.O_WRONLY
        | os.O_CREAT
        | os.O_TRUNC
        | getattr(os, "O_CLOEXEC", 0)
        | getattr(os, "O_NOFOLLOW", 0)
    )
    try:
        descriptor = os.open(output.name, flags, 0o600, dir_fd=parent_descriptor)
        try:
            if not stat.S_ISREG(os.fstat(descriptor).st_mode):
                raise RunnerError(f"harness output is not a regular file: {output}")
            payload = harness.encode("utf-8")
            view = memoryview(payload)
            while view:
                written = os.write(descriptor, view)
                view = view[written:]
        finally:
            os.close(descriptor)
    finally:
        os.close(parent_descriptor)
    return output


def main(argv: Optional[Iterable[str]] = None) -> int:
    args = parse_args(argv)
    temporary: Optional[Path] = None
    luau_descriptor: Optional[int] = None
    try:
        luau = toolchain.lexical_absolute(args.luau)
        luau_descriptor = toolchain.open_absolute_regular_file(luau)
        metadata = os.fstat(luau_descriptor)
        if stat.S_IMODE(metadata.st_mode) & 0o111 == 0:
            raise RunnerError(f"Luau runner is not executable: {luau}")
        lock = toolchain.load_lock()
        expected_digest = lock["tools"]["luau"]["entries"]["luau"]
        actual_digest = toolchain.sha256_descriptor(luau_descriptor)
        if actual_digest != expected_digest:
            raise RunnerError(
                "Luau runner differs from the pinned lock: "
                f"expected {expected_digest}, found {actual_digest}"
            )
        harness = build_harness(reverse=args.reverse)
        if args.keep_harness:
            harness_path = write_kept_harness(args.keep_harness, harness)
        else:
            handle = tempfile.NamedTemporaryFile(
                mode="w",
                encoding="utf-8",
                dir=ROOT,
                prefix=".qof-luau-tests.",
                suffix=".luau",
                delete=False,
            )
            temporary = Path(handle.name)
            with handle:
                handle.write(harness)
            harness_path = temporary
        result = subprocess.run(
            [f"/proc/self/fd/{luau_descriptor}", str(harness_path)],
            cwd=ROOT,
            pass_fds=(luau_descriptor,),
        )
        if result.returncode != 0:
            return result.returncode
    except (OSError, RunnerError, toolchain.ToolchainError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    finally:
        try:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
        finally:
            if luau_descriptor is not None:
                os.close(luau_descriptor)
    return 0


if __name__ == "__main__":
    sys.exit(main())
