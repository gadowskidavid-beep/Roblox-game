#!/usr/bin/env python3
"""
Generate BATTLE_PETS.rbxlx place file from the src/ tree.

Produces a valid Roblox Studio place file (version 4) with the correct XML
structure so that scripts execute and GUI appears. Follows the exact format
that Roblox Studio requires:
- Proper xmlns attributes on root element
- Meta ExplicitAutoJoints
- External null/nil declarations
- Scripts with Disabled=false and LinkedSource null
- CFrame for positions (not Vector3 Position)
- Lowercase "size" property name
- Color3uint8 format for colors
"""

import argparse
import json
import os
from pathlib import Path
import sys
import tempfile
import xml.etree.ElementTree as ET
from typing import Optional

from runtime_inventory import (
    InventoryError,
    RuntimeInventory,
    RuntimeSource,
    discover_runtime_inventory,
    read_runtime_source,
)

DEFAULT_PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT_NAME = "BATTLE_PETS.rbxlx"

# Global referent counter; reset explicitly for every generated document.
_ref_counter = [0]


def next_ref():
    """Generate a unique referent ID."""
    _ref_counter[0] += 1
    return f"RBX{_ref_counter[0]:08X}"


def source_xml(source: RuntimeSource, *, lvl: int, children_str: str = "") -> str:
    """Serialize one source discovered by the canonical runtime inventory."""
    return make_script_xml(
        source.class_name,
        source.name,
        read_runtime_source(source),
        lvl=lvl,
        children_str=children_str,
    )


def rgb_to_uint8(r, g, b):
    """Convert RGB (0-255) to Color3uint8 integer format."""
    # Color3uint8 is stored as: (255 << 24) | (R << 16) | (G << 8) | B
    # Actually it's just a packed ARGB with A=255
    return str((255 << 24) | (r << 16) | (g << 8) | b)


def indent(level):
    """Return indentation string."""
    return "\t" * level


def xml_escape(text):
    """Escape special XML characters in text content."""
    text = text.replace("&", "&amp;")
    text = text.replace("<", "&lt;")
    text = text.replace(">", "&gt;")
    return text


def make_cframe_props(x, y, z):
    """Generate CFrame property XML lines (identity rotation)."""
    return (
        f"<CoordinateFrame name=\"CFrame\">\n"
        f"\t\t\t\t\t<X>{x}</X><Y>{y}</Y><Z>{z}</Z>\n"
        f"\t\t\t\t\t<R00>1</R00><R01>0</R01><R02>0</R02>\n"
        f"\t\t\t\t\t<R10>0</R10><R11>1</R11><R12>0</R12>\n"
        f"\t\t\t\t\t<R20>0</R20><R21>0</R21><R22>1</R22>\n"
        f"\t\t\t\t</CoordinateFrame>"
    )


def make_vector3_size(x, y, z):
    """Generate size property XML."""
    return f'<Vector3 name="size">\n\t\t\t\t\t<X>{x}</X><Y>{y}</Y><Z>{z}</Z>\n\t\t\t\t</Vector3>'


def make_part_xml(name, class_name, x, y, z, sx, sy, sz, r, g, b, material=256,
                  transparency=0, shape_token=None, extra_props="", children="",
                  lvl=2):
    """Generate a complete Part/WedgePart/SpawnLocation Item XML block."""
    ref = next_ref()
    ind = indent(lvl)
    ind1 = indent(lvl + 1)
    ind2 = indent(lvl + 2)

    # Build properties
    props_lines = []
    props_lines.append(f'{ind2}<string name="Name">{xml_escape(name)}</string>')
    props_lines.append(f'{ind2}<bool name="Anchored">true</bool>')
    props_lines.append(f'{ind2}{make_cframe_props(x, y, z)}')
    props_lines.append(f'{ind2}{make_vector3_size(sx, sy, sz)}')
    props_lines.append(f'{ind2}<Color3uint8 name="Color3uint8">{rgb_to_uint8(r, g, b)}</Color3uint8>')
    props_lines.append(f'{ind2}<token name="Material">{material}</token>')
    if transparency > 0:
        props_lines.append(f'{ind2}<float name="Transparency">{transparency}</float>')
    if shape_token is not None:
        props_lines.append(f'{ind2}<token name="shape">{shape_token}</token>')
    if extra_props:
        props_lines.append(extra_props)

    props_str = "\n".join(props_lines)

    children_str = ""
    if children:
        children_str = f"\n{children}"

    return (
        f'{ind}<Item class="{class_name}" referent="{ref}">\n'
        f'{ind1}<Properties>\n'
        f'{props_str}\n'
        f'{ind1}</Properties>{children_str}\n'
        f'{ind}</Item>'
    )


def make_script_xml(class_name, name, source_code, lvl=2, children_str=""):
    """Generate a Script/LocalScript/ModuleScript Item XML block."""
    ref = next_ref()
    ind = indent(lvl)
    ind1 = indent(lvl + 1)
    ind2 = indent(lvl + 2)

    props_lines = []
    props_lines.append(f'{ind2}<string name="Name">{xml_escape(name)}</string>')

    # Scripts and LocalScripts need Disabled=false
    if class_name in ("Script", "LocalScript"):
        props_lines.append(f'{ind2}<bool name="Disabled">false</bool>')

    # All script types need LinkedSource
    props_lines.append(f'{ind2}<Content name="LinkedSource"><null></null></Content>')

    # Source code in CDATA
    props_lines.append(f'{ind2}<ProtectedString name="Source"><![CDATA[{source_code}]]></ProtectedString>')

    props_str = "\n".join(props_lines)

    children_xml = f"\n{children_str}" if children_str else ""
    return (
        f'{ind}<Item class="{class_name}" referent="{ref}">\n'
        f'{ind1}<Properties>\n'
        f'{props_str}\n'
        f'{ind1}</Properties>{children_xml}\n'
        f'{ind}</Item>'
    )


def make_folder_xml(name, children_str, lvl=2):
    """Generate a Folder Item XML block."""
    ref = next_ref()
    ind = indent(lvl)
    ind1 = indent(lvl + 1)
    ind2 = indent(lvl + 2)

    return (
        f'{ind}<Item class="Folder" referent="{ref}">\n'
        f'{ind1}<Properties>\n'
        f'{ind2}<string name="Name">{xml_escape(name)}</string>\n'
        f'{ind1}</Properties>\n'
        f'{children_str}\n'
        f'{ind}</Item>'
    )


def make_service_xml(class_name, name, children_str, extra_props="", lvl=1):
    """Generate a top-level service Item (Workspace, Lighting, etc.)."""
    ref = next_ref()
    ind = indent(lvl)
    ind1 = indent(lvl + 1)
    ind2 = indent(lvl + 2)

    props_lines = [f'{ind2}<string name="Name">{xml_escape(name)}</string>']
    if extra_props:
        props_lines.append(extra_props)
    props_str = "\n".join(props_lines)

    return (
        f'{ind}<Item class="{class_name}" referent="{ref}">\n'
        f'{ind1}<Properties>\n'
        f'{props_str}\n'
        f'{ind1}</Properties>\n'
        f'{children_str}\n'
        f'{ind}</Item>'
    )


def make_remote_event_xml(name, lvl=4):
    """Generate a RemoteEvent Item."""
    ref = next_ref()
    ind = indent(lvl)
    ind1 = indent(lvl + 1)
    ind2 = indent(lvl + 2)
    return (
        f'{ind}<Item class="RemoteEvent" referent="{ref}">\n'
        f'{ind1}<Properties>\n'
        f'{ind2}<string name="Name">{xml_escape(name)}</string>\n'
        f'{ind1}</Properties>\n'
        f'{ind}</Item>'
    )


def make_remote_function_xml(name, lvl=4):
    """Generate a RemoteFunction Item."""
    ref = next_ref()
    ind = indent(lvl)
    ind1 = indent(lvl + 1)
    ind2 = indent(lvl + 2)
    return (
        f'{ind}<Item class="RemoteFunction" referent="{ref}">\n'
        f'{ind1}<Properties>\n'
        f'{ind2}<string name="Name">{xml_escape(name)}</string>\n'
        f'{ind1}</Properties>\n'
        f'{ind}</Item>'
    )


def make_sound_xml(name, sound_id, lvl=2):
    """Generate a Sound Item with an asset-backed SoundId."""
    ref = next_ref()
    ind = indent(lvl)
    ind1 = indent(lvl + 1)
    ind2 = indent(lvl + 2)
    return (
        f'{ind}<Item class="Sound" referent="{ref}">\n'
        f'{ind1}<Properties>\n'
        f'{ind2}<string name="Name">{xml_escape(name)}</string>\n'
        f'{ind2}<Content name="SoundId"><url>{xml_escape(sound_id)}</url></Content>\n'
        f'{ind1}</Properties>\n'
        f'{ind}</Item>'
    )


def build_workspace():
    """Build the Workspace hierarchy with static geometry only.

    NOTE: Destructible Parts (CoinPiles, DiamondPiles, Crates) are NOT placed here.
    The server-side ZoneService.init() creates a "Zones" folder and spawns all
    destructibles dynamically with proper DestructibleId StringValue children.
    Placing them statically in the .rbxlx would create duplicates without the
    required metadata and break the client code that searches workspace.Zones.
    """
    parts = []

    # Lobby Island floor (100x1x100 marble platform at X=-150, Z=-100)
    parts.append(make_part_xml(
        "LobbyFloor", "Part",
        -150, 0, -100, 100, 1, 100,
        220, 215, 200, material=784  # Marble
    ))

    # SpawnLocation on the lobby island
    parts.append(make_part_xml(
        "SpawnLocation", "SpawnLocation",
        -150, 1, -100, 12, 1, 12,
        255, 255, 255, material=256
    ))

    # Lobby-to-Zone1 connecting path
    parts.append(make_part_xml(
        "LobbyToZonePath", "Part",
        -75, 0, -100, 50, 1, 16,
        200, 195, 180, material=256  # Cobblestone
    ))

    # Zone 1: Gruene Wiesen - large green baseplate (static scenery only)
    parts.append(make_part_xml(
        "Zone1_GrueneWiesen", "Part",
        0, 0, -100, 200, 2, 200,
        76, 204, 51, material=1024
    ))

    # Zone 2: Stadt - gray baseplate (static scenery only)
    parts.append(make_part_xml(
        "Zone2_Stadt", "Part",
        200, 0, -100, 200, 2, 200,
        128, 128, 140, material=768
    ))

    # Zone 3: Strand - sandy baseplate
    parts.append(make_part_xml(
        "Zone3_Strand", "Part",
        400, 0, -100, 200, 2, 200,
        237, 201, 136, material=1024
    ))

    # Zone 4: Wueste - desert baseplate
    parts.append(make_part_xml(
        "Zone4_Wueste", "Part",
        600, 0, -100, 200, 2, 200,
        210, 180, 100, material=1024
    ))

    # Zone 5: Eiswelt - icy baseplate
    parts.append(make_part_xml(
        "Zone5_Eiswelt", "Part",
        800, 0, -100, 200, 2, 200,
        200, 230, 255, material=1024
    ))

    # Zone 6: Vulkan - volcanic baseplate
    parts.append(make_part_xml(
        "Zone6_Vulkan", "Part",
        1000, 0, -100, 200, 2, 200,
        80, 30, 10, material=768
    ))

    # Zone 7: Himmel - heavenly baseplate
    parts.append(make_part_xml(
        "Zone7_Himmel", "Part",
        1200, 0, -100, 200, 2, 200,
        255, 255, 220, material=1024
    ))

    # Zone 8: Weltraum - space baseplate
    parts.append(make_part_xml(
        "Zone8_Weltraum", "Part",
        1400, 0, -100, 200, 2, 200,
        20, 10, 40, material=768
    ))

    # Campaign Portal - purple Neon archway
    parts.append(make_part_xml(
        "CampaignPortal", "Part",
        50, 10, -100, 2, 16, 12,
        153, 25, 230, material=288, transparency=0.2
    ))

    # Zone Gates between adjacent zones (large archway style)
    # Gates exist between zone 1->2, 2->3, 3->4, ..., 7->8
    ZONE_SPACING = 200
    pillar_h = 20
    pillar_w = 4
    opening_w = 20  # space between pillars
    arch_h = 4

    for gate_idx in range(2, 9):
        prev_center = (gate_idx - 2) * ZONE_SPACING
        curr_center = (gate_idx - 1) * ZONE_SPACING
        gate_x = (prev_center + curr_center) // 2
        gate_z = -100  # center Z of zones

        # Left Pillar
        parts.append(make_part_xml(
            f"ZoneGate{gate_idx}_LeftPillar", "Part",
            gate_x, pillar_h // 2, gate_z - opening_w // 2 - pillar_w // 2,
            pillar_w, pillar_h, pillar_w,
            140, 140, 160, material=256
        ))

        # Right Pillar
        parts.append(make_part_xml(
            f"ZoneGate{gate_idx}_RightPillar", "Part",
            gate_x, pillar_h // 2, gate_z + opening_w // 2 + pillar_w // 2,
            pillar_w, pillar_h, pillar_w,
            140, 140, 160, material=256
        ))

        # Top Arch
        arch_width = opening_w + pillar_w * 2
        parts.append(make_part_xml(
            f"ZoneGate{gate_idx}_TopArch", "Part",
            gate_x, pillar_h + arch_h // 2, gate_z,
            pillar_w, arch_h, arch_width,
            140, 140, 160, material=256
        ))

        # Barrier (semi-transparent red, collidable when locked)
        parts.append(make_part_xml(
            f"ZoneGate{gate_idx}_Barrier", "Part",
            gate_x, pillar_h // 2, gate_z,
            2, pillar_h, opening_w,
            255, 60, 60, material=288, transparency=0.5
        ))

    # Terrain (placeholder)
    terrain_ref = next_ref()
    parts.append(
        f'\t\t<Item class="Terrain" referent="{terrain_ref}">\n'
        f'\t\t\t<Properties>\n'
        f'\t\t\t\t<string name="Name">Terrain</string>\n'
        f'\t\t\t</Properties>\n'
        f'\t\t</Item>'
    )

    # Camera
    camera_ref = next_ref()
    parts.append(
        f'\t\t<Item class="Camera" referent="{camera_ref}">\n'
        f'\t\t\t<Properties>\n'
        f'\t\t\t\t<string name="Name">Camera</string>\n'
        f'\t\t\t\t<token name="CameraType">0</token>\n'
        f'\t\t\t</Properties>\n'
        f'\t\t</Item>'
    )

    children_str = "\n".join(parts)
    return make_service_xml("Workspace", "Workspace", children_str)


def build_lighting():
    """Build Lighting with ColorCorrection, Atmosphere, and Bloom."""
    children = []

    # ColorCorrectionEffect
    cc_ref = next_ref()
    children.append(
        f'\t\t<Item class="ColorCorrectionEffect" referent="{cc_ref}">\n'
        f'\t\t\t<Properties>\n'
        f'\t\t\t\t<string name="Name">ColorCorrection</string>\n'
        f'\t\t\t\t<float name="Brightness">0.05</float>\n'
        f'\t\t\t\t<float name="Contrast">0.1</float>\n'
        f'\t\t\t\t<float name="Saturation">0.2</float>\n'
        f'\t\t\t</Properties>\n'
        f'\t\t</Item>'
    )

    # Atmosphere
    atmo_ref = next_ref()
    children.append(
        f'\t\t<Item class="Atmosphere" referent="{atmo_ref}">\n'
        f'\t\t\t<Properties>\n'
        f'\t\t\t\t<string name="Name">Atmosphere</string>\n'
        f'\t\t\t\t<float name="Density">0.3</float>\n'
        f'\t\t\t\t<float name="Offset">0.25</float>\n'
        f'\t\t\t</Properties>\n'
        f'\t\t</Item>'
    )

    # BloomEffect
    bloom_ref = next_ref()
    children.append(
        f'\t\t<Item class="BloomEffect" referent="{bloom_ref}">\n'
        f'\t\t\t<Properties>\n'
        f'\t\t\t\t<string name="Name">Bloom</string>\n'
        f'\t\t\t\t<float name="Intensity">0.4</float>\n'
        f'\t\t\t\t<float name="Size">24</float>\n'
        f'\t\t\t\t<float name="Threshold">0.9</float>\n'
        f'\t\t\t</Properties>\n'
        f'\t\t</Item>'
    )

    children_str = "\n".join(children)

    # Extra lighting properties
    extra_props = (
        f'\t\t\t<float name="Brightness">2</float>\n'
        f'\t\t\t<float name="ClockTime">14</float>'
    )

    return make_service_xml("Lighting", "Lighting", children_str, extra_props=extra_props)


def _load_upgrade_tree_sounds(project_root: Path) -> list[tuple[str, str]]:
    """Load the one supported model JSON shape without silently dropping data."""
    model_path = project_root / "src/ReplicatedStorage/modules/upgradeTree/sounds.model.json"
    try:
        model = json.loads(model_path.read_bytes().decode("utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise InventoryError(f"invalid {model_path.relative_to(project_root).as_posix()}: {error}") from error
    if set(model) != {"Name", "ClassName", "Children"}:
        raise InventoryError("sounds.model.json has unsupported root fields")
    if model["Name"] != "sounds" or model["ClassName"] != "Folder" or not isinstance(model["Children"], list):
        raise InventoryError("sounds.model.json must describe the sounds Folder")
    sounds: list[tuple[str, str]] = []
    for child in model["Children"]:
        if not isinstance(child, dict) or set(child) != {"Name", "ClassName", "Properties"}:
            raise InventoryError("sounds.model.json has an unsupported child shape")
        properties = child["Properties"]
        if child["ClassName"] != "Sound" or not isinstance(child["Name"], str):
            raise InventoryError("sounds.model.json children must be named Sounds")
        if not isinstance(properties, dict) or set(properties) != {"SoundId"}:
            raise InventoryError("sounds.model.json Sound properties must contain only SoundId")
        sound_id = properties["SoundId"]
        if not isinstance(sound_id, str) or not sound_id:
            raise InventoryError("sounds.model.json SoundId values must be non-empty strings")
        sounds.append((child["Name"], sound_id))
    sounds.sort(key=lambda sound: sound[0])
    if len({name for name, _ in sounds}) != len(sounds):
        raise InventoryError("sounds.model.json contains duplicate Sound names")
    return sounds


def build_replicated_storage(inventory: RuntimeInventory, project_root: Path):
    """Build ReplicatedStorage from the canonical runtime inventory."""
    shared_modules = [source_xml(source, lvl=4) for source in inventory.shared]
    shared_folder = make_folder_xml("Shared", "\n".join(shared_modules), lvl=3)

    vide_children = [source_xml(source, lvl=5) for source in inventory.vide_children]
    vide_module = source_xml(inventory.vide_root, lvl=4, children_str="\n".join(vide_children))
    packages_folder = make_folder_xml("packages", vide_module, lvl=3)

    tree_modules = [source_xml(source, lvl=5) for source in inventory.upgrade_tree]
    sound_children = [
        make_sound_xml(name, sound_id, lvl=6)
        for name, sound_id in _load_upgrade_tree_sounds(project_root)
    ]
    sounds_folder = make_folder_xml("sounds", "\n".join(sound_children), lvl=5)
    upgrade_tree_folder = make_folder_xml(
        "upgradeTree", "\n".join(tree_modules + [sounds_folder]), lvl=4
    )

    module_scripts = [source_xml(source, lvl=4) for source in inventory.modules]
    modules_folder = make_folder_xml(
        "modules", "\n".join(module_scripts + [upgrade_tree_folder]), lvl=3
    )

    children = "\n".join([shared_folder, packages_folder, modules_folder])
    return make_service_xml("ReplicatedStorage", "ReplicatedStorage", children)


def build_server_script_service(inventory: RuntimeInventory):
    """Build the flattened ServerScriptService from discovered runtime sources."""
    service_scripts = [source_xml(source, lvl=4) for source in inventory.services]
    services_folder = make_folder_xml("Services", "\n".join(service_scripts), lvl=3)
    main_script = source_xml(inventory.server_main, lvl=3)
    return make_service_xml(
        "ServerScriptService", "ServerScriptService", f"{main_script}\n{services_folder}"
    )


def build_starter_player(inventory: RuntimeInventory):
    """Build flattened StarterPlayerScripts from discovered runtime sources."""
    controller_scripts = [source_xml(source, lvl=4) for source in inventory.controllers]
    main_script = source_xml(inventory.client_main, lvl=4)
    scripts_children = f"{main_script}\n" + "\n".join(controller_scripts)

    sps_ref = next_ref()
    sps_xml = (
        f'\t\t<Item class="StarterPlayerScripts" referent="{sps_ref}">\n'
        f'\t\t\t<Properties>\n'
        f'\t\t\t\t<string name="Name">StarterPlayerScripts</string>\n'
        f'\t\t\t</Properties>\n'
        f'{scripts_children}\n'
        f'\t\t</Item>'
    )
    return make_service_xml("StarterPlayer", "StarterPlayer", sps_xml)


def build_starter_gui():
    """Build empty StarterGui."""
    ref = next_ref()
    return (
        f'\t<Item class="StarterGui" referent="{ref}">\n'
        f'\t\t<Properties>\n'
        f'\t\t\t<string name="Name">StarterGui</string>\n'
        f'\t\t</Properties>\n'
        f'\t</Item>'
    )


def build_sound_service():
    """Build SoundService placeholder."""
    ref = next_ref()
    return (
        f'\t<Item class="SoundService" referent="{ref}">\n'
        f'\t\t<Properties>\n'
        f'\t\t\t<string name="Name">SoundService</string>\n'
        f'\t\t</Properties>\n'
        f'\t</Item>'
    )


def generate_xml(project_root: Path) -> tuple[bytes, RuntimeInventory]:
    """Generate one deterministic UTF-8/LF document in memory."""
    _ref_counter[0] = 0
    inventory = discover_runtime_inventory(project_root)

    workspace_xml = build_workspace()
    lighting_xml = build_lighting()
    replicated_storage_xml = build_replicated_storage(inventory, project_root)
    server_script_service_xml = build_server_script_service(inventory)
    starter_player_xml = build_starter_player(inventory)
    starter_gui_xml = build_starter_gui()
    sound_service_xml = build_sound_service()

    xml_content = (
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" '
        'version="4">\n'
        '\t<Meta name="ExplicitAutoJoints">true</Meta>\n'
        '\t<External>null</External>\n'
        '\t<External>nil</External>\n'
        f'{workspace_xml}\n'
        f'{server_script_service_xml}\n'
        f'{starter_player_xml}\n'
        f'{replicated_storage_xml}\n'
        f'{starter_gui_xml}\n'
        f'{lighting_xml}\n'
        f'{sound_service_xml}\n'
        '</roblox>\n'
    )
    xml_bytes = xml_content.encode("utf-8")
    if b"\r" in xml_bytes:
        raise RuntimeError("generated XML contains non-LF line endings")
    ET.fromstring(xml_bytes)
    return xml_bytes, inventory


def _atomic_write(path: Path, content: bytes) -> None:
    """Publish bytes atomically without exposing stale partial output."""
    parent = path.parent
    if not parent.is_dir():
        raise RuntimeError(f"output directory does not exist: {parent}")
    temporary_name: Optional[str] = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb", dir=parent, prefix=f".{path.name}.", suffix=".tmp", delete=False
        ) as temporary:
            temporary_name = temporary.name
            temporary.write(content)
            temporary.flush()
            os.fsync(temporary.fileno())
        os.replace(temporary_name, path)
        temporary_name = None
    finally:
        if temporary_name is not None:
            Path(temporary_name).unlink(missing_ok=True)


def parse_args(argv: Optional[list[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--project-root",
        type=Path,
        default=DEFAULT_PROJECT_ROOT,
        help="project root containing src/ (default: repository root)",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="output RBXLX path (default: <project-root>/BATTLE_PETS.rbxlx)",
    )
    return parser.parse_args(argv)


def main(argv: Optional[list[str]] = None) -> int:
    """Generate and atomically publish the BATTLE_PETS.rbxlx place file."""
    args = parse_args(argv)
    project_root = args.project_root.resolve()
    output = (args.output or project_root / DEFAULT_OUTPUT_NAME).resolve()
    print(f"Generating {output.name} from source tree: {project_root / 'src'}")
    try:
        xml_bytes, inventory = generate_xml(project_root)
        _atomic_write(output, xml_bytes)
    except (InventoryError, OSError, RuntimeError, ET.ParseError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    xml_content = xml_bytes.decode("utf-8")
    item_count = xml_content.count('<Item class=')
    script_counts = {
        "Script": sum(source.class_name == "Script" for source in inventory.all_sources()),
        "LocalScript": sum(source.class_name == "LocalScript" for source in inventory.all_sources()),
        "ModuleScript": sum(source.class_name == "ModuleScript" for source in inventory.all_sources()),
    }
    print(f"Generated: {output}")
    print(f"  File size: {len(xml_bytes):,} bytes")
    print(f"  Total Items: {item_count}")
    print(f"  Scripts: {script_counts['Script']}")
    print(f"  LocalScripts: {script_counts['LocalScript']}")
    print(f"  ModuleScripts: {script_counts['ModuleScript']}")
    print("  RemoteEvents: 0")
    print("  RemoteFunctions: 0")
    print("Done!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
