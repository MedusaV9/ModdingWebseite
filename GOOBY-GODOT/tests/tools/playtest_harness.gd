extends SceneTree
## PLAYTEST-HARNESS (G7-P58, KEIN Test — kein test_-Präfix): spielt das ECHTE
## Spiel (res://scripts/boot/main.tscn, kompletter Boot inkl. Cover/Onboarding)
## in einer eigenen Instanz wie ein Spieler — synthetische Taps/Wische/Halten,
## Screenshot nach JEDEM Schritt, Hänger-Erkennung per Schritt-Timeout und ein
## strukturierter Bug-Report als Markdown.
##
## ── Aufruf (bequem, empfohlen — Isolation + Log-Auswertung inklusive) ────────
##   tools/ci/run_playtest.sh <flow> [BxH] [lauf-id]
##   z. B.: tools/ci/run_playtest.sh flow_home_basis 2868x1320 lauf07
##
## ── Aufruf (roh, was der Wrapper tut) ────────────────────────────────────────
##   PLAYTEST_FLOW=flow_home_basis PLAYTEST_LAUF=lauf07 \
##   CIWATCH_USER_DATA_ROOT=/tmp/gooby-godot/artifacts/PLAYTEST/lauf07/user-data \
##   tools/ci/run_godot_isolated.sh xvfb-run -a godot --path GOOBY-GODOT \
##     --rendering-method gl_compatibility --rendering-driver opengl3 \
##     --audio-driver Dummy --resolution 2868x1320 \
##     --script res://tests/tools/playtest_harness.gd 2>&1 | tee lauf.log
##
## ── Umgebungsvariablen ───────────────────────────────────────────────────────
##   PLAYTEST_FLOW     Flow-Name in tests/tools/playtest_flows/ (ohne .gd)
##                     oder kompletter res://-Pfad. PFLICHT.
##   PLAYTEST_LAUF     Lauf-Id (Ordnername). Default: <flow>_<zeit>_<pid> —
##                     für PARALLELE Läufe immer eindeutig lassen!
##   PLAYTEST_OUT      Basis-Ordner. Default /tmp/gooby-godot/artifacts/PLAYTEST
##   PLAYTEST_SIZE     Fenster "BxH". Default 2868x1320 (Leitformat quer,
##                     iPhone 17 Pro Max). Hochkant: 1320x2868.
##   PLAYTEST_MAX_SEC  Globaler Watchdog in s (Default 900) — danach bricht der
##                     Lauf ab, Report wird trotzdem geschrieben.
##   PLAYTEST_STOP_BEI_FAIL  "1": nach dem ersten Pflicht-FAIL abbrechen.
##
## ── Einen neuen Flow schreiben ───────────────────────────────────────────────
##   Datei tests/tools/playtest_flows/flow_<name>.gd:
##     extends "res://tests/tools/playtest_flows/flow_basis.gd"
##     func schritte() -> Array[Dictionary]: return [ ...Schritte... ]
##   Ein Schritt ist ein Dictionary:
##     name       Kürzel (Screenshot-/Report-Name, snake_case). PFLICHT.
##     aktion     s. Liste unten. PFLICHT.
##     timeout_s  Zeitlimit (Default 30; Reisen/Boot großzügiger wählen —
##                llvmpipe rendert das Leitformat nur mit wenigen FPS).
##     pflicht    false = FAIL ist nur "auffällig", bricht nie ab (Default true)
##     erwarte    Nachbedingung, auf die nach der Aktion gewartet wird:
##                {"route": "..."} | {"klasse": "..."} | {"text": "..."} |
##                {"name": "..."} | {"weg_klasse"/"weg_text": "..."} |
##                {"bedingung": Callable() -> bool}
##     nebenbei_tipp_klasse  Klassenname, der WÄHREND des Wartens weggetippt
##                wird (z. B. "TapMashOverlay" für den Tür-Steckenbleib-Gag).
##   Aktionen:
##     warte      {"sekunden": float}
##     warte_bis  nur die erwarte-Keys (route/klasse/text/... direkt im Schritt)
##     tipp_text  {"text": String} — sichtbaren Knopf/Label mit Text tippen,
##                wo immer er liegt (Teilstring, Groß/klein egal). GOLD.
##     tipp_name  {"node": String} — Control per Node-Name tippen
##     tipp_falls_da  wie tipp_text/tipp_name, aber ohne Fund trotzdem OK
##                (für optionale Overlays wie den HUD-Coachmark)
##     tipp_pos   {"pos": Vector2} Canvas-Koordinaten, oder {"pos_rel":
##                Vector2(0..1, 0..1)} relativ zur Canvas-Größe
##     tipp_3d    {"node": String} oder {"finder": Callable() -> Node3D},
##                optional {"offset": Vector3} — Weltpunkt wird über die aktive
##                Kamera auf den Schirm projiziert und dort getippt
##     wisch      {"von"/"nach": Vector2} bzw. "von_rel"/"nach_rel" bzw.
##                "von_funktion"/"nach_funktion" (Callable() -> Vector2, wird
##                erst bei Ausführung ausgewertet), {"dauer_s": float}
##     halte      {"pos"/"pos_rel": Vector2, "dauer_s": float} — Drücken+Halten
##     eingabe    {"node": String, "text": String} — LineEdit füllen
##     taste      {"keycode": Key}
##     tue        {"funktion": Callable() -> bool/void} — Freiform (Zustand
##                merken/prüfen); false = FAIL des Schritts
##
## ── Parallel laufen (10 Instanzen) ───────────────────────────────────────────
##   Jeder Lauf braucht (1) eine EIGENE Lauf-Id und (2) ein EIGENES user://
##   (der Wrapper setzt CIWATCH_USER_DATA_ROOT unter den Lauf-Ordner;
##   tools/ci/run_godot_isolated.sh isoliert HOME/XDG komplett). xvfb-run -a
##   vergibt pro Instanz ein eigenes Display. Beispiel:
##     for f in flow_home_basis flow_baumodus flow_arcade; do
##       tools/ci/run_playtest.sh "$f" & done; wait
##
## ── Grenzen (ehrlich bleiben!) ───────────────────────────────────────────────
##   - llvmpipe (Software-GL): kein Urteil über GPU-Postprocessing/Glow/MSAA-
##     Feinheiten und keine Performance-Aussagen — nur Layout/Flow/Logik.
##   - Wenige FPS im Leitformat: Animationen wirken abgehackt, Timeouts
##     großzügig wählen; Schritt-Dauern sind KEINE Spieler-Wartezeiten.
##   - Die Fundgrube neben report.md ist die Godot-Fehlerausgabe (lauf.log,
##     der Wrapper hängt SCRIPT ERROR/WARNING-Auszüge an den Report an).

const STANDARD_OUT := "/tmp/gooby-godot/artifacts/PLAYTEST"
const STANDARD_GROESSE := Vector2i(2868, 1320)
const STANDARD_TIMEOUT_S := 30.0
const STANDARD_MAX_SEC := 900
const FLOW_ORDNER := "res://tests/tools/playtest_flows"
const MAIN_SZENE := "res://scripts/boot/main.tscn"
## Frames zwischen Druck und Loslassen eines Taps (llvmpipe: 1 Frame kann
## ~0,5 s dauern — 3 Frames sind ein sauberer, kurzer Spieler-Tap).
const TAP_FRAMES := 3
## Mindestabstand zwischen zwei Nebenbei-Taps (Tap-Mash-Gag) in ms.
const NEBENBEI_TAKT_MS := 250

var _flow: RefCounted
var _flow_name := ""
var _lauf_id := ""
var _out_dir := ""
var _stop_bei_fail := false
var _max_sec := STANDARD_MAX_SEC
var _start_ms := 0
var _schritt_nr := 0
var _ergebnisse: Array[Dictionary] = []
var _global_timeout := false
var _letzter_nebenbei_ms := 0


func _initialize() -> void:
	_lauf()


func _lauf() -> void:
	await process_frame
	if not _konfiguriere():
		quit(3)
		return
	_start_ms = Time.get_ticks_msec()
	_log("Lauf '%s' startet — Flow %s, Fenster %s" % [_lauf_id, _flow_name, str(root.size)])
	root.add_child((load(MAIN_SZENE) as PackedScene).instantiate())
	var schritte: Array[Dictionary] = _flow.schritte()
	_log("Flow liefert %d Schritte" % schritte.size())
	for schritt in schritte:
		if _global_timeout:
			break
		await _fuehre_aus(schritt)
		if _abbruch_noetig():
			break
	var code := _schreibe_bericht()
	_log("Lauf fertig — Exit %d" % code)
	quit(code)


## Env lesen, Fenster stellen, Ausgabeordner anlegen, Flow instanzieren.
func _konfiguriere() -> bool:
	_flow_name = OS.get_environment("PLAYTEST_FLOW")
	if _flow_name.is_empty():
		push_error("[PLAYTEST] PLAYTEST_FLOW fehlt (z. B. flow_home_basis)")
		return false
	var pfad := _flow_name
	if not pfad.begins_with("res://"):
		pfad = "%s/%s.gd" % [FLOW_ORDNER, _flow_name]
	if not ResourceLoader.exists(pfad):
		push_error("[PLAYTEST] Flow nicht gefunden: %s" % pfad)
		return false
	var skript: GDScript = load(pfad)
	if skript == null or not skript.can_instantiate():
		push_error("[PLAYTEST] Flow lädt nicht (Parse-Fehler?): %s" % pfad)
		return false
	_flow = skript.new()
	_flow.set("harness", self)
	_lauf_id = OS.get_environment("PLAYTEST_LAUF")
	if _lauf_id.is_empty():
		_lauf_id = "%s_%d_%d" % [_flow_name, Time.get_ticks_usec(), OS.get_process_id()]
	var basis := OS.get_environment("PLAYTEST_OUT")
	if basis.is_empty():
		basis = STANDARD_OUT
	_out_dir = "%s/%s" % [basis, _lauf_id]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var max_env := OS.get_environment("PLAYTEST_MAX_SEC")
	if max_env.is_valid_int():
		_max_sec = int(max_env)
	_stop_bei_fail = OS.get_environment("PLAYTEST_STOP_BEI_FAIL") == "1"
	var groesse := STANDARD_GROESSE
	var size_env := OS.get_environment("PLAYTEST_SIZE")
	if size_env.contains("x"):
		var teile := size_env.split("x")
		groesse = Vector2i(int(teile[0]), int(teile[1]))
	DisplayServer.window_set_size(groesse)
	root.size = groesse
	return true


func _abbruch_noetig() -> bool:
	if _ergebnisse.is_empty():
		return false
	var letzter: Dictionary = _ergebnisse[-1]
	return _stop_bei_fail and not bool(letzter["ok"]) and bool(letzter["pflicht"])


func _log(msg: String) -> void:
	print("[PLAYTEST] %s" % msg)


# ── Schritt-Engine ────────────────────────────────────────────────────────────


func _fuehre_aus(schritt: Dictionary) -> void:
	_schritt_nr += 1
	var name := str(schritt.get("name", "schritt"))
	var aktion := str(schritt.get("aktion", ""))
	var t0 := Time.get_ticks_msec()
	_log("SCHRITT %03d BEGINN %s (%s)" % [_schritt_nr, name, aktion])
	var resultat := await _dispatch(schritt, aktion)
	if resultat["ok"] and schritt.has("erwarte"):
		var erfuellt := await _warte_auf_bedingung(schritt["erwarte"], schritt)
		if not erfuellt:
			resultat = {
				"ok": false,
				"erwartung": _bedingung_text(schritt["erwarte"]),
				"beobachtung": "Nachbedingung trat nicht ein (Timeout) — %s" % _zustand_text(),
			}
	var dauer := (Time.get_ticks_msec() - t0) / 1000.0
	var datei := await _screenshot(name, bool(resultat["ok"]))
	var eintrag := {
		"nr": _schritt_nr,
		"name": name,
		"aktion": aktion,
		"ok": bool(resultat["ok"]),
		"pflicht": bool(schritt.get("pflicht", true)),
		"erwartung": str(resultat.get("erwartung", "")),
		"beobachtung": str(resultat.get("beobachtung", "")),
		"dauer_s": dauer,
		"screenshot": datei,
	}
	_ergebnisse.append(eintrag)
	var status := "OK" if eintrag["ok"] else "FAIL"
	_log("SCHRITT %03d ENDE %s -> %s (%.1f s)" % [_schritt_nr, name, status, dauer])
	if not eintrag["ok"]:
		_log("  Erwartung:   %s" % eintrag["erwartung"])
		_log("  Beobachtung: %s" % eintrag["beobachtung"])


func _dispatch(schritt: Dictionary, aktion: String) -> Dictionary:
	var handler: Dictionary = {
		"warte": _aktion_warte,
		"warte_bis": _aktion_warte_bis,
		"tipp_text": _aktion_tipp_control.bind(aktion),
		"tipp_name": _aktion_tipp_control.bind(aktion),
		"tipp_falls_da": _aktion_tipp_control.bind(aktion),
		"tipp_pos": _aktion_tipp_pos,
		"tipp_3d": _aktion_tipp_3d,
		"wisch": _aktion_wisch,
		"halte": _aktion_halte,
		"eingabe": _aktion_eingabe,
		"taste": _aktion_taste,
		"tue": _aktion_tue,
	}
	if not handler.has(aktion):
		var text := "unbekannt: " + aktion
		return {"ok": false, "erwartung": "bekannte Aktion", "beobachtung": text}
	return await (handler[aktion] as Callable).call(schritt)


func _aktion_warte(schritt: Dictionary) -> Dictionary:
	var sekunden := float(schritt.get("sekunden", 1.0))
	var deadline := Time.get_ticks_msec() + int(sekunden * 1000.0)
	while Time.get_ticks_msec() < deadline and not _global_deadline_erreicht():
		_nebenbei_tippen(schritt)
		await process_frame
	return {"ok": true}


func _aktion_warte_bis(schritt: Dictionary) -> Dictionary:
	if await _warte_auf_bedingung(schritt, schritt):
		return {"ok": true}
	return {
		"ok": false,
		"erwartung": _bedingung_text(schritt),
		"beobachtung": "Bedingung trat nicht ein (Timeout) — %s" % _zustand_text(),
	}


func _aktion_tipp_control(schritt: Dictionary, aktion: String) -> Dictionary:
	var text := str(schritt.get("text", ""))
	var node_name := str(schritt.get("node", ""))
	var beschreibung := "Text '%s'" % text if text != "" else "Node '%s'" % node_name
	var timeout_s := float(schritt.get("timeout_s", STANDARD_TIMEOUT_S))
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	var ziel: Control = null
	while ziel == null and Time.get_ticks_msec() < deadline and not _global_deadline_erreicht():
		ziel = _finde_text(root, text) if text != "" else _finde_control(root, node_name)
		if ziel == null:
			_nebenbei_tippen(schritt)
			await process_frame
	if ziel == null:
		if aktion == "tipp_falls_da":
			return {"ok": true, "beobachtung": "%s nicht da — übersprungen" % beschreibung}
		return {
			"ok": false,
			"erwartung": "sichtbares Bedienelement mit %s" % beschreibung,
			"beobachtung": "nicht gefunden — %s" % _zustand_text(),
		}
	await _tippe_canvas(ziel.get_global_rect().get_center())
	return {"ok": true}


func _aktion_tipp_pos(schritt: Dictionary) -> Dictionary:
	await _tippe_canvas(_pos_aus(schritt, "pos"))
	return {"ok": true}


func _aktion_tipp_3d(schritt: Dictionary) -> Dictionary:
	var timeout_s := float(schritt.get("timeout_s", STANDARD_TIMEOUT_S))
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	var ziel: Node3D = null
	while ziel == null and Time.get_ticks_msec() < deadline and not _global_deadline_erreicht():
		ziel = _finde_node3d(schritt)
		if ziel == null:
			await process_frame
	if ziel == null:
		return {
			"ok": false,
			"erwartung": "3D-Ziel %s" % str(schritt.get("node", schritt.get("finder", "?"))),
			"beobachtung": "nicht gefunden — %s" % _zustand_text(),
		}
	var offset: Vector3 = schritt.get("offset", Vector3.ZERO)
	var kamera := root.get_camera_3d()
	if kamera == null:
		return {"ok": false, "erwartung": "aktive 3D-Kamera", "beobachtung": "keine Kamera"}
	var canvas := kamera.unproject_position(ziel.global_position + offset)
	await _tippe_canvas(canvas)
	return {"ok": true}


func _aktion_wisch(schritt: Dictionary) -> Dictionary:
	var von := _pos_aus(schritt, "von")
	var nach := _pos_aus(schritt, "nach")
	var dauer := float(schritt.get("dauer_s", 0.5))
	await _wische(von, nach, dauer)
	return {"ok": true}


func _aktion_halte(schritt: Dictionary) -> Dictionary:
	var pos := _pos_aus(schritt, "pos")
	var dauer := float(schritt.get("dauer_s", 1.0))
	var px := _fenster_px(pos)
	_maus_knopf(px, true)
	var deadline := Time.get_ticks_msec() + int(dauer * 1000.0)
	while Time.get_ticks_msec() < deadline and not _global_deadline_erreicht():
		await process_frame
	_maus_knopf(px, false)
	await _warte_frames(TAP_FRAMES)
	return {"ok": true}


func _aktion_eingabe(schritt: Dictionary) -> Dictionary:
	var node_name := str(schritt.get("node", ""))
	var feld := _finde_control(root, node_name)
	if feld == null or not (feld is LineEdit):
		return {
			"ok": false,
			"erwartung": "sichtbares LineEdit '%s'" % node_name,
			"beobachtung": "nicht gefunden — %s" % _zustand_text(),
		}
	# Erst antippen (Fokus wie ein Spieler), dann Text setzen.
	await _tippe_canvas(feld.get_global_rect().get_center())
	(feld as LineEdit).text = str(schritt.get("text", ""))
	(feld as LineEdit).text_changed.emit((feld as LineEdit).text)
	await _warte_frames(TAP_FRAMES)
	return {"ok": true}


func _aktion_taste(schritt: Dictionary) -> Dictionary:
	var keycode: Key = schritt.get("keycode", KEY_SPACE)
	var runter := InputEventKey.new()
	runter.keycode = keycode
	runter.physical_keycode = keycode
	runter.pressed = true
	Input.parse_input_event(runter)
	var hoch := InputEventKey.new()
	hoch.keycode = keycode
	hoch.physical_keycode = keycode
	hoch.pressed = false
	Input.parse_input_event(hoch)
	await _warte_frames(TAP_FRAMES)
	return {"ok": true}


func _aktion_tue(schritt: Dictionary) -> Dictionary:
	var funktion: Callable = schritt.get("funktion", Callable())
	if not funktion.is_valid():
		return {"ok": false, "erwartung": "gültiges Callable", "beobachtung": "fehlt"}
	var ergebnis: Variant = funktion.call()
	if ergebnis is bool and not ergebnis:
		return {
			"ok": false,
			"erwartung": str(schritt.get("erwartung", "funktion liefert true")),
			"beobachtung": "funktion lieferte false — %s" % _zustand_text(),
		}
	await process_frame
	return {"ok": true}


# ── Bedingungen & Warten ──────────────────────────────────────────────────────


## Wartet, bis die Bedingung aus `quelle` (route/klasse/text/name/weg_*/
## bedingung) erfüllt ist; tippt nebenbei Overlays weg (Tap-Mash-Gag).
func _warte_auf_bedingung(quelle: Dictionary, schritt: Dictionary) -> bool:
	var timeout_s := float(schritt.get("timeout_s", STANDARD_TIMEOUT_S))
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline and not _global_deadline_erreicht():
		if _bedingung_erfuellt(quelle):
			return true
		_nebenbei_tippen(schritt)
		await process_frame
	return _bedingung_erfuellt(quelle)


func _bedingung_erfuellt(quelle: Dictionary) -> bool:
	var erfuellt := false
	if quelle.has("bedingung"):
		var funktion: Callable = quelle["bedingung"]
		erfuellt = funktion.is_valid() and bool(funktion.call())
	elif quelle.has("route"):
		var router := root.get_node_or_null("/root/SceneRouter")
		var ziel := StringName(str(quelle["route"]))
		erfuellt = (router != null and router.get_current_target() == ziel and not router.is_busy())
	elif quelle.has("klasse"):
		erfuellt = _finde_klasse(root, str(quelle["klasse"])) != null
	elif quelle.has("weg_klasse"):
		erfuellt = _finde_klasse(root, str(quelle["weg_klasse"])) == null
	elif quelle.has("text"):
		erfuellt = _finde_text(root, str(quelle["text"])) != null
	elif quelle.has("weg_text"):
		erfuellt = _finde_text(root, str(quelle["weg_text"])) == null
	elif quelle.has("name"):
		erfuellt = _finde_control(root, str(quelle["name"])) != null
	return erfuellt


func _bedingung_text(quelle: Dictionary) -> String:
	for schluessel in ["route", "klasse", "weg_klasse", "text", "weg_text", "name"]:
		if quelle.has(schluessel):
			return "%s = '%s'" % [schluessel, str(quelle[schluessel])]
	if quelle.has("bedingung"):
		return "eigene Bedingung (Callable)"
	return "?"


## Kurzer Ist-Zustand für Fehlermeldungen: Route + oberste sichtbare Screens.
func _zustand_text() -> String:
	var router := root.get_node_or_null("/root/SceneRouter")
	var route := "?"
	if router != null:
		route = str(router.get_current_target())
		if router.is_busy():
			route += " (Router busy)"
	return "Route: %s" % route


## Während eines Wartens Overlays wegtippen (z. B. TapMashOverlay beim
## Tür-Steckenbleib-Gag) — gedrosselt, damit es wie Mashen wirkt.
func _nebenbei_tippen(schritt: Dictionary) -> void:
	var klasse := str(schritt.get("nebenbei_tipp_klasse", ""))
	if klasse.is_empty():
		return
	var jetzt := Time.get_ticks_msec()
	if jetzt - _letzter_nebenbei_ms < NEBENBEI_TAKT_MS:
		return
	var node := _finde_klasse(root, klasse)
	if node == null:
		return
	_letzter_nebenbei_ms = jetzt
	var canvas := _canvas_groesse() * 0.5
	if node is Control:
		canvas = (node as Control).get_global_rect().get_center()
	var px := _fenster_px(canvas)
	_maus_knopf(px, true)
	_maus_knopf(px, false)


func _global_deadline_erreicht() -> bool:
	if _global_timeout:
		return true
	if (Time.get_ticks_msec() - _start_ms) / 1000.0 > float(_max_sec):
		_global_timeout = true
		_log("WATCHDOG: PLAYTEST_MAX_SEC (%d s) erreicht — Lauf wird beendet" % _max_sec)
	return _global_timeout


# ── Eingabe-Synthese (Fenster-Pixel; Projekt emuliert Touch aus Maus) ─────────


## Canvas-Koordinate (stretch=canvas_items) → Fensterpixel. Injizierte Events
## erwarten FENSTER-Pixel, GUI-Rects liegen im Canvas-Raum (verifiziert über
## tools/capture/clips/calibrate.gd — Muster aus clip_driver.ui()).
func _fenster_px(canvas_pos: Vector2) -> Vector2:
	return canvas_pos * (Vector2(root.size) / _canvas_groesse())


func _canvas_groesse() -> Vector2:
	return root.get_visible_rect().size


func _maus_knopf(px: Vector2, gedrueckt: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = gedrueckt
	ev.position = px
	ev.global_position = px
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if gedrueckt else 0
	Input.parse_input_event(ev)


func _maus_bewegung(px: Vector2, rel: Vector2, ziehend: bool) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = px
	ev.global_position = px
	ev.relative = rel
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if ziehend else 0
	Input.parse_input_event(ev)


func _tippe_canvas(canvas_pos: Vector2) -> void:
	var px := _fenster_px(canvas_pos)
	_maus_bewegung(px, Vector2.ZERO, false)
	await _warte_frames(1)
	_maus_knopf(px, true)
	await _warte_frames(TAP_FRAMES)
	_maus_knopf(px, false)
	await _warte_frames(TAP_FRAMES)


## Fingerzug von A nach B (Canvas-Koordinaten) über `dauer` Sekunden —
## drücken, weiche Zwischenbewegungen pro Frame, loslassen.
func _wische(von: Vector2, nach: Vector2, dauer: float) -> void:
	var von_px := _fenster_px(von)
	var nach_px := _fenster_px(nach)
	_maus_knopf(von_px, true)
	var t0 := Time.get_ticks_msec()
	var letzte := von_px
	var k := 0.0
	while k < 1.0 and not _global_deadline_erreicht():
		await process_frame
		k = clampf((Time.get_ticks_msec() - t0) / (maxf(dauer, 0.05) * 1000.0), 0.0, 1.0)
		var eased := k * k * (3.0 - 2.0 * k)
		var pos := von_px.lerp(nach_px, eased)
		_maus_bewegung(pos, pos - letzte, true)
		letzte = pos
	_maus_knopf(letzte, false)
	await _warte_frames(TAP_FRAMES)


func _warte_frames(anzahl: int) -> void:
	for _i in anzahl:
		await process_frame


## Position aus Schritt lesen: "<key>" (Canvas-px), "<key>_rel" (0..1 relativ)
## oder "<key>_funktion" (Callable, erst bei Ausführung ausgewertet).
func _pos_aus(schritt: Dictionary, key: String) -> Vector2:
	if schritt.has(key + "_funktion"):
		var funktion: Callable = schritt[key + "_funktion"]
		return funktion.call()
	if schritt.has(key + "_rel"):
		var rel: Vector2 = schritt[key + "_rel"]
		return rel * _canvas_groesse()
	return schritt.get(key, _canvas_groesse() * 0.5)


# ── Suche im Baum ─────────────────────────────────────────────────────────────


## Sichtbares Bedienelement mit Text finden (Teilstring, Groß/klein egal):
## erst BaseButton.text, dann Labels (deren tippbarer Knopf-Vorfahr gewinnt).
func _finde_text(node: Node, text: String) -> Control:
	var nadel := text.to_lower()
	var label_treffer: Control = null
	var stapel: Array[Node] = [node]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is Control and not (aktuell as Control).is_visible_in_tree():
			continue
		if aktuell is BaseButton:
			var knopf_text := str(aktuell.get("text")).to_lower()
			if knopf_text.contains(nadel) and knopf_text != "":
				return aktuell
		if label_treffer == null and aktuell is Label:
			if (aktuell as Label).text.to_lower().contains(nadel):
				var knopf := _knopf_vorfahr(aktuell)
				label_treffer = knopf if knopf != null else aktuell
		for kind in aktuell.get_children():
			stapel.append(kind)
	return label_treffer


func _knopf_vorfahr(node: Node) -> Control:
	var aktuell := node.get_parent()
	while aktuell != null:
		if aktuell is BaseButton:
			return aktuell
		aktuell = aktuell.get_parent()
	return null


func _finde_control(node: Node, node_name: String) -> Control:
	var treffer := node.find_child(node_name, true, false)
	if treffer is Control and (treffer as Control).is_visible_in_tree():
		return treffer
	return null


## Node per Script-Klassenname finden (sichtbar, falls Control/Node3D).
func _finde_klasse(node: Node, klasse: String) -> Node:
	if node.get_script() != null:
		var skript: Script = node.get_script()
		if skript.get_global_name() == StringName(klasse):
			if node is Control:
				if (node as Control).is_visible_in_tree():
					return node
			elif not (node is Node3D) or (node as Node3D).visible:
				return node
	for kind in node.get_children():
		var gefunden := _finde_klasse(kind, klasse)
		if gefunden != null:
			return gefunden
	return null


func _finde_node3d(schritt: Dictionary) -> Node3D:
	if schritt.has("finder"):
		var funktion: Callable = schritt["finder"]
		var ergebnis: Variant = funktion.call()
		return ergebnis if ergebnis is Node3D else null
	var treffer := root.find_child(str(schritt.get("node", "")), true, false)
	return treffer if treffer is Node3D else null


# ── Screenshots & Bericht ─────────────────────────────────────────────────────


func _screenshot(name: String, ok: bool) -> String:
	await _warte_frames(2)
	var suffix := "" if ok else "_FAIL"
	var datei := "%03d_%s%s.png" % [_schritt_nr, name, suffix]
	var bild := root.get_texture().get_image()
	bild.save_png("%s/%s" % [_out_dir, datei])
	return datei


## Markdown-Report + maschinenlesbares JSON. Exit: 0 = alles ok, 1 = FAILs,
## 2 = globaler Watchdog-Abbruch.
func _schreibe_bericht() -> int:
	var dauer_s := (Time.get_ticks_msec() - _start_ms) / 1000.0
	var fails := 0
	var pflicht_fails := 0
	for e in _ergebnisse:
		if not bool(e["ok"]):
			fails += 1
			if bool(e["pflicht"]):
				pflicht_fails += 1
	var zeilen: Array[String] = []
	zeilen.append("# Playtest-Bericht — %s" % _lauf_id)
	zeilen.append("")
	zeilen.append("- Flow: `%s`" % _flow_name)
	zeilen.append("- Fenster: %s (Canvas %s)" % [str(root.size), str(_canvas_groesse())])
	zeilen.append(
		"- Dauer: %.1f s — Schritte: %d ok / %d fail" % [dauer_s, _ergebnisse.size() - fails, fails]
	)
	if _global_timeout:
		zeilen.append("- **WATCHDOG-ABBRUCH** nach PLAYTEST_MAX_SEC=%d s" % _max_sec)
	zeilen.append("")
	zeilen.append("## Schritte")
	zeilen.append("")
	zeilen.append("| Nr | Schritt | Aktion | Ergebnis | Dauer | Screenshot |")
	zeilen.append("| --- | --- | --- | --- | --- | --- |")
	for e in _ergebnisse:
		(
			zeilen
			. append(
				(
					"| %03d | %s | %s | %s | %.1f s | %s |"
					% [
						int(e["nr"]),
						str(e["name"]),
						str(e["aktion"]),
						"OK" if bool(e["ok"]) else "**FAIL**",
						float(e["dauer_s"]),
						str(e["screenshot"]),
					]
				)
			)
		)
	zeilen.append("")
	zeilen.append("## Befunde (automatisch)")
	zeilen.append("")
	if fails == 0:
		zeilen.append("Keine Schritt-Fehlschläge. Optik-Befunde bitte anhand der")
		zeilen.append("Screenshots ergänzen (die Harness beurteilt keine Schönheit).")
	for e in _ergebnisse:
		if bool(e["ok"]):
			continue
		var grad := "Blocker" if bool(e["pflicht"]) else "Auffällig"
		zeilen.append("### Schritt %03d `%s` — FAIL" % [int(e["nr"]), str(e["name"])])
		zeilen.append("- Erwartung: %s" % str(e["erwartung"]))
		zeilen.append("- Beobachtung: %s" % str(e["beobachtung"]))
		zeilen.append("- Beleg: %s" % str(e["screenshot"]))
		zeilen.append("- Schweregrad (auto): %s — bitte manuell nachschärfen" % grad)
		zeilen.append("")
	zeilen.append("## Log-Auszug")
	zeilen.append("")
	zeilen.append("Der Wrapper (tools/ci/run_playtest.sh) hängt hier die")
	zeilen.append("SCRIPT-ERROR/WARNING-Zeilen aus lauf.log an.")
	var report := FileAccess.open("%s/report.md" % _out_dir, FileAccess.WRITE)
	report.store_string("\n".join(zeilen) + "\n")
	report.flush()
	var json := FileAccess.open("%s/lauf.json" % _out_dir, FileAccess.WRITE)
	(
		json
		. store_string(
			(
				JSON
				. stringify(
					{
						"lauf": _lauf_id,
						"flow": _flow_name,
						"dauer_s": dauer_s,
						"watchdog": _global_timeout,
						"schritte": _ergebnisse,
					},
					"\t"
				)
			)
		)
	)
	json.flush()
	_log("Report: %s/report.md" % _out_dir)
	if _global_timeout:
		return 2
	return 1 if pflicht_fails > 0 else 0
