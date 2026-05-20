// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MicrosoftSpeechSDK",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "MicrosoftCognitiveServicesSpeech",
            targets: ["MicrosoftCognitiveServicesSpeech"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "MicrosoftCognitiveServicesSpeech",
            url: "https://csspeechstorage.blob.core.windows.net/drop/1.50.0/MicrosoftCognitiveServicesSpeech-MacOSXCFramework-1.50.0.zip",
            checksum: "3b748dd2222c7ae06567878467bbc39b17a8dea015284a9a3117b0ea12a55a0b"
        )
    ]
)
