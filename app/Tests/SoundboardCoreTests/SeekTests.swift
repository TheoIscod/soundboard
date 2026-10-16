import Foundation
import Testing

@testable import SoundboardCore

@Test func seekingStaysInsideASoundThatDoesNotLoop() {
  #expect(Seek.target(8, length: 10, loops: false) == 8)
  #expect(Seek.target(-2, length: 10, loops: false) == 0)
  #expect(Seek.target(13, length: 10, loops: false) == 9.75)
}

@Test func seekingWrapsAroundALoopingSound() {
  #expect(Seek.target(13, length: 10, loops: true) == 3)
  #expect(Seek.target(-3, length: 10, loops: true) == 7)
}

@Test func seekingAnEmptyRegionGoesToItsStart() {
  #expect(Seek.target(4, length: 0, loops: true) == 0)
}
