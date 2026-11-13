// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NoteSDK",
    platforms: [.iOS(.v16)],
    products: [.library(name: "NoteSDK", targets: ["NoteSDK"])],
    targets: [
        .binaryTarget(name: "NoteSDK", url: "https://github.com/beclab/note-ios-sdk/releases/download/0.2.3/olares-note-ios-sdk-0.2.3-xcframework.zip", checksum: "c6b0bd64102591fb8d3a91fb52dfaf34f55513cb976be967bdcf21ed11db933f")
    ]
)
