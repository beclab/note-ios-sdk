// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NoteSDK",
    platforms: [.iOS(.v16)],
    products: [.library(name: "NoteSDK", targets: ["NoteSDK"])],
    targets: [
        .binaryTarget(name: "NoteSDK", url: "https://github.com/beclab/note-ios-sdk/releases/download/0.2.4/olares-note-ios-sdk-0.2.4-xcframework.zip", checksum: "ca1eefeadde78fe153540e1807badc27ec77cffbf85eee9d30a0e11cafbc859a")
    ]
)
