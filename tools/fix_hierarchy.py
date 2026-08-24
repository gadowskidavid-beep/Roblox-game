#!/usr/bin/env python3
"""
Fix BATTLE_PETS.rbxlx hierarchy by removing intermediate folders.

This script:
1. Removes the "Server" folder wrapper in ServerScriptService, moving its children up one level
2. Removes the "Client" folder wrapper in StarterPlayerScripts, moving its children up one level

This ensures Scripts/LocalScripts are direct children of their service containers,
which is required for Roblox Studio to auto-run them.

Uses text-based manipulation to preserve CDATA sections and formatting.
"""

import re
import sys


def find_folder_boundaries(lines, start_line_0indexed):
    """
    Given the 0-indexed start line of a <Item class="Folder"...> tag,
    find where it closes by tracking nested Item open/close tags.
    Returns the 0-indexed line number of the closing </Item> tag.
    """
    depth = 0
    for i in range(start_line_0indexed, len(lines)):
        line = lines[i]
        opens = line.count('<Item ')
        closes = line.count('</Item>')
        depth += opens - closes
        if depth == 0:
            return i
    return None


def get_indent(line):
    """Get the leading whitespace of a line."""
    return len(line) - len(line.lstrip())


def remove_folder_wrapper(lines, folder_start, folder_end):
    """
    Remove the folder Item element (opening tag, Properties, closing tag)
    while keeping all nested Item children, de-indented by one tab level.
    
    Returns the modified list of lines.
    """
    # The folder structure is:
    # folder_start:   <Item class="Folder" ...>
    # folder_start+1: <Properties>
    # folder_start+2:   <string name="Name">...</string>
    # folder_start+3: </Properties>
    # ... children ...
    # folder_end:     </Item>
    
    # Find where Properties ends (after the folder name)
    props_end = None
    for i in range(folder_start + 1, folder_end):
        if '</Properties>' in lines[i]:
            props_end = i
            break
    
    if props_end is None:
        print(f"ERROR: Could not find </Properties> for folder starting at line {folder_start + 1}")
        sys.exit(1)
    
    # The children are from props_end+1 to folder_end-1
    # We need to de-indent them by one tab level
    
    # Determine the indent of the folder itself
    folder_indent = get_indent(lines[folder_start])
    
    # Build the new lines:
    # - Everything before the folder start: keep as-is
    # - The folder's children (de-indented by one tab): insert them
    # - Everything after folder_end: keep as-is
    
    before = lines[:folder_start]
    children = lines[props_end + 1:folder_end]
    after = lines[folder_end + 1:]
    
    # De-indent children by one tab
    dedented_children = []
    for child_line in children:
        if child_line.startswith('\t'):
            # Remove one tab level
            dedented_children.append(child_line[1:])
        elif child_line.startswith('    '):
            # Remove one indent level (4 spaces)
            dedented_children.append(child_line[4:])
        else:
            dedented_children.append(child_line)
    
    return before + dedented_children + after


def main():
    input_file = 'BATTLE_PETS.rbxlx'
    
    print(f"Reading {input_file}...")
    with open(input_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    print(f"Total lines: {len(lines)}")
    
    # --- Fix 1: Remove "Server" folder in ServerScriptService ---
    print("\nFixing ServerScriptService (removing 'Server' folder)...")
    
    # Find the Server folder
    server_folder_line = None
    for i, line in enumerate(lines):
        if 'class="Folder"' in line:
            # Check if next lines have Name = "Server"
            if i + 2 < len(lines) and '>Server<' in lines[i + 2]:
                server_folder_line = i
                break
    
    if server_folder_line is None:
        print("ERROR: Could not find Server folder!")
        sys.exit(1)
    
    server_folder_end = find_folder_boundaries(lines, server_folder_line)
    print(f"  Server folder: lines {server_folder_line + 1} to {server_folder_end + 1}")
    
    lines = remove_folder_wrapper(lines, server_folder_line, server_folder_end)
    
    # --- Fix 2: Remove "Client" folder in StarterPlayerScripts ---
    print("\nFixing StarterPlayerScripts (removing 'Client' folder)...")
    
    # Find the Client folder (search again since line numbers shifted)
    client_folder_line = None
    for i, line in enumerate(lines):
        if 'class="Folder"' in line:
            # Check if next lines have Name = "Client"
            if i + 2 < len(lines) and '>Client<' in lines[i + 2]:
                client_folder_line = i
                break
    
    if client_folder_line is None:
        print("ERROR: Could not find Client folder!")
        sys.exit(1)
    
    client_folder_end = find_folder_boundaries(lines, client_folder_line)
    print(f"  Client folder: lines {client_folder_line + 1} to {client_folder_end + 1}")
    
    lines = remove_folder_wrapper(lines, client_folder_line, client_folder_end)
    
    # Write back
    print(f"\nWriting {input_file}...")
    with open(input_file, 'w', encoding='utf-8') as f:
        f.writelines(lines)
    
    print(f"Total lines after: {len(lines)}")
    print("Done!")


if __name__ == '__main__':
    main()
