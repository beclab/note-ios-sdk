// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NoteSDK",
    platforms: [.iOS(.v16)],
    products: [.library(name: "NoteSDK", targets: ["NoteSDK"])],
    targets: [
        .binaryTarget(name: "NoteSDK", url: "https://github.com/beclab/note-ios-sdk/releases/download/0.2.5/olares-note-ios-sdk-0.2.5-xcframework.zip", checksum: "dfc894f2f9166012933ff153215ebe5f07a96f766386da81d02b7d17e7a8abb1")
    ]
)
