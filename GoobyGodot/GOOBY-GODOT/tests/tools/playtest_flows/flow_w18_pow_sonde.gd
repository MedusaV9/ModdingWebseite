extends "res://tests/tools/playtest_flows/flow_basis.gd"
## W18-Playtest (Welle 3, Stadt-Agent) — Mini-Sonde „POW-Parkplatz“: Warum
## wird ein GEBREMSTES Auto am POW!-Bordstein binnen Sekunden 9–16 m
## verschoben (Läufe w18s_stadt/2/3/4, Prompt nie erreichbar)? Die Sonde
## teleportiert ans Parkfeld (einmal Trigger-Punkt, einmal Straßenseite)
## und sampelt die Auto-Position sekündlich: EIN Sprung = Kollider-
## Depenetration, VIELE kleine Stöße = Ambient-Verkehr rammt das Auto.
## W18/4-B12-FIX (G6): seit dem Fix (Pad-Stopp statt Kriech-Minimum +
## nächstseitige Depenetration) sind die beiden Prompt-Sonden PFLICHT-
## Wachen (warte_bis statt tipp_falls_da — nur SEHEN, nicht betreten,
## sonst verließe die Sonde die Stadt vor der Straßenseiten-Probe).
## Aufruf: tools/ci/run_playtest.sh flow_w18_pow_sonde

## Letzte gesampelte Position (für Delta-Ausgabe).
var _letzte_pos := Vector3.INF


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_schritte_ritual_puffer())
	(
		liste
		. append_array(
			[
				{
					"name": "reise_in_die_stadt",
					"aktion": "tipp_name",
					"node": "BtnReise",
					"erwarte": {"route": "city"},
					"timeout_s": 180.0,
				},
				{"name": "stadt_ankommen", "aktion": "warte", "sekunden": 5.0},
				{
					"name": "teleport_trigger_punkt",
					"aktion": "tue",
					"funktion": teleport_trigger,
					"erwartung": "Auto exakt auf dem POW-Trigger (47,-10), Bremse an",
				},
			]
		)
	)
	for i in range(6):
		liste.append({"name": "t%d_warte" % i, "aktion": "warte", "sekunden": 1.0})
		(
			liste
			. append(
				{
					"name": "t%d_position" % i,
					"aktion": "tue",
					"funktion": logge_position,
					"erwartung": "Positions-Sample (Log)",
					"pflicht": false,
				}
			)
		)
	(
		liste
		. append(
			{
				"name": "trigger_prompt_wache",
				"aktion": "warte_bis",
				"text": "betreten?",
				"timeout_s": 20.0,
			}
		)
	)
	(
		liste
		. append(
			{
				"name": "teleport_strassenseite",
				"aktion": "tue",
				"funktion": teleport_strasse,
				"erwartung": "Auto am Fahrbahnrand (53,-10), Bremse an",
			}
		)
	)
	for i in range(6, 12):
		liste.append({"name": "t%d_warte" % i, "aktion": "warte", "sekunden": 1.0})
		(
			liste
			. append(
				{
					"name": "t%d_position" % i,
					"aktion": "tue",
					"funktion": logge_position,
					"erwartung": "Positions-Sample (Log)",
					"pflicht": false,
				}
			)
		)
	(
		liste
		. append(
			{
				"name": "strasse_prompt_wache",
				"aktion": "warte_bis",
				"text": "betreten?",
				"timeout_s": 20.0,
			}
		)
	)
	liste.append({"name": "abschluss", "aktion": "warte", "sekunden": 2.0})
	return liste


func _stadt() -> CityScene:
	var szene := aktuelle_szene()
	return szene as CityScene


func _teleport(ziel: Vector3) -> bool:
	var stadt := _stadt()
	if stadt == null or stadt.karte == null or stadt.auto == null:
		return false
	# Ausparken-Maschine sauber abwürgen: NUR die Variable zu nullen ließe
	# das zuletzt kommandierte reverse/steer aktiv (Auto kreist rückwärts).
	stadt.set("_ausparken", null)
	stadt.auto.set_reverse(false)
	stadt.auto.set_steer(0.0)
	stadt.auto.teleport(ziel.x, ziel.z)
	stadt.auto.set_brake(true)
	_letzte_pos = stadt.auto.position
	print("[FLOW-DIAG] pow-sonde teleport ziel=", ziel, " auto=", stadt.auto.position)
	return true


func teleport_trigger() -> bool:
	var stadt := _stadt()
	if stadt == null or stadt.karte == null:
		return false
	return _teleport(stadt.karte.parkplatz_welt("pow"))


func teleport_strasse() -> bool:
	var stadt := _stadt()
	if stadt == null or stadt.karte == null:
		return false
	var park: Vector3 = stadt.karte.parkplatz_welt("pow")
	return _teleport(park + Vector3(6.0, 0.0, 0.0))


func logge_position() -> bool:
	var stadt := _stadt()
	if stadt == null or stadt.auto == null:
		return false
	var pos: Vector3 = stadt.auto.position
	var delta := 0.0
	if _letzte_pos != Vector3.INF:
		delta = Vector2(pos.x, pos.z).distance_to(Vector2(_letzte_pos.x, _letzte_pos.z))
	var park: Vector3 = stadt.karte.parkplatz_welt("pow")
	var d_park := Vector2(pos.x, pos.z).distance_to(Vector2(park.x, park.z))
	print(
		"[FLOW-DIAG] pow-sample auto=",
		pos,
		" delta=",
		delta,
		" d_trigger=",
		d_park,
		" speed=",
		stadt.auto.speed
	)
	_letzte_pos = pos
	return true


## Nachzügler-Wache (identisch zu den W18-Stadt-Flows): Tagesbonus/
## Coachmark/Guide-Karte blockieren sonst den BtnReise-Tipp.
func _schritte_ritual_puffer() -> Array[Dictionary]:
	return [
		{
			"name": "tagesbonus_nachzuegler",
			"aktion": "tipp_falls_da",
			"text": "Abholen!",
			"timeout_s": 45.0,
			"pflicht": false,
		},
		{"name": "bonus_zu_moment", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "coachmark_nachzuegler",
			"aktion": "tipp_falls_da",
			"text": "Alles klar!",
			"timeout_s": 10.0,
			"pflicht": false,
		},
		{
			"name": "guide_nachzuegler_wegtippen",
			"aktion": "tipp_falls_da",
			"node": "GuideBeenden",
			"timeout_s": 30.0,
			"pflicht": false,
		},
		{"name": "hud_frei_moment", "aktion": "warte", "sekunden": 2.0},
	]
