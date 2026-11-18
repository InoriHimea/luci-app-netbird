#!/usr/bin/env python3
"""Stage the local package for a Linux SDK without Windows text/mode leakage."""
import argparse
import hashlib
import io
from pathlib import Path
import tarfile


def build(package: Path, output: Path) -> None:
    if output.resolve().is_relative_to(package.resolve()):
        raise ValueError("output must be outside the package source")
    paths = [package, *sorted(package.rglob("*"))]
    with tarfile.open(output, "w") as archive:
        for path in paths:
            if path.is_symlink():
                raise ValueError(f"unexpected source symlink: {path}")
            entry = tarfile.TarInfo(path.relative_to(package.parent).as_posix())
            entry.uid = entry.gid = entry.mtime = 0
            entry.uname = entry.gname = "root"
            if path.is_dir():
                entry.type = tarfile.DIRTYPE
                entry.mode = 0o755
                archive.addfile(entry)
            elif path.is_file():
                content = path.read_bytes()
                if b"\0" not in content:
                    try:
                        content.decode("utf-8")
                    except UnicodeDecodeError:
                        pass
                    else:
                        content = content.replace(b"\r\n", b"\n")
                entry.mode = 0o755 if content.startswith(b"#!") else 0o644
                entry.size = len(content)
                archive.addfile(entry, io.BytesIO(content))
            else:
                raise ValueError(f"unexpected source file type: {path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    build(Path(__file__).resolve().parent.parent / "luci-app-netbird", args.output)
    data = args.output.read_bytes()
    print(f"{hashlib.sha256(data).hexdigest()}  {args.output} ({len(data)} bytes)")
