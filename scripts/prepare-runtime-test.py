"""Inventory and back up Home Manager targets without activating anything."""

import json
import os
from pathlib import Path
import sys
import tarfile


def prepare(output: Path) -> None:
    user_dir = Path.home()
    source = Path(
        "/nix/store/qh92xi7g7wrrg3v68ydjy7mbmqbaiy2z-home-manager-generation/home-files"
    ).resolve(strict=True)
    entries = []
    existing = []
    for parent, dirs, files in os.walk(source, followlinks=False):
        leaves = files + [d for d in dirs if (Path(parent) / d).is_symlink()]
        for name in sorted(leaves):
            relative = (Path(parent) / name).relative_to(source)
            target = user_dir / relative
            for ancestor in target.parents:
                if ancestor == user_dir:
                    break
                if ancestor.is_symlink() or (
                    ancestor.exists() and not ancestor.is_dir()
                ):
                    raise RuntimeError(
                        f"Review non-directory/symlink parent: {ancestor}"
                    )
            if os.path.lexists(str(target) + ".before-home-manager"):
                raise RuntimeError(
                    f"Existing Home Manager backup needs review: {target}"
                )
            present = os.path.lexists(target)
            entries.append({"path": str(relative), "existed": present})
            if present:
                existing.append(relative)

    directories = [
        "Desktop",
        "Documents",
        "Downloads",
        "Music",
        "Pictures",
        "Projects",
        "Public",
        "Templates",
        "Videos",
    ]
    manifest = {
        "home_generation": str(source),
        "targets": entries,
        "user_directories": {
            name: os.path.lexists(user_dir / name) for name in directories
        },
    }
    with (output / "home-before.json").open("x") as stream:
        json.dump(manifest, stream, indent=2)
        stream.write("\n")
    # Symlinks are archived as links; their targets are never followed.
    with tarfile.open(output / "home-before.tar", "x", dereference=False) as archive:
        for relative in existing:
            archive.add(user_dir / relative, arcname=str(relative), recursive=True)
    print(
        f"Home preflight: {len(entries)} targets; {len(existing)} existing targets backed up."
    )


if __name__ == "__main__":
    if os.getuid() != 1000 or len(sys.argv) != 2:
        raise SystemExit(
            "Run as the desktop user with one private output-directory argument."
        )
    prepare(Path(sys.argv[1]))
