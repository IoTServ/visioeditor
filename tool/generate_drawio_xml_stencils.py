#!/usr/bin/env python3
"""Generate the compressed draw.io XML stencil catalog used by vsdx.

Run from the repository root. The input is the local draw.io source checkout;
the generated Dart part is self-contained, so builds do not depend on that
checkout being present.
"""

from __future__ import annotations

import argparse
import base64
import gzip
from pathlib import Path
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "third_party/drawio/src/main/webapp/stencils"
DEFAULT_OUTPUT = (
    ROOT
    / "packages/vsdx/lib/src/generated/drawio_xml_stencil_data.g.dart"
)

ACRONYMS = {
    "apc": "APC",
    "aws": "AWS",
    "aws2": "AWS 2",
    "aws3": "AWS 3",
    "aws3d": "AWS 3D",
    "aws4": "AWS 4",
    "cisco": "Cisco",
    "gcp": "GCP",
    "gcp2": "GCP 2",
    "gcp3": "GCP 3",
    "gmdl": "Google Material Design",
    "hpe": "HPE",
    "ibm": "IBM",
    "iec417": "IEC 417",
    "ios7": "iOS 7",
    "mscae": "Microsoft Cloud and Enterprise",
    "pid": "P&ID",
    "plc": "PLC",
    "vvd": "VMware Validated Design",
}


def title_component(value: str) -> str:
    lower = value.lower()
    if lower in ACRONYMS:
        return ACRONYMS[lower]
    words = value.replace("-", "_").split("_")
    return " ".join(ACRONYMS.get(word.lower(), word.capitalize()) for word in words)


def group_name(relative: Path) -> str:
    parts = list(relative.with_suffix("").parts)
    return "Draw.io / " + " / ".join(title_component(part) for part in parts)


def dart_string(value: str) -> str:
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$") + "'"


def wrapped_string(value: str, width: int = 100) -> list[str]:
    return [dart_string(value[i : i + width]) for i in range(0, len(value), width)]


def generate(source: Path, output: Path) -> tuple[int, int, int]:
    files = sorted(source.rglob("*.xml"))
    records: list[tuple[Path, list[str], str]] = []
    shape_count = 0
    for path in files:
        root = ET.parse(path).getroot()
        names = [(shape.get("name") or "Unnamed Shape").strip() for shape in root.findall("shape")]
        if not names:
            continue
        payload = base64.b64encode(
            gzip.compress(path.read_bytes(), compresslevel=9, mtime=0)
        ).decode("ascii")
        records.append((path.relative_to(source), names, payload))
        shape_count += len(names)

    lines = [
        "// GENERATED CODE - DO NOT MODIFY BY HAND.",
        "// Source: draw.io 30.3.6 stencil XML catalog.",
        "// Contains Apache-2.0 draw.io data; attribution is in NOTICE.",
        "// Regenerate with: python3 tool/generate_drawio_xml_stencils.py",
        "part of '../stencils.dart';",
        "",
        "const List<_DrawioXmlLibraryRecord> _drawioXmlLibraryRecords =",
        "    <_DrawioXmlLibraryRecord>[",
    ]
    for relative, names, payload in records:
        lines.extend(
            [
                "  _DrawioXmlLibraryRecord(",
                f"    sourcePath: {dart_string('stencils/' + relative.as_posix())},",
                f"    groupName: {dart_string(group_name(relative))},",
                "    shapeNames: <String>[",
            ]
        )
        lines.extend(f"      {dart_string(name)}," for name in names)
        lines.extend(["    ],", "    encodedXml:"])
        chunks = wrapped_string(payload)
        lines.extend(f"        {chunk}" for chunk in chunks)
        lines.extend(["    ,", "  ),"])
    lines.extend(["];", ""])

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines), encoding="utf-8")
    return len(files), len(records), shape_count


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    files, libraries, shapes = generate(args.source, args.output)
    print(f"generated {libraries} libraries / {shapes} shapes from {files} XML files")


if __name__ == "__main__":
    main()
