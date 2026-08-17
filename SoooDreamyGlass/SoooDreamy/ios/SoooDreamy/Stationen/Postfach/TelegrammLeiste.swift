import SwiftUI

// Die Telegramm-Leiste — der „Schick Liebe"-Block des Postfachs als
// kompakte SF-Symbol-Leiste in Paar-Tinten (Re-Eval №6): das alte
// 2×4-Emoji-Kachelraster war ein Charta-Verstoß (Gebot 1 — Emojis sind
// Content, nie Chrome-Icons). Fix2-A №5 macht daraus eine echte LEISTE:
// die Telegramm-Arten sind enge KAPSEL-CHIPS (Glyphe NEBEN der
// Beschriftung, flache 44-pt-Zeilenhöhe) in zwei dichten Reihen —
// horizontale Reihen-Anmutung statt Kachel-Dashboard. Jede Touch-Art
// bleibt erreichbar (Kuss, Umarmung, Vermissen, Kitzeln, Denk-an-dich,
// Stolz, Halt-durch — das Herzklopfen wohnt weiter allein auf dem
// 3D-Herz), die Post-Station (Zeitpost/Verlauf) und die Studio-Zeilen
// ziehen unverändert mit; alle A11y-Labels und Test-IDs (`home.touch.*`,
// `home.station.*`) bleiben wörtlich bestehen.

struct TelegrammLeiste: View {
    @Environment(AppState.self) private var appState
    /// AX5: die Leiste kollabiert (4 → 2 → 1 Spalten) bevor die
    /// Beschriftungen zersplittern — Regel `AccessibilityBudget.gridColumns`.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showHapticStudio = false
    @State private var showDuet = false
    @State private var showZeitpost = false
    @State private var showJournal = false

    /// Die sichtbaren Telegramm-Arten — das Herzklopfen sendet NUR das
    /// 3D-Herz (eine Geste, eine Bedeutung; Dossier 23, Idee 26).
    private var arten: [TouchKind] {
        TouchKind.allCases.filter { $0 != .heartbeat }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader(title: L10n.t("home.sendLove"), systemImage: Icon.sendLove.rawValue)

            // Die Leiste: zwei dichte Reihen enger Chips (Fix2-A №5) —
            // Glyphe in der Paar-Tinte NEBEN der Beschriftung in
            // Nacht-Tinte, Papier-&-Licht-Ton. AX kollabiert wie gehabt
            // über `AccessibilityBudget.gridColumns` bis zur einen Spalte.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s),
                                     count: dynamicTypeSize.gridColumns(regular: 4)),
                      spacing: Space.s) {
                ForEach(arten) { kind in
                    TelegrammKnopf(kind: kind) {
                        appState.sendTouch(kind)
                    }
                    .accessibilityIdentifier("home.touch.\(kind.rawValue)")
                }
            }

            // Die Post-Station: eine Hairline-Naht setzt die Schalter-
            // Zeile von den Telegramm-Schaltern ab — Zeitpost und Verlauf
            // sind Schalter eines Dienstes, keine Berührungen.
            VStack(spacing: Space.s) {
                Rectangle()
                    .fill(Nacht.naht)
                    .frame(height: Theme.hairlineWidth)
                    .accessibilityHidden(true)
                stationRow
            }
            .padding(.top, Space.xs)

            // Composer für eigene Vibrationsmuster
            studioRow(icon: "slider.vertical.3",
                      title: L10n.t("home.hapticStudio"),
                      subtitle: L10n.t("home.hapticStudio.hint")) {
                showHapticStudio = true
            }

            // Synchronisiertes Haptik-Duett + Live-Herzschlag
            studioRow(icon: Icon.heartbeat.rawValue,
                      title: L10n.t("duet.title"),
                      subtitle: L10n.t("duet.subtitle")) {
                showDuet = true
            }
        }
        .nightCard()
        .sheet(isPresented: $showHapticStudio) {
            HapticStudioView()
        }
        .sheet(isPresented: $showDuet) {
            DuetSheet()
        }
        .sheet(isPresented: $showZeitpost) {
            ZeitpostSheet()
        }
        .sheet(isPresented: $showJournal) {
            PostJournalSheet()
        }
    }

    /// Die zwei Post-Station-Schalter nebeneinander; bei AX-Größen
    /// stapelt die Zeile (AX5-Gate), statt die Labels zu zersplittern.
    @ViewBuilder
    private var stationRow: some View {
        let layout = dynamicTypeSize.prefersVerticalLayout
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        layout {
            StationTile(systemImage: "hourglass",
                        title: L10n.t("post.station.zeitpost"),
                        a11yLabel: L10n.t("post.station.zeitpostA11y")) {
                showZeitpost = true
            }
            .accessibilityIdentifier("home.station.zeitpost")
            StationTile(systemImage: "tray.full",
                        title: L10n.t("post.station.journal"),
                        a11yLabel: L10n.t("post.station.journalA11y")) {
                showJournal = true
            }
            .accessibilityIdentifier("home.station.journal")
        }
    }

    /// Eine leise matte Zeile pro Studio-Ziel — Hairline statt des alten
    /// doppelt umrandeten Kastenstapels (DESIGN.md, Karten-Rhythmus).
    private func studioRow(icon: String, title: String, subtitle: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: LayoutMetrics.s(10)) {
                Image(systemName: icon)
                    .font(.system(.title3).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Licht.lampengold)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(Papier.aufNacht)
                    Text(subtitle)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Nacht.tertiaer)
                        // AX-Größen: erklärende Zeilen wickeln, statt auf
                        // eine Zeile amputiert zu werden.
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(Nacht.tertiaer)
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
        .buttonStyle(.plain)
    }
}

// MARK: - Telegramm-Knopf

/// Ein Telegramm-Chip der Leiste (Fix2-A №5): SF-Symbol-Glyphe in der
/// Paar-Tinte NEBEN der Klartext-Beschriftung in einer flachen Kapsel —
/// Chip-Anatomie statt Kachel (Icons antworten auf Tint und Gewicht,
/// Gebot 1); die Emoji-SIGNATUREN bleiben Content der Zustellung selbst
/// (Overlay/Chat), nie Chrome dieser Leiste.
struct TelegrammKnopf: View {
    let kind: TouchKind
    let action: () -> Void

    @Environment(\.coupleTint) private var coupleTint
    /// AX-Größen: die Beschriftung wickelt in natürlicher Größe, statt
    /// herunterskaliert zu werden — die Leiste hat oben schon Spalten
    /// abgegeben (gridColumns).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Fix3 №5: der Druck-Pop ist Transform-Motion und respektiert das
    /// System-Gate (ChatPult-Muster) — das Farb-Feedback bleibt.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false
    /// Press-Reset GEBUNDEN an den Chip (Lasche-Muster, `UmschlagKarte`):
    /// im @State gehalten, beim nächsten Druck und beim Verschwinden
    /// abgebrochen — eine recycelte Grid-Zelle behält nie einen
    /// Geister-Task, der einen fremden Chip zurücksetzt.
    @State private var resetTask: Task<Void, Never>?

    /// Die Symbol-Stimme jeder Touch-Art — Chrome-Glyphen in Paar-Tinte,
    /// semantisch nah an der gesendeten Signatur.
    private var symbol: String {
        switch kind {
        case .heartbeat: return Icon.heartbeat.rawValue
        case .kiss: return "mouth.fill"
        case .hug: return Icon.hug.rawValue
        case .missyou: return "moon.stars.fill"
        case .tickle: return "hands.sparkles.fill"
        case .thinking: return "ellipsis.bubble.fill"
        case .stolz: return "star.fill"
        case .halteDurch: return "bolt.heart.fill"
        }
    }

    /// Kurztitel der LEISTE (Fix3 №4): die engen 4-Spalten-Chips tragen
    /// kurze Formen aus PostfachL10n, wo die vollen touch.*-Titel schon
    /// bei Regulärgröße ellipsierten („Umarm…", „Vermiss…", „Stolz a…");
    /// Kuss, Kitzeln und Denk an dich brauchen keine Kurzform (Denk an
    /// dich bricht als zwei kurze Wörter sauber um). VoiceOver spricht
    /// weiter den vollen Titel (accessibilityLabel unten).
    private var chipTitleKey: String {
        switch kind {
        case .hug: return "postfach.leiste.hug"
        case .missyou: return "postfach.leiste.missyou"
        case .stolz: return "postfach.leiste.stolz"
        case .halteDurch: return "postfach.leiste.haltedurch"
        default: return kind.titleKey
        }
    }

    var body: some View {
        Button {
            // Fix3 №5 (RM-Gate, ChatPult-Muster): unter Reduce Motion
            // schaltet der Zustand sofort — der Kapsel-Farbblitz bleibt
            // als Feedback, der Scale-Pop entfällt (unten mitgegated).
            withAnimation(reduceMotion ? nil : Theme.Motion.playful) { pressed = true }
            action()
            resetTask?.cancel()
            resetTask = Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : Theme.Motion.settle) { pressed = false }
            }
        } label: {
            // Chip-Anatomie (Fix2-A №5): Glyphe NEBEN der Beschriftung,
            // flache Zeile (44-pt-Ziel ohne Extra-Polster) in einer
            // Kapsel — die Leiste liest sich als Reihe, nicht als Raster.
            // Fix3 №4: Hairline-Abstand Glyphe→Label — die gewonnenen
            // Punkte gehören der Beschriftung, die vorher ellipsierte.
            HStack(spacing: Space.xs) {
                Image(systemName: symbol)
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    // Paar-Tinte als Glyphen-Füllung — legaler Nicht-Text-
                    // Einsatz der Paar-Farbe auf der Nachtkarte.
                    .foregroundStyle(coupleTint.blend)
                    .scaleEffect(pressed && !reduceMotion ? 1.25 : 1)
                    .accessibilityHidden(true)
                Text(L10n.t(chipTitleKey))
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(Nacht.sekundaer)
                    // Fix3 №4: statt Ellipse bricht ein längerer Titel auf
                    // eine ZWEITE Zeile (intrinsische Höhe über minHeight);
                    // AX wickelt weiter frei in natürlicher Größe.
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Space.s)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                Capsule(style: .continuous)
                    // Der Druck blitzt in der Paar-Farbe, ruhende Chips
                    // bleiben matt — Feedback in der eigenen Signatur.
                    .fill(pressed ? coupleTint.blend.opacity(0.28) : Papier.nachtInnenFill)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Nacht.naht, lineWidth: Theme.hairlineWidth)
                    )
            )
        }
        .buttonStyle(.plain)
        .onDisappear {
            // Lasche-Muster: das Verschwinden bricht den Reset-Task ab
            // und legt den Chip selbst in den Ruhezustand zurück.
            resetTask?.cancel()
            resetTask = nil
            pressed = false
        }
        .accessibilityLabel(L10n.t(kind.titleKey))
        // Fix4 Befund 8 (Voice Control): der Chip hört auf BEIDE Namen —
        // die sichtbare Kurzform der Leiste UND den vollen Titel, den
        // VoiceOver weiter spricht („Umarmung" wie „Umarmung schicken").
        // SwiftUI-API heißt accessibilityInputLabels (der UIKit-Name
        // accessibilityUserInputLabels existiert hier nicht — CI-Fund).
        .accessibilityInputLabels(
            chipTitleKey == kind.titleKey
                ? [Text(L10n.t(kind.titleKey))]
                : [Text(L10n.t(chipTitleKey)), Text(L10n.t(kind.titleKey))])
        // Ein weicher physischer Tick genau dann, wenn das Telegramm das
        // Telefon verlässt.
        .sensoryFeedback(.impact(flexibility: .soft), trigger: pressed) { _, isDown in isDown }
    }
}
