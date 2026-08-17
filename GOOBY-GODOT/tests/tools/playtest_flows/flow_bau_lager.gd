extends "res://tests/tools/playtest_flows/flow_baumodus.gd"
## Flow „Bau-Lager-Runde“: Baumodus öffnen (HUD-Weggleit-Animation
## prüfen), Pflicht-Bett platzieren, dann den Fernsehsessel aus dem Lager
## nehmen → auf freie Zelle → DREHEN (rot 0→1) → platzieren → wieder
## aufnehmen → EINLAGERN → erneut herausnehmen → platzieren → „Fertig“ →
## HUD gleitet zurück. Save/Lager werden ECHT geprüft (kein reiner
## Optik-Test).
## Format: quer 2868x1320 (Leitformat, Default).
## Aufruf: tools/ci/run_playtest.sh flow_bau_lager

const SESSEL_ID := "loungeChair"

var _rot_vorher := -1
## Wohnzimmer stellt per Default-Layout BEREITS einen loungeChair auf —
## der frisch platzierte wird deshalb über seine uid identifiziert.
var _sessel_uids_vorher: Array = []


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_schritte_oeffnen_und_bett())
	liste.append_array(_schritte_sessel_runde())
	liste.append_array(_schritte_fertig())
	return liste


func _schritte_oeffnen_und_bett() -> Array[Dictionary]:
	return [
		{
			"name": "baumodus_oeffnen",
			"aktion": "tipp_name",
			"node": "BtnBau",
			"erwarte": {"text": "Fertig"},
			"timeout_s": 45.0,
		},
		{"name": "hud_gleitet_weg", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "hud_weg_pruefen",
			"aktion": "warte_bis",
			"bedingung": hud_weggeglitten,
			"timeout_s": 10.0,
			"erwartung": "HUD-Teile sind nach dem Weggleiten unsichtbar + gesperrt",
		},
		{
			"name": "bett_aus_lager",
			"aktion": "tipp_falls_da",
			"text": "Kuschelbett",
			"timeout_s": 10.0,
			"pflicht": false,
		},
		{"name": "bett_ghost_da", "aktion": "warte_bis", "text": "Platzieren", "timeout_s": 20.0},
		{
			"name": "bett_auf_zelle",
			"aktion": "tipp_pos",
			"pos_funktion": ziel_canvas_pos,
			"erwarte": {"bedingung": ghost_platzierbar},
			"timeout_s": 15.0,
		},
		{"name": "bett_platzieren", "aktion": "tipp_text", "text": "Platzieren", "timeout_s": 15.0},
		{
			"name": "bett_im_save",
			"aktion": "warte_bis",
			"bedingung": bett_platziert,
			"timeout_s": 25.0,
		},
	]


func _schritte_sessel_runde() -> Array[Dictionary]:
	return [
		{"name": "sessel_uids_merken", "aktion": "tue", "funktion": merke_sessel_uids},
		{
			"name": "sessel_aus_lager",
			"aktion": "tipp_text",
			"text": "Fernsehsessel",
			"erwarte": {"bedingung": sessel_ghost_neu},
			"timeout_s": 15.0,
		},
		{
			"name": "sessel_auf_zelle",
			"aktion": "tipp_pos",
			"pos_funktion": ziel_canvas_pos,
			"erwarte": {"bedingung": ghost_platzierbar},
			"timeout_s": 15.0,
		},
		{"name": "rot_merken", "aktion": "tue", "funktion": merke_rot},
		# W21 P2: „Drehen“ ist ein Icon-Chip ohne Text — Tap per Node-Name.
		{
			"name": "sessel_drehen",
			"aktion": "tipp_name",
			"node": "BtnDrehen",
			"erwarte": {"bedingung": rot_gestiegen},
			"timeout_s": 10.0,
		},
		{
			"name": "sessel_platzieren",
			"aktion": "tipp_text",
			"text": "Platzieren",
			"erwarte": {"bedingung": sessel_im_save_gedreht},
			"timeout_s": 20.0,
		},
		{
			"name": "sessel_aufnehmen",
			"aktion": "tipp_pos",
			"pos_funktion": sessel_canvas_pos,
			"erwarte": {"bedingung": ghost_im_move_modus},
			"timeout_s": 15.0,
		},
		{
			"name": "sessel_einlagern",
			"aktion": "tipp_text",
			"text": "Einlagern",
			"erwarte": {"bedingung": sessel_im_lager},
			"timeout_s": 15.0,
		},
		{
			"name": "lager_chip_wieder_da",
			"aktion": "warte_bis",
			"text": "Fernsehsessel",
			"timeout_s": 10.0,
		},
		{
			"name": "sessel_wieder_raus",
			"aktion": "tipp_text",
			"text": "Fernsehsessel",
			"erwarte": {"bedingung": sessel_ghost_neu},
			"timeout_s": 15.0,
		},
		{
			"name": "sessel_zelle_zwei",
			"aktion": "tipp_pos",
			"pos_funktion": ziel_canvas_pos,
			"erwarte": {"bedingung": ghost_platzierbar},
			"timeout_s": 15.0,
		},
		{
			"name": "sessel_platzieren_zwei",
			"aktion": "tipp_text",
			"text": "Platzieren",
			"erwarte": {"bedingung": sessel_im_save},
			"timeout_s": 20.0,
		},
	]


func _schritte_fertig() -> Array[Dictionary]:
	return [
		{
			"name": "baumodus_fertig",
			"aktion": "tipp_text",
			"text": "Fertig",
			"erwarte": {"bedingung": bau_modus_zu},
			"timeout_s": 30.0,
		},
		{"name": "hud_gleitet_zurueck", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "hud_da_pruefen",
			"aktion": "warte_bis",
			"bedingung": hud_wieder_da,
			"timeout_s": 10.0,
			"erwartung": "HUD federt nach dem Baumodus zurück (Knöpfe wieder tippbar)",
		},
		{"name": "abschluss", "aktion": "warte", "sekunden": 1.0},
	]


# ── HUD-Weggleit-Checks (HudSichtbarkeit, G7-P50) ────────────────────────────


func _hud_sichtbarkeit() -> Node:
	return harness.root.find_child("Sichtbarkeit", true, false)


func hud_weggeglitten() -> bool:
	var btn := harness.root.find_child("BtnBau", true, false)
	if not (btn is Control) or (btn as Control).is_visible_in_tree():
		return false
	var sicht := _hud_sichtbarkeit()
	return sicht != null and bool(sicht.call("verdeckt")) and bool(sicht.call("bau_aktiv"))


func hud_wieder_da() -> bool:
	var btn := harness.root.find_child("BtnBau", true, false)
	if not (btn is Control) or not (btn as Control).is_visible_in_tree():
		return false
	var sicht := _hud_sichtbarkeit()
	return sicht != null and not bool(sicht.call("verdeckt"))


# ── Ghost-/Save-/Lager-Checks ────────────────────────────────────────────────


func _ghost_zustand() -> Dictionary:
	var bm := _build_mode()
	if bm == null:
		return {}
	var ghost: Variant = bm.get("_ghost_state")
	return ghost if ghost is Dictionary else {}


func sessel_ghost_neu() -> bool:
	var ghost := _ghost_zustand()
	if ghost.is_empty() or str(ghost.get("mode", "")) != "new":
		return false
	return str((ghost.get("def", {}) as Dictionary).get("id", "")) == SESSEL_ID


func ghost_im_move_modus() -> bool:
	var ghost := _ghost_zustand()
	return not ghost.is_empty() and str(ghost.get("mode", "")) == "move"


func merke_rot() -> bool:
	var ghost := _ghost_zustand()
	if ghost.is_empty():
		return false
	_rot_vorher = int(ghost.get("rot", -1))
	return _rot_vorher >= 0


func rot_gestiegen() -> bool:
	var ghost := _ghost_zustand()
	if ghost.is_empty() or _rot_vorher < 0:
		return false
	return int(ghost.get("rot", -1)) == (_rot_vorher + 1) % 4


func _sessel_eintraege() -> Array:
	var gs := game_state()
	if gs == null:
		return []
	var eintraege: Variant = gs.get_value("home.rooms.living.items", [])
	if not (eintraege is Array):
		return []
	var treffer: Array = []
	for eintrag: Variant in eintraege:
		if eintrag is Dictionary and str((eintrag as Dictionary).get("item", "")) == SESSEL_ID:
			treffer.append(eintrag)
	return treffer


func merke_sessel_uids() -> bool:
	_sessel_uids_vorher = []
	for eintrag: Dictionary in _sessel_eintraege():
		_sessel_uids_vorher.append(str(eintrag.get("uid", "")))
	return true


## Der FRISCH platzierte Sessel (uid war vor dem Lager-Griff nicht im Save).
func _sessel_neu_eintrag() -> Dictionary:
	for eintrag: Dictionary in _sessel_eintraege():
		if not _sessel_uids_vorher.has(str(eintrag.get("uid", ""))):
			return eintrag
	return {}


func sessel_im_save() -> bool:
	return not _sessel_neu_eintrag().is_empty()


func sessel_im_save_gedreht() -> bool:
	var eintrag := _sessel_neu_eintrag()
	return not eintrag.is_empty() and int(eintrag.get("rot", -1)) == 1


func sessel_im_lager() -> bool:
	var gs := game_state()
	if gs == null or sessel_im_save():
		return false
	for eintrag: Variant in HomeState.storage(gs):
		if eintrag is Dictionary and str((eintrag as Dictionary).get("item", "")) == SESSEL_ID:
			return int((eintrag as Dictionary).get("count", 0)) >= 1
	return false


## Bildschirmpunkt der Mitte des FRISCH platzierten Sessels (Wieder-Aufnehmen).
func sessel_canvas_pos() -> Vector2:
	var szene := aktuelle_szene()
	var eintrag := _sessel_neu_eintrag()
	if szene == null or eintrag.is_empty():
		return Vector2(1280, 720) * 0.5
	var at_raw: Array = eintrag.get("at", [0, 0])
	var at := Vector2i(int(at_raw[0]), int(at_raw[1]))
	var fp := GridData.rotated_footprint(Vector2i(2, 2), int(eintrag.get("rot", 0)))
	return _zelle_canvas(szene, at + fp / 2)
