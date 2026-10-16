import Foundation
import Testing

@testable import SoundboardCore

@Test func rampMovesLinearlyAndStopsAtTarget() {
  var ramp = LinearRamp(value: 0)
  ramp.move(to: 1, over: 0.2)

  #expect(abs(ramp.advance(by: 0.05) - 0.25) < 1e-6)
  #expect(abs(ramp.advance(by: 0.05) - 0.5) < 1e-6)
  #expect(!ramp.isFinished)

  #expect(ramp.advance(by: 1) == 1)
  #expect(ramp.isFinished)
}

@Test func rampWithZeroDurationJumpsImmediately() {
  var ramp = LinearRamp(value: 1)
  ramp.move(to: 0.4, over: 0)

  #expect(ramp.value == 0.4)
  #expect(ramp.isFinished)
}

@Test func retargetingStartsFromCurrentValue() {
  var ramp = LinearRamp(value: 0)
  ramp.move(to: 1, over: 1)
  ramp.advance(by: 0.5)

  ramp.move(to: 0, over: 1)
  #expect(abs(ramp.advance(by: 0.5) - 0.25) < 1e-6)
}

@Test func snapRoundsNearlySilentAndNearlyFullGains() {
  #expect(Gain.snapped(0.000_001) == 0)
  #expect(Gain.snapped(0.999_999) == 1)
  #expect(Gain.snapped(0.5) == 0.5)
}

@Test func envelopeFadesInAndOutLinearly() {
  let length = 10.0
  #expect(Gain.envelope(at: 0, length: length, fadeIn: 2, fadeOut: 2) == 0)
  #expect(Gain.envelope(at: 1, length: length, fadeIn: 2, fadeOut: 2) == 0.5)
  #expect(Gain.envelope(at: 5, length: length, fadeIn: 2, fadeOut: 2) == 1)
  #expect(Gain.envelope(at: 9, length: length, fadeIn: 2, fadeOut: 2) == 0.5)
  #expect(Gain.envelope(at: 10, length: length, fadeIn: 2, fadeOut: 2) == 0)
}

@Test func envelopeFadesAreClampedToHalfTheRegion() {
  // A 10 s fade-in on a 4 s sound is limited to 2 s.
  #expect(Gain.envelope(at: 1, length: 4, fadeIn: 10, fadeOut: 0) == 0.5)
  #expect(Gain.envelope(at: 2, length: 4, fadeIn: 10, fadeOut: 0) == 1)
}

@Test func loopingSoundsFadeInOnceAndNeverFadeOutOnTheirOwn() {
  // 10 s loop, 2 s fades: the fade-in only on the first pass, no dip at the loop end.
  #expect(Gain.envelope(at: 1, length: 10, fadeIn: 2, fadeOut: 2, loops: true) == 0.5)
  #expect(Gain.envelope(at: 9.5, length: 10, fadeIn: 2, fadeOut: 2, loops: true) == 1)
  #expect(Gain.envelope(at: 11, length: 10, fadeIn: 2, fadeOut: 2, loops: true) == 1)
}
