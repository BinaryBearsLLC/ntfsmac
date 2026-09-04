// swift-tools-version:6.0
import Foundation
import PackageDescription

// GUI + privileged-helper package (PLAN.md Phase 3). Targets are added to incrementally as
// later §6 units land — this file only declares what `3-xpc-helper` needs.

// `#filePath` gives this manifest's own absolute path regardless of the CWD `swift build` is
// invoked from (build/package-app.sh, CI, or Xcode) — resolving helper/Info.plist and
// helper/launchd.plist relative to that is the only path-independent way to feed them to the
// linker below.
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let helperVariant = ProcessInfo.processInfo.environment["NTFSMAC_HELPER_VARIANT"] ?? "modern"
let legacyHelperBuild: Bool
switch helperVariant {
case "modern":
    legacyHelperBuild = false
case "legacy":
    legacyHelperBuild = true
default:
    fatalError("NTFSMAC_HELPER_VARIANT must be 'modern' or 'legacy'")
}
let helperSwiftSettings: [SwiftSetting] = legacyHelperBuild
    ? [.define("NTFSMAC_LEGACY_HELPER")]
    : []
let helperInfoPlistName = legacyHelperBuild ? "Info.plist" : "Info-Modern.plist"
let helperLaunchdPlistName = legacyHelperBuild ? "launchd.plist" : "launchd-modern.plist"
let helperInfoPlistPath = packageDir.appendingPathComponent("helper/\(helperInfoPlistName)").path
let helperLaunchdPlistPath = packageDir.appendingPathComponent("helper/\(helperLaunchdPlistName)").path

let package = Package(
    name: "ntfsmac-gui",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "HelperShared", targets: ["HelperShared"]),
        .executable(name: "ntfsmac-helper", targets: ["ntfsmac-helper"]),
        .library(name: "NtfsmacGUI", targets: ["NtfsmacGUI"]),
        .executable(name: "ntfsmac-gui", targets: ["ntfsmac-gui"]),
    ],
    targets: [
        .target(
            name: "HelperShared",
            path: "helper",
            exclude: ["main.swift", "Info.plist", "Info-Modern.plist", "launchd.plist", "launchd-modern.plist", "Tests"],
            sources: ["HelperProtocol.swift", "GeneratedCLIManifest.swift"],
            swiftSettings: helperSwiftSettings
        ),
        .executableTarget(
            name: "ntfsmac-helper",
            dependencies: ["HelperShared"],
            path: "helper",
            exclude: [
                "HelperProtocol.swift", "GeneratedCLIManifest.swift", "Info.plist", "Info-Modern.plist",
                "launchd.plist", "launchd-modern.plist", "Tests",
            ],
            sources: ["main.swift"],
            // Legacy SMJobBless reads identity and launchd metadata from these Mach-O sections.
            // The standard build keeps equally specific modern metadata embedded while
            // SMAppService owns registration through the app's Library/LaunchDaemons plist.
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", helperInfoPlistPath,
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__launchd_plist",
                    "-Xlinker", helperLaunchdPlistPath,
                ])
            ]
        ),
        .testTarget(
            name: "HelperTests",
            dependencies: ["HelperShared"],
            path: "helper/Tests",
            swiftSettings: helperSwiftSettings
        ),
        .target(
            name: "NtfsmacGUI",
            dependencies: ["HelperShared"],
            path: "gui",
            exclude: ["App", "Resources", "Info.plist", "Tests"],
            sources: [
                "Helper/HelperClient.swift", "Status/StatusIcon.swift", "State/AppState.swift",
                "State/SingleInstanceGuard.swift", "State/PopoverNavigation.swift",
                "Drives/DriveScanner.swift", "Views/DriveRow.swift", "Actions/MountSnapshot.swift",
                "Actions/MountController.swift", "Actions/MountNotifications.swift",
                "Views/DirtyBanner.swift",
                "Actions/FinderOpener.swift", "Views/SecurityIndicators.swift",
                "Actions/MenuBarPopoverController.swift",
                "Actions/SecurityStatusReader.swift",
                "Actions/PreferencesOpener.swift", "Actions/CLIAutoStager.swift",
                "Actions/DiagnoseRunner.swift", "Actions/DeveloperDiagnoseExport.swift", "Views/DiagnosePanel.swift",
                "Actions/VerifiedCopyController.swift", "Views/VerifiedCopyStatusView.swift",
                "FirstRun/HelperInstaller.swift", "FirstRun/FullDiskAccessSetup.swift", "Views/FirstRunView.swift",
                "FirstRun/HelperUninstaller.swift", "FirstRun/CLIInstallChecker.swift", "Views/CLIMissingView.swift",
                "Preferences/ProductVersion.swift", "Preferences/LegacyPreferenceMigration.swift",
                "Preferences/Settings.swift", "Preferences/PreferencesView.swift", "Updates/UpdateChecker.swift",
                "Style/Colors.swift", "Style/GlassTheme.swift", "Style/Icons.swift", "Style/KeyboardFocus.swift", "Style/PillButtons.swift",
                "Style/TooltipCopy.swift",
                "Views/PopoverContentView.swift",
            ],
            swiftSettings: helperSwiftSettings
        ),
        .executableTarget(
            name: "ntfsmac-gui",
            dependencies: ["NtfsmacGUI", "HelperShared"],
            path: "gui",
            exclude: [
                "Helper", "Status", "State", "Drives", "Views", "Actions", "FirstRun", "Preferences", "Updates",
                "Style", "Resources", "Info.plist", "Tests",
            ],
            sources: ["App/NtfsmacApp.swift", "App/DemoScaffold.swift"]
        ),
        .testTarget(
            name: "NtfsmacGUITests",
            dependencies: ["NtfsmacGUI", "HelperShared"],
            path: "gui/Tests",
            swiftSettings: helperSwiftSettings
        ),
    ]
)
