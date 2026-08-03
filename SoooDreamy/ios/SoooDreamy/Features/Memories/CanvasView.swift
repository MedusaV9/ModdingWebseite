import SwiftUI
import Combine

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

    /// Board background — the eraser paints in exactly this color.
    private static let boardHex = "FDF4E8"

    private enum CanvasTool: String, CaseIterable, Identifiable {
        case pen, marker, eraser
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .pen: return "pencil.tip"
            case .marker: return "highlighter"
            case .eraser: return "eraser.fill"
            }
        }

        var titleKey: String { "memories.canvas.tool.\(rawValue)" }
    }

    var body: some View {
        ZStack {
            DreamyBackground(showStars: false)
            VStack(spacing: 14) {
                subtitle
                board
                palette
                controls
            }
            .padding(16)
        }
        .navigationTitle(L10n.t("memories.canvas.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadStrokes() }
        .onAppear { pickInitialColor() }
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
            }
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .gesture(drawGesture(size: geo.size))
        }
        .aspectRatio(0.75, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    private var strokeCanvas: some View {
        Canvas { context, size in
            for stroke in strokes {
                drawStroke(stroke, context: &context, size: size)
            }
            if !currentPoints.isEmpty {
                drawStroke(liveStroke, context: &context, size: size)
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
        var color = Color(hex: stroke.color)
        var width = stroke.width
        switch stroke.tool {
        case "marker":
            width *= 2.5
            color = color.opacity(0.6)
        case "eraser":
            color = Color(hex: Self.boardHex)
            width *= 2.5
        default:
            break
        }
        context.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    @ViewBuilder
    private func partnerIndicator(size: CGSize) -> some View {
        if let point = partnerPoint {
            EmojiAvatarView(emoji: appState.partner?.avatar,
                            colorHex: appState.partner?.color,
                            size: 32)
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
        HStack(spacing: 10) {
            ForEach(paletteColors, id: \.self) { hex in
                Button {
                    selectedColor = hex
                    if tool == .eraser { tool = .pen }
                    Haptics.shared.tap()
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 30, height: 30)
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

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                toolPicker
                undoButton
                Spacer()
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(myLastUndoableStroke == nil ? Theme.textTertiary : Theme.textPrimary)
                .frame(width: 40, height: 34)
                .background(Capsule().fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .disabled(myLastUndoableStroke == nil)
        .accessibilityLabel(L10n.t("memories.canvas.undo"))
    }

    private var toolPicker: some View {
        HStack(spacing: 6) {
            ForEach(CanvasTool.allCases) { candidate in
                Button {
                    tool = candidate
                    Haptics.shared.tap()
                } label: {
                    Image(systemName: candidate.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tool == candidate ? Color.white : Theme.textSecondary)
                        .frame(width: 40, height: 34)
                        .background(
                            Capsule().fill(tool == candidate ? Theme.purple.opacity(0.65) : Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
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
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Capsule().fill(Color(hex: "F87171").opacity(0.14)))
        }
        .buttonStyle(.plain)
    }

    private var widthSlider: some View {
        HStack(spacing: 12) {
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
