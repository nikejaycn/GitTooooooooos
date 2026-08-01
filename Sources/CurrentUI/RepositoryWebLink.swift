import CurrentDomain
import Foundation

enum RepositoryWebLink {
  static func commit(_ oid: String, remotes: [GitRemote]) -> URL? {
    preferredBaseURL(remotes: remotes)?
      .appendingPathComponent("commit", isDirectory: false)
      .appendingPathComponent(oid, isDirectory: false)
  }

  static func branch(_ name: String, remotes: [GitRemote]) -> URL? {
    preferredBaseURL(remotes: remotes)?
      .appendingPathComponent("tree", isDirectory: false)
      .appendingPathComponent(name, isDirectory: false)
  }

  static func baseURL(remoteURL: String) -> URL? {
    let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let webURL: URL?
    if let scp = parseSCPRemote(trimmed) {
      webURL = URL(string: "https://\(scp.host)/\(scp.path)")
    } else if var components = URLComponents(string: trimmed),
      let host = components.host,
      !host.isEmpty
    {
      components.scheme = "https"
      components.user = nil
      components.password = nil
      components.port = nil
      components.query = nil
      components.fragment = nil
      webURL = components.url
    } else {
      webURL = nil
    }

    guard let webURL else { return nil }
    var value = webURL.absoluteString
    while value.hasSuffix("/") {
      value.removeLast()
    }
    if value.hasSuffix(".git") {
      value.removeLast(4)
    }
    return URL(string: value)
  }

  private static func preferredBaseURL(remotes: [GitRemote]) -> URL? {
    let ordered = remotes.sorted {
      if ($0.name == "origin") != ($1.name == "origin") {
        return $0.name == "origin"
      }
      return $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
    for remote in ordered {
      if let url = baseURL(remoteURL: remote.fetchURL) {
        return url
      }
      if let url = baseURL(remoteURL: remote.pushURL) {
        return url
      }
    }
    return nil
  }

  private static func parseSCPRemote(_ value: String) -> (host: String, path: String)? {
    guard
      !value.contains("://"),
      let colon = value.firstIndex(of: ":"),
      let at = value[..<colon].lastIndex(of: "@")
    else {
      return nil
    }
    let host = String(value[value.index(after: at)..<colon])
    let path = String(value[value.index(after: colon)...])
    guard !host.isEmpty, !path.isEmpty else { return nil }
    return (host, path)
  }
}
