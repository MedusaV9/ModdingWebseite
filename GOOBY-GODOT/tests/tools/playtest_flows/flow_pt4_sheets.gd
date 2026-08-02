extends "res://tests/tools/playtest_flows/flow_pt4_basis.gd"
## PT-4 Flow (c) „Modal/Blatt-Verhalten" (G7-P53 + P50-Verifikation):
## Tagesquests-Blatt öffnen → weicht das HUD (User-Befund 1.8.: „Blatt
## liegt ÜBER den Status-Leisten")? → Backdrop-Dim sichtbar? →
## RUNTERWISCHEN am Griff schließt das ECHTE Blatt (P53-Geste) → HUD
## kommt zurück → Wieder-Öffnen-WACHE (G8-Befund B2, GEFIXT:
## PanelSheet.add_content zerstört wiederverwendete, gecachte Panels
## nicht mehr — der Schritt ist jetzt PFLICHT und prüft zusätzlich, dass
## das Blatt echten Quest-Inhalt zeigt) → Dim-Tap räumt das Blatt weg.
## Danach Baumodus: HUD-Knöpfe gleiten weg (P50), Goobys Blase OHNE
## Wort-Abriss (P51), Bett-Bauquest ERFÜLLEN (Geist auf freie Zellen,
## Platzieren — „Fertig" ist bis dahin gesperrt!) → Fertig.
## Aufruf: tools/ci/run_playtest.sh flow_pt4_sheets


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append_array(
			[
				{
					"name": "quests_blatt_oeffnen",
					"aktion": "tipp_name",
					"node": "BtnQuests",
					"erwarte": {"klasse": "DailyQuestPanel"},
					"timeout_s": 60.0,
				},
				{"name": "quests_blatt_ansehen", "aktion": "warte", "sekunden": 2.5},
				{
					"name": "hud_weicht_dem_blatt",
					"aktion": "warte_bis",
					"bedingung": hud_weicht,
					"timeout_s": 12.0,
				},
				{
					"name": "blatt_dim_liegt_dahinter",
					"aktion": "tue",
					"funktion": blatt_dim_sichtbar,
					"erwartung": "Backdrop-Dim liegt sichtbar hinter dem Blatt (P53)",
				},
				{
					"name": "blatt_runterwischen_schliesst",
					"aktion": "wisch",
					"von_funktion": blatt_griff_pos,
					"nach_funktion": blatt_wisch_ziel,
					"dauer_s": 0.45,
					"erwarte": {"weg_klasse": "DailyQuestPanel"},
					"timeout_s": 20.0,
				},
				{
					"name": "hud_kommt_zurueck",
					"aktion": "warte_bis",
					"bedingung": hud_da,
					"timeout_s": 12.0,
				},
				# ── G8-B2-Regressions-Wache: zweites Öffnen (nach EINEM
				# Schließen) MUSS wieder ein gefülltes Blatt bringen.
				{
					"name": "wieder_oeffnen_regression",
					"aktion": "tipp_name",
					"node": "BtnQuests",
					"erwarte": {"klasse": "DailyQuestPanel"},
					"timeout_s": 20.0,
				},
				# Kurz setzen lassen: der Alt-Bug fraß den Inhalt erst im
				# FOLGEFRAME (queue_free-Zombie) — die Wache danach sieht
				# also nur echten, überlebenden Inhalt.
				{"name": "wieder_oeffnen_setzen", "aktion": "warte", "sekunden": 1.0},
				{
					"name": "wieder_oeffnen_inhalt_da",
					"aktion": "tue",
					"funktion": wieder_oeffnen_inhalt_da,
					"erwartung": "Blatt zeigt beim zweiten Öffnen wieder Quests (B2-Fix)",
				},
				{"name": "blatt_zustand_loggen", "aktion": "tue", "funktion": blatt_zustand_loggen},
				{
					"name": "dim_tap_schliesst",
					"aktion": "tipp_pos",
					"pos_rel": Vector2(0.06, 0.10),
					"erwarte": {"bedingung": kein_blatt_offen},
					"timeout_s": 20.0,
				},
				{
					"name": "hud_zurueck_nach_dim_tap",
					"aktion": "warte_bis",
					"bedingung": hud_da,
					"timeout_s": 12.0,
				},
				# ── Baumodus (P50-Gleiten + P51-Blase + Bett-Bauquest).
				{
					"name": "baumodus_oeffnen",
					"aktion": "tipp_name",
					"node": "BtnBau",
					"erwarte": {"text": "Fertig"},
					"timeout_s": 60.0,
				},
				{
					"name": "bau_sprechblase_erscheint",
					"aktion": "warte_bis",
					"klasse": "AcBubble",
					"timeout_s": 15.0,
					"pflicht": false,
				},
				{
					"name": "bau_blase_ohne_wortabriss",
					"aktion": "tue",
					"funktion": blase_im_canvas,
					"erwartung": "Sprechblase komplett im Bild, Umbruch nur an Wortgrenzen (P51)",
					"pflicht": false,
				},
				{
					"name": "hud_weicht_im_baumodus",
					"aktion": "warte_bis",
					"bedingung": hud_weicht,
					"timeout_s": 12.0,
				},
			]
		)
	)
	liste.append_array(bett_platzieren_schritte())
	liste.append_array([{"name": "abschluss_wohnzimmer", "aktion": "warte", "sekunden": 2.0}])
	return liste


## G8-B2-Wache: das WIEDER geöffnete Blatt zeigt echten Quest-Inhalt — ein
## sichtbares, LEBENDIGES DailyQuestPanel mit Kindern im offenen Blatt (der
## Alt-Bug hängte einen queue_free-Zombie ein, der im Folgeframe starb).
func wieder_oeffnen_inhalt_da() -> bool:
	var sheet := blatt()
	var panel := _suche_klasse(harness.root, "DailyQuestPanel")
	if sheet == null or panel == null:
		print(
			(
				"[PT4] B2-Wache: Blatt offen=%s, Panel sichtbar=%s"
				% [str(sheet != null), str(panel != null)]
			)
		)
		return false
	var lebendig := not panel.is_queued_for_deletion()
	var kinder := panel.get_child_count()
	var im_blatt := sheet.is_ancestor_of(panel)
	print(
		(
			"[PT4] B2-Wache: Panel lebendig=%s Kinder=%d im offenen Blatt=%s"
			% [str(lebendig), kinder, str(im_blatt)]
		)
	)
	return lebendig and kinder > 0 and im_blatt
