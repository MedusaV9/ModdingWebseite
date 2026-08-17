import SwiftUI

// The "memory of the day" row on the dashboard — extracted from the old
// 2 300-line DashboardView (W8A component split). The parent loads the
// candidates; this card only tells the story and re-posts it to the chat.

/// A randomly chosen memory older than a week: a photo or a fully
/// answered daily question.
enum FlashbackItem {
    case photo(Photo, daysAgo: Int)
    case daily(DailyEntry, DailyQuestion, daysAgo: Int)
}

struct FlashbackCard: View {
    @Environment(AppState.self) private var appState
    let item: FlashbackItem

    /// A2 (re-eval №7): the SAME once-per-day development slot the
    /// OnThisDay card uses — the two memory cards never share a screen
    /// (Flashback only fills in when today has no "on this day"), so one
    /// stable dateKey carries whichever polaroid the day shows.
    @AppStorage("postfach.polaroid.entwickeltTag") private var entwickeltTag = ""

    var body: some View {
        Button {
            appState.activeTab = .memories
        } label: {
            Group {
                switch item {
                case .photo(let photo, let daysAgo):
                    photoBody(photo, daysAgo: daysAgo)
                case .daily(_, let question, let daysAgo):
                    dailyBody(question, daysAgo: daysAgo)
                }
            }
            // Night-first: the flashback row is desk furniture, not the one
            // glowing artifact — only the daily-question briefbogen stays lit.
            .nightCard()
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                share(item)
            } label: {
                Label(L10n.t("home.flashbackShare"), systemImage: "paperplane.fill")
            }
        }
    }

    /// The photo flashback as a real memory polaroid (A2, re-eval №7):
    /// the cover arrives as milky photo paper and develops under the
    /// held thumb — the same component and choreography as OnThisDay
    /// (the inner gesture wins over the card button; the rest of the
    /// card still navigates).
    private func photoBody(_ photo: Photo, daysAgo: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.xs) {
                headerLine
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(Nacht.tertiaer)
            }
            if appState.api != nil {
                coverPhoto(photo)
                    .polaroidEntwickeln(
                        entwickelt: Binding(
                            get: { entwickeltTag == SharedDates.todayKey() },
                            set: { entwickeltTag = $0 ? SharedDates.todayKey() : "" }),
                        ansage: polaroidAnsage(photo, daysAgo: daysAgo),
                        aktionsTitel: L10n.t("postfach.polaroid.a11y"),
                        hinweis: L10n.t("postfach.polaroid.hinweis"),
                        hinweisTippen: L10n.t("postfach.polaroid.hinweis.tippen"))
            }
            if let caption = photo.caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Papier.aufNacht)
                    .lineLimit(2)
            }
            Text(L10n.t("home.flashbackDaysAgo", ["n": String(daysAgo)]))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Nacht.tertiaer)
        }
    }

    private func dailyBody(_ question: DailyQuestion, daysAgo: Int) -> some View {
        HStack(spacing: Space.m) {
            Image(icon: .memory)
                .font(.system(.largeTitle))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Nacht.sekundaer)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("home.flashbackQuestion"))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(Licht.glut)
                Text(question.text.filled(partner: appState.partnerName, lang: L10n.lang))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Papier.aufNacht)
                    .lineLimit(2)
                Text(L10n.t("home.flashbackDaysAgo", ["n": String(daysAgo)]))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Nacht.tertiaer)
        }
    }

    /// „Heute vor {n} Tagen: {Titel}" — the developed announcement, the
    /// same verbatim template as OnThisDay (ENTSCHEID §1.2).
    private func polaroidAnsage(_ photo: Photo, daysAgo: Int) -> String {
        let titel = photo.caption?.isEmpty == false
            ? photo.caption ?? "" : L10n.t("home.flashback")
        return L10n.t("postfach.polaroid.entwickelt",
                      ["wann": L10n.t("postfach.polaroid.wannTage",
                                      ["n": String(daysAgo)]),
                       "titel": titel])
    }

    /// The wide memory cover — the same paper size the OnThisDay page
    /// uses, so the two memory cards speak one format.
    private func coverPhoto(_ photo: Photo) -> some View {
        AuthenticatedAsyncImage(api: appState.api, path: photo.thumbUrl ?? photo.url) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                PaperSkeleton(kind: .tile(height: 150), onNacht: true)
            }
        }
        .frame(height: LayoutMetrics.s(150))
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    /// SF-Symbol memory mark instead of the old 💭 chrome emoji
    /// (commandment 1 — icons answer to tint and weight).
    private var headerLine: some View {
        HStack(spacing: Space.xs) {
            Image(icon: .memory)
                .font(.system(.caption2).weight(.bold))
                .accessibilityHidden(true)
            Text(L10n.t("home.flashback"))
        }
        .font(.system(.caption, design: .rounded).weight(.bold))
        .foregroundStyle(Licht.glut)
    }

    /// Re-posts the memory into the chat — photos as a real photo bubble,
    /// daily questions as text with both answers of back then.
    private func share(_ item: FlashbackItem) {
        guard let api = appState.api else { return }
        Haptics.shared.tap()
        Task {
            do {
                switch item {
                case .photo(let photo, let daysAgo):
                    var text = L10n.t("home.flashbackShareHeader", ["n": String(daysAgo)])
                    if let caption = photo.caption, !caption.isEmpty {
                        text += " " + caption
                    }
                    _ = try await api.sendPhotoMessage(photoId: photo.id, text: text)
                case .daily(let entry, let question, let daysAgo):
                    var lines = [L10n.t("home.flashbackShareHeader", ["n": String(daysAgo)]),
                                 question.text.filled(partner: appState.partnerName, lang: L10n.lang)]
                    let myName = appState.me?.name ?? L10n.t("common.you")
                    if let mine = entry.myAnswer, !mine.isEmpty {
                        lines.append("\(myName): \(mine)")
                    }
                    if let theirs = entry.partnerAnswer, !theirs.isEmpty {
                        lines.append("\(appState.partnerName): \(theirs)")
                    }
                    _ = try await api.sendMessage(type: .text, text: lines.joined(separator: "\n"))
                }
                SoundEngine.shared.play(.pop)
                Haptics.shared.success()
                appState.showToast(L10n.t("home.flashbackShared"), style: .success)
            } catch {
                appState.handleAPIError(error)
            }
        }
    }
}
