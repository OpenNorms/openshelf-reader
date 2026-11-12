import Foundation
import ReaderCore
import SwiftGit2

/// The app's GitSyncEngine, backed by libgit2 (via SwiftGit2).
///
/// NOTE — written without a compiler in the loop: this is the one file
/// in the app expected to need adjustment at the first Xcode build
/// (SwiftGit2 call signatures). The seam is deliberate: everything else
/// in the app talks to the GitSyncEngine protocol from ReaderCore, so
/// any fix stays inside this file. If SwiftGit2 fails to build under a
/// current Xcode, replace this adapter (e.g. with a libgit2 XCFramework
/// binding) without touching the rest of the app.
///
/// Semantics per the reader's model: the cache is read-only, so a pull
/// is fetch + reset --hard to the branch tip. No merges, no conflicts.
final class LibGit2SyncEngine: GitSyncEngine {

    func cloneRepository(url: URL, branch: String?, to directory: URL,
                         token: String?) throws -> String {
        var options = CloneOptions()
        if let branch { options.checkoutBranch = branch }
        if let token { options.fetchOptions = fetchOptions(token: token) }
        let result = Repository.clone(from: url, to: directory,
                                      options: options)
        let repo = try result.get()
        return try headSHA(repo)
    }

    func pullRepository(at directory: URL, token: String?) throws -> String {
        let repo = try Repository.at(directory).get()
        let remote = try repo.remote(named: "origin").get()
        try remote.fetch(fetchOptions: token.map(fetchOptions(token:)) ??
                         FetchOptions()).get()
        // Reset --hard to the fetched branch tip.
        let head = try repo.HEAD().get()
        let branchName = head.shortName ?? "main"
        let tip = try repo.lookupBranch(named: "origin/\(branchName)",
                                        type: .remote).get()
        let commit = try repo.lookupCommit(tip.oid).get()
        try repo.reset(to: commit, resetType: .hard).get()
        return commit.oid.description
    }

    // MARK: - Helpers

    private func headSHA(_ repo: Repository) throws -> String {
        let head = try repo.HEAD().get()
        return head.oid.description
    }

    private func fetchOptions(token: String) -> FetchOptions {
        var options = FetchOptions()
        options.credentials = .https(userName: "x-access-token", password: token)
        return options
    }
}
