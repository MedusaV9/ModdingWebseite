import SwiftUI
import Combine
import UIKit

/// Shared realtime doodle canvas — both partners draw on the same board.
struct CanvasView: View {
    @Environment(AppState.self) private var appState

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

    /// Board background — the eraser paints in exactly this color.
    private static let boardHex = "FDF4E8"

    private static let recentColorsKey = "sooodreamy.canvas.recentColors"
    private static let recentColorsMax = 6

    /// Immutable snapshot of the stroke list at replay start, so strokes
    /// arriving live during the replay don't glitch the animation.
    private struct ReplaySession {
        let strokes: [CanvasStroke]
        let startedAt: Date
        let strokeDuration: Double

        var total: Double { Double(strokes.count) * strokeDuration }
    }

    private enum CanvasTool: String, CaseIterable, Identifiable {
        case pen, marker, glow, dotted, calligraphy, eraser
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .pen: return "pencil.tip"
            case .marker: return "highlighter"
            case .glow: return "sparkles"
            case .dotted: return "circle.dotted"
            case .calligraphy: return "paintbrush.pointed.fill"
            case .eraser: return "eraser.fill"
            }
        }

        var titleKey: String { "memories.canvas.tool.\(rawValue)" }
    }

    var body: some View {
        ZStack {
            DreamyBackground(showStars: false)
            VStack(spacing: LayoutMetrics.s(14)) {
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
            .padding(LayoutMetrics.s(16))
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
                        .foregroundStyle(strokes.isEmpty || replay != nil ? Theme.textTertiary : Theme.pink)
                }
                .disabled(strokes.isEmpty || replay != nil)
                .accessibilityLabel(CanvasExportStrings.t("export.title"))
                Button {
                    startReplay()
                } label: {
                    Image(systemName: "play.circle")
                        .foregroundStyle(strokes.isEmpty || replay != nil ? Theme.textTertiary : Theme.pink)
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
        }
        .onDisappear {
            // Kill the delayed replay-end/celebration work — otherwise the tada
            // sound + haptic would fire minutes later from another screen.
            replayEndTask?.cancel()
            celebrationTask?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            handleServerEvent(event)
        }
        .confirmationDialog(L10n.t("memories.canvas.clearConfirm"),
                            isPresented: $confirmClear, titleVisibility: .visible) {
            Button(L10n.t("memories.canvas.clear"), role: .destructive) { clearAll() }
            Button(L10n.t("common.cancel"), role: .cancel) {}
        }
    }

    private var subtitle: some View {
        Text(L10n.t("memories.canvas.subtitle"))
            .font(.system(.footnote, design: .rounded).weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
    }

    // MARK: Board

    private var board: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(hex: Self.boardHex))
                    .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
                strokeCanvas
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                if loading {
                    ProgressView()
                        .tint(Theme.purple)
                } else if strokes.isEmpty && currentPoints.isEmpty {
                    Text(L10n.t("memories.canvas.empty"))
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.black.opacity(0.25))
                        .allowsHitTesting(false)
                }
                partnerIndicator(size: geo.size)
                if let session = replay {
                    VStack {
                        Spacer()
                        replayBar(session)
                    }
                    .padding(LayoutMetrics.s(12))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .gesture(drawGesture(size: geo.size))
        }
        .aspectRatio(0.75, contentMode: .fit)
        .frame(maxWidth: .infinity)
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
            }
        }
    }

    private var liveStroke: CanvasStroke {
        CanvasStroke(id: "live",
                     memberId: appState.memberId ?? "",
                     color: selectedColor,
                     width: strokeWidth,
                     tool: tool.rawValue,
                     points: currentPoints,
                     createdAt: Date())
    }

    private func drawStroke(_ stroke: CanvasStroke, context: inout GraphicsContext, size: CGSize) {
        let points = stroke.points.compactMap { pair -> CGPoint? in
            guard pair.count >= 2 else { return nil }
            return CGPoint(x: pair[0] * size.width, y: pair[1] * size.height)
        }
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: first)
        if points.count == 1 {
            path.addLine(to: first)
        } else {
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
        let color = Color(hex: stroke.color)
        let width = stroke.width

        func solid(_ lineWidth: Double) -> StrokeStyle {
            StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        }

        // Tool is a free string on the wire — unknown tools fall back to pen,
        // so older clients render newer strokes gracefully.
        switch stroke.tool {
        case "marker":
            context.stroke(path, with: .color(color.opacity(0.6)), style: solid(width * 2.5))
        case "eraser":
            context.stroke(path, with: .color(Color(hex: Self.boardHex)), style: solid(width * 2.5))
        case "glow":
            // Neon look: soft shadow halo underneath + a bright core stroke.
            var halo = context
            halo.addFilter(.shadow(color: color.opacity(0.85), radius: width * 1.4))
            halo.stroke(path, with: .color(color.opacity(0.55)), style: solid(width * 1.6))
            context.stroke(path, with: .color(color), style: solid(width))
        case "dotted":
            // Zero-ish dash segments with round caps render as evenly spaced dots.
            context.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: width * 1.4, lineCap: .round,
                                              lineJoin: .round, dash: [0.1, width * 2.8]))
        case "calligraphy":
            // Variable-width illusion: main stroke + a thinner, diagonally
            // offset twin — diagonals thicken, horizontals stay slim.
            let offset = max(width * 0.45, 1.2)
            let slanted = path.applying(CGAffineTransform(translationX: offset, y: -offset))
            context.stroke(path, with: .color(color), style: solid(width * 0.75))
            context.stroke(slanted, with: .color(color.opacity(0.85)), style: solid(width * 0.55))
        default:
            context.stroke(path, with: .color(color), style: solid(width))
        }
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
        HStack(spacing: LayoutMetrics.s(10)) {
            Image(systemName: "play.fill")
                .font(.scaled(11, weight: .bold))
                .foregroundStyle(Theme.pink)
            TimelineView(.animation) { timeline in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.black.opacity(0.15))
                        Capsule()
                            .fill(Theme.pink)
                            .frame(width: geo.size.width * replayProgress(session, at: timeline.date))
                    }
                }
            }
            .frame(height: 6)
            Button {
                stopReplay(celebrating: false)
            } label: {
                Image(systemName: "xmark")
                    .font(.scaled(11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.black.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("common.close"))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, LayoutMetrics.s(12))
        .background(Capsule().fill(.ultraThinMaterial))
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
        let session = ReplaySession(strokes: strokes, startedAt: Date(), strokeDuration: 0.25)
        replay = session
        replayEndTask?.cancel()
        replayEndTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(session.total * 1_000_000_000))
            guard !Task.isCancelled else { return }
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
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if !Task.isCancelled { replayCelebration = nil }
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
                guard replay == nil else { return }
                let x = min(max(value.location.x / size.width, 0), 1)
                let y = min(max(value.location.y / size.height, 0), 1)
                currentPoints.append([Double(x), Double(y)])
                if currentPoints.count >= 400 {
                    let segment = currentPoints
                    currentPoints = [segment[segment.count - 1]]
                    submitStroke(points: segment)
                }
            }
            .onEnded { _ in
                guard replay == nil else { return }
                let segment = currentPoints
                currentPoints = []
                guard !segment.isEmpty else { return }
                submitStroke(points: segment)
            }
    }

    private func submitStroke(points: [[Double]]) {
        guard let api = appState.api else { return }
        let temp = CanvasStroke(id: "local-\(UUID().uuidString)",
                                memberId: appState.memberId ?? "",
                                color: selectedColor,
                                width: strokeWidth,
                                tool: tool.rawValue,
                                points: points,
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
                                                    points: temp.points)
                if let idx = strokes.firstIndex(where: { $0.id == temp.id }) {
                    if strokes.contains(where: { $0.id == saved.id }) {
                        strokes.remove(at: idx)   // socket echo landed first
                    } else {
                        strokes[idx] = saved
                    }
                }
            } catch {
                strokes.removeAll { $0.id == temp.id }
                appState.handleAPIError(error)
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
        HStack(spacing: LayoutMetrics.s(10)) {
            ForEach(paletteColors, id: \.self) { hex in
                Button {
                    selectedColor = hex
                    if tool == .eraser { tool = .pen }
                    Haptics.shared.tap()
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: LayoutMetrics.s(30), height: LayoutMetrics.s(30))
                        .overlay(
                            Circle().strokeBorder(.white, lineWidth: selectedColor == hex ? 3 : 1)
                        )
                        .shadow(color: Color(hex: hex).opacity(0.6),
                                radius: selectedColor == hex ? 7 : 0)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
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
            HStack(spacing: LayoutMetrics.s(8)) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.scaled(11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                ForEach(recentColors, id: \.self) { hex in
                    Button {
                        selectedColor = hex
                        if tool == .eraser { tool = .pen }
                        Haptics.shared.tap()
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: LayoutMetrics.s(20), height: LayoutMetrics.s(20))
                            .overlay(
                                Circle().strokeBorder(.white, lineWidth: selectedColor == hex ? 2 : 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .accessibilityLabel(L10n.t("memories.canvas.recent"))
            .animation(.spring(response: 0.3), value: recentColors)
        }
    }

    private var controls: some View {
        VStack(spacing: LayoutMetrics.s(12)) {
            HStack(spacing: LayoutMetrics.s(10)) {
                toolPicker
                undoButton
                clearButton
            }
            widthSlider
        }
        .glassCard(padding: 14)
    }

    private var undoButton: some View {
        Button {
            undoLastStroke()
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.scaled(15, weight: .semibold))
                .foregroundStyle(myLastUndoableStroke == nil ? Theme.textTertiary : Theme.textPrimary)
                .frame(width: LayoutMetrics.s(40), height: LayoutMetrics.s(34))
                .background(Capsule().fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .disabled(myLastUndoableStroke == nil)
        .accessibilityLabel(L10n.t("memories.canvas.undo"))
    }

    /// Six brushes don't fit a fixed row on small phones — the picker scrolls.
    private var toolPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(CanvasTool.allCases) { candidate in
                    Button {
                        tool = candidate
                        Haptics.shared.tap()
                    } label: {
                        Image(systemName: candidate.icon)
                            .font(.scaled(15, weight: .semibold))
                            .foregroundStyle(tool == candidate ? Color.white : Theme.textSecondary)
                            .frame(width: LayoutMetrics.s(40), height: LayoutMetrics.s(34))
                            .background(
                                Capsule().fill(tool == candidate ? Theme.purple.opacity(0.65) : Color.white.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t(candidate.titleKey))
                }
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
                .padding(.vertical, 8)
                .padding(.horizontal, LayoutMetrics.s(12))
                .background(Capsule().fill(Color(hex: "F87171").opacity(0.14)))
        }
        .buttonStyle(.plain)
    }

    private var widthSlider: some View {
        HStack(spacing: LayoutMetrics.s(12)) {
            Circle()
                .fill(Theme.textSecondary)
                .frame(width: 5, height: 5)
            Slider(value: $strokeWidth, in: 2...16, step: 1)
                .tint(Theme.pink)
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
            strokes = try await api.canvasStrokes()
        } catch {
            appState.handleAPIError(error)
        }
        loading = false
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
            } catch {
                appState.handleAPIError(error)
            }
        }
    }

    private func handleServerEvent(_ event: ServerEvent) {
        switch event.type {
        case .canvasStroke:
            guard let stroke = event.decode(StrokeResponse.self)?.stroke else { return }
            guard !strokes.contains(where: { $0.id == stroke.id }) else { return }
            strokes.append(stroke)
            if stroke.memberId != appState.memberId {
                SoundEngine.shared.play(.pop)
                showPartnerIndicator(for: stroke)
            }
        case .canvasStrokeDeleted:
            guard let id = event.decode(IdPayload.self)?.id else { return }
            strokes.removeAll { $0.id == id }
        case .canvasClear:
            strokes = []
            currentPoints = []
            stopReplay(celebrating: false)
        default:
            break
        }
    }

    private func showPartnerIndicator(for stroke: CanvasStroke) {
        guard let last = stroke.points.last, last.count >= 2 else { return }
        withAnimation(.spring(response: 0.3)) {
            partnerPoint = CGPoint(x: last[0], y: last[1])
        }
        indicatorTask?.cancel()
        indicatorTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                partnerPoint = nil
            }
        }
    }
}

// MARK: - Export sheet

/// Identifiable wrapper so `.sheet(item:)` re-renders per export.
private struct CanvasExportItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Share / save / upload options for an exported canvas bitmap.
private struct CanvasExportSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let image: UIImage

    @State private var savingToPhotos = false
    @State private var savedToPhotos = false
    @State private var uploading = false
    @State private var uploaded = false

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    VStack(spacing: LayoutMetrics.s(16)) {
                        preview
                        actions
                    }
                    .padding(LayoutMetrics.s(16))
                }
            }
            .navigationTitle(CanvasExportStrings.t("export.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.close")) { dismiss() }
                }
            }
        }
    }

    private var preview: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
            .frame(maxHeight: LayoutMetrics.s(400))
    }

    private var actions: some View {
        VStack(spacing: LayoutMetrics.s(10)) {
            ShareLink(item: Image(uiImage: image),
                      preview: SharePreview(CanvasExportStrings.t("export.previewTitle"),
                                            image: Image(uiImage: image))) {
                Label(CanvasExportStrings.t("export.share"), systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())

            Button(action: saveToPhotos) {
                HStack(spacing: 8) {
                    if savingToPhotos {
                        ProgressView()
                            .tint(Theme.textPrimary)
                    } else {
                        Label(CanvasExportStrings.t(savedToPhotos
                                                    ? "export.savedToPhotos"
                                                    : "export.saveToPhotos"),
                              systemImage: savedToPhotos ? "checkmark" : "photo.on.rectangle.angled")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(savingToPhotos || savedToPhotos)

            if appState.api != nil {
                Button(action: uploadToGallery) {
                    HStack(spacing: 8) {
                        if uploading {
                            ProgressView()
                                .tint(Theme.textPrimary)
                        } else {
                            Label(CanvasExportStrings.t(uploaded
                                                        ? "export.uploaded"
                                                        : "export.upload"),
                                  systemImage: uploaded ? "checkmark" : "photo.stack")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(uploading || uploaded)
            }
        }
    }

    /// Add-only photo library write — covered by NSPhotoLibraryAddUsageDescription.
    private func saveToPhotos() {
        guard !savingToPhotos, !savedToPhotos else { return }
        savingToPhotos = true
        Haptics.shared.tap()
        CanvasImageSaver.save(image) { ok in
            savingToPhotos = false
            if ok {
                savedToPhotos = true
                SoundEngine.shared.play(.chime)
                Haptics.shared.success()
                appState.showToast(CanvasExportStrings.t("export.savedToast"), style: .success)
            } else {
                appState.showToast(CanvasExportStrings.t("export.saveFailed"), style: .error)
            }
        }
    }

    /// Uploads the artwork into the shared couple gallery (same flow as a
    /// gallery upload: full JPEG + best-effort grid thumbnail).
    private func uploadToGallery() {
        guard let api = appState.api, !uploading, !uploaded else { return }
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else {
            appState.showToast(CanvasExportStrings.t("export.uploadFailed"), style: .error)
            return
        }
        uploading = true
        Haptics.shared.tap()
        Task {
            do {
                let photo = try await api.uploadPhoto(jpeg: jpeg,
                                                      caption: CanvasExportStrings.t("export.caption"),
                                                      width: Int(image.size.width),
                                                      height: Int(image.size.height))
                let thumb = GalleryView.downscaled(image, maxDimension: 320)
                if let thumbJpeg = thumb.jpegData(compressionQuality: 0.7) {
                    _ = try? await api.uploadPhotoThumb(photoId: photo.id, jpeg: thumbJpeg)
                }
                uploaded = true
                SoundEngine.shared.play(.sparkle)
                Haptics.shared.success()
                appState.showToast(CanvasExportStrings.t("export.uploadedToast"), style: .love)
            } catch {
                appState.handleAPIError(error)
            }
            uploading = false
        }
    }
}

// MARK: - Photo library saver

/// UIImageWriteToSavedPhotosAlbum needs an Obj-C completion target;
/// instances keep themselves alive until the callback fires.
private final class CanvasImageSaver: NSObject {
    private static var active: [CanvasImageSaver] = []
    private var completion: ((Bool) -> Void)?

    static func save(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        let saver = CanvasImageSaver()
        saver.completion = completion
        active.append(saver)
        UIImageWriteToSavedPhotosAlbum(image, saver,
                                       #selector(CanvasImageSaver.image(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    @objc private func image(_ image: UIImage,
                             didFinishSavingWithError error: Error?,
                             contextInfo: UnsafeRawPointer) {
        let ok = error == nil
        DispatchQueue.main.async {
            self.completion?(ok)
            Self.active.removeAll { $0 === self }
        }
    }
}

// MARK: - Export strings

/// File-private strings for the export feature — deliberately NOT part of
/// MemoriesL10n (kept local to this file), resolved via the same LText type.
private enum CanvasExportStrings {
    static let table: [String: LText] = [
        "export.title": LText(de: "Kunstwerk exportieren", en: "Export artwork"),
        "export.previewTitle": LText(de: "Kritzel-Canvas", en: "Doodle canvas"),
        "export.share": LText(de: "Teilen…", en: "Share…"),
        "export.saveToPhotos": LText(de: "In Fotos sichern", en: "Save to Photos"),
        "export.savedToPhotos": LText(de: "In Fotos gesichert ✓", en: "Saved to Photos ✓"),
        "export.savedToast": LText(de: "In deiner Fotomediathek gesichert 🎨",
                                   en: "Saved to your photo library 🎨"),
        "export.saveFailed": LText(de: "Sichern fehlgeschlagen", en: "Couldn't save the image"),
        "export.upload": LText(de: "In eure Galerie hochladen", en: "Upload to your gallery"),
        "export.uploaded": LText(de: "In eurer Galerie ✓", en: "In your gallery ✓"),
        "export.uploadedToast": LText(de: "In eurer Galerie gespeichert 💜",
                                      en: "Added to your gallery 💜"),
        "export.uploadFailed": LText(de: "Upload fehlgeschlagen", en: "Upload failed"),
        "export.caption": LText(de: "Kritzel-Canvas 🎨", en: "Doodle canvas 🎨"),
        "export.renderFailed": LText(de: "Export fehlgeschlagen — versuch es nochmal.",
                                     en: "Export failed — try again.")
    ]

    static func t(_ key: String) -> String {
        table[key]?.resolved(L10n.lang) ?? key
    }
}
