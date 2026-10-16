import Foundation
import Testing

@testable import SoundboardCore

/// A MIDI 1.0 channel voice Universal MIDI Packet word.
private func word(status: UInt32, channel: UInt32, note: UInt32, velocity: UInt32) -> UInt32 {
  (0x2 << 28) | (status << 20) | (channel << 16) | (note << 8) | velocity
}

@Test func noteOnAndOffAreDecodedWithOneBasedChannels() {
  let middleC = MIDINote(channel: 1, note: 60)

  #expect(
    MIDIMessage(universalPacketWord: word(status: 0x9, channel: 0, note: 60, velocity: 100))
      == .noteOn(middleC, velocity: 100))
  #expect(
    MIDIMessage(universalPacketWord: word(status: 0x8, channel: 0, note: 60, velocity: 64))
      == .noteOff(middleC))
  #expect(
    MIDIMessage(universalPacketWord: word(status: 0x9, channel: 15, note: 36, velocity: 1))
      == .noteOn(MIDINote(channel: 16, note: 36), velocity: 1))
}

@Test func noteOnWithZeroVelocityIsANoteOff() {
  #expect(
    MIDIMessage(universalPacketWord: word(status: 0x9, channel: 2, note: 40, velocity: 0))
      == .noteOff(MIDINote(channel: 3, note: 40)))
}

@Test func otherMessagesAreIgnored() {
  // Control change on a MIDI 1.0 word, and a MIDI 2.0 note-on (message type 4).
  #expect(
    MIDIMessage(universalPacketWord: word(status: 0xB, channel: 0, note: 7, velocity: 90)) == nil)
  #expect(MIDIMessage(universalPacketWord: (0x4 << 28) | (0x9 << 20) | (60 << 8)) == nil)
}

@Test func velocityMapsLinearlyToGain() {
  #expect(MIDIMessage.gain(forVelocity: 127) == 1)
  #expect(MIDIMessage.gain(forVelocity: 0) == 0)
  #expect(abs(MIDIMessage.gain(forVelocity: 64) - 0.504) < 0.001)
}

@Test func noteNamesUseTheC3MiddleConvention() {
  #expect(MIDINote(channel: 1, note: 60).noteName == "C3")
  #expect(MIDINote(channel: 1, note: 0).noteName == "C-2")
  #expect(MIDINote(channel: 1, note: 70).noteName == "A#3")
}

@Test func assigningANoteTakesItFromTheOtherTile() {
  var set = SoundSet(title: "Pads")
  let first = Tile(fileID: UUID(), originalFileName: "a.m4a", title: "A")
  let second = Tile(fileID: UUID(), originalFileName: "b.m4a", title: "B")
  set.tiles = [first, second]
  let pad = MIDINote(channel: 10, note: 36)

  set.assignMIDI(pad, to: first.id)
  set.assignMIDI(pad, to: second.id)

  #expect(set.tile(forMIDI: pad)?.id == second.id)
  #expect(set.tiles[0].midiTrigger == nil)
}

@Test func pressCarriesTheVelocityIntoTheStartCommand() {
  var coordinator = PlaybackCoordinator()
  let tile = Tile(fileID: UUID(), originalFileName: "a.m4a", title: "A")

  #expect(coordinator.press(tile, velocity: 0.5) == [.start(tile.id, velocity: 0.5)])
}

@Test func encodedMessagesDecodeBackToThemselves() {
  let messages: [MIDIMessage] = [
    .noteOn(MIDINote(channel: 1, note: 60), velocity: 100),
    .noteOn(MIDINote(channel: 16, note: 127), velocity: 1),
    .noteOff(MIDINote(channel: 10, note: 36)),
  ]

  for message in messages {
    #expect(MIDIMessage(universalPacketWord: message.universalPacketWord) == message)
  }
  #expect(
    MIDIMessage.noteOn(MIDINote(channel: 1, note: 60), velocity: 100).universalPacketWord
      == 0x2090_3C64)
}

@Test func lightsSendOnlyChanges() {
  var lights = MIDILights()
  let kick = MIDINote(channel: 10, note: 36)
  let snare = MIDINote(channel: 10, note: 38)

  #expect(lights.update(to: [kick], velocity: 127) == [.noteOn(kick, velocity: 127)])
  #expect(lights.update(to: [kick], velocity: 127) == [])
  #expect(lights.update(to: [snare], velocity: 5) == [.noteOff(kick), .noteOn(snare, velocity: 5)])
  #expect(lights.update(to: [], velocity: 127) == [.noteOff(snare)])
  #expect(lights.lit.isEmpty)
}
