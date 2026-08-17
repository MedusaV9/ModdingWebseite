extends "res://tests/tools/playtest_flows/flow_basis.gd"
## Flow „Arcade-Wisch“ (W18 Befund B5): Boot → Onboarding → Arcade über den
## HUD-Knopf → Wisch, der AUF einer Kachel startet, scrollt das Grid
## (scroll_vertical wächst) → Rück-Wisch scrollt wieder hoch → Tap auf eine
## spielbare Kachel öffnet weiterhin das Pregame („Spielen!“).
## Format: quer 2868x1320 (Leitformat, Default).
## Aufruf: tools/ci/run_playtest.sh flow_arcade_wisch

var _scroll_vorher := -1.0
var _scroll_gewischt := -1.0


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_schritte_wisch())
	return liste


func _schritte_wisch() -> Array[Dictionary]:
	return [
		{
			"name": "arcade_oeffnen",
			"aktion": "tipp_name",
			"node": "BtnArcade",
			"erwarte": {"route": "arcade"},
			"timeout_s": 60.0,
		},
		{"name": "grid_ansehen", "aktion": "warte", "sekunden": 1.5},
		{"name": "scroll_merken", "aktion": "tue", "funktion": merke_scroll},
		{
			"name": "wisch_ueber_kachel",
			"aktion": "wisch",
			"von_funktion": kachel_wisch_von,
			"nach_funktion": kachel_wisch_nach,
			"dauer_s": 0.5,
			"erwarte": {"bedingung": grid_gescrollt},
			"timeout_s": 10.0,
			"erwartung": "Wisch startet AUF einer Kachel und scrollt das Grid (B5)",
		},
		{"name": "gescrollt_ansehen", "aktion": "warte", "sekunden": 1.0},
		{"name": "wisch_merken", "aktion": "tue", "funktion": merke_scroll_gewischt},
		{
			"name": "wisch_zurueck",
			"aktion": "wisch",
			"von_funktion": wisch_zurueck_von,
			"nach_funktion": wisch_zurueck_nach,
			"dauer_s": 0.5,
			"erwarte": {"bedingung": grid_zurueckgescrollt},
			"timeout_s": 10.0,
			"erwartung": "Rück-Wisch scrollt das Grid wieder nach oben",
		},
		{"name": "oben_ansehen", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "kachel_tippen",
			"aktion": "tipp_pos",
			"pos_funktion": spielbare_kachel_pos,
			"erwarte": {"text": "Spielen!"},
			"timeout_s": 60.0,
			"erwartung": "Tap auf die Kachel öffnet weiterhin das Pregame",
		},
		{"name": "pregame_ansehen", "aktion": "warte", "sekunden": 1.5},
	]


# ── Helfer ───────────────────────────────────────────────────────────────────


func _screen() -> Node:
	return aktuelle_szene()


func _scroll_node() -> ScrollContainer:
	var screen := _screen()
	if screen == null:
		return null
	var scroll: Variant = screen.get("_scroll")
	return scroll if scroll is ScrollContainer else null


## Sichtbare Kachel im Scroll-Sichtfeld — für den Wisch-Start bevorzugt die
## UNTERSTE (Platz nach oben), fürs Tippen die erste SPIELBARE.
func _sichtbare_kachel(nur_spielbar: bool, unterste: bool) -> Control:
	var screen := _screen()
	var scroll := _scroll_node()
	if screen == null or scroll == null:
		return null
	var grid: Variant = screen.get("_grid")
	if not (grid is Node):
		return null
	var sichtfeld := scroll.get_global_rect()
	var treffer: Control = null
	for kind in (grid as Node).get_children():
		if not (kind is Button):
			continue
		var kachel := kind as Button
		if nur_spielbar and kachel.disabled:
			continue
		if not kachel.is_visible_in_tree():
			continue
		if not sichtfeld.has_point(kachel.get_global_rect().get_center()):
			continue
		if not unterste:
			return kachel
		treffer = kachel
	return treffer


func merke_scroll() -> bool:
	var scroll := _scroll_node()
	if scroll == null:
		return false
	_scroll_vorher = float(scroll.scroll_vertical)
	return true


func merke_scroll_gewischt() -> bool:
	var scroll := _scroll_node()
	if scroll == null:
		return false
	_scroll_gewischt = float(scroll.scroll_vertical)
	return true


## Wisch-Start MITTEN AUF der untersten sichtbaren Kachel — genau der
## B5-Fall: der Drag beginnt auf einem Button, nicht in einer Lücke.
func kachel_wisch_von() -> Vector2:
	var kachel := _sichtbare_kachel(false, true)
	if kachel != null:
		return kachel.get_global_rect().get_center()
	var scroll := _scroll_node()
	if scroll != null:
		var rect := scroll.get_global_rect()
		return Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.75)
	return Vector2(800.0, 900.0)


func kachel_wisch_nach() -> Vector2:
	var von := kachel_wisch_von()
	var scroll := _scroll_node()
	var oben := 100.0
	if scroll != null:
		oben = scroll.get_global_rect().position.y + 60.0
	return Vector2(von.x, maxf(oben, von.y - 500.0))


func grid_gescrollt() -> bool:
	var scroll := _scroll_node()
	if scroll == null or _scroll_vorher < 0.0:
		return false
	return float(scroll.scroll_vertical) > _scroll_vorher + 1.0


func wisch_zurueck_von() -> Vector2:
	var scroll := _scroll_node()
	if scroll == null:
		return Vector2(800.0, 300.0)
	var rect := scroll.get_global_rect()
	return Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.25)


func wisch_zurueck_nach() -> Vector2:
	var von := wisch_zurueck_von()
	var scroll := _scroll_node()
	if scroll == null:
		return von + Vector2(0.0, 500.0)
	var rect := scroll.get_global_rect()
	return Vector2(von.x, minf(rect.end.y - 60.0, von.y + 500.0))


func grid_zurueckgescrollt() -> bool:
	var scroll := _scroll_node()
	if scroll == null or _scroll_gewischt < 0.0:
		return false
	return float(scroll.scroll_vertical) < _scroll_gewischt - 1.0


func spielbare_kachel_pos() -> Vector2:
	var kachel := _sichtbare_kachel(true, false)
	if kachel != null:
		return kachel.get_global_rect().get_center()
	return Vector2(400.0, 400.0)
