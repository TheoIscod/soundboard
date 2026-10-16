import Foundation
import Testing

@testable import SoundboardCore

@Test func peaksKeepTheExtremesOfEachSlice() {
  let samples: [Float] = [0.1, -0.5, 0.3, 0.9, -0.2, 0.0]

  #expect(
    Waveform.peaks(of: samples, binCount: 2) == [
      WaveformPeak(low: -0.5, high: 0.3), WaveformPeak(low: -0.2, high: 0.9),
    ])
}

@Test func shortSoundsGetOneBinPerSample() {
  #expect(Waveform.peaks(of: [0.5, -0.5], binCount: 600).count == 2)
  #expect(Waveform.peaks(of: [], binCount: 600).isEmpty)
}

@Test func startCannotPassTheEndMinusTheMinimumLength() {
  let editor = TrimEditor(duration: 10)
  var settings = PlayerSettings()
  settings.trimEnd = 2

  #expect(editor.settingStart(4, in: settings).trimStart == 4)
  #expect(abs(editor.settingStart(9.5, in: settings).trimStart - 7.9) < 1e-9)
  #expect(editor.settingStart(-3, in: settings).trimStart == 0)
}

@Test func endIsStoredAsTimeCutFromTheEnd() {
  let editor = TrimEditor(duration: 10)
  var settings = PlayerSettings()
  settings.trimStart = 3

  #expect(editor.settingEnd(8, in: settings).trimEnd == 2)
  #expect(abs(editor.settingEnd(1, in: settings).trimEnd - 6.9) < 1e-9)
  #expect(editor.settingEnd(12, in: settings).trimEnd == 0)
}

@Test func fadesFitInHalfThePlayablePart() {
  let editor = TrimEditor(duration: 10)
  var settings = PlayerSettings()
  settings.trimStart = 2
  settings.trimEnd = 2

  #expect(editor.settingFadeInEnd(3, in: settings).fadeInTime == 1)
  #expect(editor.settingFadeInEnd(9, in: settings).fadeInTime == 3)
  #expect(editor.settingFadeOutStart(6, in: settings).fadeOutTime == 2)
  #expect(editor.settingFadeOutStart(0, in: settings).fadeOutTime == 3)
}

@Test func trimmingShrinksFadesThatNoLongerFit() {
  let editor = TrimEditor(duration: 10)
  var settings = PlayerSettings()
  settings.fadeInTime = 4
  settings.fadeOutTime = 4

  let trimmed = editor.settingStart(6, in: settings)

  #expect(trimmed.fadeInTime == 2)
  #expect(trimmed.fadeOutTime == 2)
}
