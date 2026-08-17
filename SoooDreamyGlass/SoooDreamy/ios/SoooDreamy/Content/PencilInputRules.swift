import Foundation

/// Pure Apple-Pencil input rules — Foundation-only so the Linux LogicTests
/// can pin them down. The UIKit probe (`UI/PencilInput.swift`) reports raw
/// touch samples; these rules turn them into stroke widths WITHOUT touching
/// the wire format: `CanvasStroke` carries ONE width per stroke, so pressure
/// is read in the stroke-start window and then locked for the stroke.
enum PencilInputRules {
    /// A pencil held upright reports this altitude (radians).
    static let verticalAltitude = Double.pi / 2

    /// Pressure is sampled while the stroke is at most this many points
    /// old, then the width locks. The wire format has one width per stroke
    /// — refining any longer would repaint the whole stroke mid-draw.
    static let startWindowPoints = 4

    /// Width multiplier bounds. The relay clamps live widths at 32 and the
    /// widest tool setting is 16, so `16 × maxFactor` must stay below that;
    /// the floor keeps feather-light strokes visible.
    static let minFactor = 0.55
    static let maxFactor = 1.8

    /// Force → width factor: an average pencil press (`UITouch.force == 1`,
    /// ≈ 0.24 of `maximumPossibleForce`) draws exactly the chosen width,
    /// lighter presses thin out, leaning in fattens up. Tilting the pencil
    /// toward the paper (small altitude) broadens the line further, like
    /// shading with a real pencil's side.
    static func widthFactor(normalizedForce: Double,
                            altitude: Double = verticalAltitude) -> Double {
        let force = min(max(normalizedForce, 0), 1)
        let pressure = 0.7 + 1.25 * force
        let tiltRange = min(max(altitude / verticalAltitude, 0), 1)
        let tilt = 1 + 0.4 * (1 - tiltRange)
        return min(max(pressure * tilt, minFactor), maxFactor)
    }

    /// Effective stroke width for a base (slider) width and an optional
    /// pencil sample — finger strokes (`nil` force) keep the base width.
    /// Clamped to the live-relay bounds so partner previews and committed
    /// strokes can never disagree.
    static func effectiveWidth(base: Double,
                               normalizedForce: Double?,
                               altitude: Double = verticalAltitude) -> Double {
        guard let normalizedForce, normalizedForce > 0 else { return base }
        let width = base * widthFactor(normalizedForce: normalizedForce,
                                       altitude: altitude)
        return min(max(width, 1), 32)
    }

    /// Rendered line width of the hover preview circle, mirroring the
    /// per-tool multipliers in `StrokeRenderer` — the preview shows the
    /// footprint the NEXT stroke will actually have.
    static func previewLineWidth(tool: String, width: Double) -> Double {
        switch tool {
        case "marker", "eraser": return width * 2.5
        case "glow": return width * 1.6
        default: return width
        }
    }

    /// Palm rejection: a stroke started by a finger is discarded the moment
    /// a pencil lands — the finger was a resting palm, the pencil is the
    /// artist. Pencil-started strokes are never discarded.
    static func discardsActiveStroke(strokeIsPencil: Bool,
                                     pencilJustLanded: Bool) -> Bool {
        pencilJustLanded && !strokeIsPencil
    }
}
