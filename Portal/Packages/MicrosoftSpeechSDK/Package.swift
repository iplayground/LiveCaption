// swift-tools-version: 6.3

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
            url: "https://csspeechstorage.blob.core.windows.net/drop/1.49.1/MicrosoftCognitiveServicesSpeech-MacOSXCFramework-1.49.1.zip",
            checksum: "03dc863a726e3bd578d31aa7bef996d9772403b6bfd75bde4edc13d1206991e1"
        )
    ]
)
