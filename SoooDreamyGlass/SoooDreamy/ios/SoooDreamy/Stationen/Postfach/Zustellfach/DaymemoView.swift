import SwiftUI
import AVFoundation
import Combine

/// "Wie war dein Tag?" — the evening audio ritual. Both partners
/// record up to 60 seconds; the partner's memo unlocks only after you
/// recorded your own (server-enforced). Streak = both-recorded days.
struct DaymemoView: View {
    @Environment(AppState.self) private var appState

    @State private var days: [DaymemoDay] = []
    @State private var streak = 0
    @State private var loading = true
    @State private var loadFailed = false
    @State private var showRecorder = false

    private var today: DaymemoDay? {
        days.first { $0.dateKey == SharedDates.todayKey() }
    }

    var body: some View {
        ZStack {
            DreamyBackground()
            ScrollView {
                VStack(spacing: Space.l) {
                    header
                    todayCard
                    if pastDays.isEmpty && today == nil && !loading {
                        if loadFailed {
                            RitualsLoadFailedNotice(connected: appState.socket.state == .connected) {
                                Task { await reload() }
                            }
                        } else {
                            EmptyStateView(systemImage: "waveform",
                                           title: L10n.t("daymemo.empty.title"),
                                           subtitle: L10n.t("daymemo.empty.subtitle"))
                        }
                    }
                    if !pastDays.isEmpty {
                        historySection
                    }
                }
                .padding(Space.l)
            }
        }
        .navigationTitle(L10n.t("daymemo.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: appState.couple?.id) {
            await reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent, event.type == .daymemo,
                  let day = event.decode(DaymemoDay.self) else { return }
            apply(day)
        }
        .sheet(isPresented: $showRecorder) {
            DaymemoRecorderSheet { day in
                apply(day)
            }
        }
        .onDisappear {
            DaymemoPlayer.shared.stop()
        }
    }

    private var pastDays: [DaymemoDay] {
        days.filter { $0.dateKey != SharedDates.todayKey() }
    }

    private func apply(_ day: DaymemoDay) {
        streak = day.streak
        if let idx = days.firstIndex(where: { $0.dateKey == day.dateKey }) {
            days[idx] = day
        } else {
            days.insert(day, at: 0)
            days.sort { $0.dateKey > $1.dateKey }
        }
    }

    private func reload() async {
        guard let api = appState.api else { return }
        loading = true
        do {
            let response = try await api.daymemos(limit: 30)
            days = response.days
            streak = response.streak
            loadFailed = false
        } catch {
            loadFailed = true
        }
        loading = false
    }

    private var header: some View {
        VStack(spacing: Space.s) {
            Text(L10n.t("daymemo.subtitle"))
                .font(Typo.label)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if streak > 0 {
                HStack(spacing: Space.s) {
                    Image(systemName: "flame.fill")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.gold)
                    Text("\(streak)")
                        .font(Typo.number)
                        .foregroundStyle(Theme.gold)
                    Text(L10n.t("daymemo.streakHint"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Today

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text(L10n.t("common.today"))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                Spacer()
                if today?.bothRecorded == true {
                    PillTag(text: L10n.t("daymemo.card.ready"), tint: Licht.glut)
                }
            }
            DaymemoDayRow(day: today ?? placeholderToday)
            recordButton
        }
        .nightCard()
    }

    private var placeholderToday: DaymemoDay {
        DaymemoDay(dateKey: SharedDates.todayKey(), mine: nil, partner: nil,
                   partnerRecorded: false, bothRecorded: false, streak: streak)
    }

    private var recordButton: some View {
        Button {
            Haptics.shared.tap()
            showRecorder = true
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: "mic.fill")
                Text(L10n.t(today?.mine == nil ? "daymemo.record" : "daymemo.rerecord"))
            }
        }
        .buttonStyle(PrimaryButtonStyle())
    }

    // MARK: History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(L10n.t("daymemo.history"))
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            ForEach(pastDays, id: \.dateKey) { day in
                VStack(alignment: .leading, spacing: Space.s) {
                    Text(dayTitle(day.dateKey))
                        .font(Typo.label)
                        .foregroundStyle(Nacht.sekundaer)
                    DaymemoDayRow(day: day)
                }
                .nightCard()
            }
        }
    }

    private func dayTitle(_ dateKey: String) -> String {
        guard let date = SharedDates.parse(dateKey) else { return dateKey }
        return AppFormatters.date(date, language: L10n.lang)
    }
}

// MARK: - One day's two memos

private struct DaymemoDayRow: View {
    @Environment(AppState.self) private var appState
    let day: DaymemoDay

    var body: some View {
        VStack(spacing: Space.s) {
            memoRow(title: L10n.t("daymemo.mine"),
                    emoji: appState.me?.avatar ?? "🎙️",
                    memo: day.mine,
                    missingText: L10n.t("daymemo.card.hint", ["name": appState.partnerName]))
            memoRow(title: L10n.t("daymemo.theirs", ["name": appState.partnerName]),
                    emoji: appState.partner?.avatar ?? "💜",
                    memo: day.partner,
                    missingText: partnerMissingText)
        }
    }

    private var partnerMissingText: String {
        if day.partnerRecorded && day.partner == nil {
            return L10n.t("daymemo.locked", ["name": appState.partnerName])
        }
        return "…"
    }

    private func memoRow(title: String, emoji: String, memo: Daymemo?, missingText: String) -> some View {
        HStack(spacing: Space.m) {
            Text(emoji)
                .font(.system(.title2))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typo.caption)
                    .foregroundStyle(Nacht.sekundaer)
                if let memo {
                    DaymemoPlayButton(memo: memo)
                } else {
                    Text(missingText)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Nacht.tertiaer)
                        .lineLimit(2)
                }
            }
            Spacer()
            if let memo, let duration = memo.durationSec {
                Text(chatDurationString(duration))
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Nacht.tertiaer)
            }
        }
        .padding(Space.m)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(memo == nil ? Papier.nachtInnenFill : Papier.aufNacht.opacity(0.16))
        )
    }
}

// MARK: - Playback

/// One app-wide player for day memos (same pattern as VoicePlayer, but for
/// raw ritual audio paths instead of chat messages).
@MainActor
@Observable
final class DaymemoPlayer {
    static let shared = DaymemoPlayer()

    private(set) var playingId: String?
    private(set) var isPlaying = false
    private(set) var progress: Double = 0

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var fallbackDuration: Double = 0

    private init() {}

    func toggle(memo: Daymemo, api: API?) {
        if playingId == memo.id {
            if isPlaying {
                player?.pause()
                isPlaying = false
            } else {
                player?.play()
                isPlaying = true
            }
            return
        }
        guard let api, let request = api.mediaRequest(memo.url), let url = request.url else { return }
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": request.allHTTPHeaderFields ?? [:]
        ])
        let item = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        playingId = memo.id
        progress = 0
        fallbackDuration = memo.durationSec ?? 0
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stop()
            }
        }
        timeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player else { return }
                var total = player.currentItem.map { $0.duration.seconds } ?? 0
                if !total.isFinite || total <= 0 { total = self.fallbackDuration }
                self.progress = total > 0 ? min(1, max(0, time.seconds / total)) : 0
            }
        }
        newPlayer.play()
        isPlaying = true
    }

    func stop() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player?.pause()
        player = nil
        playingId = nil
        isPlaying = false
        progress = 0
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}

private struct DaymemoPlayButton: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    let memo: Daymemo

    private var player: DaymemoPlayer { DaymemoPlayer.shared }
    private var isCurrent: Bool { player.playingId == memo.id }

    var body: some View {
        Button {
            Haptics.shared.tap()
            player.toggle(memo: memo, api: appState.api)
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    // Computed ink + platter: white read only 2.94:1 on the
                    // static brand gradient (Schlussrunde 5).
                    .foregroundStyle(Theme.onHero)
                    .frame(width: LayoutMetrics.s(28), height: LayoutMetrics.s(28))
                    .background(Theme.heroPlatter(in: Circle()))
                ChatWaveformBars(seed: memo.id,
                                 progress: isCurrent ? player.progress : 0,
                                 activeTint: coupleTint.blend,
                                 inactiveTint: coupleTint.blend.opacity(0.25))
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recorder sheet (60 s ritual limit)

private struct DaymemoRecorderSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint

    @State private var model = VoiceRecorderModel()
    @State private var sending = false
    /// "Discard this recording?" guard — a finished memo never vanishes
    /// silently (Linse 27, same rule as the chat recorder).
    @State private var confirmDiscard = false
    let onSaved: (DaymemoDay) -> Void

    /// The ritual is deliberately short — 60 seconds, not the chat's 120.
    private let maxDuration: Double = 60

    var body: some View {
        ZStack {
            DreamyBackground(showStars: false)
            VStack(spacing: Space.xl) {
                titleRow
                stage
                Spacer(minLength: 0)
                buttons
            }
            .padding(Space.xl)
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(sending || dismissNeedsConfirmation)
        .onDisappear { model.cancel() }
        .onChange(of: model.elapsed) { _, elapsed in
            if elapsed >= maxDuration && model.phase == .recording {
                model.finishRecording()
            }
        }
        .confirmationDialog(L10n.t("chat.voiceDiscardConfirm"),
                            isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(L10n.t("chat.voiceDiscard"), role: .destructive) {
                model.cancel()
                dismiss()
            }
            Button(L10n.t("chat.voiceKeep"), role: .cancel) {}
        }
    }

    private var dismissNeedsConfirmation: Bool {
        VoiceCaptureGuard.dismissNeedsConfirmation(
            hasFinishedTake: model.phase == .recorded,
            isRecording: model.phase == .recording,
            elapsed: model.elapsed)
    }

    private var titleRow: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "mic.fill")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(coupleTint.blend)
            Text(L10n.t("daymemo.title"))
                .font(Typo.title)
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.top, Space.l)
    }

    @ViewBuilder private var stage: some View {
        switch model.phase {
        case .armed:
            armedStage
        case .denied:
            EmptyStateView(systemImage: "mic.slash",
                           title: L10n.t("chat.voiceDeniedTitle"),
                           subtitle: L10n.t("chat.voiceDeniedSubtitle"),
                           actionTitle: L10n.t("lock.openSettings"),
                           action: {
                               UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                           })
        case .failed:
            EmptyStateView(systemImage: "lifepreserver",
                           title: L10n.t("chat.voiceFailedTitle"),
                           subtitle: L10n.t("chat.voiceFailedSubtitle"),
                           actionTitle: L10n.t("common.retry"),
                           action: {
                               Haptics.shared.tap()
                               model.cancel()
                           })
        case .recording, .recorded:
            recordingStage
        }
    }

    /// Mic idle until the user explicitly taps — no surprise recordings.
    private var armedStage: some View {
        VStack(spacing: Space.l) {
            Button {
                Haptics.shared.tap()
                Task { await model.start() }
            } label: {
                ZStack {
                    // Computed ink + platter: white read only 2.94:1 on the
                    // static brand gradient (Schlussrunde 5).
                    Theme.heroPlatter(in: Circle())
                        .frame(width: LayoutMetrics.s(72), height: LayoutMetrics.s(72))
                        .shadow(color: coupleTint.blend.opacity(0.5), radius: 14, y: 6)
                    Image(systemName: "mic.fill")
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.onHero)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("chat.voiceRecord"))
            Text(L10n.t("chat.voiceArmedHint"))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .nightCard(padding: .hero)
    }

    private var recordingStage: some View {
        VStack(spacing: Space.l) {
            ChatRecorderLevelBars(levels: model.levels, live: model.phase == .recording)
            Text(timeLabel)
                .font(Typo.number)
                .foregroundStyle(Papier.aufNacht)
            // Recording writes in the ember, the finished take in lamplight.
            Text(model.phase == .recording
                 ? L10n.t("chat.voiceRecording")
                 : L10n.t("chat.voiceReady"))
                .font(Typo.label)
                .foregroundStyle(model.phase == .recording ? Licht.glut : Licht.lampengold)
            if model.phase == .recorded {
                previewRow
            } else {
                Text(L10n.t("daymemo.maxHint"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
            }
        }
        .frame(maxWidth: .infinity)
        .nightCard(padding: .hero)
    }

    /// Listen before saving: play/pause + progress + re-record escape hatch.
    private var previewRow: some View {
        HStack(spacing: Space.m) {
            Button {
                Haptics.shared.tap()
                model.togglePreview()
            } label: {
                Image(systemName: model.isPreviewing ? "pause.fill" : "play.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    // Computed ink + platter (Schlussrunde 5).
                    .foregroundStyle(Theme.onHero)
                    .frame(width: LayoutMetrics.s(36), height: LayoutMetrics.s(36))
                    .background(Theme.heroPlatter(in: Circle()))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("chat.voicePreview"))
            ProgressView(value: model.previewProgress)
                .tint(Licht.lampengold)
            Button {
                Haptics.shared.tap()
                model.cancel()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(Nacht.sekundaer)
                    .frame(width: LayoutMetrics.s(36), height: LayoutMetrics.s(36))
                    .background(Circle().fill(Papier.nachtInnenFill)
                        .overlay(Circle().strokeBorder(Nacht.naht,
                                                       lineWidth: Theme.hairlineWidth)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("chat.voiceRerecord"))
        }
    }

    private var timeLabel: String {
        let current = model.phase == .recorded ? model.recordedDuration : model.elapsed
        return "\(chatDurationString(min(current, maxDuration))) / \(chatDurationString(maxDuration))"
    }

    private var buttons: some View {
        HStack(spacing: Space.m) {
            Button(L10n.t("common.cancel")) {
                Haptics.shared.tap()
                if dismissNeedsConfirmation {
                    confirmDiscard = true
                } else {
                    model.cancel()
                    dismiss()
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(sending)

            Button(primaryLabel) {
                primaryAction()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(sending)
        }
        .padding(.bottom, Space.s)
    }

    private var primaryLabel: String {
        if sending { return L10n.t("daymemo.sending") }
        switch model.phase {
        case .armed:
            return L10n.t("chat.voiceRecord")
        case .recording:
            return L10n.t("chat.voiceStop")
        case .recorded:
            return L10n.t("daymemo.saveMemo")
        case .denied, .failed:
            return L10n.t("chat.voiceRetry")
        }
    }

    private func primaryAction() {
        Haptics.shared.tap()
        switch model.phase {
        case .armed, .denied, .failed:
            Task { await model.start() }
        case .recording:
            stopForPreview()
        case .recorded:
            save()
        }
    }

    /// Stop → preview stage. Too-short memos re-arm instead of auto-saving.
    private func stopForPreview() {
        model.finishRecording()
        if model.recordedDuration < 1 {
            Haptics.shared.warning()
            appState.showToast(L10n.t("daymemo.tooShort"), style: .info)
            model.cancel()
        }
    }

    private func save() {
        guard !sending, model.phase == .recorded else { return }
        guard let data = model.recordedData(), let api = appState.api else { return }
        sending = true
        Task {
            do {
                let duration = min(model.recordedDuration, maxDuration)
                let day = try await api.uploadDaymemo(dateKey: SharedDates.todayKey(),
                                                      data: data, durationSec: duration)
                SoundEngine.shared.play(.chime)
                Haptics.shared.success()
                appState.showToast(L10n.t("daymemo.savedToast"), style: .love)
                if day.bothRecorded {
                    // R1-D: the both-recorded moment blooms in the
                    // app-wide Lichtschein instead of confetti.
                    AppCue.fanfareMedium.play()
                    LichtscheinCenter.shared.fire()
                }
                onSaved(day)
                dismiss()
            } catch {
                sending = false
                appState.handleAPIError(error)
            }
        }
    }
}
