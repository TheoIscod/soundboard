import Foundation
import Testing

@testable import SoundboardCore

private func command(_ string: String) -> URLCommand? {
  URL(string: string).flatMap(URLCommand.init)
}

@Test func tileCommandsTakeATitleAndAnOptionalSet() {
  #expect(command("soundboard://play?title=Bonjour") == .tile(title: "Bonjour", set: nil, .play))
  #expect(
    command("soundboard://fade?title=Applaudissements%20%C3%A9t%C3%A9&set=Effets")
      == .tile(title: "Applaudissements été", set: "Effets", .fade))
  #expect(command("soundboard://stop?title=") == nil)
  #expect(command("soundboard://play") == nil)
}

@Test func setCommandShowsASetByName() {
  #expect(command("soundboard://set?title=Musique") == .showSet(title: "Musique"))
}

@Test func oscAddressesWorkAsPaths() {
  #expect(command("soundboard://transport/stopAll") == .osc(.stopAll))
  #expect(command("soundboard://master/volume?value=0.25") == .osc(.masterVolume(0.25)))
  #expect(
    command("soundboard://set/0/tile/1/0/play")
      == .osc(.tile(.index(0), GridPosition(column: 1, row: 0), .play, pressed: true)))
}

@Test func otherLinksAreRejected() {
  #expect(command("https://example.com/play?title=x") == nil)
  #expect(command("soundboard://explode") == nil)
  #expect(command("SOUNDBOARD://transport/stopAll") == .osc(.stopAll))
}

@Test func namesMatchIgnoringCaseAccentsAndOuterSpaces() {
  #expect(URLCommand.sameName(" Été ", "ete"))
  #expect(!URLCommand.sameName("Bonjour", "Bonsoir"))
}

@Test func namesEncodedTwiceAreDecoded() {
  #expect(
    command("soundboard://play?title=Applaudissements%2520%C3%89t%C3%A9")
      == .tile(title: "Applaudissements Été", set: nil, .play))
}
