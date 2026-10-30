import ProjectDescription

let teamID = "N2C267LBVY"
let bundleIDPrefix = "app.xiren"

// Each configuration gets its own bundle IDs so Debug, Development and Production builds install side by side.
let configurations: [Configuration] = [
  .debug(name: "Debug", settings: [
    "BUNDLE_ID_PREFIX": "\(bundleIDPrefix).debug",
  ]),
  .release(name: "Development", settings: [
    "BUNDLE_ID_PREFIX": "\(bundleIDPrefix).dev",
  ]),
  .release(name: "Production", settings: [
    "BUNDLE_ID_PREFIX": .string(bundleIDPrefix),
  ]),
]

let baseSettings: SettingsDictionary = [
  "DEVELOPMENT_TEAM": .string(teamID),
  "CODE_SIGN_STYLE": "Automatic",
  "SWIFT_VERSION": "5.0",
]

let version: [String: Plist.Value] = [
  "CFBundleShortVersionString": "0.1.0",
  "CFBundleVersion": .string(Environment.buildNumber.getString(default: "1")),
]

let project = Project(
  name: "Xiren",
  settings: .settings(base: baseSettings, configurations: configurations, defaultSettings: .recommended),
  targets: [
    .target(
      name: "XireniOS",
      destinations: [.iPhone],
      product: .app,
      productName: "Xiren",
      bundleId: "$(BUNDLE_ID_PREFIX).ios",
      deploymentTargets: .iOS("18.0"),
      infoPlist: .extendingDefault(with: version.merging([
        "CFBundleDisplayName": "Xiren",
        "UILaunchScreen": [:],
        "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
        "ITSAppUsesNonExemptEncryption": false,
      ]) { $1 }),
      sources: ["iOS/App/**"]
    ),
    .target(
      name: "XireniOSTests",
      destinations: [.iPhone],
      product: .unitTests,
      bundleId: "\(bundleIDPrefix).ios.tests",
      deploymentTargets: .iOS("18.0"),
      sources: ["iOS/Tests/**"],
      dependencies: [.target(name: "XireniOS")]
    ),
  ],
  schemes: [
    .scheme(
      name: "XireniOS",
      buildAction: .buildAction(targets: ["XireniOS"]),
      testAction: .targets(["XireniOSTests"], configuration: "Debug"),
      runAction: .runAction(configuration: "Debug", executable: "XireniOS"),
      archiveAction: .archiveAction(configuration: "Production"),
      profileAction: .profileAction(configuration: "Production", executable: "XireniOS"),
      analyzeAction: .analyzeAction(configuration: "Debug")
    ),
  ]
)
