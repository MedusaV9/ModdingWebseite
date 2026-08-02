extends "res://tests/tools/playtest_flows/flow_pt1_helfer.gd"
## Flow PT1 (a) „Haus-Rundgang“: Boot → Onboarding → Wohnzimmer-Möbel prüfen
## + Fernseher an/aus → Küche (Möbelbestand) → zurück → Schlafzimmer
## (Umzugskartons) → Bad (Möbel + ECHTE Dusche im Bottich: rein, abspülen,
## Hygiene +20) → zurück ins Wohnzimmer → GARTEN: ASSET-ROT-Verifikation
## (spawnen treeDefault/treeFat/gardenBench/potLarge wirklich als Nodes?).
## Jede Raum-Station protokolliert Grid-Items vs. echte Möbel-Nodes.
##
## Lektionen aus den Läufen pt1_rundgang_v1/v2 (Details im Report
## docs/playtest/G8-PT1-home-bau.md):
## * Follow-Kamera + HUD-Spalten/“Was nun?“-Karte/Sprechblasen (AcBubble-
##   Kapsel hat mouse_filter STOP!) schlucken einzelne 3D-Tipps → Türen
##   laufen über den gehärteten Baustein _tuer_reise_schritte (Pan +
##   Präzisions-Tipp + Bildmitte-Nachfassen).
## * Wannen-Tap feuert doppelt (emulate_touch_from_mouse + make_tap_area
##   reagiert auf Maus UND Touch) → Dusche startet und „endet“ im selben
##   Tap, Gooby bleibt unsichtbar hinter zugezogenem Vorhang stecken.
##   Der Flow diagnostiziert das (pflicht:false) und rettet Gooby danach.
## * Der „Fernseher aus“-Knopf liegt UNTER der HUD-Aktionsspalte (Quest-
##   Knopf) — Tipp auf die Knopfmitte öffnet die Tagesquests! Der Flow
##   misst die Überdeckung (pflicht:false) und tippt links auf den Knopf.
## * Lauf v3: die zufällige Klopapier-Mumie parkte Gooby (wander aus) und
##   ihre Tap-Zone fraß die Tür-Taps; außerdem traf der (4,4)-No-Op-Wisch
##   die verdeckte Lampen-Tap-Area DURCH die Wand (Lichtschalter-Sheet über
##   der Tür-Karte). Darum: Events vorm Start stilllegen + Ruhepunkt-No-Op.
## Aufruf: tools/ci/run_playtest.sh flow_pt1_haus_rundgang
## (PLAYTEST_MAX_SEC großzügig setzen — 7 Tür-Reisen unter llvmpipe!)


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
	liste.append_array(_wohnzimmer_schritte())
	liste.append_array(_tuer_reise_schritte("kueche", "kitchen"))
	(
		liste
		. append(
			{
				"name": "kueche_moebel_protokoll",
				"aktion": "tue",
				"funktion": moebel_protokoll.bind(["kitchenFridge", "kitchenStove", "table"]),
				"erwartung": "Küchen-Defaults stehen als Möbel-Nodes im Raum",
			}
		)
	)
	liste.append_array(_tuer_reise_schritte("zurueck_wohnzimmer", "living"))
	liste.append_array(_tuer_reise_schritte("schlafzimmer", "bedroom"))
	(
		liste
		. append(
			{
				"name": "schlafzimmer_moebel_protokoll",
				"aktion": "tue",
				"funktion": moebel_protokoll.bind(["boxA", "boxB", "sideTable"]),
				"erwartung": "Umzugskartons + Möbel stehen im Schlafzimmer",
			}
		)
	)
	liste.append_array(_tuer_reise_schritte("bad", "bathroom"))
	liste.append_array(_bad_schritte())
	liste.append_array(_tuer_reise_schritte("bad_zurueck", "bedroom"))
	liste.append_array(_tuer_reise_schritte("wohnzimmer_wieder", "living"))
	liste.append_array(_tuer_reise_schritte("garten", "garden"))
	liste.append_array(_garten_schritte())
	return liste


# ---------------------------------------------------------------- Stationen


## Wohnzimmer: Möbelbestand + Fernseher an (3D-Tap) und aus (echter
## UI-Knopf). Ein zweiter 3D-Tap wäre Zapping und landete in Lauf v1
## versehentlich auf der HUD-Aktionsspalte → Questpanel offen.
func _wohnzimmer_schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = [
		{
			"name": "wohnzimmer_moebel_protokoll",
			"aktion": "tue",
			"funktion": moebel_protokoll.bind(["loungeSofa", "televisionModern", "radio"]),
			"erwartung": "Wohnzimmer-Defaults stehen als Möbel-Nodes im Raum",
		},
		{
			"name": "wohnzimmer_hinweis_schliessen",
			"aktion": "tipp_falls_da",
			"node": "WasNunSchliessen",
			"timeout_s": 2.0,
		},
	]
	liste.append_array(
		_pan_tipp_3d_schritte(
			"fernseher",
			finde_moebel.bind("televisionModern"),
			Vector3(0.0, 0.4, 0.0),
			{"bedingung": _tv_an},
			25.0
		)
	)
	(
		liste
		. append_array(
			[
				{"name": "fernseher_laeuft", "aktion": "warte", "sekunden": 3.0},
				{
					"name": "fernseher_aus_ueberdeckung",
					"aktion": "tue",
					"funktion": _aus_knopf_frei,
					"erwartung": "GobtyAusKnopf liegt NICHT unter der HUD-Aktionsspalte",
					"pflicht": false,
				},
				{
					"name": "fernseher_aus_links_tippen",
					"aktion": "tipp_pos",
					"pos_funktion": _aus_knopf_links,
					"erwarte": {"bedingung": _tv_aus},
					"timeout_s": 15.0,
				},
			]
		)
	)
	return liste


## Bad: Möbelbestand + Dusche im Bottich. Erwartet wird das SOLL-Verhalten
## (Tap 1 = Routine läuft, Tap 2 = abspülen + Hygiene) — die Diagnose- und
## Rettungsschritte dokumentieren das Doppel-Feuer-Fehlverhalten, ohne den
## restlichen Rundgang zu verlieren.
func _bad_schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = [
		{
			"name": "bad_moebel_protokoll",
			"aktion": "tue",
			"funktion": moebel_protokoll.bind(["bathtub", "toilet", "washer"]),
			"erwartung": "Bad-Defaults stehen als Möbel-Nodes im Raum",
		},
		{"name": "hygiene_merken", "aktion": "tue", "funktion": _merke_hygiene},
	]
	liste.append_array(
		_pan_tipp_3d_schritte(
			"wanne",
			finde_moebel.bind("bathtub"),
			Vector3(0.0, 0.5, 0.0),
			{"bedingung": _dusche_reagiert},
			10.0,
			false
		)
	)
	(
		liste
		. append_array(
			[
				{
					"name": "wanne_nachfassen",
					"aktion": "warte_bis",
					"bedingung": _dusche_reagiert,
					"timeout_s": 12.0,
					"nebenbei_tipp_klasse": "KloDusche",
				},
				{
					"name": "dusche_soll_zustand",
					"aktion": "tue",
					"funktion": _dusche_diagnose,
					"erwartung": "1. Tap: Routine aktiv UND Hygiene noch unverändert",
					"pflicht": false,
				},
				{"name": "dusche_ansehen", "aktion": "warte", "sekunden": 3.0},
				{
					"name": "wanne_abspuelen",
					"aktion": "tipp_3d",
					"finder": finde_moebel.bind("bathtub"),
					"offset": Vector3(0.0, 0.5, 0.0),
					"erwarte": {"bedingung": _hygiene_gestiegen},
					"timeout_s": 30.0,
				},
				{
					"name": "dusche_aufraeumen",
					"aktion": "tue",
					"funktion": _dusche_rettung,
					"erwartung": "Gooby nach dem Abspülen sichtbar, keine Routine hängt",
					"pflicht": false,
				},
				{"name": "bad_fertig", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


## Garten: DIE ASSET-ROT-Verifikation (Nebenbefund aus Welle H). Ergebnis
## Lauf v4: Save + Grid kennen die 4 Defaults, die Nodes FEHLEN aber — und
## zwar NICHT wegen GLB-Degradation (Headless-Gegenprobe
## flow_pt1_diag_assets.gd lädt alle 4 GLBs sauber), sondern weil
## GardenView.rebuild() ALLE Kinder des geteilten blockers()-Mounts löscht,
## in den _spawn_furniture die blocks_movement-Möbel gehängt hat. Der
## Diagnose-Schritt belegt das im Lauf (Blockers-Inventar + Live-create).
func _garten_schritte() -> Array[Dictionary]:
	return [
		{"name": "garten_ankommen_extra", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "garten_save_check",
			"aktion": "tue",
			"funktion": _garten_save_hat_defaults,
			"erwartung": "treeDefault/treeFat/gardenBench/potLarge liegen im Save",
		},
		{
			"name": "garten_asset_rot_check",
			"aktion": "tue",
			"funktion":
			moebel_protokoll.bind(["treeDefault", "treeFat", "gardenBench", "potLarge"]),
			"erwartung": "Garten-Defaults spawnen als Möbel-Nodes (BEFUND: tun sie nicht)",
			"pflicht": false,
		},
		{
			"name": "garten_blocker_diagnose",
			"aktion": "tue",
			"funktion": _garten_diagnose,
			"erwartung": "Beleg: Blockers-Mount leergeräumt, Live-create funktioniert",
		},
		{"name": "garten_panorama", "aktion": "warte", "sekunden": 2.0},
	]


# ---------------------------------------------------------------- Bedingungen


## Läuft der GOB.TY-Empfang auf dem Wohnzimmer-Fernseher?
func _tv_an() -> bool:
	var tv := _finde_klasse(aktuelle_szene(), "Fernseher")
	return tv != null and bool(tv.get("_an"))


func _tv_aus() -> bool:
	return not _tv_an()


## BEFUND-MESSUNG: Liegt die Mitte des „Fernseher aus“-Knopfs unter einem
## anderen klick-schluckenden Control (HUD-Aktionsspalte)? Loggt die Rects.
func _aus_knopf_frei() -> bool:
	var knopf := _finde_sichtbares_control(harness.root, "GobtyAusKnopf")
	if knopf == null:
		print("[PT1] GobtyAusKnopf nicht gefunden/sichtbar")
		return false
	var mitte := knopf.get_global_rect().get_center()
	var oben := _stop_control_bei(mitte)
	print("[PT1] AusKnopf-Rect %s, Mitte %s" % [str(knopf.get_global_rect()), str(mitte)])
	if oben != null and oben != knopf and not knopf.is_ancestor_of(oben):
		print("[PT1] BUG-BELEG: über der Knopfmitte liegt AUCH '%s' (%s)" % [oben.name, oben])
		return false
	return true


## Workaround-Tipppunkt: linker Rand des Aus-Knopfs (die rechte Hälfte
## liegt bei 1024×471 unter Quest/Profil der HUD-Aktionsspalte).
func _aus_knopf_links() -> Vector2:
	var knopf := _finde_sichtbares_control(harness.root, "GobtyAusKnopf")
	if knopf == null:
		return Vector2(4.0, 4.0)
	var rect := knopf.get_global_rect()
	return Vector2(rect.position.x + rect.size.x * 0.12, rect.get_center().y)


func _merke_hygiene() -> bool:
	var stand := zahl("gooby.stats.hygiene", -1.0)
	return merke("hygiene_vorher", stand) and stand >= 0.0


## Wanne hat auf den Tap reagiert: Routine läuft (SOLL) ODER die
## Doppel-Feuer-Signatur (Hygiene sofort gebucht / Gooby unsichtbar).
func _dusche_reagiert() -> bool:
	if _dusche_irgendwo_aktiv():
		return true
	if zahl("gooby.stats.hygiene", -1.0) >= float(wert("hygiene_vorher", 999.0)) + 5.0:
		return true
	var gooby := gooby_node()
	return gooby != null and not gooby.visible


func _dusche_irgendwo_aktiv() -> bool:
	for dusche: Node in _alle_mit_klasse(aktuelle_szene(), "KloDusche"):
		if bool(dusche.call("is_routine_active")):
			return true
	return false


## SOLL nach Tap 1: mindestens eine Routine aktiv und Hygiene NOCH
## unverändert (+20 kommt erst beim Abspülen). Loggt den Ist-Zustand jeder
## Instanz — Beleg für den Doppel-Feuer-Befund (make_tap_area reagiert auf
## Maus UND emulierten Touch).
func _dusche_diagnose() -> bool:
	var instanzen := _alle_mit_klasse(aktuelle_szene(), "KloDusche")
	if instanzen.is_empty():
		print("[PT1] Dusche-Diagnose: keine KloDusche im Raum (falscher Raum?)")
		return false
	var vorher := float(wert("hygiene_vorher", -1.0))
	var jetzt := zahl("gooby.stats.hygiene", -1.0)
	var aktive := 0
	for dusche: Node in instanzen:
		var aktiv := bool(dusche.call("is_routine_active"))
		var ist_dusche := bool(dusche.get("_is_shower"))
		print("[PT1] KloDusche is_shower=%s routine_aktiv=%s" % [ist_dusche, aktiv])
		if aktiv:
			aktive += 1
	var gooby := gooby_node()
	var sichtbar := gooby != null and gooby.visible
	print(
		(
			"[PT1] Dusche-Diagnose: aktive_routinen=%d gooby_sichtbar=%s hygiene %.1f -> %.1f"
			% [aktive, sichtbar, vorher, jetzt]
		)
	)
	return aktive > 0 and jetzt < vorher + 5.0


## Räumt nach dem Wannen-Test auf und DOKUMENTIERT den Stuck-Zustand:
## hängende Routine → finish_shower(); Gooby unsichtbar ohne Routine
## (Doppel-Feuer-Folge) → sichtbar machen + Wander an. false = es war
## eine Rettung nötig (Beleg im Report, Schritt ist pflicht:false).
func _dusche_rettung() -> bool:
	var sauber := true
	for dusche: Node in _alle_mit_klasse(aktuelle_szene(), "KloDusche"):
		if bool(dusche.call("is_routine_active")) and bool(dusche.get("_is_shower")):
			print("[PT1] Rettung: finish_shower() auf hängender Dusch-Routine")
			dusche.call("finish_shower")
			sauber = false
	var gooby := gooby_node()
	if gooby != null and not gooby.visible:
		print("[PT1] BUG-BELEG: Gooby unsichtbar OHNE aktive Routine — mache sichtbar")
		gooby.visible = true
		if gooby.has_method("set_wander_enabled"):
			gooby.set_wander_enabled(true)
		sauber = false
	return sauber


## Abspülen bucht +20 Hygiene (Toleranz: Ticker zehrt nebenher).
func _hygiene_gestiegen() -> bool:
	var vorher := float(wert("hygiene_vorher", -1.0))
	if vorher < 0.0:
		return false
	return zahl("gooby.stats.hygiene", -1.0) >= vorher + 5.0


## Blockers-Ownership-Beleg: (1) Inventar von blockers() und grid_mount()
## — die vier blocks_movement-Defaults fehlen im Blockers-Mount, weil
## GardenView.rebuild() dessen Kinder löscht; (2) Live-create von
## treeDefault beweist, dass GLB + FurnitureNode einwandfrei funktionieren.
func _garten_diagnose() -> bool:
	var szene := aktuelle_szene()
	if szene == null:
		return false
	var blockers: Node = szene.call("blockers") if szene.has_method("blockers") else null
	var mount: Node = szene.call("grid_mount") if szene.has_method("grid_mount") else null
	print("[PT1] Blockers-Kinder: %s" % [_kinder_namen(blockers)])
	print("[PT1] GridMount-Kinder: %s" % [_kinder_namen(mount)])
	var def := FurnitureCatalog.def("treeDefault")
	var node := FurnitureNode.create(def, Vector2i(0, 4), 0, "pt1diag")
	var ok := node != null
	print("[PT1] Live-create treeDefault im Garten: %s" % ("OK — Node entsteht" if ok else "NULL"))
	if node != null:
		node.free()
	return ok


func _kinder_namen(node: Node) -> Array[String]:
	var out: Array[String] = []
	if node == null:
		return out
	for kind in node.get_children():
		if not kind.is_queued_for_deletion():
			out.append(str(kind.name))
	return out


## Liegen die vier Garten-Defaults (noch) im Save? (HomeState könnte sie
## beim Laden verwerfen — dann wäre der Befund ein anderer als ASSET-ROT.)
func _garten_save_hat_defaults() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var eintraege: Variant = gs.get_value("home.rooms.garden.items", [])
	if not (eintraege is Array):
		return false
	var ids: Array[String] = []
	for eintrag: Variant in eintraege:
		if eintrag is Dictionary:
			ids.append(str((eintrag as Dictionary).get("item", "")))
	print("[PT1] Garten-Save-Items: %s" % str(ids))
	var ok := true
	for pflicht: String in ["treeDefault", "treeFat", "gardenBench", "potLarge"]:
		if not ids.has(pflicht):
			print("[PT1] Save-FEHLT: %s" % pflicht)
			ok = false
	return ok
