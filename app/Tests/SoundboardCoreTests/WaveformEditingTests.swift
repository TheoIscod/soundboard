import Foundation
import Testing

@testable import SoundboardCore

@Test func rangesAreOrderedWhateverTheDragDirection() {
  #expect(TimeRange(5, 2) == TimeRange(2, 5))
  #expect(TimeRange(5, 2).length == 3)
}

@Test func zoomHalvesAroundTheCentreAndStaysInsideTheSound() {
  var viewport = WaveformViewport(duration: 8)

  viewport.zoomIn()
  #expect(viewport.visible == TimeRange(2, 6))

  viewport.scroll(by: 10)
  #expect(viewport.visible == TimeRange(4, 8))

  viewport.zoomOut()
  viewport.zoomOut()
  #expect(viewport.visible == TimeRange(0, 8))
}

@Test func zoomStopsAtTheMinimumLength() {
  var viewport = WaveformViewport(duration: 1)
  for _ in 0..<20 { viewport.zoomIn() }

  #expect(abs(viewport.visible.length - WaveformViewport.minimumLength) < 1e-12)
}

@Test func zoomToSelectionShowsExactlyTheSelection() {
  var viewport = WaveformViewport(duration: 10)
  viewport.zoom(to: TimeRange(3, 4))

  #expect(viewport.visible == TimeRange(3, 4))
  viewport.zoomToFit()
  #expect(viewport.visible == TimeRange(0, 10))
}

@Test func positionsMapToTimesInTheVisibleSpan() {
  var viewport = WaveformViewport(duration: 10)
  viewport.zoom(to: TimeRange(2, 4))

  #expect(viewport.time(atX: 50, width: 100) == 3)
  #expect(viewport.time(atX: 500, width: 100) == 4)
  #expect(viewport.x(of: 3, width: 100) == 50)
  #expect(viewport.x(of: 6, width: 100) == 200)
}

@Test func cropKeepsOnlyTheSelection() {
  let editor = TrimEditor(duration: 10)

  let cropped = editor.cropping(to: TimeRange(2, 7), in: PlayerSettings())

  #expect(cropped.trimStart == 2)
  #expect(cropped.trimEnd == 3)
}

@Test func cropWorksWhenTheSelectionIsAfterAnEarlierTrim() {
  let editor = TrimEditor(duration: 10)
  var trimmed = PlayerSettings()
  trimmed.trimStart = 1
  trimmed.trimEnd = 8  // plays 1…2

  let cropped = editor.cropping(to: TimeRange(5, 9), in: trimmed)

  #expect(cropped.trimStart == 5)
  #expect(cropped.trimEnd == 1)
}

@Test func fadeSelectionMovesTheBoundAndFadesOverTheSelection() {
  let editor = TrimEditor(duration: 10)

  let fadedIn = editor.fadingIn(over: TimeRange(1, 3), in: PlayerSettings())
  #expect(fadedIn.trimStart == 1)
  #expect(fadedIn.fadeInTime == 2)

  let fadedOut = editor.fadingOut(over: TimeRange(6, 9), in: PlayerSettings())
  #expect(fadedOut.trimEnd == 1)
  #expect(fadedOut.fadeOutTime == 3)
}

@Test func revertClearsTrimAndFadesOnly() {
  var settings = PlayerSettings()
  settings.trimStart = 1
  settings.fadeOutTime = 2
  settings.loops = true

  let reverted = TrimEditor(duration: 10).reverting(settings)

  #expect(reverted.trimStart == 0 && reverted.fadeOutTime == 0)
  #expect(reverted.loops)
}
