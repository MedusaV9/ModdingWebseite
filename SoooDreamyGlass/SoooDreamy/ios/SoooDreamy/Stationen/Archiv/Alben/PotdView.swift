import SwiftUI
import Combine

// MARK: - Foto des Tages 📷
//
// Every day each partner crowns ONE gallery photo. Together the pairs
// become a photo diary. Submitting again replaces your own pick;
// `potd_submitted` keeps the other phone in sync.

struct PotdView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    @State private var days: [PotdDay] = []
    @State private var photos: [Photo] = []
    @State private var loading = true
    @State private var showPicker = false
    @State private var submitting = false

    /// Each partner's own chosen color marks their slot — never a
    /// stock pink/purple pair. On the NIGHT card the raw member color
    /// stays NON-text (ring + icon accent, ≥3:1 against the dark well);
    /// label text speaks the pinned night inks instead.
    private var myTint: Color {
        appState.me.map { Color(hex: $0.color) } ?? coupleTint.primary
    }

    private var partnerTint: Color {
        appState.partner.map { Color(hex: $0.color) } ?? coupleTint.secondary
    }

    private var today: PotdDay? {
        days.first { $0.dateKey == SharedDates.todayKey() }
    }

    private var pastDays: [PotdDay] {
        days.filter { $0.dateKey != SharedDates.todayKey() }
    }

    var body: some View {
        ZStack {
            DreamyBackground(showStars: false)
            content
        }
        .navigationTitle(L10n.t("potd.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $showPicker) {
            PotdPickerSheet(photos: photos, submitting: $submitting) { photo in
                submit(photo)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            switch event.type {
            case .potdSubmitted:
                if let payload = event.decode(PotdEventPayload.self) {
                    upsert(payload.day)
                }
            case .photoAdded, .photoDeleted:
                Task { await loadPhotos() }
            default:
                break
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            ScrollView {
                VStack(spacing: Space.l) {
                    PaperSkeleton(kind: .card(height: 72), onNacht: true)
                    PaperSkeleton(kind: .card(height: 220), onNacht: true)
                }
                .padding(Space.l)
            }
        } else {
            ScrollView {
                VStack(spacing: Space.l) {
                    promptCard
                    todayCard
                    if !pastDays.isEmpty {
                        historySection
                    }
                }
                .padding(Space.l)
            }
        }
    }

    // MARK: Prompt

    private var promptCard: some View {
        HStack(spacing: Space.m) {
            Image(icon: .photo)
                .font(.system(.title, design: .rounded))
                .foregroundStyle(coupleTint.blend)
                .symbolRenderingMode(.hierarchical)
            Text(L10n.t("potd.prompt"))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightCard()
    }

    // MARK: Today

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text(L10n.t("potd.today"))
                    .font(Typo.title)
                    .foregroundStyle(Papier.aufNacht)
                Spacer()
                if bothPickedToday {
                    PillTag(text: L10n.t("potd.bothPicked"), tint: Theme.mint)
                }
            }
            HStack(spacing: Space.m) {
                potdSlot(day: today, memberId: appState.memberId,
                         label: L10n.t("potd.mine"), mine: true)
                potdSlot(day: today, memberId: appState.partner?.id,
                         label: appState.partnerName, mine: false)
            }
            if photos.isEmpty {
                Text(L10n.t("potd.noPhotos"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
            }
        }
        .nightCard()
    }

    private var bothPickedToday: Bool {
        guard let today, let myId = appState.memberId,
              let partnerId = appState.partner?.id else { return false }
        return today.entries[myId] != nil && today.entries[partnerId] != nil
    }

    @ViewBuilder
    private func potdSlot(day: PotdDay?, memberId: String?, label: String, mine: Bool) -> some View {
        let entry = memberId.flatMap { day?.entries[$0] }
        let slotTint = mine ? myTint : partnerTint
        VStack(spacing: Space.s) {
            // Inner well on the NIGHT card: matte night fill with the member
            // color as a quiet marker edge — the photo itself prints over it.
            ZStack {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Papier.nachtInnenFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .strokeBorder(slotTint.opacity(0.5),
                                          lineWidth: Theme.hairlineWidth)
                    )
                if let entry {
                    photoThumb(entry.photoId)
                } else if mine {
                    VStack(spacing: Space.s) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(.title, design: .rounded))
                            .foregroundStyle(slotTint)
                            .symbolRenderingMode(.hierarchical)
                        Text(L10n.t("potd.pick"))
                            .font(Typo.caption)
                            .foregroundStyle(Nacht.sekundaer)
                    }
                } else {
                    VStack(spacing: Space.s) {
                        Image(systemName: "hourglass")
                            .font(.system(.title2, design: .rounded))
                            .foregroundStyle(Nacht.sekundaer)
                            .symbolRenderingMode(.hierarchical)
                        Text(L10n.t("potd.waitingPartner", ["name": label]))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Nacht.sekundaer)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Space.s)
                    }
                }
            }
            .frame(height: LayoutMetrics.s(150))
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                if mine && !photos.isEmpty {
                    Haptics.shared.tap()
                    showPicker = true
                }
            }
            HStack(spacing: Space.xs) {
                // Label text stays a pinned night ink — identity lives in
                // the member-colored ring/icon, never in running text.
                Text(label)
                    .font(Typo.caption)
                    .foregroundStyle(Nacht.sekundaer)
                if mine && entry != nil {
                    Text("· " + L10n.t("potd.change"))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Nacht.sekundaer)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(L10n.t("potd.history"))
                .font(Typo.title)
                .foregroundStyle(Papier.aufNacht)
            ForEach(pastDays) { day in
                historyRow(day)
            }
        }
        .nightCard()
    }

    private func historyRow(_ day: PotdDay) -> some View {
        HStack(spacing: Space.m) {
            Text(dayLabel(day.dateKey))
                .font(Typo.caption)
                .foregroundStyle(Nacht.sekundaer)
                .frame(width: LayoutMetrics.s(64), alignment: .leading)
            HStack(spacing: Space.s) {
                ForEach(sortedEntries(day), id: \.memberId) { pair in
                    photoThumb(pair.entry.photoId)
                        .frame(width: LayoutMetrics.s(64), height: LayoutMetrics.s(64))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            Text(memberEmoji(pair.memberId))
                                .font(.system(.caption2))
                                .padding(Space.xs)
                        }
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// My photo first, partner's second — stable order in the history rows.
    private func sortedEntries(_ day: PotdDay) -> [(memberId: String, entry: PotdEntry)] {
        day.entries
            .map { (memberId: $0.key, entry: $0.value) }
            .sorted { lhs, rhs in
                (lhs.memberId == appState.memberId ? 0 : 1)
                    < (rhs.memberId == appState.memberId ? 0 : 1)
            }
    }

    private func memberEmoji(_ memberId: String) -> String {
        appState.couple?.members.first { $0.id == memberId }?.avatar ?? "💜"
    }

    private func dayLabel(_ dateKey: String) -> String {
        guard let date = SharedDates.parse(dateKey) else { return dateKey }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    // MARK: Thumbnails

    @ViewBuilder
    private func photoThumb(_ photoId: String) -> some View {
        if let photo = photos.first(where: { $0.id == photoId }) {
            AuthenticatedAsyncImage(api: appState.api, path: photo.thumbUrl ?? photo.url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Papier.nachtInnenFill
                }
            }
        } else {
            ZStack {
                Papier.nachtInnenFill
                Image(systemName: "photo")
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
            }
        }
    }

    // MARK: Data

    private func load() async {
        guard let api = appState.api else { return }
        async let daysTask = try? api.potdDays(limit: 30)
        async let photosTask = try? api.photos()
        days = (await daysTask) ?? []
        photos = (await photosTask) ?? []
        loading = false
    }

    private func loadPhotos() async {
        guard let api = appState.api else { return }
        if let loaded = try? await api.photos() {
            photos = loaded
        }
    }

    private func upsert(_ day: PotdDay) {
        if let idx = days.firstIndex(where: { $0.dateKey == day.dateKey }) {
            days[idx] = day
        } else {
            days.insert(day, at: 0)
        }
    }

    private func submit(_ photo: Photo) {
        guard let api = appState.api, !submitting else { return }
        submitting = true
        Task {
            do {
                let day = try await api.submitPotd(dateKey: SharedDates.todayKey(),
                                                   photoId: photo.id)
                upsert(day)
                showPicker = false
                SoundEngine.shared.play(.sparkle)
                Haptics.shared.success()
                appState.showToast(L10n.t("potd.submittedToast"), style: .success)
            } catch {
                appState.handleAPIError(error)
            }
            submitting = false
        }
    }
}

// MARK: - Picker sheet

private struct PotdPickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint

    let photos: [Photo]
    @Binding var submitting: Bool
    let onPick: (Photo) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: Space.s),
        GridItem(.flexible(), spacing: Space.s),
        GridItem(.flexible(), spacing: Space.s)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Space.s) {
                        ForEach(photos) { photo in
                            Button {
                                onPick(photo)
                            } label: {
                                thumb(photo)
                            }
                            .buttonStyle(.plain)
                            .disabled(submitting)
                        }
                    }
                    .padding(Space.l)
                }
                if submitting {
                    BusySpinner(tint: coupleTint.blend)
                }
            }
            .navigationTitle(L10n.t("potd.pickerTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func thumb(_ photo: Photo) -> some View {
        if appState.api != nil {
            AuthenticatedAsyncImage(api: appState.api, path: photo.thumbUrl ?? photo.url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Theme.innerFill
                }
            }
            .frame(height: LayoutMetrics.s(110))
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
    }
}
