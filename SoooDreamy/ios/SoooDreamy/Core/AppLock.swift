import SwiftUI
import Observation
import LocalAuthentication

/// Optional app lock: Face ID / Touch ID / passcode gate over the whole app.
/// Locks when the app goes to background (if enabled in settings).
@MainActor
@Observable
final class AppLock {
    private static let enabledKey = "sooodreamy.appLockEnabled"

    var locked: Bool
    @ObservationIgnored private var authenticating = false

    init() {
        locked = Self.isEnabled
    }

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Device supports some form of local authentication (biometrics or passcode).
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func lockIfNeeded() {
        if Self.isEnabled { locked = true }
    }

    func unlock() async {
        guard locked, !authenticating else { return }
        authenticating = true
        defer { authenticating = false }
        let context = LAContext()
        context.localizedCancelTitle = L10n.t("common.cancel")
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                      localizedReason: L10n.t("lock.reason"))
            if ok {
                withAnimation(.easeOut(duration: 0.3)) {
                    locked = false
                }
            }
        } catch {
            // User cancelled or auth unavailable — stay locked, button retries.
        }
    }
}

/// Full-screen lock overlay.
struct LockScreenView: View {
    @Environment(AppLock.self) private var appLock

    var body: some View {
        ZStack {
            DreamyBackground()
            VStack(spacing: LayoutMetrics.s(20)) {
                Spacer()
                Text("💜")
                    .font(.scaled(74))
                    .shadow(color: Theme.pink.opacity(0.75), radius: 28)
                Text(L10n.t("lock.title"))
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text(L10n.t("lock.subtitle"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LayoutMetrics.s(40))
                Spacer()
                Button {
                    Task { await appLock.unlock() }
                } label: {
                    Label(L10n.t("lock.unlock"), systemImage: "faceid")
                }
                .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                .padding(.bottom, LayoutMetrics.s(40))
            }
        }
        .task {
            await appLock.unlock()
        }
    }
}
