extends "res://tests/tools/playtest_flows/flow_pt2_basis.gd"
## PT-2 Flow (f) „GOOBERANDO + Guber“ (Welle H): das IGohbie zu Hause
## öffnen, bei der Möhrenschmiede zwei Gerichte in den Korb legen und
## bestellen (Geld: Preise + 3 ᴳ Liefergebühr EXAKT), den Fahrer auf der
## Live-Karte anschauen, Tür öffnen, Trinkgeld geben (−5 ᴳ, Essen landet
## 1:1 im Inventar). Danach per HomeBalken zurück aufs Grid und mit Guber
## fahren: erst rufen + stornieren (30 ᴳ hin, 28 ᴳ zurück = −2 netto),
## dann erneut rufen, einsteigen und nach Hause fahren (Route home/living).
## Debug-Keys verkürzen NUR Wartezeiten (gooberando_prep_s/guber_warte_s);
## stunde_override=12 pinnt den Guber-Preis auf 30 (kein Surge-Zufall).
## Aufruf: tools/ci/run_playtest.sh flow_pt2_gooberando_guber

const BUDGET := 300
## Möhren-Duo 7 + Glutrote Tomate 9 + Liefergebühr 3.
const BESTELL_KOSTEN := 19
const TRINKGELD := 5
const GUBER_PREIS := 30
## Storno behält 2 ᴳ Gebühr ein (30 bezahlt, 28 zurück).
const STORNO_NETTO := -2


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append_array(
			[
				{"name": "budget_setzen", "aktion": "tue", "funktion": gib_coins.bind(BUDGET)},
				{
					"name": "liefer_tempo",
					"aktion": "tue",
					"funktion": setting_setzen.bind("debug.gooberando_prep_s", 5),
				},
				{
					"name": "guber_tempo",
					"aktion": "tue",
					"funktion": setting_setzen.bind("debug.guber_warte_s", 3),
				},
				{
					"name": "handy_oeffnen",
					"aktion": "tipp_name",
					"node": "BtnIgohbie",
					"erwarte": {"klasse": "PhoneShell"},
					"timeout_s": 90.0,
				},
				{"name": "grid_ansehen", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "gooberando_oeffnen",
					"aktion": "tipp_pos",
					"pos_funktion": knopf_in.bind("KachelGooberando"),
					"erwarte": {"text": "heute herkommen"},
					"timeout_s": 30.0,
				},
				{"name": "restaurants_ansehen", "aktion": "warte", "sekunden": 1.5},
				{
					"name": "moehrenschmiede_waehlen",
					"aktion": "tipp_name",
					"node": "Restaurant_moehrenschmiede",
					"erwarte": {"text": "Liefergebühr"},
					"timeout_s": 30.0,
				},
				{
					"name": "bestell_coins_merken",
					"aktion": "tue",
					"funktion": merke_coins.bind("bestellung"),
				},
				{"name": "essen_vorher_merken", "aktion": "tue", "funktion": _essen_merken},
			]
		)
	)
	# Speisekarte im Phone-Sheet: Zeilen vor jedem Tipp über alle Scroll-
	# Ebenen ins Bild rollen (Lehre aus pt2_c/d: geclippte Taps verpuffen).
	liste.append_array(rolle_schritte("Möhren-Duo", "duo"))
	(
		liste
		. append_array(
			[
				{
					"name": "moehren_duo_in_korb",
					"aktion": "tipp_text",
					"text": "Möhren-Duo",
					"timeout_s": 20.0,
				},
			]
		)
	)
	liste.append_array(rolle_schritte("Glutrote Tomate", "tomate"))
	(
		liste
		. append_array(
			[
				{
					"name": "tomate_in_korb",
					"aktion": "tipp_text",
					"text": "Glutrote Tomate",
					"erwarte": {"text": "Im Korb: 2"},
					"timeout_s": 20.0,
				},
			]
		)
	)
	liste.append_array(rolle_schritte("Bestellen (", "bestellen"))
	(
		liste
		. append_array(
			[
				{
					"name": "bestellen",
					"aktion": "tipp_text",
					"text": "Bestellen (",
					"erwarte": {"text": "Ankunft in ca."},
					"timeout_s": 30.0,
				},
				{
					"name": "bestellung_bezahlt",
					"aktion": "tue",
					"funktion": pruefe_coins_delta.bind("bestellung", -BESTELL_KOSTEN),
					"erwartung": "16 ᴳ Gerichte + 3 ᴳ Liefergebühr abgebucht",
				},
				{"name": "fahrer_karte_ansehen", "aktion": "warte", "sekunden": 3.0},
				{
					"name": "klingel_abwarten",
					"aktion": "warte_bis",
					"text": "DING DONG",
					"timeout_s": 90.0,
				},
				{
					"name": "tuer_oeffnen",
					"aktion": "tipp_text",
					"text": "Tür öffnen",
					"erwarte": {"text": "noch warm"},
					"timeout_s": 30.0,
				},
				{
					"name": "essen_angekommen",
					"aktion": "tue",
					"funktion": _essen_angekommen,
					"erwartung": "carrot +1 und tomato +1 im Inventar",
				},
				{"name": "tip_coins_merken", "aktion": "tue", "funktion": merke_coins.bind("tip")},
				{
					"name": "trinkgeld_geben",
					"aktion": "tipp_text",
					"text": "Trinkgeld (5",
					"timeout_s": 20.0,
				},
				{"name": "trinkgeld_pling", "aktion": "warte", "sekunden": 1.5},
				{
					"name": "trinkgeld_abgebucht",
					"aktion": "tue",
					"funktion": pruefe_coins_delta.bind("tip", -TRINKGELD),
					"erwartung": "Trinkgeld −5 ᴳ",
				},
				{
					"name": "zurueck_aufs_grid",
					"aktion": "tipp_name",
					"node": "HomeBalken",
					"timeout_s": 20.0,
				},
				{"name": "grid_wieder_da", "aktion": "warte", "sekunden": 1.5},
				{
					"name": "guber_oeffnen",
					"aktion": "tipp_pos",
					"pos_funktion": knopf_in.bind("KachelGuber"),
					"erwarte": {"text": "Wagen rufen"},
					"timeout_s": 30.0,
				},
				{
					"name": "guber_mittagszeit",
					"aktion": "tue",
					"funktion": _guber_mittag,
					"erwartung": "stunde_override=12 → Preis fix 30 ᴳ (kein Surge)",
				},
				{
					"name": "ruf1_coins_merken",
					"aktion": "tue",
					"funktion": merke_coins.bind("ruf1")
				},
				# Taps per TEXT statt Node-Name: aktualisiere() baut die App
				# im selben Frame neu auf (queue_free ist deferred) — Godot
				# nummeriert kollidierende Kindernamen um, „RufenButton“ war
				# in pt2_f1 deshalb unauffindbar. Texte bleiben stabil.
				{
					"name": "wagen_rufen_1",
					"aktion": "tipp_text",
					"text": "Wagen rufen (",
					"erwarte": {"text": "Doch nicht ("},
					"timeout_s": 30.0,
				},
				{
					"name": "ruf_bezahlt",
					"aktion": "tue",
					"funktion": pruefe_coins_delta.bind("ruf1", -GUBER_PREIS),
					"erwartung": "Rufen kostet sofort 30 ᴳ",
				},
				{
					"name": "doch_nicht",
					"aktion": "tipp_text",
					"text": "Doch nicht (",
					"erwarte": {"text": "Wagen rufen ("},
					"timeout_s": 30.0,
				},
				{
					"name": "storno_erstattet",
					"aktion": "tue",
					"funktion": pruefe_coins_delta.bind("ruf1", STORNO_NETTO),
					"erwartung": "28 ᴳ zurück — netto −2 ᴳ Storno-Gebühr",
				},
				{
					"name": "ruf2_coins_merken",
					"aktion": "tue",
					"funktion": merke_coins.bind("ruf2")
				},
				{
					"name": "wagen_rufen_2",
					"aktion": "tipp_text",
					"text": "Wagen rufen (",
					"erwarte": {"text": "Doch nicht ("},
					"timeout_s": 30.0,
				},
				{
					"name": "wagen_da",
					"aktion": "warte_bis",
					"text": "Einsteigen",
					"timeout_s": 60.0,
				},
				# Einsteigen routet nach home/living — wir SIND aber schon
				# daheim (trivial wahr). Belastbar: die Wartet-Ansicht
				# verschwindet und die Fahrt kostet exakt 30 ᴳ (Check unten).
				{
					"name": "einsteigen",
					"aktion": "tipp_text",
					"text": "Einsteigen",
					"erwarte": {"weg_text": "Einsteigen"},
					"timeout_s": 120.0,
				},
				{
					"name": "fahrt_bezahlt",
					"aktion": "tue",
					"funktion": pruefe_coins_delta.bind("ruf2", -GUBER_PREIS),
					"erwartung": "Fahrt kostet 30 ᴳ (beim Rufen bezahlt)",
				},
				{"name": "abschluss", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


func _essen_merken() -> bool:
	merke("carrot_vorher", essen_bestand("carrot"))
	merke("tomato_vorher", essen_bestand("tomato"))
	return true


func _essen_angekommen() -> bool:
	var carrot_ok := essen_bestand("carrot") == int(zettel.get("carrot_vorher", 0)) + 1
	var tomato_ok := essen_bestand("tomato") == int(zettel.get("tomato_vorher", 0)) + 1
	print(
		(
			"[PT2] Lieferung: carrot %d (+1 ok: %s), tomato %d (+1 ok: %s)"
			% [essen_bestand("carrot"), str(carrot_ok), essen_bestand("tomato"), str(tomato_ok)]
		)
	)
	return carrot_ok and tomato_ok


## Guber-Preis deterministisch: Lokalzeit-Stunde auf 12 pinnen (die App
## liest sonst die Systemuhr — 18–20 Uhr wäre Surge mit 45 statt 30 ᴳ).
## KEIN aktualisiere(): der Neubau im selben Frame nummeriert die Knopf-
## Namen um (s. o.); _on_rufen liest die Stunde ohnehin erst beim Druck.
func _guber_mittag() -> bool:
	var app := _finde_fahrdienst(harness.root)
	if app == null:
		print("[PT2] FahrdienstApp nicht gefunden")
		return false
	app.stunde_override = 12.0
	print(
		(
			"[PT2] Guber: stunde_override = 12.0 → Preis %d"
			% Fahrdienst.kosten_zur_stunde(Fahrdienst.GUBER, 12.0)
		)
	)
	return true


func _finde_fahrdienst(wurzel: Node) -> FahrdienstApp:
	var stapel: Array[Node] = [wurzel]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is FahrdienstApp:
			return aktuell
		for kind in aktuell.get_children():
			stapel.append(kind)
	return null
