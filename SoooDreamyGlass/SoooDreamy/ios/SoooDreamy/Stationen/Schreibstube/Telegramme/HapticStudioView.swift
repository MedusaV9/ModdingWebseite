import CoreHaptics
import SwiftUI

// MARK: - Haptics Studio
// Record a vibe by tapping/holding the pad (press duration = strength),
// feel it, send it as a one-off moment or save it to the couple-shared
// library. Ships with presets; the history section replays vibes an
// offline partner would otherwise have missed.

struct HapticStudioView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.dismiss) private var dismiss
    /// AX5: the preset grid collapses to one column before its labels
    /// shatter (rule in `AccessibilityBudget.gridColumns`).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var builder = HapticRecordingBuilder()
    @State private var padPressed = false
    @State private var patterns: [HapticPatternModel] = []
    @State private var received: [HapticSend] = []
    @State private var showSave = false
    @State private var busy = false
    @State private var renameTarget: HapticPatternModel?
    @State private var renameText = ""
    @State private var deleteTarget: HapticPatternModel?

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    VStack(spacing: LayoutMetrics.s(16)) {
                        composerCard
                        presetsCard
                        libraryCard
                        historyCard
                        if !Haptics.deviceSupportsHaptics {
                            deviceHintCard
                        }
                    }
                    .padding(LayoutMetrics.s(16))
                }
            }
            .navigationTitle(L10n.t("haptic.studio.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("common.done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            handleServerEvent(event)
        }
        .sheet(isPresented: $showSave) {
            HapticSaveSheet(events: builder.events) { name, emoji in
                Task { await savePattern(name: name, emoji: emoji) }
            }
            .presentationDetents([.medium])
        }
        .alert(L10n.t("haptic.rename"), isPresented: renameAlertBinding, presenting: renameTarget) { pattern in
            TextField("", text: $renameText)
            Button(L10n.t("common.save")) {
                Task { await rename(pattern, to: renameText) }
            }
            Button(L10n.t("common.cancel"), role: .cancel) {}
        } message: { _ in EmptyView() }
        .alert(L10n.t("haptic.deleteConfirm"), isPresented: deleteAlertBinding, presenting: deleteTarget) { pattern in
            Button(L10n.t("common.delete"), role: .destructive) {
                Task { await delete(pattern) }
            }
            Button(L10n.t("common.cancel"), role: .cancel) {}
        } message: { _ in EmptyView() }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }

    // MARK: Composer

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(12)) {
            SectionHeader(title: L10n.t("haptic.compose.title"))
            recordPad
            if !builder.isEmpty {
                HapticTimelineBars(events: builder.events)
                    .frame(height: LayoutMetrics.s(44))
                    .padding(.horizontal, 2)
                HStack {
                    Text(L10n.t("haptic.events.count", ["n": String(builder.events.count)]))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Nacht.tertiaer)
                    Spacer()
                    Text(String(format: "%.1fs", builder.recordedDuration))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Nacht.sekundaer)
                }
                composerActions
            }
        }
        .nightCard()
    }

    /// Shared press handler — the drag gesture AND the named VoiceOver
    /// action drive the same recording path (press duration = strength).
    private func padPressBegan() {
        guard !padPressed else { return }
        padPressed = true
        builder.press(at: Date.timeIntervalSinceReferenceDate)
        Haptics.shared.composerTick(intensity: 0.75)
    }

    private func padPressEnded() {
        guard padPressed else { return }
        padPressed = false
        if let event = builder.release(at: Date.timeIntervalSinceReferenceDate), event.d > 0 {
            Haptics.shared.composerTick(intensity: event.i)
        }
    }

    private var recordPad: some View {
        ZStack {
            // Matte night wash instead of the old gradient pane — the
            // couple gradient never returns as a surface wash; the press
            // deepens the couple BLEND (a fill, secured non-text use).
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(padPressed ? AnyShapeStyle(coupleTint.blend.opacity(0.22))
                                 : AnyShapeStyle(Papier.nachtInnenFill))
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(coupleTint.blend.opacity(padPressed ? 0.9 : 0.45),
                              lineWidth: padPressed ? 2 : 1.2)

            VStack(spacing: LayoutMetrics.s(6)) {
                Image(systemName: padPressed ? "dot.radiowaves.left.and.right" : "hand.tap.fill")
                    .font(.system(.largeTitle).weight(.medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Papier.aufNacht)
                    .accessibilityHidden(true)
                Text(L10n.t(builder.isEmpty && !padPressed ? "haptic.pad.idle" : "haptic.pad.active"))
                    .font(.system(.footnote, design: .rounded).weight(.medium))
                    .foregroundStyle(Nacht.sekundaer)
                    .multilineTextAlignment(.center)
                if builder.timelineStart != nil {
                    recordingProgress
                }
            }
            .padding(LayoutMetrics.s(14))
        }
        .frame(height: LayoutMetrics.s(170))
        .scaleEffect(padPressed ? 0.99 : 1)
        .animation(Theme.Motion.settle, value: padPressed)
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in padPressBegan() }
                .onEnded { _ in padPressEnded() }
        )
        // VoiceOver contract (A11y eval): the pad was reachable only through
        // the raw drag gesture. Named start/stop actions drive the exact
        // same recording path, so a blind partner composes the same vibes.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("haptic.pad.a11y"))
        .accessibilityValue(L10n.t(padPressed
            ? "haptic.pad.a11y.recording"
            : (builder.isEmpty ? "haptic.pad.idle" : "haptic.pad.active")))
        .accessibilityHint(L10n.t("haptic.pad.a11y.hint"))
        .accessibilityAction(named: Text(L10n.t("haptic.pad.a11y.start"))) {
            padPressBegan()
        }
        .accessibilityAction(named: Text(L10n.t("haptic.pad.a11y.stop"))) {
            padPressEnded()
        }
    }

    /// Elapsed bar while the timeline is open (caps at the 15 s limit).
    private var recordingProgress: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let elapsed = builder.elapsed(now: Date.timeIntervalSinceReferenceDate)
            ProgressView(value: min(elapsed, HapticTimeline.maxSeconds), total: HapticTimeline.maxSeconds)
                .tint(elapsed >= HapticTimeline.maxSeconds ? Licht.ablauf : coupleTint.blend)
                .frame(width: LayoutMetrics.s(160))
        }
    }

    private var composerActions: some View {
        VStack(spacing: LayoutMetrics.s(8)) {
            HStack(spacing: LayoutMetrics.s(8)) {
                Button {
                    Haptics.shared.play(events: builder.events)
                } label: {
                    Label(L10n.t("haptic.feel"), systemImage: "waveform")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button(role: .destructive) {
                    withAnimation(Theme.Motion.settle) { builder.reset() }
                } label: {
                    Label(L10n.t("haptic.clear"), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            HStack(spacing: LayoutMetrics.s(8)) {
                Button {
                    Task { await sendRecording() }
                } label: {
                    Label(L10n.t("haptic.send"), systemImage: "paperplane.fill")
                }
                .buttonStyle(PrimaryButtonStyle())

                Button {
                    showSave = true
                } label: {
                    Label(L10n.t("common.save"), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .disabled(busy)
    }

    // MARK: Presets

    private var presetsCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            SectionHeader(title: L10n.t("haptic.presets.title"))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                     count: dynamicTypeSize.gridColumns(regular: 2)),
                      spacing: 8) {
                ForEach(HapticPresets.all) { preset in
                    presetCell(preset)
                }
            }
        }
        .nightCard()
    }

    private func presetCell(_ preset: HapticPreset) -> some View {
        HStack(spacing: LayoutMetrics.s(8)) {
            Button {
                Haptics.shared.play(events: preset.events)
            } label: {
                HStack(spacing: LayoutMetrics.s(8)) {
                    Text(preset.emoji).font(.system(.title2))
                    Text(L10n.t(preset.nameKey))
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(Papier.aufNacht)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            Button {
                Task { await send(events: preset.events, name: L10n.t(preset.nameKey), emoji: preset.emoji) }
            } label: {
                Image(systemName: "paperplane.circle.fill")
                    .font(.system(.title2))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(coupleTint.blend)
            }
            .buttonStyle(.plain)
            .disabled(busy)
        }
        .padding(LayoutMetrics.s(10))
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Papier.nachtInnenFill)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(Nacht.naht, lineWidth: Theme.hairlineWidth)
                )
        )
    }

    // MARK: Library

    private var libraryCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            SectionHeader(title: L10n.t("haptic.library.title"))
            if patterns.isEmpty {
                Text(L10n.t("haptic.library.empty"))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, LayoutMetrics.s(12))
            } else {
                ForEach(patterns) { pattern in
                    libraryRow(pattern)
                }
            }
        }
        .nightCard()
    }

    private func libraryRow(_ pattern: HapticPatternModel) -> some View {
        HStack(spacing: LayoutMetrics.s(10)) {
            Button {
                Haptics.shared.play(events: pattern.events)
            } label: {
                HStack(spacing: LayoutMetrics.s(10)) {
                    Text(pattern.emoji ?? "💜").font(.system(.title2))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pattern.name)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Papier.aufNacht)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            HapticTimelineBars(events: pattern.events)
                                .frame(width: LayoutMetrics.s(90), height: LayoutMetrics.s(14))
                            if let count = pattern.sentCount, count > 0 {
                                Text(L10n.t("haptic.sentCount", ["n": String(count)]))
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(Nacht.tertiaer)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            Button {
                Task { await send(pattern: pattern) }
            } label: {
                Image(systemName: "paperplane.circle.fill")
                    .font(.system(.title2))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(coupleTint.blend)
            }
            .buttonStyle(.plain)
            .disabled(busy)
        }
        .padding(.vertical, LayoutMetrics.s(4))
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                renameText = pattern.name
                renameTarget = pattern
            } label: {
                Label(L10n.t("haptic.rename"), systemImage: "pencil")
            }
            Button(role: .destructive) {
                deleteTarget = pattern
            } label: {
                Label(L10n.t("common.delete"), systemImage: "trash")
            }
        }
    }

    // MARK: History

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            SectionHeader(title: L10n.t("haptic.history.title"))
            if received.isEmpty {
                Text(L10n.t("haptic.history.empty"))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, LayoutMetrics.s(12))
            } else {
                ForEach(received.prefix(10)) { send in
                    historyRow(send)
                }
            }
        }
        .nightCard()
    }

    private func historyRow(_ send: HapticSend) -> some View {
        Button {
            Haptics.shared.play(events: send.events)
        } label: {
            HStack(spacing: LayoutMetrics.s(10)) {
                Text(send.emoji ?? "💜").font(.system(.title2))
                VStack(alignment: .leading, spacing: 2) {
                    Text(send.name ?? L10n.t("haptic.adhoc"))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Papier.aufNacht)
                        .lineLimit(1)
                    Text(historySubtitle(send))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Nacht.tertiaer)
                }
                Spacer()
                Image(systemName: "waveform")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(coupleTint.blend)
            }
            .padding(.vertical, LayoutMetrics.s(4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func historySubtitle(_ send: HapticSend) -> String {
        let who = send.senderId == appState.memberId
            ? L10n.t("haptic.fromYou")
            : L10n.t("haptic.fromPartner", ["name": appState.partnerName])
        return "\(who) · \(send.createdAt.formatted(.relative(presentation: .named)))"
    }

    // MARK: Honesty hint (simulator / iPads without a Taptic Engine)

    private var deviceHintCard: some View {
        HStack(alignment: .top, spacing: LayoutMetrics.s(10)) {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .foregroundStyle(Licht.glut)
            Text(L10n.t("haptic.deviceHint"))
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightCard()
    }

    // MARK: Server ops

    private func reload() async {
        guard let api = appState.api else { return }
        async let libraryTask = api.hapticPatterns()
        async let recentTask = api.recentHaptics()
        patterns = (try? await libraryTask) ?? patterns
        received = (try? await recentTask) ?? received
    }

    private func sendRecording() async {
        await send(events: builder.events, name: nil, emoji: nil)
    }

    private func send(events: [HapticEventSpec], name: String?, emoji: String?) async {
        guard let api = appState.api, !events.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await api.sendHaptic(name: name, emoji: emoji, events: events)
            Haptics.shared.success()
            appState.showToast(L10n.t("haptic.sent.toast", ["name": appState.partnerName]), style: .love)
        } catch {
            appState.showToast(error.localizedDescription, style: .info)
        }
    }

    private func send(pattern: HapticPatternModel) async {
        guard let api = appState.api else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await api.sendHapticPattern(id: pattern.id)
            Haptics.shared.success()
            appState.showToast(L10n.t("haptic.sent.toast", ["name": appState.partnerName]), style: .love)
        } catch {
            appState.showToast(error.localizedDescription, style: .info)
        }
    }

    private func savePattern(name: String, emoji: String?) async {
        guard let api = appState.api, !builder.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            let pattern = try await api.saveHapticPattern(name: name, emoji: emoji, events: builder.events)
            upsert(pattern)
            withAnimation(Theme.Motion.settle) { builder.reset() }
            Haptics.shared.success()
            appState.showToast(L10n.t("haptic.saved.toast"), style: .love)
        } catch {
            appState.showToast(error.localizedDescription, style: .info)
        }
    }

    private func rename(_ pattern: HapticPatternModel, to name: String) async {
        guard let api = appState.api else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let updated = try await api.renameHapticPattern(id: pattern.id, name: trimmed, emoji: pattern.emoji)
            upsert(updated)
        } catch {
            appState.showToast(error.localizedDescription, style: .info)
        }
    }

    private func delete(_ pattern: HapticPatternModel) async {
        guard let api = appState.api else { return }
        do {
            try await api.deleteHapticPattern(id: pattern.id)
            patterns.removeAll { $0.id == pattern.id }
        } catch {
            appState.showToast(error.localizedDescription, style: .info)
        }
    }

    private func upsert(_ pattern: HapticPatternModel) {
        if let idx = patterns.firstIndex(where: { $0.id == pattern.id }) {
            patterns[idx] = pattern
        } else {
            patterns.insert(pattern, at: 0)
        }
    }

    private func handleServerEvent(_ event: ServerEvent) {
        switch event.type {
        case .hapticPatternAdded, .hapticPatternUpdated:
            if let pattern = event.decode(HapticPatternResponse.self)?.pattern {
                withAnimation(Theme.Motion.settle) { upsert(pattern) }
            }
        case .hapticPatternDeleted:
            struct DeletedPayload: Decodable { let id: String }
            if let payload = event.decode(DeletedPayload.self) {
                withAnimation(Theme.Motion.settle) { patterns.removeAll { $0.id == payload.id } }
            }
        case .haptic:
            if let haptic = event.decode(HapticSendResponse.self)?.haptic {
                withAnimation(Theme.Motion.settle) { received.insert(haptic, at: 0) }
            }
        default:
            break
        }
    }
}

// MARK: - Timeline visualization

/// Compact bar rendering of a pattern: position = time, height = intensity,
/// width = duration (taps are slim), hue = sharpness (soft violet → crisp pink).
struct HapticTimelineBars: View {
    let events: [HapticEventSpec]

    /// Sub-token detail rounding for the canvas bars — not a card radius.
    private static let barRounding: CGFloat = 2

    var body: some View {
        Canvas { ctx, size in
            let total = max(HapticTimeline.duration(of: events), 0.5)
            for event in events {
                let x = event.t / total * size.width
                let width = max(3, event.d / total * size.width)
                let height = max(5, event.i * (size.height - 2))
                let rect = CGRect(x: x, y: (size.height - height) / 2,
                                  width: min(width, size.width - x), height: height)
                let hue = 0.78 + event.s * 0.14   // violet → pink
                let color = Color(hue: hue, saturation: 0.65, brightness: 1.0)
                ctx.fill(Path(roundedRect: rect, cornerRadius: Self.barRounding),
                         with: .color(color.opacity(event.d > 0 ? 0.65 : 0.95)))
            }
        }
    }
}

// MARK: - Save sheet

struct HapticSaveSheet: View {
    let events: [HapticEventSpec]
    let onSave: (String, String?) -> Void

    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji: String? = "💓"

    private static let emojiChoices = [
        "💓", "💜", "🦋", "🌧️", "😘", "🌊", "✨", "🔥", "🫦", "😏", "💤", "🤗",
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false, showBlobs: false)
                VStack(spacing: LayoutMetrics.s(16)) {
                    HapticTimelineBars(events: events)
                        .frame(height: LayoutMetrics.s(44))
                        .nightCard(padding: .compact)

                    TextField(L10n.t("haptic.save.nameField"), text: $name)
                        .textFieldStyle(DreamyFieldStyle())
                        .submitLabel(.done)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                        ForEach(Self.emojiChoices, id: \.self) { choice in
                            Button {
                                emoji = choice == emoji ? nil : choice
                            } label: {
                                Text(choice)
                                    .font(.system(.title))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, LayoutMetrics.s(6))
                                    .background(
                                        RoundedRectangle(cornerRadius: Radius.concentric(parent: Radius.control, padding: 4),
                                                         style: .continuous)
                                            .fill(choice == emoji ? coupleTint.blend.opacity(0.35) : Theme.innerFill)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), emoji)
                        dismiss()
                    } label: {
                        Label(L10n.t("common.save"), systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()
                }
                .padding(LayoutMetrics.s(16))
            }
            .navigationTitle(L10n.t("haptic.save.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Incoming haptic overlay

/// Full-screen moment when the partner sends a custom vibration. The pattern
/// itself is played by AppState; this view is the visual echo (pulse rings +
/// floating emoji) with a replay button.
///
/// Accessibility contract (A11y eval): announces sender + vibe, moves
/// VoiceOver focus onto the message, offers a NAMED close button next to
/// the replay button (the full-surface tap stays a sighted shortcut).
/// Reduce Motion stills the rings; Reduce Transparency swaps the scrim
/// for solid ink.
struct HapticReceivedOverlay: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.motionGate) private var motionGate
    let haptic: HapticSend

    @State private var pulse = false
    @AccessibilityFocusState private var messageFocused: Bool

    private var message: String {
        L10n.t("haptic.received.overlay", ["name": appState.partnerName])
    }

    var body: some View {
        ZStack {
            motionGate.scrim(0.65)
                .ignoresSafeArea()

            FloatingHeartsView(emojis: [haptic.emoji ?? "💜", "💫", "✨"], count: 18)
                .ignoresSafeArea()

            VStack(spacing: LayoutMetrics.s(20)) {
                ZStack {
                    ForEach(0..<3, id: \.self) { ring in
                        Circle()
                            .strokeBorder(coupleTint.blend.opacity(0.5 - Double(ring) * 0.14), lineWidth: 2)
                            .frame(width: LayoutMetrics.s(130 + CGFloat(ring) * 46),
                                   height: LayoutMetrics.s(130 + CGFloat(ring) * 46))
                            .scaleEffect(pulse ? 1.12 : 0.92)
                            .animation(motionGate.ambient(
                                Theme.Motion.drift(0.7)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(ring) * 0.12)),
                                value: pulse)
                    }
                    Text(haptic.emoji ?? "💜")
                        .font(.system(.largeTitle))
                        .scaleEffect(pulse ? 2.8 : 2.3)
                        .shadow(color: coupleTint.blend.opacity(0.8), radius: 36)
                        .animation(motionGate.ambient(
                            Theme.Motion.drift(0.55).repeatForever(autoreverses: true)),
                            value: pulse)
                }
                .accessibilityHidden(true)

                VStack(spacing: LayoutMetrics.s(6)) {
                    Text(haptic.name ?? L10n.t("haptic.received.title"))
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(.white)
                    Text(message)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, LayoutMetrics.s(30))
                .accessibilityElement(children: .combine)
                .accessibilityFocused($messageFocused)

                HapticTimelineBars(events: haptic.events)
                    .frame(width: LayoutMetrics.s(190), height: LayoutMetrics.s(30))
                    .opacity(0.9)
                    .accessibilityHidden(true)

                HStack(spacing: LayoutMetrics.s(10)) {
                    Button {
                        Haptics.shared.play(events: haptic.events)
                    } label: {
                        Label(L10n.t("haptic.replay"), systemImage: "waveform")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, LayoutMetrics.s(18))
                            .padding(.vertical, LayoutMetrics.s(10))
                            .glass(.chrome, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        appState.incomingHaptic = nil
                    } label: {
                        Label(L10n.t("common.close"), systemImage: "xmark")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, LayoutMetrics.s(18))
                            .padding(.vertical, LayoutMetrics.s(10))
                            .glass(.chrome, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .contentColumn(.reading)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            appState.incomingHaptic = nil
        }
        .accessibilityAddTraits(.isModal)
        .onAppear {
            pulse = true
            messageFocused = true
            let announced = [haptic.name, message].compactMap { $0 }
                .joined(separator: ", ")
            AccessibilityNotification.Announcement(announced).post()
        }
    }
}
