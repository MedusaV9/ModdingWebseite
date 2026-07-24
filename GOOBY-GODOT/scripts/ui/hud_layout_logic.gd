class_name HudLayoutLogic
extends RefCounted
## PURE Layout-Logik fürs HUD (headless testbar, keine Nodes):
## Layout-Wahl Hochkant „Daumen-Bogen“ (P1) vs. Querformat „Cockpit“ (L1)
## + die Bogen-Geometrie um die rechte untere Ecke (H §1.3).

enum Layout { PORTRAIT, LANDSCAPE }

## Daumenradius des Aktions-Bogens (≈ 9 rem, H §1.3).
const ARC_RADIUS := 150.0
const ARC_START_DEG := 176.0  # fast waagerecht links vom Eck
const ARC_END_DEG := 94.0  # fast senkrecht überm Eck


## Layout aus der Viewport-Größe: höher als breit → Hochkant.
static func pick_layout(viewport_size: Vector2) -> Layout:
	if viewport_size.y > viewport_size.x:
		return Layout.PORTRAIT
	return Layout.LANDSCAPE


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
