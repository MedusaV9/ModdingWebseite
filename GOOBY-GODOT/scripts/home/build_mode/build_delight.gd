class_name BuildDelight
extends RefCounted
## W21 P2 — Delight-Helfer des Baumodus (pure/kontextfreie Bausteine, die
## Zeitpunkte steuert BuildMode):
## - platzier_puff(): Papier-Staub-Puff am Bildschirmpunkt des frisch
##   platzierten Möbels (MotionKit.papier_puff auf einem transienten
##   IGNORE-Host — Flöckchen räumen sich selbst ab, der Host folgt nach
##   PUFF_HOST_S). Reduced-Motion-gated; Vertrag: test_w21_bau_welt.
## - zell_sig(): Zell-/Slot-Signatur eines Ghost-Zustands — Basis des
##   leisen ui_tick beim Zellen-Wechsel während des Ziehens.

## Lebensdauer des Platzier-Puff-Hosts (Flöckchen räumen sich selbst ab —
## der Host braucht nur ihre Flugzeit + Luft).
const PUFF_HOST_S := MotionKit.PUFF_S + 0.25
## Host-Kante in Design-px (×f) — klein, der Puff streut ohnehin radial.
const HOST_KANTE := 24.0


## Papier-Staub-Puff am unprojizierten Welt-Punkt. RNG injizierbar (Tests
## seeden deterministisch); hinter der Kamera/ohne Punkt passiert nichts.
static func platzier_puff(
	ui: Control, kamera: Camera3D, welt: Vector3, f: float, rng: RandomNumberGenerator
) -> void:
	if ui == null or not ui.is_inside_tree() or MotionKit.reduced(ui):
		return
	if welt == Vector3.INF or kamera == null or kamera.is_position_behind(welt):
		return
	var host := Control.new()
	host.name = "PlatzierPuff"
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.size = Vector2.ONE * HOST_KANTE * f
	host.position = kamera.unproject_position(welt) - host.size * 0.5
	ui.add_child(host)
	MotionKit.papier_puff(host, MotionKit.PUFF_TEILE, rng)
	ui.get_tree().create_timer(PUFF_HOST_S).timeout.connect(host.queue_free)


## Zell-Signatur eines Ghost-Zustands (Boden-Zelle bzw. Wand+Slot) —
## ändert sie sich während eines Drags, wechselte die Raster-Zelle.
static func zell_sig(state: Dictionary) -> String:
	return "%s|%s|%s" % [state.get("at", ""), state.get("wall", ""), state.get("offset", "")]
