extends "res://tests/tools/playtest_flows/flow_pt2_basis.gd"
## FIX-9-Mini-Flow „Guber-Umfeld“ (W18/R3 PT2-B11): beweist den B11-Fix im
## ECHTEN Spiel — die FahrdienstApp-Knöpfe heißen nach jedem aktualisiere()
## wieder EXAKT „RufenButton“/„StornoButton“/„EinsteigenButton“, darum
## laufen ALLE Taps hier per NODE-NAME (vor dem Fix unmöglich: Lauf pt2_f1
## fand „RufenButton“ nie — Godot nummerierte die im selben Frame neu
## gebauten Knöpfe um, der Bestands-Flow wich auf Text-Taps aus). Gespielt
## wird die volle Guber-Runde: rufen (−30), stornieren (+28 = netto −2),
## erneut rufen, einsteigen (Route heim), Kosten exakt nachgerechnet.
## WARUM ein eigener Flow: flow_pt2_gooberando_guber blieb im Sommer-Lauf
## an der „Erste-Viertelstunde“-Tour hängen (die Tour-Karte dodgt beim
## Verschwinden des „Qualität angepasst“-Banners nach oben, der blinde
## GuideBeenden-Tap verpufft, die offene Karte verdeckt dann die App-
## Kacheln) — hier wird die Tour deshalb NACHWEISBAR geschlossen, bevor
## das IGohbie aufgeht. Aufruf: tools/ci/run_playtest.sh flow_fix9_guber_umfeld

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
				# Tour SICHER schließen: der blinde tipp_falls_da oben kann an
				# der dodgenden Karte vorbeigehen (s. Kopf) — hier drücken wir
				# den echten GuideBeenden-Knopf und PRÜFEN, dass die Tour weg
				# ist (sonst verdeckt sie gleich die Guber-Kachel).
				{
					"name": "tour_x_druecken",
					"aktion": "tue",
					"funktion": _tour_schliessen,
				},
				{"name": "tour_zu_abwarten", "aktion": "warte", "sekunden": 1.5},
				{
					"name": "tour_wirklich_zu",
					"aktion": "tue",
					"funktion": _tour_zu_geprueft,
					"erwartung": "OnboardingGuide ist aus dem Baum",
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
				# B11-KERNPROBE im echten PhoneShell: Neubau ZWEIMAL im selben
				# Frame — der Knopf muss danach sofort wieder EXAKT
				# „RufenButton“ heißen (kein @RufenButton@…-Zombie-Name).
				{
					"name": "b11_namensprobe",
					"aktion": "tue",
					"funktion": _namen_stabil_geprueft,
					"erwartung": "genau EIN RufenButton, exakt benannt, get_node trifft",
				},
				{
					"name": "ruf1_coins_merken",
					"aktion": "tue",
					"funktion": merke_coins.bind("ruf1"),
				},
				# Ab hier ALLE App-Taps per NODE-NAME — der eigentliche
				# B11-Beweis (vorher wich der Bestands-Flow auf Texte aus).
				{
					"name": "wagen_rufen_per_name",
					"aktion": "tipp_name",
					"node": "RufenButton",
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
					"name": "storno_per_name",
					"aktion": "tipp_name",
					"node": "StornoButton",
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
					"funktion": merke_coins.bind("ruf2"),
				},
				{
					"name": "wagen_rufen_2_per_name",
					"aktion": "tipp_name",
					"node": "RufenButton",
					"erwarte": {"text": "Doch nicht ("},
					"timeout_s": 30.0,
				},
				{
					"name": "wagen_da",
					"aktion": "warte_bis",
					"text": "Einsteigen",
					"timeout_s": 60.0,
				},
				# Einsteigen routet nach home/living — wir SIND schon daheim;
				# belastbar: die Wartet-Ansicht verschwindet, Kosten exakt.
				{
					"name": "einsteigen_per_name",
					"aktion": "tipp_name",
					"node": "EinsteigenButton",
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


## Tour-X drücken, falls die Tour (noch) offen ist. Der Knopf-Druck läuft
## über pressed.emit() — frame-sicher gegen die dodgende Karte; die
## SPIELER-Taps dieses Flows folgen danach in der App selbst.
func _tour_schliessen() -> bool:
	var guide := harness.root.get_tree().get_first_node_in_group(&"onboarding_guide")
	if guide == null:
		print("[FIX9] Tour war (noch) nicht offen — nichts zu schließen")
		return true
	var knopf := guide.find_child("GuideBeenden", true, false) as BaseButton
	if knopf == null:
		print("[FIX9] Tour offen, aber ohne GuideBeenden-Knopf?")
		return false
	knopf.pressed.emit()
	print("[FIX9] GuideBeenden gedrückt")
	return true


func _tour_zu_geprueft() -> bool:
	var guide := harness.root.get_tree().get_first_node_in_group(&"onboarding_guide")
	if guide != null and not guide.is_queued_for_deletion():
		# Zweite Chance (Tour kam erst NACH dem ersten Druck hoch).
		print("[FIX9] Tour noch da — drücke erneut")
		return _tour_schliessen() and false
	print("[FIX9] Tour ist zu")
	return true


## Guber-Preis deterministisch: Lokalzeit-Stunde auf 12 pinnen (18–20 Uhr
## wäre Surge mit 45 statt 30 ᴳ) — Muster flow_pt2_gooberando_guber.
func _guber_mittag() -> bool:
	var app := _finde_fahrdienst()
	if app == null:
		print("[FIX9] FahrdienstApp nicht gefunden")
		return false
	app.stunde_override = 12.0
	print(
		(
			"[FIX9] Guber: stunde_override = 12.0 → Preis %d"
			% Fahrdienst.kosten_zur_stunde(Fahrdienst.GUBER, 12.0)
		)
	)
	return true


## B11-Sonde: aktualisiere() ZWEIMAL im selben Frame (die Stolperfalle aus
## dem Befund), dann müssen die Namen sofort wieder exakt stimmen.
func _namen_stabil_geprueft() -> bool:
	var app := _finde_fahrdienst()
	if app == null:
		print("[FIX9] FahrdienstApp nicht gefunden")
		return false
	app.aktualisiere()
	app.aktualisiere()
	var exakt := 0
	var krumm := 0
	for kind in app.get_children():
		if str(kind.name) == "RufenButton":
			exakt += 1
		elif str(kind.name).contains("RufenButton"):
			krumm += 1
	var treffer := app.get_node_or_null("RufenButton") != null
	print("[FIX9] Namensprobe: exakt=%d krumm=%d get_node=%s" % [exakt, krumm, str(treffer)])
	return exakt == 1 and krumm == 0 and treffer


func _finde_fahrdienst() -> FahrdienstApp:
	var stapel: Array[Node] = [harness.root]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is FahrdienstApp:
			return aktuell
		for kind in aktuell.get_children():
			stapel.append(kind)
	return null
