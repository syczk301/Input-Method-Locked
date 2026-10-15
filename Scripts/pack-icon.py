"""Pack PNG representations into ICNS without depending on iconutil's decoder."""
from pathlib import Path
from struct import pack, unpack
import sys

iconset, output = map(Path, sys.argv[1:3])
representations = {
    "icp4": ("icon_16x16.png", 16),
    "icp5": ("icon_32x32.png", 32),
    "ic07": ("icon_128x128.png", 128),
    "ic08": ("icon_256x256.png", 256),
    "ic09": ("icon_512x512.png", 512),
    "ic10": ("icon_512x512@2x.png", 1024),
    "ic11": ("icon_16x16@2x.png", 32),
    "ic12": ("icon_32x32@2x.png", 64),
    "ic13": ("icon_128x128@2x.png", 256),
    "ic14": ("icon_256x256@2x.png", 512),
}
chunks = []
for kind, (name, size) in representations.items():
    data = (iconset / name).read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", name
    assert unpack(">II", data[16:24]) == (size, size), name
    chunks.append(kind.encode("ascii") + pack(">I", len(data) + 8) + data)
payload = b"".join(chunks)
output.write_bytes(b"icns" + pack(">I", len(payload) + 8) + payload)
