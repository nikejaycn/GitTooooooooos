import Foundation
import GitParsers
import Testing

@Suite("Submodule machine parsers")
struct SubmoduleParsersTests {
  @Test("Parses config records with raw paths and optional branch")
  func parsesConfiguration() throws {
    let rawPath = Array("modules/demo \n\u{00E9}".utf8)
    var bytes = Array("submodule.demo.path\n".utf8)
    bytes += rawPath
    bytes += [0]
    bytes += Array("submodule.demo.url\nssh://example.test/repo.git\u{0}".utf8)
    bytes += Array("submodule.demo.branch\nmain\u{0}".utf8)
    bytes += Array("submodule.demo.update\ncheckout\u{0}".utf8)

    let modules = try SubmoduleConfigParser().parse(bytes)

    #expect(modules.count == 1)
    #expect(modules[0].name == "demo")
    #expect(modules[0].path == rawPath)
    #expect(modules[0].remoteURL == "ssh://example.test/repo.git")
    #expect(modules[0].branch == "main")
  }

  @Test("Parses checkout prefixes without reading path text")
  func parsesStatus() throws {
    let oid = String(repeating: "a", count: 40)
    let parser = SubmoduleStatusParser()

    #expect(
      try parser.parse(Array(" \(oid) modules/line\nbreak (heads/main)\n".utf8)).state
        == .current
    )
    #expect(
      try parser.parse(Array("-\(oid) modules/demo\n".utf8)).state == .uninitialized
    )
    #expect(
      try parser.parse(Array("+\(oid) modules/demo\n".utf8)).state == .pointerModified
    )
    #expect(
      try parser.parse(Array("U\(oid) modules/demo\n".utf8)).state == .conflicted
    )
  }

  @Test("Rejects incomplete configuration and malformed status")
  func rejectsMalformed() {
    #expect(throws: SubmoduleParserError.self) {
      try SubmoduleConfigParser().parse(
        Array("submodule.demo.path\nmodules/demo\u{0}".utf8)
      )
    }
    #expect(throws: SubmoduleParserError.self) {
      try SubmoduleStatusParser().parse(Array("?bad\n".utf8))
    }
  }
}
