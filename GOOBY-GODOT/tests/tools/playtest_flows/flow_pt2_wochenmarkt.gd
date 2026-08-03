extends "res://tests/tools/playtest_flows/flow_pt2_basis.gd"
## PT-2 Flow (c) „Wochenmarkt“ (Welle H; W18/R3 PT2-B10-Umbau): der Markt
## ist IMMER betretbar, aber außerhalb Sa 8–14 Uhr ruht er sichtbar. Der
## Flow spielt beide Seiten: (1) Zeit auf Samstag 6 Uhr pinnen → Planen,
## „Bis Samstag!“-Schild, Greta weg; über den „Mein Marktstand“-Knopf den
## Eigenstand TROTZDEM bestücken (Möhren+Radieschen, Preis-Slider ziehen)
## und den vertrösteten Ankauf-Tab sehen („Greta macht Pause“). (2) Zeit
## auf Samstag 9 Uhr flippen → Greta ist da, ihr Dialog startet nach, im
## Ankauf alle Tomaten verkaufen (Geld/Inventar nachrechnen), dann läuft
## der Markttag: Replay anschauen, Abrechnung abholen, nach Hause.
## HINWEIS: Läuft der Flow REAL samstags 8–14 Uhr, ist der Markt beim
## Betreten schon offen und Gretas Dialog liegt über dem Geschlossen-Teil
## — bewusst hingenommen (163 von 168 Wochenstunden sind eindeutig).
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
				# PT2-B10: der Platz ist bewusst IMMER betretbar — die
				# Öffnungszeiten zeigen sich DRINNEN als Geschlossen-Charme.
				{
					"name": "markt_betreten",
					"aktion": "tipp_text",
					"text": "Betreten",
					"erwarte": {"klasse": "OrtWochenmarkt"},
					"timeout_s": 120.0,
				},
				{"name": "marktplatz_ansehen", "aktion": "warte", "sekunden": 3.0},
				# ── Teil 1: GESCHLOSSEN (Samstag 6 Uhr, vor Marktbeginn) ──
				{
					"name": "zeit_auf_sa_frueh",
					"aktion": "tue",
					"funktion": _zeit_setzen.bind(6),
					"erwartung": "zeit_override = Samstag 6 Uhr, Markt zu",
				},
				{
					"name": "geschlossen_charme",
					"aktion": "tue",
					"funktion": _geschlossen_geprueft,
					"erwartung": "Greta weg, Planen + Bis-Samstag-Schild sichtbar",
				},
				{"name": "geschlossen_ansehen", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "stand_knopf_tipp",
					"aktion": "tipp_name",
					"node": "StandKnopf",
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
					"erwartung":
					"2 Slots auf dem Stand (Möhre + Radieschen) — GESCHLOSSEN bestückt",
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
			]
		)
	)
	# Ankauf-Tab bei GESCHLOSSENEM Markt: Greta vertröstet freundlich.
	liste.append_array(rolle_schritte("Ankauf", "tab_ankauf_zu"))
	(
		liste
		. append_array(
			[
				{
					"name": "tab_ankauf_zu",
					"aktion": "tipp_text",
					"text": "Ankauf",
					"timeout_s": 20.0,
				},
				{
					"name": "greta_macht_pause",
					"aktion": "warte_bis",
					"text": "Greta macht Pause",
					"timeout_s": 20.0,
				},
				# Sheet per BACKDROP-Tipp schließen (oben rechts, klar neben
				# dem Sheet) — s. Kommentar beim zweiten Schließen unten.
				{
					"name": "sheet_zu_vor_flip",
					"aktion": "tipp_pos",
					"pos_funktion": canvas_punkt.bind(Vector2(0.9, 0.08)),
					"pflicht": false,
				},
				{"name": "sheet_zu_abwarten_1", "aktion": "warte", "sekunden": 1.5},
				# ── Teil 2: OFFEN (Samstag 9 Uhr) — Greta kommt nach ──
				{
					"name": "zeit_auf_samstag",
					"aktion": "tue",
					"funktion": _zeit_setzen.bind(9),
					"erwartung": "zeit_override = Samstag 9 Uhr, Markt offen",
				},
				{
					"name": "greta_ist_da",
					"aktion": "tue",
					"funktion": _offen_geprueft,
					"erwartung": "Greta sichtbar, Planen/Schild weg",
				},
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
				# Ort-zeit_override (Sa 9 Uhr) wird in den Tab durchgereicht
				# (PT2-B10) — der VOR Marktbeginn bestückte Stand läuft jetzt.
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


## PT2-B10-Zeithebel: die Ort-Uhr auf den gebundenen Samstag `stunde` Uhr
## pinnen und den Marktzustand nachziehen — 6 Uhr = zu (vor Marktbeginn,
## bestücken bindet DIESEN Samstag), 9 Uhr = offen (Greta kommt nach).
func _zeit_setzen(stunde: int) -> bool:
	var markt := _finde_markt()
	if markt == null:
		print("[PT2] _zeit_setzen: kein OrtWochenmarkt aktiv")
		return false
	markt.zeit_override = naechster_samstag_unix(stunde)
	markt.aktualisiere_marktzustand()
	var offen: bool = markt.markt_offen()
	print("[PT2] zeit_override = %d (Sa %d Uhr) → offen=%s" % [markt.zeit_override, stunde, offen])
	return offen == (stunde >= 8 and stunde < 14)


## Geschlossen-Charme-Sonde: Greta (rig) unsichtbar, GeschlossenDeko
## (Planen + „Bis Samstag!“-Schild) sichtbar, Markt-Leben ruht,
## StandKnopf erreichbar.
func _geschlossen_geprueft() -> bool:
	var markt := _finde_markt()
	if markt == null:
		return false
	var deko: Node3D = markt.get("_geschlossen_deko")
	var greta_weg: bool = markt.rig != null and not markt.rig.visible
	var deko_da := deko != null and deko.visible
	var schild := deko != null and deko.find_child("SamstagSchild", true, false) != null
	var leben_ruht := markt.leben == null or not markt.leben.visible
	var knopf := harness.root.find_child("StandKnopf", true, false) != null
	print(
		(
			"[PT2] geschlossen: greta_weg=%s deko=%s schild=%s leben_ruht=%s stand_knopf=%s"
			% [greta_weg, deko_da, schild, leben_ruht, knopf]
		)
	)
	return greta_weg and deko_da and schild and leben_ruht and knopf


## Offen-Sonde nach dem Zeit-Flip: Greta sichtbar, Deko weg, Leben läuft.
func _offen_geprueft() -> bool:
	var markt := _finde_markt()
	if markt == null:
		return false
	var deko: Node3D = markt.get("_geschlossen_deko")
	var greta_da: bool = markt.rig != null and markt.rig.visible
	var deko_weg := deko == null or not deko.visible
	var leben_da := markt.leben != null and markt.leben.visible
	print("[PT2] offen: greta_da=%s deko_weg=%s leben=%s" % [greta_da, deko_weg, leben_da])
	return greta_da and deko_weg and leben_da


func _finde_markt() -> OrtWochenmarkt:
	var szene := aktuelle_szene()
	return szene if szene is OrtWochenmarkt else null
