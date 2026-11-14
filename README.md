# OpenShelf Reader

A reader for [OpenShelf](https://github.com/OpenNorms/openshelf)
knowledge bases, for iOS. The application is essentially the render:
point it at KB git repositories and it either **composes** them into
one knowledge base or renders each on its own **as a notebook**.
Knowledge bases are cached locally on the phone and synced with a
**Git pull** — periodically in the background, or on demand.

Read-only by design. The corpus lives in git and is written at desks
by humans and agents; the reader never writes to a repository.

## MVP scope

- Add KBs by git URL (public, or private with a personal access token
  stored in the Keychain).
- Local cache per KB (a real git checkout); sync = fetch + reset to
  the branch tip, which is all a pull needs when the copy is never
  edited. Provenance is shown everywhere as `kb @ <short sha>`.
- Notebook rendering: pages grouped by type, in-KB search, frontmatter
  rendered generically (nothing dropped) with rich treatment for the
  known fields (`verdict:` the precedent).
- Compositions: create one from any set of cached KBs; unified browse
  and search, cross-KB `kb://` links resolved, broken links flagged.
- Themes: five bundled token themes (Ink, Paper, Chart, Mono, Sepia),
  global default + per-KB override. Themes are token sets — the same
  core a `theme.yaml` package can carry.
- Background refresh via BGAppRefreshTask (6-hour cadence request).

Non-goals for the MVP: editing KBs, lint, ingest, push notifications,
accounts beyond per-repo tokens.

## Layout

```
Package.swift            ReaderCore — the engine (see below)
Sources/ReaderCore/      kb.yaml + frontmatter parsing (tolerant subset
                         YAML), markdown -> HTML, composition, themes,
                         the GitSyncEngine contract, the library model
Tests/ReaderCoreTests/   engine tests + two fixture KBs (spec 1.7 and
                         the 1.4 awesome-profile shape)
App/                     the iOS app: SwiftUI library / notebook /
                         composed views, WKWebView page rendering,
                         KBStore, and the libgit2 sync adapter
project.yml              XcodeGen spec for the app target
```

`ReaderCore` depends only on Foundation. The app talks to git only
through ReaderCore's `GitSyncEngine` protocol; the libgit2 adapter
(`App/LibGit2SyncEngine.swift`, against the libgit2 C API via the
SwiftPM build at github.com/ibrahimcetin/libgit2) is the single
implementation.

## Verification status

- **ReaderCore is compiled and tested**: 14 unit tests pass
  (`swift test`, Swift 6.0.3). It has also been run against the real
  fleet — target-discussion (20 pages, spec 1.7), the embedded and
  automotive awesome KBs (312 / 287 pages, spec 1.4), the biz KB
  (50 pages), and the awesome-kb registry (spec 0.1) — plus a live
  two-KB composition whose rendered pages contain no broken links.
- **The app compiles** for iOS (Xcode 27.2, `generic/platform=iOS`).
  It has not yet been run on a device or simulator, so clone / pull /
  token auth are unverified at runtime.

## Building

Engine only (any platform with Swift):

```
swift test
```

The iOS app (on a Mac):

```
brew install xcodegen
cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
#   ...set DEVELOPMENT_TEAM in it (needed for device builds only)
xcodegen generate
open OpenShelfReader.xcodeproj
```

Your team ID lives only in `Config/Signing.local.xcconfig`, which is
gitignored.

Or use the Makefile:

```
make test      # engine tests
make sim       # build + run on an iOS simulator
make deploy    # build + install + launch on your iPhone (USB or Wi-Fi)
```

`make deploy` uses the first paired iPhone (USB or Wi-Fi); pin a specific
device or simulator in `local.mk` (copy `local.mk.example`, gitignored).

## Design notes

- **Tolerant parsing is a spec-level rule for readers**: known keys
  are read, unknown keys (including `x-*` blocks) ignored, unseen spec
  versions never an error. The fleet already spans spec 0.1 – 1.7.
- **Composition mirrors the web builder's contract**: routes are
  `kb/<kb-id>/<slug>`, the bundle shape matches the composed site's
  `bundle.json`, and registry pins (`.openshelf/kbs.lock`) are the
  same "which commit am I reading" provenance the app shows per page.
- **Themes**: site themes are `theme.yaml` packages (templates +
  assets) for composed web sites. The reader shares their token core
  only — whether that core becomes a spec surface is an open OpenShelf
  question, tracked in the design brief.
