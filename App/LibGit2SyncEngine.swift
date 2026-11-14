import Foundation
import ReaderCore
import libgit2

/// The app's GitSyncEngine, backed directly by the libgit2 C API
/// (the SwiftPM build of libgit2 from github.com/ibrahimcetin/libgit2).
///
/// The seam is deliberate: everything else in the app talks to the
/// GitSyncEngine protocol from ReaderCore, so git concerns stay here.
///
/// Semantics per the reader's model: the cache is read-only, so a pull
/// is fetch + reset --hard to the branch tip. No merges, no conflicts.
final class LibGit2SyncEngine: GitSyncEngine {

    init() {
        git_libgit2_init()
    }

    deinit {
        git_libgit2_shutdown()
    }

    func cloneRepository(url: URL, branch: String?, to directory: URL,
                         token: String?,
                         progress: (@Sendable (Double) -> Void)?) throws -> String {
        var options = git_clone_options()
        try check(git_clone_options_init(&options,
                                         UInt32(GIT_CLONE_OPTIONS_VERSION)))
        options.checkout_opts.checkout_strategy = GIT_CHECKOUT_SAFE.rawValue

        return try withCredentials(token, progress: progress) { callbacks in
            options.fetch_opts.callbacks = callbacks
            var repo: OpaquePointer?
            let status: Int32
            if let branch {
                status = branch.withCString { cBranch in
                    options.checkout_branch = cBranch
                    return git_clone(&repo, url.absoluteString,
                                     directory.path, &options)
                }
            } else {
                status = git_clone(&repo, url.absoluteString,
                                   directory.path, &options)
            }
            try check(status)
            defer { git_repository_free(repo) }
            return try headSHA(repo!)
        }
    }

    func pullRepository(at directory: URL, token: String?,
                        progress: (@Sendable (Double) -> Void)?) throws -> String {
        var repo: OpaquePointer?
        try check(git_repository_open(&repo, directory.path))
        defer { git_repository_free(repo) }

        // Fetch origin.
        var remote: OpaquePointer?
        try check(git_remote_lookup(&remote, repo, "origin"))
        defer { git_remote_free(remote) }

        var fetchOptions = git_fetch_options()
        try check(git_fetch_options_init(&fetchOptions,
                                         UInt32(GIT_FETCH_OPTIONS_VERSION)))
        try withCredentials(token, progress: progress) { callbacks in
            fetchOptions.callbacks = callbacks
            try check(git_remote_fetch(remote, nil, &fetchOptions, nil))
        }

        // Resolve the remote-tracking tip of the checked-out branch.
        var head: OpaquePointer?
        try check(git_repository_head(&head, repo))
        defer { git_reference_free(head) }
        let branchName = git_reference_shorthand(head).map { String(cString: $0) } ?? "main"

        var tipOID = git_oid()
        try check(git_reference_name_to_id(&tipOID, repo,
                                           "refs/remotes/origin/\(branchName)"))

        // reset --hard to it.
        var commit: OpaquePointer?
        try check(git_object_lookup(&commit, repo, &tipOID, GIT_OBJECT_COMMIT))
        defer { git_object_free(commit) }
        try check(git_reset(repo, commit, GIT_RESET_HARD, nil))

        return oidString(&tipOID)
    }

    // MARK: - Helpers

    private func headSHA(_ repo: OpaquePointer) throws -> String {
        var oid = git_oid()
        try check(git_reference_name_to_id(&oid, repo, "HEAD"))
        return oidString(&oid)
    }

    private func oidString(_ oid: inout git_oid) -> String {
        String(cString: git_oid_tostr_s(&oid))
    }

    /// Runs `body` with remote callbacks that answer HTTPS auth with the
    /// personal access token (if any) and report transfer progress. The
    /// token never touches disk.
    private func withCredentials<T>(_ token: String?,
                                    progress: (@Sendable (Double) -> Void)?,
                                    _ body: (git_remote_callbacks) throws -> T) throws -> T {
        var callbacks = git_remote_callbacks()
        try check(git_remote_init_callbacks(&callbacks,
                                            UInt32(GIT_REMOTE_CALLBACKS_VERSION)))
        guard token != nil || progress != nil else { return try body(callbacks) }

        let state = CallbackState(token: token, progress: progress)
        return try withExtendedLifetime(state) {
            if token != nil { callbacks.credentials = credentialCallback }
            if progress != nil { callbacks.transfer_progress = transferProgressCallback }
            callbacks.payload = Unmanaged.passUnretained(state).toOpaque()
            return try body(callbacks)
        }
    }
}

// MARK: - libgit2 glue

struct LibGit2Error: LocalizedError {
    let code: Int32
    let message: String
    var errorDescription: String? { "git error \(code): \(message)" }
}

private func check(_ status: Int32) throws {
    guard status < 0 else { return }
    let message = git_error_last().flatMap { $0.pointee.message }
        .map { String(cString: $0) } ?? "unknown error"
    throw LibGit2Error(code: status, message: message)
}

private final class CallbackState {
    let token: String?
    let progress: (@Sendable (Double) -> Void)?
    var attempts = 0
    init(token: String?, progress: (@Sendable (Double) -> Void)?) {
        self.token = token
        self.progress = progress
    }
}

/// Object-transfer progress (received / total objects), 0...1.
private let transferProgressCallback: git_indexer_progress_cb = { stats, payload in
    guard let stats, let payload else { return 0 }
    let state = Unmanaged<CallbackState>.fromOpaque(payload).takeUnretainedValue()
    let total = Double(stats.pointee.total_objects)
    if total > 0 { state.progress?(Double(stats.pointee.received_objects) / total) }
    return 0
}

/// HTTPS userpass credentials from the token. Gives up after one
/// rejected attempt so a bad token fails fast instead of looping.
private let credentialCallback: git_credential_acquire_cb = { out, _, _, allowed, payload in
    guard let payload,
          allowed & GIT_CREDENTIAL_USERPASS_PLAINTEXT.rawValue != 0 else {
        return GIT_PASSTHROUGH.rawValue
    }
    let state = Unmanaged<CallbackState>.fromOpaque(payload).takeUnretainedValue()
    guard let token = state.token else { return GIT_PASSTHROUGH.rawValue }
    state.attempts += 1
    guard state.attempts <= 1 else {
        git_error_set_str(Int32(GIT_ERROR_HTTP.rawValue),
                          "authentication failed: the access token was rejected")
        return GIT_EAUTH.rawValue
    }
    return git_credential_userpass_plaintext_new(out, "x-access-token", token)
}
