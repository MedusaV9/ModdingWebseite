extends "res://tests/tools/playtest_flows/flow_pt1_helfer.gd"
## Flow PT1 (c) „Kühlschrank 2.0 + Fütter-Sequenz“: Boot → Onboarding → Küche
## → Kühlschrank öffnet das Regal-Grid (Karten mit Vorrats-Badge, Kategorien-
## Chips) → Chips filtern WIRKLICH (Süßes zeigt nur den Cupcake) → Möhre
## füttern: FuetterRegie spawnt (Speise schwebt), Zeitplan hat VOLLE 3 Bisse,
## Möhre = Lieblingsessen → GoobyFeelings „verliebtheit“ → Buchung: Hunger
## steigt, Vorrat 3→2 → Regal erneut öffnen (Badge ×2) und über den
## Schließen-Knopf verlassen. Aufruf: tools/ci/run_playtest.sh flow_pt1_kuehlschrank


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = [
		{
			"name": "events_stilllegen",
			"aktion": "tue",
			"funktion": _events_stilllegen,
			"erwartung": "Random-Events liegen für den Lauf auf Cooldown",
		},
		{
			"name": "tuer_confirm_aus",
			"aktion": "tue",
			"funktion": _tuer_confirm_aus,
			"erwartung": "Türen reisen ohne Bestätigungskarte (Testziel ist der Kühlschrank)",
		},
	]
	liste.append_array(onboarding_schritte())
	liste.append_array(_kuechen_schritte())
	liste.append_array(_grid_schritte())
	liste.append_array(_fuetter_schritte())
	liste.append_array(_nachkontrolle_schritte())
	return liste


# ---------------------------------------------------------------- Abschnitte


func _kuechen_schritte() -> Array[Dictionary]:
	return _tuer_direkt_schritte("kueche", "kitchen")


## Regal-Grid: Karten + Vorrats-Badges + Kategorien-Chips (Filter-Beweis).
## Kühlschrank-Tap über Pan+Präzisions-Tipp und Bildmitte-Nachfassen —
## Sprechblasen (mouse_filter STOP) können den Einzel-Tipp schlucken.
func _grid_schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(
		_pan_tipp_3d_schritte(
			"kuehlschrank",
			finde_moebel.bind("kitchenFridge"),
			Vector3(0.0, 0.9, 0.0),
			{"klasse": "FuetterGrid"},
			10.0,
			false
		)
	)
	liste.append_array(_grid_prueft_schritte())
	return liste


func _grid_prueft_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "kuehlschrank_nachfassen",
			"aktion": "warte_bis",
			"klasse": "FuetterGrid",
			"timeout_s": 12.0,
			"nebenbei_tipp_klasse": "Kuehlschrank",
		},
		{
			"name": "starter_karten_da",
			"aktion": "tue",
			"funktion": _starter_karten_da,
			"erwartung": "Karten für carrot/apple/cupcake sichtbar (Starter-Vorrat)",
		},
		{
			"name": "chip_suesses_filtern",
			"aktion": "tipp_name",
			"node": "Chip_suesses",
			"erwarte": {"bedingung": _nur_suesses_sichtbar},
			"timeout_s": 15.0,
		},
		{"name": "filter_suesses_ansehen", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "chip_gemuese_filtern",
			"aktion": "tipp_name",
			"node": "Chip_gemuese",
			"erwarte": {"bedingung": _nur_gemuese_sichtbar},
			"timeout_s": 15.0,
		},
		{
			"name": "chip_alles_zurueck",
			"aktion": "tipp_name",
			"node": "Chip_alle",
			"erwarte": {"bedingung": _starter_karten_da},
			"timeout_s": 15.0,
		},
	]


## Möhre füttern: Sequenz-Inszenierung + Verliebtheit + echte Buchung.
## Die ~2,5-s-Sequenz wird in EINEM Poll-Schritt beobachtet (llvmpipe
## rendert nur wenige FPS — getrennte Schritte verpassen die Regie).
func _fuetter_schritte() -> Array[Dictionary]:
	return [
		{"name": "hunger_und_vorrat_merken", "aktion": "tue", "funktion": _merke_stand},
		{
			"name": "moehre_waehlen",
			"aktion": "tipp_name",
			"node": "Karte_carrot",
			"erwarte": {"weg_klasse": "FuetterGrid"},
			"timeout_s": 30.0,
		},
		{
			"name": "sequenz_bis_verliebtheit",
			"aktion": "warte_bis",
			"bedingung": _sequenz_beobachtet,
			"timeout_s": 120.0,
			"erwartung": "Regie spawnt, Speise schwebt, Ende: GoobyFeelings 'verliebtheit'",
		},
		{
			"name": "sequenz_fakten",
			"aktion": "tue",
			"funktion": _sequenz_fakten_ok,
			"erwartung": "Beobachtet: Regie da, Modell schwebte, Zeitplan = 3 Bisse",
		},
		{
			"name": "hunger_gebucht",
			"aktion": "warte_bis",
			"bedingung": _hunger_gestiegen,
			"timeout_s": 30.0,
			"erwartung": "gooby.stats.hunger steigt nach der Sequenz (echte Buchung)",
		},
		{
			"name": "vorrat_abgebucht",
			"aktion": "tue",
			"funktion": _vorrat_abgebucht,
			"erwartung": "inventory.food.carrot ist um 1 gesunken",
		},
	]


## Regal nochmal öffnen: Badge ×2 an der Möhre, Schließen-Knopf-Weg.
func _nachkontrolle_schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = [
		{"name": "verliebtheit_ausklingen", "aktion": "warte", "sekunden": 4.0},
	]
	liste.append_array(
		_pan_tipp_3d_schritte(
			"kuehlschrank_wieder",
			finde_moebel.bind("kitchenFridge"),
			Vector3(0.0, 0.9, 0.0),
			{"klasse": "FuetterGrid"},
			10.0,
			false
		)
	)
	liste.append_array(_nachkontrolle_rest())
	return liste


func _nachkontrolle_rest() -> Array[Dictionary]:
	return [
		{
			"name": "kuehlschrank_wieder_nachfassen",
			"aktion": "warte_bis",
			"klasse": "FuetterGrid",
			"timeout_s": 12.0,
			"nebenbei_tipp_klasse": "Kuehlschrank",
		},
		{
			"name": "moehren_badge_x2",
			"aktion": "warte_bis",
			"text": "×2",
			"timeout_s": 10.0,
			"pflicht": false,
		},
		{
			"name": "regal_schliessen",
			"aktion": "tipp_name",
			"node": "SchliessenKnopf",
			"erwarte": {"weg_klasse": "FuetterGrid"},
			"timeout_s": 20.0,
		},
		{"name": "abschluss_kueche", "aktion": "warte", "sekunden": 2.0},
	]


# ---------------------------------------------------------------- Bedingungen


func _starter_karten_da() -> bool:
	return control_da("Karte_carrot") and control_da("Karte_apple") and control_da("Karte_cupcake")


## Süßes-Filter: nur der Cupcake bleibt im Regal.
func _nur_suesses_sichtbar() -> bool:
	return (
		control_da("Karte_cupcake") and control_weg("Karte_carrot") and control_weg("Karte_apple")
	)


## Gemüse-&-Obst-Filter: Möhre + Apfel, kein Cupcake.
func _nur_gemuese_sichtbar() -> bool:
	return control_da("Karte_carrot") and control_da("Karte_apple") and control_weg("Karte_cupcake")


func _merke_stand() -> bool:
	var hunger := zahl("gooby.stats.hunger", -1.0)
	var vorrat := zahl("inventory.food.carrot", -1.0)
	return merke("hunger_vorher", hunger) and merke("vorrat_vorher", vorrat) and hunger >= 0.0


## Frame-Beobachter der Fütter-Sequenz (Seiteneffekt im Poll): notiert
## Regie-Auftritt, geplante Bisse und schwebendes Modell, sobald sichtbar;
## true erst, wenn die Verliebtheits-Emotion inszeniert wird.
func _sequenz_beobachtet() -> bool:
	var regie := _finde_klasse(aktuelle_szene(), "FuetterRegie")
	if regie != null:
		merke("regie_gesehen", true)
		var sequenz: Variant = regie.call("sequenz")
		if sequenz != null and int(sequenz.call("biss_anzahl")) > 0:
			merke("bisse_geplant", int(sequenz.call("biss_anzahl")))
		if regie.get("_modell") != null:
			merke("modell_gesehen", true)
	if feelings_aktuelle() == "verliebtheit":
		merke("verliebtheit_gesehen", true)
	return bool(wert("verliebtheit_gesehen", false))


## Nachschau: alles Beobachtete zusammen bewerten (Regie kann da schon
## wieder freigegeben sein — deshalb die Merkzettel statt Live-Zugriff).
func _sequenz_fakten_ok() -> bool:
	var regie := bool(wert("regie_gesehen", false))
	var bisse := int(wert("bisse_geplant", -1))
	var modell := bool(wert("modell_gesehen", false))
	print("[PT1] Sequenz-Fakten: regie=%s bisse=%d modell=%s" % [regie, bisse, modell])
	return regie and bisse == 3 and modell


## Möhre bucht +Hunger; kleine Toleranz, weil der Ticker nebenher zehrt.
func _hunger_gestiegen() -> bool:
	var vorher := float(wert("hunger_vorher", -1.0))
	if vorher < 0.0:
		return false
	return zahl("gooby.stats.hunger", -1.0) >= vorher + 2.0


func _vorrat_abgebucht() -> bool:
	var vorher := float(wert("vorrat_vorher", -1.0))
	var jetzt := zahl("inventory.food.carrot", -1.0)
	print("[PT1] Möhren-Vorrat: %s → %s" % [str(vorher), str(jetzt)])
	return jetzt == vorher - 1.0
