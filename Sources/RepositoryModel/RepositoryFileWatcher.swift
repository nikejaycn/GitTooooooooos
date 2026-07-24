import CoreServices
import CurrentDomain
import Foundation

public enum RepositoryWatchEventKind: Hashable, Sendable {
  case worktree
  case gitMetadata
  case objectDatabase
  case fullRescan
}

public struct RepositoryWatchEvent: Hashable, Sendable {
  public let path: String
  public let kind: RepositoryWatchEventKind
  public let eventID: UInt64

  public init(
    path: String,
    kind: RepositoryWatchEventKind,
    eventID: UInt64
  ) {
    self.path = path
    self.kind = kind
    self.eventID = eventID
  }

  public var requiresSnapshotRefresh: Bool {
    kind != .objectDatabase
  }
}

public enum RepositoryFileWatcherError: Error, LocalizedError {
  case streamCreationFailed
  case streamStartFailed

  public var errorDescription: String? {
    switch self {
    case .streamCreationFailed:
      "Could not create the repository file-event stream."
    case .streamStartFailed:
      "Could not start the repository file-event stream."
    }
  }
}

public struct RepositoryWatchEventClassifier: Sendable {
  private static let rescanFlags =
    FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
    | FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped)
    | FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped)
    | FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped)
    | FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)

  private let worktreePath: String
  private let gitDirectoryPath: String
  private let commonGitDirectoryPath: String
  private let objectDatabasePath: String
  private let isBare: Bool

  public init(location: RepositoryLocation) {
    worktreePath = Self.normalized(location.worktreeURL.path)
    gitDirectoryPath = Self.normalized(location.gitDirectoryURL.path)
    commonGitDirectoryPath = Self.normalized(location.commonGitDirectoryURL.path)
    objectDatabasePath = Self.normalized(
      location.commonGitDirectoryURL.appendingPathComponent("objects").path
    )
    isBare = location.kind == .bare
  }

  public func classify(
    path: String,
    flags: FSEventStreamEventFlags = 0
  ) -> RepositoryWatchEventKind {
    if flags & Self.rescanFlags != 0 {
      return .fullRescan
    }

    let normalizedPath = Self.normalized(path)
    if Self.isPath(normalizedPath, within: objectDatabasePath) {
      return .objectDatabase
    }
    if Self.isPath(normalizedPath, within: gitDirectoryPath)
      || Self.isPath(normalizedPath, within: commonGitDirectoryPath)
    {
      return .gitMetadata
    }
    if !isBare, Self.isPath(normalizedPath, within: worktreePath) {
      return .worktree
    }
    return .fullRescan
  }

  private static func normalized(_ path: String) -> String {
    let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
    guard standardized.count > 1, standardized.hasSuffix("/") else {
      return standardized
    }
    return String(standardized.dropLast())
  }

  private static func isPath(_ path: String, within root: String) -> Bool {
    path == root || path.hasPrefix(root + "/")
  }
}

private final class RepositoryFileWatcherCallbackBox: @unchecked Sendable {
  let classifier: RepositoryWatchEventClassifier
  let handler: @Sendable ([RepositoryWatchEvent]) -> Void

  init(
    classifier: RepositoryWatchEventClassifier,
    handler: @Sendable @escaping ([RepositoryWatchEvent]) -> Void
  ) {
    self.classifier = classifier
    self.handler = handler
  }
}

private let repositoryFileWatcherCallback: FSEventStreamCallback = {
  _, callbackInfo, eventCount, eventPaths, eventFlags, eventIDs in
  guard let callbackInfo else { return }
  let box = Unmanaged<RepositoryFileWatcherCallbackBox>
    .fromOpaque(callbackInfo)
    .takeUnretainedValue()
  let paths = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
  var events: [RepositoryWatchEvent] = []
  events.reserveCapacity(Int(eventCount))

  for index in 0..<Int(eventCount) {
    let path = String(cString: paths[index])
    let flags = eventFlags[index]
    events.append(
      RepositoryWatchEvent(
        path: path,
        kind: box.classifier.classify(path: path, flags: flags),
        eventID: eventIDs[index]
      )
    )
  }

  if !events.isEmpty {
    box.handler(events)
  }
}

private let repositoryFileWatcherRetain: CFAllocatorRetainCallBack = { info in
  guard let info else { return nil }
  _ = Unmanaged<RepositoryFileWatcherCallbackBox>.fromOpaque(info).retain()
  return info
}

private let repositoryFileWatcherRelease: CFAllocatorReleaseCallBack = { info in
  guard let info else { return }
  Unmanaged<RepositoryFileWatcherCallbackBox>.fromOpaque(info).release()
}

public final class RepositoryFileWatcher: @unchecked Sendable {
  private let callbackBox: RepositoryFileWatcherCallbackBox
  private let queue: DispatchQueue
  private var stream: FSEventStreamRef?

  public init(
    location: RepositoryLocation,
    latency: TimeInterval = 0.05,
    handler: @Sendable @escaping ([RepositoryWatchEvent]) -> Void
  ) throws {
    callbackBox = RepositoryFileWatcherCallbackBox(
      classifier: RepositoryWatchEventClassifier(location: location),
      handler: handler
    )
    queue = DispatchQueue(
      label: "com.fun2ex.Current.repository-watcher.\(UUID().uuidString)",
      qos: .utility
    )

    var context = FSEventStreamContext(
      version: 0,
      info: Unmanaged.passUnretained(callbackBox).toOpaque(),
      retain: repositoryFileWatcherRetain,
      release: repositoryFileWatcherRelease,
      copyDescription: nil
    )
    let roots = Self.watchRoots(for: location)
    let flags =
      FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
      | FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot)
      | FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)

    guard
      let createdStream = FSEventStreamCreate(
        nil,
        repositoryFileWatcherCallback,
        &context,
        roots as CFArray,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
        latency,
        flags
      )
    else {
      throw RepositoryFileWatcherError.streamCreationFailed
    }

    stream = createdStream
    FSEventStreamSetDispatchQueue(createdStream, queue)
    guard FSEventStreamStart(createdStream) else {
      FSEventStreamInvalidate(createdStream)
      FSEventStreamRelease(createdStream)
      stream = nil
      throw RepositoryFileWatcherError.streamStartFailed
    }
  }

  deinit {
    guard let stream else { return }
    FSEventStreamStop(stream)
    FSEventStreamInvalidate(stream)
    FSEventStreamRelease(stream)
  }

  private static func watchRoots(for location: RepositoryLocation) -> [String] {
    var roots: [String] = []
    if location.kind != .bare {
      roots.append(location.worktreeURL.standardizedFileURL.path)
    }

    // A standard repository's .git directory is already below the worktree.
    // Linked worktrees need both their private gitdir and the shared common dir.
    if location.kind != .standard {
      roots.append(location.gitDirectoryURL.standardizedFileURL.path)
      roots.append(location.commonGitDirectoryURL.standardizedFileURL.path)
    }

    var seen = Set<String>()
    return roots.filter { seen.insert($0).inserted }
  }
}

private struct RepositoryWatchSubscription {
  let commonGitDirectoryPath: String
  let handler: @Sendable ([RepositoryWatchEvent]) -> Void
}

public final class RepositoryWatchCoordinator: @unchecked Sendable {
  public static let shared = RepositoryWatchCoordinator()

  private let lock = NSLock()
  private var subscriptions: [UUID: RepositoryWatchSubscription] = [:]

  private init() {}

  fileprivate func subscribe(
    commonGitDirectoryURL: URL,
    handler: @Sendable @escaping ([RepositoryWatchEvent]) -> Void
  ) -> UUID {
    let id = UUID()
    let subscription = RepositoryWatchSubscription(
      commonGitDirectoryPath: commonGitDirectoryURL.standardizedFileURL.path,
      handler: handler
    )
    lock.withLock {
      subscriptions[id] = subscription
    }
    return id
  }

  fileprivate func unsubscribe(_ id: UUID) {
    _ = lock.withLock {
      subscriptions.removeValue(forKey: id)
    }
  }

  fileprivate func publish(
    _ events: [RepositoryWatchEvent],
    sourceID: UUID,
    commonGitDirectoryURL: URL
  ) {
    let commonPath = commonGitDirectoryURL.standardizedFileURL.path
    let deliveries: [(@Sendable ([RepositoryWatchEvent]) -> Void, [RepositoryWatchEvent])] =
      lock.withLock {
        subscriptions.compactMap { id, subscription in
          let matchingEvents = events.filter { event in
            switch event.kind {
            case .worktree:
              id == sourceID
            case .gitMetadata, .objectDatabase, .fullRescan:
              subscription.commonGitDirectoryPath == commonPath
            }
          }
          guard !matchingEvents.isEmpty else { return nil }
          return (subscription.handler, matchingEvents)
        }
      }

    for (handler, matchingEvents) in deliveries {
      handler(matchingEvents)
    }
  }
}

public final class RepositoryWatchSession: @unchecked Sendable {
  private let coordinator: RepositoryWatchCoordinator
  private let subscriptionID: UUID
  private let watcher: RepositoryFileWatcher

  public init(
    location: RepositoryLocation,
    coordinator: RepositoryWatchCoordinator = .shared,
    handler: @Sendable @escaping ([RepositoryWatchEvent]) -> Void
  ) throws {
    self.coordinator = coordinator
    let createdSubscriptionID = coordinator.subscribe(
      commonGitDirectoryURL: location.commonGitDirectoryURL,
      handler: handler
    )
    subscriptionID = createdSubscriptionID

    do {
      watcher = try RepositoryFileWatcher(location: location) { events in
        coordinator.publish(
          events,
          sourceID: createdSubscriptionID,
          commonGitDirectoryURL: location.commonGitDirectoryURL
        )
      }
    } catch {
      coordinator.unsubscribe(createdSubscriptionID)
      throw error
    }
  }

  deinit {
    coordinator.unsubscribe(subscriptionID)
  }
}
