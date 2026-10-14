# Sound set document format (`.farragoset`)

Status: **observed** on the 3 bundled sample sets; field meanings marked
*inferred* are not yet confirmed in code.

Sources (REA `inspect_plist` Evidence, retained JSON in `analysis/evidence/`):

| Evidence | File |
|---|---|
| `ev_fe76c699…0b7e` | Sample Sound Effects / `Sound Set Data.plist` |
| `ev_9a567144…dbccc` | Sample Music / `Sound Set Data.plist` |
| `ev_634f482e…3d93` | Sample List Mode / `Sound Set Data.plist` |
| `ev_998036d3…69b9`, `ev_b86aca5e…8511`, `ev_4b4df0ff…7df0` | one `Metadata/<uuid>` per set |
| `ev_bd4ed24a…82f3b` | `ShortcutsIntents.intentdefinition` |

## Package layout (observed)

UTI `com.rogueamoeba.farrago.farragoset`, extension `farragoset`, conforms to
`com.apple.package` (a directory shown as one file).

```
<Name>.farragoset/
  Sound Set Data.plist      binary plist, the set model
  Sound Files/<fileUUID>.<ext>   audio copied into the set (samples: AAC .m4a)
  Metadata/<fileUUID>       binary plist, per-audio-file cache
```

Audio is referenced by `fileUUID`, not by name; `fileName` keeps the original
name for display/export.

## `Sound Set Data.plist` (observed keys)

| Key | Observed values | Meaning |
|---|---|---|
| `type` | `"Farrago.FGTileSet"` | model class tag |
| `formatVersion`, `formatMinSupportedVersion` | 2, 2 | versioning |
| `uuid`, `title`, `notes` | | identity |
| `mode` | 0 (grid samples), 1 (List Mode sample) | *inferred*: 0 = grid, 1 = list |
| `playbackMode` | 1 (grid samples), 2 (List Mode sample) | **observed**: 0 = Single, 1 = Toggle, 2 = Continuous (`FGTileSet.playbackModeSingle/Toggle/Continuous` compare the stored value to 0/1/2; Evidence `ev_bd6c7a2d…`, `ev_bdaf5b00…`, `ev_97820375…`). Behaviour of each mode: see `02-playback-behaviour.md` |
| `crossfadeDuration` | 0, 0.409 (List Mode sample) | seconds, *inferred* list-mode crossfade |
| `position` | 0, 1, 2 | order in the sets sidebar |
| `maxRowsGrid`, `maxRowsList` | 8, 80 | layout limits |
| `security` | `{locked, password, passwordRequired, hint}` | "Lock Set" feature |
| `automations.modelItems` | `[]` everywhere | *unknown* (automation rules) |
| `setWindowState`, `splitViewState` | empty | UI state |
| `tiles` | array (4/20/30 entries) | sounds |

### Tile (observed keys)

| Key | Observed | Meaning |
|---|---|---|
| `tileUUID`, `fileUUID`, `fileName`, `title`, `notes`, `notesShown` | | identity / text |
| `tileIcon` | array of 1–2 emoji strings | tile icon |
| `colorIndex` | 0–4 seen | *inferred*: index into 9 colors (Shortcuts enum: purple, pink, red, orange, yellow, green, lightBlue, darkBlue, black; order not confirmed) |
| `gridPositionX/Y` | 0–5 / 0–4 | grid cell |
| `listPositionY` | 0… | row in list mode |
| `playbackEnabled`, `favorite`, `holdToPlay`, `solo`, `selected` | | flags (menu: Enable/Disable, Hold to Play, Solo) |
| `lastPlayStart` | `-62135769600` (= year 1 sentinel, never played) or Unix time | "Mark Played/Unplayed" |
| `automations.modelItems` | `[]` | *unknown* |
| `editorWindowState`, `editorModelState` | empty | editor UI state |
| `playerSettings` | see below | |

### `playerSettings`

| Key | Observed | Meaning |
|---|---|---|
| `duration` | seconds (float) | |
| `packetCount` | e.g. 1201 | **observed**: equals the AAC packet count of the file (`afinfo`, 1024 frames/packet) |
| `startPackets`, `endPackets` | 0–42, 0–70 | *inferred*: trim in packets from start / from end |
| `fadeInTime`, `fadeOutTime` | 0 | seconds |
| `loop` | true on all Music sample tiles | |
| `defaultToPause` | false | *inferred*: "Pausable" menu flag |
| `fullVolume` | 1 | *inferred*: Volume A (Shortcuts `volumeA`) |
| `duckVolume` | 0.4 | *inferred*: Volume B (Shortcuts `volumeB`) |
| `ducked` | false | *inferred*: tile currently at Volume B |
| `muted` | false | |
| `channels` | `[0, 0]` | *unknown*: output channel routing (prefs have Left/Right channel) |

## `Metadata/<fileUUID>` (observed)

| Key | Meaning |
|---|---|
| `fileUUID` | back-reference |
| `originalHash` | **observed**: SHA-1 of the stored sound file (verified on `04CED452…`) |
| `tags` | dict of audio tags (`Artist`, `Title`, `Encoder`…) |
| `waveformData` | 4800 bytes = 1200 little-endian float32 in [-1, 1], independent of sound length; *inferred* 600 (max, min) peak pairs for the tile waveform |

## Rebuild decisions

- Read/write this format for interoperability with existing sets is optional;
  the rebuild may use its own model but should keep: package with copied audio,
  UUID-addressed files, cached waveform peaks, per-tile player settings.
- Trim stored in packets is codec-specific; the rebuild should store trim in
  seconds or frames instead.

## Open questions

- `automations` structure (no non-empty sample).
- `channels` encoding.
- Exact color order for `colorIndex`.
