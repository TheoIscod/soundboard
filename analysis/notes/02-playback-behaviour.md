# Playback behaviour (trigger modes, solo, fades, volumes)

Status: **mostly answered**. Trigger/stop flow, solo, Continuous
auto-advance, crossfade timing, master volume step and fade defaults are
**observed** in the main binary. The audio engine (`jtr.framework`:
`JTRFilePlayer`, `JTRCrossfade`) was analysed in a second session: fade
curves, fade durations, the volume chain and Volume A/B are now **observed**
there (§3, §4, §9). What remains open is mostly on the app side: whether
Farrago passes its own `fadeTime` into the engine.

Notation: tile/set vtable slots are named after the behaviour they produce at
the call site; slot names not confirmed by a symbol are marked *inferred*.

## Sources

All Evidence from the Ghidra session on `analysis/bin/Farrago.x86_64`
(sha256 `69afe739…`), plus `nm`/`strings` on
`Farrago.app/Contents/Frameworks/jtr.framework` (x86_64 slice, read-only).

| Evidence | Covers |
|---|---|
| `ev_4cd42349…` | `search_procedures` FGTile/FGTileSet playback symbols (holdToPlayForMode, soloForMode, togglePlayback, playerDidStop…, resetPlayState, markSelectedTiles…) |
| `ev_9d0f9225…` | `search_procedures` stopAll / masterVolume / FadeBetweenVolumes / resetList symbols |
| `ev_ec5cfae8…`, `ev_d5eae507…` | `FGTile.startPlayingWithSolo:velocity:withFade:withPreview:withQueueing:` thunk and body (0x1000efc40) |
| `ev_ab9ff69d…` | `FGTile.togglePlayback` |
| `ev_219d746e…` | `FGTile.setPlaying:` body (0x1000ecb30); `soloForMode`/`holdToPlayForMode` bodies (0x1000e1570, 0x1000e1800) |
| `ev_c97aca02…`, `ev_11aa99cd…` | `FGTile.soloForMode` thunk chain |
| `ev_a87f99d4…` | `FGTile.playing / isPlaying / paused / playbackEnabled / holdToPlayForMode` getters |
| `ev_7a09c3fb…` | `FGTile.stopPlayingWithFade:` |
| `ev_d6b5c2e6…` | `FGTile.stopOthersWithFade:` |
| `ev_88c245ec…`, `ev_5379ec36…` | `FGNowPlaying.stopAllWithExcept:withFade:` and body |
| `ev_70414fc3…`, `ev_f8073cbc…` | `FGNowPlaying.fadeAllOut` and body |
| `ev_cc22924d…` | batch: `fadeOutAll:`, `stopAll:`, `togglePauseAll:`, `toggleMasterVolumeMode:`, `masterVolumeUp/Down:` thunks, `FGTileSet.tilePlayerDidStop…`, `FGTile.playerDidStop…`, `FGTile.resetPlayState`, `FUN_10022f820` (playNextTileAfter body), `handleFadeBetweenVolumes` |
| `ev_6876885d…`, `ev_2ab1f07b…` | assembly of `masterVolumeUp:` / `masterVolumeDown:` (closure addresses) |
| `ev_e5e519f2…` | master volume up/down closures (±0.05), `FUN_1000f16b0` (tile stop handler) |
| `ev_9b1a9526…`, `ev_4b44dfd5…`, `ev_4f6ad89a…`, `ev_7d73af7f…` | `toggleMasterVolumeMode:` closure chain |
| `ev_6702e9dd…` | `FUN_100244090` set-level "tile stopped" handler |
| `ev_8bf4e782…`, `ev_101c6da3…` | `FGTileSet.tilePlayerPositionDidChange…` and body `FUN_10022f260` (Continuous crossfade trigger) |
| `ev_1628223f…` | callers of `FUN_10022f820` |
| `ev_e35495bc…`, `ev_49e6d5dc…` | `FGTileView.mouseDown:` / `mouseUp:` and bodies |
| `ev_88aee563…` | `FGPreferences` init body (`FUN_10011db70`): preference defaults |
| `ev_22d0309d…`, `ev_052799186…`, `ev_ee91e8a9…`, `ev_6c5d2ce8…`, `ev_aa6dd1f2…` | `fadeTime` getter, `fade` string inventory, xrefs |
| `ev_7c9a745a…`, `ev_3b50d8b6…`, `ev_585172cf…` | `jtr_clip_log_fade` import, its callers, export-render body `FUN_1000ff2f0` and editor fade `FUN_10009e900` |
| `ev_1cec6c51…` | `FUN_1000ef3b0` (pre-start error check), `currentVolume` / `ducked` getters |

jtr session on `analysis/bin/jtr.x86_64` (sha256 `01538742…`, x86_64 slice of
`jtr.framework`). Farrago snapshot: `analysis/evidence/Farrago.x86_64.snapshot.json`.

| Evidence | Covers |
|---|---|
| `ev_cd165591…` | `JTRCrossfade.startFadeFrom:to:duration:` stores start, target, duration, resets progress |
| `ev_bcfbf2de…` | `JTRCrossfade.startFadeFrom:to:` default duration 0.2 s |
| `ev_d20432d8…` | `JTRCrossfade.volumeAfter:` linear gain interpolation, progress clamped to [0,1] |
| `ev_1ffc2e91…` | `search_procedures` JTRFilePlayer / JTRCrossfade / log_fade inventory |
| `ev_470b9aa2…` | batch: `setMasterVolume:`, `masterVolumeCurrent`, `setMasterDucked:`, both `setCurrentVolume:`, `targetVolume`, `startPlayingWithVolume:fadeIn:`, `fadeToStopWithFade:`, `stopPlaying:` (+ block), `resetFades`, `envelopeVolumesForFrame:`, `setPaused:`, `JTRFilePlayerAudioBuffer.fadeFromVol:toVol:overFrames:` |
| `ev_f34356eb…` | batch: `commonInit`, `constrainVolume(s):`, `combineVolumes:`, `startPlayingWithVolume:`, `setFadeIn:`/`setFadeOut:`, `startFadeFrom:to:`, `playFinished`, `resetPlayState` |
| `ev_c714abfd…` + `nm` ivar list | ivar offsets: `_lastPacketVolume` 0x08, `_duration` 0x10, `_autoCrossfade` 0x30, `_masterCrossfade` 0x38, `_inCrossFade` 0x40, `_outCrossFade` 0x48, `_safetyCrossfade` 0x50, `_playingFlag` 0x58 |
| `ev_0cad0440…`, `ev_ed753a9a…` | `playOnePacket` pseudocode and assembly (per-packet gain chain) |
| `ev_316eb5f3…` | constant at 0x401a0 = 0.2 (volume-change ramp duration) |
| `ev_f4430721…` | `playPackets` (+ stop block), `JTRCrossfade.isFinished`, `JTR::Clip::log_fade` |

## 1. Single / Toggle / Continuous (`FGTileSet.playbackMode`)

Status: **partial**.

### Triggering a tile (independent of playbackMode)

- Clicking a tile toggles it: if it is not playing it starts, if it is playing
  it stops. The toggle is done by `setPlaying:` with the negated current
  state, from `mouseUp:` (normal tiles) or `mouseDown:` (Hold to Play
  tiles, see §5). **observed** (`ev_49e6d5dc…`, `ev_219d746e…`)
- A normal start uses velocity 1.0, no fade-in, no preview, queueing allowed.
  **observed** (`ev_ab9ff69d…`, `ev_219d746e…`)
- A normal stop is immediate. Holding Ctrl+Shift+Cmd while stopping requests a
  faded stop; Ctrl+Shift while starting requests a *solo* start.
  **observed** (modifier checks in `setPlaying:` body)
- Triggering a playing tile therefore **stops** it; it does not restart.
  Re-trigger to restart is not a behaviour of the click path. **observed**
- Starting a tile does **not** stop other tiles unless the tile (or the
  request) is Solo (§2). **observed**
- Shift-click (without Ctrl) on a tile pauses it (sets `paused`) instead of
  stopping; triggering a paused tile resumes it. **observed** in
  `mouseUp:` and in the start body (paused → resume path). Exact key mapping
  is *inferred* from flag values (Shift = 0x20000, Control = 0x40000).
- If the tile has `playbackEnabled == false`, the start request is turned into
  "not playing, not paused" and nothing plays. *inferred* (slot 0xe68 read as
  playbackEnabled).

### What the mode changes

The mode is only read at two places, both in the set's player callbacks:

| Mode | Value | Behaviour when a tile in the set plays | Evidence |
|---|---|---|---|
| Single | 0 | Nothing special: the sound ends and stops. | absence in both handlers **observed** |
| Toggle | 1 | When a tile stops (natural end or stop), the selection moves to the next playable tile (deselect all, select next as anchor, scroll to it). The next tile is **cued, not played**. | `ev_6702e9dd…` **observed**; "next tile" slot *inferred* |
| Continuous | 2 | While a tile plays, when its position reaches `trimmedDuration − X` the next playable tile is started automatically; the current tile is faded to stop over X unless it loops. | `ev_101c6da3…` **observed** |

So the UI labels "Single / Toggle / Continuous" are *inferred* to be the
List-mode advance options: stop, advance cue, or auto-play next. The sample
grid sets carry mode 1 but in grid mode the cue movement has no audible
effect. *inferred*

### Continuous crossfade

- X = min(`crossfadeDuration`, trimmedDuration / 2). **observed** (the
  half-duration clamp); the slot read as `crossfadeDuration` is *inferred*.
- The check is skipped if the current player is already fading out.
  **observed**
- With `crossfadeDuration == 0`, the next tile starts when the current one
  reaches its end (X = 0). **observed** (comparison uses ≥ trimmedDuration − X)
- Before starting the next tile, Farrago checks that it is not already
  playing / is not the same tile, and that there is a next playable tile
  (`nextPlayableTileAfter:`; disabled tiles skipped *inferred*). **observed**
  structure, slot meanings *inferred*.
- The outgoing tile gets `fadeToStopWithFade:` (duration = X) only if it does
  not loop; a looping tile keeps playing under the next one. **observed**
- The incoming tile is started via the set's play-next path with fade-in
  equal to the crossfade (fade-in itself clamped to half its duration, §3).
  *inferred* (the fade argument goes through an unnamed slot).
- `playNextTileAfter:withFade:` (also used by "next tile" commands) only
  starts the next tile if one exists, selects it as anchor, and starts it.
  **observed** (`ev_cc22924d…`, FUN_10022f820)

## 2. Solo

Status: **answered** (fade duration still unknown).

- After a tile starts (not in preview), if it is Solo *or* the start request
  was a solo request, Farrago stops **all other playing objects** through the
  global `FGNowPlaying` list (all sets, all windows), excluding only the tile
  that just started. **observed** (`ev_d5eae507…`, `ev_d6b5c2e6…`,
  `ev_5379ec36…`)
- Fade on solo stop: the "with fade" flag is true only if **Command** is held
  at trigger time; otherwise others stop immediately. **observed**
- Solo and Hold to Play are ignored when the set is in List mode (the
  `…ForMode` getters return false when the parent set reports list mode).
  **observed** structure; "list mode" meaning of the set flag *inferred*.
- Clicking a non-playing Solo tile also stops others at mouse-down time.
  **observed** in `mouseDown:`/`mouseUp:`.

## 3. Fades

Status: **answered** for the engine; one app-side unknown (`fadeTime` use).

### App side (Farrago binary)

| Item | Finding | Tag |
|---|---|---|
| `FGPreferences.fadeTime` default | **2.0 s** | **observed** (`ev_88aee563…`) |
| Other defaults seen in the same init | `previewVolume` 1.0, `singleClickToPlay` false, GarageBand/Freesound search on, `screamOnDelete` off | **observed** |
| Where `fadeTime` is used | no caller found in Farrago; not visible from jtr (jtr has no notion of it, see below). Candidate: duration argument of `fadeToStopWithFade:` for faded stops. | unknown |
| Fade Out All | For every object in `FGNowPlaying`, sets the player's `fadeOut` flag to true and refreshes the UI. No duration is passed from the app side. | **observed** (`ev_f8073cbc…`) |
| Stop All | `FGNowPlaying.stopAllWithExcept:nil` → each playing object gets `stopPlayingWithFade:`; fade flag appears false. | **observed** / flag *inferred* |
| Fade-in request | Clamped to **half the trimmed duration** before `startPlayingWithVolume:fadeIn:`. | **observed** |
| Export | Exported sound = cut from `startPackets` to `packetCount − endPackets`, then a fade-in envelope over `fadeInTime` and a fade-out envelope over `fadeOutTime`, baked with `jtr_clip_log_fade`. | **observed** (`ev_585172cf…`) |
| Player done | After a player stops, the tile clears its paused state and disconnects audio nodes **5 s** later. | **observed** (`ev_e5e519f2…`) |

### Engine side (jtr): five independent ramps per player

Each `JTRFilePlayer` owns five `JTRCrossfade` objects, created in
`commonInit`. **observed** (`ev_f34356eb…`, ivar offsets `ev_c714abfd…`)

| Ramp | Role | Duration | Evidence |
|---|---|---|---|
| `inCrossFade` | fade-in on start, used only while the `fadeIn` flag is set | see "fade-in quirk" below | `ev_470b9aa2…` |
| `outCrossFade` | fade-to-stop, used only while the `fadeOut` flag is set | 2.0 s by default; `fadeToStopWithFade:d` re-arms it 1→0 over d (only if playing) and sets `fadeOut` when d > 0 | `ev_470b9aa2…` |
| `autoCrossfade` | follows the player's own target volume (tile volume, A/B, mute, velocity) | 0.2 s per change | `ev_0cad0440…`, `ev_316eb5f3…` |
| `masterCrossfade` | follows the global master volume (A or B, mute) | 0.2 s per change | same |
| `safetyCrossfade` | 0→1 over min(sound duration, 20 s), used only when the global "enforcify" option and the per-player "needs enforcer" flag are both on | unknown purpose; not driven by Farrago as far as seen | `ev_470b9aa2…`, `ev_0cad0440…` |

- `resetFades` (called on every start and on reset) re-arms `outCrossFade`
  1→0 over **2.0 s**, `inCrossFade` 0→1 over **2.0 s**, and the safety ramp.
  A ramp only advances while it is being consulted, so the out ramp sits at
  full volume until `fadeOut` is set. **observed** (`ev_470b9aa2…`,
  `ev_0cad0440…`)
- **Fade Out All therefore fades over 2.0 s** (jtr's built-in default), unless
  the app re-armed the out ramp with `fadeToStopWithFade:` beforehand.
  **observed** in jtr; app-side override unknown.
- When `fadeOut` is set and the out ramp has finished, the player stops
  (scheduled after the already-buffered audio drains) and reports a normal
  stop to its delegate. **observed** (`ev_f4430721…`)
- Starting a player clears a pending `fadeOut`. **observed**
- **Fade-in quirk**: `startPlayingWithVolume:fadeIn:d` arms the in ramp over
  d and sets `fadeIn` when d > 0, then calls the plain start, which (if the
  player was not already playing) calls `resetFades` and re-arms the in ramp
  over 2.0 s. So any non-zero fade-in requested at start effectively lasts
  **2.0 s** whatever d was. **observed** call order; effective result
  *inferred* (no runtime check). This also applies to the Continuous
  crossfade's incoming tile.
- When starting with a fade-in, or resuming from pause, the first packet
  starts from silence; otherwise playback starts directly at its target
  gain. **observed** (`startPlayingWithVolume:`)

### Per-tile `fadeInTime` / `fadeOutTime` during live playback

Applied by `envelopeVolumesForFrame:` on every packet, independent of the
ramps above: a **linear** gain rise from 0 to 1 across the first
`fadeInTime` seconds after the start trim, and a linear fall to 0 across the
last `fadeOutTime` seconds before the end trim (time converted to frames by
the frames/duration ratio). The two envelopes are combined with min. Not
applied when both times are 0. **observed** (`ev_470b9aa2…`)

### Curves

| Path | Curve | Tag |
|---|---|---|
| All live ramps (`JTRCrossfade`) | linear in gain between start and target | **observed** (`ev_d20432d8…`) |
| Per-tile live envelope | linear in gain | **observed** |
| Within one packet | gain moves linearly, sample by sample, from the previous packet's gain to the new one (`fadeFromVol:toVol:overFrames:`), so every gain change is click-free | **observed** (`ev_470b9aa2…`, `ev_0cad0440…`) |
| `log_fade` (export bake, editor Fade In/Out Selection) | a linear ramp between the two end values, **squared** per sample: a power curve (slow start for fade-in, fast drop then long tail for fade-out). It is not dB-linear despite the name. | **observed** (`ev_f4430721…`) |
| Gain snapping | with "constrain volumes" on (default), gains below 0.00001 snap to 0 and above 0.99999 snap to 1 | **observed** (`ev_f34356eb…`) |

No live playback path uses `log_fade`. **observed** (only callers are the
Farrago export and editor functions, `ev_3b50d8b6…`)

## 4. Volume A / B ("duck")

Status: **answered** at engine level; app-level transition timing unknown.

- Per player, the target volume is 0 if the player or the global master is
  muted; otherwise it is (`ducked` ? `duckedVolume` : `fullVolume`) ×
  requested volume (the velocity / start volume). So **`ducked = true` means
  Volume B**. **observed** (`targetVolume`, `ev_470b9aa2…`)
- Engine defaults: `fullVolume` 1.0, `duckedVolume` 0.4 (same as the sample
  sets). **observed** (`commonInit`)
- Setting "current volume" on a player writes `duckedVolume` when ducked,
  else `fullVolume`; so the tile volume slider edits whichever of A/B is
  active. **observed**
- Master: global (class-level) `masterVolume`, `masterVolumeB`,
  `masterDucked`, `masterMuted`. The effective master is `masterVolumeB` when
  `masterDucked`, else `masterVolume`; setting the master "current volume"
  edits whichever is active. **observed**
- Final gain per packet = master ramp × tile-volume ramp × (fade-in ramp if
  active) × (fade-out ramp if active) × per-tile envelope, then snapped.
  **observed** (`ev_0cad0440…`)
- **Transition**: any change of the tile or master target (A↔B switch, slider
  move, mute) is followed by a linear ramp of **0.2 s**. **observed**
  (`ev_316eb5f3…`)
- App side: `toggleMasterVolumeMode:` ("Fade to Volume A/B", ⇧⌘D) only flips
  the master duck boolean. **observed** (`ev_7d73af7f…`). If the app forwards
  it straight to `masterDucked`, the audible switch is a 0.2 s ramp.
  *inferred*; an app-side slower animation (e.g. over `fadeTime`) was not
  seen but not excluded. `FadeBetweenVolumes` (Shortcuts) body not followed.
  unknown

## 5. Hold to Play, Pausable, Loop, playbackEnabled, velocity, preview

Status: **partial**.

- **Hold to Play**: on `mouseDown:` a Hold to Play tile is toggled
  immediately (starts); on `mouseUp:` it is set to not playing (stops). Stop
  on release is immediate (no fade). **observed** structure; slot 0x680 read
  as holdToPlay *inferred* (matches `holdToPlayForMode`). Ignored in list
  mode (§2).
- **Pausable** (`defaultToPause`): on start, the player's `resume` flag is set
  from a tile setting (not in preview). *inferred*: Pausable tiles pause on
  re-trigger and resume from the paused position; non-Pausable tiles restart.
- **Loop**: the player's `loop` flag is set from the tile's loop setting, and
  forced off in preview. **observed** (setter calls), slot meaning
  *inferred*.
- **playbackEnabled**: disabled tiles do not start (§1). *inferred*
- **Velocity**: the `velocity` float of the start call is stored as the tile's
  "immediate playback volume" and passed as the `volume` argument of
  `startPlayingWithVolume:fadeIn:`. Mouse/keyboard starts use 1.0.
  **observed**. In the engine this becomes the player's requested volume and
  is **multiplied** with the active tile volume (A or B) and the master
  volume. **observed** (§4, `ev_470b9aa2…`). How MIDI velocity is normalised
  and gated by the MIDI "velocity" preference: unknown.
- **Pause in the engine**: pausing stops the player with a "paused" state;
  un-pausing restarts it from the current position, ramping up from silence
  over the first packet. **observed** (`setPaused:`, `startPlayingWithVolume:`)
- **Preview**: preview starts skip solo handling and list selection, force
  loop and resume off. **observed**. Output on the preview device with
  `previewVolume` (default 1.0) is *inferred* from preference names.
- `FGTile.playerDidStop…`: on natural end or stop, a paused tile is
  un-paused. **observed**

## 6. Trim

Status: **answered**.

`startPackets` = number of packets skipped from the **start**; `endPackets` =
number of packets removed from the **end**; playable range is packet
`startPackets` through `packetCount − endPackets` (clamped to the last
packet). Units: codec packets (1024 frames for AAC). **observed** in the
export path (`ev_585172cf…`). `resetPlayState` rewinds the player to
`startPackets`. **observed** (`ev_cc22924d…`)

## 7. Played / unplayed and Reset List

Status: **partial**.

- `FGTile.resetPlayState` marks the player not playing, updates a tile state
  slot, and rewinds to `startPackets`. **observed**
- In `mouseDown:`, a click on the played indicator (list mode, when the tile
  is idle) toggles `lastPlayStart` between the "never played" sentinel and a
  played value. *inferred* (slots 0xe48/0xe50 compared against a sentinel).
- `resetList:` decompiles to an identical-code-folded helper; its real effect
  was not traced. *inferred* from the menu and `markAllTilesUnplayed:`:
  marks every tile unplayed (`lastPlayStart` = sentinel) and moves the
  selection to the first tile. unknown in detail.

## 8. Master volume step

Status: **answered**. Master Volume Up/Down change the master volume by
**±0.05** (5 % of full scale) per action, then refresh the volume view and
Stream Deck state. **observed** (`ev_e5e519f2…`). Clamping to [0, 1] was not
seen in the closure; *inferred* to happen in the setter.

## Rebuild decisions

- Model a tile trigger as a toggle: idle → play, playing → stop (immediate),
  paused → resume. Shift-trigger pauses. A modifier can request a faded stop.
- Hold to Play: start on press, stop on release. Ignore Hold to Play and Solo
  in list mode.
- Solo: after a solo tile starts, stop every other playing sound in the app
  (all sets). Default immediate; with a modifier, fade out over the global
  fade time.
- Set advance modes (list mode): `single` (do nothing), `advanceCue` (move
  selection to next playable tile when a tile ends), `continuous` (auto-start
  next playable tile X seconds before the end, X = min(crossfade, half the
  current sound); fade the outgoing sound over X unless it loops).
- Clamp any fade-in to half the trimmed sound duration; do the same for
  crossfade. Unlike Farrago, honour the requested fade-in duration (do not
  replace it by a fixed 2 s).
- Global fade time preference, default 2.0 s, used for Fade Out All and
  faded stops (this matches Farrago's effective 2 s). A fade-out stops the
  sound when it reaches silence.
- Gain chain per voice: master (A or B) × voice volume (A or B) × velocity ×
  fade-in ramp × fade-out ramp × per-tile envelope. Every change to master or
  voice volume (A/B switch, slider, mute) ramps linearly over 0.2 s; within a
  render buffer, interpolate gain per sample from the previous buffer's value.
  Snap gains within 1e-5 of 0 or 1.
- All live fades linear in gain. Per-tile fade in/out is a live linear
  envelope over the first/last N seconds of the trimmed region; export and
  editor fades use a squared-linear (power) curve. Keeping live linear and
  baked squared is our default for fidelity; may unify later.
- Volume A/B: per tile, `ducked` selects Volume B (default B = 0.4); the
  volume slider edits the active one. Master has its own A/B with a global
  toggle (⇧⌘D) that ramps over 0.2 s (slower app-level animation not seen).
- Trim stored as start offset and end offset (from end); store in frames, not
  codec packets.
- Master volume step 0.05, clamped to [0, 1].
- Velocity (MIDI) multiplies the voice gain; UI triggers use 1.0.
- Preview never loops or resumes, ignores solo, goes to the preview output at
  preview volume.
- Resume from pause and fade-in start from silence; other starts begin at
  full target gain (with per-buffer interpolation to avoid clicks).
- Release audio resources a few seconds after a sound stops.

## Open questions

- Where Farrago's `fadeTime` preference is consumed (likely as the duration of
  `fadeToStopWithFade:` for faded stops / Shortcuts "Fade sound"). Not visible
  from jtr; needs the Farrago session (snapshot) again.
- Whether the app animates the master A/B switch itself (slower than the
  engine's 0.2 s ramp), and the body of `FadeBetweenVolumes`.
- Purpose of jtr's "enforcify"/safety ramp and whether Farrago enables it.
- Exact effect of `resetList:` and of "Mark Played" (what value is written to
  `lastPlayStart`).
- Whether `defaultToPause` maps to the player's `resume` flag (slot 0x790),
  and what `resume` changes in jtr (not traced).
- How MIDI velocity is normalised and gated by the MIDI "velocity" preference.
- UI label ↔ value mapping for `playbackMode` (0/1/2) should be confirmed
  against the list-mode UI.
- Runtime confirmation of the 2 s fade-in quirk.
