import Foundation
import Testing

@testable import SoundboardCore

@Test func masterStartsAtFullVolumeA() {
  let master = MasterVolume()

  #expect(master.gain == 1)
  #expect(!master.usesVolumeB)
}

@Test func togglingABSwitchesTheGainBetweenPresets() {
  var master = MasterVolume()

  master.toggleAB()
  #expect(master.gain == 0.4)
  master.toggleAB()
  #expect(master.gain == 1)
}

@Test func stepsEditOnlyTheActivePresetAndStayInRange() {
  var master = MasterVolume()
  master.stepUp()
  #expect(master.volumeA == 1)

  master.toggleAB()
  master.stepDown()
  #expect(abs(master.volumeB - 0.35) < 1e-6)
  #expect(master.volumeA == 1)

  master.activeVolume = -2
  #expect(master.volumeB == 0)
}

@Test func muteSilencesWithoutForgettingTheLevel() {
  var master = MasterVolume()
  master.muted = true

  #expect(master.gain == 0)
  #expect(master.activeVolume == 1)
}
