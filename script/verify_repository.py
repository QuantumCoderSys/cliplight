#!/usr/bin/env python3
"""Check public documentation links, PNG exports, versioning, and release inputs."""
from pathlib import Path
import re
import struct

root = Path(__file__).resolve().parent.parent
version = (root / "VERSION").read_text().strip()
assert re.fullmatch(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", version), "Invalid VERSION"
assert f"## [{version}]" in (root / "CHANGELOG.md").read_text(), "Missing changelog entry"
for name in ["README.md", "CONTRIBUTING.md", "SECURITY.md", "RELEASING.md", "packaging/release-notes.md"]:
    file = root / name
    text = file.read_text()
    assert "github.com/OWNER" not in text, f"Unresolved repository owner: {name}"
    for target in re.findall(r"\]\(([^)]+)\)", text) + re.findall(r'(?:src|srcset)="([^"]+)"', text):
        if target.startswith(("https://", "http://", "#", "mailto:")):
            continue
        target = target.split("#")[0]
        assert (file.parent / target).exists(), f"Broken local link: {name}: {target}"
for name in ["light", "dark", "actions", "snippets"]:
    path = root / "docs" / f"showcase-{name}.png"
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", f"Not a PNG: {path.name}"
    width, height = struct.unpack(">II", data[16:24])
    assert (width, height) == (1680, 1460), f"Unexpected export dimensions: {path.name}: {width}x{height}"
for script in ["build_and_run.sh", "check.sh", "make_app.sh", "release.sh"]:
    assert (root / "script" / script).stat().st_mode & 0o111, f"Script isn't executable: {script}"
print(f"Repository verified: version {version}, local links, 4 showcase PNGs, executable scripts.")
