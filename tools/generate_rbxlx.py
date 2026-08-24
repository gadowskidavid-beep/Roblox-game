#!/usr/bin/env python3
"""
Generate BATTLE_PETS.rbxlx place file from the src/ tree.

Reads all .lua source files and embeds them into a valid Roblox place XML file
(version 4) with procedural world geometry for zones, portals, gates, and
destructible objects.
"""

import os
import sys
import xml.etree.ElementTree as ET
from xml.etree.ElementTree import Element, SubElement

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


def add_property(properties_elem, tag, name, value=None, children=None):
    """Add a property element to a Properties container."""
    prop = SubElement(properties_elem, tag)
    prop.set("name", name)
    if value is not None:
        prop.text = value
    if children:
        for child_tag, child_text in children:
            child = SubElement(prop, child_tag)
            child.text = child_text
    return prop


def add_vector3(properties_elem, name, x, y, z):
    """Add a Vector3 property."""
    add_property(properties_elem, "Vector3", name, children=[
        ("X", str(x)), ("Y", str(y)), ("Z", str(z))
    ])


def add_color3(properties_elem, name, r, g, b):
    """Add a Color3 property (values 0-1)."""
    add_property(properties_elem, "Color3", name, children=[
        ("R", str(r)), ("G", str(g)), ("B", str(b))
    ])


def add_string(properties_elem, name, value):
    """Add a string property."""
    add_property(properties_elem, "string", name, value)


def add_bool(properties_elem, name, value):
    """Add a bool property."""
    add_property(properties_elem, "bool", name, "true" if value else "false")


def add_float(properties_elem, name, value):
    """Add a float property."""
    add_property(properties_elem, "float", name, str(value))


def add_token(properties_elem, name, value):
    """Add a token property (enum)."""
    add_property(properties_elem, "token", name, str(value))


def add_source(properties_elem, source_code):
    """Add a ProtectedString Source property.
    
    The source code is stored as element text. During final serialization,
    we post-process to wrap it in CDATA for proper .rbxlx format.
    """
    prop = SubElement(properties_elem, "ProtectedString")
    prop.set("name", "Source")
    # Store source in text; we'll convert to CDATA during serialization
    prop.text = source_code


def create_item(parent, class_name, name, extra_props=None):
    """Create an Item element with Name property."""
    item = SubElement(parent, "Item")
    item.set("class", class_name)
    item.set("referent", next_ref())
    props = SubElement(item, "Properties")
    add_string(props, "Name", name)
    if extra_props:
        extra_props(props)
    return item


def create_part(parent, name, position, size, color_rgb, material=256,
                transparency=0, shape=None):
    """Create a Part Item with standard properties.
    
    color_rgb: tuple of (R, G, B) in 0-1 range
    material: SmoothPlastic=256, Neon=288, Grass=1024, Wood=512, Slate=768
    """
    item = SubElement(parent, "Item")
    item.set("class", "Part" if shape != "Wedge" else "WedgePart")
    item.set("referent", next_ref())
    props = SubElement(item, "Properties")
    add_string(props, "Name", name)
    add_bool(props, "Anchored", True)
    add_vector3(props, "Position", *position)
    add_vector3(props, "Size", *size)
    add_color3(props, "Color", *color_rgb)
    add_token(props, "Material", material)
    if transparency > 0:
        add_float(props, "Transparency", transparency)
    if shape == "Cylinder":
        add_token(props, "shape", 1)  # Cylinder shape enum
    return item


def create_script_item(parent, class_name, name, source_code):
    """Create a Script/LocalScript/ModuleScript with embedded source."""
    item = SubElement(parent, "Item")
    item.set("class", class_name)
    item.set("referent", next_ref())
    props = SubElement(item, "Properties")
    add_string(props, "Name", name)
    add_source(props, source_code)
    if class_name == "Script":
        add_token(props, "RunContext", 0)
    return item


def create_folder(parent, name):
    """Create a Folder item."""
    return create_item(parent, "Folder", name)


def build_workspace(root):
    """Build the Workspace hierarchy with procedural geometry."""
    workspace = create_item(root, "Workspace", "Workspace")

    # Camera
    camera = SubElement(workspace, "Item")
    camera.set("class", "Camera")
    camera.set("referent", next_ref())
    cam_props = SubElement(camera, "Properties")
    add_string(cam_props, "Name", "Camera")
    add_token(cam_props, "CameraType", 0)

    # SpawnLocation
    create_part(workspace, "SpawnLocation", (0, 2, 0), (12, 1, 12),
                (1, 1, 1), material=256)
    # Override class to SpawnLocation
    spawn_item = workspace[-1]
    spawn_item.set("class", "SpawnLocation")

    # Zone 1: Gruene Wiesen - large green baseplate
    create_part(workspace, "Zone1_GrueneWiesen", (0, 0, -100), (200, 2, 200),
                (0.3, 0.8, 0.2), material=1024)

    # Zone 1 Destructibles - Coin Piles (yellow cylinders)
    coin_positions = [
        (-30, 3, -80), (-50, 3, -120), (20, 3, -60),
        (40, 3, -140), (-10, 3, -160), (60, 3, -90),
        (-70, 3, -50), (30, 3, -180)
    ]
    for i, pos in enumerate(coin_positions):
        create_part(workspace, f"CoinPile_{i+1}", pos, (3, 4, 3),
                    (1, 0.85, 0.1), material=256, shape="Cylinder")

    # Zone 1 Destructibles - Diamond Piles (blue wedges)
    diamond_positions = [
        (-20, 3, -110), (50, 3, -70), (-60, 3, -150),
        (10, 3, -190), (70, 3, -130)
    ]
    for i, pos in enumerate(diamond_positions):
        create_part(workspace, f"DiamondPile_{i+1}", pos, (3, 5, 3),
                    (0.2, 0.5, 1.0), material=256, shape="Wedge")

    # Zone 1 Destructibles - Crates (brown cubes)
    crate_positions = [
        (-40, 3, -90), (25, 3, -100), (-15, 3, -140),
        (55, 3, -50), (-65, 3, -170), (35, 3, -160)
    ]
    for i, pos in enumerate(crate_positions):
        create_part(workspace, f"Crate_{i+1}", pos, (4, 4, 4),
                    (0.55, 0.35, 0.15), material=512)

    # Zone 2: Stadt - gray baseplate offset
    create_part(workspace, "Zone2_Stadt", (250, 0, -100), (200, 2, 200),
                (0.5, 0.5, 0.55), material=768)

    # Zone 2 Destructibles - urban themed
    urban_crate_positions = [
        (220, 3, -80), (260, 3, -120), (240, 3, -60),
        (280, 3, -140), (230, 3, -160), (270, 3, -90)
    ]
    for i, pos in enumerate(urban_crate_positions):
        create_part(workspace, f"UrbanCrate_{i+1}", pos, (5, 5, 5),
                    (0.4, 0.4, 0.45), material=256)

    urban_coin_positions = [
        (210, 3, -110), (290, 3, -70), (245, 3, -150),
        (265, 3, -190), (235, 3, -40)
    ]
    for i, pos in enumerate(urban_coin_positions):
        create_part(workspace, f"UrbanCoinPile_{i+1}", pos, (3, 4, 3),
                    (1, 0.85, 0.1), material=256, shape="Cylinder")

    # Campaign Portal - purple Neon archway
    create_part(workspace, "CampaignPortal", (50, 10, -100), (2, 16, 12),
                (0.6, 0.1, 0.9), material=288, transparency=0.2)

    # Zone Gate between Zone 1 and Zone 2
    create_part(workspace, "ZoneGate_1_2", (125, 8, -100), (4, 16, 16),
                (0.9, 0.7, 0.1), material=288, transparency=0.3)

    # Terrain (empty placeholder)
    terrain = SubElement(workspace, "Item")
    terrain.set("class", "Terrain")
    terrain.set("referent", next_ref())
    t_props = SubElement(terrain, "Properties")
    add_string(t_props, "Name", "Terrain")

    return workspace


def build_lighting(root):
    """Build Lighting with ColorCorrection and Atmosphere."""
    lighting = create_item(root, "Lighting", "Lighting")
    props = lighting.find("Properties")
    add_color3(props, "Ambient", 0.5, 0.5, 0.6)
    add_color3(props, "OutdoorAmbient", 0.7, 0.7, 0.75)
    add_float(props, "Brightness", 2)
    add_float(props, "ClockTime", 14)

    # ColorCorrectionEffect
    cc = SubElement(lighting, "Item")
    cc.set("class", "ColorCorrectionEffect")
    cc.set("referent", next_ref())
    cc_props = SubElement(cc, "Properties")
    add_string(cc_props, "Name", "ColorCorrection")
    add_float(cc_props, "Brightness", 0.05)
    add_float(cc_props, "Contrast", 0.1)
    add_float(cc_props, "Saturation", 0.2)

    # Atmosphere
    atmo = SubElement(lighting, "Item")
    atmo.set("class", "Atmosphere")
    atmo.set("referent", next_ref())
    atmo_props = SubElement(atmo, "Properties")
    add_string(atmo_props, "Name", "Atmosphere")
    add_float(atmo_props, "Density", 0.3)
    add_float(atmo_props, "Offset", 0.25)

    # BloomEffect for cartoon glow
    bloom = SubElement(lighting, "Item")
    bloom.set("class", "BloomEffect")
    bloom.set("referent", next_ref())
    bloom_props = SubElement(bloom, "Properties")
    add_string(bloom_props, "Name", "Bloom")
    add_float(bloom_props, "Intensity", 0.4)
    add_float(bloom_props, "Size", 24)
    add_float(bloom_props, "Threshold", 0.9)

    return lighting


def build_replicated_storage(root):
    """Build ReplicatedStorage with shared modules and remotes."""
    rs = create_item(root, "ReplicatedStorage", "ReplicatedStorage")

    # Shared folder
    shared = create_folder(rs, "Shared")
    shared_modules = ["Config", "PetData", "ZoneData", "CampaignData"]
    for mod_name in shared_modules:
        filepath = os.path.join(SRC_DIR, "ReplicatedStorage", "Shared",
                                f"{mod_name}.lua")
        source = read_source(filepath)
        create_script_item(shared, "ModuleScript", mod_name, source)

    # Remotes folder with RemoteEvents and RemoteFunctions
    remotes = create_folder(rs, "Remotes")

    # RemoteEvents used by the game
    remote_events = [
        "CurrencyUpdate", "PetUpdate", "ZoneUpdate",
        "SpawnPet", "DespawnPet", "DestroyObject",
        "UnlockZone", "EquipPet", "UnequipPet",
        "StartCampaign", "CampaignUpdate", "CampaignEnd",
        "UpgradePet", "OpenEgg", "EggResult",
        "PlayEffect", "UINotification"
    ]
    for event_name in remote_events:
        create_item(remotes, "RemoteEvent", event_name)

    # RemoteFunctions
    remote_functions = [
        "GetPlayerData", "GetPets", "GetZones",
        "PurchaseEgg", "GetCampaignStatus"
    ]
    for func_name in remote_functions:
        create_item(remotes, "RemoteFunction", func_name)

    return rs


def build_server_script_service(root):
    """Build ServerScriptService with server scripts."""
    sss = create_item(root, "ServerScriptService", "ServerScriptService")

    # Server folder
    server = create_folder(sss, "Server")

    # Main.server.lua -> Script class
    main_path = os.path.join(SRC_DIR, "ServerScriptService", "Server",
                             "Main.server.lua")
    main_source = read_source(main_path)
    create_script_item(server, "Script", "Main", main_source)

    # Services folder
    services = create_folder(server, "Services")
    service_files = [
        "DataService", "CurrencyService", "PetService",
        "UpgradeService", "ZoneService", "CampaignService", "EggService"
    ]
    for svc_name in service_files:
        filepath = os.path.join(SRC_DIR, "ServerScriptService", "Server",
                                "Services", f"{svc_name}.lua")
        source = read_source(filepath)
        create_script_item(services, "ModuleScript", svc_name, source)

    return sss


def build_starter_player(root):
    """Build StarterPlayer with client scripts."""
    sp = create_item(root, "StarterPlayer", "StarterPlayer")

    # StarterPlayerScripts
    sps = create_item(sp, "StarterPlayerScripts", "StarterPlayerScripts")

    # Client folder
    client = create_folder(sps, "Client")

    # Main.client.lua -> LocalScript class
    main_path = os.path.join(SRC_DIR, "StarterPlayer",
                             "StarterPlayerScripts", "Client",
                             "Main.client.lua")
    main_source = read_source(main_path)
    create_script_item(client, "LocalScript", "Main", main_source)

    # Controller ModuleScripts
    controller_files = [
        "UIController", "PetController",
        "CampaignController", "EffectsController"
    ]
    for ctrl_name in controller_files:
        filepath = os.path.join(SRC_DIR, "StarterPlayer",
                                "StarterPlayerScripts", "Client",
                                f"{ctrl_name}.lua")
        source = read_source(filepath)
        create_script_item(client, "ModuleScript", ctrl_name, source)

    return sp


def build_starter_gui(root):
    """Build StarterGui placeholder."""
    return create_item(root, "StarterGui", "StarterGui")


def build_sound_service(root):
    """Build SoundService placeholder."""
    return create_item(root, "SoundService", "SoundService")


def serialize_with_cdata(root):
    """Serialize the XML tree, wrapping ProtectedString content in CDATA.
    
    ElementTree doesn't support CDATA natively, so we use a custom serializer
    that properly handles ProtectedString elements with CDATA sections.
    """
    lines = []
    lines.append("<?xml version='1.0' encoding='utf-8'?>")
    _serialize_element(root, lines, 0)
    return "\n".join(lines)


def _serialize_element(elem, lines, level):
    """Recursively serialize an element, using CDATA for ProtectedString."""
    indent = "  " * level
    tag = elem.tag
    attrs = "".join(f' {k}="{_xml_escape_attr(v)}"' for k, v in elem.attrib.items())

    is_protected_string = (tag == "ProtectedString")

    if len(elem) == 0 and elem.text is None:
        # Self-closing tag
        lines.append(f"{indent}<{tag}{attrs} />")
    elif len(elem) == 0:
        # Leaf element with text
        if is_protected_string and elem.text:
            # Use CDATA for source code
            lines.append(f"{indent}<{tag}{attrs}><![CDATA[{elem.text}]]></{tag}>")
        else:
            escaped_text = _xml_escape(elem.text) if elem.text else ""
            lines.append(f"{indent}<{tag}{attrs}>{escaped_text}</{tag}>")
    else:
        # Element with children
        lines.append(f"{indent}<{tag}{attrs}>")
        for child in elem:
            _serialize_element(child, lines, level + 1)
        lines.append(f"{indent}</{tag}>")


def _xml_escape(text):
    """Escape text for XML content."""
    if text is None:
        return ""
    text = text.replace("&", "&amp;")
    text = text.replace("<", "&lt;")
    text = text.replace(">", "&gt;")
    return text


def _xml_escape_attr(text):
    """Escape text for XML attributes."""
    text = text.replace("&", "&amp;")
    text = text.replace("<", "&lt;")
    text = text.replace(">", "&gt;")
    text = text.replace('"', "&quot;")
    return text


def main():
    """Generate the BATTLE_PETS.rbxlx place file."""
    print(f"Generating BATTLE_PETS.rbxlx from source tree: {SRC_DIR}")

    # Verify source directory exists
    if not os.path.isdir(SRC_DIR):
        print(f"ERROR: Source directory not found: {SRC_DIR}", file=sys.stderr)
        sys.exit(1)

    # Build XML tree
    root = Element("roblox")
    root.set("version", "4")

    # Build all top-level services
    build_workspace(root)
    build_lighting(root)
    build_replicated_storage(root)
    build_server_script_service(root)
    build_starter_player(root)
    build_starter_gui(root)
    build_sound_service(root)

    # Serialize with CDATA support
    xml_content = serialize_with_cdata(root)

    # Write output
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        f.write(xml_content)
        f.write("\n")

    # Report stats
    file_size = os.path.getsize(OUTPUT_FILE)
    item_count = len(root.findall(".//Item"))
    print(f"Generated: {OUTPUT_FILE}")
    print(f"  File size: {file_size:,} bytes")
    print(f"  Total items: {item_count}")
    print("Done!")


if __name__ == "__main__":
    main()
