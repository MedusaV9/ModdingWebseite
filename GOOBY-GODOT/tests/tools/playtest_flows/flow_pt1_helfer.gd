extends "res://tests/tools/playtest_flows/flow_basis.gd"
## PT-1-Helfer-Schicht (Welle H, G8) — geteilte Sucher/Prüfer für die
## Home/Bau/Füttern/Zuwendungs-Flows (flow_pt1_*). Muster flow_pt2_helfer:
## eigene Schicht wegen gdlint max-public-methods; die konkreten Flows
## erben hiervon und liefern nur noch `schritte()` + Spezial-Helfer.

## Merkzettel für Vorher/Nachher-Vergleiche (merke/wert).
var _zettel: Dictionary = {}

# ---------------------------------------------------------------- Merken


## Wert unter einem Schlüssel notieren (immer true — für tue-Schritte).
func merke(key: String, val: Variant) -> bool:
	_zettel[key] = val
	print("[PT1] merke %s = %s" % [key, str(val)])
	return true


func wert(key: String, fallback: Variant = null) -> Variant:
	return _zettel.get(key, fallback)


## Zahl aus dem GameState lesen (get_value-Pfad, -1 ohne GameState).
func zahl(pfad: String, fallback: float = -1.0) -> float:
	var gs := game_state()
	if gs == null:
		return fallback
	return float(gs.get_value(pfad, fallback))


# ---------------------------------------------------------------- UI-Sucher


## Sichtbares Control mit Node-Namen da? (Für warte_bis-{"bedingung": …} —
## der erwarte-Key "name" kollidiert mit dem Schritt-Namen.)
func control_da(node_name: String) -> bool:
	return _finde_sichtbares_control(harness.root, node_name) != null


func control_weg(node_name: String) -> bool:
	return not control_da(node_name)


## Mitte eines sichtbaren Controls (Vector2.ZERO = nicht gefunden).
func control_mitte(node_name: String) -> Vector2:
	var node := _finde_sichtbares_control(harness.root, node_name)
	if node == null:
		print("[PT1] control_mitte: '%s' nicht sichtbar/gefunden" % node_name)
		return Vector2.ZERO
	return node.get_global_rect().get_center()


## Sichtbares Label/Button mit Text (Teilstring) irgendwo im Baum?
func text_da(text: String) -> bool:
	return _finde_text_control(harness.root, text) != null


## Ist die Mitte des Knopfs mit `text` frei tippbar? Goobys Sprechblasen-
## Kapsel (mouse_filter STOP, folgt dem Kopf) kann Action-Bar-Knöpfe
## überdecken — der Tap schließt dann nur die Blase statt zu drücken
## (Befund pt1_bau_v1, Schritt bett_drehen). Fremde STOP-Controls über
## der Knopfmitte landen mit Namen im Log (Beweis für den Report).
func text_frei(text: String) -> bool:
	var ziel := _finde_knopf_text(harness.root, text)
	if ziel == null:
		return false
	var mitte := ziel.get_global_rect().get_center()
	for stop: Control in _stop_controls_bei(mitte):
		if stop == ziel or stop.is_ancestor_of(ziel) or ziel.is_ancestor_of(stop):
			continue
		print("[PT1] text_frei: '%s' von '%s' überdeckt" % [text, stop.name])
		return false
	return true


# ---------------------------------------------------------------- HUD (P50)


## Weicht das HUD gerade (P50-Verdeckung: Baumodus/Blatt offen)?
func hud_verdeckt() -> bool:
	var hud_node := _finde_klasse(harness.root, "Hud")
	if hud_node == null or not hud_node.has_method("sichtbarkeit"):
		return false
	var sicht: Variant = hud_node.call("sichtbarkeit")
	return sicht != null and bool(sicht.call("verdeckt"))


## HUD wieder da: Zustandsmaschine frei UND der Bau-Knopf tippbar sichtbar.
func hud_zurueck() -> bool:
	return not hud_verdeckt() and control_da("BtnBau")


## HUD wirklich weggeglitten: Zustand verdeckt UND Bau-Knopf unsichtbar.
func hud_weg() -> bool:
	return hud_verdeckt() and not control_da("BtnBau")


# ---------------------------------------------------------------- Möbel


## Möbel-Protokoll eines Raums: loggt Grid-Stand + fehlende Nodes und
## prüft, dass alle `pflicht_ids` WIRKLICH als Node im Raum stehen.
func moebel_protokoll(pflicht_ids: Array) -> bool:
	var szene := aktuelle_szene()
	if szene == null or szene.get("grid") == null:
		print("[PT1] moebel_protokoll: keine Szene/kein Grid")
		return false
	var items: Array = szene.grid.to_items_array()
	var ids: Array[String] = []
	for eintrag: Dictionary in items:
		ids.append(str(eintrag.get("item", "?")))
	print("[PT1] Raum %s: %d Grid-Items: %s" % [str(szene.get("room_id")), items.size(), ids])
	var fehlend := _moebel_fehlende(szene)
	if not fehlend.is_empty():
		print("[PT1] FEHLENDE Möbel-Nodes (weiche Degradation!): %s" % str(fehlend))
	var ok := true
	for pflicht_id: Variant in pflicht_ids:
		var gefunden := finde_moebel(str(pflicht_id)) != null
		print("[PT1] Pflicht-Item %s: %s" % [str(pflicht_id), "DA" if gefunden else "FEHLT"])
		ok = ok and gefunden
	return ok and fehlend.is_empty()


# ---------------------------------------------------------------- Gooby


## GoobyReactions-Runner des aktuellen Raums (null ohne Raum).
func gooby_runner() -> Node:
	var szene := aktuelle_szene()
	return szene.get_node_or_null("GoobyReactions") if szene != null else null


## SeeleRunner unterm Reactions-Runner (Stimmung/Gespräche).
func seele() -> Node:
	var runner := gooby_runner()
	return runner.get_node_or_null("SeeleRunner") if runner != null else null


## Gooby-Node des Raums (RoomBase.gooby()).
func gooby_node() -> Node3D:
	var szene := aktuelle_szene()
	if szene == null or not szene.has_method("gooby"):
		return null
	return szene.gooby()


## Id der gerade inszenierten GoobyFeelings-Emotion ("" = keine).
func feelings_aktuelle() -> String:
	var gooby := gooby_node()
	if gooby == null or not (gooby.get("rig") is Node):
		return ""
	var layer: Variant = (gooby.get("rig") as Node).get_node_or_null("GoobyFeelings")
	if layer == null or not layer.has_method("aktuelle"):
		return ""
	return str(layer.call("aktuelle"))


# ---------------------------------------------------------------- Baumodus


## BuildMode-Node des aktuellen Raums (RoomBase hängt ihn als "BuildMode" an).
func build_mode() -> Node:
	var szene := aktuelle_szene()
	return szene.get_node_or_null("BuildMode") if szene != null else null


## Ghost-Zustand des Baumodus ({} ohne aktiven Ghost).
func ghost_state() -> Dictionary:
	var bm := build_mode()
	if bm == null:
		return {}
	var ghost: Variant = bm.get("_ghost_state")
	return ghost if ghost is Dictionary else {}


## Aktive Bau-Ebene (0=Boden, 1=Wand, 2=Decke; -1 ohne Baumodus).
func bau_ebene() -> int:
	var bm := build_mode()
	if bm == null:
		return -1
	return int(bm.get("_ebene"))


# ---------------------------------------------------------------- Kamera-Pan
# Die Follow-Kamera hängt an Gooby — 3D-Ziele (Türen!) liegen je nach
# Gooby-Position unter HUD-Spalten oder gleich ganz außerhalb des Bildes
# (Befund Lauf pt1_rundgang_v1). Gegenmittel wie ein echter Spieler:
# EIN-Finger-Pan, der das Ziel in die Bildmitte holt, dann erst tippen.


## von_funktion fürs Pan-Wischen: rechnet den Schwenk aus, merkt den
## Endpunkt (_pan_nach) und liefert den Startpunkt. Ohne Ziel/Kamera oder
## freien Startpunkt wird der Wisch zum No-Op auf einem RUHEPUNKT.
## fertig_text: ist dieser Text schon sichtbar (z. B. „Los!“-Karte eines
## früheren Versuchs), wird gar nicht mehr geschwenkt.
func _pan_start(finder: Callable, offset: Vector3, fertig_text: String = "") -> Vector2:
	var kamera := harness.root.get_camera_3d()
	var canvas: Vector2 = harness.root.get_visible_rect().size
	var ruhe := _ruhe_punkt(kamera, canvas)
	_zettel["pan_nach"] = ruhe
	if not fertig_text.is_empty() and text_da(fertig_text):
		print("[PT1] pan: '%s' schon sichtbar — kein Schwenk nötig" % fertig_text)
		return ruhe
	var ziel: Variant = finder.call()
	if not (ziel is Node3D) or kamera == null:
		print("[PT1] pan: kein 3D-Ziel/keine Kamera — Wisch wird No-Op")
		return ruhe
	var punkt := kamera.unproject_position((ziel as Node3D).global_position + offset)
	var delta := canvas * 0.5 - punkt
	if delta.length() < 70.0:
		print("[PT1] pan: Ziel bereits zentral (%s)" % str(punkt))
		return ruhe
	var start := _freier_start_punkt(kamera, canvas)
	if start == Vector2.ZERO:
		print("[PT1] pan: kein freier Startpunkt — Wisch wird No-Op")
		return ruhe
	var ende := start + delta
	ende.x = clampf(ende.x, 30.0, canvas.x - 30.0)
	ende.y = clampf(ende.y, 30.0, canvas.y - 30.0)
	_zettel["pan_nach"] = ende
	print("[PT1] pan: Zielpunkt %s, Wisch %s -> %s" % [str(punkt), str(start), str(ende)])
	return start


func _pan_nach() -> Vector2:
	return wert("pan_nach", Vector2(4.0, 4.0))


## No-Op-„Wisch“-Punkt: Druck+Loslassen ohne Bewegung wirkt wie ein TAP und
## muss darum garantiert folgenlos sein. Lauf v3 bewies die Gefahr: die Ecke
## (4,4) traf die per Raycast unsichtbare Lampen-Tap-Area DURCH die Wand und
## das Lichtschalter-Sheet legte sich über die Tür-Karte. Erste Wahl darum:
## oberer Rand der offenen Tür-Karte (PanelContainer schluckt den Tap, dort
## liegt kein Knopf). Sonst ein geprüft leerer Punkt (kein STOP-Control,
## keine pickbare Area), auf dem ein Tap höchstens den Tür-Skip auslöst.
func _ruhe_punkt(kamera: Camera3D, canvas: Vector2) -> Vector2:
	var karte := _finde_sichtbares_control(harness.root, "TuerConfirm")
	if karte != null:
		var rect := karte.get_global_rect()
		return Vector2(rect.get_center().x, rect.position.y + 12.0)
	if kamera != null:
		var frei := _freier_start_punkt(kamera, canvas)
		if frei != Vector2.ZERO:
			return frei
	return Vector2(4.0, 4.0)


## Tipp-Punkt für den Tür-ZWEITVERSUCH: Nur wenn wirklich noch ein Tür-Tap
## nötig ist, wird die Tür FRISCH unprojiziert — die Follow-Kamera driftet
## nach dem Pan zurück (Manual-Hold ~2,5 s), und ein blinder Tipp auf die
## alte Position traf in Lauf v4 die Status-Kapsel: das Gooby-Status-Sheet
## legte sich über die „Los!“-Karte und die Reise war tot. Steht die Karte
## schon (fertig_text), ist die Tür busy oder der Punkt von UI überdeckt,
## geht der Tap stattdessen auf den sicheren Ruhepunkt.
func _tuer_zweitversuch_punkt(ziel_raum: String, fertig_text: String) -> Vector2:
	var kamera := harness.root.get_camera_3d()
	var canvas: Vector2 = harness.root.get_visible_rect().size
	if not fertig_text.is_empty() and text_da(fertig_text):
		return _ruhe_punkt(kamera, canvas)
	var tuer: Variant = finde_tuer(ziel_raum)
	if not (tuer is Node3D) or kamera == null:
		return _ruhe_punkt(kamera, canvas)
	if (tuer as Node).has_method("is_busy") and bool((tuer as Node).call("is_busy")):
		print("[PT1] zweitversuch: Tür busy (Reise läuft) — Ruhepunkt")
		return _ruhe_punkt(kamera, canvas)
	var punkt := kamera.unproject_position(
		(tuer as Node3D).global_position + Vector3(0.0, 1.0, 0.0)
	)
	punkt.x = clampf(punkt.x, 8.0, canvas.x - 8.0)
	punkt.y = clampf(punkt.y, 8.0, canvas.y - 8.0)
	var stop := _stop_control_bei(punkt)
	if stop != null:
		print(
			"[PT1] zweitversuch: Tür-Punkt %s von '%s' überdeckt — Ruhepunkt" % [punkt, stop.name]
		)
		return _ruhe_punkt(kamera, canvas)
	return punkt


## Schrittgruppe „Kamera-Pan aufs Ziel, dann 3D-Tipp“. Nach dem Wisch darf
## die Kamera kurz einrasten (SMOOTHING-Lerp), der Tipp muss aber VOR dem
## Ablauf des 2,5-s-Manual-Holds passieren — sonst driftet die Kamera
## zurück zu Gooby und die Unprojektion verrutscht mitten im Klick.
func _pan_tipp_3d_schritte(
	prefix: String,
	finder: Callable,
	offset: Vector3,
	erwarte: Dictionary,
	timeout_s: float,
	pflicht := true,
	fertig_text := "",
	nebenbei := ""
) -> Array[Dictionary]:
	return [
		{
			"name": "%s_kamera_pan" % prefix,
			"aktion": "wisch",
			"von_funktion": _pan_start.bind(finder, offset, fertig_text),
			"nach_funktion": _pan_nach,
			"dauer_s": 0.45,
		},
		{"name": "%s_kamera_ruhe" % prefix, "aktion": "warte", "sekunden": 0.35},
		{
			"name": "%s_tippen" % prefix,
			"aktion": "tipp_3d",
			"finder": finder,
			"offset": offset,
			"erwarte": erwarte,
			"timeout_s": timeout_s,
			"pflicht": pflicht,
			"nebenbei_tipp_klasse": nebenbei,
		},
	]


## Tür-Reise MIT Bestätigungskarte (gehärtet nach Lauf v1–v3): Hinweis-Karte
## weg → Pan+Präzisions-Tipp (pflicht:false — Sprechblasen mit mouse_filter
## STOP können den Einzel-Tipp schlucken) → Nachfass-Pan (steht die Karte
## schon, wird er zum sicheren Karten-Ruhepunkt-No-Op) → Zweitversuch-Tipp
## auf die Tür (harmlos bei stehender Karte: der _choice-Guard in
## RoomBase._on_door_tapped schluckt Doppel-Taps) → „Los!“ bestätigen →
## Ankunft. Der TapMashOverlay-Nebenbei-Tipp masht den Klemm-Gag frei.
func _tuer_reise_schritte(prefix: String, ziel_raum: String) -> Array[Dictionary]:
	var finder := finde_tuer.bind(ziel_raum)
	var liste: Array[Dictionary] = [
		{
			"name": "%s_hinweis_schliessen" % prefix,
			"aktion": "tipp_falls_da",
			"node": "WasNunSchliessen",
			"timeout_s": 1.5,
		},
	]
	liste.append_array(
		_pan_tipp_3d_schritte(
			"%s_tuer" % prefix, finder, Vector3(0.0, 1.0, 0.0), {"text": "Los!"}, 8.0, false
		)
	)
	(
		liste
		. append_array(
			[
				{
					"name": "%s_tuer_nachfass_pan" % prefix,
					"aktion": "wisch",
					"von_funktion": _pan_start.bind(finder, Vector3(0.0, 1.0, 0.0), "Los!"),
					"nach_funktion": _pan_nach,
					"dauer_s": 0.45,
				},
				{"name": "%s_tuer_nachfass_ruhe" % prefix, "aktion": "warte", "sekunden": 0.3},
				{
					"name": "%s_tuer_zweitversuch" % prefix,
					"aktion": "tipp_pos",
					"pos_funktion": _tuer_zweitversuch_punkt.bind(ziel_raum, "Los!"),
					"erwarte": {"text": "Los!"},
					"timeout_s": 8.0,
					"pflicht": false,
				},
				{
					"name": "%s_tuer_bestaetigen" % prefix,
					"aktion": "tipp_text",
					"text": "Los!",
					"erwarte": {"route": "home/%s" % ziel_raum},
					"timeout_s": 90.0,
					"nebenbei_tipp_klasse": "TapMashOverlay",
				},
				{"name": "%s_ankommen" % prefix, "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


## Tür-Reise OHNE Karte (AppSettings door_confirmation=false, siehe
## _tuer_confirm_aus) — für Flows, in denen Türnavigation nur Mittel zum
## Zweck ist. Tipp → Reise startet sofort; der Zweitversuch fängt geschluckte
## Erst-Tipps, das warte_bis masht einen etwaigen Klemm-Gag frei.
func _tuer_direkt_schritte(prefix: String, ziel_raum: String) -> Array[Dictionary]:
	var finder := finde_tuer.bind(ziel_raum)
	var route := "home/%s" % ziel_raum
	var liste: Array[Dictionary] = [
		{
			"name": "%s_hinweis_schliessen" % prefix,
			"aktion": "tipp_falls_da",
			"node": "WasNunSchliessen",
			"timeout_s": 1.5,
		},
	]
	liste.append_array(
		_pan_tipp_3d_schritte(
			"%s_tuer" % prefix,
			finder,
			Vector3(0.0, 1.0, 0.0),
			{"route": route},
			25.0,
			false,
			"",
			"TapMashOverlay"
		)
	)
	(
		liste
		. append_array(
			[
				{
					"name": "%s_tuer_zweitversuch" % prefix,
					"aktion": "tipp_pos",
					"pos_funktion": _tuer_zweitversuch_punkt.bind(ziel_raum, ""),
					"erwarte": {"route": route},
					"timeout_s": 25.0,
					"pflicht": false,
					"nebenbei_tipp_klasse": "TapMashOverlay",
				},
				{
					"name": "%s_angekommen" % prefix,
					"aktion": "warte_bis",
					"route": route,
					"timeout_s": 30.0,
					"nebenbei_tipp_klasse": "TapMashOverlay",
				},
				{"name": "%s_ankommen" % prefix, "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


## Startpunkt für den Pan-Finger: weder ein klick-schluckendes Control
## (mouse_filter STOP) noch eine 3D-Tap-Area (Möbel/Tür/Gooby) darunter —
## sonst löst der Wisch-Druck ungewollt Interaktionen aus. Die Kandidaten
## streuen bewusst weit: die Follow-Kamera hält Gooby (samt Tap-Sphäre und
## Sprechblase) meist nahe der Bildmitte.
func _freier_start_punkt(kamera: Camera3D, canvas: Vector2) -> Vector2:
	var kandidaten: Array[Vector2] = [
		Vector2(0.5, 0.62),
		Vector2(0.42, 0.75),
		Vector2(0.58, 0.75),
		Vector2(0.35, 0.55),
		Vector2(0.65, 0.55),
		Vector2(0.5, 0.42),
		Vector2(0.25, 0.68),
		Vector2(0.72, 0.68),
		Vector2(0.2, 0.5),
		Vector2(0.68, 0.4),
		Vector2(0.3, 0.85),
		Vector2(0.62, 0.88),
	]
	for anteil: Vector2 in kandidaten:
		var punkt := canvas * anteil
		if _stop_control_bei(punkt) == null and not _tap_area_unter(kamera, punkt):
			return punkt
	return Vector2.ZERO


func _stop_control_bei(punkt: Vector2) -> Control:
	var treffer := _stop_controls_bei(punkt)
	return null if treffer.is_empty() else treffer[0]


## ALLE sichtbaren STOP-Controls über einem Punkt — wer davon GUI-topmost
## ist, weiß nur der Viewport, darum prüfen Verdeckungs-Checks konservativ
## gegen JEDES fremde Control in der Liste.
func _stop_controls_bei(punkt: Vector2) -> Array[Control]:
	var out: Array[Control] = []
	var stapel: Array[Node] = [harness.root]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is Control:
			var control := aktuell as Control
			if (
				control.is_visible_in_tree()
				and control.mouse_filter == Control.MOUSE_FILTER_STOP
				and control.get_global_rect().has_point(punkt)
			):
				out.append(control)
		for kind in aktuell.get_children():
			stapel.append(kind)
	return out


## Liegt unter dem Bildschirmpunkt eine PICKBARE Area3D (Tap-Zone)?
## Nicht-pickbare Areas (Trigger-Zonen) empfangen keine Taps und werden
## per exclude übersprungen.
func _tap_area_unter(kamera: Camera3D, punkt: Vector2) -> bool:
	var welt := kamera.get_world_3d()
	if welt == null:
		return false
	var von := kamera.project_ray_origin(punkt)
	var params := PhysicsRayQueryParameters3D.create(
		von, von + kamera.project_ray_normal(punkt) * 60.0
	)
	params.collide_with_areas = true
	params.collide_with_bodies = false
	for _i in 4:
		var hit := welt.direct_space_state.intersect_ray(params)
		if hit.is_empty():
			return false
		var collider: Variant = hit.get("collider")
		if collider is CollisionObject3D and (collider as CollisionObject3D).input_ray_pickable:
			return true
		params.exclude = params.exclude + [hit.get("rid")]
	return false


## Schrittgruppe „warte bis Knopf frei, dann tippen“: Wächter gegen Goobys
## Sprechblase über der Action-Bar (s. text_frei). Blasen laufen nach
## dauer_s (3,5 s + Typewriter) von selbst aus — der Wächter wartet das ab,
## statt dass der Tipp die Blase schließt und der Knopf nie feuert.
func _tipp_frei_schritte(
	schritt_name: String, text: String, erwarte: Dictionary, timeout_s: float
) -> Array[Dictionary]:
	var tipp: Dictionary = {
		"name": schritt_name,
		"aktion": "tipp_text",
		"text": text,
		"timeout_s": timeout_s,
	}
	if not erwarte.is_empty():
		tipp["erwarte"] = erwarte
	var liste: Array[Dictionary] = [
		{
			"name": "%s_frei" % schritt_name,
			"aktion": "warte_bis",
			"bedingung": text_frei.bind(text),
			"timeout_s": 12.0,
		},
		tipp,
	]
	return liste


# ---------------------------------------------------------------- Test-Setup


## Random-Events für den Lauf stilllegen: aktives Event verwerfen und alle
## Event-Defs auf fernen Cooldown legen. Grund (Lauf v3): die Klopapier-
## Mumie parkte Gooby mit wander_enabled=false auf dem Küchentisch und ihre
## Tap-Zone fing die Tür-Taps ab — Navigation unmöglich. Die Events selbst
## testet bewusst kein PT-1-Flow; als ERSTER Schritt (vor dem Onboarding-
## Abschluss) greift das VOR dem roll_on_start des Home-Eintritts.
func _events_stilllegen() -> bool:
	var gs := game_state()
	if gs == null:
		print("[PT1] events_stilllegen: kein GameState — übersprungen")
		return true
	var fern := int(Time.get_unix_time_from_system() * 1000.0) + 14 * 24 * 3600 * 1000
	var defs: Array = RandomEventEngine.defs_from_registry()
	gs.update(
		func(s: Dictionary) -> void:
			var slice: Dictionary = s.get("events", {})
			slice["active"] = {}
			var cds: Dictionary = slice.get("cooldowns", {})
			for def: Dictionary in defs:
				cds[str(def.get("id", ""))] = fern
			slice["cooldowns"] = cds
			s["events"] = slice
	)
	print("[PT1] events_stilllegen: %d Event-Defs auf Cooldown gelegt" % defs.size())
	return true


## Tür-Bestätigungskarte global abschalten (AppSettings door_confirmation)
## — macht Türnavigation in Flows deterministischer, deren Testziel NICHT
## die Tür-UX ist. Der Rundgang-Flow testet die Karte weiterhin MIT.
func _tuer_confirm_aus() -> bool:
	var settings := harness.root.get_node_or_null("/root/AppSettings")
	if settings == null:
		print("[PT1] tuer_confirm_aus: kein AppSettings — übersprungen")
		return true
	settings.set_setting("door_confirmation", false)
	print("[PT1] tuer_confirm_aus: Tür-Bestätigung deaktiviert")
	return true


# ---------------------------------------------------------------- privat


## Alle Nodes mit Script-Klassennamen unterhalb der Wurzel (z. B. beide
## KloDusche-Instanzen im Bad — Klo UND Wanne).
func _alle_mit_klasse(wurzel: Node, klasse: String) -> Array[Node]:
	var out: Array[Node] = []
	if wurzel == null:
		return out
	var stapel: Array[Node] = [wurzel]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		var skript: Variant = aktuell.get_script()
		if skript is Script and (skript as Script).get_global_name() == StringName(klasse):
			out.append(aktuell)
		for kind in aktuell.get_children():
			stapel.append(kind)
	return out


## Grid-Einträge des Raums, zu denen KEIN Möbel-Node lebt (weiche
## GLB-Degradation in FurnitureNode → ASSET-ROT-Verdacht).
func _moebel_fehlende(szene: Node) -> Array[String]:
	var out: Array[String] = []
	var moebel: Variant = szene.get("_furniture")
	var vorhanden: Dictionary = moebel if moebel is Dictionary else {}
	for eintrag: Dictionary in szene.grid.to_items_array():
		var uid := str(eintrag.get("uid", ""))
		var node: Variant = vorhanden.get(uid)
		if node == null or not is_instance_valid(node):
			out.append("%s@%s" % [str(eintrag.get("item", "?")), str(eintrag.get("at", "?"))])
	return out


func _finde_sichtbares_control(wurzel: Node, node_name: String) -> Control:
	var stapel: Array[Node] = [wurzel]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is Control and aktuell.name == node_name:
			if (aktuell as Control).is_visible_in_tree():
				return aktuell
		for kind in aktuell.get_children():
			stapel.append(kind)
	return null


## Knopf-Sucher mit BaseButton-Präferenz — MUSS die Wahl der Harness
## (_finde_text) spiegeln, damit text_frei denselben Knopf prüft, den der
## tipp_text-Schritt anschließend drückt (Label „Ebene: Boden“ vs. Chip
## „Boden“!). Gleiche DFS-Reihenfolge (pop_back) wie drüben.
func _finde_knopf_text(wurzel: Node, text: String) -> Control:
	var nadel := text.to_lower()
	var label_treffer: Control = null
	var stapel: Array[Node] = [wurzel]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is Control and not (aktuell as Control).is_visible_in_tree():
			continue
		if aktuell is BaseButton:
			var knopf_text := str(aktuell.get("text")).to_lower()
			if not knopf_text.is_empty() and knopf_text.contains(nadel):
				return aktuell
		if label_treffer == null and aktuell is Label:
			if str(aktuell.get("text")).to_lower().contains(nadel):
				label_treffer = aktuell
		for kind in aktuell.get_children():
			stapel.append(kind)
	return label_treffer


func _finde_text_control(wurzel: Node, text: String) -> Control:
	var nadel := text.to_lower()
	var stapel: Array[Node] = [wurzel]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is Control and not (aktuell as Control).is_visible_in_tree():
			continue
		if aktuell is Label or aktuell is Button:
			var t := str(aktuell.get("text"))
			if not t.is_empty() and t.to_lower().contains(nadel):
				return aktuell
		for kind in aktuell.get_children():
			stapel.append(kind)
	return null


## Node per Script-Klassenname (Muster Harness._finde_klasse).
func _finde_klasse(node: Node, klasse: String) -> Node:
	if node == null:
		return null
	var stapel: Array[Node] = [node]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		var skript: Variant = aktuell.get_script()
		if skript is Script and (skript as Script).get_global_name() == StringName(klasse):
			return aktuell
		for kind in aktuell.get_children():
			stapel.append(kind)
	return null
