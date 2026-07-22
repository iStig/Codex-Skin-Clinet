import Foundation

@main
struct LocalizationTests {
  static func main() throws {
    guard CommandLine.arguments.count == 3 else { throw TestError("missing resource or source root") }
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let sourceRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    let locales = ["en", "zh-Hans", "ja"]
    let tables = try Dictionary(uniqueKeysWithValues: locales.map { locale in
      let url = root.appendingPathComponent("\(locale).lproj/Localizable.strings")
      let data = try Data(contentsOf: url)
      var format = PropertyListSerialization.PropertyListFormat.openStep
      guard let table = try PropertyListSerialization.propertyList(
        from: data,
        options: [],
        format: &format
      ) as? [String: String] else {
        throw TestError("invalid strings table: \(locale)")
      }
      return (locale, table)
    })

    guard let english = tables["en"], !english.isEmpty else { throw TestError("empty English table") }
    let expectedKeys = Set(english.keys)
    let sourceKeys = try localizedKeys(in: sourceRoot)
    guard sourceKeys == expectedKeys else {
      let missing = sourceKeys.subtracting(expectedKeys).sorted().joined(separator: ", ")
      let unused = expectedKeys.subtracting(sourceKeys).sorted().joined(separator: ", ")
      throw TestError("source/resource key mismatch; missing=[\(missing)] unused=[\(unused)]")
    }
    for locale in locales {
      guard let table = tables[locale], Set(table.keys) == expectedKeys else {
        throw TestError("localization keys differ: \(locale)")
      }
      for key in expectedKeys {
        guard let value = table[key], !value.isEmpty else { throw TestError("empty value: \(locale) / \(key)") }
        guard placeholders(in: value) == placeholders(in: key) else {
          throw TestError("format placeholders differ: \(locale) / \(key)")
        }
      }
    }
    print("PASS: English, Simplified Chinese, and Japanese localization tables are complete.")
  }

  private static func placeholders(in value: String) -> [String] {
    let expression = try! NSRegularExpression(pattern: "%[@d]")
    let range = NSRange(value.startIndex..., in: value)
    return expression.matches(in: value, range: range).compactMap { match in
      Range(match.range, in: value).map { String(value[$0]) }
    }.sorted()
  }

  private static func localizedKeys(in root: URL) throws -> Set<String> {
    let manager = FileManager.default
    guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: nil) else {
      throw TestError("cannot enumerate Swift sources")
    }
    let expression = try NSRegularExpression(
      pattern: #"L10n\.(?:text|format)\(\s*"([^"]+)""#,
      options: [.dotMatchesLineSeparators]
    )
    var keys = Set<String>()
    for case let url as URL in enumerator where url.pathExtension == "swift" {
      let source = try String(contentsOf: url, encoding: .utf8)
      let range = NSRange(source.startIndex..., in: source)
      for match in expression.matches(in: source, range: range) {
        guard let keyRange = Range(match.range(at: 1), in: source) else { continue }
        keys.insert(String(source[keyRange]))
      }
    }
    return keys
  }
}

private struct TestError: Error {
  let message: String
  init(_ message: String) { self.message = message }
}
