import UIKit
import CarPlay

/// Application delegate — routes the CarPlay scene role cleanly on iOS 17–26.
/// Phone/iPad windows are handled by SwiftUI's WindowGroup via `@UIApplicationDelegateAdaptor`
/// in `CarSpeakApp.swift`, while UIKit reads `Info.plist`'s `CPTemplateApplicationSceneSessionRoleApplication`
/// entry and instantiates `CarPlaySceneDelegate` directly (identical to `Hands-Free Lingo`).
public final class AppDelegate: NSObject, UIApplicationDelegate { }
