import SwiftUI
import Combine
import UIKit

/// Shared realtime doodle canvas — both partners draw on the same board.
struct CanvasView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @State private var strokes: [CanvasStroke] = []
    @State private var currentPoints: [[Double]] = []
    @State private var loading = true
    @State private var selectedColor = "#FF5C8A"
    @State private var strokeWidth: Double = 5
    @State private var tool: CanvasTool = .pen
    @State private var confirmClear = false
    @State private var partnerPoint: CGPoint?
    @State private var indicatorTask: Task<Void, Never>?
    @State private var replay: ReplaySession?
    @State private var replayEndTask: Task<Void, Never>?
    @State private var replayCelebration: Date?
    @State private var celebrationTask: Task<Void, Never>?
    /// Last colors actually drawn with (newest first, max 6) — persisted.
    @State private var recentColors: [String] = []
    /// Rendered board bitmap awaiting export (drives the export sheet).
    @State private var exportItem: CanvasExportItem?
    /// Partner's in-progress stroke, streamed via the ephemeral
    /// `canvas_live` relay — drawn on top, never persisted locally.
    @State private var partnerLive: CanvasStroke?
    /// True while the partner has the canvas open (hello/draw frames).
    @State private var partnerOnCanvas = false
    @State private var presenceExpiryTask: Task<Void, Never>?
    /// Periodic "I'm here" announcements while this screen is open.
    @State private var presenceAnnounceTask: Task<Void, Never>?
    /// Throttles outgoing live-draw frames (~12/s).
    @State private var lastLiveSentAt = Date.distantPast
    /// Failed stroke posts wait here and retry — never silently deleted.
    @State private var strokeRetryQueue: [CanvasStroke] = []
    @State private var strokeRetryTask: Task<Void, Never>?
    /// Board generation (contract v11): every stroke POST carries it, so a
    /// board cleared on the other device refuses strokes drawn against the
    /// old picture (`409 stale_generation`). Nil on old servers — strokes
    /// then post without the guard, exactly like before.
    @State private var boardGeneration: Int?
    /// Partner-stroke pop plays at most every 4 s — a drawing session is
    /// ambience, not a notification storm.
    @State private var lastPartnerPopAt = Date.distantPast
    /// Clears a finished live preview if the committed stroke never
    /// arrives (partner offline mid-send).
    @State private var partnerLiveClearTask: Task<Void, Never>?

    // Apple-Pencil state (fed by the passive `PencilProbe`, mapped through
    // `PencilInputRules` — the wire format stays one width per stroke).
    /// Latest raw pencil reading — pressure source for the stroke start.
    @State private var latestPencilSample: PencilSample?
    /// True while any pencil touch rests on the board.
    @State private var pencilOnSurface = false
    /// Whether the stroke currently in flight was started by the pencil.
    @State private var strokeIsPencil = false
    /// Peak-force sample inside the stroke-start window (width lock source).
    @State private var strokeStartSample: PencilSample?
    /// Width of the stroke in flight: the slider width for finger strokes,
    /// pressure-modulated for pencil strokes. Locked after the start window.
    @State private var activeStrokeWidth: Double = 5
    /// The stroke in flight was a resting palm — swallow it silently.
    @State private var palmRejected = false
    /// Points captured in the whole physical stroke — unlike
    /// `currentPoints.count` it survives the 400-point segment split, so
    /// the pressure window can't re-open mid-stroke.
    @State private var strokePointTotal = 0
    /// Pencil-hover / pointer position over the board (board-local points).
    @State private var hoverPoint: CGPoint?

    /// Board background — the shared board IS a sheet of letter paper
    /// (Papier & Licht). The eraser paints in exactly this color, so the
    /// board fill, eraser strokes and the export bitmap stay one tone.
    private static let boardHex = PaperRules.briefHex

    private static let recentColorsKey = "sooodreamy.canvas.recentColors"
    private static let recentColorsMax = 6

    /// Ephemeral live co-drawing frame from the partner.
    private struct CanvasLivePayload: Decodable {
        let memberId: String
        let phase: String
        let color: String?
        let width: Double?
        let tool: String?
        let points: [[Double]]?
    }

    /// Clear attribution — who wiped the shared board.
    private struct CanvasClearPayload: Decodable {
        let by: String?
    }

    /// Immutable snapshot of the stroke list at replay start, so strokes
    /// arriving live during the replay don't glitch the animation.
    /// `background` renders fully from frame one — the auto-replay of new
    /// partner strokes animates only what's actually new.
    private struct ReplaySession {
        let strokes: [CanvasStroke]
        let background: [CanvasStroke]
        let startedAt: Date
        let strokeDuration: Double

        var total: Double { Double(strokes.count) * strokeDuration }
    }

    /// Three pens + eraser — the retired brushes (dotted, calligraphy)
    /// keep rendering via the shared `StrokeRenderer` fallbacks, so old
    /// artwork never changes appearance.
    private enum CanvasTool: String, CaseIterable, Identifiable {
        case pen, marker, glow, eraser
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .pen: return "pencil.tip"
            case .marker: return "highlighter"
            case .glow: return "sparkles"
            case .eraser: return "eraser.fill"
            }
        }

        var titleKey: String { "memories.canvas.tool.\(rawValue)" }
    }

    var body: some View {
        ZStack {
            DreamyBackground(showStars: false)
            // Live-resize safe: the pane width is re-read every layout pass,
            // so dragging a Stage-Manager window across the rail threshold
            // swaps layouts mid-flight instead of sticking to a snapshot.
            GeometryReader { geo in
                if LayoutRules.canvasUsesSideRail(paneWidth: geo.size.width,
                                                  isRegularWidth: horizontalSizeClass == .regular) {
                    wideLayout
                } else {
                    stackedLayout
                }
            }
            if let started = replayCelebration {
                FloatingHeartsView(emojis: ["🎨", "💜", "✨", "💖"], count: 16, startedAt: started)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle(L10n.t("memories.canvas.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    exportBoard()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(strokes.isEmpty || replay != nil ? Theme.textTertiary : coupleTint.blend)
                }
                .disabled(strokes.isEmpty || replay != nil)
                .accessibilityLabel(CanvasExportStrings.t("export.title"))
                Button {
                    startReplay()
                } label: {
                    Image(systemName: "play.circle")
                        .foregroundStyle(strokes.isEmpty || replay != nil ? Theme.textTertiary : coupleTint.blend)
                }
                .disabled(strokes.isEmpty || replay != nil)
                .accessibilityLabel(L10n.t("memories.canvas.replay"))
            }
        }
        .sheet(item: $exportItem) { item in
            CanvasExportSheet(image: item.image)
        }
        .task { await loadStrokes() }
        .onAppear {
            pickInitialColor()
            recentColors = UserDefaults.standard.stringArray(forKey: Self.recentColorsKey) ?? []
            startPresenceAnnouncements()
        }
        .onDisappear {
            // Kill the delayed replay-end/celebration work — otherwise the tada
            // sound + haptic would fire minutes later from another screen.
            replayEndTask?.cancel()
            celebrationTask?.cancel()
            presenceAnnounceTask?.cancel()
            presenceExpiryTask?.cancel()
            strokeRetryTask?.cancel()
            partnerLiveClearTask?.cancel()
            sendLiveFrame(phase: "bye")
            markCanvasSeen()
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            handleServerEvent(event)
        }
        .confirmationDialog(L10n.t("memories.canvas.clearConfirm"),
                            isPresented: $confirmClear, titleVisibility: .visible) {
            // Archive-first is the default (B-11): the artwork lands in the
            // shared gallery BEFORE the board goes blank.
            Button(L10n.t("memories.canvas.archiveClear")) { archiveAndClear() }
            Button(L10n.t("memories.canvas.clearOnly"), role: .destructive) { clearAll() }
            Button(L10n.t("common.cancel"), role: .cancel) {}
        }
    }

    private var subtitle: some View {
        Text(L10n.t("memories.canvas.subtitle"))
            .font(.system(.footnote, design: .rounded).weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
    }

    // MARK: Layout variants

    /// Phone / narrow panes: board on top, tools stacked underneath.
    private var stackedLayout: some View {
        VStack(spacing: Space.l) {
            subtitle
            board
            Group {
                palette
                recentColorsRow
                controls
            }
            .opacity(replay == nil ? 1 : 0.3)
            .disabled(replay != nil)
        }
        .padding(Space.l)
    }

    /// Wide regular panes (roadmap 18): the board gets the full height and
    /// the tools move into a trailing chrome rail — no scrolling past the
    /// canvas to reach a slider.
    private var wideLayout: some View {
        HStack(alignment: .center, spacing: Space.l) {
            VStack(spacing: Space.l) {
                subtitle
                board
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            toolRail
                .opacity(replay == nil ? 1 : 0.3)
                .disabled(replay != nil)
        }
        .padding(Space.l)
    }

    /// All drawing controls as one vertical rail next to the board.
    /// Tools FLOAT above the desk → glass chrome (Zwei-Materialien-Gesetz:
    /// the paper board lies, the toolbox hovers).
    private var toolRail: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            toolPicker
            widthSlider
            paletteGrid
            recentColorsRow
            Spacer(minLength: 0)
            HStack(spacing: Space.m) {
                undoButton
                clearButton
            }
        }
        .frame(maxHeight: .infinity)
        .padding(Space.l)
        .glass(.chrome, in: RoundedRectangle(cornerRadius: Radius.card,
                                             style: .continuous))
        .frame(width: LayoutMetrics.toolRailWidth)
    }

    // MARK: Board

    /// Cut paper is sharper than glass — every board corner shares the
    /// paper radius (fill, clip and hit shape stay congruent).
    private var boardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
    }

    private var board: some View {
        GeometryReader { geo in
            ZStack {
                // The drawing surface is paper: opaque brief fill, grain
                // (skipped under Increased Contrast, like paperCard), the
                // 10-o'clock light edge and the raised elevation — the
                // artwork is the hero of this screen.
                boardShape
                    .fill(Papier.brief)
                    .overlay {
                        if colorSchemeContrast != .increased {
                            PaperGrainView().clipShape(boardShape)
                        }
                    }
                    .overlay(boardShape.strokeBorder(PaperLightEdge.gradient,
                                                     lineWidth: Theme.hairlineWidth))
                    .elevation(.raised)
                strokeCanvas
                    .clipShape(boardShape)
                if loading {
                    BusySpinner(tint: coupleTint.tinte)
                } else if strokes.isEmpty && currentPoints.isEmpty {
                    Text(L10n.t("memories.canvas.empty"))
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(Tinte.tertiaer)
                        .allowsHitTesting(false)
                }
                brushPreview
                partnerIndicator(size: geo.size)
                VStack {
                    partnerPresenceBanner
                    Spacer()
                }
                .padding(Space.m)
                if let session = replay {
                    VStack {
                        Spacer()
                        replayBar(session)
                    }
                    .padding(Space.m)
                }
            }
            .contentShape(boardShape)
            .gesture(drawGesture(size: geo.size))
            // Passive probe next to the drag: reports pencil pressure/tilt,
            // pencil contact and the palm-rejection trigger. Attached via
            // the representable-specific `gesture(_:)` overload — a
            // `UIGestureRecognizerRepresentable` is not a `Gesture`, so
            // `simultaneousGesture` cannot take it. Simultaneity lives on
            // the UIKit side (probe delegate + never-recognizing
            // recognizer), so the draw gesture is untouched.
            .gesture(pencilProbe)
            // Pencil hover (and pointer) — feeds the brush preview.
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let point): hoverPoint = point
                case .ended: hoverPoint = nil
                }
            }
        }
        .aspectRatio(0.75, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    // MARK: Pencil input

    private var pencilProbe: PencilProbe {
        PencilProbe(onSample: { sample in
            latestPencilSample = sample
            refineStrokeStartWidth(with: sample)
        }, onContactChanged: { touching in
            pencilOnSurface = touching
        }, onPencilLanded: {
            rejectPalmStroke()
        })
    }

    /// Pressure refinement inside the stroke-start window: the wire format
    /// carries ONE width per stroke, so the peak press of the first few
    /// points decides, then the width locks for the rest of the stroke.
    private func refineStrokeStartWidth(with sample: PencilSample) {
        guard strokeIsPencil, !palmRejected, !currentPoints.isEmpty,
              strokePointTotal <= PencilInputRules.startWindowPoints,
              sample.normalizedForce >= (strokeStartSample?.normalizedForce ?? 0)
        else { return }
        strokeStartSample = sample
        activeStrokeWidth = PencilInputRules.effectiveWidth(base: strokeWidth,
                                                            normalizedForce: sample.normalizedForce,
                                                            altitude: sample.altitude)
    }

    /// A pencil landing while a finger stroke is in flight = resting palm:
    /// wipe the smear locally and end the partner's live preview. The drag
    /// keeps reporting until the palm lifts — `palmRejected` swallows it.
    private func rejectPalmStroke() {
        guard PencilInputRules.discardsActiveStroke(strokeIsPencil: strokeIsPencil,
                                                    pencilJustLanded: true),
              !currentPoints.isEmpty else { return }
        currentPoints = []
        palmRejected = true
        sendLiveFrame(phase: "end")
    }

    /// Subtle brush footprint under the hovering pencil (or pointer): the
    /// exact rendered diameter of the NEXT stroke, in the selected color.
    /// Hidden while drawing or replaying — it previews, never distracts.
    @ViewBuilder private var brushPreview: some View {
        if let hoverPoint, replay == nil, currentPoints.isEmpty, !pencilOnSurface {
            let diameter = max(PencilInputRules.previewLineWidth(tool: tool.rawValue,
                                                                 width: strokeWidth), 4)
            let ink = tool == .eraser ? Tinte.dunkel : displayInk(selectedColor)
            Circle()
                .fill(ink.opacity(0.18))
                .overlay(Circle().strokeBorder(ink.opacity(0.5), lineWidth: 1))
                .frame(width: diameter, height: diameter)
                .position(hoverPoint)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var strokeCanvas: some View {
        if let session = replay {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    drawReplayFrame(session, at: timeline.date, context: &context, size: size)
                }
            }
        } else {
            Canvas { context, size in
                for stroke in strokes {
                    drawStroke(stroke, context: &context, size: size)
                }
                if !currentPoints.isEmpty {
                    drawStroke(liveStroke, context: &context, size: size)
                }
                if let partnerLive {
                    drawStroke(partnerLive, context: &context, size: size)
                }
            }
        }
    }

    /// "…zeichnet gerade mit" — visible while the partner has the canvas
    /// open, so drawing together feels like a shared room, not a mailbox.
    @ViewBuilder private var partnerPresenceBanner: some View {
        if partnerOnCanvas {
            HStack(spacing: Space.s) {
                EmojiAvatarView(emoji: appState.partner?.avatar,
                                colorHex: appState.partner?.color,
                                size: LayoutMetrics.s(22))
                Text(L10n.t("memories.canvas.partnerDrawing", ["name": appState.partnerName]))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.vertical, Space.xs)
            .padding(.horizontal, Space.m)
            .glass(.chrome, in: Capsule())
            .transition(.move(edge: .top).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }

    private var liveStroke: CanvasStroke {
        CanvasStroke(id: "live",
                     memberId: appState.memberId ?? "",
                     color: selectedColor,
                     width: activeStrokeWidth,
                     tool: tool.rawValue,
                     points: currentPoints,
                     createdAt: Date())
    }

    /// Papier & Licht contrast guard: the board is bright letter paper,
    /// but the stroke palette (member colors + stock hexes) was tuned for
    /// the old dark board. The WIRE format is untouched — strokes store
    /// and sync the raw hex — only the DISPLAY runs a too-bright color
    /// through the `inkOnPaper` darkening ladder, so #FFD166 & co. still
    /// read on paper on every device. The ladder is bounded (≤ 12 mixing
    /// steps against the four paper anchors), cheap enough per stroke per
    /// frame. Erasers ignore the color (StrokeRenderer paints boardColor).
    private func displayInk(_ hex: String) -> Color {
        Color(hex: CouplePaletteRules.inkOnPaper(hex))
    }

    /// All stroke drawing goes through the shared `StrokeRenderer` —
    /// smoothing, dots and tool looks stay identical to widget & co.
    private func drawStroke(_ stroke: CanvasStroke, context: inout GraphicsContext, size: CGSize) {
        StrokeRenderer.draw(points: stroke.points,
                            color: displayInk(stroke.color),
                            width: stroke.width,
                            tool: stroke.tool,
                            boardColor: Color(hex: Self.boardHex),
                            context: &context,
                            size: size)
    }

    // MARK: Export

    /// Renders the finished board and opens the export sheet.
    private func exportBoard() {
        guard !strokes.isEmpty, replay == nil else { return }
        guard let image = renderBoardImage() else {
            appState.showToast(CanvasExportStrings.t("export.renderFailed"), style: .error)
            return
        }
        Haptics.shared.tap()
        SoundEngine.shared.play(.pop)
        exportItem = CanvasExportItem(image: image)
    }

    /// Renders all strokes into a bitmap with the same 3:4 aspect ratio as
    /// the on-screen board, reusing the exact `drawStroke` code (points are
    /// normalized, so any output resolution works).
    private func renderBoardImage() -> UIImage? {
        let exportSize = CGSize(width: 1080, height: 1440)
        let snapshot = strokes
        let board = Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color(hex: Self.boardHex)))
            for stroke in snapshot {
                drawStroke(stroke, context: &context, size: size)
            }
        }
        .frame(width: exportSize.width, height: exportSize.height)
        let renderer = ImageRenderer(content: board)
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.uiImage
    }

    // MARK: Replay

    /// Draws strokes 0..<n fully plus a point-prefix of the currently animating stroke.
    private func drawReplayFrame(_ session: ReplaySession, at date: Date,
                                 context: inout GraphicsContext, size: CGSize) {
        for stroke in session.background {
            drawStroke(stroke, context: &context, size: size)
        }
        let elapsed = date.timeIntervalSince(session.startedAt)
        guard elapsed >= 0 else { return }
        let fullCount = Int(elapsed / session.strokeDuration)
        for (index, stroke) in session.strokes.enumerated() {
            if index < fullCount {
                drawStroke(stroke, context: &context, size: size)
            } else if index == fullCount {
                let fraction = (elapsed - Double(index) * session.strokeDuration) / session.strokeDuration
                drawPartialStroke(stroke, fraction: fraction, context: &context, size: size)
            } else {
                break
            }
        }
    }

    private func drawPartialStroke(_ stroke: CanvasStroke, fraction: Double,
                                   context: inout GraphicsContext, size: CGSize) {
        let clamped = min(max(fraction, 0), 1)
        let prefixCount = max(1, Int(Double(stroke.points.count) * clamped))
        let partial = CanvasStroke(id: stroke.id,
                                   memberId: stroke.memberId,
                                   color: stroke.color,
                                   width: stroke.width,
                                   tool: stroke.tool,
                                   points: Array(stroke.points.prefix(prefixCount)),
                                   createdAt: stroke.createdAt)
        drawStroke(partial, context: &context, size: size)
    }

    /// Progress is derived from the same clock that drives the stroke drawing.
    private func replayBar(_ session: ReplaySession) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: "play.fill")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(coupleTint.blend)
            TimelineView(.animation) { timeline in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.black.opacity(0.15))
                        Capsule()
                            .fill(coupleTint.blend)
                            .frame(width: geo.size.width * replayProgress(session, at: timeline.date))
                    }
                }
            }
            .frame(height: 6)
            Button {
                stopReplay(celebrating: false)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.black.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("common.close"))
        }
        .padding(.vertical, Space.s)
        .padding(.horizontal, Space.m)
        .glass(.chrome, in: Capsule())
    }

    private func replayProgress(_ session: ReplaySession, at date: Date) -> CGFloat {
        guard session.total > 0 else { return 1 }
        let elapsed = date.timeIntervalSince(session.startedAt)
        return CGFloat(min(max(elapsed / session.total, 0), 1))
    }

    private func startReplay() {
        guard replay == nil, !strokes.isEmpty else { return }
        Haptics.shared.tap()
        SoundEngine.shared.play(.pop)
        beginReplay(background: [], animated: strokes)
    }

    private func beginReplay(background: [CanvasStroke], animated: [CanvasStroke]) {
        let session = ReplaySession(strokes: animated, background: background,
                                    startedAt: Date(), strokeDuration: 0.25)
        replay = session
        replayEndTask?.cancel()
        replayEndTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(session.total * 1_000_000_000))
            } catch {
                return  // cancelled — the replay was stopped early
            }
            stopReplay(celebrating: true)
        }
    }

    private func stopReplay(celebrating: Bool) {
        replayEndTask?.cancel()
        replay = nil
        guard celebrating else { return }
        SoundEngine.shared.play(.sparkle)
        Haptics.shared.success()
        replayCelebration = Date()
        celebrationTask?.cancel()
        celebrationTask = Task {
            do {
                try await Task.sleep(nanoseconds: 2_400_000_000)
            } catch {
                return  // cancelled on disappear
            }
            replayCelebration = nil
        }
    }

    @ViewBuilder
    private func partnerIndicator(size: CGSize) -> some View {
        if let point = partnerPoint {
            EmojiAvatarView(emoji: appState.partner?.avatar,
                            colorHex: appState.partner?.color,
                            size: LayoutMetrics.s(32))
                .position(x: point.x * size.width,
                          y: max(point.y * size.height - 28, 16))
                .transition(.scale.combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    // MARK: Drawing gesture

    private func drawGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard replay == nil, !palmRejected else { return }
                if currentPoints.isEmpty && strokePointTotal == 0 {
                    // Stroke start: remember what started it and derive the
                    // width — finger strokes keep the slider width, pencil
                    // strokes press their width (refined for a few points
                    // by `refineStrokeStartWidth`, then locked).
                    strokeIsPencil = pencilOnSurface
                    strokeStartSample = strokeIsPencil ? latestPencilSample : nil
                    activeStrokeWidth = PencilInputRules.effectiveWidth(
                        base: strokeWidth,
                        normalizedForce: strokeStartSample?.normalizedForce,
                        altitude: strokeStartSample?.altitude
                            ?? PencilInputRules.verticalAltitude)
                }
                let x = Double(min(max(value.location.x / size.width, 0), 1))
                let y = Double(min(max(value.location.y / size.height, 0), 1))
                // Thin 120-Hz jitter at capture time — the payload stays
                // compact and the server point budget goes into real length.
                if let last = currentPoints.last, last.count >= 2,
                   !StrokeGeometry.farEnough(x: x, y: y, lastX: last[0], lastY: last[1]) {
                    return
                }
                currentPoints.append([x, y])
                strokePointTotal += 1
                streamLivePointsThrottled()
                if currentPoints.count >= 400 {
                    let segment = currentPoints
                    currentPoints = [segment[segment.count - 1]]
                    submitStroke(points: segment)
                }
            }
            .onEnded { _ in
                let wasPalm = palmRejected
                palmRejected = false
                strokeIsPencil = false
                strokeStartSample = nil
                strokePointTotal = 0
                guard replay == nil, !wasPalm else { return }
                let segment = currentPoints
                currentPoints = []
                sendLiveFrame(phase: "end")
                guard !segment.isEmpty else { return }
                submitStroke(points: segment)
            }
    }

    // MARK: Live co-drawing relay

    /// Streams the in-progress stroke to the partner (~12 frames/s). Full
    /// point list per frame: a dropped frame heals itself with the next
    /// one, and the committed stroke arrives via `canvas_stroke` anyway.
    private func streamLivePointsThrottled() {
        let now = Date()
        guard now.timeIntervalSince(lastLiveSentAt) > 0.08 else { return }
        lastLiveSentAt = now
        sendLiveFrame(phase: "draw", includePoints: true)
    }

    private func sendLiveFrame(phase: String, includePoints: Bool = false) {
        var payload: [String: Any] = ["phase": phase]
        if includePoints {
            payload["color"] = selectedColor
            payload["width"] = activeStrokeWidth
            payload["tool"] = tool.rawValue
            payload["points"] = currentPoints
        }
        appState.socket.send(["type": "canvas_live", "payload": payload])
    }

    /// "I'm on the canvas" heartbeat every 10 s — feeds the partner's
    /// presence banner without any new server state.
    private func startPresenceAnnouncements() {
        presenceAnnounceTask?.cancel()
        presenceAnnounceTask = Task {
            while !Task.isCancelled {
                sendLiveFrame(phase: "hello")
                do {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                } catch {
                    return  // cancelled on disappear
                }
            }
        }
    }

    private func touchPartnerPresence() {
        if !partnerOnCanvas {
            withAnimation(Theme.Motion.settle) { partnerOnCanvas = true }
        }
        presenceExpiryTask?.cancel()
        presenceExpiryTask = Task {
            do {
                try await Task.sleep(nanoseconds: 25_000_000_000)
            } catch {
                return  // refreshed by a newer frame
            }
            withAnimation(Theme.Motion.settle) { partnerOnCanvas = false }
        }
    }

    private func submitStroke(points: [[Double]]) {
        guard let api = appState.api else { return }
        let temp = CanvasStroke(id: "local-\(UUID().uuidString)",
                                memberId: appState.memberId ?? "",
                                color: selectedColor,
                                width: activeStrokeWidth,
                                tool: tool.rawValue,
                                points: StrokeGeometry.compacted(points),
                                createdAt: Date())
        strokes.append(temp)
        if tool != .eraser {
            recordRecentColor(selectedColor)
        }
        Haptics.shared.tap()
        Task {
            do {
                let saved = try await api.addStroke(color: temp.color,
                                                    width: temp.width,
                                                    tool: temp.tool,
                                                    points: temp.points,
                                                    generation: boardGeneration)
                reconcile(temp: temp.id, saved: saved)
            } catch {
                // 409 stale_generation (contract v11): the board was cleared
                // while this stroke was drawn against the OLD picture —
                // discard it and reload instead of resurrecting a ghost line
                // on the partner's fresh canvas.
                if (error as? APIError)?.serverCode == "stale_generation" {
                    discardStaleStroke(temp.id)
                    return
                }
                // B-11: the stroke stays on the board and requeues — a
                // connection hiccup must never eat drawn art.
                if !strokeRetryQueue.contains(where: { $0.id == temp.id }) {
                    strokeRetryQueue.append(temp)
                }
                appState.showToast(L10n.t("memories.canvas.strokeQueued"), style: .info)
                scheduleStrokeRetry()
            }
        }
    }

    /// Stroke bounced off a newer board generation: drop it everywhere and
    /// reload the fresh board (which also adopts the new generation).
    private func discardStaleStroke(_ tempId: String) {
        strokes.removeAll { $0.id == tempId }
        strokeRetryQueue.removeAll { $0.id == tempId }
        appState.showToast(L10n.t("memories.canvas.staleStroke"), style: .info)
        Task { await loadStrokes() }
    }

    /// Swap the optimistic temp for the server stroke (socket echo may
    /// have landed first).
    private func reconcile(temp tempId: String, saved: CanvasStroke) {
        guard let idx = strokes.firstIndex(where: { $0.id == tempId }) else { return }
        if strokes.contains(where: { $0.id == saved.id }) {
            strokes.remove(at: idx)
        } else {
            strokes[idx] = saved
        }
    }

    private func scheduleStrokeRetry() {
        guard strokeRetryTask == nil else { return }
        strokeRetryTask = Task {
            while !Task.isCancelled && !strokeRetryQueue.isEmpty {
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    break  // cancelled on disappear
                }
                await retryQueuedStrokes()
            }
            strokeRetryTask = nil
        }
    }

    private func retryQueuedStrokes() async {
        guard let api = appState.api else { return }
        for temp in strokeRetryQueue {
            do {
                let saved = try await api.addStroke(color: temp.color,
                                                    width: temp.width,
                                                    tool: temp.tool,
                                                    points: temp.points,
                                                    generation: boardGeneration)
                strokeRetryQueue.removeAll { $0.id == temp.id }
                reconcile(temp: temp.id, saved: saved)
            } catch {
                if (error as? APIError)?.serverCode == "stale_generation" {
                    discardStaleStroke(temp.id)
                    continue
                }
                // Still unreachable — the next pass tries again.
            }
        }
    }

    // MARK: Palette & controls

    private var paletteColors: [String] {
        var hexes: [String] = []
        func add(_ raw: String) {
            let hex = normalizedHex(raw)
            if !hexes.contains(hex) { hexes.append(hex) }
        }
        if let mine = appState.me?.color { add(mine) }
        if let theirs = appState.partner?.color { add(theirs) }
        for hex in ["#FF5C8A", "#FFD166", "#6EE7B7", "#60A5FA", "#A855F7", "#FB923C", "#1F2937", "#F87171"] {
            add(hex)
        }
        return Array(hexes.prefix(8))
    }

    private func normalizedHex(_ raw: String) -> String {
        raw.hasPrefix("#") ? raw : "#" + raw
    }

    private var palette: some View {
        HStack(spacing: Space.m) {
            ForEach(paletteColors, id: \.self) { hex in
                paletteSwatch(hex)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Rail variant of the palette: same swatches, four per row.
    private var paletteGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.m),
                                 count: 4),
                  spacing: Space.m) {
            ForEach(paletteColors, id: \.self) { hex in
                paletteSwatch(hex)
            }
        }
    }

    /// Swatches show the DISPLAY ink (what actually lands on the paper),
    /// not the raw wire hex — picking a pen is honest about its result.
    private func paletteSwatch(_ hex: String) -> some View {
        Button {
            selectedColor = hex
            if tool == .eraser { tool = .pen }
            Haptics.shared.tap()
        } label: {
            Circle()
                .fill(displayInk(hex))
                .frame(width: LayoutMetrics.s(30), height: LayoutMetrics.s(30))
                .overlay(
                    Circle().strokeBorder(.white, lineWidth: selectedColor == hex ? 3 : 1)
                )
                .shadow(color: displayInk(hex).opacity(0.6),
                        radius: selectedColor == hex ? 7 : 0)
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }

    // MARK: Recent colors (last 6 actually drawn with)

    private func recordRecentColor(_ hex: String) {
        var list = recentColors
        list.removeAll { $0 == hex }
        list.insert(hex, at: 0)
        if list.count > Self.recentColorsMax {
            list = Array(list.prefix(Self.recentColorsMax))
        }
        guard list != recentColors else { return }
        recentColors = list
        UserDefaults.standard.set(list, forKey: Self.recentColorsKey)
    }

    /// Small quick-access strip under the palette: the last colors a stroke
    /// was actually drawn with (persists across sessions).
    @ViewBuilder private var recentColorsRow: some View {
        if !recentColors.isEmpty {
            HStack(spacing: Space.s) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                ForEach(recentColors, id: \.self) { hex in
                    Button {
                        selectedColor = hex
                        if tool == .eraser { tool = .pen }
                        Haptics.shared.tap()
                    } label: {
                            Circle()
                            .fill(displayInk(hex))
                            .frame(width: LayoutMetrics.s(20), height: LayoutMetrics.s(20))
                            .overlay(
                                Circle().strokeBorder(.white, lineWidth: selectedColor == hex ? 2 : 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.lift)
                }
                Spacer(minLength: 0)
            }
            .accessibilityLabel(L10n.t("memories.canvas.recent"))
            .animation(Theme.Motion.settle, value: recentColors)
        }
    }

    /// Stacked-layout toolbox — floating chrome, like the wide rail.
    private var controls: some View {
        VStack(spacing: Space.m) {
            HStack(spacing: Space.m) {
                toolPicker
                undoButton
                clearButton
            }
            widthSlider
        }
        .padding(Space.l)
        .glass(.chrome, in: RoundedRectangle(cornerRadius: Radius.card,
                                             style: .continuous))
    }

    private var undoButton: some View {
        Button {
            undoLastStroke()
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(myLastUndoableStroke == nil ? Theme.textTertiary : Theme.textPrimary)
                .frame(width: LayoutMetrics.s(40), height: LayoutMetrics.s(34))
                .background(Capsule().fill(Theme.innerFill))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .disabled(myLastUndoableStroke == nil)
        .accessibilityLabel(L10n.t("memories.canvas.undo"))
    }

    /// Four tools fit a fixed row on every phone — no scrolling needed.
    private var toolPicker: some View {
        HStack(spacing: 6) {
            ForEach(CanvasTool.allCases) { candidate in
                Button {
                    tool = candidate
                    Haptics.shared.tap()
                } label: {
                    Image(systemName: candidate.icon)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(tool == candidate ? Color.white : Theme.textSecondary)
                        .frame(width: LayoutMetrics.s(40), height: LayoutMetrics.s(34))
                        .background(
                            Capsule().fill(tool == candidate ? coupleTint.blend.opacity(0.65) : Theme.innerFill)
                        )
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .accessibilityLabel(L10n.t(candidate.titleKey))
            }
        }
    }

    private var clearButton: some View {
        Button {
            Haptics.shared.tap()
            confirmClear = true
        } label: {
            Label(L10n.t("memories.canvas.clear"), systemImage: "trash")
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Color(hex: "F87171"))
                .padding(.vertical, Space.s)
                .padding(.horizontal, Space.m)
                .background(Capsule().fill(Color(hex: "F87171").opacity(0.14)))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
    }

    private var widthSlider: some View {
        HStack(spacing: Space.m) {
            Circle()
                .fill(Theme.textSecondary)
                .frame(width: 5, height: 5)
            Slider(value: $strokeWidth, in: 2...16, step: 1)
                .tint(coupleTint.blend)
                .accessibilityLabel(L10n.t("memories.canvas.width"))
            Circle()
                .fill(Theme.textSecondary)
                .frame(width: 14, height: 14)
        }
    }

    // MARK: Data & realtime

    private func pickInitialColor() {
        if let mine = appState.me?.color {
            selectedColor = normalizedHex(mine)
        }
    }

    private func loadStrokes() async {
        guard let api = appState.api else { return }
        do {
            let board = try await api.canvasBoard()
            strokes = board.strokes
            boardGeneration = board.generation
            autoReplayNewPartnerStrokes()
        } catch {
            appState.handleAPIError(error)
        }
        loading = false
    }

    private var lastSeenKey: String {
        "sooodreamy.canvas.lastSeen.\(appState.couple?.id ?? "solo")"
    }

    /// Everything currently on the board counts as seen.
    private func markCanvasSeen() {
        UserDefaults.standard.set(Date(), forKey: lastSeenKey)
    }

    /// Replay magic: strokes the partner drew since my last visit play
    /// back as an animation on top of the familiar old board — opening
    /// the canvas becomes "watch what they made for you".
    private func autoReplayNewPartnerStrokes() {
        let lastSeen = UserDefaults.standard.object(forKey: lastSeenKey) as? Date ?? .distantPast
        markCanvasSeen()
        guard replay == nil else { return }
        let fresh = strokes.filter { $0.memberId != appState.memberId && $0.createdAt > lastSeen }
        guard !fresh.isEmpty else { return }
        let freshIds = Set(fresh.map(\.id))
        let background = strokes.filter { !freshIds.contains($0.id) }
        SoundEngine.shared.play(.pop)
        beginReplay(background: background, animated: fresh)
    }

    /// My most recent stroke that already has a server id (in-flight "local-" temps can't be undone yet).
    private var myLastUndoableStroke: CanvasStroke? {
        strokes.last { $0.memberId == appState.memberId && !$0.id.hasPrefix("local-") }
    }

    private func undoLastStroke() {
        guard let api = appState.api, let stroke = myLastUndoableStroke else { return }
        guard let idx = strokes.firstIndex(where: { $0.id == stroke.id }) else { return }
        strokes.remove(at: idx)
        Haptics.shared.tap()
        Task {
            do {
                try await api.deleteStroke(id: stroke.id)
            } catch {
                if !strokes.contains(where: { $0.id == stroke.id }) {
                    strokes.insert(stroke, at: min(idx, strokes.count))
                }
                appState.handleAPIError(error)
            }
        }
    }

    private func clearAll() {
        guard let api = appState.api else { return }
        Task {
            do {
                try await api.clearCanvas()
                strokes = []
                currentPoints = []
                appState.showToast(L10n.t("memories.canvas.cleared"), style: .info)
                SoundEngine.shared.play(.whoosh)
                // Adopt the bumped board generation for the next strokes.
                await loadStrokes()
            } catch {
                appState.handleAPIError(error)
            }
        }
    }

    /// Default clear path (B-11): the artwork is uploaded into the shared
    /// gallery FIRST — the board only goes blank once the archive is safe.
    private func archiveAndClear() {
        guard let api = appState.api else { return }
        guard let image = renderBoardImage(),
              let jpeg = image.jpegData(compressionQuality: 0.85) else {
            appState.showToast(L10n.t("memories.canvas.archiveFailed"), style: .error)
            return
        }
        Haptics.shared.tap()
        Task {
            do {
                let photo = try await api.uploadPhoto(jpeg: jpeg,
                                                      caption: CanvasExportStrings.t("export.caption"),
                                                      width: Int(image.size.width),
                                                      height: Int(image.size.height))
                let thumb = GalleryView.downscaled(image, maxDimension: 320)
                if let thumbJpeg = thumb.jpegData(compressionQuality: 0.7) {
                    do {
                        _ = try await api.uploadPhotoThumb(photoId: photo.id, jpeg: thumbJpeg)
                    } catch {
                        // Thumbnail is best effort — the gallery falls back
                        // to the full image.
                    }
                }
                try await api.clearCanvas()
                strokes = []
                currentPoints = []
                SoundEngine.shared.play(.whoosh)
                appState.showToast(L10n.t("memories.canvas.archived"), style: .love)
                // Adopt the bumped board generation for the next strokes.
                await loadStrokes()
            } catch {
                // Upload or clear failed — the board stays untouched.
                appState.handleAPIError(error)
            }
        }
    }

    private func handleServerEvent(_ event: ServerEvent) {
        switch event.type {
        case .canvasStroke:
            guard let stroke = event.decode(StrokeResponse.self)?.stroke else { return }
            markCanvasSeen()
            guard !strokes.contains(where: { $0.id == stroke.id }) else { return }
            strokes.append(stroke)
            if stroke.memberId != appState.memberId {
                partnerLiveClearTask?.cancel()
                partnerLive = nil
                touchPartnerPresence()
                if Date().timeIntervalSince(lastPartnerPopAt) >= 4 {
                    lastPartnerPopAt = Date()
                    SoundEngine.shared.play(.pop)
                }
                showPartnerIndicator(for: stroke)
            }
        case .canvasStrokeDeleted:
            guard let id = event.decode(IdPayload.self)?.id else { return }
            strokes.removeAll { $0.id == id }
        case .canvasClear:
            strokes = []
            currentPoints = []
            partnerLive = nil
            stopReplay(celebrating: false)
            // The clear bumped the board generation — refetch it so the
            // next stroke posts against the fresh board (the frame itself
            // carries no generation; old servers have none anyway).
            boardGeneration = nil
            Task { await loadStrokes() }
            if let by = event.decode(CanvasClearPayload.self)?.by, by != appState.memberId {
                appState.showToast(L10n.t("memories.canvas.clearedBy",
                                          ["name": appState.partnerName]),
                                   style: .info)
            }
        case .canvasLive:
            guard let live = event.decode(CanvasLivePayload.self),
                  live.memberId != appState.memberId else { return }
            handleLiveFrame(live)
        case .welcome:
            // Socket (re)connected — stroke/clear fanouts eaten by the gap
            // never return; refetch the board (strokes + generation) while
            // mounted (welcome catch-up).
            boardGeneration = nil
            Task { await loadStrokes() }
        default:
            break
        }
    }

    private func handleLiveFrame(_ live: CanvasLivePayload) {
        switch live.phase {
        case "draw":
            touchPartnerPresence()
            partnerLiveClearTask?.cancel()
            if let points = live.points, !points.isEmpty {
                partnerLive = CanvasStroke(id: "partner-live",
                                           memberId: live.memberId,
                                           color: live.color ?? "#FF5C8A",
                                           width: live.width ?? 5,
                                           tool: live.tool ?? "pen",
                                           points: points,
                                           createdAt: Date())
            }
        case "end":
            // Keep the preview until the committed canvas_stroke replaces
            // it — with a fallback wipe in case that stroke never lands.
            touchPartnerPresence()
            partnerLiveClearTask?.cancel()
            partnerLiveClearTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                } catch {
                    return  // replaced by the committed stroke or a new draw
                }
                partnerLive = nil
            }
        case "bye":
            partnerLive = nil
            presenceExpiryTask?.cancel()
            withAnimation(Theme.Motion.settle) { partnerOnCanvas = false }
        default:
            touchPartnerPresence()  // "hello" heartbeat
        }
    }

    private func showPartnerIndicator(for stroke: CanvasStroke) {
        guard let last = stroke.points.last, last.count >= 2 else { return }
        withAnimation(Theme.Motion.settle) {
            partnerPoint = CGPoint(x: last[0], y: last[1])
        }
        indicatorTask?.cancel()
        indicatorTask = Task {
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                return  // superseded by a newer indicator
            }
            withAnimation(Theme.Motion.settle) {
                partnerPoint = nil
            }
        }
    }
}
