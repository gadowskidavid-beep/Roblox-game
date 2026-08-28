#!/usr/bin/env python3
"""Canonical, fail-closed inventory of Luau sources embedded in the place."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


class InventoryError(RuntimeError):
    """Raised when the supported source tree has an unexpected layout."""


@dataclass(frozen=True)
class RuntimeSource:
    path: Path
    name: str
    class_name: str


@dataclass(frozen=True)
class RuntimeInventory:
    shared: tuple[RuntimeSource, ...]
    vide_root: RuntimeSource
    vide_children: tuple[RuntimeSource, ...]
    modules: tuple[RuntimeSource, ...]
    upgrade_tree: tuple[RuntimeSource, ...]
    server_main: RuntimeSource
    services: tuple[RuntimeSource, ...]
    client_main: RuntimeSource
    controllers: tuple[RuntimeSource, ...]

    def all_sources(self) -> tuple[RuntimeSource, ...]:
        return (
            self.shared
            + (self.vide_root,)
            + self.vide_children
            + self.modules
            + self.upgrade_tree
            + (self.server_main,)
            + self.services
            + (self.client_main,)
            + self.controllers
        )


def _relative(path: Path, root: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return str(path)


def _require_directory(path: Path, root: Path) -> None:
    if path.is_symlink() or not path.is_dir():
        raise InventoryError(f"expected directory: {_relative(path, root)}")


def _require_regular_file(path: Path, root: Path) -> None:
    if path.is_symlink() or not path.is_file():
        raise InventoryError(f"expected regular file: {_relative(path, root)}")


def _entries(path: Path, root: Path) -> tuple[Path, ...]:
    _require_directory(path, root)
    entries = tuple(sorted(path.iterdir(), key=lambda item: item.name))
    for entry in entries:
        if entry.is_symlink():
            raise InventoryError(f"symbolic links are unsupported: {_relative(entry, root)}")
    return entries


def _expect_names(path: Path, expected: Iterable[str], root: Path) -> None:
    actual = {entry.name for entry in _entries(path, root)}
    wanted = set(expected)
    if actual != wanted:
        missing = sorted(wanted - actual)
        unexpected = sorted(actual - wanted)
        details = []
        if missing:
            details.append(f"missing={missing}")
        if unexpected:
            details.append(f"unexpected={unexpected}")
        raise InventoryError(
            f"unsupported layout in {_relative(path, root)}: {', '.join(details)}"
        )


def _lua_modules(path: Path, root: Path, *, ignored: Iterable[str] = ()) -> tuple[RuntimeSource, ...]:
    ignored_names = set(ignored)
    modules = []
    for entry in _entries(path, root):
        if entry.name in ignored_names:
            _require_regular_file(entry, root)
            continue
        if entry.suffix != ".lua" or not entry.stem or not entry.is_file():
            raise InventoryError(f"unsupported runtime entry: {_relative(entry, root)}")
        modules.append(RuntimeSource(entry, entry.stem, "ModuleScript"))
    if not modules:
        raise InventoryError(f"runtime surface is empty: {_relative(path, root)}")
    return tuple(modules)


def _validate_sources(inventory: RuntimeInventory, root: Path) -> None:
    paths: set[Path] = set()
    placements: set[tuple[str, str]] = set()
    for source in inventory.all_sources():
        _require_regular_file(source.path, root)
        if source.path in paths:
            raise InventoryError(f"runtime source appears twice: {_relative(source.path, root)}")
        paths.add(source.path)
        placement = (source.class_name, source.name)
        # Duplicate names across distinct Roblox parents are valid (notably Main),
        # so uniqueness is enforced within each surface while constructing it.
        if not source.name or "/" in source.name or "\\" in source.name:
            raise InventoryError(f"invalid Roblox script name: {source.name!r}")
        try:
            raw = source.path.read_bytes()
            text = raw.decode("utf-8")
        except UnicodeDecodeError as error:
            raise InventoryError(
                f"runtime source is not UTF-8: {_relative(source.path, root)}"
            ) from error
        if "\r" in text:
            raise InventoryError(
                f"runtime source must use LF line endings: {_relative(source.path, root)}"
            )
        if "]]>" in text:
            raise InventoryError(
                f"runtime source contains unsupported CDATA terminator: {_relative(source.path, root)}"
            )
        placements.add(placement)


def discover_runtime_inventory(project_root: Path) -> RuntimeInventory:
    """Discover every currently supported runtime source or reject the tree."""
    root = project_root.resolve()
    src = root / "src"
    _expect_names(src, {"ReplicatedStorage", "ServerScriptService", "StarterPlayer"}, root)

    replicated = src / "ReplicatedStorage"
    _expect_names(replicated, {"Shared", "modules", "packages"}, root)

    shared = _lua_modules(replicated / "Shared", root)

    packages = replicated / "packages"
    _expect_names(packages, {"vide"}, root)
    vide_dir = packages / "vide"
    vide_modules = _lua_modules(vide_dir, root)
    vide_init = tuple(module for module in vide_modules if module.path.name == "init.lua")
    if len(vide_init) != 1:
        raise InventoryError("src/ReplicatedStorage/packages/vide must contain exactly one init.lua")
    vide_root = RuntimeSource(vide_init[0].path, "vide", "ModuleScript")
    vide_children = tuple(module for module in vide_modules if module.path.name != "init.lua")

    modules_dir = replicated / "modules"
    _expect_names(modules_dir, {"formatNumber.lua", "upgradeTree"}, root)
    format_number_path = modules_dir / "formatNumber.lua"
    _require_regular_file(format_number_path, root)
    modules = (RuntimeSource(format_number_path, "formatNumber", "ModuleScript"),)

    upgrade_tree_dir = modules_dir / "upgradeTree"
    upgrade_tree = _lua_modules(upgrade_tree_dir, root, ignored={"sounds.model.json"})
    _require_regular_file(upgrade_tree_dir / "sounds.model.json", root)

    server = src / "ServerScriptService"
    _expect_names(server, {"Main.server.lua", "Services"}, root)
    server_main_path = server / "Main.server.lua"
    _require_regular_file(server_main_path, root)
    services = _lua_modules(server / "Services", root, ignored={".gitkeep"})

    starter_player = src / "StarterPlayer"
    _expect_names(starter_player, {"StarterPlayerScripts"}, root)
    starter_scripts = starter_player / "StarterPlayerScripts"
    entries = _entries(starter_scripts, root)
    main_paths = tuple(entry for entry in entries if entry.name == "Main.client.lua")
    if len(main_paths) != 1:
        raise InventoryError("StarterPlayerScripts must contain exactly one Main.client.lua")
    _require_regular_file(main_paths[0], root)
    controller_paths = tuple(entry for entry in entries if entry.name.endswith("Controller.lua"))
    unexpected = tuple(entry for entry in entries if entry not in main_paths + controller_paths)
    if unexpected:
        raise InventoryError(
            "unsupported runtime entries: "
            + ", ".join(_relative(path, root) for path in unexpected)
        )
    if not controller_paths:
        raise InventoryError("StarterPlayerScripts controller surface is empty")
    controllers = tuple(
        RuntimeSource(path, path.stem, "ModuleScript") for path in controller_paths
    )

    inventory = RuntimeInventory(
        shared=shared,
        vide_root=vide_root,
        vide_children=vide_children,
        modules=modules,
        upgrade_tree=upgrade_tree,
        server_main=RuntimeSource(server_main_path, "Main", "Script"),
        services=services,
        client_main=RuntimeSource(main_paths[0], "Main", "LocalScript"),
        controllers=controllers,
    )
    _validate_sources(inventory, root)
    return inventory


def read_runtime_source(source: RuntimeSource) -> str:
    """Read a previously validated UTF-8/LF source without newline conversion."""
    return source.path.read_bytes().decode("utf-8")
