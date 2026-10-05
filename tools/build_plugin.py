#!/usr/bin/env python3
"""Builds the plugin from src/ without needing Rojo.

Two files are written to dist/:
  TouchPeak.rbxmx  the plugin as a model: drop it into Studio's Plugins folder,
                   or insert it into a place with "Insert from File...".
  TouchPeak.rbxlx  a place with the plugin already laid out in ServerStorage,
                   ready to edit in Studio and publish with "Publish as Plugin...".

The layout matches `rojo build default.project.json`:
  src/init.server.luau  -> Script "TouchPeak" (the plugin entry point)
  src/<Name>.luau       -> ModuleScript <Name>
  src/<Folder>/         -> Folder <Folder>

Usage:
  python3 tools/build_plugin.py            # write both files to dist/
  python3 tools/build_plugin.py --check    # fail if dist/ is out of date
  python3 tools/build_plugin.py --output "%LOCALAPPDATA%/Roblox/Plugins/TouchPeak.rbxmx"
      (a path ending in .rbxlx gets the place, anything else the model)
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
DIST = ROOT / "dist"
PLUGIN_NAME = "TouchPeak"
DEFAULT_OUTPUTS = [DIST / f"{PLUGIN_NAME}.rbxmx", DIST / f"{PLUGIN_NAME}.rbxlx"]


class Builder:
    def __init__(self) -> None:
        self.next_ref = 0
        self.lines: list[str] = []

    def ref(self) -> str:
        value = f"RBX{self.next_ref}"
        self.next_ref += 1
        return value

    def emit(self, depth: int, text: str) -> None:
        self.lines.append("\t" * depth + text)

    def item(self, depth: int, class_name: str, name: str, source: str | None, children) -> None:
        self.emit(depth, f'<Item class="{class_name}" referent="{self.ref()}">')
        self.emit(depth + 1, "<Properties>")
        self.emit(depth + 2, f'<string name="Name">{escape(name)}</string>')
        if source is not None:
            # "]]>" cannot appear inside CDATA; split it across two sections.
            safe = source.replace("]]>", "]]]]><![CDATA[>")
            self.lines.append("\t" * (depth + 2) + f'<ProtectedString name="Source"><![CDATA[{safe}]]></ProtectedString>')
        self.emit(depth + 1, "</Properties>")
        for child in children:
            child(depth + 1)
        self.emit(depth, "</Item>")


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def folder_children(builder: Builder, directory: Path):
    children = []
    for entry in sorted(directory.iterdir(), key=lambda p: p.name):
        if entry.is_dir():
            children.append(lambda depth, entry=entry: builder.item(
                depth, "Folder", entry.name, None, folder_children(builder, entry)))
        elif entry.suffix == ".luau" and not entry.name.startswith("init."):
            children.append(lambda depth, entry=entry: builder.item(
                depth, "ModuleScript", entry.stem, read(entry), []))
    return children


def build(place: bool) -> str:
    builder = Builder()
    builder.lines.append(
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
    )

    def plugin(depth: int) -> None:
        builder.item(depth, "Script", PLUGIN_NAME, read(SRC / "init.server.luau"), folder_children(builder, SRC))

    if place:
        # Scripts in ServerStorage never run, so the place is a safe home for the source.
        builder.item(1, "ServerStorage", "ServerStorage", None, [plugin])
    else:
        plugin(1)
    builder.lines.append("</roblox>")
    return "\n".join(builder.lines) + "\n"


def content_for(path: Path) -> str:
    return build(place=path.suffix.lower() == ".rbxlx")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output", type=Path, help="write only this file (.rbxlx = place, otherwise model)")
    parser.add_argument("--check", action="store_true", help="verify the output is up to date")
    args = parser.parse_args()

    outputs = DEFAULT_OUTPUTS
    if args.output:
        outputs = [Path(os.path.expandvars(str(args.output))).expanduser()]

    if args.check:
        stale = [p for p in outputs if not p.exists() or p.read_text(encoding="utf-8") != content_for(p)]
        for path in stale:
            print(f"{path} is out of date; run python3 tools/build_plugin.py", file=sys.stderr)
        if not stale:
            print("dist/ is up to date")
        return 1 if stale else 0

    for path in outputs:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content_for(path), encoding="utf-8", newline="\n")
        print(f"Wrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
