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

import os
import sys

# Project root is parent of tools/
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(PROJECT_ROOT, "src")
OUTPUT_FILE = os.path.join(PROJECT_ROOT, "BATTLE_PETS.rbxlx")

# Global referent counter
_ref_counter = [0]


def next_ref():
    """Generate a unique referent ID."""
    _ref_counter[0] += 1
    return f"RBX{_ref_counter[0]:08X}"


def read_source(filepath):
    """Read a Lua source file and return its contents."""
    with open(filepath, "r", encoding="utf-8") as f:
        return f.read()


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


def make_script_xml(class_name, name, source_code, lvl=2):
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

    return (
        f'{ind}<Item class="{class_name}" referent="{ref}">\n'
        f'{ind1}<Properties>\n'
        f'{props_str}\n'
        f'{ind1}</Properties>\n'
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


def build_workspace():
    """Build the Workspace hierarchy with static geometry only.

    NOTE: Destructible Parts (CoinPiles, DiamondPiles, Crates) are NOT placed here.
    The server-side ZoneService.init() creates a "Zones" folder and spawns all
    destructibles dynamically with proper DestructibleId StringValue children.
    Placing them statically in the .rbxlx would create duplicates without the
    required metadata and break the client code that searches workspace.Zones.
    """
    parts = []

    # SpawnLocation
    parts.append(make_part_xml(
        "SpawnLocation", "SpawnLocation",
        0, 2, 0, 12, 1, 12,
        255, 255, 255, material=256
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
        250, 0, -100, 200, 2, 200,
        128, 128, 140, material=768
    ))

    # Zone 3: Strand - sandy baseplate
    parts.append(make_part_xml(
        "Zone3_Strand", "Part",
        500, 0, -100, 200, 2, 200,
        237, 201, 136, material=1024
    ))

    # Zone 4: Wueste - desert baseplate
    parts.append(make_part_xml(
        "Zone4_Wueste", "Part",
        750, 0, -100, 200, 2, 200,
        210, 180, 100, material=1024
    ))

    # Zone 5: Eiswelt - icy baseplate
    parts.append(make_part_xml(
        "Zone5_Eiswelt", "Part",
        1000, 0, -100, 200, 2, 200,
        200, 230, 255, material=1024
    ))

    # Zone 6: Vulkan - volcanic baseplate
    parts.append(make_part_xml(
        "Zone6_Vulkan", "Part",
        1250, 0, -100, 200, 2, 200,
        80, 30, 10, material=768
    ))

    # Zone 7: Himmel - heavenly baseplate
    parts.append(make_part_xml(
        "Zone7_Himmel", "Part",
        1500, 0, -100, 200, 2, 200,
        255, 255, 220, material=1024
    ))

    # Zone 8: Weltraum - space baseplate
    parts.append(make_part_xml(
        "Zone8_Weltraum", "Part",
        1750, 0, -100, 200, 2, 200,
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
    ZONE_SPACING = 250
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


def build_replicated_storage():
    """Build ReplicatedStorage with Shared modules only.

    NOTE: The Remotes folder is NOT included here. The server Main.server.lua
    creates it at runtime via Instance.new("Folder") with all RemoteEvents and
    RemoteFunctions. Including it in the .rbxlx would create a duplicate folder
    that conflicts with the server-created one. The client uses WaitForChild("Remotes")
    which correctly waits for the server to create it.
    """
    # Shared folder with ModuleScripts
    shared_modules = []
    module_names = ["Config", "PetData", "ZoneData", "CampaignData", "QuestData", "MasteryData"]
    for mod_name in module_names:
        filepath = os.path.join(SRC_DIR, "ReplicatedStorage", "Shared", f"{mod_name}.lua")
        source = read_source(filepath)
        shared_modules.append(make_script_xml("ModuleScript", mod_name, source, lvl=4))

    shared_children = "\n".join(shared_modules)
    shared_folder = make_folder_xml("Shared", shared_children, lvl=3)

    # ReplicatedStorage contains only the Shared folder
    return make_service_xml("ReplicatedStorage", "ReplicatedStorage", shared_folder)


def build_server_script_service():
    """Build ServerScriptService with scripts (flattened structure - no Server/ subfolder)."""
    # Services folder with ModuleScripts
    service_names = [
        "DataService", "CurrencyService", "PetService",
        "UpgradeService", "ZoneService", "CampaignService", "EggService",
        "QuestService", "MasteryService"
    ]
    service_scripts = []
    for svc_name in service_names:
        filepath = os.path.join(SRC_DIR, "ServerScriptService", "Services", f"{svc_name}.lua")
        source = read_source(filepath)
        service_scripts.append(make_script_xml("ModuleScript", svc_name, source, lvl=4))

    services_children = "\n".join(service_scripts)
    services_folder = make_folder_xml("Services", services_children, lvl=3)

    # Main.server.lua -> Script
    main_path = os.path.join(SRC_DIR, "ServerScriptService", "Main.server.lua")
    main_source = read_source(main_path)
    main_script = make_script_xml("Script", "Main", main_source, lvl=3)

    # ServerScriptService contains Main script and Services subfolder directly
    children_str = f"{main_script}\n{services_folder}"

    return make_service_xml("ServerScriptService", "ServerScriptService", children_str)


def build_starter_player():
    """Build StarterPlayer with StarterPlayerScripts (flattened structure - no Client/ subfolder)."""
    # Controller ModuleScripts
    controller_names = ["UIController", "PetController", "CampaignController", "EffectsController", "MusicController"]
    controller_scripts = []
    for ctrl_name in controller_names:
        filepath = os.path.join(SRC_DIR, "StarterPlayer", "StarterPlayerScripts", f"{ctrl_name}.lua")
        source = read_source(filepath)
        controller_scripts.append(make_script_xml("ModuleScript", ctrl_name, source, lvl=4))

    # Main.client.lua -> LocalScript
    main_path = os.path.join(SRC_DIR, "StarterPlayer", "StarterPlayerScripts", "Main.client.lua")
    main_source = read_source(main_path)
    main_script = make_script_xml("LocalScript", "Main", main_source, lvl=4)

    # StarterPlayerScripts contains scripts directly (no Client subfolder)
    scripts_children = f"{main_script}\n" + "\n".join(controller_scripts)

    # StarterPlayerScripts
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


def main():
    """Generate the BATTLE_PETS.rbxlx place file."""
    print(f"Generating BATTLE_PETS.rbxlx from source tree: {SRC_DIR}")

    # Verify source directory exists
    if not os.path.isdir(SRC_DIR):
        print(f"ERROR: Source directory not found: {SRC_DIR}", file=sys.stderr)
        sys.exit(1)

    # Build all sections
    workspace_xml = build_workspace()
    lighting_xml = build_lighting()
    replicated_storage_xml = build_replicated_storage()
    server_script_service_xml = build_server_script_service()
    starter_player_xml = build_starter_player()
    starter_gui_xml = build_starter_gui()
    sound_service_xml = build_sound_service()

    # Assemble complete file with correct Roblox XML header
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

    # Write output
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        f.write(xml_content)

    # Report stats
    file_size = os.path.getsize(OUTPUT_FILE)
    # Count items
    item_count = xml_content.count('<Item class=')
    script_count = xml_content.count('class="Script"')
    local_script_count = xml_content.count('class="LocalScript"')
    module_script_count = xml_content.count('class="ModuleScript"')
    remote_event_count = xml_content.count('class="RemoteEvent"')
    remote_function_count = xml_content.count('class="RemoteFunction"')

    print(f"Generated: {OUTPUT_FILE}")
    print(f"  File size: {file_size:,} bytes")
    print(f"  Total Items: {item_count}")
    print(f"  Scripts: {script_count}")
    print(f"  LocalScripts: {local_script_count}")
    print(f"  ModuleScripts: {module_script_count}")
    print(f"  RemoteEvents: {remote_event_count}")
    print(f"  RemoteFunctions: {remote_function_count}")
    print("Done!")


if __name__ == "__main__":
    main()
