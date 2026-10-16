# Soundboard

A personal macOS soundboard: grid/list sets of sound tiles with per-tile
fades, trim, loop, solo, hold-to-play and Volume A/B. Behaviour is specified in
`../analysis/notes/` (clean-room rebuild of Farrago's behaviour; no Farrago code
or assets).

## Install

Requirements: macOS 14+, Swift 6.3 (Command Line Tools are enough; Xcode is
optional). No third-party dependencies.

## Run

```bash
make run
```

The package also opens directly in Xcode (`File > Open…` on `Package.swift`).

To get a real app with its icon:

```bash
make bundle
```

This builds `build/Soundboard.app` (release, signed ad hoc for this Mac); `make open`
builds and launches it. Copy it to `/Applications` to keep it. `make icon` regenerates
`Resources/AppIcon.icns` from `scripts/make-icon.swift`.

## Test

```bash
make test
```

`make check` runs lint, build and tests; `make format` rewrites sources with
`swift format` (config in `.swift-format`).
