extends "res://tests/tools/playtest_flows/flow_pt2_basis.gd"
## PT-2 Flow (c) „Wochenmarkt“ (Welle H): mit Ernte im Korb zum Markt
## fahren, Gretas Dialog durchtippen („Ich möchte Ernte verkaufen.“),
## im ANKAUF-Tab alle Tomaten verkaufen (Geld/Inventar nachrechnen),
## dann im Tab „Mein Stand“ den Eigenstand bestücken (Möhren+Radieschen),
## den Preis-Slider WIRKLICH ziehen (billiger = verkauft sich schneller),
## den Markttag per zeit_override auf Samstag 9 Uhr stellen, das Replay
## anschauen und die Abrechnung abholen. Zum Schluss zurück nach Hause.
## Aufruf: tools/ci/run_playtest.sh flow_pt2_wochenmarkt

const MOEHREN := 3
const RADIESCHEN := 2
const TOMATEN := 2


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append_array(
			[
				{
					"name": "ernte_moehren",
					"aktion": "tue",
					"funktion": gib_essen.bind("carrot", MOEHREN)
				},
				{
					"name": "ernte_radieschen",
					"aktion": "tue",
					"funktion": gib_essen.bind("radish", RADIESCHEN),
				},
				{
					"name": "ernte_tomaten",
					"aktion": "tue",
					"funktion": gib_essen.bind("tomato", TOMATEN)
				},
				{
					"name": "in_die_stadt",
					"aktion": "tipp_name",
					"node": "BtnReise",
					"erwarte": {"route": "city"},
					"timeout_s": 120.0,
				},
				{"name": "stadt_ankommen", "aktion": "warte", "sekunden": 3.0},
				{
					"name": "vorfahrt_wochenmarkt",
					"aktion": "tue",
					"funktion": fahre_zu.bind("wochenmarkt"),
					"erwartung": "Auto steht am Marktplatz",
				},
				# HINWEIS Öffnungsregel: laut city_map.json hat der Markt nur
				# samstags 8–14 Uhr offen — der Prompt erscheint trotzdem an
				# jedem Tag (Befund, s. Report). Der Flow nutzt das aus.
				{
					"name": "markt_betreten",
					"aktion": "tipp_text",
					"text": "Betreten",
					"erwarte": {"klasse": "OrtWochenmarkt"},
					"timeout_s": 120.0,
				},
				{"name": "marktplatz_ansehen", "aktion": "warte", "sekunden": 3.0},
			]
		)
	)
	liste.append_array(dialog_taps(2, "gruss"))
	(
		liste
		. append_array(
			[
				{
					"name": "option_verkaufen",
					"aktion": "tipp_text",
					"text": "Ich möchte Ernte verkaufen.",
					"timeout_s": 30.0,
				},
			]
		)
	)
	liste.append_array(dialog_taps(3, "greta"))
	(
		liste
		. append_array(
			[
				{
					"name": "ankauf_sheet_da",
					"aktion": "warte_bis",
					"text": "Eins verkaufen",
					"timeout_s": 30.0,
				},
				{
					"name": "ankauf_coins_merken",
					"aktion": "tue",
					"funktion": merke_coins.bind("ankauf")
				},
			]
		)
	)
	# Ankauf-Liste zeigt nur ~1 Zeile (Radieschen zuerst) — die Tomate
	# erst über BEIDE Scroller (SheetScroll + Liste) ins Bild rollen,
	# sonst tippt der Tap DANEBEN und der Backdrop schließt das Sheet
	# (Lauf pt2_c1/c2!). Nadel „Tomate —“ trifft NUR die Listen-Zeile.
	liste.append_array(rolle_schritte("Tomate —", "tomate"))
	(
		liste
		. append_array(
			[
				{
					"name": "tomaten_verkaufen",
					"aktion": "tipp_pos",
					"pos_funktion": knopf_neben_label.bind("Tomate —"),
					"timeout_s": 20.0,
				},
				{"name": "verkauf_pling", "aktion": "warte", "sekunden": 1.5},
				{
					"name": "tomaten_geld_da",
					"aktion": "tue",
					"funktion": pruefe_coins_gestiegen.bind("ankauf"),
					"erwartung": "Münzen nach Tomaten-Verkauf gestiegen",
				},
				{
					"name": "tomaten_aus_korb",
					"aktion": "tue",
					"funktion": _tomaten_leer,
					"erwartung": "inventory.food.tomato == 0 (alle verkauft)",
				},
			]
		)
	)
	# Der Tab-Balken steht am KOPF des Sheet-Inhalts — nach dem Tomaten-
	# Roll ist das SheetScroll unten: erst zurückrollen, sonst tippt der
	# Tap auf die Sheet-Chrome-Zone und der Tab wechselt nie (Lauf pt2_c3).
	liste.append_array(rolle_schritte("Mein Stand", "tab_stand"))
	(
		liste
		. append_array(
			[
				{
					"name": "tab_mein_stand",
					"aktion": "tipp_text",
					"text": "Mein Stand",
					"timeout_s": 20.0,
				},
				{
					"name": "stand_titel_da",
					"aktion": "warte_bis",
					"text": "Dein Marktstand",
					"timeout_s": 20.0,
				},
			]
		)
	)
	# Lager-Zeilen liegen unter der langen Erste-Male-Karte — jede Ware
	# erst über beide Scroller ins Bild rollen („{name} — {basis} ᴳ“-
	# Zeile; der „Alle n“-Knopf legt den GANZEN Vorrat auf den Stand).
	liste.append_array(rolle_schritte("Möhre —", "moehren"))
	(
		liste
		. append_array(
			[
				{
					"name": "moehren_auflegen",
					"aktion": "tipp_pos",
					"pos_funktion": knopf_neben_label.bind("Möhre —"),
					"timeout_s": 20.0,
				},
				{"name": "auflegen_pling", "aktion": "warte", "sekunden": 1.5},
			]
		)
	)
	liste.append_array(rolle_schritte("Radieschen —", "radieschen"))
	(
		liste
		. append_array(
			[
				{
					"name": "radieschen_auflegen",
					"aktion": "tipp_pos",
					"pos_funktion": knopf_neben_label.bind("Radieschen —"),
					"timeout_s": 20.0,
				},
				{"name": "auflegen_pling_2", "aktion": "warte", "sekunden": 1.5},
				{
					"name": "stand_bestueckt",
					"aktion": "tue",
					"funktion": _stand_hat_slots.bind(2),
					"erwartung": "2 Slots auf dem Stand (Möhre + Radieschen)",
				},
				# Preis-Slider WIRKLICH ziehen: erster Slot (Möhre) auf billig —
				# billiger verkauft sich schneller, das Replay wird voller.
				{
					"name": "preis_slider_ziehen",
					"aktion": "wisch",
					"von_funktion": slider_punkt.bind(0.0),
					"nach_funktion": slider_punkt.bind(-0.6),
					"dauer_s": 0.6,
				},
				{
					"name": "preis_gesenkt",
					"aktion": "tue",
					"funktion": _faktor_unter_eins,
					"erwartung": "ein Slot-Preis-Faktor unter 1,0 (Slider hat gegriffen)",
					"pflicht": false,
				},
				{
					"name": "zeit_auf_samstag",
					"aktion": "tue",
					"funktion": _markttag_starten,
					"erwartung": "zeit_override = Samstag 9 Uhr, Sheet im LAEUFT-Zustand",
				},
				{
					"name": "markttag_laeuft",
					"aktion": "warte_bis",
					"text": "Der Markttag läuft gerade!",
					"timeout_s": 20.0,
				},
				{
					"name": "replay_coins_merken",
					"aktion": "tue",
					"funktion": merke_coins.bind("stand")
				},
			]
		)
	)
	liste.append_array(rolle_schritte("Zuschauen", "zuschauen"))
	(
		liste
		. append_array(
			[
				{
					"name": "replay_zuschauen",
					"aktion": "tipp_text",
					"text": "Zuschauen",
					"timeout_s": 20.0,
				},
				{
					"name": "abrechnung_karte",
					"aktion": "warte_bis",
					"text": "Markttag-Abrechnung",
					"timeout_s": 90.0,
				},
				{
					"name": "erloes_geprueft",
					"aktion": "tue",
					"funktion": pruefe_coins_gestiegen.bind("stand"),
					"erwartung": "Erlös nach Abrechnung auf dem Konto",
					"pflicht": false,
				},
			]
		)
	)
	liste.append_array(rolle_schritte("Alles klar!", "abrechnung_ok"))
	(
		liste
		. append_array(
			[
				{
					"name": "abrechnung_ok",
					"aktion": "tipp_text",
					"text": "Alles klar!",
					"timeout_s": 20.0,
				},
				{
					"name": "stand_wieder_leer",
					"aktion": "warte_bis",
					"text": "Der Stand ist leer",
					"timeout_s": 20.0,
				},
				# Sheet per BACKDROP-Tipp schließen (oben rechts, klar neben dem
				# Sheet). Ein Runter-Wisch ab Sheet-Mitte SCROLLT nur (pt2_c4) —
				# und der „Verlassen“-Tipp danach ging in den Backdrop und
				# verpuffte (Sheet zu, Knopf nie gedrückt, route blieb stehen).
				{
					"name": "sheet_zumachen",
					"aktion": "tipp_pos",
					"pos_funktion": canvas_punkt.bind(Vector2(0.9, 0.08)),
					"pflicht": false,
				},
				{"name": "sheet_zu_abwarten", "aktion": "warte", "sekunden": 1.5},
				{
					"name": "markt_verlassen",
					"aktion": "tipp_name",
					"node": "Verlassen",
					"erwarte": {"route": "city"},
					"timeout_s": 120.0,
				},
				{
					"name": "nach_hause",
					"aktion": "tipp_text",
					"text": "Nach Hause",
					"erwarte": {"route": "home/living"},
					"timeout_s": 120.0,
				},
				{"name": "abschluss", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


func _tomaten_leer() -> bool:
	var bestand := essen_bestand("tomato")
	print("[PT2] Tomaten im Korb: %d" % bestand)
	return bestand == 0


func _stand_slots() -> Array:
	return MarktStand.slice_von(game_state())["slots"]


func _stand_hat_slots(soll: int) -> bool:
	var slots := _stand_slots()
	print("[PT2] Stand-Slots: %d (soll %d)" % [slots.size(), soll])
	return slots.size() == soll


func _faktor_unter_eins() -> bool:
	for slot: Dictionary in _stand_slots():
		var faktor := float(slot["faktor"])
		print("[PT2] Preis-Faktor %s: %.2f" % [str(slot["ware"]), faktor])
		if faktor < 1.0:
			return true
	return false


## Markttag anwerfen: Sheet finden, Zeit auf den gebundenen Samstag 9 Uhr
## einfrieren und neu aufbauen — der Stand steht dann mitten im Markttag.
func _markttag_starten() -> bool:
	var sheet := _finde_stand_sheet(harness.root)
	if sheet == null:
		print("[PT2] MarktStandSheet nicht gefunden")
		return false
	sheet.zeit_override = naechster_samstag_unix(9)
	sheet.aktualisiere()
	print("[PT2] zeit_override = %d (Samstag 9 Uhr)" % sheet.zeit_override)
	return true


func _finde_stand_sheet(wurzel: Node) -> MarktStandSheet:
	var stapel: Array[Node] = [wurzel]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is MarktStandSheet:
			return aktuell
		for kind in aktuell.get_children():
			stapel.append(kind)
	return null
