extends "res://tests/tools/playtest_flows/flow_pt1_helfer.gd"
## Flow PT1 (d) „Gooby-Zuwendung“: Boot → Onboarding → STREICHELN (echter
## 3D-Tap auf Gooby bucht petsToday, dann 11-Tap-Burst über den öffentlichen
## handle_tap → Übermut-Gag W15/VOICE2: refuse + „Paus-e-e!“-Bitte) → BALL
## (Flick über dem WurfBall — die Harness-Drags haben velocity=0, BallLogic
## wirft trotzdem den Mindest-Bogen — Gooby apportiert, Kopfstoß, balls-
## Counter +1, +3 Spaß) → ANTWORT-CHIPS (gruss_eingeschnappt hat chance 1.0:
## Chips erscheinen, „Tut mir leid“ antworten → Slice-Eintrag + Follow-up;
## danach gruss_vermisst-Chips unbeantwortet lassen → 12-s-Timeout räumt ab).
## Aufruf: tools/ci/run_playtest.sh flow_pt1_zuwendung

## StreichelUebermut.MAX_PETS=10 — ein Burst MIT Reserve reißt das Fenster.
const BURST_TAPS := 12


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = [
		{
			"name": "events_stilllegen",
			"aktion": "tue",
			"funktion": _events_stilllegen,
			"erwartung": "Random-Events liegen für den Lauf auf Cooldown",
		},
	]
	liste.append_array(onboarding_schritte())
	liste.append_array(_streichel_schritte())
	liste.append_array(_ball_schritte())
	liste.append_array(_chips_schritte())
	return liste


# ---------------------------------------------------------------- Abschnitte


## Streicheln: 1 echter Tap (Area3D-Pfad), dann Burst → Übermut-Gag.
func _streichel_schritte() -> Array[Dictionary]:
	return [
		{"name": "ankommen", "aktion": "warte", "sekunden": 2.0},
		{"name": "streichel_stand_merken", "aktion": "tue", "funktion": _merke_streicheln},
		{
			"name": "gooby_echt_antippen",
			"aktion": "tipp_3d",
			"finder": gooby_node,
			"offset": Vector3(0.0, 0.35, 0.0),
			"erwarte": {"bedingung": _pets_gestiegen},
			"timeout_s": 30.0,
			"erwartung": "Tap auf die GoobyTapArea bucht petsToday +1",
		},
		{"name": "kicher_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "streichel_burst",
			"aktion": "tue",
			"funktion": _streichel_burst,
			"erwartung": "12 Streichler im 30-s-Fenster (Übermut-Schwelle >10)",
		},
		{
			"name": "uebermut_gag_bubble",
			"aktion": "warte_bis",
			"text": "zerzaust",
			"timeout_s": 12.0,
			"erwartung": "Übermut-Gag sagt 'Paus-e-e! Mein Fell ist ganz zerzaust!'",
		},
		{
			"name": "streichel_fakten",
			"aktion": "tue",
			"funktion": _streichel_fakten,
			"erwartung": "petsToday >= 13 und tickles-Zähler gestiegen (Kitzlig-Stufe)",
		},
		{"name": "gag_ansehen", "aktion": "warte", "sekunden": 2.0},
	]


## Ball werfen: Gooby herholen (Apport-Gate <= 3,2 m), Flick, Zyklus beobachten.
func _ball_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "ball_liegt_bereit",
			"aktion": "tue",
			"funktion": _ball_bereit,
			"erwartung": "WurfBall im Wohnzimmer, Zustand RUHT (balls/fun gemerkt)",
		},
		{"name": "gooby_heranrufen", "aktion": "tue", "funktion": _gooby_zum_ball},
		{
			"name": "gooby_nah_am_ball",
			"aktion": "warte_bis",
			"bedingung": _gooby_nah,
			"timeout_s": 30.0,
			"pflicht": false,
		},
		{
			"name": "ball_flick",
			"aktion": "wisch",
			"von_funktion": _ball_canvas,
			"nach_funktion": _ball_canvas_hoch,
			"dauer_s": 0.35,
		},
		{
			"name": "apport_zyklus",
			"aktion": "warte_bis",
			"bedingung": _apport_beobachtet,
			"timeout_s": 90.0,
			"erwartung": "FLIEGT→GOOBY_HOLT→BRINGT_ZURUECK, balls-Counter +1",
		},
		{
			"name": "apport_fakten",
			"aktion": "tue",
			"funktion": _apport_fakten,
			"erwartung": "balls +1 gebucht; Apport-Zustände beobachtet",
		},
		{"name": "apport_ansehen", "aktion": "warte", "sekunden": 2.0},
	]


## Antwort-Chips: deterministischer Anlass (chance 1.0), antworten, Timeout.
func _chips_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "alte_chips_abwarten",
			"aktion": "warte_bis",
			"bedingung": _chips_weg,
			"timeout_s": 20.0,
			"pflicht": false,
		},
		{
			"name": "gespraech_ausloesen",
			"aktion": "tue",
			"funktion": _gespraech_starten.bind("gruss_eingeschnappt"),
			"erwarte": {"bedingung": _chips_da},
			"timeout_s": 15.0,
			"erwartung": "stoss_gruss(gruss_eingeschnappt) öffnet die Antwort-Chips",
		},
		{"name": "chips_ansehen", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "chip_antworten",
			"aktion": "tipp_text",
			"text": "Tut mir leid",
			"erwarte": {"bedingung": _antwort_verbucht},
			"timeout_s": 20.0,
			"erwartung": "Antwort 'entschuldigen' landet im Soul-Slice (gespraeche)",
		},
		{
			"name": "chips_nach_antwort_weg",
			"aktion": "warte_bis",
			"bedingung": _chips_weg,
			"timeout_s": 10.0,
		},
		{
			"name": "folge_line_da",
			"aktion": "warte_bis",
			"bedingung": _folge_line_da,
			"timeout_s": 10.0,
			"pflicht": false,
		},
		{
			"name": "gespraech_zwei_ausloesen",
			"aktion": "tue",
			"funktion": _gespraech_starten.bind("gruss_vermisst"),
			"erwarte": {"bedingung": _chips_da},
			"timeout_s": 15.0,
			"erwartung": "gruss_vermisst (chance 1.0) öffnet die zweiten Chips",
		},
		{
			"name": "chips_timeout_raeumt_ab",
			"aktion": "warte_bis",
			"bedingung": _chips_weg,
			"timeout_s": 25.0,
			"erwartung": "Unbeantwortete Chips verschwinden nach CHIP_TIMEOUT_S=12 selbst",
		},
		{"name": "abschluss_zuwendung", "aktion": "warte", "sekunden": 2.0},
	]


# ---------------------------------------------------------------- Streicheln


func _merke_streicheln() -> bool:
	var pets := zahl("achievements.counters.petsToday", 0.0)
	var tickles := zahl("achievements.counters.tickles", 0.0)
	return merke("pets_vorher", pets) and merke("tickles_vorher", tickles)


func _pets_gestiegen() -> bool:
	return zahl("achievements.counters.petsToday", -1.0) > float(wert("pets_vorher", 999.0))


## 12 Streichler in einem Rutsch über den ÖFFENTLICHEN handle_tap()-Pfad
## (Tests rufen direkt, s. gooby_reactions.gd) — echte Taps schaffen das
## 30-s-Fenster unter llvmpipe nicht zuverlässig. Der Gag muss beim
## 11. Stempel feuern (StreichelUebermut.MAX_PETS=10).
func _streichel_burst() -> bool:
	var runner := gooby_runner()
	if runner == null or not runner.has_method("handle_tap"):
		print("[PT1] streichel_burst: kein GoobyReactions-Runner")
		return false
	for i in BURST_TAPS:
		runner.handle_tap()
	return true


func _streichel_fakten() -> bool:
	var pets := zahl("achievements.counters.petsToday", -1.0)
	var tickles := zahl("achievements.counters.tickles", -1.0)
	var pets_soll := float(wert("pets_vorher", 999.0)) + 1.0 + float(BURST_TAPS)
	print("[PT1] Streicheln: petsToday=%s (soll %s) tickles=%s" % [pets, pets_soll, tickles])
	return pets >= pets_soll and tickles > float(wert("tickles_vorher", 999.0))


# ---------------------------------------------------------------- Ball


func _ball_node() -> Node:
	return _finde_klasse(aktuelle_szene(), "WurfBall")


## Welt-Liegepunkt des Balls (Node-Anker + BallLogic-Lokalposition).
func _ball_welt() -> Vector3:
	var ball := _ball_node()
	if ball == null:
		return Vector3.ZERO
	return (ball as Node3D).global_position + (ball.get("logic").get("pos") as Vector3)


func _ball_bereit() -> bool:
	var ball := _ball_node()
	if ball == null:
		print("[PT1] BALL FEHLT im Wohnzimmer!")
		return false
	var zustand := str(ball.get("logic").get("zustand"))
	print("[PT1] Ball: zustand=%s welt=%s" % [zustand, str(_ball_welt())])
	var ok_merken := (
		merke("balls_vorher", zahl("achievements.counters.balls", 0.0))
		and merke("fun_vorher", zahl("gooby.stats.fun", -1.0))
		and merke("ball_zustaende", [] as Array)
	)
	return ok_merken and zustand == "RUHT"


## Gooby neben den Ball schicken (Apport-Gate: 0,05–3,2 m bei der Landung).
## Kein Spieler-Feature — nur Test-Determinismus gegen weite Wander-Wege.
func _gooby_zum_ball() -> bool:
	var gooby := gooby_node()
	if gooby == null:
		return false
	if _gooby_nah():
		return true
	gooby.walk_to(_ball_welt() + Vector3(0.45, 0.0, 0.45), 5.0)
	return true


func _gooby_nah() -> bool:
	var gooby := gooby_node()
	if gooby == null:
		return false
	var ball := _ball_welt()
	var von := gooby.global_position
	var dist := Vector2(ball.x - von.x, ball.z - von.z).length()
	return dist > 0.15 and dist < 2.6


## Canvas-Punkt über dem liegenden Ball (Flick-Start).
func _ball_canvas() -> Vector2:
	var kamera := harness.root.get_camera_3d()
	if kamera == null:
		return Vector2(1280, 720) * 0.5
	return kamera.unproject_position(_ball_welt())


func _ball_canvas_hoch() -> Vector2:
	return _ball_canvas() + Vector2(0.0, -170.0)


## Frame-Beobachter des Wurf-Zyklus (Muster _sequenz_beobachtet): notiert
## jeden gesehenen BallLogic-Zustand; fertig, wenn der balls-Counter bucht.
func _apport_beobachtet() -> bool:
	var ball := _ball_node()
	if ball != null:
		var zustand := str(ball.get("logic").get("zustand"))
		var gesehen: Array = wert("ball_zustaende", [] as Array)
		if not gesehen.has(zustand):
			gesehen.append(zustand)
			merke("ball_zustaende", gesehen)
	return zahl("achievements.counters.balls", -1.0) > float(wert("balls_vorher", 999.0))


func _apport_fakten() -> bool:
	var balls := zahl("achievements.counters.balls", -1.0)
	var fun := zahl("gooby.stats.fun", -1.0)
	var gesehen: Array = wert("ball_zustaende", [] as Array)
	print(
		(
			"[PT1] Apport: balls %s→%s fun %s→%s zustaende=%s"
			% [wert("balls_vorher"), balls, wert("fun_vorher"), fun, str(gesehen)]
		)
	)
	return balls == float(wert("balls_vorher", 999.0)) + 1.0


# ---------------------------------------------------------------- Chips


## Mini-Gespräch deterministisch anstoßen: die beiden Anlässe mit chance 1.0
## laufen über den ÖFFENTLICHEN SeeleRunner.stoss_gruss (der Hook, den auch
## jeder echte Betreten-Moment durchläuft).
func _gespraech_starten(anlass_id: String) -> bool:
	var seele_node := seele()
	if seele_node == null or not seele_node.has_method("stoss_gruss"):
		print("[PT1] gespraech: kein SeeleRunner")
		return false
	seele_node.stoss_gruss(anlass_id)
	return true


func _chips_da() -> bool:
	return control_da("GoobyGespraechChips")


func _chips_weg() -> bool:
	return control_weg("GoobyGespraechChips")


## Slice-Beweis: die Antwort steht unter soul.gespraeche.eingeschnappt.
func _antwort_verbucht() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var gefuehrt: Dictionary = SoulState.slice_of(gs).get("gespraeche", {})
	var eintrag: Variant = gefuehrt.get("eingeschnappt", {})
	if not (eintrag is Dictionary):
		return false
	return str((eintrag as Dictionary).get("antwort", "")) == "entschuldigen"


## Follow-up-Line f1/f2 der Entschuldigen-Antwort (soul_lines.json).
func _folge_line_da() -> bool:
	return text_da("Schmollen") or text_da("Angenommen")
