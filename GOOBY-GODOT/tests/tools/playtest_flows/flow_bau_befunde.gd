extends "res://tests/tools/playtest_flows/flow_baumodus.gd"
## Befund-Flow „Bau-Audit-Befunde“: Onboarding OHNE die Guide-Tour zu
## schließen, dann Baumodus öffnen und messen: (1) Liegt die Guide-Karte
## über dem Bau-Dock? (2) Spawnt der Bau-Ghost hinter der
## klick-schluckenden Knopfleiste (Grid-Mitte → Bildschirmpunkt unter
## Dock-UI)? (3) Verpufft deshalb ein Drag, der auf dem Ghost-Spawnpunkt
## startet? Die drei Befund-Schritte sind pflicht=false: OK = Befund
## reproduziert, FAIL = an dieser Auflösung nicht reproduziert (beides
## ist ein Ergebnis, kein Harness-Fehler; [W18-BEFUND]-Zeilen im lauf.log
## tragen die Messwerte).
## Format: quer 2868x1320 (Default); Befunde sind auflösungsabhängig —
## optional mit anderem BxH gegenprüfen.
## Aufruf: tools/ci/run_playtest.sh flow_bau_befunde [BxH]

var _ghost_at_vorher := Vector2i(-9999, -9999)


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(_onboarding_ohne_guide_schliessen())
	liste.append_array(_schritte_befunde())
	liste.append_array(_schritte_sauber_beenden())
	return liste


## Wie flow_basis.onboarding_schritte(), aber die Erste-Viertelstunde-Tour
## bleibt OFFEN (der Befund braucht die sichtbare Guide-Karte).
func _onboarding_ohne_guide_schliessen() -> Array[Dictionary]:
	return [
		{
			"name": "boot_bis_onboarding",
			"aktion": "warte_bis",
			"klasse": "OnboardingFlow",
			"timeout_s": 180.0,
		},
		{"name": "name_eingeben", "aktion": "eingabe", "node": "NameEdit", "text": "Pionier"},
		{"name": "welcome_weiter", "aktion": "tipp_name", "node": "WelcomeNext"},
		{
			"name": "spitzname_eingeben",
			"aktion": "eingabe",
			"node": "NicknameEdit",
			"text": "Goobster",
		},
		{"name": "spitzname_weiter", "aktion": "tipp_name", "node": "NicknameNext"},
		{"name": "editor_weiter", "aktion": "tipp_name", "node": "EditorNext"},
		{
			"name": "onboarding_fertig",
			"aktion": "tipp_name",
			"node": "DoneButton",
			"erwarte": {"route": "home/living"},
			"timeout_s": 120.0,
		},
		{"name": "wohnzimmer_ankommen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "tagesbonus_abholen",
			"aktion": "tipp_falls_da",
			"text": "Abholen!",
			"timeout_s": 10.0,
			"pflicht": false,
		},
		{
			"name": "coachmark_wegtippen",
			"aktion": "tipp_falls_da",
			"text": "Alles klar!",
			"timeout_s": 6.0,
			"pflicht": false,
		},
		{
			"name": "guide_karte_da",
			"aktion": "warte_bis",
			"bedingung": guide_karte_sichtbar,
			"timeout_s": 20.0,
			"erwartung": "Guide-Tour-Karte ist nach dem Onboarding sichtbar",
		},
	]


func _schritte_befunde() -> Array[Dictionary]:
	return [
		{
			"name": "baumodus_oeffnen",
			"aktion": "tipp_name",
			"node": "BtnBau",
			"erwarte": {"text": "Fertig"},
			"timeout_s": 45.0,
		},
		{"name": "bau_dock_setzen", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "befund_guide_ueber_dock",
			"aktion": "warte_bis",
			"bedingung": guide_ueberlappt_dock,
			"timeout_s": 5.0,
			"pflicht": false,
			"erwartung": "Audit-Befund: Guide-Karte überlappt das Bau-Dock (OK = reproduziert)",
		},
		{"name": "ueberlappung_protokoll", "aktion": "tue", "funktion": protokolliere_rects},
		# Karte schließen, damit die restlichen Messungen nicht von ihr
		# verfälscht werden (und der Lager-Chip sicher tippbar ist).
		{
			"name": "guide_schliessen",
			"aktion": "tipp_falls_da",
			"node": "GuideBeenden",
			"timeout_s": 8.0,
			"pflicht": false,
		},
		{
			"name": "bett_aus_lager",
			"aktion": "tipp_falls_da",
			"text": "Kuschelbett",
			"timeout_s": 10.0,
			"pflicht": false,
		},
		{"name": "ghost_da", "aktion": "warte_bis", "text": "Platzieren", "timeout_s": 20.0},
		{"name": "ghost_spawn_protokoll", "aktion": "tue", "funktion": protokolliere_ghost_spawn},
		{
			"name": "befund_ghost_hinter_leiste",
			"aktion": "warte_bis",
			"bedingung": ghost_hinter_leiste,
			"timeout_s": 5.0,
			"pflicht": false,
			"erwartung": "Audit-Befund: Ghost-Spawnzelle liegt hinter Dock-UI (OK = reproduziert)",
		},
		{"name": "ghost_at_merken", "aktion": "tue", "funktion": merke_ghost_at},
		{
			"name": "drag_vom_spawn_weg",
			"aktion": "wisch",
			"von_funktion": ghost_canvas_pos,
			"nach_funktion": ziel_canvas_pos,
			"dauer_s": 0.6,
		},
		{
			"name": "befund_drag_verpufft",
			"aktion": "warte_bis",
			"bedingung": drag_verpufft,
			"timeout_s": 3.0,
			"pflicht": false,
			"erwartung": "Audit-Befund: Drag ab Spawnpunkt bewegt den Ghost NICHT (OK = repro)",
		},
	]


func _schritte_sauber_beenden() -> Array[Dictionary]:
	return [
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
		{
			"name": "baumodus_fertig",
			"aktion": "tipp_text",
			"text": "Fertig",
			"erwarte": {"bedingung": bau_modus_zu},
			"timeout_s": 30.0,
		},
		{"name": "abschluss", "aktion": "warte", "sekunden": 1.0},
	]


# ── Guide-Karte vs. Bau-Dock ─────────────────────────────────────────────────


func _guide_karte() -> Control:
	var karte := harness.root.find_child("GuideKarte", true, false)
	return karte if karte is Control else null


func _bau_dock() -> Control:
	var lager := harness.root.find_child("LagerKarte", true, false)
	if lager == null:
		return null
	var dock := lager.get_parent()
	return dock if dock is Control else lager


func guide_karte_sichtbar() -> bool:
	var karte := _guide_karte()
	return karte != null and karte.is_visible_in_tree()


func guide_ueberlappt_dock() -> bool:
	var karte := _guide_karte()
	var dock := _bau_dock()
	if karte == null or dock == null:
		return false
	if not karte.is_visible_in_tree() or not dock.is_visible_in_tree():
		return false
	return karte.get_global_rect().intersects(dock.get_global_rect())


func protokolliere_rects() -> bool:
	var karte := _guide_karte()
	var dock := _bau_dock()
	var karte_rect := karte.get_global_rect() if karte != null else Rect2()
	var dock_rect := dock.get_global_rect() if dock != null else Rect2()
	print(
		(
			"[W18-BEFUND] GuideKarte=%s sichtbar=%s | BauDock=%s | Schnitt=%s"
			% [
				karte_rect,
				karte != null and karte.is_visible_in_tree(),
				dock_rect,
				karte_rect.intersects(dock_rect),
			]
		)
	)
	return true


# ── Ghost-Spawn hinter der Knopfleiste ───────────────────────────────────────


func _ghost_dict() -> Dictionary:
	var bm := _build_mode()
	if bm == null:
		return {}
	var ghost: Variant = bm.get("_ghost_state")
	return ghost if ghost is Dictionary else {}


## Bildschirmpunkt der Footprint-Mitte des aktuellen Ghosts.
func ghost_canvas_pos() -> Vector2:
	var szene := aktuelle_szene()
	var ghost := _ghost_dict()
	if szene == null or ghost.is_empty():
		return Vector2(100.0, 100.0)
	var def: Dictionary = ghost["def"]
	var fp := GridData.rotated_footprint(def["footprint"], int(ghost["rot"]))
	return _zelle_canvas(szene, (ghost["at"] as Vector2i) + fp / 2)


func ghost_hinter_leiste() -> bool:
	var ghost := _ghost_dict()
	if ghost.is_empty():
		return false
	return _ui_verdeckt(ghost_canvas_pos())


func protokolliere_ghost_spawn() -> bool:
	var ghost := _ghost_dict()
	if ghost.is_empty():
		print("[W18-BEFUND] Kein Ghost aktiv — Spawn-Messung entfällt")
		return true
	var punkt := ghost_canvas_pos()
	print(
		(
			"[W18-BEFUND] Ghost-Spawn at=%s canvas=%s ui_verdeckt=%s"
			% [ghost["at"], punkt, _ui_verdeckt(punkt)]
		)
	)
	return true


func merke_ghost_at() -> bool:
	var ghost := _ghost_dict()
	if ghost.is_empty():
		return false
	_ghost_at_vorher = ghost["at"]
	return true


## true = der Drag hat den Ghost NICHT bewegt (Befund reproduziert).
func drag_verpufft() -> bool:
	var ghost := _ghost_dict()
	if ghost.is_empty():
		return false
	return (ghost["at"] as Vector2i) == _ghost_at_vorher
