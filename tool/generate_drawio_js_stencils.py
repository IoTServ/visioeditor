#!/usr/bin/env python3
"""Generate native stencil data from draw.io JavaScript Canvas shapes."""

from __future__ import annotations

import argparse
import base64
import gzip
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_WEBAPP = ROOT / "third_party/drawio/src/main/webapp"
DEFAULT_OUTPUT = (
    ROOT / "packages/vsdx/lib/src/generated/drawio_js_stencil_data.g.dart"
)
CAPTURE = ROOT / "tool/capture_drawio_js_stencils.js"


def dart_string(value: str) -> str:
    escaped = (
        value.replace("\\", "\\\\")
        .replace("'", "\\'")
        .replace("$", "\\$")
        .replace("\r", "\\r")
        .replace("\n", "\\n")
    )
    return f"'{escaped}'"


def catalog_name(value: str | None) -> str:
    return " ".join((value or "Unnamed Shape").split()) or "Unnamed Shape"


def wrapped_string(value: str, width: int = 100) -> list[str]:
    return [
        dart_string(value[index : index + width])
        for index in range(0, len(value), width)
    ]


def generate(webapp: Path, output: Path) -> tuple[int, int]:
    captured = json.loads(
        subprocess.check_output(["node", str(CAPTURE), str(webapp)], text=True)
    )
    if captured["shapeLoadErrors"]:
        raise RuntimeError(f"draw.io shape load errors: {captured['shapeLoadErrors']}")

    records: list[tuple[str, str, list[str], str]] = []
    shape_count = 0
    for library in captured["libraries"]:
        xml = library["xml"]
        names = [catalog_name(shape.get("name")) for shape in ET.fromstring(xml)]
        if not names:
            continue
        payload = base64.b64encode(
            gzip.compress(xml.encode("utf-8"), compresslevel=9, mtime=0)
        ).decode("ascii")
        records.append((library["sourcePath"], library["groupName"], names, payload))
        shape_count += len(names)

    lines = [
        "// GENERATED CODE - DO NOT MODIFY BY HAND.",
        "// Source: draw.io 30.3.6 JavaScript Canvas shape catalog.",
        "// Contains Apache-2.0 draw.io-derived geometry; attribution is in NOTICE.",
        "// Regenerate with: python3 tool/generate_drawio_js_stencils.py",
        "part of '../stencils.dart';",
        "",
        "const List<_DrawioXmlLibraryRecord> _drawioJsLibraryRecords =",
        "    <_DrawioXmlLibraryRecord>[",
    ]
    for source_path, group_name, names, payload in records:
        lines.extend(
            [
                "  _DrawioXmlLibraryRecord(",
                f"    sourcePath: {dart_string(source_path)},",
                f"    groupName: {dart_string(group_name)},",
                "    shapeNames: <String>[",
            ]
        )
        lines.extend(f"      {dart_string(name)}," for name in names)
        lines.extend(["    ],", "    encodedXml:"])
        lines.extend(f"        {chunk}" for chunk in wrapped_string(payload))
        lines.extend(["    ,", "  ),"])
    lines.extend(["];", ""])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines), encoding="utf-8")
    return len(records), shape_count


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--webapp", type=Path, default=DEFAULT_WEBAPP)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    libraries, shapes = generate(args.webapp, args.output)
    print(f"generated {libraries} JavaScript libraries / {shapes} shapes")


if __name__ == "__main__":
    main()
