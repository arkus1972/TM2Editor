// swift-tools-version:5.9
//
// Edytor ustawień Roland TM-2.
//
// Projekt celowo stoi na SwiftPM, nie na pliku .xcodeproj. Powód jest
// praktyczny: w sesji roboczej nie ma Xcode ani kompilatora Swift, a
// ręcznie pisany project.pbxproj to plik, którego nie da się zweryfikować
// przez czytanie — jedna zgubiona referencja i projekt się nie otwiera.
// Package.swift czyta się jak zwykły kod, Xcode otwiera go bezpośrednio
// (File -> Open -> Package.swift), a GitHub Actions buduje przez
// `swift build` bez żadnej generacji projektu.
//
// Gotowa aplikacja .app powstaje ze skryptu Scripts/zbuduj-app.sh, który
// pakuje binarkę razem z Info.plist w bundle i podpisuje ad-hoc.

import PackageDescription

let package = Package(
    name: "TM2Editor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TM2Editor", targets: ["TM2Editor"])
    ],
    targets: [
        .executableTarget(
            name: "TM2Editor",
            path: "Sources/TM2Editor"
        ),
        // Testy sięgają do celu wykonywalnego przez @testable import.
        // SwiftPM to obsługuje na macOS od narzędzi 5.5 — gdyby jednak
        // linker zaprotestował, lekarstwem jest wydzielenie warstwy modelu
        // (Model/ i Support/) do osobnego celu bibliotecznego i dodanie
        // modyfikatorów public. Na razie nie komplikujemy bez powodu.
        .testTarget(
            name: "TM2EditorTests",
            dependencies: ["TM2Editor"],
            path: "Tests/TM2EditorTests"
        )
    ]
)
