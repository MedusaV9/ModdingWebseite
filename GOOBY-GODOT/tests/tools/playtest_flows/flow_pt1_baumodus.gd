extends "res://tests/tools/playtest_flows/flow_pt1_helfer.gd"
## Flow PT1 (b) „Baumodus komplett“: Boot → Onboarding → Baumodus öffnen und
## die HUD-Weggleit-Animation (G7-P50) VERIFIZIEREN (Zustandsmaschine
## verdeckt + BtnBau weg) → Kuschelbett aus dem Umzugs-Lager → gültige
## Zelle → DREHEN (rot 0→1) → Platzieren (Save-Check) → Fußmatte nehmen,
## platzieren angesetzt, dann EINLAGERN (Lager-Zähler-Check) → Ebenen-Chips
## Decke/Boden (Kamera-Neigung + Status-Kapsel) → „Fertig“ → HUD federt
## zurück (P50-Rückweg). Aufruf: tools/ci/run_playtest.sh flow_pt1_baumodus
##
## Lektion Lauf v1: die Bett-Quest-Sprechblase (öffnet mit dem Baumodus,
## AcBubble-Kapsel = mouse_filter STOP, folgt Goobys Kopf) schwebte über
## dem Drehen-Knopf — der Tap schloss nur die Blase, der Knopf feuerte nie.
## Darum laufen ALLE Action-Bar-/Chip-Taps über _tipp_frei_schritte.


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = [
		{
			"name": "events_stilllegen",
			"aktion": "tue",
			"funktion": _events_stilllegen,
			"erwartung": "Random-Events liegen für den Lauf auf Cooldown",
		},
	]
	liste.append_array(onboarding_schritte())
	liste.append_array(_oeffnen_schritte())
	liste.append_array(_bett_schritte())
	liste.append_array(_einlagern_schritte())
	liste.append_array(_ebenen_schritte())
	liste.append_array(_schliessen_schritte())
	return liste


# ---------------------------------------------------------------- Abschnitte


## Öffnen + P50-Hinweg: HUD-Teile gleiten raus, Eingaben gesperrt.
func _oeffnen_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "hud_da_vor_bau",
			"aktion": "warte_bis",
			"bedingung": hud_zurueck,
			"timeout_s": 20.0,
		},
		{
			"name": "baumodus_oeffnen",
			"aktion": "tipp_name",
			"node": "BtnBau",
			"erwarte": {"text": "Fertig"},
			"timeout_s": 45.0,
		},
		{
			"name": "hud_p50_weggeglitten",
			"aktion": "warte_bis",
			"bedingung": hud_weg,
			"timeout_s": 15.0,
		},
		{"name": "bau_dock_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "status_kapsel_zeigt_ebene",
			"aktion": "warte_bis",
			"text": "Ebene: Boden",
			"timeout_s": 10.0,
			"pflicht": false,
		},
	]


## Kuschelbett: Lager-Karte → Zelle → Drehen → Platzieren → Save-Check.
## Alle Action-Bar-Taps laufen über _tipp_frei_schritte — in Lauf v1 schob
## sich die Bett-Quest-Sprechblase („Platzier dein Bett!“, Kapsel STOP)
## über den Drehen-Knopf und schluckte den Tap (bett_drehen FAIL).
func _bett_schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = [
		{
			"name": "bett_aus_lager_nehmen",
			"aktion": "tipp_falls_da",
			"text": "Kuschelbett",
			"timeout_s": 12.0,
			"pflicht": false,
		},
		{
			"name": "bett_ghost_aktiv",
			"aktion": "warte_bis",
			"text": "Platzieren",
			"timeout_s": 20.0,
		},
		{
			"name": "bett_auf_freie_zelle",
			"aktion": "tipp_pos",
			"pos_funktion": _ziel_canvas_pos,
			"erwarte": {"bedingung": _ghost_platzierbar},
			"timeout_s": 15.0,
		},
		{"name": "bett_rotation_merken", "aktion": "tue", "funktion": _merke_rotation},
	]
	liste.append_array(
		_tipp_frei_schritte("bett_drehen", "Drehen", {"bedingung": _rotation_gewechselt}, 15.0)
	)
	(
		liste
		. append_array(
			[
				{"name": "bett_gedreht_ansehen", "aktion": "warte", "sekunden": 1.0},
				{
					"name": "bett_nach_drehung_umsetzen",
					"aktion": "tipp_pos",
					"pos_funktion": _ziel_canvas_pos,
					"erwarte": {"bedingung": _ghost_platzierbar},
					"timeout_s": 15.0,
				},
			]
		)
	)
	liste.append_array(_tipp_frei_schritte("bett_platzieren", "Platzieren", {}, 15.0))
	(
		liste
		. append(
			{
				"name": "bett_im_save",
				"aktion": "warte_bis",
				"bedingung": _bett_platziert,
				"timeout_s": 25.0,
				"erwartung": "bedSingle liegt in home.rooms.living.items",
			}
		)
	)
	return liste


## Fußmatte platzieren, WIEDER AUFNEHMEN und EINLAGERN (Einlagern gilt nur
## für aufgenommene Möbel — der Lager-Zähler muss den Roundtrip überleben).
func _einlagern_schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = [
		{"name": "lager_stand_merken", "aktion": "tue", "funktion": _merke_fussmatten},
		{
			"name": "fussmatte_aus_lager",
			"aktion": "tipp_falls_da",
			"text": "Fußmatte",
			"timeout_s": 12.0,
			"pflicht": false,
		},
		{
			"name": "fussmatte_ghost_aktiv",
			"aktion": "warte_bis",
			"text": "Platzieren",
			"timeout_s": 20.0,
		},
		{
			"name": "fussmatte_auf_zelle",
			"aktion": "tipp_pos",
			"pos_funktion": _ziel_canvas_pos,
			"erwarte": {"bedingung": _ghost_platzierbar},
			"timeout_s": 15.0,
		},
	]
	liste.append_array(
		_tipp_frei_schritte(
			"fussmatte_platzieren", "Platzieren", {"bedingung": _matte_im_save}, 20.0
		)
	)
	(
		liste
		. append_array(
			[
				{"name": "fussmatte_liegt", "aktion": "warte", "sekunden": 1.0},
				{
					"name": "fussmatte_wieder_aufnehmen",
					"aktion": "tipp_pos",
					"pos_funktion": _matte_canvas_pos,
					"erwarte": {"bedingung": _ghost_ist_move},
					"timeout_s": 20.0,
				},
			]
		)
	)
	liste.append_array(
		_tipp_frei_schritte(
			"fussmatte_einlagern", "Einlagern", {"bedingung": _fussmatte_wieder_im_lager}, 20.0
		)
	)
	return liste


## Ebenen-Umschalter: Decke (Kamera neigt, Overlay hebt) und zurück.
func _ebenen_schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = _tipp_frei_schritte(
		"ebene_decke_waehlen", "Decke", {"bedingung": _ebene_ist_decke}, 15.0
	)
	(
		liste
		. append_array(
			[
				{"name": "decken_blick_ansehen", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "decken_status_kapsel",
					"aktion": "warte_bis",
					"text": "Ebene: Decke",
					"timeout_s": 10.0,
					"pflicht": false,
				},
			]
		)
	)
	liste.append_array(
		_tipp_frei_schritte("ebene_boden_zurueck", "Boden", {"bedingung": _ebene_ist_boden}, 15.0)
	)
	return liste


## Schließen + P50-Rückweg: HUD federt zurück, Knöpfe wieder tippbar.
func _schliessen_schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = _tipp_frei_schritte(
		"baumodus_fertig", "Fertig", {"bedingung": _bau_modus_zu}, 30.0
	)
	(
		liste
		. append_array(
			[
				{
					"name": "hud_p50_zurueckgefedert",
					"aktion": "warte_bis",
					"bedingung": hud_zurueck,
					"timeout_s": 15.0,
				},
				{"name": "abschluss_wohnzimmer", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


# ---------------------------------------------------------------- Bedingungen


## Zielpunkt: gültige freie Zelle nahe der Raummitte, deren Schirmpunkt
## nicht von klick-schluckender UI verdeckt ist (Muster flow_baumodus —
## hier zusätzlich rotationsbewusst, weil wir vor dem Platzieren drehen).
func _ziel_canvas_pos() -> Vector2:
	var bm := build_mode()
	var szene := aktuelle_szene()
	if bm == null or szene == null:
		return Vector2(1280, 720) * 0.5
	var ghost := ghost_state()
	if ghost.is_empty():
		return Vector2(1280, 720) * 0.5
	var def: Dictionary = ghost["def"]
	var rot := int(ghost.get("rot", 0))
	var grid: Object = szene.get("grid")
	var fp: Vector2i = def["footprint"]
	if rot % 2 == 1:
		fp = Vector2i(fp.y, fp.x)
	var mitte := Vector2(grid.size) * 0.5
	var beste_punkt := Vector2(-1.0, -1.0)
	var beste_d := 1.0e9
	for y in int(grid.size.y):
		for x in int(grid.size.x):
			var at := Vector2i(x, y)
			var d: float = Vector2(at).distance_to(mitte)
			if d <= 1.5 or d >= beste_d:
				continue
			if not bool(grid.can_place(def, at, rot, str(ghost.get("uid", "")))["ok"]):
				continue
			var punkt := _zelle_canvas(szene, at + fp / 2)
			if _ui_verdeckt(punkt):
				continue
			beste_d = d
			beste_punkt = punkt
	if beste_punkt.x < 0.0:
		return Vector2(1280, 720) * 0.5
	return beste_punkt


## Kann der Ghost an seiner AKTUELLEN Zelle wirklich platziert werden?
func _ghost_platzierbar() -> bool:
	var szene := aktuelle_szene()
	var ghost := ghost_state()
	if szene == null or ghost.is_empty():
		return false
	var grid: Object = szene.get("grid")
	var pruefung: Variant = grid.can_place(
		ghost["def"], ghost["at"], int(ghost["rot"]), str(ghost.get("uid", ""))
	)
	return pruefung is Dictionary and bool((pruefung as Dictionary)["ok"])


func _merke_rotation() -> bool:
	var ghost := ghost_state()
	if ghost.is_empty():
		return false
	return merke("bett_rot", int(ghost["rot"]))


## Der Drehen-Knopf muss die Ghost-Rotation wirklich weiterschalten.
func _rotation_gewechselt() -> bool:
	var ghost := ghost_state()
	if ghost.is_empty():
		return false
	return int(ghost["rot"]) != int(wert("bett_rot", -1))


## Liegt das Kuschelbett nach dem Platzieren wirklich im Wohnzimmer-Save?
func _bett_platziert() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var eintraege: Variant = gs.get_value("home.rooms.living.items", [])
	if not (eintraege is Array):
		return false
	for eintrag: Variant in eintraege:
		if eintrag is Dictionary and str((eintrag as Dictionary).get("item", "")) == "bedSingle":
			return true
	return false


func _merke_fussmatten() -> bool:
	return merke("fussmatten_vorher", _lager_anzahl("rugDoormat"))


## Liegt die frisch platzierte Lager-Fußmatte im Wohnzimmer-Save? (Die
## Default-Matte bei [10,7] zählt nicht — wir suchen einen ZWEITEN Eintrag.)
func _matte_im_save() -> bool:
	return _matte_eintraege().size() >= 2


## Einlagern muss die Fußmatte in den Lager-Bestand zurückbuchen UND den
## zweiten Raum-Eintrag entfernen.
func _fussmatte_wieder_im_lager() -> bool:
	var im_lager := _lager_anzahl("rugDoormat") >= int(wert("fussmatten_vorher", 999))
	return im_lager and _matte_eintraege().size() <= 1


## Aufnahme-Tap: Zellmitte der ZULETZT platzierten Fußmatte am Schirm.
## Nimmt eine Footprint-Zelle OHNE Boden-/Flächen-Item darüber — der
## Baumodus-Tap greift sonst das obere Möbel statt des Teppichs.
func _matte_canvas_pos() -> Vector2:
	var szene := aktuelle_szene()
	var eintraege := _matte_eintraege()
	if szene == null or eintraege.size() < 2:
		return Vector2(1280, 720) * 0.5
	var eintrag: Dictionary = eintraege[-1]
	var at := Vector2i(int(eintrag["at"][0]), int(eintrag["at"][1]))
	var rot := int(eintrag.get("rot", 0))
	var def: Dictionary = FurnitureCatalog.def("rugDoormat")
	var fp: Vector2i = def["footprint"]
	if rot % 2 == 1:
		fp = Vector2i(fp.y, fp.x)
	var grid: Object = szene.get("grid")
	var ziel := at + fp / 2
	for y in fp.y:
		for x in fp.x:
			var zelle := at + Vector2i(x, y)
			var frei_floor: bool = str(grid.item_at(zelle, GridData.Layer.FLOOR)) == ""
			var frei_surface: bool = str(grid.item_at(zelle, GridData.Layer.SURFACE)) == ""
			if frei_floor and frei_surface:
				ziel = zelle
				break
	return _zelle_canvas(szene, ziel)


## Ist der Ghost ein AUFGENOMMENES Möbel (mode "move")? Nur dann gibt es
## den Einlagern-Knopf.
func _ghost_ist_move() -> bool:
	return str(ghost_state().get("mode", "")) == "move"


func _ebene_ist_decke() -> bool:
	return bau_ebene() == 2


func _ebene_ist_boden() -> bool:
	return bau_ebene() == 0


func _bau_modus_zu() -> bool:
	var szene := aktuelle_szene()
	if szene == null or not szene.has_method("is_build_mode_active"):
		return false
	return not bool(szene.call("is_build_mode_active"))


# ---------------------------------------------------------------- privat


## Alle rugDoormat-Einträge des Wohnzimmer-Saves (Reihenfolge = Alter).
func _matte_eintraege() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var gs := game_state()
	if gs == null:
		return out
	var eintraege: Variant = gs.get_value("home.rooms.living.items", [])
	if not (eintraege is Array):
		return out
	for eintrag: Variant in eintraege:
		if eintrag is Dictionary and str((eintrag as Dictionary).get("item", "")) == "rugDoormat":
			out.append(eintrag)
	return out


## Lager-Bestand eines Items (home.storage[] = [{item, variant, count}]).
func _lager_anzahl(item_id: String) -> int:
	var gs := game_state()
	if gs == null:
		return -1
	var lager: Variant = gs.get_value("home.storage", [])
	if not (lager is Array):
		return -1
	var summe := 0
	for eintrag: Variant in lager:
		if eintrag is Dictionary and str((eintrag as Dictionary).get("item", "")) == item_id:
			summe += int((eintrag as Dictionary).get("count", 0))
	return summe


## Schluckt an dieser Canvas-Position ein sichtbares Control den Klick?
func _ui_verdeckt(pos: Vector2) -> bool:
	var stapel: Array[Node] = [harness.root]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is Control:
			var control := aktuell as Control
			if (
				control.is_visible_in_tree()
				and control.mouse_filter == Control.MOUSE_FILTER_STOP
				and control.get_global_rect().has_point(pos)
			):
				return true
		for kind in aktuell.get_children():
			stapel.append(kind)
	return false


## Zellmitte (Boden) → Canvas-Pixel über die aktive (Bau-)Kamera.
func _zelle_canvas(szene: Node, zelle: Vector2i) -> Vector2:
	var lokal: Vector3 = GridData.world_center(zelle, Vector2i.ONE, 0)
	var mount: Node3D = szene.call("grid_mount")
	var welt := mount.to_global(lokal)
	var kamera := harness.root.get_camera_3d()
	if kamera == null:
		return Vector2(1280, 720) * 0.5
	return kamera.unproject_position(welt)
