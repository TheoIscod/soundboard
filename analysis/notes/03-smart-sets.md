# Smart sets

Status: **observed** names and strings in the shipped binary
(`analysis/bin/Farrago.x86_64`, `strings`); behaviour beyond what the names say
is *inferred*. Not traced in Ghidra.

## Observed

| Observation | Source strings |
|---|---|
| Menu actions "New Smart Set" and "Edit Rules…" | `addSmartSet:`, `editSmartSet:` (MainMenu.nib, see 00-feature-map.md), "Add Smart Set", "Edit Smart Set Rules for" |
| A smart set is its own class, holding smart tiles | `FGSmartTileSet`, `FGSmartTile`, `isSmartSet`, `smartSets` |
| Smart tiles stand for tiles of ordinary sets | `allTilesInDumbSets`, `smartTileForTileWithParent:`, `smartTileMap`, `emptySmartTile` |
| Rules are an `NSPredicate`, edited in a rule editor | `FGPredicateModel`, `FGRuleEditor`, `FGRuleEditorWindowController`, `NSCompoundPredicate`, `andPredicateWithSubpredicates:`, `filteredArrayUsingPredicate:`, `matchFilterPredicateWithTiles:force:` |
| Rules can be combined with All / Any | "All", `compoundPredicateType` |
| Text rules ignore case and diacritics | `CONTAINS[cd]`, `BEGINSWITH[cd]`, `ENDSWITH[cd]` |
| Rule subjects | "Title", "Color", "Played", `DurationReplace`, `ruleFavorite`, `ruleHoldToPlay`, `ruleLoop`, `ruleResume`, `ruleSolo` |
| Matching is refreshed on a timer | `_updateSmartSetsTimer`, `_wantsSmartSetUpdate` |
| Rule editor has its own undo | `FGRuleEditorUndoManager` |

## Inferred behaviour

- A smart set has no sounds of its own. It shows every tile of the ordinary
  sets that matches its rules, and updates as tiles change.
- Playing a smart tile plays the original tile (same sound, same settings).
- "Resume" is the Pausable flag (`defaultToPause`, see 01-sound-set-format.md).
- "Played" means the tile has a last-play date.

## Unknown

- How Farrago orders and places smart tiles in the grid.
- Duration rule operators and units.
- Whether smart tiles can be edited, deleted or reordered from the smart set.

## Rebuild decisions

- `SoundSet.smartRules` (optional, so older sets still decode) makes a set
  smart: match **all** or **any** of a list of rules.
- Rules: title contains / begins with / ends with (case and diacritic
  insensitive), colour is, and is / is not for favourite, loop, hold to play,
  solo and played. Duration and pausable are left out until there is a UI to
  see a tile's length and to set pausable.
- Smart tiles are the original tiles, shown in sidebar order then grid
  order of their own set, laid out in a fresh grid. Playing, editing in the
  inspector, hotkeys and MIDI act on the original tile.
- A smart set can't receive dropped sounds, and its tiles can't be deleted or
  reordered from it (do that in their own set).
- A favourite toggle is added to the inspector and context menu, since
  "favourite" is the most natural smart-set rule and had no UI yet.
