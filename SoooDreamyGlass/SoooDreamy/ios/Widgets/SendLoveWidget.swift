import WidgetKit
import SwiftUI
import AppIntents

// MARK: - "Send love" — interactive widget (iOS 17 AppIntent buttons)

// Tapping a heart sends a real touch to the partner straight from the home
// screen (no app launch): the intent POSTs to the couple server using the
// app-group-mirrored credentials, then reloads this widget so a short
// "sent 💌" confirmation appears.

struct SendLoveEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let palette: WidgetPalette
    let lastSend: SendLoveState.Last?
    let hasCredentials: Bool
}

struct SendLoveProvider: AppIntentTimelineProvider {
    private func entry(for configuration: CoupleWidgetConfigIntent) -> SendLoveEntry {
        SendLoveEntry(date: Date(),
                      snapshot: WidgetDiagnostics.renderableSnapshot,
                      palette: WidgetPalette.resolve(kind: WidgetKindID.sendLove,
                                                     intentThemeId: configuration.theme.themeId),
                      lastSend: SendLoveState.recent(),
                      hasCredentials: SharedStore.readServerCredentials() != nil)
    }

    func placeholder(in context: Context) -> SendLoveEntry {
        entry(for: CoupleWidgetConfigIntent())
    }

    func snapshot(for configuration: CoupleWidgetConfigIntent, in context: Context) async -> SendLoveEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: CoupleWidgetConfigIntent, in context: Context) async -> Timeline<SendLoveEntry> {
        let current = entry(for: configuration)
        // While a "sent" confirmation shows, schedule its fade-out re-render.
        if current.lastSend != nil {
            let fade = Date().addingTimeInterval(80)
            return Timeline(entries: [current], policy: .after(fade))
        }
        return Timeline(entries: [current], policy: .after(Date().addingTimeInterval(60 * 60)))
    }
}

// MARK: - Views

struct SendLoveWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SendLoveEntry

    private var palette: WidgetPalette { entry.palette }

    private var partnerName: String {
        entry.snapshot?.partnerName ?? WText.t("Dein Schatz", "Your partner")
    }

    private var smallTouches: [WidgetTouchChoice] { [.heartbeat, .kiss, .hug, .thinking] }
    private var mediumTouches: [WidgetTouchChoice] { [.heartbeat, .kiss, .hug, .missyou, .tickle, .thinking] }

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: rectangular
            case .systemMedium: medium
            default: small
            }
        }
        .widgetChrome(palette)
        .widgetFreshness(kind: WidgetKindID.sendLove,
                         updatedAt: entry.snapshot?.updatedAt,
                         now: entry.date, family: family, palette: palette)
        // Taps outside the heart buttons open the app on the home tab —
        // the buttons themselves keep their fire-and-forget intent.
        .widgetURL(ActivityLink.url(ActivityLink.sendLove))
    }

    private var small: some View {
        VStack(spacing: 6) {
            header
            Spacer(minLength: 0)
            if let last = entry.lastSend {
                confirmation(last)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(smallTouches, id: \.rawValue) { touch in
                        touchButton(touch, size: 40)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var medium: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                WAvatarBadge(snapshot: entry.snapshot, size: 30)
                Text(WText.t("Liebe an \(partnerName)", "Love to \(partnerName)"))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                WHeart(palette: palette, size: 14)
            }
            if let last = entry.lastSend {
                Spacer(minLength: 0)
                confirmation(last)
                Spacer(minLength: 0)
            } else {
                HStack(spacing: 8) {
                    ForEach(mediumTouches, id: \.rawValue) { touch in
                        touchButton(touch, size: 42)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            WAvatarBadge(snapshot: entry.snapshot, size: 22)
            Text(partnerName)
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func touchButton(_ touch: WidgetTouchChoice, size: CGFloat) -> some View {
        Button(intent: WidgetSendTouchIntent(type: touch)) {
            Text(touch.emoji)
                .font(WidgetTypo.glyph(size * 0.5))
                .frame(width: size, height: size)
                .background(Circle().fill(palette.chipFill))
                .overlay(Circle().strokeBorder(palette.accent.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!entry.hasCredentials)
    }

    @ViewBuilder
    private func confirmation(_ last: SendLoveState.Last) -> some View {
        VStack(spacing: 3) {
            Text(last.ok ? TouchEmoji.map(last.type) : "😿")
                .font(WidgetTypo.glyph(30))
            Text(last.ok
                 ? WText.t("Gesendet!", "Sent!")
                 : WText.t("Senden fehlgeschlagen", "Send failed"))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(last.ok ? WidgetPalette.mint : palette.accent)
        }
        .transition(.scale.combined(with: .opacity))
    }

    private var rectangular: some View {
        HStack(spacing: 10) {
            if let last = entry.lastSend {
                Text(last.ok ? TouchEmoji.map(last.type) : "😿")
                    .font(WidgetTypo.glyph(22))
                Text(last.ok
                     ? WText.t("Gesendet!", "Sent!")
                     : WText.t("Senden fehlgeschlagen", "Send failed"))
                    .font(.system(.headline, design: .rounded).weight(.bold))
            } else {
                Button(intent: WidgetSendTouchIntent(type: .heartbeat)) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.path.ecg")
                            .font(WidgetTypo.glyph(20, weight: .semibold))
                            .widgetAccentable()
                        VStack(alignment: .leading, spacing: 0) {
                            Text(WText.t("Herzklopfen senden", "Send heartbeat"))
                                .font(.system(.headline, design: .rounded).weight(.bold))
                                .lineLimit(1)
                                .widgetAccentable()
                            Text(WText.t("an \(partnerName)", "to \(partnerName)"))
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!entry.hasCredentials)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Widget

struct SendLoveWidget: Widget {
    let kind = WidgetKindID.sendLove

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: CoupleWidgetConfigIntent.self,
                               provider: SendLoveProvider()) { entry in
            SendLoveWidgetView(entry: entry)
        }
        .configurationDisplayName(WText.t("Liebe senden", "Send love"))
        .description(WText.t("Herzklopfen, Küsse & Umarmungen direkt vom Homescreen senden.",
                             "Send heartbeats, kisses & hugs straight from your home screen."))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
