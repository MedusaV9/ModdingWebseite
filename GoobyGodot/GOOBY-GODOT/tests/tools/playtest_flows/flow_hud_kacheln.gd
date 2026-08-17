extends "res://tests/tools/playtest_flows/flow_schlaf_bett.gd"
## Flow „HUD-Kacheln“: Boot → Onboarding → ALLE 10 Aktions-Kacheln des
## HUD einmal antippen und wieder zurück: Quests (Blatt), IGohbie
## (Handy-Overlay), Bauen (Baumodus), Album, Profil, Garderobe,
## Möbel/IKEA, Gestalten, Arcade (je Route + „Zurück“) und zum Schluss
## Reise (Stadt + „Nach Hause“, schwerste Szene). Nach jeder Rückkehr
## muss die Route wieder home/living sein — Hänger, tote Knöpfe oder
## Routen-Fehlleitungen fallen hier sofort auf.
## Erbt die Bau-Helfer von flow_schlaf_bett (Lauf kacheln01: der Baumodus
## erzwingt beim ERSTEN Besuch die Bett-Quest — „Fertig“ verweigert, bis
## das Kuschelbett platziert ist; ohne Platzieren blieb der Baumodus offen
## und ALLE folgenden Kacheln-Schritte liefen ins Leere, weil das HUD im
## Baumodus ausgeblendet wird).
## Format: quer 2868x1320 (Leitformat, Default).
## Aufruf: tools/ci/run_playtest.sh flow_hud_kacheln


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append_array(
			[
				# 1) Tagesquests-Blatt — Sekundär-Kachel: erst das
				# Mehr-Cluster aufklappen (W20 P1, Helfer unten).
				freilegen_schritt("quests"),
				{
					"name": "kachel_quests",
					"aktion": "tipp_name",
					"node": "BtnQuests",
					"erwarte": {"klasse": "DailyQuestPanel"},
					"timeout_s": 45.0,
				},
				{
					"name": "quests_zu",
					"aktion": "taste",
					"keycode": KEY_ESCAPE,
					"erwarte": {"weg_klasse": "DailyQuestPanel"},
					"timeout_s": 20.0,
				},
				# 2) IGohbie (Handy-Shell-Overlay)
				{
					"name": "kachel_igohbie",
					"aktion": "tipp_name",
					"node": "BtnIgohbie",
					"erwarte": {"klasse": "PhoneShell"},
					"timeout_s": 45.0,
				},
				{"name": "igohbie_ansehen", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "igohbie_zu",
					"aktion": "taste",
					"keycode": KEY_ESCAPE,
					"erwarte": {"weg_klasse": "PhoneShell"},
					"timeout_s": 20.0,
				},
				# 3) Baumodus auf/zu — die Bett-Quest des ersten Besuchs
				# verlangt erst das Kuschelbett (sonst verweigert „Fertig").
				{
					"name": "kachel_bau",
					"aktion": "tipp_name",
					"node": "BtnBau",
					"erwarte": {"text": "Fertig"},
					"timeout_s": 45.0,
				},
				{
					"name": "bett_aus_lager_nehmen",
					"aktion": "tipp_falls_da",
					"text": "Kuschelbett",
					"timeout_s": 10.0,
					"pflicht": false,
				},
				{
					"name": "ghost_aktiv",
					"aktion": "warte_bis",
					"text": "Platzieren",
					"timeout_s": 20.0,
				},
				{
					"name": "ghost_auf_freie_zelle_tippen",
					"aktion": "tipp_pos",
					"pos_funktion": ziel_canvas_pos,
					"erwarte": {"bedingung": ghost_platzierbar},
					"timeout_s": 15.0,
				},
				# Lauf schlaf01: AcBubble-Kapsel über dem Knopf frisst den
				# Tap — warten, bis sie weggeblendet ist (Helfer geerbt).
				{
					"name": "platzieren_knopf_frei",
					"aktion": "warte_bis",
					"bedingung": platzieren_frei,
					"timeout_s": 30.0,
				},
				{
					"name": "bett_platzieren",
					"aktion": "tipp_text",
					"text": "Platzieren",
					"timeout_s": 15.0,
				},
				{
					"name": "bett_im_save",
					"aktion": "warte_bis",
					"bedingung": bett_platziert,
					"timeout_s": 25.0,
				},
				{
					"name": "bau_zu",
					"aktion": "tipp_text",
					"text": "Fertig",
					"erwarte": {"bedingung": bau_modus_zu},
					"timeout_s": 30.0,
				},
			]
		)
	)
	for eintrag in [
		["album", "album"],
		["profil", "profil"],
		["wardrobe", "wardrobe"],
		["ikea", "ikea"],
		["gestalten", "gestalten"],
		["arcade", "arcade"],
	]:
		var kachel := str(eintrag[0])
		var route := str(eintrag[1])
		# Lauf kacheln02: „Zurück" als Teilstring trifft auf dem
		# Gestalten-Screen ZUERST „Zurücksetzen" (Fußzeile, spätere
		# Geschwister gewinnen die Suche) — der Reset ändert die Route
		# nicht und der Schritt lief 90 s ins Leere. Darum dort den
		# Kopfzeilen-Knopf gezielt per Node-Namen antippen.
		var zurueck_schritt := (
			{
				"name": kachel + "_zurueck",
				"aktion": "tipp_name",
				"node": "BackButton",
				"erwarte": {"route": "home/living"},
				"timeout_s": 90.0,
			}
			if kachel == "gestalten"
			else {
				"name": kachel + "_zurueck",
				"aktion": "tipp_text",
				"text": "Zurück",
				"erwarte": {"route": "home/living"},
				"timeout_s": 90.0,
			}
		)
		# W20 P1 (Mehr-Cluster): Sekundär-Kacheln vor dem Tipp freilegen —
		# jede Heimkehr kann ein frisches (eingeklapptes) Cockpit bringen.
		if kachel in ["album", "wardrobe", "ikea", "gestalten"]:
			liste.append(freilegen_schritt(kachel))
		(
			liste
			. append_array(
				[
					{
						"name": "kachel_" + kachel,
						"aktion": "tipp_name",
						"node": "Btn" + kachel.capitalize(),
						"erwarte": {"route": route},
						"timeout_s": 90.0,
					},
					{"name": kachel + "_ansehen", "aktion": "warte", "sekunden": 2.0},
					zurueck_schritt,
				]
			)
		)
	(
		liste
		. append_array(
			[
				# 10) Reise → Stadt (schwerste Szene, ganz ans Ende)
				{
					"name": "kachel_reise",
					"aktion": "tipp_name",
					"node": "BtnReise",
					"erwarte": {"route": "city"},
					"timeout_s": 180.0,
				},
				{"name": "stadt_ansehen", "aktion": "warte", "sekunden": 4.0},
				{
					"name": "stadt_nach_hause",
					"aktion": "tipp_text",
					"text": "Nach Hause",
					"erwarte": {"route": "home/living"},
					"timeout_s": 180.0,
				},
				{"name": "abschluss_wohnzimmer", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


## W20 P1 Nachfix (HUD-Slimming): Sekundär-Kacheln (Quests/Album/Garderobe/
## Möbel/Gestalten) leben im Quer-Cockpit eingeklappt hinter der Mehr-
## Kachel — der Freileg-Schritt klappt das Cluster bei Bedarf auf. Als
## warte_bis-Bedingung (NICHT „tue“): nach einer Heimkehr kann der Router
## noch busy sein und das HUD fehlt kurz — die Bedingung pollt bis Timeout.
func freilegen_schritt(kachel: String) -> Dictionary:
	var node := "Btn" + kachel.capitalize()
	return {
		"name": kachel + "_freilegen",
		"aktion": "warte_bis",
		"bedingung": kachel_freilegen.bind(node),
		"timeout_s": 30.0,
	}


## Idempotent gepollte Bedingung: true, sobald die Kachel sichtbar ist
## (hochkant zeigt alle 10, oder das Cluster ist offen). Solange nicht,
## drückt jeder Poll höchstens EINMAL „Mehr“ (dasselbe Signal wie ein
## Spieler-Tap) — apply_layout schaltet die Kacheln synchron sichtbar,
## der Recheck direkt danach verhindert Doppel-Drücke/Zuklappen.
func kachel_freilegen(node_name: String) -> bool:
	var kachel := harness.root.find_child(node_name, true, false) as Control
	if kachel != null and kachel.is_visible_in_tree():
		return true
	var mehr := harness.root.find_child("BtnMehr", true, false) as Button
	if mehr == null or not mehr.is_visible_in_tree():
		return false
	mehr.pressed.emit()
	kachel = harness.root.find_child(node_name, true, false) as Control
	return kachel != null and kachel.is_visible_in_tree()
