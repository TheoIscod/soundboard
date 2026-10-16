import Foundation
import Testing

@testable import SoundboardCore

@Test func messagesRoundTripThroughTheWireFormat() {
  let message = OSCMessage(
    address: "/set/0/tile/1/2/play",
    arguments: [.float(1), .int(-3), .string("abc"), .bool(true), .bool(false)]
  )

  let data = message.encoded()

  #expect(data.count % 4 == 0)
  #expect(OSCMessage.decodePacket(data) == [message])
}

@Test func encodingMatchesTheOSCLayout() {
  // "/a" padded to 4, ",f" padded to 4, then 1.0 as big-endian float.
  let data = OSCMessage(address: "/a", arguments: [.float(1)]).encoded()

  #expect([UInt8](data) == [0x2F, 0x61, 0, 0, 0x2C, 0x66, 0, 0, 0x3F, 0x80, 0, 0])
}

@Test func bundlesYieldEveryMessage() {
  let first = OSCMessage(address: "/transport/stopAll").encoded()
  let second = OSCMessage(address: "/master/toggleAB", arguments: [.int(1)]).encoded()
  var bundle = Data("#bundle".utf8) + [0] + Data(count: 8)
  for element in [first, second] {
    bundle += withUnsafeBytes(of: Int32(element.count).bigEndian) { Data($0) } + element
  }

  #expect(
    OSCMessage.decodePacket(bundle).map(\.address) == ["/transport/stopAll", "/master/toggleAB"])
}

@Test func malformedPacketsGiveNoMessages() {
  #expect(OSCMessage.decodePacket(Data([0x2F, 0x61])).isEmpty)
  #expect(OSCMessage.decodePacket(Data("hello\0\0\0".utf8)).isEmpty)
  #expect(OSCMessage.decodePacket(Data("/a\0\0,z\0\0".utf8)).isEmpty)
}

@Test func tileAddressesFollowFarragosScheme() {
  let press = OSCMessage(address: "/set/2/tile/3/1/play", arguments: [.float(1)])
  let release = OSCMessage(address: "/set/selected/tile/0/0/play", arguments: [.int(0)])

  #expect(
    OSCCommand(press) == .tile(.index(2), GridPosition(column: 3, row: 1), .play, pressed: true))
  #expect(
    OSCCommand(release) == .tile(.selected, GridPosition(column: 0, row: 0), .play, pressed: false))
  #expect(
    OSCCommand(OSCMessage(address: "/set/0/tile/0/0/toggleAB"))?.isTileAction(.toggleAB) == true)
  #expect(OSCCommand(OSCMessage(address: "/set/0/tile/0/0/explode")) == nil)
  #expect(OSCCommand(OSCMessage(address: "/set/-1/tile/0/0/play")) == nil)
}

@Test func globalCommandsIgnoreButtonReleases() {
  #expect(OSCCommand(OSCMessage(address: "/transport/stopAll")) == .stopAll)
  #expect(OSCCommand(OSCMessage(address: "/transport/stopAll", arguments: [.float(0)])) == nil)
  #expect(
    OSCCommand(OSCMessage(address: "/master/toggleAB", arguments: [.bool(true)])) == .masterToggleAB
  )
  #expect(
    OSCCommand(OSCMessage(address: "/master/volume", arguments: [.float(1.7)])) == .masterVolume(1))
  #expect(OSCCommand(OSCMessage(address: "/master/volume")) == nil)
}

@Test func playingFeedbackAddressesTheTileByPosition() {
  #expect(
    OSCCommand.playingFeedback(
      setIndex: 1, position: GridPosition(column: 4, row: 2), isPlaying: true)
      == OSCMessage(address: "/set/1/tile/4/2/play", arguments: [.float(1)]))
}

extension OSCCommand {
  fileprivate func isTileAction(_ action: TileAction) -> Bool {
    if case .tile(_, _, let tileAction, _) = self { return tileAction == action }
    return false
  }
}

@Test func deeplyNestedBundlesAreRefused() {
  var packet = OSCMessage(address: "/transport/stopAll").encoded()
  for _ in 0..<12 {
    packet =
      Data("#bundle".utf8) + [0] + Data(count: 8)
      + withUnsafeBytes(of: Int32(packet.count).bigEndian) { Data($0) } + packet
  }
  #expect(OSCMessage.decodePacket(packet).isEmpty)
}
