import Foundation

/// A note on one MIDI channel, used to trigger a tile from a controller.
public struct MIDINote: Codable, Sendable, Hashable {
  /// 1…16, as shown on controllers.
  public var channel: Int
  /// 0…127; 60 is middle C (C3 in the Yamaha naming most controllers use).
  public var note: Int

  public init(channel: Int, note: Int) {
    self.channel = channel
    self.note = note
  }

  private static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

  /// Note name with octave, e.g. "C3" for note 60.
  public var noteName: String {
    "\(Self.names[note % 12])\(note / 12 - 2)"
  }
}

public enum MIDIMessage: Sendable, Equatable {
  /// Velocity 1…127; a note-on with velocity 0 is reported as a note-off.
  case noteOn(MIDINote, velocity: Int)
  case noteOff(MIDINote)

  /// Decodes a Universal MIDI Packet word carrying a MIDI 1.0 channel voice message
  /// (message type 2). Everything else (controllers, clock, system messages) gives nil.
  public init?(universalPacketWord word: UInt32) {
    guard word >> 28 == 0x2 else { return nil }
    let status = (word >> 20) & 0xF
    let note = MIDINote(channel: Int((word >> 16) & 0xF) + 1, note: Int((word >> 8) & 0x7F))
    let velocity = Int(word & 0x7F)
    switch status {
    case 0x9 where velocity > 0: self = .noteOn(note, velocity: velocity)
    case 0x9, 0x8: self = .noteOff(note)
    default: return nil
    }
  }

  /// Velocity as a gain factor: full velocity plays at the tile's own volume.
  public static func gain(forVelocity velocity: Int) -> Float {
    Float(min(max(velocity, 0), 127)) / 127
  }
}

extension SoundSet {
  public func tile(forMIDI note: MIDINote) -> Tile? {
    tiles.first { $0.midiTrigger == note }
  }

  /// Gives `note` to one tile, taking it away from any other tile of the set; nil clears it.
  public mutating func assignMIDI(_ note: MIDINote?, to tileID: UUID) {
    for index in tiles.indices {
      if tiles[index].id == tileID {
        tiles[index].midiTrigger = note
      } else if note != nil, tiles[index].midiTrigger == note {
        tiles[index].midiTrigger = nil
      }
    }
  }
}
