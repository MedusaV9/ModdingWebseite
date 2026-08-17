extends "res://tests/tools/playtest_flows/flow_w18_dlc5_basis.gd"
## W18/3-Playtest (Agent 5) — Flow „DLC-Hub & Kauf-Gates“ (HOCHKANT):
## Settings → DLC-Bibliothek, Karten/Cover/Ribbons prüfen, dann die
## Gate-Zustände einmal quer durch: Ranch GESPERRT (Level 1, Knopf
## disabled + Level-Hinweis), nach Level-Staging das Ranch-Angebot
## („Jetzt losfahren“/„Später kaufen“), Goo-und-Bye-Angebot mit ZU WENIG
## Münzen (Klartext-Warnung statt Kauf — Progression-Check: kein Geld
## weg!), McGooby INSTALLIERT („Probeschicht starten!“). Hochkant-Aufruf:
##   tools/ci/run_playtest.sh flow_w18_dlc_hub 1320x2868

## Münzstand vor dem Fehlkauf-Versuch (Progression-Wache).
var _muenzen_vorher := -1


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(schritte_zur_bibliothek())
	liste.append_array(_schritte_karten_check())
	liste.append_array(_schritte_ranch_gesperrt())
	liste.append_array(_schritte_ranch_angebot())
	liste.append_array(_schritte_goobye_zu_wenig())
	liste.append_array(_schritte_mcgooby_installiert())
	liste.append_array(_schritte_abschluss())
	return liste


func _schritte_karten_check() -> Array[Dictionary]:
	return [
		{
			"name": "karten_und_cover_pruefen",
			"aktion": "tue",
			"funktion": karten_und_cover_ok,
			"erwartung": "3 DLC-Karten mit geladenen Cover-Texturen und Ribbons",
		},
		# BEFUND B3 GEFIXT (W18/4): ein ECHTER Spieler-Wisch über den Karten
		# scrollt jetzt die Bibliothek (Drag-Schwelle + eigener Pan in
		# dlc_screen), statt das Detail-Sheet der Karte unterm Finger zu
		# öffnen — der Wächter: nach dem Wisch ist KEIN PanelSheet offen und
		# der Pan hat den Zug wirklich verarbeitet (gescrollt, sofern die
		# Bibliothek überhaupt Scroll-Luft hat).
		{
			"name": "bibliothek_wischen",
			"aktion": "wisch",
			"von_rel": Vector2(0.5, 0.7),
			"nach_rel": Vector2(0.5, 0.3),
			"dauer_s": 0.6,
			"erwarte": {"weg_klasse": "PanelSheet"},
			"timeout_s": 10.0,
		},
		{
			"name": "bibliothek_wisch_scrollt",
			"aktion": "tue",
			"funktion": bibliothek_gescrollt,
			"erwartung": "Wisch lief durch den Bibliotheks-Pan (und scrollte bei Scroll-Luft)",
		},
		{"name": "bibliothek_unten_ansehen", "aktion": "warte", "sekunden": 1.5},
	]


## Ranch bei Level 1: Detail zeigt den GESPERRT-Zustand (Knopf disabled +
## „…trainiert fleißig“-Hinweis) — ein Tap darauf darf NICHTS auslösen.
func _schritte_ranch_gesperrt() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(schritte_detail_oeffnen("ranch", "Zur Ranch"))
	(
		liste
		. append_array(
			[
				{
					"name": "ranch_gate_hinweis_da",
					"aktion": "warte_bis",
					"text": "trainiert fleißig",
					"timeout_s": 15.0,
				},
				{
					"name": "ranch_gate_knopf_disabled",
					"aktion": "tue",
					"funktion": aktion_knopf_disabled,
					"erwartung": "Aktions-Knopf im Gesperrt-Detail ist disabled",
				},
				{
					"name": "ranch_gate_tap_probe",
					"aktion": "tipp_text",
					"text": "Zur Ranch",
					"pflicht": false,
				},
				{"name": "ranch_gate_ansehen", "aktion": "warte", "sekunden": 1.0},
				schritt_sheet_schliessen("ranch_gate_sheet_zu"),
				{"name": "ranch_gate_zu_ruhe", "aktion": "warte", "sekunden": 1.0},
			]
		)
	)
	return liste


## Level 15 staged (Münzen bleiben knapp): Ranch-Detail zeigt jetzt das
## Angebot; „Später kaufen“ lässt den Stand unangetastet.
func _schritte_ranch_angebot() -> Array[Dictionary]:
	var liste: Array[Dictionary] = [
		{
			"name": "staging_level15_arm",
			"aktion": "tue",
			"funktion": stage_level_muenzen.bind(15, 100),
			"erwartung": "Level 15 + 100 Münzen gesetzt (Staging)",
		},
	]
	liste.append_array(schritte_detail_oeffnen("ranch", "Zur Ranch"))
	(
		liste
		. append_array(
			[
				{
					"name": "ranch_angebot_oeffnen",
					"aktion": "tipp_text",
					"text": "Zur Ranch",
					"erwarte": {"text": "Jetzt losfahren"},
					"timeout_s": 30.0,
				},
				{"name": "ranch_angebot_ansehen", "aktion": "warte", "sekunden": 1.5},
				{
					"name": "ranch_angebot_spaeter",
					"aktion": "tipp_text",
					"text": "Später kaufen",
					"erwarte": {"weg_text": "Jetzt losfahren"},
					"timeout_s": 20.0,
				},
				{"name": "ranch_angebot_zu_ruhe", "aktion": "warte", "sekunden": 1.0},
			]
		)
	)
	return liste


## Goo und Bye mit 100 Münzen (BEFUND B12 GEFIXT, W18/4): der Kauf-Knopf
## ist von vornherein DISABLED und die Hinweiszeile sagt sofort „Noch
## nicht genug Münzen…“ — kein lockender grüner Knopf mehr. Der
## Tipp-Versuch auf den grauen Knopf (Kopfschüttel-Feedback) darf
## weiterhin KEINE Münzen abbuchen.
func _schritte_goobye_zu_wenig() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(schritte_detail_oeffnen("goo_und_bye", "Schlüssel ansehen"))
	(
		liste
		. append_array(
			[
				{
					"name": "goobye_angebot_oeffnen",
					"aktion": "tipp_text",
					"text": "Schlüssel ansehen",
					"erwarte": {"text": "Schlüssel übernehmen"},
					"timeout_s": 30.0,
				},
				{
					"name": "goobye_warnung_sofort_da",
					"aktion": "warte_bis",
					"text": "Noch nicht genug Münzen",
					"timeout_s": 15.0,
				},
				{
					"name": "goobye_kauf_knopf_disabled",
					"aktion": "tue",
					"funktion": goobye_kauf_knopf_disabled,
					"erwartung": "Kauf-Knopf ist bei Münzmangel disabled (B12)",
				},
				{
					"name": "goobye_muenzen_merken",
					"aktion": "tue",
					"funktion": merke_muenzen,
					"erwartung": "Münzstand notiert",
				},
				{
					"name": "goobye_fehlkauf_probe",
					"aktion": "tipp_text",
					"text": "Schlüssel übernehmen",
					"erwarte": {"text": "Noch nicht genug Münzen"},
					"timeout_s": 20.0,
				},
				{
					"name": "goobye_kein_geld_weg",
					"aktion": "tue",
					"funktion": muenzen_unveraendert,
					"erwartung": "Fehlkauf hat keine Münzen abgebucht",
				},
				{"name": "goobye_warnung_ansehen", "aktion": "warte", "sekunden": 1.5},
				{
					"name": "goobye_angebot_spaeter",
					"aktion": "tipp_text",
					"text": "Später",
					"erwarte": {"weg_text": "Schlüssel übernehmen"},
					"timeout_s": 20.0,
				},
			]
		)
	)
	return liste


## McGooby ist Welle A frei spielbar: Ribbon INSTALLIERT, Detail-Knopf
## „Probeschicht starten!“ (der Start selbst ist flow_w18_mcgooby_schicht).
func _schritte_mcgooby_installiert() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(schritte_detail_oeffnen("mcgooby", "Probeschicht starten"))
	liste.append(schritt_sheet_schliessen("mcgooby_detail_zu"))
	return liste


func _schritte_abschluss() -> Array[Dictionary]:
	return [
		{"name": "bibliothek_schluss_ruhe", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "zurueck_nach_hause",
			"aktion": "tipp_name",
			"node": "Zurueck",
			"erwarte": {"route": "home/living"},
			"timeout_s": 90.0,
		},
	]


## 3 Karten (ranch/goo_und_bye/mcgooby) mit geladenem Cover + Ribbon?
func karten_und_cover_ok() -> bool:
	for dlc_id in ["ranch", "goo_und_bye", "mcgooby"]:
		var karte := harness.root.find_child("DlcKarte_" + dlc_id, true, false)
		if karte == null:
			return false
		var cover: Node = karte.find_child("Cover", true, false)
		if not (cover is TextureRect) or (cover as TextureRect).texture == null:
			return false
		if karte.find_child("Ribbon", true, false) == null:
			return false
	return true


## Aktions-Knopf des offenen Detail-Sheets muss disabled sein (Gate).
func aktion_knopf_disabled() -> bool:
	var knopf := harness.root.find_child("AktionKnopf", true, false)
	return knopf is Button and (knopf as Button).disabled


## B3-Wächter: der Wisch ist wirklich als Pan durch die Bibliothek gelaufen.
## Auf dem hohen Leitformat (1320x2868) passen alle drei Karten auf den
## Schirm — dann bleibt scroll_vertical zwangsläufig 0 und der Beweis ist
## die vom Pan aufgesummelte Zugstrecke (_pan_summe überlebt das Release).
## Hat die Liste dagegen Scroll-Luft, MUSS der Wisch auch gescrollt haben.
func bibliothek_gescrollt() -> bool:
	var screen: Node = harness._finde_klasse(harness.root, "DlcScreen")
	if screen == null:
		return false
	var scroll: ScrollContainer = screen.get("_scroll")
	if scroll == null:
		return false
	var balken := scroll.get_v_scroll_bar()
	var luft := maxf(0.0, float(balken.max_value) - balken.page)
	var pan_weg := absf(float(screen.get("_pan_summe")))
	print(
		(
			"[FLOW] Bibliothek nach Wisch: scroll_vertical=%d, Scroll-Luft=%.0f px, Pan-Weg=%.0f px"
			% [scroll.scroll_vertical, luft, pan_weg]
		)
	)
	if pan_weg <= float(scroll.scroll_deadzone):
		return false
	return luft <= 0.0 or scroll.scroll_vertical > 0


## B12-Wächter: der Kauf-Knopf des offenen Goobye-Angebots ist disabled.
func goobye_kauf_knopf_disabled() -> bool:
	var knopf := harness.root.find_child("Kaufen", true, false)
	return knopf is Button and (knopf as Button).disabled


func merke_muenzen() -> bool:
	_muenzen_vorher = muenzstand()
	return _muenzen_vorher >= 0


func muenzen_unveraendert() -> bool:
	return _muenzen_vorher >= 0 and muenzstand() == _muenzen_vorher
