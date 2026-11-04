# macOS distribution

`python3 client-godot/tools/package-macos.py` produces a universal Godot app with
separate Apple Silicon and Intel Temurin 17 runtimes, the Java bridge and Forge
rules/assets. Friends do not need to install Java or Godot. The output is
`dist/ForgeUI-macOS-universal.dmg`; drag the app to Applications before opening it.
The source archive and licenses travel with the build.

## Local build retention

Keep the original Mac checkout and its backup until reconciliation is accepted on both
platforms. The shared clone builds into its own ignored `dist/`; it does not reuse or
overwrite the old Mac app. Use `--output` to keep successive validation builds.
Each app and build folder includes `build-info.json` with the source commit, dirty
state, Forge commit, patch checksum, platform and bundled architectures.

## Build prerequisites

Use macOS, Python 3.12 or newer, and a JDK 17. Place these official downloads in
the project (the `.tools` directory is ignored by Git):

- Godot 4.7.2 macOS universal editor: extract to `.tools/godot/Godot.app`.
- Godot 4.7.2 export templates: extract only `templates/macos.zip` to
  `.tools/godot/macos.zip`.
- Godot's `LICENSE.txt` and `COPYRIGHT.txt` from the same release: save as
  `.tools/godot/Godot-LICENSE.txt` and `.tools/godot/Godot-COPYRIGHT.txt`.
- Apache Maven 3.9.9: extract to `.tools/apache-maven-3.9.9`.
- Eclipse Temurin 17 macOS JRE archives: save the aarch64 download as
  `.tools/downloads/jre-arm64.tar.gz` and the x64 download as
  `.tools/downloads/jre-x86_64.tar.gz`.

Download sources:

- https://github.com/godotengine/godot/releases/tag/4.7.2-stable
- https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/
- https://api.adoptium.net/v3/binary/latest/17/ga/mac/aarch64/jre/hotspot/normal/eclipse
- https://api.adoptium.net/v3/binary/latest/17/ga/mac/x64/jre/hotspot/normal/eclipse

The build stores Maven dependencies in `.tools/maven-cache`, verifies the pinned Forge revision and recorded patch, then builds Forge, runs the bridge regression harness, exports Godot,
bundles both runtimes, signs the app ad hoc, runs the exported mock-table smoke
test, tests the app's bundled service and real Commander match, creates a
compressed DMG, verifies it, and writes its SHA-256 checksum.
It excludes Adventure assets, personal decks, Git history and build caches.
The Godot template targets macOS 11+ on Intel and macOS 13+ on Apple Silicon.

Use `--skip-build` after compiling the Java modules, or
`--output ForgeUI-macOS-next` to preserve an earlier build. Existing output
folders are never deleted automatically. Logs are in `dist/`.

## App layout

The executable is `ForgeUI.app/Contents/MacOS/ForgeUI`.
`Contents/Resources` contains `service`, `forge-gui`, `licenses`, and
`runtime/{arm64,x86_64}/Contents/Home`. `BundledService.gd` selects Java for the
running executable's architecture, uses the Unix classpath separator and writes
service state to Godot's writable `user://service` folder. The app bundle can
remain read-only. Child match JVMs use the same runtime and watch their parent.

## Signing

Ad-hoc signing permits local execution and validates the bundle's integrity.
It does not provide Apple Developer ID authentication or notarization. Friends
may need to attempt to open the app, then allow it using System Settings >
Privacy & Security > Open Anyway. Managed Macs may disallow this.

For a release that opens without this approval, sign nested native code and the
app using a Developer ID Application identity, submit to Apple's notary service,
staple the ticket, and recreate/sign the DMG. Apple account credentials are not
part of this repository or build. Do not modify the bundle after final signing.
