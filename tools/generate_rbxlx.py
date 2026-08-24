#!/usr/bin/env python3
"""
Generate BATTLE_PETS.rbxlx place file from the src/ tree.

Produces a valid Roblox Studio place file (rbxlx format) with:
- Correct DataModel root element with xmlns attributes
- Proper script hierarchy (Script, LocalScript, ModuleScript)
- ProtectedString Source properties with CDATA wrapping
- CoordinateFrame for Part positioning
- All RemoteEvents and RemoteFunctions
- Procedural world geometry for 2 zones + campaign portal
- Lighting with post-processing effects
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
    """Generate a unique referent string."""
    _ref_counter[0] += 1
    return "RBX{:08X}".format(_ref_counter[0])


def read_source(filepath):
    """Read a Lua source file."""
    with open(filepath, "r", encoding="utf-8") as f:
        return f.read()


def escape_xml(text):
    """Escape special XML characters in text content."""
    if text is None:
        return ""
    text = text.replace("&", "&amp;")
    text = text.replace("<", "&lt;")
    text = text.replace(">", "&gt;")
    return text


def escape_attr(text):
    """Escape special XML characters in attribute values."""
    text = text.replace("&", "&amp;")
    text = text.replace("<", "&lt;")
    text = text.replace(">", "&gt;")
    text = text.replace('"', "&quot;")
    return text


def color3_to_uint32(r, g, b):
    """Convert float RGB (0-1) to Color3uint8 packed value (4294967295 format).
    Roblox uses: 0xFF000000 | (R << 16) | (G << 8) | B
    """
    ri = max(0, min(255, int(r * 255)))
    gi = max(0, min(255, int(g * 255)))
    bi = max(0, min(255, int(b * 255)))
    return 0xFF000000 | (ri << 16) | (gi << 8) | bi


class XMLWriter:
    """Simple XML writer that supports CDATA sections and proper indentation."""

    def __init__(self):
        self.lines = []
        self._indent = 0

    def _i(self):
        return "\t" * self._indent

    def raw(self, text):
        self.lines.append(text)

    def open_tag(self, tag, attrs=None):
        attr_str = ""
        if attrs:
            for k, v in attrs.items():
                attr_str += ' {}="{}"'.format(k, escape_attr(str(v)))
        self.lines.append("{}<{}{}>".format(self._i(), tag, attr_str))
        self._indent += 1

    def close_tag(self, tag):
        self._indent -= 1
        self.lines.append("{}</{}>".format(self._i(), tag))

    def self_closing(self, tag, attrs=None):
        attr_str = ""
        if attrs:
            for k, v in attrs.items():
                attr_str += ' {}="{}"'.format(k, escape_attr(str(v)))
        self.lines.append("{}<{}{} />".format(self._i(), tag, attr_str))

    def text_element(self, tag, text, attrs=None):
        attr_str = ""
        if attrs:
            for k, v in attrs.items():
                attr_str += ' {}="{}"'.format(k, escape_attr(str(v)))
        self.lines.append("{}<{}{}>{}</{}>".format(
            self._i(), tag, attr_str, escape_xml(str(text)), tag))

    def cdata_element(self, tag, content, attrs=None):
        """Write an element whose text is wrapped in CDATA."""
        attr_str = ""
        if attrs:
            for k, v in attrs.items():
                attr_str += ' {}="{}"'.format(k, escape_attr(str(v)))
        # Multi-line CDATA for source code
        self.lines.append("{}<{}{}><![CDATA[{}]]></{}>".format(
            self._i(), tag, attr_str, content, tag))

    def result(self):
        return "\n".join(self.lines) + "\n"


def write_string_prop(w, name, value):
    w.text_element("string", value, {"name": name})


def write_bool_prop(w, name, value):
    w.text_element("bool", "true" if value else "false", {"name": name})


def write_int_prop(w, name, value):
    w.text_element("int", str(int(value)), {"name": name})


def write_float_prop(w, name, value):
    w.text_element("float", str(value), {"name": name})


def write_double_prop(w, name, value):
    w.text_element("double", str(value), {"name": name})


def write_token_prop(w, name, value):
    w.text_element("token", str(value), {"name": name})


def write_color3uint8_prop(w, name, r, g, b):
    """Write Color3uint8 property (packed uint32)."""
    val = color3_to_uint32(r, g, b)
    w.text_element("Color3uint8", str(val), {"name": name})


def write_color3_prop(w, name, r, g, b):
    """Write Color3 property with float RGB children."""
    w.open_tag("Color3", {"name": name})
    w.text_element("R", str(r))
    w.text_element("G", str(g))
    w.text_element("B", str(b))
    w.close_tag("Color3")


def write_vector3_prop(w, name, x, y, z):
    w.open_tag("Vector3", {"name": name})
    w.text_element("X", str(x))
    w.text_element("Y", str(y))
    w.text_element("Z", str(z))
    w.close_tag("Vector3")


def write_cframe_prop(w, name, x, y, z):
    """Write a CoordinateFrame property (position only, identity rotation)."""
    w.open_tag("CoordinateFrame", {"name": name})
    w.text_element("X", str(x))
    w.text_element("Y", str(y))
    w.text_element("Z", str(z))
    w.text_element("R00", "1")
    w.text_element("R01", "0")
    w.text_element("R02", "0")
    w.text_element("R10", "0")
    w.text_element("R11", "1")
    w.text_element("R12", "0")
    w.text_element("R20", "0")
    w.text_element("R21", "0")
    w.text_element("R22", "1")
    w.close_tag("CoordinateFrame")


def write_source_prop(w, source_code):
    """Write ProtectedString Source property with CDATA."""
    w.cdata_element("ProtectedString", source_code, {"name": "Source"})


def begin_item(w, class_name, name, extra_props_fn=None):
    """Open an Item element. Returns referent. Caller must close_tag('Item')."""
    ref = next_ref()
    w.open_tag("Item", {"class": class_name, "referent": ref})
    w.open_tag("Properties")
    write_string_prop(w, "Name", name)
    if extra_props_fn:
        extra_props_fn(w)
    w.close_tag("Properties")
    return ref


def write_item_simple(w, class_name, name, extra_props_fn=None):
    """Write a self-contained Item with no children."""
    begin_item(w, class_name, name, extra_props_fn)
    w.close_tag("Item")


def write_script_item(w, class_name, name, source_code, has_children=False):
    """Write a Script/LocalScript/ModuleScript item with source.
    If has_children=True, leaves the Item tag open for nested items.
    """
    ref = next_ref()
    w.open_tag("Item", {"class": class_name, "referent": ref})
    w.open_tag("Properties")
    write_string_prop(w, "Name", name)
    write_source_prop(w, source_code)
    if class_name == "Script":
        # RunContext: 0 = Legacy (runs in ServerScriptService automatically)
        write_token_prop(w, "RunContext", 0)
    w.close_tag("Properties")
    if not has_children:
        w.close_tag("Item")
    return ref


def write_part(w, name, pos, size, color_rgb, material=272, transparency=0,
               shape="Block", anchored=True, can_collide=True):
    """Write a Part or WedgePart or SpawnLocation.
    
    material values: SmoothPlastic=272, Neon=288, Grass=1024, Wood=512,
                     Slate=768, Brick=256, Concrete=816
    shape: Block, Ball, Cylinder, Wedge
    """
    class_name = "Part"
    if shape == "Wedge":
        class_name = "WedgePart"

    ref = next_ref()
    w.open_tag("Item", {"class": class_name, "referent": ref})
    w.open_tag("Properties")
    write_string_prop(w, "Name", name)
    write_bool_prop(w, "Anchored", anchored)
    write_bool_prop(w, "CanCollide", can_collide)
    write_cframe_prop(w, "CFrame", pos[0], pos[1], pos[2])
    write_vector3_prop(w, "size", size[0], size[1], size[2])
    write_color3uint8_prop(w, "Color3uint8", color_rgb[0], color_rgb[1], color_rgb[2])
    write_token_prop(w, "Material", material)
    if transparency > 0:
        write_float_prop(w, "Transparency", transparency)
    if shape == "Ball":
        write_token_prop(w, "shape", 0)  # Ball
    elif shape == "Cylinder":
        write_token_prop(w, "shape", 1)  # Cylinder
    # Block is default (2)
    w.close_tag("Properties")
    w.close_tag("Item")
    return ref


def write_spawn_location(w, name, pos, size):
    """Write a SpawnLocation part."""
    ref = next_ref()
    w.open_tag("Item", {"class": "SpawnLocation", "referent": ref})
    w.open_tag("Properties")
    write_string_prop(w, "Name", name)
    write_bool_prop(w, "Anchored", True)
    write_bool_prop(w, "CanCollide", True)
    write_cframe_prop(w, "CFrame", pos[0], pos[1], pos[2])
    write_vector3_prop(w, "size", size[0], size[1], size[2])
    write_color3uint8_prop(w, "Color3uint8", 0.63, 0.63, 0.63)
    write_token_prop(w, "Material", 272)
    write_int_prop(w, "Duration", 0)
    write_bool_prop(w, "Neutral", True)
    w.close_tag("Properties")
    w.close_tag("Item")


def write_folder(w, name, has_children=True):
    """Write a Folder item. If has_children, leaves tag open."""
    begin_item(w, "Folder", name)
    if not has_children:
        w.close_tag("Item")


def build_workspace(w):
    """Build the Workspace with all world geometry."""
    begin_item(w, "Workspace", "Workspace")

    # Camera
    begin_item(w, "Camera", "Camera", lambda wr: write_token_prop(wr, "CameraType", 0))
    w.close_tag("Item")

    # SpawnLocation
    write_spawn_location(w, "SpawnLocation", (0, 1.5, 0), (12, 1, 12))

    # Terrain (required by Roblox Studio)
    begin_item(w, "Terrain", "Terrain")
    w.close_tag("Item")

    # Zones folder (for client-side destructible lookup)
    write_folder(w, "Zones", has_children=True)

    # Zone 1: Gruene Wiesen
    write_folder(w, "Zone_1", has_children=True)
    # Ground
    write_part(w, "Ground", (50, -0.5, -50), (100, 1, 100),
               (0.3, 0.6, 0.0), material=1024)
    # CoinPiles
    coin_positions = [
        (20, 2, -30), (35, 2, -50), (10, 2, -70),
        (60, 2, -40), (45, 2, -80), (70, 2, -20),
        (25, 2, -90), (80, 2, -60)
    ]
    for i, pos in enumerate(coin_positions):
        _write_destructible(w, "CoinPile_{}".format(i+1), pos, "Cylinder",
                            (1.0, 0.84, 0.0), 10)
    # DiamondPiles
    diamond_positions = [
        (15, 2, -40), (55, 2, -25), (30, 2, -60),
        (75, 2, -45), (50, 2, -85)
    ]
    for i, pos in enumerate(diamond_positions):
        _write_destructible(w, "DiamondPile_{}".format(i+1), pos, "Wedge",
                            (0.0, 0.6, 1.0), 20)
    # Crates
    crate_positions = [
        (40, 2, -35), (65, 2, -55), (20, 2, -75),
        (50, 2, -15), (85, 2, -70), (30, 2, -95)
    ]
    for i, pos in enumerate(crate_positions):
        _write_destructible(w, "Crate_{}".format(i+1), pos, "Block",
                            (0.55, 0.35, 0.17), 15)
    w.close_tag("Item")  # Close Zone_1 folder

    # Zone 2: Stadt
    write_folder(w, "Zone_2", has_children=True)
    write_part(w, "Ground", (170, -0.5, -50), (100, 1, 100),
               (0.5, 0.5, 0.55), material=816)
    urban_coin_positions = [
        (140, 2, -30), (160, 2, -50), (180, 2, -70),
        (200, 2, -40), (150, 2, -80)
    ]
    for i, pos in enumerate(urban_coin_positions):
        _write_destructible(w, "UrbanCoinPile_{}".format(i+1), pos, "Cylinder",
                            (1.0, 0.84, 0.0), 25)
    urban_crate_positions = [
        (145, 2, -45), (165, 2, -25), (185, 2, -60),
        (205, 2, -35), (155, 2, -90), (175, 2, -15)
    ]
    for i, pos in enumerate(urban_crate_positions):
        _write_destructible(w, "UrbanCrate_{}".format(i+1), pos, "Block",
                            (0.4, 0.4, 0.45), 35)
    w.close_tag("Item")  # Close Zone_2 folder

    w.close_tag("Item")  # Close Zones folder

    # Campaign Portal
    write_part(w, "CampaignPortal", (95, 8, -50), (3, 16, 12),
               (0.6, 0.1, 0.9), material=288, transparency=0.2)

    # Zone Gate between zones
    write_part(w, "ZoneGate_1_2", (120, 6, -50), (4, 12, 16),
               (0.9, 0.7, 0.1), material=288, transparency=0.3)

    w.close_tag("Item")  # Close Workspace


def _write_destructible(w, name, pos, shape, color, hp):
    """Write a destructible Part with a DestructibleId StringValue child."""
    ref = next_ref()
    class_name = "Part"
    if shape == "Wedge":
        class_name = "WedgePart"

    size = (3, 4, 3)
    if shape == "Block":
        size = (4, 4, 4)
    elif shape == "Cylinder":
        size = (3, 4, 3)
    elif shape == "Wedge":
        size = (3, 5, 3)

    material = 272  # SmoothPlastic
    if shape == "Block":
        material = 512  # Wood

    w.open_tag("Item", {"class": class_name, "referent": ref})
    w.open_tag("Properties")
    write_string_prop(w, "Name", name)
    write_bool_prop(w, "Anchored", True)
    write_bool_prop(w, "CanCollide", True)
    write_cframe_prop(w, "CFrame", pos[0], pos[1], pos[2])
    write_vector3_prop(w, "size", size[0], size[1], size[2])
    write_color3uint8_prop(w, "Color3uint8", color[0], color[1], color[2])
    write_token_prop(w, "Material", material)
    if shape == "Ball":
        write_token_prop(w, "shape", 0)
    elif shape == "Cylinder":
        write_token_prop(w, "shape", 1)
    w.close_tag("Properties")

    # DestructibleId StringValue child
    id_ref = next_ref()
    w.open_tag("Item", {"class": "StringValue", "referent": id_ref})
    w.open_tag("Properties")
    write_string_prop(w, "Name", "DestructibleId")
    write_string_prop(w, "Value", "{}_{}".format(name, ref))
    w.close_tag("Properties")
    w.close_tag("Item")

    # IntValue for HP tracking (optional for server, but useful reference)
    hp_ref = next_ref()
    w.open_tag("Item", {"class": "IntValue", "referent": hp_ref})
    w.open_tag("Properties")
    write_string_prop(w, "Name", "HP")
    write_int_prop(w, "Value", hp)
    w.close_tag("Properties")
    w.close_tag("Item")

    # MaxHP IntValue
    maxhp_ref = next_ref()
    w.open_tag("Item", {"class": "IntValue", "referent": maxhp_ref})
    w.open_tag("Properties")
    write_string_prop(w, "Name", "MaxHP")
    write_int_prop(w, "Value", hp)
    w.close_tag("Properties")
    w.close_tag("Item")

    w.close_tag("Item")  # Close destructible Part


def build_lighting(w):
    """Build Lighting service with post-processing effects."""
    ref = next_ref()
    w.open_tag("Item", {"class": "Lighting", "referent": ref})
    w.open_tag("Properties")
    write_string_prop(w, "Name", "Lighting")
    write_color3_prop(w, "Ambient", 0.5, 0.5, 0.6)
    write_color3_prop(w, "OutdoorAmbient", 0.7, 0.7, 0.75)
    write_float_prop(w, "Brightness", 2)
    write_float_prop(w, "ClockTime", 14)
    write_float_prop(w, "GeographicLatitude", 41.7)
    w.close_tag("Properties")

    # ColorCorrectionEffect
    begin_item(w, "ColorCorrectionEffect", "ColorCorrection",
               lambda wr: (
                   write_float_prop(wr, "Brightness", 0.05),
                   write_float_prop(wr, "Contrast", 0.1),
                   write_float_prop(wr, "Saturation", 0.2),
               ))
    w.close_tag("Item")

    # Atmosphere
    begin_item(w, "Atmosphere", "Atmosphere",
               lambda wr: (
                   write_float_prop(wr, "Density", 0.3),
                   write_float_prop(wr, "Offset", 0.25),
               ))
    w.close_tag("Item")

    # BloomEffect
    begin_item(w, "BloomEffect", "Bloom",
               lambda wr: (
                   write_float_prop(wr, "Intensity", 0.4),
                   write_float_prop(wr, "Size", 24),
                   write_float_prop(wr, "Threshold", 0.9),
               ))
    w.close_tag("Item")

    w.close_tag("Item")  # Close Lighting


def build_replicated_storage(w):
    """Build ReplicatedStorage with shared modules and remotes."""
    begin_item(w, "ReplicatedStorage", "ReplicatedStorage")

    # Shared folder with ModuleScripts
    write_folder(w, "Shared", has_children=True)
    shared_modules = ["Config", "PetData", "ZoneData", "CampaignData"]
    for mod_name in shared_modules:
        filepath = os.path.join(SRC_DIR, "ReplicatedStorage", "Shared",
                                "{}.lua".format(mod_name))
        source = read_source(filepath)
        write_script_item(w, "ModuleScript", mod_name, source)
    w.close_tag("Item")  # Close Shared folder

    # Remotes folder with RemoteEvents and RemoteFunctions
    write_folder(w, "Remotes", has_children=True)

    # All RemoteEvents from Main.server.lua
    remote_events = [
        "CurrencyUpdated",
        "PetInventoryUpdated",
        "PetEquipped",
        "PetUnequipped",
        "ZoneUnlocked",
        "DestructibleDamaged",
        "DestructibleDestroyed",
        "EggHatchStart",
        "EggHatchResult",
        "CampaignBattleUpdate",
        "CampaignVictory",
        "CampaignDefeat",
        "UpgradeUpdated",
        "CollectCurrency",
    ]
    for event_name in remote_events:
        write_item_simple(w, "RemoteEvent", event_name)

    # All RemoteFunctions from Main.server.lua
    remote_functions = [
        "HatchEgg",
        "EquipPet",
        "UnequipPet",
        "DeletePet",
        "DeletePets",
        "UnlockZone",
        "PurchaseUpgrade",
        "GetPlayerData",
        "StartCampaignLevel",
        "DeployPetInCampaign",
        "AttackDestructible",
    ]
    for func_name in remote_functions:
        write_item_simple(w, "RemoteFunction", func_name)

    w.close_tag("Item")  # Close Remotes folder

    w.close_tag("Item")  # Close ReplicatedStorage


def build_server_script_service(w):
    """Build ServerScriptService with server scripts.
    
    Hierarchy: ServerScriptService > Server (Folder) > Main (Script) + Services (Folder)
    Main.server.lua uses: require(script.Parent.Services.DataService)
    So script.Parent = Server folder, Services is a sibling child of Server folder.
    """
    begin_item(w, "ServerScriptService", "ServerScriptService")

    # Server folder
    write_folder(w, "Server", has_children=True)

    # Main.server.lua as a Script (sibling to Services folder)
    main_path = os.path.join(SRC_DIR, "ServerScriptService", "Server",
                             "Main.server.lua")
    main_source = read_source(main_path)
    write_script_item(w, "Script", "Main", main_source)

    # Services subfolder (sibling to Main script inside Server folder)
    write_folder(w, "Services", has_children=True)
    service_files = [
        "DataService", "CurrencyService", "PetService",
        "UpgradeService", "ZoneService", "CampaignService", "EggService"
    ]
    for svc_name in service_files:
        filepath = os.path.join(SRC_DIR, "ServerScriptService", "Server",
                                "Services", "{}.lua".format(svc_name))
        source = read_source(filepath)
        write_script_item(w, "ModuleScript", svc_name, source)
    w.close_tag("Item")  # Close Services folder

    w.close_tag("Item")  # Close Server folder

    w.close_tag("Item")  # Close ServerScriptService


def build_starter_player(w):
    """Build StarterPlayer with StarterPlayerScripts containing client code.
    
    Hierarchy: StarterPlayer > StarterPlayerScripts > Client (Folder) > Main (LocalScript) + Controllers
    Main.client.lua uses: require(script.Parent:WaitForChild("UIController"))
    So script.Parent = Client folder, controllers are sibling children of Client folder.
    """
    begin_item(w, "StarterPlayer", "StarterPlayer")

    # StarterPlayerScripts
    begin_item(w, "StarterPlayerScripts", "StarterPlayerScripts")

    # Client folder
    write_folder(w, "Client", has_children=True)

    # Main.client.lua as LocalScript (sibling to controller modules)
    main_path = os.path.join(SRC_DIR, "StarterPlayer",
                             "StarterPlayerScripts", "Client",
                             "Main.client.lua")
    main_source = read_source(main_path)
    write_script_item(w, "LocalScript", "Main", main_source)

    # Controller ModuleScripts (siblings to Main in Client folder)
    controller_files = [
        "UIController", "PetController",
        "CampaignController", "EffectsController"
    ]
    for ctrl_name in controller_files:
        filepath = os.path.join(SRC_DIR, "StarterPlayer",
                                "StarterPlayerScripts", "Client",
                                "{}.lua".format(ctrl_name))
        source = read_source(filepath)
        write_script_item(w, "ModuleScript", ctrl_name, source)

    w.close_tag("Item")  # Close Client folder

    w.close_tag("Item")  # Close StarterPlayerScripts

    w.close_tag("Item")  # Close StarterPlayer


def build_starter_gui(w):
    """Build StarterGui service (empty, UI is created via code)."""
    begin_item(w, "StarterGui", "StarterGui",
               lambda wr: write_bool_prop(wr, "ResetPlayerGuiOnSpawn", False))
    w.close_tag("Item")


def build_starter_pack(w):
    """Build StarterPack service (placeholder)."""
    begin_item(w, "StarterPack", "StarterPack")
    w.close_tag("Item")


def build_players(w):
    """Build Players service (placeholder)."""
    begin_item(w, "Players", "Players")
    w.close_tag("Item")


def build_sound_service(w):
    """Build SoundService placeholder."""
    begin_item(w, "SoundService", "SoundService",
               lambda wr: write_bool_prop(wr, "RespectFilteringEnabled", True))
    w.close_tag("Item")


def build_chat(w):
    """Build Chat service placeholder."""
    begin_item(w, "Chat", "Chat")
    w.close_tag("Item")


def build_http_service(w):
    """Build HttpService (needed for GenerateGUID in scripts)."""
    begin_item(w, "HttpService", "HttpService",
               lambda wr: write_bool_prop(wr, "HttpEnabled", True))
    w.close_tag("Item")


def main():
    """Generate the BATTLE_PETS.rbxlx place file."""
    print("Generating BATTLE_PETS.rbxlx from source tree: {}".format(SRC_DIR))

    if not os.path.isdir(SRC_DIR):
        print("ERROR: Source directory not found: {}".format(SRC_DIR), file=sys.stderr)
        sys.exit(1)

    w = XMLWriter()

    # XML declaration
    w.raw('<?xml version="1.0" encoding="utf-8"?>')

    # Root roblox element with proper attributes
    w.raw('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">')
    w._indent = 1

    # External references (required by Roblox Studio)
    w.text_element("External", "null")
    w.text_element("External", "nil")

    # Build all top-level services/containers
    build_workspace(w)
    build_lighting(w)
    build_replicated_storage(w)
    build_server_script_service(w)
    build_starter_player(w)
    build_starter_gui(w)
    build_starter_pack(w)
    build_players(w)
    build_sound_service(w)
    build_chat(w)
    build_http_service(w)

    w._indent = 0
    w.raw('</roblox>')

    # Write output
    xml_content = w.result()
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        f.write(xml_content)

    # Report stats
    file_size = os.path.getsize(OUTPUT_FILE)
    item_count = xml_content.count('<Item ')
    script_count = xml_content.count('ProtectedString')
    print("Generated: {}".format(OUTPUT_FILE))
    print("  File size: {:,} bytes".format(file_size))
    print("  Total items: {}".format(item_count))
    print("  Scripts with source: {}".format(script_count))
    print("Done!")


if __name__ == "__main__":
    main()
