#!/usr/bin/env python3
"""Verify that the generated Battle Pets place embeds the QOF-02 runtime sources."""

from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PLACE = ROOT / "BATTLE_PETS.rbxlx"
EXPECTED_SOURCES = {
    "BalanceConfig": "src/ReplicatedStorage/Shared/BalanceConfig.lua",
    "Config": "src/ReplicatedStorage/Shared/Config.lua",
    "ShopData": "src/ReplicatedStorage/Shared/ShopData.lua",
    "upgradeTreeData": "src/ReplicatedStorage/modules/upgradeTree/upgradeTreeData.lua",
    "PetService": "src/ServerScriptService/Services/PetService.lua",
}
EXPECTED_SCRIPT_COUNTS = {"ModuleScript": 58, "Script": 1, "LocalScript": 1}


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
        if name is not None and source is not None:
            scripts.setdefault(name.text or "", []).append(source.text or "")

    for script_name, relative_path in EXPECTED_SOURCES.items():
        generated_sources = scripts.get(script_name, [])
        assert len(generated_sources) == 1, (
            f"expected exactly one {script_name}, found {len(generated_sources)}"
        )
        expected_source = (ROOT / relative_path).read_text()
        assert generated_sources[0] == expected_source, (
            f"generated source differs from {relative_path}"
        )

    actual_counts = {name: counts.get(name, 0) for name in EXPECTED_SCRIPT_COUNTS}
    assert actual_counts == EXPECTED_SCRIPT_COUNTS, (
        f"generated script counts changed: {actual_counts}"
    )
    print("PASS: generated place embeds all QOF-02 sources exactly once")
    print(f"PASS: generated script counts are {actual_counts}")


if __name__ == "__main__":
    main()
