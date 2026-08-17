import SwiftUI
import Observation
import LocalAuthentication
import UIKit

/// Optional app lock: Face ID / Touch ID / passcode gate over the whole app.
/// Locks when the app goes to background (if enabled in settings).
@MainActor
@Observable
final class AppLock {
    private static let enabledKey = "sooodreamy.appLockEnabled"

    var locked: Bool
    var failureKey: String?
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
        failureKey = nil
        defer { authenticating = false }
        let context = LAContext()
        context.localizedCancelTitle = L10n.t("common.cancel")
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            failureKey = "lock.error.unavailable"
            return
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                      localizedReason: L10n.t("lock.reason"))
            if ok {
                // Named curve instead of a raw ease (commandment 11): the
                // gate lifting is a calm state change.
                withAnimation(Theme.Motion.settle) {
                    locked = false
                }
            }
        } catch {
            let code = (error as? LAError)?.code
            if code != .userCancel && code != .systemCancel && code != .appCancel {
                failureKey = code == .authenticationFailed
                    ? "lock.error.failed"
                    : "lock.error.unavailable"
            }
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
                if let failureKey = appLock.failureKey {
                    VStack(spacing: LayoutMetrics.s(8)) {
                        Text(L10n.t(failureKey))
                            .font(.system(.footnote, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.gold)
                            .multilineTextAlignment(.center)
                        if failureKey == "lock.error.unavailable" {
                            Button(L10n.t("lock.openSettings")) {
                                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                            }
                            .font(.system(.footnote, design: .rounded).weight(.bold))
                            .foregroundStyle(Theme.pink)
                        }
                    }
                    .padding(.horizontal, LayoutMetrics.s(40))
                }
                Spacer()
                Button {
                    Task { await appLock.unlock() }
                } label: {
                    Label(L10n.t("lock.unlock"), systemImage: "faceid")
                }
                .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                .padding(.bottom, LayoutMetrics.s(40))
            }
            .contentColumn(.reading)
        }
        .task {
            await appLock.unlock()
        }
    }
}
