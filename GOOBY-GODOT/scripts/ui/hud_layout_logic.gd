class_name HudLayoutLogic
extends RefCounted
## PURE Layout-Logik fürs HUD (headless testbar, keine Nodes):
## Layout-Wahl Hochkant „Daumen-Bogen“ (P1) vs. Querformat „Cockpit“ (L1)
## + die Bogen-Geometrie um die rechte untere Ecke (H §1.3).

enum Layout { PORTRAIT, LANDSCAPE }

## Daumenradius des Aktions-Bogens (≈ 9 rem, H §1.3) — BASIS-Werte für einen
## 720 px breiten Hochkant-Canvas; auf dem echten Canvas mit
## `portrait_scale()` multiplizieren (Stretch expand hält den Canvas in
## Hochkant immer ≥1280 breit, E5-F2). Radius/Stagger sind so gewählt, dass
## sich benachbarte 72er-Buttons auf dem 176°→94°-Fächer auch als
## Bounding-Boxen nie überlappen (jedes Paar hat auf mindestens einer
## Achse ≥ Buttongröße Abstand — nachgerechnet + im FIXB-Audit geprüft).
const ARC_RADIUS := 166.0
const ARC_START_DEG := 176.0  # fast waagerecht links vom Eck
const ARC_END_DEG := 94.0  # fast senkrecht überm Eck
const ARC_STAGGER := 82.0
## Aktions-Button-Kantenlänge (H §1.3, Basis wie ARC_RADIUS) — Auge/Bogen.
const ACTION_BTN := 72.0
## Kompakte Cockpit-Kachel Querformat (Design-px vor UiScale): 48er-Taste
## mit 22er-Icon — ACTION_BTN×f war physisch zu groß (H2-Debug).
const LANDSCAPE_BTN := 48.0
const LANDSCAPE_ICON := 22.0


## Layout aus der Viewport-Größe: höher als breit → Hochkant.
static func pick_layout(viewport_size: Vector2) -> Layout:
	if viewport_size.y > viewport_size.x:
		return Layout.PORTRAIT
	return Layout.LANDSCAPE


## Skalierungsfaktor fürs Hochkant-HUD: Die Bogen-Basiswerte sind für einen
## 720 px breiten Hochkant-Screen gedacht, das Projekt-Stretch
## (Basis 1280×720, canvas_items + expand) liefert in Hochkant aber immer
## einen ≥1280 px breiten Canvas — physisch wird alles auf
## Fensterbreite/1280 verkleinert (E5-F2/F4). Deshalb wachsen die
## Design-Größen mit Canvas-Breite/720 (~1,78 bei Basis-Stretch).
static func portrait_scale(canvas_size: Vector2) -> float:
	return clampf(canvas_size.x / 720.0, 1.0, 2.0)


## Touch-Floor in CANVAS-px: `AcTokens.TOUCH_FLOOR` (48) gilt PHYSISCH.
## Durch Stretch expand ist die kurze Canvas-Achse immer ≥720 (Basis) —
## der Faktor kurze-Achse/720 rechnet den physischen Floor auf Canvas-px
## hoch (Hochkant: 48·1280/720 ≈ 85 Canvas-px; Quer 1280×720: 48).
static func touch_floor_canvas(canvas_size: Vector2) -> float:
	var short_axis := minf(canvas_size.x, canvas_size.y)
	return float(AcTokens.TOUCH_FLOOR) * maxf(short_axis / 720.0, 1.0)


## Gleichmäßig verteilte Bogen-Winkel (Grad) für `count` Buttons.
static func arc_angles_deg(
	count: int, start_deg: float = ARC_START_DEG, end_deg: float = ARC_END_DEG
) -> Array[float]:
	var angles: Array[float] = []
	if count <= 0:
		return angles
	if count == 1:
		angles.append((start_deg + end_deg) / 2.0)
		return angles
	var step := (end_deg - start_deg) / float(count - 1)
	for i in count:
		angles.append(start_deg + step * float(i))
	return angles


## Punkt auf dem Bogen um `corner` (rechte untere Ecke, y wächst nach unten):
## 180° = links vom Eck, 90° = senkrecht über dem Eck.
static func arc_point(corner: Vector2, radius: float, angle_deg: float) -> Vector2:
	var rad := deg_to_rad(angle_deg)
	return corner + Vector2(cos(rad) * radius, -sin(rad) * radius)


## Safe-Area-Insets (W4/POLISH-4, Notch/Home-Indicator): rechnet
## `DisplayServer.get_display_safe_area()`-Koordinaten in Rand-Abstände
## {left, top, right, bottom} um. Beide Argumente im GLEICHEN
## Koordinatenraum (Fenster-Pixel ODER Canvas — Aufrufer skaliert).
## Leere/ungültige Safe-Area → alle Insets 0 (Desktop/Headless).
static func safe_insets(window_size: Vector2, safe_area: Rect2) -> Dictionary:
	var zero := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	if window_size.x <= 0.0 or window_size.y <= 0.0:
		return zero
	if safe_area.size.x <= 0.0 or safe_area.size.y <= 0.0:
		return zero
	return {
		"left": maxf(safe_area.position.x, 0.0),
		"top": maxf(safe_area.position.y, 0.0),
		"right": maxf(window_size.x - safe_area.end.x, 0.0),
		"bottom": maxf(window_size.y - safe_area.end.y, 0.0),
	}
