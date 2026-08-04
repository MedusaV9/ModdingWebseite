import SwiftUI

// MARK: - Avatar

struct EmojiAvatarView: View {
    let emoji: String?
    let colorHex: String?
    var size: CGFloat = 52
    var online: Bool? = nil

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(
                    LinearGradient(colors: [Color(hex: colorHex ?? "A855F7").opacity(0.95),
                                            Color(hex: colorHex ?? "A855F7").opacity(0.55)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5))
                .frame(width: size, height: size)
                .overlay(
                    Text(emoji ?? "💜")
                        .font(.system(size: size * 0.52))
                )
            if let online {
                Circle()
                    .fill(online ? Theme.mint : Color.gray.opacity(0.7))
                    .frame(width: size * 0.26, height: size * 0.26)
                    .overlay(Circle().strokeBorder(Theme.bgTop, lineWidth: 2))
            }
        }
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil
    var onTrailingTap: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if let trailing {
                Button(action: { onTrailingTap?() }) {
                    Text(trailing)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.pink)
                }
            }
        }
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let emoji: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: LayoutMetrics.s(10)) {
            Text(emoji)
                .font(.scaled(54))
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            Text(subtitle)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LayoutMetrics.s(36))
        .padding(.horizontal, LayoutMetrics.s(24))
    }
}

// MARK: - Loading

struct LoadingView: View {
    var text: String = L10n.t("common.loading")

    var body: some View {
        VStack(spacing: LayoutMetrics.s(14)) {
            ProgressView()
                .tint(Theme.pink)
                .scaleEffect(1.3)
            Text(text)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Toast

struct Toast: Equatable {
    enum Style { case info, success, error, love }
    let text: String
    var style: Style = .info

    var tint: Color {
        switch style {
        case .info: return Theme.blue
        case .success: return Theme.mint
        case .error: return Color(hex: "F87171")
        case .love: return Theme.pink
        }
    }

    var icon: String {
        switch style {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .love: return "heart.fill"
        }
    }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: LayoutMetrics.s(10)) {
            Image(systemName: toast.icon)
                .foregroundStyle(toast.tint)
            Text(toast.text)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
        }
        .padding(.vertical, LayoutMetrics.s(12))
        .padding(.horizontal, LayoutMetrics.s(18))
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(toast.tint.opacity(0.5), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .padding(.horizontal, LayoutMetrics.s(24))
    }
}

// MARK: - Floating hearts (celebrations, incoming touches)

struct FloatingHeartsView: View {
    var emojis: [String] = ["💜", "💖", "💗", "✨", "💞"]
    var count: Int = 18
    var startedAt = Date()

    private struct Particle {
        let x: CGFloat
        let delay: Double
        let speed: Double
        let size: CGFloat
        let sway: CGFloat
        let emojiIndex: Int
    }

    private var particles: [Particle] {
        var seed: UInt64 = 0xC0FFEE
        func rnd() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
        }
        return (0..<count).map { i in
            Particle(x: 0.05 + rnd() * 0.9,
                     delay: Double(rnd()) * 1.4,
                     speed: 0.55 + Double(rnd()) * 0.8,
                     size: LayoutMetrics.s(18 + rnd() * 22),
                     sway: LayoutMetrics.s(14 + rnd() * 26),
                     emojiIndex: i % emojis.count)
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(startedAt)
                for p in particles {
                    let life = (t - p.delay) * p.speed
                    guard life > 0 else { continue }
                    let progress = life.truncatingRemainder(dividingBy: 1.0)
                    let y = size.height * (1.05 - CGFloat(progress) * 1.15)
                    let x = p.x * size.width + sin(life * 4) * p.sway
                    let alpha = progress < 0.15 ? progress / 0.15 : (1 - progress)
                    let resolved = context.resolve(Text(emojis[p.emojiIndex]).font(.system(size: p.size)))
                    context.opacity = alpha
                    context.draw(resolved, at: CGPoint(x: x, y: y))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Connection banner

/// Compact socket-status pill (v1.5.3 polish): a softly pulsing dot while
/// connecting, a clear wifi-slash badge while offline (the socket retries
/// on its own) and a short mint "Verbunden" flash right after a reconnect.
struct ConnectionBanner: View {
    let state: SocketState

    /// True for a moment right after a reconnect — flashes the mint
    /// confirmation before the banner fades back to nothing.
    @State private var showReconnected = false
    @State private var reconnectFlashTask: Task<Void, Never>?

    var body: some View {
        Group {
            switch state {
            case .connected:
                if showReconnected {
                    label(L10n.t("conn.connected"), color: Theme.mint, icon: "checkmark")
                }
            case .connecting:
                label(L10n.t("conn.connecting"), color: Theme.gold, pulsing: true)
            case .disconnected:
                label(L10n.t("conn.offline"), color: Color(hex: "F87171"), icon: "wifi.slash")
            }
        }
        .animation(.spring(response: 0.35), value: state)
        .animation(.spring(response: 0.35), value: showReconnected)
        .onChange(of: state) { oldValue, newValue in
            reconnectFlashTask?.cancel()
            guard newValue == .connected, oldValue != .connected else {
                showReconnected = false
                return
            }
            showReconnected = true
            reconnectFlashTask = Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard !Task.isCancelled else { return }
                showReconnected = false
            }
        }
    }

    private func label(_ text: String, color: Color,
                       icon: String? = nil, pulsing: Bool = false) -> some View {
        HStack(spacing: 7) {
            if let icon {
                Image(systemName: icon)
                    .font(.scaled(10, weight: .bold))
                    .foregroundStyle(color)
            } else {
                ConnectionStatusDot(color: color, pulsing: pulsing)
            }
            Text(text)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, LayoutMetrics.s(13))
        .background(
            Capsule()
                .fill(Color.black.opacity(0.35))
                .overlay(Capsule().strokeBorder(color.opacity(0.40), lineWidth: 1))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }
}

/// Status dot with an optional expanding-ring pulse (while connecting).
private struct ConnectionStatusDot: View {
    let color: Color
    var pulsing = false

    @State private var animating = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.7), lineWidth: 1.5)
                    .scaleEffect(animating ? 2.2 : 1)
                    .opacity(animating ? 0 : 0.8)
            )
            .onAppear {
                guard pulsing else { return }
                withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) {
                    animating = true
                }
            }
    }
}

// MARK: - Emoji picker row

struct EmojiPickerGrid: View {
    let emojis: [String]
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
            ForEach(emojis, id: \.self) { e in
                Button {
                    selection = e
                    Haptics.shared.tap()
                } label: {
                    Text(e)
                        .font(.scaled(26))
                        .frame(width: LayoutMetrics.s(46), height: LayoutMetrics.s(46))
                        .background(
                            Circle().fill(selection == e ? Theme.pink.opacity(0.35) : Color.white.opacity(0.06))
                        )
                        .overlay(
                            Circle().strokeBorder(selection == e ? Theme.pink : .clear, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Color picker row

struct MemberColorPicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: LayoutMetrics.s(12)) {
            ForEach(Theme.memberColors, id: \.self) { hex in
                Button {
                    selection = hex
                    Haptics.shared.tap()
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: LayoutMetrics.s(34), height: LayoutMetrics.s(34))
                        .overlay(
                            Circle().strokeBorder(.white, lineWidth: selection == hex ? 3 : 0)
                        )
                        .shadow(color: Color(hex: hex).opacity(0.6), radius: selection == hex ? 8 : 0)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Pill tag

struct PillTag: View {
    let text: String
    var tint: Color = Theme.purple

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.vertical, 5)
            .padding(.horizontal, LayoutMetrics.s(11))
            .background(Capsule().fill(tint.opacity(0.30)))
    }
}
