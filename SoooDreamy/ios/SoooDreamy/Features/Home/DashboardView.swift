import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState

    @State private var heartBurst = 0
    @State private var showMoodPicker = false
    @State private var dailyAnswerText = ""
    @State private var sendingDaily = false
    @State private var flashback: FlashbackItem?

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground()
                ScrollView {
                    VStack(spacing: LayoutMetrics.s(16)) {
                        header

                        if let inbox = appState.missedInbox, !inbox.isEmpty {
                            missedInboxCard(inbox)
                        }

                        if let milestone = monthiversary {
                            monthiversaryCard(milestone)
                        }

                        if appState.couple == nil {
                            sessionStateCard
                        } else if appState.partner == nil {
                            WaitingForPartnerCard()
                        } else {
                            partnerCard
                        }

                        heartCard
                        touchGrid
                        dailyCard

                        if let flashback {
                            flashbackCard(flashback)
                        }

                        if let next = appState.nextEvent {
                            nextEventCard(next.event, days: next.days)
                        }
                    }
                    .padding(LayoutMetrics.s(16))
                    .padding(.bottom, LayoutMetrics.s(12))
                }
                .refreshable {
                    await appState.refreshAll()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showMoodPicker) {
            MoodPickerSheet()
        }
        .task(id: appState.couple?.id) {
            await loadFlashback()
        }
    }

    // MARK: Flashback ("memory of the day")

    enum FlashbackItem {
        case photo(Photo, daysAgo: Int)
        case daily(DailyEntry, DailyQuestion, daysAgo: Int)
    }

    private func loadFlashback() async {
        // Reset on every (re-)run — the task id changes with the couple, so a
        // server/couple switch must never show the previous couple's memory.
        flashback = nil
        guard let api = appState.api, let couple = appState.couple else { return }
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        var candidates: [FlashbackItem] = []
        if let photos = try? await api.photos() {
            for photo in photos where photo.createdAt < cutoff {
                let days = Int(Date().timeIntervalSince(photo.createdAt) / 86400)
                candidates.append(.photo(photo, daysAgo: days))
            }
        }
        if let entries = try? await api.dailyHistory(limit: 120) {
            for entry in entries where entry.bothAnswered {
                if let date = SharedDates.parse(entry.dateKey), date < cutoff {
                    let question = ContentPack.dailyQuestions.first { $0.id == entry.questionId }
                        ?? ContentPack.dailyQuestion(dateKey: entry.dateKey, coupleId: couple.id)
                    let days = Int(Date().timeIntervalSince(date) / 86400)
                    candidates.append(.daily(entry, question, daysAgo: days))
                }
            }
        }
        flashback = candidates.randomElement()
    }

    @ViewBuilder
    private func flashbackCard(_ item: FlashbackItem) -> some View {
        Button {
            appState.activeTab = .memories
        } label: {
            HStack(spacing: LayoutMetrics.s(12)) {
                switch item {
                case .photo(let photo, let daysAgo):
                    if let url = appState.api?.mediaURL(photo.thumbUrl ?? photo.url) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.white.opacity(0.08)
                        }
                        .frame(width: LayoutMetrics.s(60), height: LayoutMetrics.s(60))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("💭 " + L10n.t("home.flashback"))
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(Theme.gold)
                        if let caption = photo.caption, !caption.isEmpty {
                            Text(caption)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(2)
                        }
                        Text(L10n.t("home.flashbackDaysAgo", ["n": String(daysAgo)]))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                case .daily(_, let question, let daysAgo):
                    Text("💭")
                        .font(.scaled(34))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("home.flashbackQuestion"))
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(Theme.gold)
                        Text(question.text.filled(partner: appState.partnerName, lang: L10n.lang))
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                        Text(L10n.t("home.flashbackDaysAgo", ["n": String(daysAgo)]))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.scaled(12, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassCard(padding: 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: "While you were away" (missed inbox)

    /// Non-zero categories as (emoji, a11y label key, count) chips.
    private func missedEntries(_ inbox: InboxResponse) -> [(key: String, emoji: String, count: Int)] {
        [(key: "home.missed.messages", emoji: "💬", count: inbox.messageCount),
         (key: "home.missed.touches", emoji: "💓", count: inbox.touchCount),
         (key: "home.missed.photos", emoji: "📸", count: inbox.photoCount),
         (key: "home.missed.coupons", emoji: "🎟️", count: inbox.couponCount),
         (key: "home.missed.songs", emoji: "🎶", count: inbox.songCount),
         (key: "home.missed.canvas", emoji: "🎨", count: inbox.canvasCount),
         (key: "home.missed.daily", emoji: "❓", count: inbox.partnerAnsweredDaily ? 1 : 0)]
            .filter { $0.count > 0 }
    }

    /// Preview of the newest missed message — only when the PARTNER sent it.
    private func missedTeaser(_ inbox: InboxResponse) -> String? {
        guard let last = inbox.messages?.last,
              last.senderId != appState.memberId,
              let text = last.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    private func missedInboxCard(_ inbox: InboxResponse) -> some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            HStack(spacing: LayoutMetrics.s(10)) {
                Text("💤")
                    .font(.scaled(26))
                Text(L10n.t("home.missedTitle"))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                Button {
                    Haptics.shared.tap()
                    withAnimation(.spring(response: 0.35)) {
                        appState.missedInbox = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.scaled(11, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: LayoutMetrics.s(26), height: LayoutMetrics.s(26))
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("common.close"))
            }
            HStack(spacing: 6) {
                ForEach(missedEntries(inbox), id: \.key) { entry in
                    HStack(spacing: 4) {
                        Text(entry.emoji)
                            .font(.scaled(13))
                        Text("\(entry.count)")
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, LayoutMetrics.s(9))
                    .background(
                        Capsule()
                            .fill(Theme.purple.opacity(0.22))
                            .overlay(Capsule().strokeBorder(Theme.purple.opacity(0.45), lineWidth: 1))
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(L10n.t(entry.key)): \(entry.count)")
                }
                Spacer(minLength: 0)
            }
            if let teaser = missedTeaser(inbox) {
                Text("💬 „\(teaser)“")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Text(L10n.t("home.missedBody"))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .glassCard(padding: 14)
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .onTapGesture {
            openMissedInbox(inbox)
        }
    }

    /// Tap = clear the card and jump to where most of the action happened
    /// (touches & the daily answer already live here on the dashboard).
    private func openMissedInbox(_ inbox: InboxResponse) {
        Haptics.shared.tap()
        withAnimation(.spring(response: 0.35)) {
            appState.missedInbox = nil
        }
        if inbox.messageCount > 0 {
            appState.activeTab = .chat
        } else if inbox.photoCount + inbox.couponCount + inbox.songCount + inbox.canvasCount > 0 {
            appState.activeTab = .memories
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SoooDreamy")
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    .foregroundStyle(
                        LinearGradient(colors: [Theme.rose, Theme.pink, Theme.purple],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                if let days = appState.daysTogether, days > 0 {
                    Text("\(days) \(L10n.t("home.daysTogether")) 💞")
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            ConnectionBanner(state: appState.socket.state)
        }
        .padding(.top, 6)
    }

    // MARK: Monthiversary (exactly X months / years together today)

    private var monthiversary: (count: Int, years: Bool)? {
        guard let key = appState.couple?.anniversary,
              let start = SharedDates.parse(key) else { return nil }
        let cal = SharedDates.calendar
        let startDay = cal.startOfDay(for: start)
        let today = cal.startOfDay(for: Date())
        guard today > startDay else { return nil }
        let comps = cal.dateComponents([.month, .day], from: startDay, to: today)
        guard let months = comps.month, months >= 1, comps.day == 0 else { return nil }
        if months % 12 == 0 { return (months / 12, true) }
        return (months, false)
    }

    private func monthiversaryCard(_ milestone: (count: Int, years: Bool)) -> some View {
        let text: String
        if milestone.years {
            text = milestone.count == 1
                ? L10n.t("home.anniversaryOneYear")
                : L10n.t("home.anniversaryYears", ["n": String(milestone.count)])
        } else {
            text = milestone.count == 1
                ? L10n.t("home.monthiversaryOne")
                : L10n.t("home.monthiversary", ["n": String(milestone.count)])
        }
        return ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.heroGradient)
                .opacity(0.85)
            FloatingHeartsView(emojis: milestone.years ? ["🥂", "💍", "💖"] : ["🎉", "💞", "✨"], count: 8)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            HStack(spacing: LayoutMetrics.s(12)) {
                Text(milestone.years ? "🥂" : "🎉")
                    .font(.scaled(34))
                Text(text)
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(LayoutMetrics.s(16))
        }
        .frame(minHeight: 68)
        .shadow(color: Theme.pink.opacity(0.4), radius: 14, y: 6)
    }

    // MARK: Session loading / retry (cold start without network)

    private var sessionStateCard: some View {
        VStack(spacing: LayoutMetrics.s(12)) {
            if appState.sessionLoading {
                ProgressView()
                    .tint(Theme.pink)
                Text(L10n.t("common.loading"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("📡")
                    .font(.scaled(40))
                Text(L10n.t("error.network"))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                Button(L10n.t("common.retry")) {
                    Task {
                        await appState.refreshAll()
                        appState.connectSocket()
                    }
                }
                .buttonStyle(SecondaryButtonStyle(fullWidth: false))
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard(padding: 24)
    }

    // MARK: Partner card

    private var partnerCard: some View {
        HStack(spacing: LayoutMetrics.s(14)) {
            EmojiAvatarView(emoji: appState.partner?.avatar,
                            colorHex: appState.partner?.color,
                            size: LayoutMetrics.s(58),
                            online: appState.partner?.online ?? false)

            VStack(alignment: .leading, spacing: 4) {
                Text(appState.partner?.name ?? "–")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                if appState.partner?.online == true {
                    Text(L10n.t("home.online"))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.mint)
                } else if let lastSeen = appState.partner?.lastSeenAt {
                    // Compact app-language relative time + clock icon — easier
                    // to spot than the old locale-driven system phrasing.
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.scaled(9, weight: .semibold))
                        Text(L10n.t("home.lastSeen", ["time": L10n.relativeShort(lastSeen)]))
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                    }
                    .foregroundStyle(Theme.textSecondary)
                } else {
                    Text(L10n.t("home.offline"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }

                if let mood = appState.partner?.mood {
                    HStack(spacing: 6) {
                        Text(mood)
                        if let note = appState.partner?.moodNote, !note.isEmpty {
                            Text(note)
                                .lineLimit(1)
                        }
                    }
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 5)
                    .padding(.horizontal, LayoutMetrics.s(10))
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                }
            }

            Spacer()

            // My mood bubble
            Button {
                showMoodPicker = true
            } label: {
                VStack(spacing: 4) {
                    Text(appState.me?.mood ?? "➕")
                        .font(.scaled(26))
                        .frame(width: LayoutMetrics.s(52), height: LayoutMetrics.s(52))
                        .background(Circle().fill(Theme.purple.opacity(0.25)))
                        .overlay(Circle().strokeBorder(Theme.purple.opacity(0.5), lineWidth: 1.5))
                    Text(L10n.t("home.yourMood"))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .buttonStyle(.plain)
        }
        .glassCard(padding: 14)
    }

    // MARK: Heart

    private var heartCard: some View {
        VStack(spacing: 4) {
            Heart3DView(burstTrigger: heartBurst)
                .frame(height: LayoutMetrics.s(250))
                .contentShape(Rectangle())
                .onTapGesture {
                    heartBurst += 1
                    appState.sendTouch(.heartbeat)
                }

            Text(L10n.t("home.heartTapHint"))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .padding(.bottom, 8)
        }
    }

    // MARK: Touch grid

    private var touchGrid: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(12)) {
            SectionHeader(title: L10n.t("home.sendLove"))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(TouchKind.allCases) { kind in
                    TouchButton(kind: kind) {
                        appState.sendTouch(kind)
                    }
                }
            }
        }
        .glassCard(padding: 16)
    }

    // MARK: Daily question

    private var dailyCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(12)) {
            HStack {
                SectionHeader(title: L10n.t("home.dailyQuestion"))
                if let streak = appState.dailyEntry?.streak, streak > 1 {
                    StreakFirePill(streak: streak)
                }
            }

            if let couple = appState.couple {
                let question = ContentPack.dailyQuestion(dateKey: SharedDates.todayKey(), coupleId: couple.id)
                Text(question.text.filled(partner: appState.partnerName, lang: L10n.lang))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                let entry = appState.dailyEntry
                if entry?.bothAnswered == true {
                    VStack(alignment: .leading, spacing: 8) {
                        answerBubble(name: appState.me?.name ?? L10n.t("common.you"),
                                     text: entry?.myAnswer ?? "", tint: Theme.purple)
                        answerBubble(name: appState.partnerName,
                                     text: entry?.partnerAnswer ?? "", tint: Theme.pink)
                        Text(L10n.t("home.bothAnswered"))
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.mint)
                    }
                } else if entry?.myAnswer != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        answerBubble(name: appState.me?.name ?? L10n.t("common.you"),
                                     text: entry?.myAnswer ?? "", tint: Theme.purple)
                        Text(L10n.t("home.waitingPartnerAnswer", ["name": appState.partnerName]))
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    HStack(spacing: LayoutMetrics.s(10)) {
                        TextField(L10n.t("home.answerNow"), text: $dailyAnswerText, axis: .vertical)
                            .textFieldStyle(DreamyFieldStyle())
                            .lineLimit(1...4)
                        Button {
                            Task { await submitDaily(question: question) }
                        } label: {
                            if sendingDaily {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.scaled(17, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: LayoutMetrics.s(46), height: LayoutMetrics.s(46))
                        .background(Circle().fill(Theme.heroGradient))
                        .disabled(sendingDaily || dailyAnswerText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .glassCard(padding: 16)
    }

    private func answerBubble(name: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name)
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.14))
        )
    }

    private func submitDaily(question: DailyQuestion) async {
        guard let api = appState.api else { return }
        let text = dailyAnswerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sendingDaily = true
        defer { sendingDaily = false }
        do {
            let entry = try await api.answerDaily(dateKey: SharedDates.todayKey(),
                                                  questionId: question.id, text: text)
            appState.dailyEntry = entry
            dailyAnswerText = ""
            SoundEngine.shared.play(.chime)
            Haptics.shared.success()
            appState.updateWidgetSnapshot()
        } catch {
            appState.handleAPIError(error)
        }
    }

    // MARK: Next event

    private func nextEventCard(_ event: EventItem, days: Int) -> some View {
        HStack(spacing: LayoutMetrics.s(14)) {
            Text(event.emoji)
                .font(.scaled(34))
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("home.nextEvent"))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                Text(event.title)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            Text(days == 0 ? L10n.t("home.todayBang")
                 : days == 1 ? L10n.t("home.tomorrow")
                 : L10n.t("home.inDays", ["n": String(days)]))
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundStyle(days <= 1 ? Theme.gold : Theme.pink)
        }
        .glassCard(padding: 16)
        .onTapGesture {
            appState.activeTab = .memories
        }
    }
}

// MARK: - Streak pill

/// Daily-question streak pill; from a 3-day streak on, the flame gently
/// pulses to celebrate that the streak is worth protecting.
struct StreakFirePill: View {
    let streak: Int

    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 4) {
            Text("🔥")
                .font(.scaled(12))
                .scaleEffect(pulsing ? 1.3 : 1.0)
                .animation(pulsing
                           ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                           : .default,
                           value: pulsing)
            Text(L10n.t("home.streak", ["n": String(streak)]))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, LayoutMetrics.s(11))
        .background(Capsule().fill(Theme.gold.opacity(0.30)))
        .onAppear {
            pulsing = streak >= 3
        }
        .onChange(of: streak) { _, newValue in
            pulsing = newValue >= 3
        }
    }
}

// MARK: - Touch button

struct TouchButton: View {
    let kind: TouchKind
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { pressed = true }
            action()
            Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                withAnimation(.spring(response: 0.3)) { pressed = false }
            }
        } label: {
            VStack(spacing: 6) {
                Text(kind.emoji)
                    .font(.scaled(30))
                    .scaleEffect(pressed ? 1.35 : 1)
                Text(L10n.t(kind.titleKey))
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LayoutMetrics.s(14))
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(pressed ? 0.16 : 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Waiting for partner

struct WaitingForPartnerCard: View {
    @Environment(AppState.self) private var appState
    @State private var showQR = false
    @State private var copied = false

    var body: some View {
        VStack(spacing: LayoutMetrics.s(14)) {
            Text("💌")
                .font(.scaled(44))
            Text(L10n.t("home.waitingForPartner"))
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.textPrimary)
            Text(L10n.t("home.waitingForPartnerSub"))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            if let code = appState.couple?.code {
                Text(code.map(String.init).joined(separator: " "))
                    .font(.scaled(34, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Theme.gold)
                    .padding(.vertical, LayoutMetrics.s(10))
                    .padding(.horizontal, LayoutMetrics.s(18))
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.black.opacity(0.3))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Theme.gold.opacity(0.4), lineWidth: 1)
                            )
                    )

                HStack(spacing: LayoutMetrics.s(10)) {
                    Button {
                        UIPasteboard.general.string = code
                        copied = true
                        Haptics.shared.success()
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            copied = false
                        }
                    } label: {
                        Label(L10n.t(copied ? "common.copied" : "common.copy"),
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    ShareLink(item: shareText(code: code)) {
                        Label(L10n.t("common.share"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                Button {
                    withAnimation(.spring(response: 0.35)) { showQR.toggle() }
                } label: {
                    Label(L10n.t("pairing.showQR"), systemImage: "qrcode")
                }
                .buttonStyle(.plain)
                .font(.system(.footnote, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.pink)

                if showQR, let server = appState.servers.activeProfile?.urlString,
                   let qr = QRGenerator.image(for: PairQRPayload.encode(server: server, code: code)) {
                    VStack(spacing: 6) {
                        Image(uiImage: qr)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: LayoutMetrics.s(180), height: LayoutMetrics.s(180))
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 16).fill(.white))
                        Text(L10n.t("pairing.qrHint"))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                }
            }

            HStack(spacing: 8) {
                ProgressView().tint(Theme.pink)
                Text(L10n.t("pairing.waiting"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .glassCard(padding: 20)
    }

    private func shareText(code: String) -> String {
        let server = appState.servers.activeProfile?.urlString ?? ""
        return L10n.isGerman
            ? "Komm zu mir auf SoooDreamy! 💜\nServer: \(server)\nCode: \(code)"
            : "Join me on SoooDreamy! 💜\nServer: \(server)\nCode: \(code)"
    }
}

// MARK: - Mood picker

struct MoodPickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private static let moods = ["🥰", "😊", "😌", "🥳", "😴", "🤒", "😢", "😤",
                                "🥺", "😩", "💪", "🤗", "🫠", "🤍", "😇", "🤪"]

    @State private var selected: String = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: LayoutMetrics.s(16)) {
                        EmojiPickerGrid(emojis: Self.moods, selection: $selected)
                        TextField(L10n.t("home.moodNote"), text: $note, axis: .vertical)
                            .textFieldStyle(DreamyFieldStyle())
                            .lineLimit(1...3)
                        Button(L10n.t("home.setMood")) {
                            appState.setMood(selected.isEmpty ? nil : selected,
                                             note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note)
                            dismiss()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(selected.isEmpty)

                        if appState.me?.mood != nil {
                            Button(L10n.t("common.delete")) {
                                appState.setMood(nil, note: nil)
                                dismiss()
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    .padding(LayoutMetrics.s(20))
                }
            }
            .navigationTitle(L10n.t("home.setMood"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            selected = appState.me?.mood ?? ""
            note = appState.me?.moodNote ?? ""
        }
    }
}

// MARK: - Incoming touch overlay

struct TouchReceivedOverlay: View {
    @Environment(AppState.self) private var appState
    let touch: Touch

    @State private var pulse = false

    private var heartsFor: [String] {
        switch touch.type {
        case .heartbeat: return ["💓", "💗", "💖"]
        case .kiss: return ["💋", "😘", "💖"]
        case .hug: return ["🫂", "🤗", "💞"]
        case .missyou: return ["🥺", "💌", "💜"]
        case .tickle: return ["🪶", "😂", "✨"]
        case .thinking: return ["💭", "💜", "✨"]
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            FloatingHeartsView(emojis: heartsFor, count: 22)
                .ignoresSafeArea()

            VStack(spacing: LayoutMetrics.s(18)) {
                Text(touch.type.emoji)
                    .font(.scaled(110))
                    .scaleEffect(pulse ? 1.15 : 0.9)
                    .shadow(color: Theme.pink.opacity(0.8), radius: 40)
                    .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: pulse)

                Text(L10n.t("touch.received.\(touch.type.rawValue)",
                            ["name": appState.partnerName]))
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LayoutMetrics.s(30))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            appState.incomingTouch = nil
        }
        .onAppear { pulse = true }
    }
}
