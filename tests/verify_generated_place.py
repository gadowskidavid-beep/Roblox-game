#!/usr/bin/env python3
"""Verify that the generated Battle Pets place embeds every QOF-11 runtime source."""

from collections import Counter
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PLACE = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / "BATTLE_PETS.rbxlx"
EXPECTED_SOURCES = {
    "BalanceConfig": "src/ReplicatedStorage/Shared/BalanceConfig.lua",
    "Config": "src/ReplicatedStorage/Shared/Config.lua",
    "ShopData": "src/ReplicatedStorage/Shared/ShopData.lua",
    "upgradeTreeData": "src/ReplicatedStorage/modules/upgradeTree/upgradeTreeData.lua",
    "upgradeTreeSettings": "src/ReplicatedStorage/modules/upgradeTree/upgradeTreeSettings.lua",
    "PetHatchMath": "src/ReplicatedStorage/Shared/PetHatchMath.lua",
    "PetVariantMath": "src/ReplicatedStorage/Shared/PetVariantMath.lua",
    "PetVariantPresentation": "src/ReplicatedStorage/Shared/PetVariantPresentation.lua",
    "HatchCinematicPolicy": "src/ReplicatedStorage/Shared/HatchCinematicPolicy.lua",
    "PetService": "src/ServerScriptService/Services/PetService.lua",
    "CurrencyService": "src/ServerScriptService/Services/CurrencyService.lua",
    "EggService": "src/ServerScriptService/Services/EggService.lua",
    "ShopService": "src/ServerScriptService/Services/ShopService.lua",
    "UpgradeTreeService": "src/ServerScriptService/Services/UpgradeTreeService.lua",
    "DataSchema": "src/ServerScriptService/Services/DataSchema.lua",
    "DataService": "src/ServerScriptService/Services/DataService.lua",
    "UIController": "src/StarterPlayer/StarterPlayerScripts/UIController.lua",
    "EffectsController": "src/StarterPlayer/StarterPlayerScripts/EffectsController.lua",
    "PetController": "src/StarterPlayer/StarterPlayerScripts/PetController.lua",
    "UpgradeTreeController": "src/StarterPlayer/StarterPlayerScripts/UpgradeTreeController.lua",
}
EXPECTED_SCRIPT_COUNTS = {"ModuleScript": 62, "Script": 1, "LocalScript": 1}
EXPECTED_DUPLICATE_NAME_SOURCES = {
    "Main": [
        "src/ServerScriptService/Main.server.lua",
        "src/StarterPlayer/StarterPlayerScripts/Main.client.lua",
    ],
}


def all_expected_runtime_paths() -> list[Path]:
    """Mirror the generator's runtime source surfaces and exclude tests/tools."""
    paths = [
        *sorted((ROOT / "src/ReplicatedStorage/Shared").glob("*.lua")),
        *sorted((ROOT / "src/ReplicatedStorage/packages/vide").glob("*.lua")),
        ROOT / "src/ReplicatedStorage/modules/formatNumber.lua",
        *sorted((ROOT / "src/ReplicatedStorage/modules/upgradeTree").glob("*.lua")),
        ROOT / "src/ServerScriptService/Main.server.lua",
        *sorted((ROOT / "src/ServerScriptService/Services").glob("*.lua")),
        ROOT / "src/StarterPlayer/StarterPlayerScripts/Main.client.lua",
        *sorted((ROOT / "src/StarterPlayer/StarterPlayerScripts").glob("*Controller.lua")),
    ]
    assert len(paths) == EXPECTED_SCRIPT_COUNTS["ModuleScript"] + 2, (
        f"expected 64 runtime source paths, found {len(paths)}"
    )
    return paths


def serialized_source_bytes(source: str) -> bytes:
    """Recover exact Source bytes from XML or rbxmk's binary-string projection."""
    try:
        # rbxmk 0.9.1 projects RBXL ProtectedString bytes as Latin-1 code points
        # when writing an XML roundtrip. Re-encoding restores the original bytes.
        return source.encode("latin-1")
    except UnicodeEncodeError:
        return source.encode("utf-8")


def main() -> None:
    root = ET.parse(PLACE).getroot()
    scripts: dict[str, list[str]] = {}
    counts: dict[str, int] = {}

    for item in root.findall(".//Item"):
        class_name = item.attrib.get("class", "")
        counts[class_name] = counts.get(class_name, 0) + 1
        properties = item.find("Properties")
        if properties is None:
            continue
        name = properties.find("./string[@name='Name']")
        source = properties.find("./ProtectedString[@name='Source']")
        if source is None:
            source = properties.find("./string[@name='Source']")
        if name is not None and source is not None:
            scripts.setdefault(name.text or "", []).append(source.text or "")

    for script_name, relative_path in EXPECTED_SOURCES.items():
        generated_sources = scripts.get(script_name, [])
        assert len(generated_sources) == 1, (
            f"expected exactly one {script_name}, found {len(generated_sources)}"
        )
        expected_source = (ROOT / relative_path).read_bytes()
        assert serialized_source_bytes(generated_sources[0]) == expected_source, (
            f"generated source bytes differ from {relative_path}"
        )

    for script_name, relative_paths in EXPECTED_DUPLICATE_NAME_SOURCES.items():
        generated_sources = scripts.get(script_name, [])
        assert len(generated_sources) == len(relative_paths), (
            f"expected {len(relative_paths)} {script_name} scripts, found {len(generated_sources)}"
        )
        for relative_path in relative_paths:
            expected_source = (ROOT / relative_path).read_bytes()
            assert sum(
                serialized_source_bytes(source) == expected_source
                for source in generated_sources
            ) == 1, (
                f"generated source differs from or duplicates {relative_path}"
            )

    expected_source_counts = Counter(
        path.read_bytes() for path in all_expected_runtime_paths()
    )
    generated_source_counts = Counter(
        serialized_source_bytes(source)
        for source_list in scripts.values()
        for source in source_list
    )
    assert generated_source_counts == expected_source_counts, (
        "generated place does not have byte-exact one-to-one runtime source parity"
    )

    actual_counts = {name: counts.get(name, 0) for name in EXPECTED_SCRIPT_COUNTS}
    assert actual_counts == EXPECTED_SCRIPT_COUNTS, (
        f"generated script counts changed: {actual_counts}"
    )
    print("PASS: generated place embeds every QOF-11 runtime source exactly once")
    print("PASS: all 64 generated script sources have byte-exact source parity")
    print(f"PASS: generated script counts are {actual_counts}")


if __name__ == "__main__":
    main()
