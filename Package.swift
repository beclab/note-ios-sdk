// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NoteSDK",
    platforms: [.iOS(.v16)],
    products: [.library(name: "NoteSDK", targets: ["NoteSDK"])],
    targets: [
        .binaryTarget(name: "NoteSDK", url: "https://github.com/beclab/note-ios-sdk/releases/download/0.2.2/olares-note-ios-sdk-0.2.2-xcframework.zip", checksum: "0e6ecd24e0fabfad6c2a95f63d1b0022a3c16dde95a7acbee601e494bd276807")
    ]
)
