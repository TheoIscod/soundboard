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

  /// The message as a MIDI 1.0 channel voice Universal MIDI Packet word, group 0.
  public var universalPacketWord: UInt32 {
    let (status, note, velocity): (UInt32, MIDINote, Int) =
      switch self {
      case .noteOn(let note, let velocity): (0x9, note, velocity)
      case .noteOff(let note): (0x8, note, 0)
      }
    return (0x2 << 28) | (status << 20) | (UInt32(note.channel - 1) & 0xF) << 16
      | (UInt32(note.note) & 0x7F) << 8 | (UInt32(velocity) & 0x7F)
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

/// Which controller pads are lit, so only changes are sent: a pad lights while its tile plays.
public struct MIDILights: Sendable, Equatable {
  public private(set) var lit: Set<MIDINote> = []

  public init() {}

  /// Messages turning off pads no longer wanted and lighting new ones, with `velocity`
  /// (which picks the colour on many pad controllers). Updates what is recorded as lit.
  public mutating func update(to wanted: Set<MIDINote>, velocity: Int) -> [MIDIMessage] {
    let off = lit.subtracting(wanted).sorted(by: Self.order).map { MIDIMessage.noteOff($0) }
    let on = wanted.subtracting(lit).sorted(by: Self.order)
      .map { MIDIMessage.noteOn($0, velocity: min(max(velocity, 1), 127)) }
    lit = wanted
    return off + on
  }

  private static func order(_ lhs: MIDINote, _ rhs: MIDINote) -> Bool {
    (lhs.channel, lhs.note) < (rhs.channel, rhs.note)
  }
}
