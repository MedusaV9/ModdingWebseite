class_name ArcadeSternenbuch
extends RefCounted
## A1 „Arcade-Sternenbuch“ (G8-IDEEN A1): macht die VORHANDENE Meta-
## Progression der 38 Minigames sichtbar — pure Ableitungen aus dem Save
## (minigames.plays + minigames.legacy.beaten/best/bestByDiff, s.
## save_schema.gd), KEIN neues Grind-System. Sterne je Spiel:
##   ★  gespielt (plays > 0)
##   ★★ Ziel auf Normal geschlagen (legacy.beaten[id].normal)
##   ★★★ Ziel auf Schwer (beaten[id].hard — dieselbe Bedingung wie der
##       Endlos-Unlock in MinigameFrameworkLogic.endless_unlocked)
## Meilensteine (10/25/50/80/114 ★) schalten Münz-Belohnungen über den
## bestehenden Economy.award-Pfad frei — idempotent über
## minigames.sternenbuch.claimed (additive Keys überleben
## SaveSchema.merge_defaults, Muster dayCoins/dayCoinsDay). Das Buch füllt
## sich rückwirkend beim ersten Öffnen der Arcade: arcade_screen.gd liest
## Pips/Zähler hier und claimt fällige Meilensteine (Feier: Toast+Konfetti
## über die bestehende ToastLayer-/RewardFx-Schicht).

const Economy := preload("res://scripts/logic/economy.gd")

## Maximal 3 Sterne pro Spiel (gespielt / Normal-Ziel / Schwer-Ziel).
const STERNE_PRO_SPIEL := 3
## Meilenstein-Schwellen (Doc A1: 10/25/50/80/114) + Münz-Belohnungen.
const MEILENSTEINE: Array[int] = [10, 25, 50, 80, 114]
const MEILENSTEIN_COINS := {10: 40, 25: 80, 50: 120, 80: 200, 114: 300}
## Economy-Reason der Meilenstein-Münzen (kein Tages-Ledger — Einmal-Bonus).
const REASON := "arcadeSterne"


## Sterne EINES Spiels deterministisch aus dem Save ableiten (0..3):
## 3 = Schwer-Ziel geschlagen, 2 = Normal-Ziel, 1 = gespielt, 0 = unberührt.
static func sterne_fuer(state: Dictionary, game_id: String) -> int:
	var slice := MinigameFrameworkLogic.difficulty_slice_of(state, game_id)
	var beaten: Dictionary = slice["beaten"]
	if beaten.get("hard", false) == true:
		return 3
	if beaten.get("normal", false) == true:
		return 2
	return 1 if plays_von(state, game_id) > 0 else 0


## Runden-Zähler eines Spiels (minigames.plays[id], fehlertolerant).
static func plays_von(state: Dictionary, game_id: String) -> int:
	var plays: Variant = _dict(_dict(state.get("minigames")).get("plays")).get(game_id)
	if plays is int or plays is float:
		return maxi(0, int(plays))
	return 0


## Gesamtsterne über die spielbaren Registry-Spiele („23“ in „23/114 ★“).
static func gesamt_sterne(state: Dictionary, games: Array[Dictionary]) -> int:
	var summe := 0
	for game: Dictionary in games:
		if bool(game.get("coming_soon", false)):
			continue
		summe += sterne_fuer(state, str(game.get("id", "")))
	return summe


## Maximal erreichbare Sterne: 3 × spielbare Spiele („114“ in „23/114 ★“) —
## wächst automatisch mit, wenn neue Manifest-Spiele landen.
static func max_sterne(games: Array[Dictionary]) -> int:
	var spielbar := 0
	for game: Dictionary in games:
		if not bool(game.get("coming_soon", false)):
			spielbar += 1
	return spielbar * STERNE_PRO_SPIEL


## Bestwert fürs Kachel-Etikett: Maximum über die ZEIT-Modi (Normal-Board +
## easy/hard-Boards). Endlos bleibt draußen — eigenes Punkte-Universum, das
## die Zahl neben dem Ziel-vergleichbaren Bestwert nur verzerren würde.
static func bestwert_fuer(state: Dictionary, game_id: String) -> int:
	var slice := MinigameFrameworkLogic.difficulty_slice_of(state, game_id)
	var best := int(slice["best"])
	var by_diff: Dictionary = slice["bestByDiff"]
	for mode: String in ["easy", "hard"]:
		var wert: Variant = by_diff.get(mode)
		if wert is int or wert is float:
			best = maxi(best, int(wert))
	return maxi(0, best)


## Fällige, noch nicht abgeholte Meilensteine claimen — mutiert `state`,
## also innerhalb von GameState.update aufrufen. Idempotent: `claimed`
## merkt sich jede Schwelle (kein Doppel-Reward, auch nicht rückwirkend).
## Rückgabe {"neu": Array[int], "coins": int, "sterne": int}.
static func claim_meilensteine(
	state: Dictionary, games: Array[Dictionary], now_ms: int
) -> Dictionary:
	var sterne := gesamt_sterne(state, games)
	var claimed := _claimed_slice(state)
	var neu: Array[int] = []
	var coins := 0
	for schwelle: int in MEILENSTEINE:
		if sterne < schwelle or claimed.has(str(schwelle)):
			continue
		claimed[str(schwelle)] = now_ms
		neu.append(schwelle)
		coins += int(MEILENSTEIN_COINS.get(schwelle, 0))
	if coins > 0 and state.get("economy") is Dictionary:
		Economy.award(state["economy"], coins, REASON)
	return {"neu": neu, "coins": coins, "sterne": sterne}


## Additiven claimed-Ast im minigames-Slice sicherstellen (und liefern).
static func _claimed_slice(state: Dictionary) -> Dictionary:
	if not (state.get("minigames") is Dictionary):
		state["minigames"] = {}
	var mg: Dictionary = state["minigames"]
	if not (mg.get("sternenbuch") is Dictionary):
		mg["sternenbuch"] = {}
	var buch: Dictionary = mg["sternenbuch"]
	if not (buch.get("claimed") is Dictionary):
		buch["claimed"] = {}
	return buch["claimed"]


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


## Kleine Sterne-Pips für die Arcade-Kacheln: Vektor-Polygone nach dem
## FeelStarRow-Muster (kein Font-Glyph, kein Bild-Asset), bewusst STATISCH
## (Reduced-Motion-neutral). Größen skalieren über die zentrale UiScale-
## Regel — bei Resize/Rotation misst der Pip sich selbst neu.
class SternPips:
	extends Control

	const SLOTS := 3
	## Design-px (Basis 390×844) — skaliert mit dem UiScale-Faktor.
	const RADIUS := 7.0
	const FILL := Color(1.0, 0.8, 0.2)
	const RIM := Color(0.85, 0.55, 0.1)
	const LEER := Color(0.55, 0.48, 0.42, 0.35)

	var earned := 0
	var _f := 1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_apply_metrics()
		get_viewport().size_changed.connect(_apply_metrics)

	## Verdiente Sterne (0..3) setzen — rein statische Anzeige.
	func setup(sterne: int) -> void:
		earned = clampi(sterne, 0, SLOTS)
		queue_redraw()

	func _apply_metrics() -> void:
		if not is_inside_tree():
			return
		_f = UiScale.for_viewport(get_viewport())
		var radius := RADIUS * _f
		var gap := radius * 0.8
		custom_minimum_size = Vector2(SLOTS * radius * 2.0 + (SLOTS - 1) * gap, radius * 2.4)
		queue_redraw()

	func _draw() -> void:
		var radius := RADIUS * _f
		var gap := radius * 0.8
		var cy := size.y * 0.5
		for i in SLOTS:
			var center := Vector2(radius + float(i) * (radius * 2.0 + gap), cy)
			if i < earned:
				_zeichne_stern(center, radius, FILL, RIM)
			else:
				_zeichne_stern(center, radius * 0.82, Color(0, 0, 0, 0), LEER)

	func _zeichne_stern(center: Vector2, radius: float, fill: Color, rim: Color) -> void:
		var points := PackedVector2Array()
		for i in 10:
			var angle := -PI * 0.5 + TAU * float(i) / 10.0
			var dist := radius if i % 2 == 0 else radius * 0.45
			points.append(center + Vector2(cos(angle), sin(angle)) * dist)
		if fill.a > 0.0:
			draw_colored_polygon(points, fill)
		draw_polyline(points + PackedVector2Array([points[0]]), rim, maxf(radius * 0.16, 1.2))
