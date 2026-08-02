extends "res://tests/tools/playtest_flows/flow_pt2_basis.gd"
## PT-2 Flow (a) „Stadt-Rundgang“ (Welle H): mit dem Auto in die Stadt,
## Stadtleben prüfen (Verkehr + Fußgänger, FIX-5), dann vier Orte wie ein
## Spieler betreten und verlassen (REHWEI, GOOBYTHEKE, Flughafen, Post) —
## je Ort: Betreten-Prompt, Energie-Abzug (Zentrum −4, Flughafen −6),
## Ambient-Leben (G7-P55) und der Rückweg in die Stadt. Am Ende kostenlos
## „Nach Hause“. Aufruf: tools/ci/run_playtest.sh flow_pt2_stadtrundgang

## Energie-Toleranz: zwischen merken und betreten tickt die Stat-Sim weiter.
const ENERGIE_TOLERANZ := 1.5


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
				{
					"name": "stadtleben_pruefen",
					"aktion": "tue",
					"funktion": stadt_lebt,
					"erwartung": "Verkehr UND Fußgänger unterwegs (FIX-5)",
				},
			]
		)
	)
	liste.append_array(_ort_besuch("rehwei", "OrtRehwei", 4.0))
	liste.append_array(_ort_besuch("goobytheke", "OrtGoobytheke", 4.0))
	liste.append_array(_ort_besuch("flughafen", "OrtFlughafen", 6.0))
	liste.append_array(_ort_besuch("post", "OrtPost", 4.0))
	(
		liste
		. append_array(
			[
				{
					"name": "nach_hause_kostenlos",
					"aktion": "tipp_text",
					"text": "Nach Hause",
					"erwarte": {"route": "home/living"},
					"timeout_s": 120.0,
				},
				{"name": "abschluss_wohnzimmer", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


## Ein Orts-Besuch: vorfahren → Prompt → betreten (Energie prüfen) →
## Ambient-Leben ansehen → verlassen (zurück in die Stadt am Bordstein).
func _ort_besuch(ort_id: String, klasse: String, energie_kosten: float) -> Array[Dictionary]:
	return [
		{
			"name": "vorfahrt_%s" % ort_id,
			"aktion": "tue",
			"funktion": fahre_zu.bind(ort_id),
			"erwartung": "Auto steht am Parkplatz %s" % ort_id,
		},
		{
			"name": "prompt_%s" % ort_id,
			"aktion": "warte_bis",
			"text": "betreten?",
			"timeout_s": 20.0,
		},
		{
			"name": "energie_merken_%s" % ort_id,
			"aktion": "tue",
			"funktion": merke_energie.bind("energie_%s" % ort_id),
		},
		{
			"name": "betreten_%s" % ort_id,
			"aktion": "tipp_text",
			"text": "Betreten",
			"erwarte": {"klasse": klasse},
			"timeout_s": 120.0,
		},
		{"name": "umsehen_%s" % ort_id, "aktion": "warte", "sekunden": 4.0},
		{
			"name": "energie_abzug_%s" % ort_id,
			"aktion": "tue",
			"funktion": _energie_abzug_ok.bind(ort_id, energie_kosten),
			"erwartung": "Energie −%.0f beim Betreten" % energie_kosten,
			"pflicht": false,
		},
		{
			"name": "leben_%s" % ort_id,
			"aktion": "tue",
			"funktion": ort_lebt,
			"erwartung": "OrtLeben-Besucher im Laden (G7-P55)",
			"pflicht": false,
		},
		{
			"name": "verlassen_%s" % ort_id,
			"aktion": "tipp_name",
			"node": "Verlassen",
			"erwarte": {"route": "city"},
			"timeout_s": 120.0,
		},
		{"name": "wieder_stadt_%s" % ort_id, "aktion": "warte", "sekunden": 2.0},
	]


func _energie_abzug_ok(ort_id: String, kosten: float) -> bool:
	var vorher := float(zettel.get("energie_%s" % ort_id, 0.0))
	var ist := energie()
	var abzug := vorher - ist
	print(
		(
			"[PT2] Energie %s: %.1f → %.1f (Abzug %.1f, soll %.1f)"
			% [ort_id, vorher, ist, abzug, kosten]
		)
	)
	return abzug >= kosten - 0.01 and abzug <= kosten + ENERGIE_TOLERANZ
