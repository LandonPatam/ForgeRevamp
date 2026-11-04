#!/usr/bin/env python3
"""Build a self-contained universal Mac app and drag-to-Applications DMG.

Requires JDK 17, .tools/apache-maven-3.9.9, Godot 4.7.2 in .tools/godot,
.tools/godot/macos.zip, and Temurin 17 JRE archives in .tools/downloads.
See docs/macos-build.md for setup and signing limitations.
"""
import argparse
import hashlib
import os
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tarfile
import platform

ROOT = Path(__file__).resolve().parents[2]
DIST = ROOT / "dist"
TOOLS = ROOT / ".tools"
GODOT = Path(os.environ.get("FORGE_GODOT_PATH", TOOLS / "godot/Godot.app/Contents/MacOS/Godot"))


def run(args, *, cwd=ROOT, log=None, timeout=None):
    print("Running:", " ".join(map(str, args)), flush=True)
    if log:
        with (DIST / log).open("w") as stream:
            subprocess.run(list(map(str, args)), cwd=cwd, stdout=stream,
                           stderr=subprocess.STDOUT, check=True, timeout=timeout)
    else:
        subprocess.run(list(map(str, args)), cwd=cwd, check=True, timeout=timeout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--output", default="ForgeUI-macOS")
    args = parser.parse_args()
    if args.output in {"", ".", ".."} or Path(args.output).name != args.output:
        parser.error("--output must be a folder name inside dist")
    stage = DIST / args.output
    if stage.exists():
        parser.error(f"{stage} exists; choose a new --output to preserve it")
    DIST.mkdir(exist_ok=True)
    forge_revision = subprocess.check_output(["git", "-C", "forge", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    if forge_revision != (ROOT / "FORGE_COMMIT").read_text().strip():
        parser.error("Forge must be checked out at FORGE_COMMIT")
    run(["git", "-C", "forge", "apply", "--reverse", "--check", "../forge-patches/netplay-fixes.patch"])
    build_info = {
        "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "source_dirty": bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True)),
        "forge_commit": forge_revision,
        "forge_patch_sha256": hashlib.sha256((ROOT / "forge-patches/netplay-fixes.patch").read_bytes()).hexdigest(),
        "platform": platform.platform(),
        "architectures": ["arm64", "x86_64"],
    }
    maven = TOOLS / "apache-maven-3.9.9/bin/mvn"
    repo = f"-Dmaven.repo.local={TOOLS / 'maven-cache'}"
    if not args.skip_build:
        run([maven, "-B", "-ntp", repo, "-DskipTests", "-Dmaven.javadoc.skip=true",
             "-pl", "forge-gui", "-am", "flatten:flatten", "install"],
            cwd=ROOT / "forge", log="forge-build.log")
        run([maven, "-B", "-ntp", repo, "-f", "bridge/pom.xml", "-DskipTests", "package"],
            log="bridge-build.log")
    run(["java", "-cp", "bridge/target/test-classes:bridge/target/classes:bridge/target/lib/*",
         "forgeui.bridge.BridgeChecks"], log="bridge-checks.log")
    templates = ROOT / "client-godot/.export-templates"
    templates.mkdir(exist_ok=True)
    (templates / ".gdignore").touch()
    if not (templates / "macos.zip").exists():
        shutil.copy2(TOOLS / "godot/macos.zip", templates / "macos.zip")
    artifacts = ROOT / "client-godot/artifacts"
    artifacts.mkdir(exist_ok=True)
    (artifacts / ".gdignore").touch()
    run([GODOT, "--headless", "--path", "client-godot", "--editor", "--import", "--quit"],
        log="godot-import.log")
    exported = DIST / "ForgeUI-macos.zip"
    run([GODOT, "--headless", "--path", "client-godot", "--export-release", "macOS", exported],
        log="godot-export.log")
    stage.mkdir()
    run(["ditto", "-x", "-k", exported, stage])
    exported_apps = list(stage.glob("*.app"))
    if len(exported_apps) != 1:
        raise RuntimeError("Expected one exported macOS app")
    app = stage / "ForgeUI.app"
    if exported_apps[0] != app:
        exported_apps[0].rename(app)
    plist_path = app / "Contents/Info.plist"
    info = plistlib.loads(plist_path.read_bytes())
    original_name = info["CFBundleExecutable"]
    (app / "Contents/MacOS" / original_name).rename(app / "Contents/MacOS/ForgeUI")
    (app / "Contents/Resources" / (original_name + ".pck")).rename(app / "Contents/Resources/ForgeUI.pck")
    info.update(CFBundleExecutable="ForgeUI", CFBundleName="ForgeUI", CFBundleDisplayName="ForgeUI")
    plist_path.write_bytes(plistlib.dumps(info))
    resources = app / "Contents/Resources"
    (resources / "build-info.json").write_text(json.dumps(build_info, indent=2) + "\n")
    (stage / "build-info.json").write_text(json.dumps(build_info, indent=2) + "\n")
    for folder in ("classes", "lib"):
        shutil.copytree(ROOT / f"bridge/target/{folder}", resources / f"service/{folder}")
    shutil.copytree(ROOT / "forge/forge-gui/res", resources / "forge-gui/res",
                    ignore=shutil.ignore_patterns("adventure"))
    for arch in ("arm64", "x86_64"):
        archive = TOOLS / f"downloads/jre-{arch}.tar.gz"
        destination = resources / "runtime" / arch
        destination.mkdir(parents=True)
        # Only extract the official archive's Contents tree, dropping its versioned root.
        with tarfile.open(archive) as bundle:
            for member in bundle.getmembers():
                parts = Path(member.name).parts
                if len(parts) < 2 or parts[1] != "Contents":
                    continue
                member.name = str(Path(*parts[1:]))
                bundle.extract(member, destination, filter="data")
        java = destination / "Contents/Home/bin/java"
        run([java, "-version"]) if arch == "arm64" else None
    licenses = resources / "licenses"
    licenses.mkdir()
    shutil.copy2(ROOT / "forge/LICENSE", licenses / "Forge-GPL-3.txt")
    for name in ("Godot-LICENSE.txt", "Godot-COPYRIGHT.txt"):
        shutil.copy2(TOOLS / "godot" / name, licenses / name)
    shutil.copy2(ROOT / "client-godot/assets/CREDITS.md", licenses / "Asset-credits.md")
    shutil.copytree(ROOT / "client-godot/assets/fonts", licenses / "fonts")
    (stage / "READ ME.txt").write_text(
        "ForgeUI for macOS — Apple Silicon and Intel\n\n"
        "Drag ForgeUI.app onto Applications, then open it there.\n"
        "Godot, Java 17, and the Forge rules engine are included. No separate installs are needed.\n"
        "First launch takes a minute to load the card database. Internet is used for missing card images.\n\n"
        "This private build is ad-hoc signed, without Apple notarization. If macOS blocks it,\n"
        "try opening it, then use System Settings > Privacy & Security > Open Anyway.\n"
        "Only allow a copy you received from a trusted friend.\n\n"
        "Online play requires everyone to use this same build. The host may need to allow\n"
        "incoming connections and forward TCP 36743, or use a shared VPN.\n\n"
        "Forge's GPL license and asset credits are in the app's Contents/Resources/licenses.\n"
        "The accompanying source archive includes the exact Forge and bridge sources, local\n"
        "patches, client sources, and build scripts. Java licensing is included with each runtime.\n",
        encoding="utf-8")
    (stage / "Applications").symlink_to("/Applications")
    # Keep the source for this build with the binary, excluding private history and local caches.
    def source_filter(info):
        parts = Path(info.name).parts
        if any(p in {".git", ".godot", ".export-templates", "target", "artifacts", "node_modules", "__pycache__"}
               for p in parts):
            return None
        if "adventure" in parts or info.name.endswith((".log", ".flattened-pom.xml")):
            return None
        return info
    with tarfile.open(stage / "ForgeUI-source.tar.gz", "w:gz") as source:
        for name in ("forge", "bridge", "client-godot", "docs", "forge-patches",
                     "FORGE_COMMIT", "FORGE_PATCHES.md", "README.md", "AGENTS.md"):
            source.add(ROOT / name, arcname=f"ForgeUI/{name}", filter=source_filter)
    # Re-sign nested Java bundles before signing the enclosing app.
    for arch in ("arm64", "x86_64"):
        run(["codesign", "--force", "--deep", "--sign", "-", resources / "runtime" / arch])
    run(["codesign", "--force", "--deep", "--sign", "-", app])
    run(["codesign", "--verify", "--deep", "--strict", app])
    executable = app / "Contents/MacOS/ForgeUI"
    run([executable, "--headless", "--", "--smoke"], log="macos-smoke.log", timeout=240)
    smoke = (DIST / "macos-smoke.log").read_text()
    if "PASS: mock table smoke" not in smoke or any(s in smoke for s in ("SCRIPT ERROR:", "Parse Error:")):
        raise RuntimeError("Exported game failed the smoke check; see dist/macos-smoke.log")
    run(["node", "client-godot/tools/bundled-check.mjs", executable],
        log="bundled-check.log", timeout=300)
    dmg = DIST / f"{args.output}-universal.dmg"
    run(["hdiutil", "create", "-volname", "ForgeUI", "-srcfolder", stage,
         "-format", "UDZO", "-ov", dmg])
    run(["hdiutil", "verify", dmg])
    digest = hashlib.file_digest(dmg.open("rb"), "sha256").hexdigest()
    dmg.with_suffix(".dmg.sha256").write_text(f"{digest}  {dmg.name}\n")
    print(f"Built {dmg} ({dmg.stat().st_size / 1024 / 1024:.1f} MiB)", flush=True)


if __name__ == "__main__":
    main()
