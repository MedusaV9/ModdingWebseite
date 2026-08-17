import SwiftUI

/// Date-idea generator: set your filters, pull the lever and let the
/// slot machine decide your next date. Favorites go straight to the
/// shared bucket list.
struct DateIdeasView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum LocationFilter: String, CaseIterable {
        case any, indoor, outdoor
    }

    /// Mood tags offered as chips ("longdistance" has its own toggle).
    private static let moodTags = [
        "cozy", "adventure", "creative", "food", "romantic", "silly", "athome", "night"
    ]

    @State private var location: LocationFilter = .any
    @State private var maxBudget: Int?
    @State private var longDistance = false
    @State private var selectedTags: Set<String> = []

    @State private var idea: DateIdea?
    @State private var spinIdea: DateIdea?
    @State private var spinning = false
    @State private var addingToBucket = false
    @State private var addedIdeaIds: Set<Int> = []
    @State private var sharingIdea = false
    @State private var sharedIdeaIds: Set<Int> = []

    var body: some View {
        ZStack {
            DreamyBackground()
            ScrollView {
                VStack(spacing: LayoutMetrics.s(16)) {
                    filtersCard
                    resultArea
                    generateButtons
                }
                .padding(LayoutMetrics.s(16))
                .padding(.bottom, LayoutMetrics.s(12))
            }
        }
        .navigationTitle(L10n.t("games.card.dateideas.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Filtering

    private var pool: [DateIdea] {
        ContentPack.dateIdeas.filter { candidate in
            if location == .indoor && !candidate.indoor { return false }
            if location == .outdoor && candidate.indoor { return false }
            if let maxBudget, candidate.budget > maxBudget { return false }
            if longDistance && !candidate.tags.contains("longdistance") { return false }
            if !selectedTags.isEmpty && selectedTags.isDisjoint(with: Set(candidate.tags)) {
                return false
            }
            return true
        }
    }

    // MARK: Filters UI

    private var filtersCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(14)) {
            locationSection
            budgetSection
            moodSection
            longDistanceToggle
        }
        .nightCard()
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            filterLabel(L10n.t("games.dateideas.location"))
            HStack(spacing: 8) {
                ForEach(LocationFilter.allCases, id: \.rawValue) { option in
                    filterChip(label: L10n.t("games.dateideas.location.\(option.rawValue)"),
                               selected: location == option) {
                        location = option
                    }
                }
            }
        }
    }

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            filterLabel(L10n.t("games.dateideas.budget"))
            HStack(spacing: 8) {
                filterChip(label: L10n.t("games.dateideas.budget.any"),
                           selected: maxBudget == nil) {
                    maxBudget = nil
                }
                ForEach(0...3, id: \.self) { level in
                    filterChip(label: budgetLabel(level), selected: maxBudget == level) {
                        maxBudget = level
                    }
                }
            }
        }
    }

    private func budgetLabel(_ level: Int) -> String {
        level == 0 ? L10n.t("games.dateideas.budget.free") : String(repeating: "€", count: level)
    }

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            filterLabel(L10n.t("games.dateideas.mood"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                ForEach(Self.moodTags, id: \.self) { tag in
                    filterChip(label: L10n.t("games.dateideas.tag.\(tag)"),
                               selected: selectedTags.contains(tag)) {
                        toggleTag(tag)
                    }
                }
            }
        }
    }

    private func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    private var longDistanceToggle: some View {
        Toggle(isOn: $longDistance) {
            HStack(spacing: 8) {
                Image(systemName: "globe.europe.africa.fill")
                    .foregroundStyle(Licht.lampengold)
                    .accessibilityHidden(true)
                Text(L10n.t("games.dateideas.longdistance"))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Papier.aufNacht)
            }
        }
        .tint(coupleTint.blend)
        .onChange(of: longDistance) { _, _ in
            Haptics.shared.tap()
        }
    }

    private func filterLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundStyle(Nacht.tertiaer)
            .textCase(.uppercase)
    }

    private func filterChip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.shared.tap()
        } label: {
            Text(label)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Papier.aufNacht)
                .padding(.vertical, 7)
                .padding(.horizontal, LayoutMetrics.s(12))
                .background(
                    Capsule().fill(selected ? coupleTint.blend.opacity(0.16) : Papier.nachtInnenFill)
                )
                .overlay(
                    Capsule().strokeBorder(selected ? coupleTint.blend : Nacht.naht,
                                           lineWidth: selected ? 1.2 : Theme.hairlineWidth)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Result area

    @ViewBuilder
    private var resultArea: some View {
        if pool.isEmpty {
            EmptyStateView(systemImage: "magnifyingglass",
                           title: L10n.t("games.dateideas.empty.title"),
                           subtitle: L10n.t("games.dateideas.empty.body"),
                           actionTitle: L10n.t("games.dateideas.empty.action"),
                           action: {
                               Haptics.shared.tap()
                               withAnimation(Theme.Motion.settle) {
                                   location = .any
                                   maxBudget = nil
                                   longDistance = false
                                   selectedTags = []
                               }
                           })
                .nightCard(padding: .compact, grain: false)
        } else if spinning {
            spinCard
        } else if let idea {
            resultCard(idea)
        } else {
            idleCard
        }
    }

    private var idleCard: some View {
        VStack(spacing: LayoutMetrics.s(12)) {
            Image(systemName: "wand.and.stars")
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(coupleTint.tinte)
                .accessibilityHidden(true)
            Text(L10n.t("games.dateideas.idle.title"))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Tinte.dunkel)
                .multilineTextAlignment(.center)
            Text(L10n.t("games.dateideas.idle.body"))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Tinte.sekundaer)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: LayoutMetrics.s(200))
        .paperCard(padding: .hero)
    }

    private var spinCard: some View {
        VStack(spacing: LayoutMetrics.s(12)) {
            Text(spinIdea?.emoji ?? "✨")
                .font(.system(.largeTitle, design: .rounded))
                .id(spinIdea?.id ?? -1)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            Text(spinIdea?.title.resolved(L10n.lang) ?? "…")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Tinte.sekundaer)
                .multilineTextAlignment(.center)
                .blur(radius: 1.5)
        }
        .frame(maxWidth: .infinity, minHeight: LayoutMetrics.s(200))
        .paperCard(padding: .hero)
        .animation(Theme.Motion.settle, value: spinIdea?.id)
    }

    private func resultCard(_ idea: DateIdea) -> some View {
        VStack(spacing: LayoutMetrics.s(14)) {
            // The rolled idea sits in a warm pool of lamplight on the paper.
            Text(idea.emoji)
                .font(.system(.largeTitle, design: .rounded))
                .shadow(color: Licht.lampengold.opacity(0.6), radius: 18)
                .accessibilityHidden(true)
            Text(idea.title.resolved(L10n.lang))
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(Tinte.dunkel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(idea.details.resolved(L10n.lang))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Tinte.sekundaer)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ideaPills(idea)
            bucketButton(idea)
            shareButton(idea)
        }
        .frame(maxWidth: .infinity)
        .paperCard(padding: .hero)
        .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
    }

    private func ideaPills(_ idea: DateIdea) -> some View {
        HStack(spacing: 6) {
            PaperTag(text: L10n.t(idea.indoor
                                  ? "games.dateideas.location.indoor"
                                  : "games.dateideas.location.outdoor"),
                     ink: Tinte.sekundaer)
            PaperTag(text: budgetLabel(idea.budget), ink: Wachs.rot)
            if let firstTag = idea.tags.first {
                PaperTag(text: L10n.t("games.dateideas.tag.\(firstTag)"),
                         ink: Tinte.sekundaer)
            }
        }
    }

    private func bucketButton(_ idea: DateIdea) -> some View {
        let added = addedIdeaIds.contains(idea.id)
        return Button {
            addToBucket(idea)
        } label: {
            Label(L10n.t(added ? "games.dateideas.bucketDone" : "games.dateideas.bucket"),
                  systemImage: added ? "checkmark" : "sparkles")
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(added || addingToBucket || appState.api == nil)
        .opacity(added ? 0.6 : 1)
    }

    /// Posts the rolled idea into the couple chat.
    @ViewBuilder
    private func shareButton(_ idea: DateIdea) -> some View {
        if appState.api != nil {
            let shared = sharedIdeaIds.contains(idea.id)
            Button {
                shareToChat(idea)
            } label: {
                if sharingIdea {
                    ProgressView()
                        .tint(coupleTint.tinte)
                } else {
                    Label(L10n.t(shared ? "games.sharedToChat" : "games.shareToChat"),
                          systemImage: shared ? "checkmark" : "paperplane.fill")
                        .font(.system(.footnote, design: .rounded).weight(.bold))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(shared ? Tinte.sekundaer : coupleTint.tinte)
            .disabled(sharingIdea || shared)
        }
    }

    private func shareToChat(_ idea: DateIdea) {
        guard let api = appState.api, !sharingIdea,
              !sharedIdeaIds.contains(idea.id) else { return }
        sharingIdea = true
        Haptics.shared.tap()
        let text = L10n.t("games.dateideas.shareHeader")
            + "\n\(idea.emoji) \(idea.title.resolved(L10n.lang))"
            + "\n" + idea.details.resolved(L10n.lang)
        Task {
            do {
                try await api.sendMessage(type: .text, text: text)
                sharedIdeaIds.insert(idea.id)
                SoundEngine.shared.play(.pop)
                Haptics.shared.success()
                appState.showToast(L10n.t("games.sharedToChat"), style: .success)
            } catch {
                appState.handleAPIError(error)
            }
            sharingIdea = false
        }
    }

    // MARK: Generate

    private var generateButtons: some View {
        Button {
            generate()
        } label: {
            Label(L10n.t(idea == nil
                         ? "games.dateideas.generate"
                         : "games.dateideas.regenerate"),
                  systemImage: "dice.fill")
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(spinning || pool.isEmpty)
    }

    private func generate() {
        guard !spinning else { return }
        let choices = pool
        guard let fallback = choices.randomElement() else { return }
        var final = fallback
        if choices.count > 1, let current = idea,
           let other = choices.filter({ $0.id != current.id }).randomElement() {
            final = other
        }
        spinning = true
        SoundEngine.shared.play(.whoosh)
        Task {
            // Reduce Motion: no slot-machine flicker — the idea lands at once.
            if !reduceMotion {
                let steps = 11
                for step in 0..<steps {
                    withAnimation(Theme.Motion.settle) {
                        spinIdea = choices.randomElement()
                    }
                    if step % 3 == 0 {
                        SoundEngine.shared.play(.pop)
                    }
                    Haptics.shared.tap()
                    let slowdown = UInt64(step * step) * 3_200_000
                    try? await Task.sleep(nanoseconds: 55_000_000 + slowdown)
                }
            }
            spinIdea = nil
            spinning = false
            withAnimation(reduceMotion ? nil : Theme.Motion.playful) {
                idea = final
            }
            SoundEngine.shared.play(.tada)
            Haptics.shared.success()
            GamesA11y.announce(L10n.t("games.dateideas.a11y.result",
                                      ["title": final.title.resolved(L10n.lang)]))
        }
    }

    // MARK: Bucket list

    private func addToBucket(_ idea: DateIdea) {
        guard let api = appState.api, !addingToBucket else { return }
        addingToBucket = true
        Task {
            do {
                _ = try await api.addBucketItem(text: idea.title.resolved(L10n.lang),
                                                emoji: idea.emoji)
                addedIdeaIds.insert(idea.id)
                appState.showToast(L10n.t("games.dateideas.bucketAdded"), style: .success)
                SoundEngine.shared.play(.sparkle)
                Haptics.shared.success()
            } catch {
                appState.handleAPIError(error)
            }
            addingToBucket = false
        }
    }
}
