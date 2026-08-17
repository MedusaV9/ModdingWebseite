import SwiftUI
import Combine

// W8C board & duel games — the shared SwiftUI scaffolding all six new
// board views (Dame, Reversi, Käsekästchen, Gomoku, Mancala, Memory-Duo)
// build on. The pure rules live in Content/BoardGameRules.swift (tested on
// Linux); this file only owns the shared chrome: screen state switching,
// the turn banner, the piece legend, setup/end panels and the wide game
// table arrangement. Pieces are drawn in each MEMBER's OWN avatar color —
// the couple's colors carry the board, not a stock palette.

// MARK: - Shared naming helpers

enum BoardDuel {
    /// Spoken/board name of a square — column letter + row number ("A1").
    /// Row 0 is the CREATOR's back row, same as the server index contract.
    static func squareName(_ index: Int, size: Int) -> String {
        let letter = Character(UnicodeScalar(UInt8(65 + index % size)))
        return "\(letter)\(index / size + 1)"
    }
}

/// Deterministic face → motif mapping for Memory-Duo: SF-Symbol motifs on
/// token tints instead of an emoji wallpaper. Both clients map the same
/// face value to the same motif — the mapping IS the card art. On the
/// paper cards the motifs are STAMPED in the four paper-safe inks
/// (Tinte plus the wax red, all ≥4.5:1 on the text papers — pinned in
/// PaperRulesTests); the night accents of the glass era are gone.
enum MemoryMotifs {
    static let symbols: [String] = [
        "heart.fill", "star.fill", "moon.fill", "sun.max.fill",
        "cloud.fill", "bolt.fill", "leaf.fill", "flame.fill",
        "drop.fill", "snowflake", "sparkles", "music.note",
        "gift.fill", "key.fill", "bell.fill", "crown.fill",
        "pawprint.fill", "airplane",
    ]
    static let tints: [Color] = [Tinte.dunkel, Wachs.rot, Tinte.sekundaer, Tinte.tertiaer]

    static func symbol(for face: Int) -> String {
        symbols[abs(face) % symbols.count]
    }

    static func tint(for face: Int) -> Color {
        tints[abs(face) % tints.count]
    }
}

// MARK: - Roster (who is who, whose color is whose)

/// Derived member context every board view needs: ids, display names and
/// each member's OWN avatar color for their pieces.
@MainActor
struct DuelRoster {
    let myId: String
    let starterId: String
    let otherId: String
    private let colors: [String: String]
    private let myName: String
    private let partnerName: String

    init(appState: AppState, session: GameSession?) {
        myId = appState.memberId ?? ""
        starterId = session?.createdBy ?? ""
        let members = appState.couple?.members ?? []
        otherId = members.map(\.id).first { $0 != session?.createdBy } ?? ""
        colors = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.color) })
        myName = appState.me?.name ?? L10n.t("common.you")
        partnerName = appState.partnerName
    }

    func name(of memberId: String) -> String {
        memberId == myId ? myName : partnerName
    }

    /// The member's own avatar color — the piece color on NIGHT surfaces
    /// (end panels, night legends). Never place this on paper: light
    /// member colors (mint, gold, sky) vanish there — use `ink(of:)`.
    func color(of memberId: String) -> Color {
        colors[memberId].map { Color(hex: $0) } ?? Theme.gold
    }

    /// The member's color as INK on the paper game plan: the same
    /// `inkOnPaper` ladder behind `coupleTint.tinte*` (≥4.5:1 on every
    /// paper tone, pinned matrix) — light member colors darken until they
    /// read, dark ones pass through. One member = one ink on any Zettel.
    func ink(of memberId: String) -> Color {
        colors[memberId].map { Color(hex: CouplePaletteRules.inkOnPaper($0)) }
            ?? Tinte.dunkel
    }
}

// MARK: - Screen scaffold (partner check → lobby → setup/play/end)

/// The shared state machine wrapper of one board-game screen. Mirrors the
/// established session-view pattern (ConnectFourView & friends) so all six
/// W8C boards behave identically: partner required, lobby via
/// `GameLobbyView`, forfeit toolbar, socket forwarding and resume-on-open.
struct BoardDuelScreen<Setup: View, Play: View, End: View>: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    let engine: GameEngine
    let kind: GameKind
    /// True once the reduced state (or the server result) says the match
    /// is decided — flips the screen to the end panel.
    let finished: Bool
    @ViewBuilder let setup: () -> Setup
    @ViewBuilder let play: () -> Play
    @ViewBuilder let end: () -> End

    @State private var tutorial: GameTutorial?

    var body: some View {
        ZStack {
            DreamyBackground()
            content
        }
        .navigationTitle(L10n.t("games.card.\(kind.rawValue).title"))
        .navigationBarTitleDisplayMode(.inline)
        .gameForfeitToolbar(engine: engine)
        .toolbar {
            // The ?-help right AT the table: the three-step intro as a
            // sheet, no detour through the hub's tutorial library.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // Immediate quiet feedback in the tap frame (F6) — the
                    // sheet arrival alone left the tap feeling dead.
                    AppCue.click.play()
                    tutorial = GameTutorialCatalog.intro(for: kind.rawValue)
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel(L10n.t("games.tutorial.open"))
            }
        }
        .sheet(item: $tutorial) { GameTutorialView(tutorial: $0) }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            if let event = note.object as? ServerEvent {
                engine.handle(event)
            }
        }
        .task {
            engine.onError = { [weak appState] error in
                appState?.handleAPIError(error)
            }
            if engine.session == nil {
                await engine.resume(api: appState.api)
            }
        }
    }

    private var session: GameSession? {
        guard let current = engine.session, current.kind == kind else { return nil }
        return current
    }

    @ViewBuilder
    private var content: some View {
        if appState.partner == nil {
            GameNeedsPartnerView()
        } else if let session {
            if session.state == "lobby" {
                ScrollView {
                    GameLobbyView(engine: engine, accent: coupleTint.blend)
                        .padding(Space.l)
                }
            } else if finished || session.state == "ended" {
                end()
            } else if session.state == "active" {
                play()
            } else {
                setup()
            }
        } else {
            setup()
        }
    }
}

// MARK: - Setup panel

/// Shared setup card: SF-Symbol motif, teaser, rules and the start button,
/// with room for per-game option pickers (Käsekästchen size, Mancala stones).
struct BoardDuelSetupCard<Options: View>: View {
    @Environment(\.coupleTint) private var coupleTint

    let symbol: String
    let kind: GameKind
    let bodyKey: String
    let busy: Bool
    let start: () -> Void
    @ViewBuilder let options: () -> Options

    var body: some View {
        ScrollView {
            VStack(spacing: Space.l) {
                Image(systemName: symbol)
                    .font(Typo.hero)
                    .symbolRenderingMode(.hierarchical)
                    // Identity as non-text accent on the night card —
                    // blend, never the paper ink (drowns on dark).
                    .foregroundStyle(coupleTint.blend)
                    .accessibilityHidden(true)
                Text(L10n.t("games.card.\(kind.rawValue).teaser"))
                    .font(Typo.title)
                    .foregroundStyle(Papier.aufNacht)
                    .multilineTextAlignment(.center)
                Text(L10n.t(bodyKey))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                options()
                Button {
                    // Quiet tap-frame feedback — the round starts only
                    // after the server round-trip (F6).
                    AppCue.click.play()
                    start()
                } label: {
                    Text(L10n.t("games.start"))
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy)
            }
            .nightCard(padding: .hero)
            .padding(Space.l)
            .contentColumn(.reading)
        }
    }
}

extension BoardDuelSetupCard where Options == EmptyView {
    init(symbol: String, kind: GameKind, bodyKey: String, busy: Bool,
         start: @escaping () -> Void) {
        self.init(symbol: symbol, kind: kind, bodyKey: bodyKey, busy: busy,
                  start: start, options: { EmptyView() })
    }
}

// MARK: - Play layout (game table on wide panes, stacked on phones)

/// Header + board + footer, arranged as a real game table on wide regular
/// panes (board centered, header/footer in the side rail) and stacked on
/// phones — the roadmap-22 pattern shared by all six boards.
struct BoardDuelPlayLayout<Header: View, Board: View, Footer: View>: View {
    let gameType: String
    @ViewBuilder let header: () -> Header
    @ViewBuilder let board: () -> Board
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        GameTableContainer(gameType: gameType) { paneWidth in
            GameTableLayout(gameType: gameType, paneWidth: paneWidth) {
                board()
                    .gameActGated()
            } rail: {
                VStack(spacing: Space.m) {
                    header()
                    footer()
                }
                .gameActGated()
            }
        } stacked: {
            ScrollView {
                VStack(spacing: Space.m) {
                    header()
                    board()
                    footer()
                }
                .gameActGated()
                .padding(Space.l)
            }
        }
    }
}

// MARK: - Board keyboard control (hardware keyboards, HIG)

/// One cursor slot on a board lattice — column/row in VISUAL order (what
/// the player sees, not the server index; flipped boards translate in
/// their `activate` closure).
struct BoardKeySlot: Equatable {
    var column: Int
    var row: Int
}

/// Geometry + activation contract one board hands the shared keyboard
/// cursor: lattice dimensions, which slots exist, where a slot sits inside
/// the modified view, and what Space/Return on a slot means. The engine
/// (`boardKeyCursor`) is central — each board only declares its lattice.
/// MainActor like the views that build it: the closures route straight
/// into view state (selections, engine sends).
@MainActor
struct BoardKeyLattice {
    let columns: Int
    let rows: Int
    /// False for lattice holes (Käsekästchen dots/boxes) — arrow movement
    /// steps over holes and stops at the lattice edge.
    var contains: (Int, Int) -> Bool = { _, _ in true }
    /// Frame of slot (column, row) in the coordinate space of the view the
    /// cursor modifier is attached to.
    let frame: (Int, Int, CGSize) -> CGRect
    /// Space/Return on the cursor slot — routes into the game's OWN tap
    /// path, so every turn/legality guard keeps working unchanged.
    let activate: (Int, Int) -> Void
    /// Esc — the engine clears the cursor; boards with in-flight
    /// selections (Dame jump chains) clear those here too.
    var escape: () -> Void = {}
}

extension BoardKeyLattice {
    /// Uniform-cell grid (Dame, Reversi, Gomoku, Memory-Duo, Mancala's own
    /// pit row): frame math derived purely from the counts and the grid's
    /// inter-cell spacing. `contains` guards lattice holes (Memory-Duo's
    /// possible partial last row).
    static func grid(columns: Int, rows: Int, spacing: CGFloat,
                     contains: @escaping (Int, Int) -> Bool = { _, _ in true },
                     activate: @escaping (Int, Int) -> Void,
                     escape: @escaping () -> Void = {}) -> BoardKeyLattice {
        BoardKeyLattice(
            columns: columns, rows: rows,
            contains: contains,
            frame: { column, row, size in
                let cellWidth = (size.width - CGFloat(columns - 1) * spacing)
                    / CGFloat(columns)
                let cellHeight = (size.height - CGFloat(rows - 1) * spacing)
                    / CGFloat(rows)
                return CGRect(x: CGFloat(column) * (cellWidth + spacing),
                              y: CGFloat(row) * (cellHeight + spacing),
                              width: cellWidth, height: cellHeight)
            },
            activate: activate, escape: escape)
    }

    /// Käsekästchen's alternating edge lattice: even rows hold the `size`
    /// horizontal edges of one dot row, odd rows the `size + 1` vertical
    /// edges of one box row. `dot` is the board's fixed dot diameter —
    /// the same constant that drives the view's row heights.
    static func kaeseEdges(size: Int, dot: CGFloat,
                           activate: @escaping (Int, Int) -> Void) -> BoardKeyLattice {
        BoardKeyLattice(
            columns: size + 1,
            rows: 2 * size + 1,
            contains: { column, row in
                row.isMultiple(of: 2) ? column < size : true
            },
            frame: { column, row, boardSize in
                let box = (boardSize.width - CGFloat(size + 1) * dot) / CGFloat(size)
                if row.isMultiple(of: 2) {
                    // Horizontal edge `column` in dot row `row / 2`.
                    return CGRect(x: dot + CGFloat(column) * (dot + box),
                                  y: CGFloat(row / 2) * (dot + box),
                                  width: box, height: dot)
                }
                // Vertical edge `column` in box row `(row - 1) / 2`.
                return CGRect(x: CGFloat(column) * (dot + box),
                              y: dot + CGFloat((row - 1) / 2) * (box + dot),
                              width: dot, height: box)
            },
            activate: activate)
    }
}

/// Central board keyboard control (iOS 17 focus APIs): Tab (hardware
/// keyboard focus) reaches the board, arrow keys move a visible cursor
/// slot by slot, Space/Return activates the slot through the game's own
/// tap path, Esc clears cursor + selection. Cells keep their existing
/// accessibility labels — the cursor ring is purely visual chrome and
/// invisible to VoiceOver.
private struct BoardKeyCursorModifier: ViewModifier {
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let lattice: BoardKeyLattice

    @FocusState private var focused: Bool
    /// Cursor slot — appears with the first arrow key while focused.
    @State private var cursor: BoardKeySlot?

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    if let cursor, focused {
                        let rect = lattice.frame(cursor.column, cursor.row, geo.size)
                        RoundedRectangle(cornerRadius: Radius.concentric(
                            parent: Radius.control, padding: Space.xs),
                            style: .continuous)
                            // The cursor ring rides on the PAPER game plan
                            // now — the couple ink stays visible there,
                            // the raw blend (mint/gold) would not.
                            .strokeBorder(coupleTint.tinte, lineWidth: 3)
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                            .animation(reduceMotion ? nil : Theme.Motion.settle,
                                       value: cursor)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .focusable()
            .focused($focused)
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                move(press.key)
                return .handled
            }
            .onKeyPress(keys: [.space, .return]) { _ in
                guard let cursor else { return .ignored }
                lattice.activate(cursor.column, cursor.row)
                return .handled
            }
            .onKeyPress(.escape) {
                guard cursor != nil else { return .ignored }
                cursor = nil
                lattice.escape()
                return .handled
            }
            .onChange(of: focused) {
                // Focus moving on takes the cursor along — a stale ring on
                // an unfocused board would promise keys that go elsewhere.
                if !focused { cursor = nil }
            }
    }

    private func move(_ key: KeyEquivalent) {
        guard var slot = cursor else {
            // First arrow press: the cursor enters at the top-leading slot.
            cursor = firstSlot()
            return
        }
        let step: (columns: Int, rows: Int)
        switch key {
        case .leftArrow: step = (-1, 0)
        case .rightArrow: step = (1, 0)
        case .upArrow: step = (0, -1)
        case .downArrow: step = (0, 1)
        default: return
        }
        // Step in the pressed direction until a real slot appears; the
        // lattice edge simply stops the cursor (no wrap-around surprises).
        repeat {
            slot = BoardKeySlot(column: slot.column + step.columns,
                                row: slot.row + step.rows)
            guard (0..<lattice.columns).contains(slot.column),
                  (0..<lattice.rows).contains(slot.row) else { return }
        } while !lattice.contains(slot.column, slot.row)
        cursor = slot
    }

    private func firstSlot() -> BoardKeySlot? {
        for row in 0..<lattice.rows {
            for column in 0..<lattice.columns where lattice.contains(column, row) {
                return BoardKeySlot(column: column, row: row)
            }
        }
        return nil
    }
}

extension View {
    /// Attach directly to the board's raw grid (BEFORE its padding), so the
    /// lattice frame math sees exactly the cell geometry.
    func boardKeyCursor(_ lattice: BoardKeyLattice) -> some View {
        modifier(BoardKeyCursorModifier(lattice: lattice))
    }
}

// MARK: - Turn banner + legend

/// The piece dot of the night chrome: the mover's PAPER ink (the exact
/// piece color on the light board) lying on a tiny brief-paper disc —
/// so the dark banner still names the piece the player sees on the
/// bright game plan. Never the raw member color (light couple colors
/// stay board-illegible), never the bare ink (dark ink drowns on the
/// night card). Shared by every board's turn/legend chrome.
struct BoardPieceDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(Papier.brief)
            .frame(width: Space.l, height: Space.l)
            .overlay(Circle().fill(color).padding(3))
            .overlay(Circle().strokeBorder(Nacht.naht,
                                           lineWidth: Theme.hairlineWidth))
    }
}

/// "Du bist dran." / "{name} überlegt…" — a night Zettel with the mover's
/// piece dot (pass `DuelRoster.ink(of:)`, never the raw member color:
/// the dot mirrors the piece on the paper board).
struct BoardTurnBanner: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: Space.m) {
            BoardPieceDot(color: color)
            Text(text)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(Papier.aufNacht)
            Spacer(minLength: 0)
        }
        .nightCard(grain: false)
    }
}

/// Which piece ink belongs to whom (plus an optional live score line) —
/// a night Zettel under the bright board.
struct BoardColorLegend: View {
    struct Entry: Identifiable {
        let id: String
        let color: Color
        let label: String
        let value: String?
    }

    let entries: [Entry]

    var body: some View {
        HStack(spacing: Space.l) {
            ForEach(entries) { entry in
                HStack(spacing: Space.s) {
                    BoardPieceDot(color: entry.color)
                    Text(entry.label)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Nacht.sekundaer)
                    if let value = entry.value {
                        Text(value)
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Papier.aufNacht)
                    }
                }
                if entry.id != entries.last?.id {
                    Spacer(minLength: 0)
                }
            }
        }
        .nightCard(padding: .compact, grain: false)
    }
}

// MARK: - End panel

/// The static lamp glow behind a verdict symbol on the dark end panel —
/// the resting state of the Lichtschein signature (same tokens, no new
/// numbers): the lamp leans over the couple's finished match. Purely
/// decorative, never hit-testable.
struct VerdictLampenschein: View {
    var body: some View {
        GeometryReader { geo in
            let radius = max(geo.size.width, geo.size.height)
                * Theme.Motion.Signature.lichtscheinRadiusFactor
            Circle()
                .fill(RadialGradient(
                    colors: [Licht.lampengold.opacity(
                        Theme.Motion.Signature.lichtscheinRestOpacity), .clear],
                    center: .center, startRadius: 0, endRadius: radius))
                .frame(width: radius * 2, height: radius * 2)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Shared end screen, nacht-first: ONE focused dark panel — verdict line
/// in the lamp's resting glow, the final bright board still on the table
/// for one last look, and the rematch button. The celebration itself runs
/// through `GameEndCelebration` from the game view (budgeted — no new
/// excess).
struct BoardDuelEndPanel<Board: View>: View {
    @Environment(\.coupleTint) private var coupleTint

    let symbol: String
    let headline: String
    let detail: String?
    let busy: Bool
    let rematch: () -> Void
    @ViewBuilder let board: () -> Board

    var body: some View {
        ScrollView {
            VStack(spacing: Space.l) {
                Image(systemName: symbol)
                    .font(Typo.hero)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(coupleTint.blend)
                    .background(VerdictLampenschein())
                    .accessibilityHidden(true)
                Text(headline)
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Papier.aufNacht)
                    .multilineTextAlignment(.center)
                if let detail {
                    Text(detail)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Nacht.sekundaer)
                }
                board()
                Button {
                    AppCue.click.play()
                    rematch()
                } label: {
                    Text(L10n.t("games.rematch"))
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy)
            }
            .frame(maxWidth: .infinity)
            .nightCard(padding: .hero)
            .padding(Space.l)
            .contentColumn(.reading)
        }
    }
}
