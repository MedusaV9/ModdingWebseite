// swift-tools-version: 5.9
// Linux-runnable SwiftPM package covering the pure-logic (Foundation-only)
// subset of the SoooDreamy iOS app. The full app is built by XcodeGen from
// project.yml — this manifest exists ONLY so `swift test` can exercise the
// content packs, date helpers, seeded RNG and localization tables on Linux/CI.
// Do not add SwiftUI/UIKit files to `sources`.
import PackageDescription

let package = Package(
    name: "SoooDreamyLogic",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "SoooDreamyLogic", targets: ["SoooDreamyLogic"])
    ],
    targets: [
        .target(
            name: "SoooDreamyLogic",
            path: ".",
            sources: [
                "SoooDreamy/Content/ContentModels.swift",
                "SoooDreamy/Content/Data/DailyQuestionsData.swift",
                "SoooDreamy/Content/Data/QuizData.swift",
                "SoooDreamy/Content/Data/ThisOrThatData.swift",
                "SoooDreamy/Content/Data/WouldYouRatherData.swift",
                "SoooDreamy/Content/Data/TruthOrDareData.swift",
                "SoooDreamy/Content/Data/Questions36Data.swift",
                "SoooDreamy/Content/Data/DateIdeasData.swift",
                "SoooDreamy/Content/Data/WordleWordsData.swift",
                "SoooDreamy/Content/Data/EmojiRiddlesData.swift",
                "Shared/SharedBridge.swift",
                "SoooDreamy/Core/SeededRandom.swift",
                "SoooDreamy/Core/L10n.swift",
                "SoooDreamy/Core/CoreStrings.swift",
                "SoooDreamy/Features/Chat/ChatL10n.swift",
                "SoooDreamy/Features/Games/GamesL10n.swift",
                "SoooDreamy/Features/Memories/MemoriesL10n.swift"
            ]
        ),
        .testTarget(
            name: "SoooDreamyLogicTests",
            dependencies: ["SoooDreamyLogic"],
            path: "LogicTests"
        )
    ]
)
