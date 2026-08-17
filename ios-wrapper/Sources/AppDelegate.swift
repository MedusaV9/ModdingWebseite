// MONKEY-MONEY-iPad-Wrapper (TECH-SPEC §6): klassischer UIKit-Einstieg ohne Scenes.
// Der Wrapper existiert für genau drei Dinge, die Safari nicht kann:
//   1. Display-Sleep aus (isIdleTimerDisabled) — die Show läuft stundenlang,
//   2. Landscape-Lock (Info.plist),
//   3. Audio-Autoplay ohne Touch (GameViewController + AVAudioSession .playback).
import AVFoundation
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Display-Sleep aus — DER Grund für den Wrapper.
        application.isIdleTimerDisabled = true

        // Show-Sound (Jingles/Musik) läuft auch bei Stummschalter/Fokus-Modi.
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)

        // Navigation-Controller mit versteckter Leiste: Connect-Screen ↔ WebView
        // per Push/Pop, ohne sichtbares Browser-Chrome.
        let navigation = UINavigationController(rootViewController: ConnectViewController())
        navigation.isNavigationBarHidden = true

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
