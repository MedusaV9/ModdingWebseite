extends "res://tests/tools/playtest_flows/flow_pt1_helfer.gd"
## Flow PT1 (a) „Haus-Rundgang“: Boot → Onboarding → Wohnzimmer-Möbel prüfen
## + Fernseher an/aus → Küche (Möbelbestand) → zurück → Schlafzimmer
## (Umzugskartons) → Bad (Möbel + ECHTE Dusche im Bottich: rein, abspülen,
## Hygiene +20) → zurück ins Wohnzimmer → GARTEN: Blocker-Ownership-Wache
## (treeDefault/treeFat/gardenBench/potLarge müssen Rebuilds überleben).
## Jede Raum-Station protokolliert Grid-Items vs. echte Möbel-Nodes.
##
## Lektionen aus den Läufen pt1_rundgang_v1/v2 (Details im Report
## docs/playtest/G8-PT1-home-bau.md):
## * Follow-Kamera + HUD-Spalten/“Was nun?“-Karte/Sprechblasen (die Kapsel
##   schirmt 3D-Taps unter sich weiterhin ab — seit FIX-5 via
##   _unhandled_input statt STOP-GUI) schlucken einzelne 3D-Tipps → Türen
##   laufen über den gehärteten Baustein _tuer_reise_schritte (Pan +
##   Präzisions-Tipp + Bildmitte-Nachfassen).
## * B2-FIX VERBAUT (Welle H → R2): make_tap_area dedupliziert jetzt die
##   emulierten Maus/Touch-Zwillinge, feuert erst auf Release unter der
##   Pan-Schwelle und sperrt Taps während Goobys Anlauf (interactables_
##   host.gd). Die Dusch-Sonde erwartet darum das SOLL-Verhalten HART
##   (dusche_soll_zustand/dusche_aufraeumen ohne pflicht:false); die
##   Rettungslogik bleibt als Diagnose-Netz stehen.
## * B4-FIX (FIX-5): der „Fernseher aus“-Knopf dodgt jetzt die HUD-
##   Cockpit-Spalte — die Überdeckungs-Messung ist PFLICHT und der Tipp
##   geht wie beim echten Spieler auf die Knopfmitte.
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
				},
				{
					"name": "fernseher_aus_tippen",
					"aktion": "tipp_pos",
					"pos_funktion": _aus_knopf_mitte,
					"erwarte": {"bedingung": _tv_aus},
					"timeout_s": 15.0,
				},
			]
		)
	)
	return liste


## Bad: Möbelbestand + Dusche im Bottich. B2-SONDE (FIX-6, Pflicht): seit dem
## make_tap_area-Wurzelfix ist das SOLL-Verhalten HARTE Erwartung — Tap 1
## startet GENAU EINE Routine (Hygiene unverändert), Tap 2 spült ab (+20).
## Timing beachten: die Wiedereintritts-Sperre schluckt Taps, solange Gooby
## anläuft (walk_to-Kappe 5 s), und die Start-Blase schirmt 3D-Taps unter
## sich ab — der EINE Abspül-Tap fällt darum erst nach Anlauf + Blase.
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
				},
				# Anlauf aussitzen: walk_to kappt bei 5 s — danach ist die
				# Wiedereintritts-Sperre sicher offen für den Abspül-Tap.
				{"name": "dusche_ansehen", "aktion": "warte", "sekunden": 6.0},
				{
					"name": "wanne_tap_frei",
					"aktion": "warte_bis",
					"bedingung": _wanne_tap_frei,
					"timeout_s": 12.0,
				},
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
				},
				{"name": "bad_fertig", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


## Garten: B1-REGRESSIONSWACHE (FIX-5). Lauf v4 bewies: Save + Grid kennen
## die 4 Defaults, aber GardenView.rebuild() löschte ALLE Kinder des
## geteilten blockers()-Mounts — samt der von _spawn_furniture geparkten
## blocks_movement-Möbel (GLB-Degradation war es NICHT, Gegenprobe
## flow_pt1_diag_assets.gd). Seit der Ownership-Trennung gibt rebuild()
## nur noch GardenView-eigene Bauten frei: der Möbel-Check ist PFLICHT,
## und ein Zellen-Tap-Rebuild obendrauf darf die Defaults nicht fressen.
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
			"erwartung": "Garten-Defaults stehen nach dem GardenView-Setup als Möbel-Nodes",
		},
		{
			"name": "garten_rebuild_anstossen",
			"aktion": "tue",
			"funktion": _garten_rebuild_anstossen,
			"erwartung": "Zellen-Auswahl stößt einen weiteren GardenView-Rebuild an",
		},
		# queue_free() der GardenView-Bauten sackt am Frame-Ende — kurz warten,
		# damit die Wache lebende Nodes von Leichen unterscheiden kann.
		{"name": "garten_rebuild_sacken", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "garten_blocker_wache",
			"aktion": "tue",
			"funktion": _garten_blocker_wache,
			"erwartung": "Defaults leben nach dem Rebuild weiter im Blockers-Mount",
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


## B4-WACHE (FIX-5, Pflicht): Liegt die Mitte des „Fernseher aus“-Knopfs
## unter einem fremden klick-schluckenden Control (HUD-Aktionsspalte)?
## Seit dem Cockpit-Spalten-Dodge in fernseher.gd darf das nie mehr sein.
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


## Tipppunkt „Fernseher aus“: die KNOPFMITTE, wie ein echter Spieler tippt.
## Vor dem B4-Fix lag die rechte Hälfte bei 1024×471 unter Quest/Profil der
## HUD-Aktionsspalte und der Flow musste auf den linken Rand ausweichen.
func _aus_knopf_mitte() -> Vector2:
	var knopf := _finde_sichtbares_control(harness.root, "GobtyAusKnopf")
	if knopf == null:
		return Vector2(4.0, 4.0)
	return knopf.get_global_rect().get_center()


func _merke_hygiene() -> bool:
	var stand := zahl("gooby.stats.hygiene", -1.0)
	return merke("hygiene_vorher", stand) and stand >= 0.0


## Wanne hat auf den Tap reagiert: Routine läuft (SOLL) ODER die alte
## Doppel-Feuer-Signatur (Hygiene sofort gebucht / Gooby unsichtbar).
## Die Signatur-Zweige bleiben BEWUSST drin — sie sind nur das Warte-Netz;
## das SOLL erzwingt der harte Folgeschritt dusche_soll_zustand. Käme das
## Doppel-Feuer zurück, liefe dieser Schritt noch durch und die Diagnose
## dahinter zeigte ROT mit dem präzisen Ist-Zustand statt Timeout-Raterei.
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


## B2-WACHE (FIX-6, Pflicht) — SOLL nach Tap 1: mindestens eine Routine
## aktiv und Hygiene NOCH unverändert (+20 kommt erst beim Abspülen).
## Genau diese Kombination riss das Doppel-Feuer (Maus + emulierter Touch
## in make_tap_area): Fire 2 beendete sofort, Hygiene buchte beim 1. Tap.
## Loggt den Ist-Zustand jeder Instanz als Beleg fürs Protokoll.
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


## B2-WACHE (FIX-6, Pflicht): nach dem Abspülen darf NICHTS hängen —
## hängende Dusch-Routine oder Gooby unsichtbar ohne Routine wären die
## Doppel-Feuer-Folgen. Die Rettungslogik bleibt als Diagnose-Netz stehen
## (sie räumt auf UND meldet false = ROT). Eine aktive KLO-Routine (der
## 4-h-Bedürfnis-Timer, nicht die Dusche) versteckt Gooby legitim und
## zählt darum nicht als Stuck-Beleg.
func _dusche_rettung() -> bool:
	var sauber := true
	var klo_aktiv := false
	for dusche: Node in _alle_mit_klasse(aktuelle_szene(), "KloDusche"):
		if not bool(dusche.call("is_routine_active")):
			continue
		if bool(dusche.get("_is_shower")):
			print("[PT1] Rettung: finish_shower() auf hängender Dusch-Routine")
			dusche.call("finish_shower")
			sauber = false
		else:
			klo_aktiv = true
	var gooby := gooby_node()
	if gooby != null and not gooby.visible and not klo_aktiv:
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


## Ist der Abspül-Tipppunkt (Wanne +0,5 m) frei? Die Start-Blase
## („bad.dusche.start") schirmt 3D-Taps unter sich weiterhin ab
## (AcBubble._unhandled_input + set_input_as_handled) und läuft nach
## ~4 s von selbst aus — der EINE Abspül-Tap wartet das ab, statt in
## der Kapsel zu versanden (Muster _tipp_frei_schritte, nur für 3D).
func _wanne_tap_frei() -> bool:
	var wanne := finde_moebel("bathtub")
	var kamera := harness.root.get_camera_3d()
	if wanne == null or kamera == null:
		return false
	var punkt := kamera.unproject_position(wanne.global_position + Vector3(0.0, 0.5, 0.0))
	var stop := _stop_control_bei(punkt)
	if stop != null:
		print("[PT1] wanne_tap_frei: Punkt %s von '%s' überdeckt" % [punkt, stop.name])
		return false
	for blase: Node in _alle_mit_klasse(harness.root, "AcBubble"):
		if not (blase.has_method("is_active") and bool(blase.call("is_active"))):
			continue
		var kapsel: Variant = blase.get("_kapsel")
		if kapsel is Control and (kapsel as Control).get_global_rect().has_point(punkt):
			print("[PT1] wanne_tap_frei: Blasen-Kapsel über dem Tipppunkt %s" % punkt)
			return false
	return true


## B1-Trigger: GardenHost.select_cell() läuft denselben Pfad wie ein
## Spieler-Tap auf eine Garten-Zelle (highlight + _refresh → rebuild) —
## VOR dem Ownership-Fix zerstörte genau dieser Rebuild die Default-Möbel
## im geteilten blockers()-Mount.
func _garten_rebuild_anstossen() -> bool:
	var host := _finde_klasse(aktuelle_szene(), "GardenHost")
	if host == null:
		print("[PT1] rebuild_anstossen: kein GardenHost im Raum")
		return false
	host.call("select_cell", Vector2i(0, 0))
	print("[PT1] rebuild_anstossen: select_cell(0,0) → GardenView.rebuild() lief")
	return true


## B1-WACHE (FIX-5, Pflicht): nach dem Rebuild müssen die vier
## blocks_movement-Defaults als LEBENDE Kinder im geteilten blockers()-
## Mount stehen — rebuild() gibt nur noch GardenView-eigene Bauten frei.
## Loggt beide Mount-Inventare als Beleg fürs Protokoll.
func _garten_blocker_wache() -> bool:
	var szene := aktuelle_szene()
	if szene == null:
		return false
	var blockers: Node = szene.call("blockers") if szene.has_method("blockers") else null
	var mount: Node = szene.call("grid_mount") if szene.has_method("grid_mount") else null
	print("[PT1] Blockers-Kinder: %s" % [_kinder_namen(blockers)])
	print("[PT1] GridMount-Kinder: %s" % [_kinder_namen(mount)])
	if blockers == null:
		return false
	var ok := true
	for item_id: String in ["treeDefault", "treeFat", "gardenBench", "potLarge"]:
		var node := finde_moebel(item_id)
		var lebt := (
			node != null and node.get_parent() == blockers and not node.is_queued_for_deletion()
		)
		print(
			(
				"[PT1] Blocker-Wache %s: %s"
				% [item_id, "LEBT im Blockers-Mount" if lebt else "FEHLT/verwaist"]
			)
		)
		ok = ok and lebt
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
