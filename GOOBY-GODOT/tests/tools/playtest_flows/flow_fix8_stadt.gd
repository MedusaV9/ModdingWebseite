extends "res://tests/tools/playtest_flows/flow_pt2_basis.gd"
## FIX-8 Mini-Flow (W18/R3) — Stadt-Ausschnitt für zwei R1-Restbefunde,
## bewusst kurz statt vollem Stadtrundgang:
## - PT2-B3: Flughafen/Post-Parkplatz — der parkplatz_welt-Anker steckte
##   ~0,5 m im Fassaden-Collider; _kollidiere schob das Auto raus und der
##   „Betreten"-Prompt flackerte. Hier: vorfahren und den Prompt eine
##   Kontinuitäts-Spanne lang OHNE Abriss halten — für BEIDE Befund-Orte.
##   BEWUSST keine Stillstands-Probe: das Auto ist ein Auto-Runner, dessen
##   Bremse per Design auf BRAKE_MIN_SPEED kriecht (Web-Parität §C7.2) und
##   dessen Spur-Assist seitlich Richtung Fahrbahn zieht — „steht still"
##   war nie das Versprechen, „Prompt flackert nicht" schon (Lauf
##   fix8_stadt_v2: 3 m „Drift" in 2,5 s waren GENAU dieses Kriechen).
## - PT2-B8: Telefon-Statusleiste — Münzen standen nur beim Öffnen fest.
##   Hier: Telefon öffnen, Stand prüfen, Buchung WÄHREND das Telefon offen
##   ist (set_value → coins_changed), die Leiste muss live nachziehen.
## Aufruf: tools/ci/run_playtest.sh flow_fix8_stadt

## So lange muss der Prompt am Stück stehen (ab Anker: Kriechen + Spur-
## Assist schaffen in der Spanne < 3 m — sicher im 4-m-Prompt-Radius; der
## Vor-Fix-Flacker war ein An/Aus im Sub-Sekunden-Takt und reißt hier ab).
const PROMPT_HALT_S := 1.0
## „Buchung" bei offenem Telefon (krumme Zahl — kein Verwechseln mit Boni).
const BUCHUNG_PLUS := 37


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append_array(
			[
				{
					"name": "in_die_stadt",
					"aktion": "tipp_name",
					"node": "BtnReise",
					"erwarte": {"route": "city"},
					"timeout_s": 120.0,
				},
				{"name": "ausparken_ansehen", "aktion": "warte", "sekunden": 5.0},
			]
		)
	)
	liste.append_array(_parkplatz_stabil("flughafen", "OrtFlughafen"))
	liste.append_array(_parkplatz_stabil("post", "OrtPost"))
	(
		liste
		. append_array(
			[
				{
					"name": "nach_hause",
					"aktion": "tipp_text",
					"text": "Nach Hause",
					"erwarte": {"route": "home/living"},
					"timeout_s": 120.0,
				},
				{"name": "wohnzimmer_kurz", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "telefon_oeffnen",
					"aktion": "tipp_name",
					"node": "BtnIgohbie",
					"erwarte": {"klasse": "PhoneShell"},
					"timeout_s": 45.0,
				},
				{"name": "telefon_ansehen", "aktion": "warte", "sekunden": 1.5},
				{
					"name": "status_stimmt_beim_oeffnen",
					"aktion": "tue",
					"funktion": status_zeigt_kontostand,
					"erwartung": "Statusleiste zeigt beim Öffnen den echten Münzstand",
				},
				{
					"name": "buchung_bei_offenem_telefon",
					"aktion": "tue",
					"funktion": buche_muenzen,
				},
				{
					"name": "status_folgt_buchung_live",
					"aktion": "warte_bis",
					"bedingung": status_zeigt_kontostand,
					"timeout_s": 10.0,
					"erwartung": "PT2-B8: Statusleiste zieht die Buchung LIVE nach",
				},
				{
					"name": "telefon_zu",
					"aktion": "tipp_name",
					"node": "HomeBalken",
					"erwarte": {"weg_klasse": "PhoneShell"},
					"timeout_s": 30.0,
				},
				{"name": "abschluss_wohnzimmer", "aktion": "warte", "sekunden": 1.5},
			]
		)
	)
	return liste


## PT2-B3-Baustein: vorfahren, Prompt-Kontinuität messen, rein + raus.
## Vor „Betreten" wird NOCHMAL vorgefahren: zwischen Sonde und Tap liegen
## Screenshot + Suchzeit, in denen die Kriech-Bremse weiterrollt — frisch
## am Anker ist der Prompt beim Tap garantiert da.
func _parkplatz_stabil(ort_id: String, klasse: String) -> Array[Dictionary]:
	return [
		{
			"name": "vorfahrt_%s" % ort_id,
			"aktion": "tue",
			"funktion": fahre_zu.bind(ort_id),
			"erwartung": "Auto steht am Parkplatz %s" % ort_id,
		},
		{
			"name": "prompt_flackerfrei_%s" % ort_id,
			"aktion": "warte_bis",
			"bedingung": prompt_haelt.bind(ort_id),
			"timeout_s": 15.0,
			"erwartung": "PT2-B3: Prompt %s hält %.1f s ohne Abriss" % [ort_id, PROMPT_HALT_S],
		},
		{
			"name": "nochmal_vorfahren_%s" % ort_id,
			"aktion": "tue",
			"funktion": fahre_zu.bind(ort_id),
			"erwartung": "Auto frisch am Anker %s (fürs Betreten)" % ort_id,
		},
		{
			"name": "betreten_%s" % ort_id,
			"aktion": "tipp_text",
			"text": "Betreten",
			"erwarte": {"klasse": klasse},
			"timeout_s": 120.0,
		},
		{"name": "umsehen_%s" % ort_id, "aktion": "warte", "sekunden": 2.0},
		{
			"name": "verlassen_%s" % ort_id,
			"aktion": "tipp_name",
			"node": "Verlassen",
			"erwarte": {"route": "city"},
			"timeout_s": 120.0,
		},
		{"name": "wieder_stadt_%s" % ort_id, "aktion": "warte", "sekunden": 2.0},
	]


## PT2-B3-Sonde (jede Frame gepollt): _prompt_ort muss PROMPT_HALT_S am
## Stück auf dem Befund-Ort stehen. Jeder Abriss (vor dem Fix: der
## Fassaden-Collider drückte das Auto im Wechsel aus dem 4-m-Radius, der
## Prompt ging im Sub-Sekunden-Takt an/aus) setzt die Uhr zurück — dann
## reißt der Schritt in den 15-s-Timeout.
func prompt_haelt(ort_id: String) -> bool:
	var szene := stadt()
	if szene == null:
		return false
	var key := "prompt_seit_%s" % ort_id
	var jetzt := Time.get_ticks_msec()
	if str(szene.get("_prompt_ort")) != ort_id:
		if zettel.has(key):
			var stand := (jetzt - int(zettel[key])) / 1000.0
			print("[FIX8] %s: Prompt-ABRISS nach %.2f s — Uhr zurück" % [ort_id, stand])
			zettel.erase(key)
		return false
	if not zettel.has(key):
		zettel[key] = jetzt
		return false
	var dauer := (jetzt - int(zettel[key])) / 1000.0
	if dauer < PROMPT_HALT_S:
		return false
	print("[FIX8] %s: Prompt hielt %.2f s ohne Abriss" % [ort_id, dauer])
	return true


## Münz-Label der Telefon-Statusleiste (das einzige reine Ziffern-Label —
## die Uhr enthält ':', der Akku ist eine ProgressBar).
func _status_muenzen_label() -> Label:
	var leiste := harness.root.find_child("Statusleiste", true, false)
	if leiste == null:
		return null
	for kind in leiste.get_children():
		if kind is Label and String((kind as Label).text).is_valid_int():
			return kind
	return null


func status_zeigt_kontostand() -> bool:
	var label := _status_muenzen_label()
	if label == null:
		print("[FIX8] Statusleiste/Münz-Label nicht gefunden")
		return false
	print("[FIX8] Status-Münzen '%s', Konto %d" % [label.text, coins()])
	return label.text == str(coins())


## „Buchung" während das Telefon offen ist: Kontostand ändern — die
## Statusleiste muss über coins_changed nachziehen (PT2-B8).
func buche_muenzen() -> bool:
	return gib_coins(coins() + BUCHUNG_PLUS)
