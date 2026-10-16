import Foundation

/// One argument of an OSC message (OSC 1.0 types plus the common T/F booleans).
public enum OSCArgument: Sendable, Equatable {
  case int(Int32)
  case float(Float)
  case string(String)
  case bool(Bool)

  /// Numeric reading used by controls: buttons send 1/0, faders 0…1.
  public var number: Double? {
    switch self {
    case .int(let value): Double(value)
    case .float(let value): Double(value)
    case .bool(let value): value ? 1 : 0
    case .string: nil
    }
  }
}

public struct OSCMessage: Sendable, Equatable {
  public var address: String
  public var arguments: [OSCArgument]

  public init(address: String, arguments: [OSCArgument] = []) {
    self.address = address
    self.arguments = arguments
  }

  /// Messages in a UDP datagram: a single message, or a bundle (possibly nested).
  /// Malformed data gives no messages rather than partial ones.
  public static func decodePacket(_ data: Data) -> [OSCMessage] {
    var reader = Reader(bytes: [UInt8](data))
    return (try? reader.packet(length: data.count)) ?? []
  }

  /// The message as an OSC datagram.
  public func encoded() -> Data {
    var bytes = Self.padded(address)
    var tags = ","
    var payload: [UInt8] = []
    for argument in arguments {
      switch argument {
      case .int(let value):
        tags += "i"
        payload += withUnsafeBytes(of: value.bigEndian, Array.init)
      case .float(let value):
        tags += "f"
        payload += withUnsafeBytes(of: value.bitPattern.bigEndian, Array.init)
      case .string(let value):
        tags += "s"
        payload += Self.padded(value)
      case .bool(let value):
        tags += value ? "T" : "F"
      }
    }
    bytes += Self.padded(tags) + payload
    return Data(bytes)
  }

  /// OSC strings are NUL-terminated and padded to a multiple of 4 bytes.
  private static func padded(_ string: String) -> [UInt8] {
    var bytes = Array(string.utf8) + [0]
    while bytes.count % 4 != 0 { bytes.append(0) }
    return bytes
  }
}

private struct Reader {
  enum Failure: Error { case malformed }

  let bytes: [UInt8]
  var offset = 0

  mutating func packet(length: Int) throws -> [OSCMessage] {
    let end = offset + length
    guard end <= bytes.count else { throw Failure.malformed }
    if bytes[offset...].starts(with: Array("#bundle".utf8) + [0]) {
      offset += 16  // "#bundle\0" and the 8-byte time tag, ignored: messages act on arrival.
      var messages: [OSCMessage] = []
      while offset < end {
        let size = Int(try int32())
        guard size > 0, size % 4 == 0 else { throw Failure.malformed }
        messages += try packet(length: size)
      }
      return messages
    }
    let message = try self.message()
    guard offset <= end else { throw Failure.malformed }
    offset = end
    return [message]
  }

  private mutating func message() throws -> OSCMessage {
    let address = try string()
    guard address.hasPrefix("/") else { throw Failure.malformed }
    // A message without a type tag string has no arguments (old OSC senders).
    guard offset < bytes.count, bytes[offset] == UInt8(ascii: ",") else {
      return OSCMessage(address: address)
    }
    let tags = try string().dropFirst()
    var arguments: [OSCArgument] = []
    for tag in tags {
      switch tag {
      case "i": arguments.append(.int(try int32()))
      case "f": arguments.append(.float(Float(bitPattern: UInt32(bitPattern: try int32()))))
      case "s": arguments.append(.string(try string()))
      case "T": arguments.append(.bool(true))
      case "F": arguments.append(.bool(false))
      default: throw Failure.malformed  // Unknown types have unknown sizes.
      }
    }
    return OSCMessage(address: address, arguments: arguments)
  }

  private mutating func int32() throws -> Int32 {
    guard offset + 4 <= bytes.count else { throw Failure.malformed }
    let value = bytes[offset..<offset + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    offset += 4
    return Int32(bitPattern: value)
  }

  private mutating func string() throws -> String {
    guard let terminator = bytes[offset...].firstIndex(of: 0) else { throw Failure.malformed }
    let string = String(decoding: bytes[offset..<terminator], as: UTF8.self)
    offset = (terminator + 4) & ~3
    guard offset <= bytes.count else { throw Failure.malformed }
    return string
  }
}
