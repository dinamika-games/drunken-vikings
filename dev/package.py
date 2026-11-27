#!/usr/bin/env python3

"""
Package the game for Linux, Windows and macOS into build/, and zip them into dist/.

We export with the presets of export_presets.cfg, and add what Godot does not
export itself: our license, the third-party notices and the licenses of the
third parties (Godot, the models and ONNX Runtime), and, on Windows, the camera
extension next to the executable (see
addons/CameraServerExtension/CameraServerExtension.gdextension): Godot 4.6 has
no camera on Windows, and the game finds no camera there without it.

Godot exits with zero even if it fails to build the C# part, and then writes a
package without it; so we check its output for errors, and that every package
has ONNX Runtime (for both the Apple Silicon and the Intel Macs).

With --upload <tag>, the zips are uploaded to the GitHub release of the tag
(with the gh CLI); the tag must be v<the version of project.godot>.

You need the export templates of Godot 4.6.2 (.NET); see CONTRIBUTING.md,
"Packaging".
"""

import argparse
import os
import pathlib
import re
import shutil
import subprocess
import sys
import zipfile
from typing import Dict, List, Optional

REPO_ROOT = pathlib.Path(os.path.realpath(__file__)).parent.parent

BUILD_DIR = REPO_ROOT / "build"

DIST_DIR = REPO_ROOT / "dist"

SLUG = "drunken-vikings"

EXTENSION_DIR = REPO_ROOT / "addons" / "CameraServerExtension"

# NOTE (mristin):
# The export preset and the path of the export in build/; macOS exports an
# archive, the others a folder.
PLATFORMS = {
    "linux": ("Linux", "linux/drunken-vikings.x86_64"),
    "windows": ("Windows", "windows/drunken-vikings.exe"),
    "macos": ("macOS", "macos/drunken-vikings.zip"),
}

# NOTE (mristin):
# The models whose licenses go into the packages, by their directory in
# scenes/vision/.
MODELS = ["rtmo", "rtmpose", "yolox"]

# NOTE (mristin):
# The libraries of ONNX Runtime which every package must have, by platform
# (the macOS app is universal).
ONNX_RUNTIME = {
    "linux": ["data_DrunkenVikings_linuxbsd_x86_64/libonnxruntime.so"],
    "windows": ["data_DrunkenVikings_windows_x86_64/onnxruntime.dll"],
    "macos": [
        "data_DrunkenVikings_macos_arm64/libonnxruntime.dylib",
        "data_DrunkenVikings_macos_x86_64/libonnxruntime.dylib",
    ],
}

# NOTE (mristin):
# The errors in Godot's output which do not break an export.
HARMLESS_ERRORS = re.compile(r"leaked|still in use|Pages in use|Unreferenced static")


def find_godot(explicit: Optional[str]) -> Optional[str]:
    """Find the Godot 4.6 .NET executable in the arguments, environment or path."""
    if explicit is not None:
        return explicit

    from_env = os.environ.get("GODOT")
    if from_env:
        return from_env

    for name in ("godot", "godot4", "godot-mono", "godot4-mono"):
        found = shutil.which(name)
        if found is not None:
            return found

    return None


def run(cmd: List[str]) -> None:
    """Run the command in the repository, and stop on failure."""
    print(f"Executing: {' '.join(cmd)}", flush=True)
    subprocess.run(cmd, cwd=REPO_ROOT, check=True)


def export(godot: str, preset: str, output: pathlib.Path) -> None:
    """Export the preset, and stop if Godot reported an error."""
    cmd = [godot, "--headless", "--path", ".", "--export-release", preset, str(output)]
    print(f"Executing: {' '.join(cmd)}", flush=True)
    completed = subprocess.run(
        cmd,
        cwd=REPO_ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=True,
    )
    print(completed.stdout, flush=True)
    errors = [
        line
        for line in completed.stdout.splitlines()
        if re.match(r"^(ERROR|SCRIPT ERROR)", line) and not HARMLESS_ERRORS.search(line)
    ]
    if errors:
        raise RuntimeError(
            f"The export for {preset} reported errors:\n" + "\n".join(errors)
        )


def check_onnx_runtime(platform: str, output: pathlib.Path) -> None:
    """Check that the package has the C# part with ONNX Runtime."""
    if platform == "macos":
        with zipfile.ZipFile(output) as zip_file:
            names = zip_file.namelist()
        for library in ONNX_RUNTIME[platform]:
            if not any(name.endswith(library) for name in names):
                raise RuntimeError(f"The macOS package misses {library}.")
    else:
        for library in ONNX_RUNTIME[platform]:
            if not (output.parent / library).is_file():
                raise RuntimeError(f"The {platform} package misses {library}.")


def onnx_runtime_license() -> pathlib.Path:
    """Find the license of ONNX Runtime in the NuGet cache, at the version of the game."""
    project = (REPO_ROOT / "DrunkenVikings.csproj").read_text(encoding="utf-8")
    match = re.search(
        r'Include="Microsoft\.ML\.OnnxRuntime" Version="([^"]+)"', project
    )
    if match is None:
        raise RuntimeError("DrunkenVikings.csproj references no ONNX Runtime.")
    packages = pathlib.Path(
        os.environ.get("NUGET_PACKAGES", pathlib.Path.home() / ".nuget" / "packages")
    )
    return packages / "microsoft.ml.onnxruntime" / match.group(1) / "LICENSE"


def notices() -> Dict[str, pathlib.Path]:
    """Map each license file of a package (its path in the package) to its source."""
    result = {
        "LICENSE": REPO_ROOT / "LICENSE",
        "THIRD_PARTY_NOTICES.md": REPO_ROOT / "THIRD_PARTY_NOTICES.md",
    }
    for path in sorted((REPO_ROOT / "licenses").rglob("*")):
        if path.is_file() and path.name != ".gdignore":
            result[path.relative_to(REPO_ROOT).as_posix()] = path
    for model in MODELS:
        result[f"licenses/models/{model}-LICENSE"] = (
            REPO_ROOT / "scenes" / "vision" / model / "model" / "LICENSE"
        )
    result["licenses/onnxruntime/LICENSE"] = onnx_runtime_license()
    for name, source in result.items():
        if not source.is_file():
            raise RuntimeError(f"The license {name} is missing: {source}")
    return result


def copy_licenses(directory: pathlib.Path) -> None:
    """Copy our license and the third-party licenses into the package folder."""
    for name, source in notices().items():
        target = directory / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)


def add_camera_extension(directory: pathlib.Path) -> None:
    """Put the camera extension next to the Windows executable, with its license."""
    for name in (
        "CameraServerExtension.gdextension",
        "libcameraserver-extension.windows.dll",
    ):
        shutil.copy2(EXTENSION_DIR / name, directory / name)

    license_dir = directory / "licenses" / "camera-server-extension"
    license_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(EXTENSION_DIR / "LICENSE", license_dir / "LICENSE")


def add_licenses_to_archive(archive: pathlib.Path) -> None:
    """Add our license and the third-party licenses to the macOS archive, beside the app."""
    with zipfile.ZipFile(archive, "a", compression=zipfile.ZIP_DEFLATED) as zip_file:
        existing = set(zip_file.namelist())
        for name, source in notices().items():
            if name not in existing:
                zip_file.write(source, name)


def read_version() -> str:
    """Read the version of the game from project.godot."""
    project = (REPO_ROOT / "project.godot").read_text(encoding="utf-8")
    match = re.search(r'^config/version="([^"]+)"', project, flags=re.MULTILINE)
    if match is None:
        raise RuntimeError("project.godot sets no config/version.")
    return match.group(1)


def zip_package(platform: str, output: pathlib.Path, version: str) -> pathlib.Path:
    """Zip the package into dist/; macOS is already exported as an archive."""
    DIST_DIR.mkdir(exist_ok=True)
    archive = DIST_DIR / f"{SLUG}-{version}-{platform}.zip"
    if platform == "macos":
        shutil.copy2(output, archive)
        return archive

    archive.unlink(missing_ok=True)
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as zip_file:
        for path in sorted(output.parent.rglob("*")):
            if path.is_file():
                # NOTE (mristin):
                # The zip keeps the executable bit of the Linux executable.
                zip_file.write(
                    path, f"{SLUG}/{path.relative_to(output.parent).as_posix()}"
                )
    return archive


def main() -> int:
    """Execute the main routine."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--platforms",
        nargs="+",
        choices=sorted(PLATFORMS),
        default=sorted(PLATFORMS),
        help="Which platforms to package (default: all)",
    )
    parser.add_argument(
        "--godot", help="The Godot executable (default: $GODOT or the path)"
    )
    parser.add_argument(
        "--upload",
        metavar="TAG",
        help="Upload the zips to the GitHub release of this tag (v<version>)",
    )
    args = parser.parse_args()

    try:
        version = read_version()
    except RuntimeError as exception:
        print(str(exception), file=sys.stderr)
        return 1

    if args.upload is not None and args.upload != f"v{version}":
        print(
            f"The tag {args.upload} does not match the version {version} "
            f"of project.godot; expected v{version}.",
            file=sys.stderr,
        )
        return 1

    godot = find_godot(args.godot)
    if godot is None:
        print("Could not find Godot; set GODOT or pass --godot.", file=sys.stderr)
        return 1

    # NOTE (mristin):
    # The .gdignore hides the packages from Godot, which would otherwise import
    # them, and try to load the camera extension of the Windows package on
    # every platform, and fail.
    BUILD_DIR.mkdir(exist_ok=True)
    (BUILD_DIR / ".gdignore").touch()

    try:
        run(["dotnet", "build", "DrunkenVikings.sln", "-c", "Release"])

        archives: List[pathlib.Path] = []
        for platform in args.platforms:
            preset, relative = PLATFORMS[platform]
            output = BUILD_DIR / relative
            # NOTE (mristin):
            # We start from an empty folder so that no stale file of an earlier
            # export ends up in the zip.
            shutil.rmtree(output.parent, ignore_errors=True)
            output.parent.mkdir(parents=True, exist_ok=True)
            export(godot, preset, output)
            check_onnx_runtime(platform, output)

            if platform == "macos":
                add_licenses_to_archive(output)
            else:
                copy_licenses(output.parent)

            if platform == "windows":
                add_camera_extension(output.parent)

            archive = zip_package(platform, output, version)
            archives.append(archive)
            print(
                f"Packaged {preset} into {archive.relative_to(REPO_ROOT)}.", flush=True
            )

        if args.upload is not None:
            run(
                ["gh", "release", "upload", args.upload]
                + [str(archive) for archive in archives]
                + ["--clobber"]
            )
    except subprocess.CalledProcessError as exception:
        print(f"Failed with exit code {exception.returncode}.", file=sys.stderr)
        return 1
    except RuntimeError as exception:
        print(str(exception), file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
