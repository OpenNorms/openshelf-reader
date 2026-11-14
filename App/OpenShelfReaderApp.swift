import SwiftUI
import BackgroundTasks

/// OpenShelf Reader — a reader for OpenShelf knowledge bases.
///
/// The application is essentially the render: point it at KB git
/// repositories, and it either composes them into one knowledge base
/// or renders each on its own as a notebook. KBs are cached locally
/// and synced with Git pulls, periodically (background refresh) or on
/// demand (pull-to-refresh / Pull buttons).
@main
struct OpenShelfReaderApp: App {
    @StateObject private var store = KBStore(engine: LibGit2SyncEngine())

    init() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskID, using: nil) { task in
                guard let refreshTask = task as? BGAppRefreshTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                Self.scheduleRefresh()
                let work = Task { @MainActor in
                    // The store is created with the scene; background
                    // refresh performs a best-effort pull of all KBs via
                    // a short-lived store over the same cache.
                    let bgStore = KBStore(engine: LibGit2SyncEngine())
                    await bgStore.pullAll()
                }
                refreshTask.expirationHandler = { work.cancel() }
                Task {
                    _ = await work.value
                    refreshTask.setTaskCompleted(success: !work.isCancelled)
                }
            }
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(store)
                .environment(\.typeface, store.library.typeface)
                .preferredColorScheme(store.preferredScheme)
                .onAppear { Self.scheduleRefresh() }
        }
    }

    static let refreshTaskID = "org.opennorms.openshelf-reader.refresh"

    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
