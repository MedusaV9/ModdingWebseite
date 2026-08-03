import SwiftUI
import Combine

/// Love coupons — little vouchers the partners gift each other.
struct CouponsView: View {
    @Environment(AppState.self) private var appState

    @State private var coupons: [Coupon] = []
    @State private var loading = true
    @State private var showCreate = false
    @State private var redeemTarget: Coupon?
    @State private var confirmRedeem = false
    @State private var deleteTarget: Coupon?
    @State private var confirmDelete = false
    @State private var celebrationDate: Date?
    @State private var celebrationTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            DreamyBackground(showStars: false)
            content
            if appState.partner != nil {
                floatingCreateButton
            }
            if let started = celebrationDate {
                FloatingHeartsView(emojis: ["🎟️", "💖", "✨", "🎉", "💜"], count: 20, startedAt: started)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle(L10n.t("memories.coupons.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadCoupons() }
        .sheet(isPresented: $showCreate) {
            CouponCreateSheet { coupon in
                insert(coupon)
            }
        }
        .confirmationDialog(L10n.t("memories.coupons.redeemConfirm"),
                            isPresented: $confirmRedeem, titleVisibility: .visible,
                            presenting: redeemTarget) { coupon in
            Button(L10n.t("memories.coupons.redeem")) { redeem(coupon) }
            Button(L10n.t("common.cancel"), role: .cancel) {}
        }
        .confirmationDialog(L10n.t("memories.coupons.deleteConfirm"),
                            isPresented: $confirmDelete, titleVisibility: .visible,
                            presenting: deleteTarget) { coupon in
            Button(L10n.t("common.delete"), role: .destructive) { delete(coupon) }
            Button(L10n.t("common.cancel"), role: .cancel) {}
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            handleServerEvent(event)
        }
    }

    // MARK: Derived lists

    /// Coupons made for me — unredeemed first, newest first within each group.
    private var forMe: [Coupon] {
        coupons
            .filter { $0.forMember == appState.memberId }
            .sorted { lhs, rhs in
                if (lhs.redeemedAt == nil) != (rhs.redeemedAt == nil) {
                    return lhs.redeemedAt == nil
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    /// Coupons I created for my partner, newest first.
    private var byMe: [Coupon] {
        coupons
            .filter { $0.createdBy == appState.memberId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if appState.partner == nil {
            noPartnerState
        } else if loading {
            LoadingView()
        } else {
            couponList
        }
    }

    private var noPartnerState: some View {
        VStack {
            Spacer()
            EmptyStateView(emoji: "🎟️",
                           title: L10n.t("memories.coupons.noPartner.title"),
                           subtitle: L10n.t("memories.coupons.noPartner.subtitle"))
            Spacer()
        }
    }

    private var couponList: some View {
        List {
            Section {
                if forMe.isEmpty {
                    emptyHint(L10n.t("memories.coupons.emptyForYou"))
                } else {
                    ForEach(forMe) { coupon in
                        voucherCard(coupon)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                    }
                }
            } header: {
                SectionHeader(title: L10n.t("memories.coupons.forYou"))
            }
            Section {
                if byMe.isEmpty {
                    emptyHint(L10n.t("memories.coupons.emptyFromYou"))
                } else {
                    ForEach(byMe) { coupon in
                        createdRow(coupon)
                    }
                }
            } header: {
                SectionHeader(title: L10n.t("memories.coupons.fromYou"))
            }
            Color.clear
                .frame(height: 70)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 10)
        .refreshable { await loadCoupons() }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    // MARK: Voucher card (for me)

    private func voucherCard(_ coupon: Coupon) -> some View {
        let redeemed = coupon.redeemedAt != nil
        return VStack(spacing: 12) {
            HStack(spacing: 14) {
                Text(coupon.emoji)
                    .font(.system(size: 40))
                VStack(alignment: .leading, spacing: 4) {
                    Text(coupon.title)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(redeemed ? Theme.textSecondary : Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note = coupon.note, !note.isEmpty {
                        Text(note)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(fromInfo(coupon))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
            }
            if let redeemedAt = coupon.redeemedAt {
                redeemedStamp(redeemedAt)
            } else {
                Button(L10n.t("memories.coupons.redeem")) {
                    Haptics.shared.tap()
                    redeemTarget = coupon
                    confirmRedeem = true
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Theme.pink.opacity(redeemed ? 0.06 : 0.16),
                                              Theme.purple.opacity(redeemed ? 0.05 : 0.12)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.pink.opacity(redeemed ? 0.25 : 0.55),
                              style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
        )
        .saturation(redeemed ? 0.4 : 1)
        .opacity(redeemed ? 0.75 : 1)
    }

    private func redeemedStamp(_ date: Date) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 13, weight: .bold))
            Text(L10n.t("memories.coupons.redeemedAt",
                        ["date": date.formatted(date: .abbreviated, time: .omitted)]))
                .font(.system(.caption, design: .rounded).weight(.bold))
        }
        .foregroundStyle(Theme.mint)
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Capsule().fill(Theme.mint.opacity(0.14)))
        .rotationEffect(.degrees(-2))
    }

    private func fromInfo(_ coupon: Coupon) -> String {
        let name = appState.couple?.members.first { $0.id == coupon.createdBy }?.name
            ?? appState.partnerName
        let date = coupon.createdAt.formatted(date: .abbreviated, time: .omitted)
        return L10n.t("memories.coupons.from", ["name": name]) + " · " + date
    }

    // MARK: Created row (by me)

    private func createdRow(_ coupon: Coupon) -> some View {
        HStack(spacing: 12) {
            Text(coupon.emoji)
                .font(.system(size: 26))
            VStack(alignment: .leading, spacing: 2) {
                Text(coupon.title)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text(forInfo(coupon))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            statusChip(coupon)
        }
        .glassCard(padding: 12)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if coupon.redeemedAt == nil {
                Button(role: .destructive) {
                    deleteTarget = coupon
                    confirmDelete = true
                } label: {
                    Label(L10n.t("common.delete"), systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private func statusChip(_ coupon: Coupon) -> some View {
        if coupon.redeemedAt != nil {
            PillTag(text: L10n.t("memories.coupons.statusRedeemed"), tint: Theme.mint)
        } else {
            PillTag(text: L10n.t("memories.coupons.statusOpen"), tint: Theme.gold)
        }
    }

    private func forInfo(_ coupon: Coupon) -> String {
        let date = coupon.createdAt.formatted(date: .abbreviated, time: .omitted)
        return L10n.t("memories.coupons.forName", ["name": appState.partnerName]) + " · " + date
    }

    // MARK: Create button

    private var floatingCreateButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    Haptics.shared.tap()
                    showCreate = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(Theme.heroGradient)
                            .frame(width: 60, height: 60)
                            .shadow(color: Theme.pink.opacity(0.5), radius: 14, y: 6)
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("memories.coupons.create"))
                .padding(.trailing, 20)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: Actions

    private func loadCoupons() async {
        guard let api = appState.api else { return }
        do {
            coupons = try await api.coupons()
        } catch {
            appState.handleAPIError(error)
        }
        loading = false
    }

    private func redeem(_ coupon: Coupon) {
        guard let api = appState.api else { return }
        Task {
            do {
                let updated = try await api.redeemCoupon(id: coupon.id)
                apply(updated)
                SoundEngine.shared.play(.tada)
                Haptics.shared.success()
                celebrate()
            } catch {
                appState.handleAPIError(error)
            }
        }
    }

    private func delete(_ coupon: Coupon) {
        guard let api = appState.api else { return }
        coupons.removeAll { $0.id == coupon.id }
        Task {
            do {
                try await api.deleteCoupon(id: coupon.id)
            } catch {
                insert(coupon)
                appState.handleAPIError(error)
            }
        }
    }

    private func celebrate() {
        celebrationDate = Date()
        celebrationTask?.cancel()
        celebrationTask = Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if !Task.isCancelled { celebrationDate = nil }
        }
    }

    // MARK: Realtime

    private func insert(_ coupon: Coupon) {
        guard !coupons.contains(where: { $0.id == coupon.id }) else { return }
        coupons.append(coupon)
    }

    private func apply(_ coupon: Coupon) {
        if let idx = coupons.firstIndex(where: { $0.id == coupon.id }) {
            coupons[idx] = coupon
        } else {
            coupons.append(coupon)
        }
    }

    private func handleServerEvent(_ event: ServerEvent) {
        switch event.type {
        case .couponAdded:
            if let coupon = event.decode(CouponResponse.self)?.coupon {
                insert(coupon)
            }
        case .couponRedeemed:
            if let coupon = event.decode(CouponResponse.self)?.coupon {
                apply(coupon)
            }
        case .couponDeleted:
            if let id = event.decode(IdPayload.self)?.id {
                coupons.removeAll { $0.id == id }
            }
        default:
            break
        }
    }
}

// MARK: - Create sheet

private struct CouponCreateSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let onCreated: (Coupon) -> Void

    @State private var title = ""
    @State private var note = ""
    @State private var emoji = "🎟️"
    @State private var saving = false

    private static let emojis = [
        "🎟️", "💆", "🍳", "🎬", "🧖", "🍕",
        "🌹", "📽️", "🛁", "💃", "🚗", "🧺",
        "🌟", "🍝", "🎮", "😴", "🧽", "🚶"
    ]

    /// Preset ideas — bundled content (like ContentPack), not L10n keys.
    private struct CouponPreset: Identifiable {
        let id: Int
        let emoji: String
        let title: LText
    }

    private static let presets: [CouponPreset] = [
        CouponPreset(id: 1, emoji: "💆", title: LText(de: "1× Massage", en: "1× massage")),
        CouponPreset(id: 2, emoji: "🍳", title: LText(de: "Frühstück ans Bett", en: "Breakfast in bed")),
        CouponPreset(id: 3, emoji: "🎬", title: LText(de: "Filmabend — du wählst", en: "Movie night — you pick")),
        CouponPreset(id: 4, emoji: "🧽", title: LText(de: "1× Abwasch übernehmen", en: "1× doing the dishes")),
        CouponPreset(id: 5, emoji: "🧺", title: LText(de: "Picknick-Date", en: "Picnic date")),
        CouponPreset(id: 6, emoji: "🚶", title: LText(de: "Langer Spaziergang", en: "A long walk together")),
        CouponPreset(id: 7, emoji: "🌟", title: LText(de: "1× Wunsch frei", en: "One free wish")),
        CouponPreset(id: 8, emoji: "🍝", title: LText(de: "Selbstgekochtes Dinner", en: "Home-cooked dinner")),
        CouponPreset(id: 9, emoji: "🎮", title: LText(de: "Gaming-Abend zusammen", en: "Gaming night together")),
        CouponPreset(id: 10, emoji: "😴", title: LText(de: "Ausschlafen — ich übernehme alles", en: "Sleep in — I'll handle everything"))
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        presetRow
                        titleField
                        noteField
                        emojiSection
                        createButton
                    }
                    .padding(16)
                }
            }
            .navigationTitle(L10n.t("memories.coupons.createTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                        .tint(Theme.pink)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var presetRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("memories.coupons.ideas"))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.presets) { preset in
                        presetChip(preset)
                    }
                }
            }
        }
    }

    private func presetChip(_ preset: CouponPreset) -> some View {
        Button {
            Haptics.shared.tap()
            title = preset.title.resolved(L10n.lang)
            emoji = preset.emoji
        } label: {
            Text("\(preset.emoji) \(preset.title.resolved(L10n.lang))")
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.07))
                        .overlay(Capsule().strokeBorder(Theme.purple.opacity(0.35), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }

    private var titleField: some View {
        TextField(L10n.t("memories.coupons.titleField"), text: $title)
            .textFieldStyle(DreamyFieldStyle())
            .submitLabel(.done)
    }

    private var noteField: some View {
        TextField(L10n.t("memories.coupons.noteField"), text: $note, axis: .vertical)
            .textFieldStyle(DreamyFieldStyle())
            .lineLimit(1...3)
    }

    private var emojiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("memories.events.emoji"))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            EmojiPickerGrid(emojis: Self.emojis, selection: $emoji)
        }
    }

    private var createButton: some View {
        Button {
            create()
        } label: {
            if saving {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
            } else {
                Text(L10n.t("memories.coupons.create"))
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func create() {
        guard let api = appState.api, !saving else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        saving = true
        Task {
            do {
                let coupon = try await api.createCoupon(title: trimmedTitle,
                                                        emoji: emoji,
                                                        note: trimmedNote.isEmpty ? nil : trimmedNote)
                onCreated(coupon)
                SoundEngine.shared.play(.chime)
                Haptics.shared.success()
                appState.showToast(L10n.t("memories.coupons.created"), style: .love)
                dismiss()
            } catch {
                appState.handleAPIError(error)
            }
            saving = false
        }
    }
}
