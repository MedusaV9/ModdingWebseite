extends "res://tests/tools/playtest_flows/flow_pt3_basis.gd"
## PT-3 Flow (a) „Arcade-Rahmen“ (Welle H): Boot → Onboarding → Arcade über
## den HUD-Knopf → Kachel-Grid prüfen (38 Spiele, Zähler-Kapsel, Scrollen)
## → Pregame öffnen/ansehen (Chips, Energie-Zeile, Bestwert) → „‹ Zurück“
## zur Arcade → Teestube WIRKLICH starten (Pregame → Countdown → gießen)
## → Pause-Modal (alle 5 Rahmen-Knöpfe) → „Weiter“ mit RESUME-COUNTDOWN-
## Zentrier-Wache (B4-Fix: Ziffer sitzt auf der SPIELFELD-Mitte) → wieder
## Pause → „Beenden“ zur Arcade → HISTORY-WACHE (G7-Blocker-Fix ec242ee3:
## mg_pregame/mg_host nie in der Router-History) → Arcade-„Zurück“ führt
## nach HAUSE (nicht in eine frische Runde — DIE Blocker-Regression).
## FIX-7: die B1-Scroll-Diagnose ist jetzt ERFOLGS-Erwartung (hart) —
## Kachel-Wisch UND echter Touch-Drag müssen das Grid rollen (DragScroll).
## Aufruf: tools/ci/run_playtest.sh flow_pt3_rahmen


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append_array(
			[
				{
					"name": "arcade_oeffnen",
					"aktion": "tipp_name",
					"node": "BtnArcade",
					"erwarte": {"route": "arcade"},
					"timeout_s": 90.0,
				},
				{"name": "arcade_ansehen", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "kachel_grid_pruefen",
					"aktion": "tue",
					"funktion": kacheln_pruefen,
					"erwartung": "38 Kacheln im Grid + Zähler-Kapsel „38 Spiele“",
				},
				# Umgebungs-Beleg für den Report: Metriken + Safe-Insets
				# (xvfb meldet einen 1280×1024-Screen → Phantom-Insets?).
				{
					"name": "insets_loggen",
					"aktion": "tue",
					"funktion": insets_loggen,
					"pflicht": false,
				},
				{
					"name": "scroll_stand_vorher",
					"aktion": "tue",
					"funktion": scroll_stand.bind("vor dem Wischen"),
					"pflicht": false,
				},
				{
					"name": "grid_runterwischen",
					"aktion": "wisch",
					"von_rel": Vector2(0.5, 0.75),
					"nach_rel": Vector2(0.5, 0.3),
					"dauer_s": 0.6,
				},
				{"name": "grid_unten_ansehen", "aktion": "warte", "sekunden": 1.0},
				# B1-FIX (FIX-7): früher geplanter Diagnose-Soft-Fail —
				# jetzt HARTE Erwartung: der Wisch AUF den Kacheln pannt.
				{
					"name": "wisch_hat_gescrollt",
					"aktion": "tue",
					"funktion": scroll_bewegt,
					"erwartung": "Touch-Wisch bewegt das Arcade-Grid (scroll_vertical > 0)",
				},
				{
					"name": "grid_ans_ende_wischen",
					"aktion": "wisch",
					"von_rel": Vector2(0.5, 0.75),
					"nach_rel": Vector2(0.5, 0.2),
					"dauer_s": 0.6,
				},
				{"name": "grid_ende_ansehen", "aktion": "warte", "sekunden": 1.0},
				{
					"name": "scroll_stand_nach_wisch",
					"aktion": "tue",
					"funktion": scroll_stand.bind("nach 2 Wischern"),
					"pflicht": false,
				},
				# Ursachen-Trennung 1: Wisch in der KACHEL-LÜCKE (kein Button
				# unterm Finger — schlucken die Kachel-Buttons den Drag?).
				{
					"name": "wisch_in_luecke",
					"aktion": "wisch",
					"von_funktion": luecken_punkt.bind(0.8),
					"nach_funktion": luecken_punkt.bind(0.3),
					"dauer_s": 0.6,
				},
				{"name": "luecke_wirken_lassen", "aktion": "warte", "sekunden": 1.0},
				{
					"name": "luecken_wisch_stand",
					"aktion": "tue",
					"funktion": scroll_stand.bind("nach Lücken-Wisch"),
					"pflicht": false,
				},
				# Ursachen-Trennung 2: scrollt wenigstens das MAUSRAD? (Wisch
				# kaputt + Rad ok → Touch-Pan-Problem; beides tot → Container.)
				{
					"name": "rad_scrollen",
					"aktion": "tue",
					"funktion": rad_scrollen,
					"pflicht": false,
				},
				{"name": "rad_wirken_lassen", "aktion": "warte", "sekunden": 1.0},
				{
					"name": "rad_hat_gescrollt",
					"aktion": "tue",
					"funktion": scroll_stand.bind("nach dem Mausrad"),
					"pflicht": false,
				},
				# Ursachen-Trennung 3: ECHTER Touch-Drag (ScreenTouch/-Drag
				# direkt, wie ihn Android/iOS liefern) MITTEN AUF einer
				# Kachel — pannt DAS? (Maus-Emulation vs. Geräte-Realität.)
				{
					"name": "touch_drag_auf_kachel",
					"aktion": "tue",
					"funktion": touch_drag_auf_kachel,
					"pflicht": false,
				},
				{"name": "touch_drag_wirken_lassen", "aktion": "warte", "sekunden": 1.5},
				# B1-FIX (FIX-7): auch der ECHTE Touch-Drag (ScreenTouch/
				# ScreenDrag wie vom OS) MITTEN AUF einer Kachel pannt —
				# Referenz ist der zettel["scroll"]-Stand nach dem Mausrad.
				{
					"name": "touch_drag_hat_gescrollt",
					"aktion": "tue",
					"funktion": touch_drag_hat_gescrollt,
					"erwartung": "echter Touch-Drag auf Kachel rollt das Grid weiter",
				},
				{
					"name": "touch_drag_stand",
					"aktion": "tue",
					"funktion": scroll_stand.bind("nach echtem Touch-Drag"),
					"pflicht": false,
				},
				{
					"name": "zurueck_nach_oben_rollen",
					"aktion": "tue",
					"funktion": anrollen.bind("Tile_teaParty"),
					"pflicht": false,
				},
				{"name": "oben_setzen", "aktion": "warte", "sekunden": 0.8},
				# Route-Erwartung: is_busy() deckt das LoadingVeil mit ab
				# (Text „Spielen!“ wäre schon UNTER dem Veil sichtbar).
				{
					"name": "teestube_ansehen",
					"aktion": "tipp_name",
					"node": "Tile_teaParty",
					"erwarte": {"route": "mg_pregame"},
					"timeout_s": 90.0,
				},
				{"name": "pregame_ansehen", "aktion": "warte", "sekunden": 1.5},
				{
					"name": "pregame_rahmen_pruefen",
					"aktion": "tue",
					"funktion": pregame_pruefen,
					"erwartung": "Chips Leicht/Normal/Schwer, Energie-Zeile, Bestwert",
				},
				# Pregame-Rückweg: „‹ Zurück“ muss sauber zur Arcade führen.
				{
					"name": "pregame_zurueck",
					"aktion": "tipp_text",
					"text": "Zurück",
					"erwarte": {"route": "arcade"},
					"timeout_s": 60.0,
				},
				{
					"name": "history_nach_pregame_sauber",
					"aktion": "tue",
					"funktion": history_sauber,
					"erwartung": "mg_pregame liegt NICHT in der Router-History",
				},
				{
					"name": "teestube_wieder_waehlen",
					"aktion": "tipp_name",
					"node": "Tile_teaParty",
					"erwarte": {"route": "mg_pregame"},
					"timeout_s": 90.0,
				},
				{"name": "pregame_setzen_lassen", "aktion": "warte", "sekunden": 1.0},
				{
					"name": "spiel_starten",
					"aktion": "tipp_text",
					"text": "Spielen!",
					"erwarte": {"route": "mg_host"},
					"timeout_s": 120.0,
				},
				{
					"name": "countdown_abwarten",
					"aktion": "warte_bis",
					"bedingung": runde_laeuft,
					"timeout_s": 90.0,
				},
				{
					"name": "giessen_1",
					"aktion": "halte",
					"pos_funktion": spiel_punkt_rel.bind(Vector2(0.5, 0.62)),
					"dauer_s": 1.2,
				},
				{
					"name": "giessen_2",
					"aktion": "halte",
					"pos_funktion": spiel_punkt_rel.bind(Vector2(0.5, 0.62)),
					"dauer_s": 0.8,
				},
				{
					"name": "pause_oeffnen",
					"aktion": "tipp_text",
					"text": "Pause",
					"erwarte": {"text": "Beenden"},
					"timeout_s": 30.0,
				},
				{
					"name": "pause_rahmen_pruefen",
					"aktion": "tue",
					"funktion": pause_modal_pruefen,
					"erwartung": "Weiter/Neustart/Ton/Hilfe/Beenden alle da (G7-P56)",
				},
				# B4-FIX (FIX-7): „Weiter“ → die Resume-Countdown-Ziffer
				# sitzt auf der SPIELFELD-Mitte (letterboxter Container),
				# nicht auf der Fenster-Mitte (pt3_d2/046: „3“ ragte raus).
				{
					"name": "weiter_tippen",
					"aktion": "tipp_text",
					"text": "Weiter",
					"timeout_s": 30.0,
				},
				{
					"name": "resume_countdown_feldzentriert",
					"aktion": "warte_bis",
					"bedingung": countdown_feld_zentriert,
					"timeout_s": 20.0,
				},
				{
					"name": "resume_laeuft",
					"aktion": "warte_bis",
					"bedingung": spiel_aktiv,
					"timeout_s": 60.0,
				},
				{
					"name": "pause_knopf_wieder_aktiv",
					"aktion": "warte_bis",
					"bedingung": pause_knopf_aktiv,
					"timeout_s": 30.0,
				},
				{
					"name": "pause_wieder_oeffnen",
					"aktion": "tipp_text",
					"text": "Pause",
					"erwarte": {"text": "Beenden"},
					"timeout_s": 30.0,
				},
				{
					"name": "spiel_beenden",
					"aktion": "tipp_text",
					"text": "Beenden",
					"erwarte": {"route": "arcade"},
					"timeout_s": 90.0,
				},
				# DIE Blocker-Regression (Fix ec242ee3): Host/Pregame dürfen
				# nach dem Ausstieg NICHT in der History liegen …
				{
					"name": "history_nach_host_sauber",
					"aktion": "tue",
					"funktion": history_sauber,
					"erwartung": "mg_host/mg_pregame NICHT in der Router-History",
				},
				# … und „Zurück“ führt nach HAUSE statt in eine frische Runde.
				{
					"name": "zurueck_nach_hause",
					"aktion": "tipp_text",
					"text": "Zurück",
					"erwarte": {"route": "home/living"},
					"timeout_s": 120.0,
				},
				{
					"name": "keine_gratis_runde",
					"aktion": "tue",
					"funktion": keine_runde_mehr,
					"erwartung": "kein MinigameHost/Results mehr im Baum",
				},
				{"name": "abschluss_wohnzimmer", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


## Grid-Wache: alle Registry-Spiele haben eine Kachel, die Zähler-Kapsel
## nennt die spielbare Zahl (W14-Kopfzeile).
func kacheln_pruefen() -> bool:
	var erwartet := MinigameRegistry.all_games().size()
	var spielbar := MinigameRegistry.playable().size()
	var kacheln := _zaehle_kacheln(harness.root)
	var zaehler := harness.root.find_child("CountLabel", true, false) as Label
	var zaehler_text := zaehler.text if zaehler != null else "?"
	print(
		(
			"[PT3] Arcade-Grid: %d Kacheln (Registry %d, spielbar %d), Kapsel '%s'"
			% [kacheln, erwartet, spielbar, zaehler_text]
		)
	)
	if kacheln != erwartet:
		return false
	return zaehler != null and zaehler_text.contains(str(spielbar))


## Pregame-Rahmen (G7-P56): Schwierigkeits-Chips, Energie-Zeile, Bestwert
## und der Gooby-Sticker der Lade-Karte (EIN Begleiter durch den Rahmen).
func pregame_pruefen() -> bool:
	var ok := true
	for chip in ["Leicht", "Normal", "Schwer"]:
		if _finde_knopf_mit_text(harness.root, chip) == null:
			print("[PT3] Pregame: Chip '%s' FEHLT" % chip)
			ok = false
	var endlos := _finde_knopf_mit_text(harness.root, "Endlos")
	print(
		(
			"[PT3] Pregame: Endlos-Chip %s (frisch = gesperrt erwartet)"
			% ["da" if endlos != null else "nicht da"]
		)
	)
	for text in ["Kostet", "Bestwert"]:
		if _finde_label_mit_text(harness.root, text) == null:
			print("[PT3] Pregame: Zeile '%s…' FEHLT" % text)
			ok = false
	var sticker := harness.root.find_child("GoobySticker", true, false)
	print("[PT3] Pregame: GoobySticker %s" % ["da" if sticker != null else "FEHLT"])
	return ok and sticker != null


## Pause-Modal-Rahmen (FB3/G7-P56): alle fünf Knöpfe des EINEN Looks.
func pause_modal_pruefen() -> bool:
	var ok := true
	var knoepfe := ["ResumeButton", "RestartButton", "SoundButton", "HelpButton", "QuitButton"]
	for knopf_name: String in knoepfe:
		var knopf := harness.root.find_child(knopf_name, true, false) as Control
		var da := knopf != null and knopf.is_visible_in_tree()
		print("[PT3] Pause-Modal: %s %s" % [knopf_name, "da" if da else "FEHLT"])
		if not da:
			ok = false
	return ok


## Umgebungs-Beleg: UiScale-Metriken + Safe-Insets des Arcade-Screens in
## den Log (der xvfb-Screen 1280×1024 < Fenster 2868×1320 erzeugt über
## get_display_safe_area() PHANTOM-Insets rechts/unten — Report-Beleg).
func insets_loggen() -> bool:
	var m: Dictionary = ScreenShell.metrics(harness.root)
	print(
		(
			"[PT3] Metriken: canvas %s, f %.2f, floor_px %.1f, insets %s"
			% [
				str(m.get("canvas")),
				float(m.get("f")),
				float(m.get("floor_px")),
				str(m.get("insets"))
			]
		)
	)
	return true


## Arcade-ScrollContainer greifen (liegt unter dem ArcadeScreen).
func _arcade_scroller() -> ScrollContainer:
	var screen := _suche_klasse(harness.root, "ArcadeScreen")
	if screen == null:
		return null
	var stapel: Array[Node] = [screen]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is ScrollContainer:
			return aktuell
		for kind in aktuell.get_children():
			stapel.append(kind)
	return null


## Scroll-Stand loggen (immer ok — reiner Beleg-Helfer).
func scroll_stand(etikett: String) -> bool:
	var scroller := _arcade_scroller()
	if scroller == null:
		print("[PT3] Scroll (%s): kein ScrollContainer gefunden" % etikett)
		return true
	var balken := scroller.get_v_scroll_bar()
	print(
		(
			"[PT3] Scroll (%s): scroll_vertical %d, max %.0f, page %.0f"
			% [etikett, scroller.scroll_vertical, balken.max_value, balken.page]
		)
	)
	zettel["scroll"] = scroller.scroll_vertical
	return true


## Hat der Touch-Wisch das Grid bewegt? (scroll_vertical > 0 nach Wisch.)
func scroll_bewegt() -> bool:
	var scroller := _arcade_scroller()
	if scroller == null:
		return false
	print("[PT3] Scroll nach Wisch: scroll_vertical = %d" % scroller.scroll_vertical)
	return scroller.scroll_vertical > 0


## B1-Wache (FIX-7): der echte Touch-Drag auf einer Kachel muss das Grid
## WEITERgerollt haben — Referenz ist zettel["scroll"] (Stand nach dem Rad,
## geschrieben vom scroll_stand-Schritt davor).
func touch_drag_hat_gescrollt() -> bool:
	var scroller := _arcade_scroller()
	if scroller == null:
		return false
	var vorher := int(zettel.get("scroll", -1))
	print(
		(
			"[PT3] Touch-Drag-Wache: scroll_vertical %d (Referenz vorher %d)"
			% [scroller.scroll_vertical, vorher]
		)
	)
	return vorher >= 0 and scroller.scroll_vertical > vorher


## B4-Wache (FIX-7): die sichtbare Countdown-Ziffer sitzt auf der Mitte des
## LETTERBOXTEN Spielfelds (SubViewportContainer), nicht auf der Fenster-
## Mitte — unter den xvfb-Phantom-Insets (B6) liegen die beiden auseinander.
func countdown_feld_zentriert() -> bool:
	if not countdown_sichtbar():
		return false
	var h := host()
	var label := h.get("_countdown_label") as Label
	var feld := h.get("_viewport_container") as Control
	if label == null or feld == null:
		return false
	var label_mitte := label.get_global_rect().get_center()
	var feld_mitte := feld.get_global_rect().get_center()
	var delta := (label_mitte - feld_mitte).abs()
	var zentriert := delta.x <= 3.0 and delta.y <= 3.0
	print(
		(
			"[PT3] Countdown vs Feld-Mitte: Label %s, Feld %s, Δ(%.1f, %.1f) -> %s"
			% [label_mitte, feld_mitte, delta.x, delta.y, "zentriert" if zentriert else "DANEBEN"]
		)
	)
	return zentriert


## Canvas-Punkt in der LÜCKE zwischen Kachel-Spalte 1 und 2 (h_separation
## des GridContainers — dort liegt KEIN Button) auf Höhe y_rel im Scroller.
func luecken_punkt(y_rel: float) -> Vector2:
	var scroller := _arcade_scroller()
	if scroller == null:
		return Vector2.ZERO
	var kachel_1 := harness.root.find_child("Tile_teaParty", true, false) as Control
	if kachel_1 == null:
		return Vector2.ZERO
	var rect := kachel_1.get_global_rect()
	var scroll_rect := scroller.get_global_rect()
	var x := rect.end.x + 8.0
	var y := scroll_rect.position.y + scroll_rect.size.y * clampf(y_rel, 0.05, 0.95)
	print("[PT3] Lücken-Punkt: (%.0f, %.0f)" % [x, y])
	return Vector2(x, y)


## ECHTEN Touch-Drag synthetisieren (InputEventScreenTouch + ScreenDrag in
## Fenster-px, wie vom OS): Start MITTEN auf einer Kachel, 300 Canvas-px
## hoch in 6 Zügen (ein Input-Flush genügt — ScrollContainer summiert
## drag_accum pro EVENT). Klärt, ob das Kachel-Wisch-Problem nur die
## Maus-Emulation der Harness betrifft oder Geräte genauso träfe.
func touch_drag_auf_kachel() -> bool:
	var kachel := _sichtbare_kachel()
	if kachel == null:
		return false
	var faktor: Vector2 = Vector2(harness.root.size) / harness.root.get_visible_rect().size
	var start := kachel.get_global_rect().get_center() * faktor
	var schritt := Vector2(0.0, -300.0 * faktor.y / 6.0)
	var runter := InputEventScreenTouch.new()
	runter.index = 0
	runter.pressed = true
	runter.position = start
	Input.parse_input_event(runter)
	var pos := start
	for i in 6:
		pos += schritt
		var zug := InputEventScreenDrag.new()
		zug.index = 0
		zug.position = pos
		zug.relative = schritt
		Input.parse_input_event(zug)
	var hoch := InputEventScreenTouch.new()
	hoch.index = 0
	hoch.pressed = false
	hoch.position = pos
	Input.parse_input_event(hoch)
	print("[PT3] Touch-Drag: %s -> %s (6 Züge) auf '%s'" % [start, pos, kachel.name])
	return true


## Erste Kachel, deren Mitte GERADE SICHTBAR im Scroller liegt (nach dem
## Rad-Scrollen ist Reihe 1 weggerollt — deren Global-Rect wäre geclippt).
func _sichtbare_kachel() -> Control:
	var scroller := _arcade_scroller()
	if scroller == null:
		return null
	var fenster := scroller.get_global_rect()
	var stapel: Array[Node] = [scroller]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is Button and str(aktuell.name).begins_with("Tile_"):
			var mitte: Vector2 = (aktuell as Control).get_global_rect().get_center()
			if fenster.has_point(mitte):
				return aktuell
		for kind in aktuell.get_children():
			stapel.append(kind)
	return null


## Mausrad-Synthese mitten im Grid (Ursachen-Trennung zum Touch-Wisch).
func rad_scrollen() -> bool:
	var scroller := _arcade_scroller()
	if scroller == null:
		return false
	var mitte := scroller.get_global_rect().get_center()
	var px := mitte * (Vector2(harness.root.size) / harness.root.get_visible_rect().size)
	for i in 6:
		var runter := InputEventMouseButton.new()
		runter.button_index = MOUSE_BUTTON_WHEEL_DOWN
		runter.pressed = true
		runter.position = px
		runter.global_position = px
		runter.factor = 1.0
		Input.parse_input_event(runter)
		var hoch := runter.duplicate() as InputEventMouseButton
		hoch.pressed = false
		Input.parse_input_event(hoch)
	print("[PT3] Mausrad: 6× WHEEL_DOWN bei %s synthetisiert" % str(px))
	return true


## Nach dem Heimweg darf kein Host/Results-Rest mehr leben (die alte
## Gratis-Runden-Farm lief GENAU hier weiter).
func keine_runde_mehr() -> bool:
	var kein_host := host() == null
	var keine_results := not rundenende_da()
	print("[PT3] Nach Heimweg: Host weg=%s, Results weg=%s" % [kein_host, keine_results])
	return kein_host and keine_results


func _zaehle_kacheln(node: Node) -> int:
	var anzahl := 0
	var stapel: Array[Node] = [node]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is Button and str(aktuell.name).begins_with("Tile_"):
			anzahl += 1
		for kind in aktuell.get_children():
			stapel.append(kind)
	return anzahl


func _finde_knopf_mit_text(node: Node, text: String) -> Button:
	var nadel := text.to_lower()
	var stapel: Array[Node] = [node]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is Control and not (aktuell as Control).is_visible_in_tree():
			continue
		if aktuell is Button and str(aktuell.get("text")).to_lower().contains(nadel):
			return aktuell
		for kind in aktuell.get_children():
			stapel.append(kind)
	return null


func _finde_label_mit_text(node: Node, text: String) -> Label:
	var nadel := text.to_lower()
	var stapel: Array[Node] = [node]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is Control and not (aktuell as Control).is_visible_in_tree():
			continue
		if aktuell is Label and (aktuell as Label).text.to_lower().contains(nadel):
			return aktuell
		for kind in aktuell.get_children():
			stapel.append(kind)
	return null
