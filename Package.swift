// swift-tools-version:6.0
import PackageDescription

// DeskPet is split into a library target (DeskPetKit) and a thin executable
// (DeskPet). The split exists so the test target can link against the library:
// SPM cannot reliably link a test target against an executable target that
// declares `@main`.
//
// Swift 5 language mode is used deliberately. AppKit view/window subclasses,
// CALayer callbacks, and the timer plumbing in ReminderScheduler are all
// main-thread-confined by construction rather than by `Sendable` annotation,
// and Swift 6 strict concurrency checking rejects that pattern wholesale.
let package = Package(
    name: "DeskPet",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "DeskPetKit",
            path: "Sources/DeskPetKit",
            resources: [.copy("Resources/PetAssets")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("ServiceManagement"),
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "DeskPet",
            dependencies: ["DeskPetKit"],
            path: "Sources/DeskPet",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DeskPetTests",
            dependencies: ["DeskPetKit"],
            path: "Tests/DeskPetTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
