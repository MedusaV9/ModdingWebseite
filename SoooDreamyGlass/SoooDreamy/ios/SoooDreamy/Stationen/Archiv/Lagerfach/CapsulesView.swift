import SwiftUI
import Combine

/// Zeitkapsel-Briefe: sealed letters with a hard server-side unlock
/// date. The recipient sees only the envelope until the capsule is opened
/// in a small ceremony; opened capsules stay as a shared archive.
struct CapsulesView: View {
    @Environment(AppState.self) private var appState

    @State private var capsules: [TimeCapsule] = []
    @State private var loading = true
    @State private var loadFailed = false
    @State private var showCompose = false
    @State private var ceremonyCapsule: TimeCapsule?
    @State private var now = Date()

    var body: some View {
        ZStack {
            DreamyBackground()
            ScrollView {
                VStack(spacing: Space.l) {
                    Text(L10n.t("capsules.subtitle"))
                        .font(Typo.label)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                    Button {
                        Haptics.shared.tap()
                        showCompose = true
                    } label: {
                        Label(L10n.t("capsules.new"), systemImage: "envelope.badge.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    if capsules.isEmpty && !loading {
                        if loadFailed {
                            RitualsLoadFailedNotice(connected: appState.socket.state == .connected) {
                                Task { await reload() }
                            }
                        } else {
                            EmptyStateView(systemImage: "envelope",
                                           title: L10n.t("capsules.empty.title"),
                                           subtitle: L10n.t("capsules.empty.subtitle",
                                                            ["name": appState.partnerName]))
                        }
                    }
                    if !sealed.isEmpty {
                        section(title: L10n.t("capsules.sectionSealed"), items: sealed)
                    }
                    if !opened.isEmpty {
                        section(title: L10n.t("capsules.sectionOpened"), items: opened)
                    }
                }
                .padding(Space.l)
            }
        }
        .navigationTitle(L10n.t("capsules.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: appState.couple?.id) {
            await reload()
        }
        .task(id: nextUnlockAt) {
            guard let unlockAt = nextUnlockAt else { return }
            let delay = unlockAt.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            now = Date()
            await reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            switch event.type {
            case .capsuleSealed, .capsuleOpened:
                if let capsule = event.decode(CapsuleEventPayload.self)?.capsule {
                    apply(capsule)
                }
            case .capsuleDeleted:
                if let id = event.decode(IdPayload.self)?.id {
                    capsules.removeAll { $0.id == id }
                }
            default:
                break
            }
        }
        .sheet(isPresented: $showCompose) {
            CapsuleComposeSheet { capsule in
                apply(capsule)
            }
        }
        .fullScreenCover(item: $ceremonyCapsule) { capsule in
            CapsuleCeremonyView(capsule: capsule)
        }
    }

    private var sealed: [TimeCapsule] { capsules.filter { $0.openedAt == nil } }
    private var opened: [TimeCapsule] { capsules.filter { $0.openedAt != nil } }
    private var nextUnlockAt: Date? {
        sealed.map(\.unlockAt).filter { $0 > now }.min()
    }

    private func apply(_ capsule: TimeCapsule) {
        if let idx = capsules.firstIndex(where: { $0.id == capsule.id }) {
            capsules[idx] = capsule
        } else {
            capsules.insert(capsule, at: 0)
        }
    }

    private func reload() async {
        guard let api = appState.api else { return }
        loading = true
        do {
            capsules = try await api.capsules()
            loadFailed = false
        } catch {
            // A failed primary load must not LOOK like an empty screen —
            // the shared failed/offline notice offers an honest retry.
            loadFailed = true
        }
        loading = false
    }

    private func section(title: String, items: [TimeCapsule]) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(items) { capsule in
                CapsuleRow(capsule: capsule,
                           now: now,
                           onOpen: { open(capsule) },
                           onDelete: capsule.createdBy == appState.memberId && capsule.openedAt == nil
                               ? { delete(capsule) } : nil)
            }
        }
    }

    private func open(_ capsule: TimeCapsule) {
        guard let api = appState.api else { return }
        Task {
            do {
                let openedCapsule = try await api.openCapsule(id: capsule.id)
                apply(openedCapsule)
                // The arbiter grants the size: epic while the app-wide
                // budget lasts, medium afterwards — degraded, never silenced.
                Delight.celebrate(DelightArbiterStore.request(.capsuleOpened),
                                  theme: .hearts)
                ceremonyCapsule = openedCapsule
            } catch {
                appState.handleAPIError(error)
            }
        }
    }

    private func delete(_ capsule: TimeCapsule) {
        guard let api = appState.api else { return }
        Task {
            do {
                try await api.deleteCapsule(id: capsule.id)
                capsules.removeAll { $0.id == capsule.id }
            } catch {
                appState.handleAPIError(error)
            }
        }
    }
}

// MARK: - One capsule row

private struct CapsuleRow: View {
    @Environment(AppState.self) private var appState
    let capsule: TimeCapsule
    let now: Date
    let onOpen: () -> Void
    let onDelete: (() -> Void)?

    @State private var confirmDelete = false

    private var isForMe: Bool { capsule.forMember == appState.memberId }
    private var isUnlocked: Bool { capsule.unlocked || capsule.unlockAt <= now }
    private var canOpen: Bool { isForMe && capsule.openedAt == nil && isUnlocked }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                Text(capsule.emoji ?? "💌")
                    .font(.system(.title))
                VStack(alignment: .leading, spacing: 2) {
                    Text(capsule.title ?? L10n.t("capsules.title"))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Papier.aufNacht)
                        .lineLimit(1)
                    Text(isForMe
                         ? L10n.t("capsules.from", ["name": appState.partnerName])
                         : L10n.t("capsules.forPartner", ["name": appState.partnerName]))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Nacht.sekundaer)
                }
                Spacer()
                statusPill
            }
            if capsule.openedAt != nil, let text = capsule.text {
                Text(text)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
                    .lineLimit(3)
            }
            if canOpen {
                Button(L10n.t("capsules.open")) {
                    Haptics.shared.tap()
                    onOpen()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            if let onDelete {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Text(L10n.t("common.delete"))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Nacht.tertiaer)
                }
                .buttonStyle(.plain)
                .minimumHitTarget()
                .confirmationDialog(L10n.t("capsules.deleteConfirm"),
                                    isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button(L10n.t("common.delete"), role: .destructive) { onDelete() }
                }
            }
        }
        .nightCard()
    }

    @ViewBuilder
    private var statusPill: some View {
        if capsule.openedAt != nil {
            PillTag(text: L10n.t("capsules.openedAt",
                                 ["date": ritualDateString(capsule.openedAt ?? capsule.unlockAt)]),
                    tint: Licht.glut)
        } else if isUnlocked {
            PillTag(text: L10n.t("capsules.readyToOpen"), tint: Theme.gold)
        } else {
            PillTag(text: L10n.t("capsules.sealedUntil",
                                 ["date": ritualDateString(capsule.unlockAt)]),
                    tint: Licht.glut)
        }
    }
}

/// Medium date in the app language ("8. Aug. 2026" / "Aug 8, 2026").
func ritualDateString(_ date: Date) -> String {
    AppFormatters.date(date, language: L10n.lang)
}

// MARK: - Compose sheet

private struct CapsuleComposeSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint
    let onSealed: (TimeCapsule) -> Void

    @State private var title = ""
    @State private var text = ""
    @State private var unlockAt = Date().addingTimeInterval(7 * 86400)
    @State private var galleryPhotos: [Photo] = []
    @State private var photoId: String?
    @State private var sealing = false

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.l) {
                        TextField(L10n.t("capsules.compose.titleField"), text: $title)
                            .textFieldStyle(RitualFieldStyle())
                        TextField(L10n.t("capsules.compose.textField"), text: $text, axis: .vertical)
                            .lineLimit(6...12)
                            .textFieldStyle(RitualFieldStyle())
                        DatePicker(L10n.t("capsules.compose.unlockAt"),
                                   selection: $unlockAt,
                                   in: Date().addingTimeInterval(3600)...,
                                   displayedComponents: [.date])
                            .font(Typo.label)
                            .foregroundStyle(Theme.textPrimary)
                            .tint(coupleTint.blend)
                            .colorScheme(.dark)
                            // System pickers follow the DEVICE locale, the
                            // app speaks ITS language (Amt seam, Re-Eval
                            // Runde 2 roll-out).
                            .environment(\.locale, Locale(identifier: L10n.lang))
                        photoPicker
                        Button(sealing ? L10n.t("capsules.sealing") : L10n.t("capsules.seal")) {
                            seal()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(sealing || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(Space.l)
                }
            }
            .navigationTitle(L10n.t("capsules.compose.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                }
            }
        }
        .task {
            if let photos = try? await appState.api?.photos() {
                galleryPhotos = Array(photos.prefix(12))
            }
        }
    }

    private var photoPicker: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(L10n.t("capsules.compose.photo"))
                .font(Typo.label)
                .foregroundStyle(Theme.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s) {
                    Button {
                        photoId = nil
                    } label: {
                        Text(L10n.t("capsules.compose.photoNone"))
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: LayoutMetrics.s(64), height: LayoutMetrics.s(64))
                            .background(
                                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                    .fill(Theme.innerFill)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                    .strokeBorder(photoId == nil ? coupleTint.blend : Theme.hairline,
                                                  lineWidth: photoId == nil ? 2 : Theme.hairlineWidth)
                            )
                    }
                    .buttonStyle(.plain)
                    ForEach(galleryPhotos) { photo in
                        photoThumb(photo)
                    }
                }
            }
        }
    }

    private func photoThumb(_ photo: Photo) -> some View {
        Button {
            photoId = photo.id
        } label: {
            AuthenticatedAsyncImage(api: appState.api, path: photo.thumbUrl ?? photo.url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    GlassSkeleton(kind: .tile(height: 64))
                }
            }
            .frame(width: LayoutMetrics.s(64), height: LayoutMetrics.s(64))
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(photoId == photo.id ? coupleTint.blend : Theme.hairline,
                                  lineWidth: photoId == photo.id ? 2 : Theme.hairlineWidth)
            )
        }
        .buttonStyle(.plain)
    }

    private func seal() {
        guard let api = appState.api, !sealing else { return }
        sealing = true
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let capsule = try await api.sealCapsule(
                    title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                    emoji: nil,
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    photoId: photoId,
                    unlockAt: unlockAt)
                SoundEngine.shared.play(.sparkle)
                Haptics.shared.success()
                appState.showToast(L10n.t("capsules.sealedToast"), style: .love)
                onSealed(capsule)
                dismiss()
            } catch {
                sealing = false
                appState.handleAPIError(error)
            }
        }
    }
}

/// Glassy text-field chrome shared by the ritual compose sheets.
struct RitualFieldStyle: TextFieldStyle {
    // swiftlint:disable:next identifier_name
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(.body, design: .rounded))
            .foregroundStyle(Theme.textPrimary)
            .padding(Space.m)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Theme.innerFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: Theme.hairlineWidth)
            )
    }
}

// MARK: - Opening ceremony

/// Full-screen dramatic reveal: the envelope wiggles, bursts open and the
/// letter (plus optional photo) fades in.
///
/// Internal since Fix4 Befund 10: the CI proof shots present the ceremony
/// directly (MemoriesView + `ScreenshotSeed.stagedCapsule`) — with
/// `startRevealed` the letter stands open in the very first frame, so the
/// stempelEinzug law is photographable without racing the envelope act.
struct CapsuleCeremonyView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.motionGate) private var motionGate
    let capsule: TimeCapsule

    @State private var revealed: Bool
    @State private var wiggle = false

    init(capsule: TimeCapsule, startRevealed: Bool = false) {
        self.capsule = capsule
        _revealed = State(initialValue: startRevealed)
    }

    var body: some View {
        ZStack {
            DreamyBackground()
            ScrollView {
                VStack(spacing: Space.xl) {
                    Text(L10n.t("capsules.ceremony.title"))
                        .brandTitle()
                        .padding(.top, Space.xxl)
                    Text(L10n.t("capsules.ceremony.hint",
                                ["date": ritualDateString(capsule.createdAt)]))
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)

                    if !revealed {
                        // Hero seal: Typo.hero scaled up visually — the glyph is
                        // decorative, the reserved frame keeps the layout stable.
                        Text(capsule.emoji ?? "💌")
                            .font(Typo.hero)
                            .scaleEffect(2.4)
                            .frame(width: LayoutMetrics.s(120), height: LayoutMetrics.s(120))
                            .rotationEffect(.degrees(wiggle ? 6 : -6))
                            // Endless wiggle — gated: under Reduce Motion the
                            // envelope holds a gentle tilt (MotionGate).
                            .animation(motionGate.ambient(
                                Theme.Motion.drift(0.35).repeatForever(autoreverses: true)),
                                       value: wiggle)
                            .padding(.vertical, Space.xxl)
                            .onAppear { wiggle = true }
                    } else {
                        letter
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }

                    Button(revealed ? L10n.t("common.close") : L10n.t("capsules.open")) {
                        if revealed {
                            dismiss()
                        } else {
                            withAnimation(Theme.Motion.arrive) {
                                revealed = true
                            }
                            // The capsule opens with the app-wide reveal shimmer.
                            AppCue.reveal.play()
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, Space.xxl)
                }
                .padding(Space.l)
            }
        }
    }

    private var letter: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if let title = capsule.title {
                // Fix3 №1: the wax seal overhangs the sheet's top-left
                // corner exactly where the first line prints — the title
                // starts CLEAR of it (decor never eats information;
                // same law as DailyQuestionCard's Stempelzeile).
                Text(title)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(Tinte.dunkel)
                    .padding(.leading, BriefbogenDekor.stempelEinzug(
                        contentPadding: CardPadding.hero.value))
            }
            // Words the partner wrote — the "voice of the relationship" role
            // in dark ink on the unsealed letter.
            Text(capsule.text ?? "")
                .font(Typo.voice)
                .foregroundStyle(Tinte.dunkel)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Same seal-overhang law for the TITLELESS letter: then
                // the body itself is the first printed row inside the
                // seal's corner and indents instead (DailyQuestionCard's
                // stampless-hero branch).
                .padding(.leading, capsule.title == nil
                         ? BriefbogenDekor.stempelEinzug(
                            contentPadding: CardPadding.hero.value)
                         : 0)
            if let photoId = capsule.photoId {
                AuthenticatedAsyncImage(api: appState.api, path: "/api/photos/\(photoId)/raw") { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFit()
                    } else {
                        PaperSkeleton(kind: .tile(height: 180))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            }
            Text(L10n.t("capsules.from", ["name": appState.partnerName]))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Tinte.sekundaer)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        // THE unsealed letter is the one Briefbogen hero of the ceremony:
        // real letter paper wearing the couple's band.
        .paperCard(.briefbogen, padding: .hero)
        .briefbogenDekor()
    }
}
