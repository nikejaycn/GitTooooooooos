import CoreServices
import Foundation

private final class RepositoryCatalogWatchCallbackBox: @unchecked Sendable {
  let roots: [String]
  let handler: @Sendable (Set<String>) -> Void

  init(roots: [String], handler: @Sendable @escaping (Set<String>) -> Void) {
    self.roots = roots
    self.handler = handler
  }
}

private let catalogWatchRetain: CFAllocatorRetainCallBack = { info in
  guard let info else { return nil }
  _ = Unmanaged<RepositoryCatalogWatchCallbackBox>.fromOpaque(info).retain()
  return info
}

private let catalogWatchRelease: CFAllocatorReleaseCallBack = { info in
  guard let info else { return }
  Unmanaged<RepositoryCatalogWatchCallbackBox>.fromOpaque(info).release()
}

private let catalogWatchCallback: FSEventStreamCallback = {
  _, callbackInfo, eventCount, eventPaths, eventFlags, _ in
  guard let callbackInfo else { return }
  let box = Unmanaged<RepositoryCatalogWatchCallbackBox>
    .fromOpaque(callbackInfo).takeUnretainedValue()
  let paths = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
  let rescanFlags = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
    | FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped)
    | FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped)
    | FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)
  var affected = Set<String>()

  for index in 0..<Int(eventCount) {
    if eventFlags[index] & rescanFlags != 0 {
      affected.formUnion(box.roots)
      continue
    }
    let path = String(cString: paths[index])
    for root in box.roots where path == root || path.hasPrefix(root + "/") {
      affected.insert(root)
    }
  }
  if !affected.isEmpty { box.handler(affected) }
}

private final class RepositoryCatalogWatchSession: @unchecked Sendable {
  private let callbackBox: RepositoryCatalogWatchCallbackBox
  private let queue = DispatchQueue(
    label: "com.fun2ex.Current.catalog-watcher", qos: .utility
  )
  private var stream: FSEventStreamRef?

  init(
    rootPaths: [String],
    handler: @Sendable @escaping (Set<String>) -> Void
  ) throws {
    let roots = Array(Set(rootPaths.map {
      URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL.path
    })).sorted()
    callbackBox = RepositoryCatalogWatchCallbackBox(roots: roots, handler: handler)
    var context = FSEventStreamContext(
      version: 0,
      info: Unmanaged.passUnretained(callbackBox).toOpaque(),
      retain: catalogWatchRetain,
      release: catalogWatchRelease,
      copyDescription: nil
    )
    let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
      | FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot)
    guard let stream = FSEventStreamCreate(
      kCFAllocatorDefault,
      catalogWatchCallback,
      &context,
      roots as CFArray,
      FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
      1.0,
      flags
    ) else {
      throw RepositoryFileWatcherError.streamCreationFailed
    }
    self.stream = stream
    FSEventStreamSetDispatchQueue(stream, queue)
    guard FSEventStreamStart(stream) else {
      FSEventStreamInvalidate(stream)
      FSEventStreamRelease(stream)
      self.stream = nil
      throw RepositoryFileWatcherError.streamStartFailed
    }
  }

  deinit {
    guard let stream else { return }
    FSEventStreamStop(stream)
    FSEventStreamInvalidate(stream)
    FSEventStreamRelease(stream)
  }
}

/// Keeps a low-frequency FSEvents stream over configured project roots.
/// Callbacks identify only affected roots so the catalog scanner can replace
/// those groups while retaining the cached results for every other root.
@MainActor
public final class RepositoryCatalogWatchLifecycle {
  private var session: RepositoryCatalogWatchSession?
  private var startTask: Task<Void, Never>?
  private var startID = UUID()

  public init() {}

  public func start(
    rootPaths: [String],
    onChange: @MainActor @Sendable @escaping (Set<String>) -> Void,
    onFailure: @MainActor @Sendable @escaping (String) -> Void
  ) {
    stop()
    guard !rootPaths.isEmpty else { return }
    let requestID = UUID()
    startID = requestID
    startTask = Task { [weak self] in
      do {
        let session = try await Task.detached(priority: .utility) {
          try RepositoryCatalogWatchSession(rootPaths: rootPaths) { roots in
            Task { @MainActor in onChange(roots) }
          }
        }.value
        guard !Task.isCancelled, self?.startID == requestID else { return }
        self?.session = session
      } catch {
        guard !Task.isCancelled, self?.startID == requestID else { return }
        onFailure(error.localizedDescription)
      }
      if self?.startID == requestID { self?.startTask = nil }
    }
  }

  public func stop() {
    startID = UUID()
    startTask?.cancel()
    startTask = nil
    session = nil
  }
}
