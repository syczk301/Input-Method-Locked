"""Mount a DMG read-only, verify its app and installer link, then detach."""
from pathlib import Path
import hashlib
import os
import subprocess
import sys
import tempfile

dmg, original = map(lambda p: Path(p).resolve(), sys.argv[1:3])

def files(folder):
    return {str(p.relative_to(folder)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in folder.rglob("*") if p.is_file() and not p.is_symlink()}

with tempfile.TemporaryDirectory(prefix="input-method-locked-verify-") as temp:
    mount = Path(temp) / "volume"
    mount.mkdir()
    subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen",
                    "-mountpoint", str(mount), str(dmg)], check=True)
    try:
        app = mount / "Input Method Locked.app"
        assert files(app) == files(original), "Packaged app differs from build"
        assert os.readlink(mount / "Applications") == "/Applications"
        assert (mount / "Read Me.txt").is_file()
        subprocess.run(["codesign", "--verify", "--strict", str(app)], check=True)
        archs = subprocess.check_output(["xcrun", "lipo", "-archs",
            str(app / "Contents/MacOS/InputMethodLocked")], text=True).split()
        assert set(archs) == {"arm64", "x86_64"}, archs
        print("PASS: DMG app hashes, signature, universal architectures and Applications link")
    finally:
        subprocess.run(["hdiutil", "detach", str(mount)], check=True)
