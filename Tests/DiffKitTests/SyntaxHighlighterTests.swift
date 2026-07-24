import CurrentDomain
import DiffKit
import Foundation
import Testing

@Suite("Tree-sitter syntax highlighting")
struct SyntaxHighlighterTests {
  @Test("Detects the twelve supported language families")
  func languageDetection() {
    let expected: [(String, SyntaxLanguage)] = [
      ("File.swift", .swift),
      ("file.c", .c),
      ("file.hpp", .cpp),
      ("file.m", .objectiveC),
      ("file.mjs", .javaScript),
      ("file.ts", .typeScript),
      ("file.py", .python),
      ("file.go", .go),
      ("file.rs", .rust),
      ("File.java", .java),
      ("data.json", .json),
      ("config.yml", .yaml),
    ]

    for (path, language) in expected {
      #expect(SyntaxLanguage.detect(path: GitPath(path)) == language)
    }
    #expect(SyntaxLanguage.detect(path: GitPath("README.md")) == nil)
  }

  @Test("Loads every grammar and emits bounded UTF-16 ranges")
  func grammarSmokeTest() async throws {
    let fixtures: [(path: String, source: String)] = [
      ("File.swift", #"struct Box { let value = "x" }"#),
      ("file.c", "int main(void) { return 1; }"),
      ("file.cpp", "class Box { public: int value; };"),
      ("file.m", "@interface Box : NSObject\n@end"),
      ("file.js", #"const value = "x";"#),
      ("file.ts", "interface Box { value: string }"),
      ("file.tsx", "const App = () => <View />;"),
      ("file.py", #"def greet(name): return "hi""#),
      ("file.go", "package main\nfunc main() {}"),
      ("file.rs", "fn main() { let value = 1; }"),
      ("File.java", #"class Box { String value = "x"; }"#),
      ("data.json", #"{"value": 1}"#),
      ("config.yaml", "value: 1"),
    ]
    let service = SyntaxHighlightService()

    for fixture in fixtures {
      let result = try #require(
        try await service.highlights(
          in: fixture.source,
          path: GitPath(fixture.path)
        )
      )
      #expect(!result.spans.isEmpty, "Expected captures for \(fixture.path)")
      let utf16Length = fixture.source.utf16.count
      #expect(
        result.spans.allSatisfy {
          $0.range.location >= 0
            && $0.range.length > 0
            && NSMaxRange($0.range) <= utf16Length
        }
      )
    }
  }

  @Test("Skips unsupported and oversized inputs")
  func degradation() async throws {
    let service = SyntaxHighlightService()
    #expect(
      try await service.highlights(
        in: "plain",
        path: GitPath("README.md")
      ) == nil
    )
    let oversized = String(
      repeating: "x",
      count: SyntaxHighlightService.maximumUTF16Length + 1
    )
    #expect(
      try await service.highlights(
        in: oversized,
        path: GitPath("file.swift")
      ) == nil
    )
  }

  @Test("Maps only visible source captures into rendered diff text")
  func projection() {
    let projection = SyntaxHighlightProjection(
      sourceText: "let value = 1\n",
      mappings: [
        SyntaxRangeMapping(
          sourceRange: NSRange(location: 0, length: 13),
          renderedRange: NSRange(location: 21, length: 13)
        )
      ]
    )

    #expect(
      projection.sourceRange(
        intersecting: NSRange(location: 25, length: 5)
      ) == NSRange(location: 0, length: 13)
    )
    #expect(
      projection.sourceRange(
        intersecting: NSRange(location: 0, length: 10)
      ) == nil
    )

    let rendered = projection.render(
      [
        SyntaxHighlightSpan(
          range: NSRange(location: 0, length: 3),
          kind: .keyword
        ),
        SyntaxHighlightSpan(
          range: NSRange(location: 4, length: 5),
          kind: .variable
        ),
      ],
      within: NSRange(location: 21, length: 7)
    )
    #expect(
      rendered == [
        RenderedSyntaxSpan(
          range: NSRange(location: 21, length: 3),
          kind: .keyword
        ),
        RenderedSyntaxSpan(
          range: NSRange(location: 25, length: 3),
          kind: .variable
        ),
      ]
    )
  }
}
