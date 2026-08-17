import SwiftUI

/// „An diesem Tag" on the dashboard — a found page from the album, not a
/// list row: the time distance as the headline in the couple's ink, the
/// photo as a wide cover. Swipe it aside and it folds into a quiet pill for
/// the rest of the day (reversible — tapping the pill unfolds it again).
struct OnThisDayCard: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    let response: OnThisDayResponse

    /// The dateKey whose card was swiped away — the pill state resets by
    /// itself the next day because the key no longer matches.
    @AppStorage("sooodreamy.onthisday.dismissedDay") private var dismissedDay = ""
    /// A2: the dateKey whose polaroid was already developed — one held
    /// development carries the whole day, the next day milks up fresh.
    @AppStorage("postfach.polaroid.entwickeltTag") private var entwickeltTag = ""
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        if dismissedDay == response.dateKey {
            pill
        } else if let item = response.items.first {
            card(item)
        }
    }

    // MARK: Card

    private func card(_ item: OnThisDayItem) -> some View {
        Button {
            appState.activeTab = .memories
        } label: {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(spacing: Space.s) {
                    // The couple's shared color stays a non-text glyph;
                    // the label speaks rounded night (serif is paper-only).
                    Image(systemName: "sparkles")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(coupleTint.blend)
                    Text(L10n.t("onthisday.title"))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(Nacht.sekundaer)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(Nacht.tertiaer)
                }
                // The distance IS the headline — "1 Jahr" hits harder than
                // any label around it; on night it glows in lamp gold.
                Text(item.distance.label)
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(Licht.lampengold)
                if item.kind == "photo", let photo = item.photo, appState.api != nil {
                    // A2 „Polaroid entwickeln": the cover arrives as milky
                    // photo paper — holding develops it radially under the
                    // thumb (the inner gesture wins over the card button,
                    // so the photo is the darkroom; the rest of the card
                    // still navigates and still swipes away).
                    coverPhoto(photo)
                        .polaroidEntwickeln(
                            entwickelt: Binding(
                                get: { entwickeltTag == response.dateKey },
                                set: { entwickeltTag = $0 ? response.dateKey : "" }),
                            ansage: polaroidAnsage(item, photo: photo),
                            aktionsTitel: L10n.t("postfach.polaroid.a11y"),
                            hinweis: L10n.t("postfach.polaroid.hinweis"),
                            hinweisTippen: L10n.t("postfach.polaroid.hinweis.tippen"))
                }
                if let line = teaserLine(item) {
                    Text(line)
                        .font(.system(.title3, design: .rounded).italic())
                        .foregroundStyle(Papier.aufNacht)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if let monthiversary = response.monthiversary {
                    Text(L10n.t(
                        MemoriesLogic.monthiversaryLabelKey(unit: monthiversary.unit,
                                                            n: monthiversary.n),
                        ["n": String(monthiversary.n)]))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Licht.lampengold)
                }
                if response.items.count > 1 {
                    Text(L10n.t("onthisday.more", ["count": String(response.items.count - 1)]))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Nacht.tertiaer)
                }
            }
            .nightCard()
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                share(item)
            } label: {
                Label(L10n.t("onthisday.share"), systemImage: "paperplane.fill")
            }
            Button {
                dismissCard()
            } label: {
                Label(L10n.t("onthisday.dismiss"), systemImage: "moon.zzz")
            }
        }
        .offset(x: dragOffset)
        .opacity(1 - Double(min(abs(dragOffset) / 240, 0.9)))
        .gesture(dismissDrag)
        .accessibilityAction(named: Text(L10n.t("onthisday.dismiss"))) {
            dismissCard()
        }
    }

    /// „Heute vor 1 Jahr: {Titel}" — the developed announcement, verbatim
    /// wording from the adopted dossier (ENTSCHEID §1.2).
    private func polaroidAnsage(_ item: OnThisDayItem, photo: MagazinePhoto) -> String {
        let titel = photo.caption?.isEmpty == false
            ? photo.caption ?? "" : L10n.t("onthisday.title")
        return L10n.t("postfach.polaroid.entwickelt",
                      ["wann": item.distance.label, "titel": titel])
    }

    private func coverPhoto(_ photo: MagazinePhoto) -> some View {
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

    /// Swipe the memory aside — some days the past should stay quiet.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 25)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                if abs(value.translation.width) > 110
                    || abs(value.predictedEndTranslation.width) > 260 {
                    dismissCard()
                } else {
                    withAnimation(Theme.Motion.settle) { dragOffset = 0 }
                }
            }
    }

    private func dismissCard() {
        Haptics.shared.tap()
        withAnimation(Theme.Motion.settle) {
            dismissedDay = response.dateKey
            dragOffset = 0
        }
    }

    // MARK: Pill (dismissed state)

    /// The folded card: a quiet capsule that keeps the door to the memory
    /// open instead of pretending it never existed.
    private var pill: some View {
        Button {
            Haptics.shared.tap()
            withAnimation(Theme.Motion.arrive) { dismissedDay = "" }
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: "sparkles")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                Text(L10n.t("onthisday.pill"))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.vertical, Space.s)
            .padding(.horizontal, Space.m)
            .background(Capsule().fill(Theme.innerFill))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    // MARK: Teaser line + share

    /// One preview line: the photo caption or the daily question of back then.
    private func teaserLine(_ item: OnThisDayItem) -> String? {
        switch item.kind {
        case "photo":
            return item.photo?.caption
        case "daily":
            return questionText(item) ?? L10n.t("onthisday.dailyIntro")
        default:
            return nil
        }
    }

    private func questionText(_ item: OnThisDayItem) -> String? {
        if let custom = item.customText { return custom }
        guard let questionId = item.questionId,
              let question = ContentPack.dailyQuestions.first(where: { $0.id == questionId }) else {
            return nil
        }
        return question.text.filled(partner: appState.partnerName, lang: L10n.lang)
    }

    /// Re-posts the memory into the chat with the "on this day" header and
    /// both answers of back then.
    private func share(_ item: OnThisDayItem) {
        guard let api = appState.api else { return }
        Haptics.shared.tap()
        let header = L10n.t("onthisday.shareHeader", ["when": item.distance.label])
        Task {
            do {
                if item.kind == "photo", let photo = item.photo {
                    var text = header
                    if let caption = photo.caption, !caption.isEmpty {
                        text += " " + caption
                    }
                    _ = try await api.sendPhotoMessage(photoId: photo.id, text: text)
                } else {
                    var lines = [header]
                    if let question = questionText(item) {
                        lines.append(question)
                    }
                    let myName = appState.me?.name ?? L10n.t("common.you")
                    if let myId = appState.memberId, let mine = item.answers?[myId], !mine.isEmpty {
                        lines.append("\(myName): \(mine)")
                    }
                    if let partnerId = appState.partner?.id,
                       let theirs = item.answers?[partnerId], !theirs.isEmpty {
                        lines.append("\(appState.partnerName): \(theirs)")
                    }
                    _ = try await api.sendMessage(type: .text, text: lines.joined(separator: "\n"))
                }
                SoundEngine.shared.play(.pop)
                Haptics.shared.success()
                appState.showToast(L10n.t("onthisday.sharedToast"), style: .success)
            } catch {
                appState.handleAPIError(error)
            }
        }
    }
}
