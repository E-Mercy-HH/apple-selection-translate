#!/usr/bin/env python3
"""Package the generated PNG icon sizes into a macOS .icns resource."""

from pathlib import Path
from struct import pack, unpack_from
import sys


# The type codes distinguish regular and Retina representations of each size.
ICONS = (
    (b"icp4", "icon_16x16.png", 16),
    (b"ic11", "icon_16x16@2x.png", 32),
    (b"icp5", "icon_32x32.png", 32),
    (b"ic12", "icon_32x32@2x.png", 64),
    (b"ic07", "icon_128x128.png", 128),
    (b"ic13", "icon_128x128@2x.png", 256),
    (b"ic08", "icon_256x256.png", 256),
    (b"ic14", "icon_256x256@2x.png", 512),
    (b"ic09", "icon_512x512.png", 512),
    (b"ic10", "icon_512x512@2x.png", 1024),
)
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("Usage: pack_icns.py ICONSET_DIRECTORY OUTPUT.icns")

    iconset = Path(sys.argv[1])
    output = Path(sys.argv[2])
    chunks = []
    table_of_contents = []

    for kind, filename, expected_size in ICONS:
        png = (iconset / filename).read_bytes()
        if not png.startswith(PNG_SIGNATURE) or png[12:16] != b"IHDR":
            raise ValueError(f"Invalid PNG: {filename}")
        width, height = unpack_from(">II", png, 16)
        if (width, height) != (expected_size, expected_size):
            raise ValueError(f"Wrong dimensions for {filename}: {width}x{height}")

        chunk_size = 8 + len(png)
        chunks.append(kind + pack(">I", chunk_size) + png)
        table_of_contents.append(kind + pack(">I", chunk_size))

    toc_payload = b"".join(table_of_contents)
    toc = b"TOC " + pack(">I", 8 + len(toc_payload)) + toc_payload
    body = toc + b"".join(chunks)
    output.write_bytes(b"icns" + pack(">I", 8 + len(body)) + body)


if __name__ == "__main__":
    main()
