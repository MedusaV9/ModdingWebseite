extends "res://tests/tools/playtest_flows/flow_basis.gd"
## Flow „Garderobe“: Screen öffnen, Kauf ZU TEUER (Münzen per Staging
## auf 15 gesetzt → Partyhut 120 wird abgelehnt, Münzen unverändert),
## Kauf ERFOLGREICH (Münzen auf 500 → Partyhut gekauft + direkt angelegt,
## Münzen 380), Kategorie-Chips swipen + Tab-Wechsel (Fell), Grid ans
## Scroll-Ende (letzte Karte frei über der Fade-Kante?) und die
## Audit-Frage „Briefkasten am Scroll-Ende sichtbar?“ (Erwartung:
## Briefkasten ist KEINE Garderoben-Kategorie — der Chip darf nirgends
## auftauchen; er gehört zu Gestalten).
## Format: quer 2868x1320 (Leitformat, Default).
## Aufruf: tools/ci/run_playtest.sh flow_garderobe

const HUT_ID := "partyHat"
const HUT_PREIS := 120
const ARM := 15
const REICH := 500
const LETZTER_HUT := "hut_frosch"

var _tab_scroll_vorher := -1.0


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_schritte_kauf())
	liste.append_array(_schritte_chips_und_scroll())
	return liste


func _schritte_kauf() -> Array[Dictionary]:
	return [
		{
			"name": "garderobe_oeffnen",
			"aktion": "tipp_name",
			"node": "BtnWardrobe",
			"erwarte": {"route": "wardrobe"},
			"timeout_s": 45.0,
		},
		{"name": "garderobe_ansehen", "aktion": "warte", "sekunden": 1.5},
		{"name": "muenzen_auf_arm", "aktion": "tue", "funktion": setze_arm},
		{
			"name": "kauf_zu_teuer",
			"aktion": "tipp_name",
			"node": "Item_%s" % HUT_ID,
			"erwarte": {"bedingung": kauf_abgelehnt},
			"timeout_s": 10.0,
			"erwartung": "Partyhut (120) wird bei 15 Münzen abgelehnt (kein Besitz, Münzen gleich)",
		},
		{"name": "ablehnung_ansehen", "aktion": "warte", "sekunden": 1.0},
		{"name": "muenzen_auf_reich", "aktion": "tue", "funktion": setze_reich},
		{
			"name": "kauf_erfolgreich",
			"aktion": "tipp_name",
			"node": "Item_%s" % HUT_ID,
			"erwarte": {"bedingung": kauf_erfolgt},
			"timeout_s": 10.0,
			"erwartung": "Partyhut gekauft + angelegt, Münzen 500-120=380",
		},
		{"name": "kauf_ansehen", "aktion": "warte", "sekunden": 1.0},
	]


func _schritte_chips_und_scroll() -> Array[Dictionary]:
	return [
		{"name": "tab_scroll_merken", "aktion": "tue", "funktion": merke_tab_scroll},
		{
			"name": "chips_swipen",
			"aktion": "wisch",
			"von_funktion": tab_wisch_von,
			"nach_funktion": tab_wisch_nach,
			"dauer_s": 0.5,
		},
		{
			"name": "chips_gescrollt",
			"aktion": "warte_bis",
			"bedingung": chips_gescrollt,
			"timeout_s": 3.0,
			"pflicht": false,
			"erwartung": "Chip-Leiste läuft über und lässt sich swipen (FAIL = kein Überlauf)",
		},
		{
			"name": "tab_fell",
			"aktion": "tipp_name",
			"node": "Tab_fell",
			"erwarte": {"bedingung": tab_ist_fell},
			"timeout_s": 10.0,
		},
		{"name": "fell_ansehen", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "tab_hut_zurueck",
			"aktion": "tipp_name",
			"node": "Tab_hut",
			"erwarte": {"bedingung": tab_ist_hut},
			"timeout_s": 10.0,
		},
		{
			"name": "grid_swipen",
			"aktion": "wisch",
			"von_funktion": grid_wisch_von,
			"nach_funktion": grid_wisch_nach,
			"dauer_s": 0.5,
		},
		{"name": "grid_ans_ende", "aktion": "tue", "funktion": scrolle_grid_ans_ende},
		{"name": "scroll_ende_setzen", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "letzte_karte_frei",
			"aktion": "warte_bis",
			"bedingung": letzte_karte_frei,
			"timeout_s": 5.0,
			"erwartung": "Letzte Hut-Karte liegt am Scroll-Ende komplett im Sichtfenster",
		},
		{
			"name": "befund_briefkasten_in_garderobe",
			"aktion": "warte_bis",
			"bedingung": briefkasten_chip_da,
			"timeout_s": 3.0,
			"pflicht": false,
			"erwartung": "Audit-Frage: „Briefkasten“ in der Garderobe sichtbar? (FAIL = nein)",
		},
		{"name": "abschluss", "aktion": "warte", "sekunden": 1.0},
	]


# ── Kauf-Checks ──────────────────────────────────────────────────────────────


func _screen() -> Node:
	return aktuelle_szene()


func _coins() -> int:
	var gs := game_state()
	return int(gs.get_value("economy.coins", 0)) if gs != null else -1


func _besitzt_hut() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var slice: Variant = gs.get_value("cosmetics", {})
	if not (slice is Dictionary):
		return false
	return CosmeticsState.is_owned(slice as Dictionary, HUT_ID)


func setze_arm() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	gs.set_value("economy.coins", ARM)
	return _coins() == ARM


func setze_reich() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	gs.set_value("economy.coins", REICH)
	return _coins() == REICH


func kauf_abgelehnt() -> bool:
	return not _besitzt_hut() and _coins() == ARM


func kauf_erfolgt() -> bool:
	if not _besitzt_hut() or _coins() != REICH - HUT_PREIS:
		return false
	var gs := game_state()
	var slice: Variant = gs.get_value("cosmetics", {})
	return CosmeticsState.equipped(slice as Dictionary, "hut") == HUT_ID


# ── Chips + Scroll ───────────────────────────────────────────────────────────


func _tab_scroll() -> ScrollContainer:
	var screen := _screen()
	if screen == null:
		return null
	var scroll: Variant = screen.get("_tab_scroll")
	return scroll if scroll is ScrollContainer else null


func _grid_scroll() -> ScrollContainer:
	var screen := _screen()
	if screen == null:
		return null
	var scroll: Variant = screen.get("_grid_scroll")
	return scroll if scroll is ScrollContainer else null


func merke_tab_scroll() -> bool:
	var scroll := _tab_scroll()
	if scroll == null:
		return false
	_tab_scroll_vorher = float(scroll.scroll_horizontal)
	return true


func tab_wisch_von() -> Vector2:
	var scroll := _tab_scroll()
	if scroll == null:
		return Vector2(200.0, 200.0)
	var rect := scroll.get_global_rect()
	return Vector2(rect.position.x + rect.size.x * 0.9, rect.get_center().y)


func tab_wisch_nach() -> Vector2:
	var scroll := _tab_scroll()
	if scroll == null:
		return Vector2(100.0, 200.0)
	var rect := scroll.get_global_rect()
	return Vector2(rect.position.x + rect.size.x * 0.1, rect.get_center().y)


func chips_gescrollt() -> bool:
	var scroll := _tab_scroll()
	return scroll != null and float(scroll.scroll_horizontal) > _tab_scroll_vorher + 1.0


func tab_ist_fell() -> bool:
	var screen := _screen()
	return screen != null and str(screen.get("_tab")) == "fell"


func tab_ist_hut() -> bool:
	var screen := _screen()
	return screen != null and str(screen.get("_tab")) == "hut"


func grid_wisch_von() -> Vector2:
	var scroll := _grid_scroll()
	if scroll == null:
		return Vector2(400.0, 600.0)
	var rect := scroll.get_global_rect()
	return Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.8)


func grid_wisch_nach() -> Vector2:
	var scroll := _grid_scroll()
	if scroll == null:
		return Vector2(400.0, 200.0)
	var rect := scroll.get_global_rect()
	return Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.2)


func scrolle_grid_ans_ende() -> bool:
	var scroll := _grid_scroll()
	if scroll == null:
		return false
	scroll.scroll_vertical = 999999
	return true


## Letzte Hut-Karte (hut_frosch) komplett im Scroll-Sichtfenster?
func letzte_karte_frei() -> bool:
	var karte := harness.root.find_child("Item_%s" % LETZTER_HUT, true, false)
	var scroll := _grid_scroll()
	if not (karte is Control) or scroll == null:
		return false
	var control := karte as Control
	if not control.is_visible_in_tree():
		return false
	var innen := control.get_global_rect()
	var fenster := scroll.get_global_rect()
	return fenster.encloses(innen.grow(-1.0))


## Gibt es IRGENDWO in der Garderobe einen Knopf/Chip „Briefkasten“?
func briefkasten_chip_da() -> bool:
	var stapel: Array[Node] = [harness.root]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is Button and str((aktuell as Button).text).contains("Briefkasten"):
			return (aktuell as Button).is_visible_in_tree()
		for kind in aktuell.get_children():
			stapel.append(kind)
	return false
