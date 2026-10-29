// swift-tools-version:5.10
// Bookmark Manager — tabs, directories and sub-directories of bookmarks, with secrets, color codes and search.
// `swift build` builds the core and the app; BUILD_APP.sh wraps the app into "Bookmark Manager.app".
import PackageDescription

let package = Package(
    name: "BookmarkManager",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BookmarkManagerCore", targets: ["BookmarkManagerCore"]),
        .executable(name: "BookmarkManager", targets: ["BookmarkManager"]),
    ],
    targets: [
        // The library of tabs, folders and bookmarks, the file it lives in, the secrets, search, moving things,
        // export / validate / import. No UI — testable on its own.
        .target(name: "BookmarkManagerCore", path: "Sources/BookmarkManagerCore"),
        // The SwiftUI app (the window, the editors, the secret window, Settings). Thin: it drives the core.
        .executableTarget(name: "BookmarkManager", dependencies: ["BookmarkManagerCore"], path: "Sources/BookmarkManager"),
        .testTarget(name: "BookmarkManagerCoreTests", dependencies: ["BookmarkManagerCore"], path: "Tests/BookmarkManagerCoreTests"),
        // the app's own logic (AppModel) on a scratch BOOKMARKMANAGER_HOME
        .testTarget(name: "BookmarkManagerTests", dependencies: ["BookmarkManager", "BookmarkManagerCore"], path: "Tests/BookmarkManagerTests"),
    ],
    swiftLanguageVersions: [.v5]
)
