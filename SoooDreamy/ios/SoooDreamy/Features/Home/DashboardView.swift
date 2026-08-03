import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState

    @State private var heartBurst = 0
    @State private var showMoodPicker = false
    @State private var dailyAnswerText = ""
    @State private var sendingDaily = false

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        header

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

                        if let next = appState.nextEvent {
                            nextEventCard(next.event, days: next.days)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 12)
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
            HStack(spacing: 12) {
                Text(milestone.years ? "🥂" : "🎉")
                    .font(.system(size: 34))
                Text(text)
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .frame(minHeight: 68)
        .shadow(color: Theme.pink.opacity(0.4), radius: 14, y: 6)
    }

    // MARK: Session loading / retry (cold start without network)

    private var sessionStateCard: some View {
        VStack(spacing: 12) {
            if appState.sessionLoading {
                ProgressView()
                    .tint(Theme.pink)
                Text(L10n.t("common.loading"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("📡")
                    .font(.system(size: 40))
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
        HStack(spacing: 14) {
            EmojiAvatarView(emoji: appState.partner?.avatar,
                            colorHex: appState.partner?.color,
                            size: 58,
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
                    Text(L10n.t("home.lastSeen", ["time": lastSeen.formatted(.relative(presentation: .named))]))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
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
                    .padding(.horizontal, 10)
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
                        .font(.system(size: 26))
                        .frame(width: 52, height: 52)
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
                .frame(height: 250)
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
        VStack(alignment: .leading, spacing: 12) {
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: L10n.t("home.dailyQuestion"))
                if let streak = appState.dailyEntry?.streak, streak > 1 {
                    PillTag(text: "🔥 " + L10n.t("home.streak", ["n": String(streak)]), tint: Theme.gold)
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
                    HStack(spacing: 10) {
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
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 46, height: 46)
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
        HStack(spacing: 14) {
            Text(event.emoji)
                .font(.system(size: 34))
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
                    .font(.system(size: 30))
                    .scaleEffect(pressed ? 1.35 : 1)
                Text(L10n.t(kind.titleKey))
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
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
        VStack(spacing: 14) {
            Text("💌")
                .font(.system(size: 44))
            Text(L10n.t("home.waitingForPartner"))
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.textPrimary)
            Text(L10n.t("home.waitingForPartnerSub"))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            if let code = appState.couple?.code {
                Text(code.map(String.init).joined(separator: " "))
                    .font(.system(size: 34, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Theme.gold)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.black.opacity(0.3))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Theme.gold.opacity(0.4), lineWidth: 1)
                            )
                    )

                HStack(spacing: 10) {
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
                            .frame(width: 180, height: 180)
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
                    VStack(alignment: .leading, spacing: 16) {
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
                    .padding(20)
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

            VStack(spacing: 18) {
                Text(touch.type.emoji)
                    .font(.system(size: 110))
                    .scaleEffect(pulse ? 1.15 : 0.9)
                    .shadow(color: Theme.pink.opacity(0.8), radius: 40)
                    .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: pulse)

                Text(L10n.t("touch.received.\(touch.type.rawValue)",
                            ["name": appState.partnerName]))
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            appState.incomingTouch = nil
        }
        .onAppear { pulse = true }
    }
}
