extends "res://tests/tools/playtest_flows/flow_basis.gd"
## J3-Playtest „Läden lebendig 2“ — Tour durch drei NEU belebte Orte:
## GOOBYTHEKE (Ambient-Kunden + CC0-Schrankwand/Bank + Kassen-NPC + Opa
## Hatschi mit Namensschild), FLUGHAFEN (Rollkoffer-Goobys in der Warte-
## halle + Frau Fernweh) und WOCHENMARKT (4 Bummler zwischen den CC0-
## Ständen + Esel + Karren). Screenshots belegen Besucher + NPCs + Props.
##
## Stammkunden hängen an der (injizierbaren) Uhr — der Flow injiziert die
## Fenster-Stunde über OrtLeben.stunde_override + _spawne_stammkunden, weil
## die Systemuhr des Runners sonst über den Bildinhalt entscheiden würde
## (das Fenster-Verhalten selbst sichert test_j3_leben_rollout headless ab).
## Aufruf: tools/ci/run_playtest.sh flow_j3_leben_tour

const SEED := 4711


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_schritte_tour())
	return liste


func _schritte_tour() -> Array[Dictionary]:
	return [
		# Die Guide-Karte spawnt teils erst DEUTLICH nach dem onboarding_
		# schritte-Beenden-Tap (Befund zweier Läufe) und schluckt dann jeden
		# BtnReise-Tap — deshalb die Tour über ihren Save-Slice abschalten
		# (onboarding.guide.done/skipped gate't attach_to) statt Tap-Rennen.
		{
			"name": "guide_stumm_schalten",
			"aktion": "tue",
			"funktion": guide_stumm_schalten,
			"erwartung": "Guide-Tour beendet/abgeschaltet",
		},
		{
			"name": "reise_in_die_stadt",
			"aktion": "tipp_name",
			"node": "BtnReise",
			"erwarte": {"route": "city"},
			"timeout_s": 180.0,
		},
		{"name": "stadt_ankommen", "aktion": "warte", "sekunden": 5.0},
		# ── Ort 1: GOOBYTHEKE (Apotheke) ────────────────────────────────
		{
			"name": "vorfahren_goobytheke",
			"aktion": "tue",
			"funktion": fahre_vor.bind("goobytheke"),
			"erwartung": "Auto steht am GOOBYTHEKE-Parkplatz",
		},
		{
			"name": "goobytheke_betreten",
			"aktion": "tipp_text",
			"text": "Betreten",
			"erwarte": {"route": "city/ort/goobytheke"},
			"timeout_s": 120.0,
		},
		{
			"name": "hatschi_einblenden",
			"aktion": "tue",
			"funktion": stammkunde_einblenden.bind("hatschi", 10.0),
			"erwartung": "Opa Hatschi steht im Fenster [9, 11) in der Apotheke",
		},
		# Begrüßungs-Bubble durchtippen (Muster flow_w18_rehwei), dann den
		# Raum in Ruhe ablichten: Besucher + Hatschi + CC0-Möbel.
		{
			"name": "apotheke_bubble_zeigen",
			"aktion": "tipp_falls_da",
			"node": "TypewriterTapFang",
			"timeout_s": 20.0,
		},
		{"name": "apotheke_bubble_lesen", "aktion": "warte", "sekunden": 0.6},
		{
			"name": "apotheke_bubble_weiter",
			"aktion": "tipp_falls_da",
			"node": "TypewriterTapFang",
			"timeout_s": 4.0,
		},
		{"name": "apotheke_leben", "aktion": "warte", "sekunden": 5.0},
		{
			"name": "apotheke_verlassen",
			"aktion": "tipp_name",
			"node": "Verlassen",
			"erwarte": {"route": "city"},
			"timeout_s": 60.0,
		},
		{"name": "zurueck_im_auto_1", "aktion": "warte", "sekunden": 3.0},
		# ── Ort 2: FLUGHAFEN (Wartehalle mit Rollkoffer-Goobys) ─────────
		{
			"name": "vorfahren_flughafen",
			"aktion": "tue",
			"funktion": fahre_vor.bind("flughafen"),
			"erwartung": "Auto steht am FLUGHAFEN-Parkplatz",
		},
		# Betreten über den ECHTEN Spiel-Handler (_on_betreten: Energie-
		# Gate + Route) statt Prompt-Tap: das Flughafen-Pad liegt am
		# Terminal-Kollider, die Kollisionsauflösung schiebt das Auto vom
		# Pad (Befund Läufe v3-v5; Karten-/Kulissen-Thema, J4-Zone).
		{
			"name": "flughafen_betreten",
			"aktion": "tue",
			"funktion": betrete_ort.bind("flughafen"),
			"erwarte": {"route": "city/ort/flughafen"},
			"erwartung": "FLUGHAFEN betreten (echter _on_betreten-Pfad)",
			"timeout_s": 120.0,
		},
		{
			"name": "fernweh_einblenden",
			"aktion": "tue",
			"funktion": stammkunde_einblenden.bind("fernweh", 12.0),
			"erwartung": "Frau Fernweh wartet im Fenster [11, 16) mit Koffer",
		},
		{
			"name": "flughafen_bubble_zeigen",
			"aktion": "tipp_falls_da",
			"node": "TypewriterTapFang",
			"timeout_s": 20.0,
		},
		{"name": "flughafen_bubble_lesen", "aktion": "warte", "sekunden": 0.6},
		{
			"name": "flughafen_bubble_weiter",
			"aktion": "tipp_falls_da",
			"node": "TypewriterTapFang",
			"timeout_s": 4.0,
		},
		{"name": "flughafen_koffer_leben", "aktion": "warte", "sekunden": 5.0},
		{
			"name": "flughafen_verlassen",
			"aktion": "tipp_name",
			"node": "Verlassen",
			"erwarte": {"route": "city"},
			"timeout_s": 60.0,
		},
		{"name": "zurueck_im_auto_2", "aktion": "warte", "sekunden": 3.0},
		# ── Ort 3: WOCHENMARKT (CC0-Stände + Esel + 4 Bummler) ──────────
		{
			"name": "vorfahren_wochenmarkt",
			"aktion": "tue",
			"funktion": fahre_vor.bind("wochenmarkt"),
			"erwartung": "Auto steht am WOCHENMARKT-Parkplatz",
		},
		{
			"name": "wochenmarkt_betreten",
			"aktion": "tipp_text",
			"text": "Betreten",
			"erwarte": {"route": "city/ort/wochenmarkt"},
			"timeout_s": 120.0,
		},
		{
			"name": "markt_bubble_zeigen",
			"aktion": "tipp_falls_da",
			"node": "TypewriterTapFang",
			"timeout_s": 20.0,
		},
		{"name": "markt_bubble_lesen", "aktion": "warte", "sekunden": 0.6},
		{
			"name": "markt_bubble_weiter",
			"aktion": "tipp_falls_da",
			"node": "TypewriterTapFang",
			"timeout_s": 4.0,
		},
		{"name": "markt_leben", "aktion": "warte", "sekunden": 5.0},
	]


## Ort über den echten CityScene-Handler betreten (Energie-Gate inklusive) —
## für Pads, deren Betreten-Prompt nicht stabil erreichbar ist (s. Schritt).
func betrete_ort(ort_id: String) -> bool:
	var szene := aktuelle_szene()
	if not (szene is CityScene):
		return false
	szene.call("_on_betreten", ort_id)
	return true


## Guide-Tour abschalten: Slice-Flags setzen (verhindert SPÄTES attach_to)
## und eine schon offene Karte sauber über ihr eigenes Tour-Ende schließen.
func guide_stumm_schalten() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	gs.set_value("onboarding.guide", {"done": true, "skipped": true, "step": 0, "base": {}})
	for node in harness.get_nodes_in_group("onboarding_guide"):
		if node.has_method("_end_tour"):
			node.call("_end_tour")
		else:
			node.queue_free()
	return true


## Auto direkt an den Parkplatz des Orts stellen (Muster flow_w18_rehwei,
## aber über die ECHTE teleport-API): rohes `position =` lässt heading/
## _prev_xz/_stuck_t stehen — die Anti-Stuck-Logik schob den Wagen dann
## vom Ziel-Pad weg (Befund Lauf v3: „Betreten“ landete im REHWEI).
func fahre_vor(ort_id: String) -> bool:
	var szene := aktuelle_szene()
	if not (szene is CityScene):
		return false
	var stadt: CityScene = szene
	if stadt.karte == null or stadt.auto == null:
		return false
	stadt.set("_ausparken", null)
	var park: Vector3 = stadt.karte.parkplatz_welt(ort_id)
	stadt.auto.teleport(park.x, park.z)
	# Auto-Gas! Ohne gehaltene Bremse rollt der Wagen vom Pad, der Prompt
	# verschwindet und der „Betreten“-Tap greift irgendwo anders (Befund
	# Lauf v3/v4: Wagen wanderte bis vor den REHWEI).
	stadt.auto.set_brake(true)
	return true


## Stammkunden fürs Foto einblenden: Fenster-Stunde injizieren und den
## Spawn nachholen (idempotent — steht die Figur schon da, passiert nichts).
func stammkunde_einblenden(id: String, stunde: float) -> bool:
	var szene := aktuelle_szene()
	if not (szene is OrtScene):
		return false
	var ort: OrtScene = szene
	if ort.leben == null:
		return false
	ort.leben.stunde_override = stunde
	if ort.leben.stammkunde_node(id) == null:
		ort.leben._spawne_stammkunden(SEED)
	return ort.leben.stammkunde_node(id) != null
