# Farrago clean-room rebuild (personal use)

Goal: build a personal soundboard app that reproduces the *behaviour* of
Rogue Amoeba's Farrago 2.1.5 (installed at `/Applications/Farrago.app`, x86_64,
Swift/AppKit). REA is used to understand how features work; the rebuild is
written from scratch.

## Ground rules

- Reimplement behaviour, never copy: no decompiled code pasted into `app/`, no
  icons, sounds, nibs or other assets extracted from Farrago. Write specs in
  `analysis/notes/` first, then implement from the spec.
- Ignore licensing, registration and anti-piracy code (`PasswordKit`, license
  checks): out of scope.
- Do not modify `/Applications/Farrago.app` or its preferences/data.
- Everything stays inside this directory: no global installs, no `rea setup`,
  no `claude mcp add`, no edits to `~/.claude*`. These are denied in
  `.claude/settings.json`.

## Tooling

- REA is pinned to `rea-agents@6.4.0`, registered as the `rea` MCP server in
  `.mcp.json`. The npm cache lives in `.cache/npm` (also exported to Bash via
  `.claude/settings.json`). The REA skill is vendored in
  `.claude/skills/reverse-engineer-anything/` from the same package version.
- CLI equivalent: `npx -y rea-agents@6.4.0 <command> ... --format json`.
- To upgrade REA: bump the version in `.mcp.json`, `.claude/settings.json`,
  this file, and re-copy `skills/` from the new package (`npm pack`).

### What works without a native decompiler

Static, read-only, no Hopper/Ghidra needed: `inspect-plist`, `inspect-macho`,
`inspect-signature`, `inspect-artifact`, `inspect-asset-catalog`,
`decode-interface-builder` (UI layout from nibs), `inspect-keyed-archive`
(Farrago document format), `demangle-swift`.

### Native provider: Ghidra (project-local)

Pseudocode / call tracing (`analyze`, `decompile`, `function`,
`inspect-native-dispatch-metadata`) uses Ghidra, installed under `tools/`:

- `tools/ghidra_12.1.4_PUBLIC` (official NSA release, SHA-256 verified) and
  `tools/jdk-21.0.12.1+1` (Temurin, SHA-256 verified).
- The release ships no macOS decompiler; it was built locally with
  `support/gradle/gradlew buildNatives` into
  `Ghidra/Features/Decompiler/build/os/mac_x86_64/`. Re-run that (with
  `JAVA_HOME` and `GRADLE_USER_HOME=.cache/gradle` set) after any Ghidra upgrade.
- `GHIDRA_INSTALL_DIR` and `JAVA_HOME` are set in `.mcp.json` (MCP) and
  `.claude/settings.json` (Bash). Do **not** set `REA_ANALYSIS_PROVIDER=ghidra`:
  it forces Ghidra onto bundle-level operations (`inspect-plist`,
  `decode-interface-builder`) which then fail on the universal app. Ghidra is
  the only deep provider, so auto-selection picks it for thinned binaries.
- Bundle-level tools on `/Applications/Farrago.app` are easiest via the CLI,
  which takes the path directly (MCP `open_binary` on the universal app fails).
- Readiness check: `npx -y rea-agents@6.4.0 doctor --provider ghidra --format json`.
- **Ghidra rejects universal Mach-O.** Thin first, into the gitignored
  `analysis/bin/`:
  `lipo -thin x86_64 -output analysis/bin/<name>.x86_64 <universal binary>`.
  The main `Farrago` binary is universal (x86_64 + arm64).
- Sessions are ephemeral and never modify the analysed file.

Runtime tools (`capture-native-ui-scenario`, `capture-process`) launch
Farrago; only run them when explicitly asked.

## Layout

- `tools/` – Ghidra + JDK (gitignored). `.cache/downloads/` holds the
  verified archives and can be deleted.
- `analysis/bin/` – thinned binary slices for Ghidra (gitignored).
- `analysis/evidence/` – raw REA Evidence JSON (gitignored, can be huge;
  project it with `inspect-analysis-view`).
- `analysis/notes/` – one Markdown spec per feature: observed behaviour,
  Evidence IDs backing each claim, unknowns.
- `app/` – the rebuild, a Swift package (see below).

## App (`app/`)

- Targets: `SoundboardCore` (model and, later, playback logic; no UI, unit
  tested) and `Soundboard` (SwiftUI executable). Tests: `SoundboardCoreTests`
  (Swift Testing).
- Commands, run from `app/`: `make run`, `make test`, `make lint`,
  `make format`, `make check` (lint + build + test), `make bundle`
  (`build/Soundboard.app`, release, ad hoc signed), `make open`, `make icon`. `make check` must pass
  before a task is done.
- Style: `swift format` with the pinned `app/.swift-format` (2-space indent,
  100 columns). No third-party dependencies so far.

### Decisions

- **Swift package, not `.xcodeproj`**: Xcode is not installed (Command Line
  Tools only). The package builds with `swift build` and opens as-is in Xcode
  later.
- **Swift Testing via Makefile flags**: CLT ship `Testing.framework` outside
  the default search paths; `make test` passes `-F`/rpath. Plain `swift test`
  fails without Xcode.
- **App bundle assembled by the Makefile** (no Xcode): `make bundle` copies the
  release binary, `Resources/Info.plist` (bundle id
  `io.github.theoiscod.soundboard`, `.soundset` exported as a package type) and
  `Resources/AppIcon.icns`, then signs ad hoc. `make run` still launches the bare
  executable, which needs `setActivationPolicy(.regular)` for a Dock icon.
  Preferences (master volume, shown set) live under the bundle id, separate from
  the bare executable's `Soundboard` domain; the set library is shared.
- **Opening a set** (Finder double-click, Open With, Dock, drop on the board) goes
  through `AppDelegate.application(_:open:)`, which buffers URLs until the board
  is ready. A `.soundset` whose set id is already in the library is shown, not
  duplicated; `.farragoset` is always imported. Import Set… always copies. The
  app is the owner of `.soundset` and only an alternate handler of `.farragoset`.
- **MIDI** (`MIDIInput`, CoreMIDI, no dependency): listens to every source and
  reconnects on setup changes. A tile's `midiTrigger` (channel + note) is set by
  MIDI learn (⌘L) and, like hotkeys, works for the shown set only. Note-on plays
  with velocity/127 as a gain factor, note-off releases Hold to Play tiles.
  CoreMIDI callbacks are created in `nonisolated` functions: closures formed in
  main-actor code would be inferred main-actor isolated and trap on CoreMIDI's
  threads. End-to-end check without hardware: a virtual source script plus
  `/usr/bin/log stream --level debug --predicate 'subsystem ==
  "io.github.theoiscod.soundboard"'` shows the connected sources and notes.
- **OSC** (`OSCService`, Network framework, UDP): off by default, enabled in the
  Settings window (⌘,) so macOS only asks for local network access when wanted.
  Addresses follow the scheme found in Farrago's binary (`/set/<n>/tile/<x>/<y>/…`,
  `/master/…`, `/transport/…`; the per-tile action list is partly inferred). Tiles
  are addressed by sidebar index and grid cell. Feedback `…/play 1|0` goes to the
  output address. End-to-end check: enable `oscInputEnabled`/`oscOutputEnabled` in
  the bundle's defaults, send UDP packets to 8080 and listen on 8081.
- **Smart sets** (spec `analysis/notes/03-smart-sets.md`): a set with
  `smartRules` shows matching tiles of ordinary sets, laid out in a fresh grid by
  `SoundLibrary.shownSet`. The board, hotkeys, MIDI, OSC and Play Selection work on
  `BoardModel.shownSet`. Those tiles carry the smart set's layout, so
  `BoardModel.update` always keeps the position stored in the tile's own set.
  Smart sets take no dropped sounds, and their tiles can't be deleted or moved there.
- **Global shortcut** (Settings → Général) brings the app forward, like Farrago's
  "Bring Farrago Forward"; also `/global/bringForward` over OSC. Registered with
  Carbon `RegisterEventHotKey` (no Accessibility permission). Since macOS 14 a
  background app's own `activate()` is ignored, so `AppActivation.bringForward`
  asks Launch Services to open the running bundle instead (verified from Chrome
  and Finder via the OSC address).
- **MIDI output** (`MIDIOutput`, Settings → MIDI): one destination plus an "on"
  velocity (colour on pad controllers), where Farrago has a per-device table.
  Pads of the shown set's playing tiles are lit; `MIDILights` sends only changes,
  and switching sets relights. Verified end to end with a virtual destination.
- **`SOUNDBOARD_LIBRARY_DIR`** points the app at another set library, for
  end-to-end checks on throwaway data (`open -g --env SOUNDBOARD_LIBRARY_DIR=… build/Soundboard.app`).
  Handwritten test plists must store `Float` fields as exact float32 values, or
  `PropertyListDecoder` rejects them ("does not fit in Float").
- **Waveform editor window** (⇧⌘E, one window per tile, `WaveformEditorWindow`):
  zoom (`WaveformViewport`), selection, trim/fade handles, preview of the
  selection, undo/redo (a handle drag is one step). Unlike Farrago, editing is
  **non-destructive**: Crop sets the trim, Fade Selection In/Out move the trim
  bound and fade over the selection, Revert clears trim and fades; the sound file
  is never rewritten (so Farrago's squared "baked" fade curve isn't used).
  Editor peaks are ~5 ms bins, regrouped per pixel column with `Waveform.columns`.
- **Seeking** (editor ← / →, ±5 s or ±1 s with ⇧, ⌥-click): `AudioEngine.seek`
  stops the node and reschedules the rest of the region (then the whole region
  looping). Player time restarts at 0, so a voice keeps an `offset`; every
  schedule bumps `Voice.schedule` so the completion of a replaced schedule (fired by
  `stop()`) doesn't end the voice. Completion closures stored in variables must be
  declared `@Sendable` or they are main-actor isolated and trap on the audio thread.
- **Saved waveforms**: peaks are stored in the set package as
  `Waveforms/<fileID>-<binCount>.peaks` (`WaveformFile`: "SBWF", version, count,
  Float32 pairs), like Farrago's `Metadata/` waveform. The copied sound never
  changes, so the file id is the cache key (no hash). Unreadable or outdated files
  are recomputed; removing a sound removes its waveforms; imports copy them.
- **Shortcuts integration = `soundboard://` links**, not App Intents: App Intents
  compile with the Command Line Tools but only show up in Shortcuts with the
  `Metadata.appintents` that Xcode's `appintentsmetadataprocessor` generates, and
  Xcode can't be installed without an Apple ID. `URLCommand`: `play|stop|fade?title=`
  (`&set=`), `set?title=`, and every OSC address as a path (`?value=`). Names compare
  ignoring case and accents; query values are percent-decoded once more because
  `open` double-encodes links typed with raw accents. `farrago://` is not claimed.
  Check: `open -g "soundboard://…"` against a throwaway library with OSC feedback on.
- **Icon is drawn by `scripts/make-icon.swift`**, our own design; the generated
  `.icns` is committed so bundling doesn't need to redraw it.
- **Own document format**: `SoundSet` is `Codable` with its own
  `formatVersion`; trim is stored in seconds, not codec packets. Importing
  `.farragoset` is optional and would be a separate importer.
- **Behaviour follows `analysis/notes/02-playback-behaviour.md`**, except
  where its "Rebuild decisions" deliberately differ (e.g. honour the requested
  fade-in duration instead of Farrago's fixed 2 s).
- Minimum macOS 14 (SwiftUI `Observable`, modern `AVAudioEngine` APIs).

## Known facts (from Info.plist)

- Principal class `FGApplication`, URL scheme `farrago://`.
- App Intents: Play/Fade/Stop/Pause sounds, sets, master volume/mute, OSC
  get/set values.
- Bundled frameworks of interest: `auverse`, `RAAudioUnit`, `ControlSurface`,
  `RAStreamDeck`, ffmpeg (`libavcodec`/`libavformat`), `libFLAC`, `libmp3lame`.
