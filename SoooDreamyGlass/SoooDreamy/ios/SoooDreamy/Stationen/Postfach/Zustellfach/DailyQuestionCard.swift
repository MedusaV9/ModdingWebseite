import SwiftUI

// The daily-question card — extracted from the old 2 300-line DashboardView
// (W8A component split). Owns the whole answer choreography: input, the
// waiting overture, the sealed state that starts the reveal ceremony, and
// the calm two-voices end state.

/// Schlussrunde 6: persistence for an answer stranded by the daily-pin race
/// (direct 409 before an app kill, or an offline replay that lost the race).
/// One UserDefaults slot per profile+day — same pattern as `LetterDraftStore`;
/// the pure key/prefill rules live in `DailyAnswerDraftRules` (Linux-tested).
enum DailyAnswerDraftStore {
    static func load(profileID: String?, dateKey: String) -> String? {
        UserDefaults.standard.string(
            forKey: DailyAnswerDraftRules.draftKey(profileID: profileID, dateKey: dateKey))
    }

    static func save(_ text: String, profileID: String?, dateKey: String) {
        let key = DailyAnswerDraftRules.draftKey(profileID: profileID, dateKey: dateKey)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(text, forKey: key)
        }
    }

    static func clear(profileID: String?, dateKey: String) {
        UserDefaults.standard.removeObject(
            forKey: DailyAnswerDraftRules.draftKey(profileID: profileID, dateKey: dateKey))
    }
}

/// Shared launcher for the full-screen reveal ceremony — used by the card's
/// sealed state AND by the dashboard's pending-deeplink consumption
/// (`sooodreamy://reveal` from widgets/island), so both paths stay one code.
/// `@MainActor` because it reads AppState and drives RevealCeremony — both
/// main-actor-isolated; every caller is a View, so isolation matches.
@MainActor
enum DailyRevealLauncher {
    /// True while both answered but the seal was never broken on this
    /// device — drives the sealed state and the gold glow (K-03).
    static func revealPending(appState: AppState) -> Bool {
        // Reading `version` re-evaluates this the moment the seal breaks.
        _ = RevealCeremony.shared.version
        guard let entry = appState.dailyEntry, entry.bothAnswered else { return false }
        return !RevealedDailyStore.isRevealed(coupleId: appState.couple?.id,
                                              dateKey: entry.dateKey)
    }

    /// Opens the full-screen ceremony for today's both-answered entry.
    static func present(appState: AppState) {
        guard let couple = appState.couple, let entry = appState.dailyEntry else { return }
        // The entry's server-pinned questionId is pair-authoritative — the
        // ceremony must show the question that was actually answered, not
        // this device's local derivation (see ContentPack.dailyQuestion).
        let question = ContentPack.dailyQuestion(dateKey: SharedDates.todayKey(),
                                                 coupleId: couple.id,
                                                 pinnedId: entry.questionId,
                                                 pinnedText: entry.questionText)
        let questionText = entry.customQuestion?.text
            ?? question.text.filled(partner: appState.partnerName, lang: L10n.lang)
        let author: String? = entry.customQuestion?.authorId.map { authorId in
            authorId == appState.memberId
                ? (appState.me?.name ?? L10n.t("common.you"))
                : appState.partnerName
        }
        RevealCeremony.shared.present(
            coupleId: couple.id,
            dateKey: entry.dateKey,
            question: questionText,
            questionAuthor: author,
            myName: appState.me?.name ?? L10n.t("common.you"),
            partnerName: appState.partnerName,
            entry: entry
        )
    }
}

struct DailyQuestionCard: View {
    /// True when the dashboard stages this card as THE Briefbogen hero of
    /// the screen (Papier & Licht): paper + couple band + the "TAG {n}"
    /// postmark embossing. Embedded/non-hero placements stay plain brief
    /// paper — exactly one Briefbogen per screen.
    var hero = false
    /// The Zustellrunden stamp line ON the sheet ("MORGENPOST · TAG 137",
    /// Neubau §4.1) — the sheet's printed head while the rounds stage.
    /// Nil while the rounds are off; then the circular Poststempel keeps
    /// carrying "TAG {n}" alone (§4.6 static entry). Hero-only.
    var rundenStempel: String?

    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    /// AX5 gate: header chips leave the title row and stack, the sealed
    /// state unstacks — the question never shatters into single letters.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var sharing = false
    @State private var shared = false
    @State private var showStreakCalendar = false
    /// Manage my secret contributions to the couple question pool.
    @State private var showCustomQuestions = false

    private var revealPending: Bool {
        DailyRevealLauncher.revealPending(appState: appState)
    }

    /// The pool-question id the server pinned with the FIRST answer of
    /// TODAY's entry — pair-authoritative (both devices must show exactly
    /// this question). Nil while no entry exists: only then is the local
    /// cycle derivation still a proposal.
    private var pinnedQuestionId: Int? {
        guard let entry = appState.dailyEntry,
              entry.dateKey == SharedDates.todayKey() else { return nil }
        return entry.questionId
    }

    /// The bilingual text stored with the pin (Schlussrunde 5) — renders
    /// the pinned question even when this build's pool doesn't know the
    /// id (mixed-version couple). Same today-gate as the id.
    private var pinnedQuestionText: LText? {
        guard pinnedQuestionId != nil else { return nil }
        return appState.dailyEntry?.questionText
    }

    var body: some View {
        Group {
            if revealPending {
                cardBody.revealGlow()
            } else {
                cardBody
            }
        }
        .sheet(isPresented: $showStreakCalendar) {
            StreakCalendarView()
        }
        .sheet(isPresented: $showCustomQuestions) {
            CustomQuestionsView()
        }
    }

    /// The "TAG {n}" postmark embossing of the Briefbogen hero — the
    /// number is the couple's existing biography count (daysTogether).
    /// While the Stempelzeile prints the round + day on the sheet, the
    /// circular stamp stays empty: the day count never appears twice.
    private var heroStamp: String? {
        guard hero, rundenStempel == nil,
              let days = appState.daysTogether, days > 0 else { return nil }
        return L10n.t("home.stamp.day", ["n": String(days)])
    }

    /// The Stempelzeile (§4.1): anschrift ink on the sheet, a hairline
    /// rule beneath — the printed head of the Briefbogen. The screen's
    /// ONE postal word (the round name) rides here, nowhere else.
    /// FirstMomentCard prints the identical head — one shared component.
    private func stempelzeile(_ text: String) -> some View {
        StempelzeileView(text: text)
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if hero, let rundenStempel {
                // Fix2-A №1: the wax seal overhangs the sheet's top-left
                // corner — the stamp line starts CLEAR of it instead of
                // being eaten to „TA…POST" (decor never eats information).
                stempelzeile(rundenStempel)
                    .padding(.leading, BriefbogenDekor.stempelEinzug(
                        contentPadding: CardPadding.regular.value))
            }
            // AX5: the streak pill and the plus chip leave the title row —
            // squeezed beside a grown SectionHeader they shattered the
            // "Frage des Tages" heading into single letters.
            // Fix4 Befund 2: at AX sizes they leave the card HEAD entirely
            // — stacked under the title they pushed question + composer
            // below the first viewport. The header stays compact (title
            // only); streak + plus wait at the END of the card, after the
            // composer (see the trailing block below).
            Group {
                if dynamicTypeSize.prefersVerticalLayout {
                    SectionHeader(title: L10n.t("home.dailyQuestion"),
                                  systemImage: "questionmark.bubble.fill", onPaper: true)
                } else {
                    HStack {
                        SectionHeader(title: L10n.t("home.dailyQuestion"),
                                      systemImage: "questionmark.bubble.fill", onPaper: true)
                        streakButton
                        customQuestionsButton
                    }
                }
            }
            // Same seal-overhang law for the STAMPLESS hero (rounds off,
            // §4.6 static entry): there the header is the first printed
            // row inside the seal's corner and indents instead.
            .padding(.leading, hero && rundenStempel == nil
                     ? BriefbogenDekor.stempelEinzug(
                        contentPadding: CardPadding.regular.value)
                     : 0)

            if let couple = appState.couple {
                let question = ContentPack.dailyQuestion(dateKey: SharedDates.todayKey(),
                                                         coupleId: couple.id,
                                                         pinnedId: pinnedQuestionId,
                                                         pinnedText: pinnedQuestionText)
                // Custom day: the couple's own question replaces the pack
                // question; who wrote it stays a surprise until both answered.
                // The question is the day's invitation to the couple's own
                // words — serif voice on paper (Papier & Licht).
                let custom = appState.dailyEntry?.customQuestion
                Text(custom?.text ?? question.text.filled(partner: appState.partnerName, lang: L10n.lang))
                    .font(Typo.voice)
                    .foregroundStyle(Tinte.dunkel)
                    .fixedSize(horizontal: false, vertical: true)
                if let custom {
                    PillTag(text: customAuthorLabel(custom), tint: Theme.gold, onPaper: true)
                }

                let entry = appState.dailyEntry
                if entry?.bothAnswered == true {
                    if revealPending {
                        sealedState
                    } else {
                        revealedState(entry: entry, question: question)
                    }
                } else if entry?.myAnswer != nil {
                    waitingState(entry: entry)
                } else {
                    DailyAnswerComposer(question: question)
                }
            }

            // Fix4 Befund 2: the AX tail — streak line (Fix3 №3b: plain
            // full-width ink line, wraps freely) and the plus chip come
            // AFTER the composer, so title → question → answer field fill
            // the first viewport and nothing essential hides below it.
            if dynamicTypeSize.prefersVerticalLayout {
                streakButton
                HStack(spacing: Space.s) {
                    customQuestionsButton
                    Spacer(minLength: 0)
                }
            }
        }
        .paperCard(hero ? .briefbogen : .brief)
        .briefbogenDekor(stamp: heroStamp, active: hero)
    }

    /// The streak pill is a door, not decoration — it opens the calendar.
    /// Fix3 №3b: at AX layout sizes the gold capsule grew into a
    /// multi-line giant pill that outshouted the question — there the
    /// streak becomes a plain full-width TEXT line (wraps freely, no
    /// capsule shell); hierarchy stays title → question → composer.
    @ViewBuilder
    private var streakButton: some View {
        if let streak = appState.dailyEntry?.streak, streak > 1 {
            Button {
                Haptics.shared.tap()
                showStreakCalendar = true
            } label: {
                if dynamicTypeSize.prefersVerticalLayout {
                    HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                        // Seal wax + dark ink — the pill's own onPaper
                        // voices, just without the capsule around them.
                        Image(systemName: "heart.circle.fill")
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(Wachs.rot)
                            .accessibilityHidden(true)
                        Text(L10n.t("home.sharedDays", count: streak))
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(Tinte.dunkel)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    SharedDaysPill(days: streak, onPaper: true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("home.streakCalendar.open"))
        }
    }

    private var customQuestionsButton: some View {
        Button {
            Haptics.shared.tap()
            showCustomQuestions = true
        } label: {
            Image(systemName: "plus.bubble")
                .font(.system(.footnote, design: .rounded).weight(.bold))
                .foregroundStyle(Tinte.tertiaer)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("dailyq.title"))
    }

    /// Both answered, seal unbroken: no content leaks — one tap starts the
    /// full-screen ceremony (Dossier 34, ideas 1/4). Re-eval №12: the
    /// closure is the REAL poured `WachsSiegel` body (the app's one seal
    /// component), not a pale ceremony heart — and the wax-red call line
    /// replaces the disclosure chevron: a sealed letter invites breaking,
    /// it does not navigate.
    private var sealedState: some View {
        Button {
            Haptics.shared.tap()
            DailyRevealLauncher.present(appState: appState)
        } label: {
            Group {
                // AX5: seal + grown text no longer share a row — the texts
                // get the full card width and wrap naturally.
                if dynamicTypeSize.prefersVerticalLayout {
                    VStack(alignment: .leading, spacing: Space.s) {
                        WachsSiegel(size: LayoutMetrics.s(48))
                        sealedTexts
                    }
                } else {
                    HStack(spacing: Space.m) {
                        WachsSiegel(size: LayoutMetrics.s(48))
                        sealedTexts
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(Space.m)
            // Inner surfaces on paper: ink wash + kante hairline, never a
            // second material (the old gold wash was night language).
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Papier.innenFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .strokeBorder(Papier.kante, lineWidth: Theme.hairlineWidth))
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("reveal.card.a11y"))
    }

    private var sealedTexts: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(L10n.t("reveal.ready.title"))
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Tinte.dunkel)
            // Seal red as the call line — wax is the one accent that stays
            // readable ON paper (5.2:1 pinned); lamp gold never writes here.
            Text(L10n.t("reveal.open"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Wachs.rot)
        }
    }

    /// The calm end state after the ceremony: two INK paragraphs on the
    /// letter sheet — the author's ink carries only the name line and the
    /// leading ink edge, running text stays dark ink (Papier & Licht:
    /// legibility before identity).
    private func revealedState(entry: DailyEntry?, question: DailyQuestion) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            inkParagraph(name: appState.me?.name ?? L10n.t("common.you"),
                         text: entry?.myAnswer ?? "", ink: coupleTint.tinteSecondary)
            inkParagraph(name: appState.partnerName,
                         text: entry?.partnerAnswer ?? "", ink: coupleTint.tintePrimary)
            HStack {
                Text(L10n.t("home.bothAnswered"))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Tinte.sekundaer)
                Spacer(minLength: 0)
                shareButton(question: question)
            }
            // On-device follow-up question from both answers — appears
            // only after the reveal, only on AI-capable devices, and the
            // server never participates (on-device privacy contract).
            DailySparkCard(
                question: entry?.customQuestion?.text
                    ?? question.text.filled(partner: appState.partnerName, lang: L10n.lang),
                myName: appState.me?.name ?? L10n.t("common.you"),
                myAnswer: entry?.myAnswer ?? "",
                partnerName: appState.partnerName,
                partnerAnswer: entry?.partnerAnswer ?? "")
                .padding(.top, Space.xs)
        }
    }

    /// The overture: my answer is in, the partner's is still sealed —
    /// anticipation belongs to the choreography (Dossier 34, idea 29).
    private func waitingState(entry: DailyEntry?) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            inkParagraph(name: appState.me?.name ?? L10n.t("common.you"),
                         text: entry?.myAnswer ?? "", ink: coupleTint.tinteSecondary)
            HStack(spacing: Space.s) {
                Image(systemName: "seal.fill")
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(Wachs.rot)
                Text(L10n.t("home.waitingPartnerAnswer", ["name": appState.partnerName]))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Tinte.sekundaer)
            }
            Text(L10n.t("reveal.waiting.hint"))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Tinte.tertiaer)
        }
    }

    /// One ink paragraph on the sheet: the author's name line and a 4-pt
    /// leading ink edge in THEIR ink (`inkOnPaper`-secured), the words
    /// themselves in reading serif and dark ink — couple words on paper.
    private func inkParagraph(name: String, text: String, ink: Color) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(name)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(ink)
            Text(text)
                .font(Typo.brief)
                .foregroundStyle(Tinte.dunkel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: Papier.tintenkante / 2, style: .continuous)
                .fill(ink)
                .frame(width: Papier.tintenkante)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    /// Once both answered, the reveal can be kept forever in the chat.
    @ViewBuilder
    private func shareButton(question: DailyQuestion) -> some View {
        if appState.api != nil {
            Button {
                share(question: question)
            } label: {
                if sharing {
                    BusySpinner(tint: coupleTint.tinte)
                } else {
                    Label(L10n.t(shared ? "games.sharedToChat" : "home.shareAnswers"),
                          systemImage: shared ? "checkmark" : "paperplane.fill")
                }
            }
            .buttonStyle(.plain)
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundStyle(coupleTint.tinte)
            .disabled(sharing || shared)
        }
    }

    /// "your question" / "{name}'s question" / still-hidden author.
    private func customAuthorLabel(_ custom: DailyCustomQuestion) -> String {
        guard let authorId = custom.authorId else { return L10n.t("dailyq.badge.secret") }
        return authorId == appState.memberId
            ? L10n.t("dailyq.badge.mine")
            : L10n.t("dailyq.badge.partner", ["name": appState.partnerName])
    }

    /// Posts today's question with both answers into the couple chat.
    private func share(question: DailyQuestion) {
        guard let api = appState.api, let entry = appState.dailyEntry,
              entry.bothAnswered, !sharing, !shared else { return }
        sharing = true
        Haptics.shared.tap()
        let myName = appState.me?.name ?? L10n.t("common.you")
        let questionText = entry.customQuestion?.text
            ?? question.text.filled(partner: appState.partnerName, lang: L10n.lang)
        let text = L10n.t("home.dailyShareHeader") + " "
            + questionText + "\n"
            + "\(myName): \(entry.myAnswer ?? "")" + "\n"
            + "\(appState.partnerName): \(entry.partnerAnswer ?? "")"
        Task {
            do {
                _ = try await api.sendMessage(type: .text, text: text)
                shared = true
                SoundEngine.shared.play(.pop)
                Haptics.shared.success()
                appState.showToast(L10n.t("games.sharedToChat"), style: .success)
            } catch {
                appState.handleAPIError(error)
            }
            sharing = false
        }
    }

}

// MARK: - Stempelzeile (the printed head of the Briefbogen hero)

/// The Stempelzeile (§4.1): anschrift ink on the sheet, a hairline rule
/// beneath. ONE component for every stamped hero (DailyQuestionCard and
/// the FirstMoment stage), printed in the named `PaperRules.stempelTinteHex`
/// composite — fully opaque secondary ink (7.5:1 on brief, pinned), never
/// an `.opacity` wash (re-eval №3: the 0.7 alpha composited to 3.6:1).
struct StempelzeileView: View {
    var text: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(text)
                .font(Typo.anschrift(
                    isAccessibilitySize: dynamicTypeSize.isAccessibilitySize))
                .foregroundStyle(Color(hex: PaperRules.stempelTinteHex))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Rectangle()
                .fill(Papier.kante)
                .frame(height: Theme.hairlineWidth)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Answer composer (shared by hero card and first-moment stage)

/// The ink-well composer of the day letter: input row, send button and
/// the whole submit choreography (draft persistence, pin-race adoption)
/// in ONE reusable piece. Re-eval №5: the FirstMoment stage embeds this
/// SAME composer directly on its first Briefbogen — a fresh couple
/// focuses and sends (two interactions), and no second bright daily
/// card ever stacks under the stage.
struct DailyAnswerComposer: View {
    let question: DailyQuestion

    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    @State private var answerText = ""
    @State private var sending = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: LayoutMetrics.s(10)) {
                // Ink well ON paper instead of the night-era DreamyField:
                // matte ink wash + kante hairline, the caret writes in the
                // couple's shared ink.
                TextField(L10n.t("home.answerNow"),
                          text: $answerText,
                          // Final-Eval S2: the default placeholder gray is
                          // near-invisible on the bright letter paper — the
                          // prompt writes in explicit tertiary ink.
                          prompt: Text(L10n.t("home.answerNow"))
                              .foregroundStyle(Tinte.tertiaer),
                          axis: .vertical)
                    .paperField()
                    .lineLimit(1...4)
                    // Schlussrunde 6: an answer stranded by the pin race
                    // (409 before an app kill, or a lost replay) comes back
                    // as the day's draft — only into an empty editor.
                    .onAppear {
                        let dateKey = SharedDates.todayKey()
                        guard DailyAnswerDraftRules.shouldPrefill(
                            editorText: answerText,
                            alreadyAnswered: appState.dailyEntry?.myAnswer != nil
                        ), let draft = DailyAnswerDraftStore.load(
                            profileID: appState.servers.activeProfileID?.uuidString,
                            dateKey: dateKey
                        ) else { return }
                        answerText = draft
                    }
                Button {
                    Task { await submit() }
                } label: {
                    if sending {
                        BusySpinner(tint: coupleTint.onGradient)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(.body, design: .rounded).weight(.bold))
                            // Computed foreground on the couple platter —
                            // hard white fails on mint/gold/sky palettes.
                            .foregroundStyle(coupleTint.onGradient)
                    }
                }
                .frame(width: LayoutMetrics.s(46), height: LayoutMetrics.s(46))
                // Scrim travels with the gradient platter (Schlussrunde 4).
                .background(
                    Circle().fill(coupleTint.heroGradient)
                        .overlay(Circle().fill(coupleTint.gradientTextScrim ?? .clear))
                )
                .disabled(sending || answerText.trimmingCharacters(in: .whitespaces).isEmpty)
                // Fix2-A №8: VoiceOver hears the ACTION, never the SF
                // default („paperplane") — the glyph-only button speaks.
                .accessibilityLabel(L10n.t("postfach.antwort.sendenA11y"))
            }
            // Second-answerer choreography: when the partner already
            // answered, submitting IS the reveal (Dossier 34, idea 9).
            // Seal red on paper — lamp gold reads 1.4:1 here (forbidden).
            if appState.missedInbox?.partnerAnsweredDaily == true {
                Text(L10n.t("reveal.partnerWaiting", ["name": appState.partnerName]))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Wachs.rot)
            }
        }
    }

    private func submit() async {
        let text = answerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        defer { sending = false }
        do {
            let entry = try await appState.answerDailyOfflineFirst(
                dateKey: SharedDates.todayKey(),
                questionId: question.id,
                text: text,
                questionText: question.text
            )
            appState.dailyEntry = entry
            answerText = ""
            // The day is answered — a stranded draft slot is stale now.
            DailyAnswerDraftStore.clear(
                profileID: appState.servers.activeProfileID?.uuidString,
                dateKey: SharedDates.todayKey())
            SoundEngine.shared.play(.chime)
            Haptics.shared.success()
            appState.updateWidgetSnapshot()
        } catch {
            // Schlussrunde 5: losing the pin race must not cost the draft.
            // The 409 names the pinned question (id + stored text) — adopt
            // it so the card re-renders the authoritative question with the
            // answer text preserved; the humanizer toast explains the swap.
            if case APIError.httpDetailed(_, let code, _, _, let details) = error,
               code == "daily_question_mismatch", let pinnedId = details.questionId {
                // Schlussrunde 6: persist the draft too — an app kill
                // between this 409 and the re-send must not eat the answer.
                DailyAnswerDraftStore.save(
                    text,
                    profileID: appState.servers.activeProfileID?.uuidString,
                    dateKey: SharedDates.todayKey())
                await appState.adoptPinnedDailyQuestion(questionId: pinnedId,
                                                        questionText: details.questionText)
            }
            appState.handleAPIError(error)
        }
    }
}
