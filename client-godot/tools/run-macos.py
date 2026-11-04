#!/usr/bin/env python3
"""Mac source launcher. Own and stop only the service started by this invocation."""
import argparse
import os
from pathlib import Path
import socket
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
GODOT = os.environ.get("FORGE_GODOT_PATH", str(ROOT / ".tools/godot/Godot.app/Contents/MacOS/Godot"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    for flag in ("Editor", "Live", "Connect", "Decks", "Mock"):
        mode.add_argument("-" + flag, "--" + flag.lower(), action="store_true", dest=flag.lower())
    parser.add_argument("-Check", "--check", action="store_true")
    parser.add_argument("-Capture", "--capture", action="store_true")
    parser.add_argument("-Deck", "--deck", default="")
    parser.add_argument("-Port", "--port", type=int)
    args = parser.parse_args()
    if args.port is not None and not 1 <= args.port <= 65535:
        parser.error("Port must be between 1 and 65535")
    if args.check or args.capture:
        if args.decks or args.live:
            tool = "library-check.mjs" if args.decks else "live-check.mjs"
            return subprocess.call(["node", str(ROOT / "client-godot/tools" / tool)] + (["--render"] if args.capture else []), cwd=ROOT)
        if args.capture:
            artifacts = ROOT / "client-godot/artifacts"
            artifacts.mkdir(exist_ok=True)
            (artifacts / ".gdignore").touch()
            command = [GODOT, "--path", "client-godot", "--resolution", "1600x1000", "--", f"--visual-checks={artifacts}"]
            expected = "PASS: rendered visual checks"
        else:
            imported = subprocess.run([GODOT, "--headless", "--path", "client-godot", "--editor", "--import", "--quit"], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            print(imported.stdout)
            if imported.returncode or "ERROR:" in imported.stdout:
                return 1
            command = [GODOT, "--headless", "--path", "client-godot", "--", "--smoke"]
            expected = "PASS: mock table smoke"
        result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=240)
        print(result.stdout)
        return int(result.returncode != 0 or "ERROR:" in result.stdout or expected not in result.stdout)
    client = [GODOT, "--path", str(ROOT / "client-godot")]
    if args.editor:
        return subprocess.call(client + ["--editor"], cwd=ROOT)
    if args.mock:
        return subprocess.call(client + ["--", "--mock"], cwd=ROOT)
    port = args.port or (7777 if args.live or args.connect else 7778)
    if args.connect:
        return subprocess.call(client + ["--", f"--live=ws://127.0.0.1:{port}/ws"], cwd=ROOT)
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", port))
    if not (ROOT / "bridge/target/classes/forgeui/bridge/LibraryMain.class").exists():
        parser.error("Build the bridge first; see docs/macos-build.md")
    artifacts = ROOT / "client-godot/artifacts"
    artifacts.mkdir(exist_ok=True)
    (artifacts / ".gdignore").touch()
    service = "BridgeMain" if args.live else "LibraryMain"
    command = ["java", "-Xmx4g", "-cp", os.pathsep.join(["target/classes", "target/lib/*"]),
               "forgeui.bridge." + service, "--assets", "../forge/forge-gui", "--port", str(port), "--parent-pid", str(os.getpid())]
    if args.live:
        command += ["--opponents", "2"] + (["--deck", args.deck] if args.deck else [])
    with (artifacts / "mac-launch-service.log").open("w+") as log:
        bridge = subprocess.Popen(command, cwd=ROOT / "bridge", stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 120
            marker = "Bridge ready:" if args.live else "Library ready:"
            while True:
                log.seek(0)
                if marker in log.read():
                    break
                if bridge.poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError("Forge startup failed; see client-godot/artifacts/mac-launch-service.log")
                time.sleep(0.2)
            options = [f"--live=ws://127.0.0.1:{port}/ws"] if args.live else [f"--library-url=ws://127.0.0.1:{port}/ws"]
            if args.decks:
                options += ["--open-decks"]
            return subprocess.call(client + ["--"] + options, cwd=ROOT)
        finally:
            if bridge.poll() is None:
                bridge.terminate()
                try:
                    bridge.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    bridge.kill()
                    bridge.wait()


if __name__ == "__main__":
    raise SystemExit(main())
