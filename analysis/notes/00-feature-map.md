# Farrago 2.1.5 feature map

Status: **observed** from shipped resources (menu actions, preference labels,
Shortcuts intents). These show which features exist and how they are reached;
none of these sources proves runtime behavior. Behavior specs per feature go in
separate notes.

Sources: `ev_2630c65c…abd3ab` (REA `decode_interface_builder`: MainMenu.nib,
FGPreferences.nib, FGControllerPreferences.nib), `ev_bd4ed24a…82f3b`
(Shortcuts intents), Info.plist.

The main window (board) is built in code, not in a nib; its layout must
come from code analysis or from using the app.

## Core concepts

- **Sound set** (`FGTileSet`): a named collection of tiles. Shown in a sidebar
  (`Hide Sets` ⌘S, previous/next set ⇧⌘[ / ⇧⌘]). Can be a **Smart Set**
  (`New Smart Set`, `Edit Rules…`). Can be **locked** (⇧⌘L, optional password).
  Can open in a secondary window.
- **Display mode**: Grid or List (`Switch To List Mode`). List mode has
  `Reset List` (⌘R) and an inferred crossfade between items.
- **Tile**: one sound, with emoji icon, color, notes, and flags: Enabled,
  Played/Unplayed, Loop, Solo, Pausable, Hold to Play, Favorite.
- **Volume A / Volume B** per tile and on the master; "Fade to Volume A" (⇧⌘D)
  toggles the master between them (`toggleMasterVolumeMode:`).

## Menu actions and shortcuts

Shortcuts decoded from `NSKeyEquiv` + `NSKeyEquivModMask` (an uppercase key
character implies ⇧). Playback keys have **no modifier**.

| Menu | Item | Shortcut | Selector |
|---|---|---|---|
| Playback | Play Selection | Return (also ⌃Return) | `toggleSelectionPlaying:` |
| Playback | Preview | ⇧Return | `previewSelectedTiles:` |
| Playback | Pause All | Space | `togglePauseAll:` |
| Playback | Stop All | Esc | `stopAll:` |
| Playback | Stop and Reset All | ⌘Esc | `stopAndResetAll:` |
| Playback | Reset All | ⇧Esc | `stopAndResetAll:` (same selector) |
| Playback | Fade Out All | - | `fadeOutAll:` |
| Playback | Master Volume Up / Down | ⌘↑ / ⌘↓ | `masterVolumeUp:` / `masterVolumeDown:` |
| Playback | Fade to Volume A | ⇧⌘D | `toggleMasterVolumeMode:` |
| Playback | Reset List | ⌘R | `resetList:` |
| Tile | Edit… | ⇧⌘E | `editTile:` |
| Tile | Enable / Disable, Mark Played / Unplayed, Loop, Solo, Pausable, Hold to Play, Select Color…, Export Selected Sounds… | – | `enableSelectedTiles:` … `exportSelectedSounds:` |
| Sound Set | Add Sounds… | ⌘N | `addNewTile:` |
| Sound Set | New Set | ⇧⌘N | `addNewSet:` |
| Sound Set | New Smart Set / Edit Rules… | – | `addSmartSet:` / `editSmartSet:` |
| Sound Set | Lock Set | ⇧⌘L | `toggleSetLock:` |
| Sound Set | Switch To List Mode | – | `toggleGridMode:` |
| Sound Set | Open in Secondary Window, Import Set…, Export Set…, Export All Sets… | – | |
| Editor | Crop Selection | ⇧⌘X | `crop:` |
| Editor | Fade Selection In / Out | ⇧⌘I / ⇧⌘O | `fadeInSelection:` / `fadeOutSelection:` |
| Editor | Zoom In / Out / to Fit / to Selection | ⌘+ / ⌘- / ⌥⌘- / ⌥⌘= | |
| Editor | Scan Backward / Forward | ← / → | |
| Editor | Revert to Original | – | `revert:` |
| Edit | Search | ⌥⌘F | `searchLibrary:` |
| Edit | Duplicate | ⌘D | `duplicate:` |
| MIDI | Learn MIDI | ⌘L | `learnMidi:` |
| MIDI | Clear MIDI, Device Settings… | – | |
| Window | Farrago / Hide Sets / Hide Inspector | ⌘0 / ⌘S / ⌘I | |
| Window | Previous / Next Set | ⇧⌘[ / ⇧⌘] | |

## Preferences

- Playback: single click to trigger playback (otherwise ⌘-click selects without
  playing); bring Farrago forward (popup); main/preview output devices;
  left/right channel mapping; preview volume.
- Global hotkey.
- Library sources: Freesound (search, account login, 25 searches/day without
  account), Apple Loops.
- Controllers: OSC input port (8080) / output address and port
  (127.0.0.1:8081), MIDI (device, channel, output, velocity, MIDI keys),
  Elgato Stream Deck plugin (install/uninstall).

## Automation surface (Shortcuts intents)

PlaySound, FadeSound(duration), FadeAll, PauseAll, UnpauseAll, StopAll,
FadeBetweenVolumes, SetMasterVolume(A|B, value), SetMasterMute(set|toggle),
SetSoundVolume(A|B, value), SetSoundMute, SetSoundSetting(looping, holdToPlay,
solo, pausable, favorite, color), GetSound, GetSoundSet, GetPlayingSounds,
ResetList, SetOSCValue(paths, value), GetOSCValue(path).

Sound and SoundSet each expose an `oscBaseAddress`, so OSC addresses are per
set and per sound.

Also: URL scheme `farrago://` (commands unknown).

## Out of scope for the rebuild (proposal)

License/registration, Sparkle updates, news, usage data, Freesound/Apple Loops
library (optional later), Stream Deck plugin (optional later).

## Suggested rebuild order

1. Set + tile model, grid view, play/stop with multiple simultaneous sounds.
2. Per-tile settings: loop, fade in/out, trim, volume A/B, hold to play, solo,
   pausable; Pause/Stop/Fade Out All; master volume A/B.
3. List mode with auto-advance and crossfade; played/unplayed marks.
4. Waveform editor (trim, crop, fades) and the package format.
5. Keyboard shortcuts per tile, MIDI learn, OSC.
