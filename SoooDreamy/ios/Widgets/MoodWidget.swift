import WidgetKit
import SwiftUI

// MARK: - Timeline

struct MoodEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct MoodProvider: TimelineProvider {
    func placeholder(in context: Context) -> MoodEntry {
        MoodEntry(date: Date(), snapshot: SharedStore.readSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (MoodEntry) -> Void) {
        completion(MoodEntry(date: Date(), snapshot: SharedStore.readSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MoodEntry>) -> Void) {
        // The relative timestamp renders live via Text(_:style:); the app also
        // reloads timelines on mood changes, so a gentle periodic refresh is enough.
        let entry = MoodEntry(date: Date(), snapshot: SharedStore.readSnapshot())
        let refresh = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

// MARK: - Views

struct MoodWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MoodEntry

    private var partnerName: String {
        entry.snapshot?.partnerName ?? WText.t("Dein Schatz", "Your love")
    }

    private var partnerColor: Color {
        Color(hexString: entry.snapshot?.partnerColorHex ?? "FF5C8A")
    }

    private var mood: String? {
        guard let mood = entry.snapshot?.partnerMood, !mood.isEmpty else { return nil }
        return mood
    }

    private var moodNote: String? {
        guard let note = entry.snapshot?.partnerMoodNote, !note.isEmpty else { return nil }
        return note
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: rectangular
            default: small
            }
        }
        .containerBackground(for: .widget) { WTheme.bgGradient }
        .widgetURL(URL(string: "sooodreamy://tab/home"))
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                avatarBubble
                Text(partnerName)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(WTheme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            if let mood {
                Text(mood)
                    .font(.system(size: 38))
                    .minimumScaleFactor(0.6)
                if let moodNote {
                    Text(moodNote)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                if let updatedAt = entry.snapshot?.partnerMoodUpdatedAt {
                    Text(updatedAt, style: .relative)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(WTheme.textSecondary)
                }
            } else {
                emptyState
            }
        }
    }

    private var avatarBubble: some View {
        Text(entry.snapshot?.partnerAvatar ?? "💜")
            .font(.system(size: 13))
            .frame(width: 26, height: 26)
            .background(Circle().fill(partnerColor.opacity(0.3)))
            .overlay(Circle().strokeBorder(partnerColor.opacity(0.6), lineWidth: 1))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("💭")
                .font(.system(size: 32))
            Text(WText.t("Noch keine Stimmung", "No mood yet"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(WTheme.textSecondary)
        }
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            Text(mood ?? "💭")
                .font(.system(size: 26))
            VStack(alignment: .leading, spacing: 1) {
                Text(partnerName)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .lineLimit(1)
                    .widgetAccentable()
                if mood != nil {
                    if let moodNote {
                        Text(moodNote)
                            .font(.system(.caption, design: .rounded))
                            .lineLimit(1)
                    }
                    if let updatedAt = entry.snapshot?.partnerMoodUpdatedAt {
                        Text(updatedAt, style: .relative)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(WText.t("Noch keine Stimmung", "No mood yet"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Widget

struct MoodWidget: Widget {
    let kind = "SoooDreamy.Mood"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MoodProvider()) { entry in
            MoodWidgetView(entry: entry)
        }
        .configurationDisplayName(WText.t("Stimmung", "Mood"))
        .description(WText.t("Zeigt die aktuelle Stimmung deines Schatzes.",
                             "Shows your partner's current mood."))
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}
