extends "res://tests/tools/playtest_flows/flow_pt3_basis.gd"
## PT-3 Flow (b3/d) „Einkaufsfahrt + Pause-Menü TIEF“ (Welle H): Onboarding →
## Arcade → cityDrive (3D-Fahrspiel, 6 Energie, difficulty_opt_in) → Intro-
## Beat → FAHREN wie ein Spieler (Lenk-Holds: der Flow liest van_pos/heading
## und peilt wie der eingebaute Autopilot die nächste Münze an — exakt die
## invertierte _steer_from-Formel) → PAUSE-MENÜ IN DER TIEFE: Freeze-Beweis
## (Sim-Uhr steht), Hilfe-Typewriter (mg.cityDrive.hint), Ton-Schalter
## (audio.master 0/1 + Label An/Aus), „Weiter“ mit 3-2-1-Countdown (Ziffer
## sichtbar, Uhr läuft weiter, Pause-Knopf wieder aktiv) → BACKDROP-Tap
## (PanelStack: Tap neben der Karte = Fortsetzen) → Runde zu Ende fahren
## (90 s) → Results → „Zur Arcade“ (mittlerer Rahmen-Knopf) → History-Wache
## → „Zurück“ nach Hause.
## Aufruf: tools/ci/run_playtest.sh flow_pt3_city_drive

## Lenk-Hold je Fahr-Schritt (s) — Drücken hält den Lenkwinkel konstant.
const HOLD_S := 0.9
## Wie der eingebaute Autopilot zielen (BOT_STEER_GAIN aus city_drive.gd).
const STEUER_GAIN := 1.6
## Fahr-Schritte nach den Pause-Tests (Rest der 90-s-Runde).
const FAHR_SCHRITTE := 26


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(arcade_pregame_schritte("cityDrive", "", 6.0))
	liste.append({"name": "intro_beat_ansehen", "aktion": "warte", "sekunden": 2.5})
	for i in 4:
		liste.append(_fahr_schritt("anfahren_%d" % (i + 1)))
		liste.append({"name": "rollen_%d" % (i + 1), "aktion": "warte", "sekunden": 0.5})
	liste.append_array(_pause_tief_schritte())
	for i in 2:
		liste.append(_fahr_schritt("wieder_fahren_%d" % (i + 1)))
		liste.append({"name": "wieder_rollen_%d" % (i + 1), "aktion": "warte", "sekunden": 0.5})
	liste.append_array(_backdrop_schritte())
	for i in FAHR_SCHRITTE:
		liste.append(_fahr_schritt("fahren_%02d" % (i + 1)))
		liste.append({"name": "fahrt_%02d" % (i + 1), "aktion": "warte", "sekunden": 1.0})
	(
		liste
		. append_array(
			[
				{
					"name": "runde_zu_ende",
					"aktion": "warte_bis",
					"bedingung": rundenende_da,
					"timeout_s": 300.0,
				},
				{"name": "results_zaehlen_lassen", "aktion": "warte", "sekunden": 4.0},
				{
					"name": "fahrt_ausbeute_loggen",
					"aktion": "tue",
					"funktion": ausbeute_loggen,
				},
				{
					"name": "muenzen_gutgeschrieben",
					"aktion": "tue",
					"funktion": pruefe_coins_gestiegen.bind("start_coins"),
					"erwartung": "Fahr-Score > 0 → Münz-Award gebucht",
					"pflicht": false,
				},
				# Mittlerer Rahmen-Knopf (G7-P56): zurück in die Arcade.
				{
					"name": "zur_arcade",
					"aktion": "tipp_text",
					"text": "Zur Arcade",
					"erwarte": {"route": "arcade"},
					"timeout_s": 120.0,
				},
				{
					"name": "history_sauber_arcade",
					"aktion": "tue",
					"funktion": history_sauber,
					"erwartung": "mg_host/mg_pregame NICHT in der History",
				},
				{
					"name": "zurueck_nach_hause",
					"aktion": "tipp_text",
					"text": "Zurück",
					"erwarte": {"route": "home/living"},
					"timeout_s": 120.0,
				},
				{"name": "abschluss_wohnzimmer", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


## Ein Lenk-Hold: Position kommt ERST bei Ausführung aus fahr_punkt().
func _fahr_schritt(schritt_name: String) -> Dictionary:
	return {
		"name": schritt_name,
		"aktion": "halte",
		"pos_funktion": fahr_punkt,
		"dauer_s": HOLD_S,
		"pflicht": false,
	}


## Das Pause-Menü in der Tiefe (FB3/G7-P56) — Freeze, Hilfe, Ton, 3-2-1.
func _pause_tief_schritte() -> Array[Dictionary]:
	return [
		{"name": "fahrt_loggen", "aktion": "tue", "funktion": fahrt_loggen},
		{
			"name": "pause_oeffnen",
			"aktion": "tipp_text",
			"text": "Pause",
			"erwarte": {"text": "Beenden"},
			"timeout_s": 30.0,
		},
		# Uhr ERST merken, wenn das Modal offen ist (Lauf pt3_d1: zwischen
		# Merken und Freeze lagen 0,57 s Tap-/Modal-Latenz → Fehlalarm).
		{"name": "modal_setzen_lassen", "aktion": "warte", "sekunden": 0.8},
		{
			"name": "uhr_unter_pause_merken",
			"aktion": "tue",
			"funktion": merke_elapsed.bind("pause1"),
		},
		{"name": "pause_wirken_lassen", "aktion": "warte", "sekunden": 2.5},
		{
			"name": "pause_friert_ein",
			"aktion": "tue",
			"funktion": elapsed_steht.bind("pause1"),
			"erwartung": "Sim-Uhr steht unter der Pause (SubViewport DISABLED)",
		},
		# Hilfe-Chip: der Spiel-Hint (mg.cityDrive.hint) tickt als
		# Typewriter in die Karte — „rosa Ringe“ ist cityDrive-spezifisch.
		{
			"name": "hilfe_oeffnen",
			"aktion": "tipp_text",
			"text": "Hilfe",
			"erwarte": {"text": "rosa Ringe"},
			"timeout_s": 30.0,
		},
		{"name": "hilfe_lesen", "aktion": "warte", "sekunden": 2.5},
		# Ton-Schalter: Label kippt auf „Ton: Aus“ UND audio.master → 0.
		{
			"name": "ton_aus_schalten",
			"aktion": "tipp_text",
			"text": "Ton",
			"erwarte": {"text": "Ton: Aus"},
			"timeout_s": 20.0,
		},
		{
			"name": "ton_aus_geprueft",
			"aktion": "tue",
			"funktion": ton_pruefen.bind(0.0),
			"erwartung": "audio.master == 0 nach dem Aus-Schalter",
		},
		{
			"name": "ton_wieder_an",
			"aktion": "tipp_text",
			"text": "Ton: Aus",
			"erwarte": {"text": "Ton: An"},
			"timeout_s": 20.0,
		},
		{
			"name": "ton_an_geprueft",
			"aktion": "tue",
			"funktion": ton_pruefen.bind(1.0),
			"erwartung": "audio.master == 1 nach dem An-Schalter",
		},
		# „Weiter“ → NICHT sofort weiter: erst die 3-2-1-Ziffer (EF-3),
		# dann läuft die Runde (spiel_aktiv) und die Uhr tickt wieder.
		{
			"name": "weiter_tippen",
			"aktion": "tipp_text",
			"text": "Weiter",
			"erwarte": {"bedingung": countdown_sichtbar},
			"timeout_s": 30.0,
		},
		{
			"name": "resume_countdown_abwarten",
			"aktion": "warte_bis",
			"bedingung": spiel_aktiv,
			"timeout_s": 60.0,
		},
		{
			"name": "pause_knopf_wieder_aktiv",
			"aktion": "warte_bis",
			"bedingung": pause_knopf_aktiv,
			"timeout_s": 20.0,
		},
		{"name": "nach_resume_rollen", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "uhr_laeuft_wieder",
			"aktion": "tue",
			"funktion": elapsed_laeuft.bind("pause1"),
			"erwartung": "Sim-Uhr läuft nach dem Resume weiter",
		},
	]


## Backdrop-Kontrakt (PanelStack): Tap NEBEN der Karte = Fortsetzen.
func _backdrop_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "pause_wieder_oeffnen",
			"aktion": "tipp_text",
			"text": "Pause",
			"erwarte": {"text": "Beenden"},
			"timeout_s": 30.0,
		},
		{
			"name": "backdrop_tippen",
			"aktion": "tipp_pos",
			"pos_rel": Vector2(0.5, 0.06),
			"erwarte": {"weg_text": "Beenden"},
			"timeout_s": 20.0,
		},
		{
			"name": "backdrop_resume_abwarten",
			"aktion": "warte_bis",
			"bedingung": spiel_aktiv,
			"timeout_s": 60.0,
		},
	]


## Lenken wie der eingebaute Autopilot (BOT_STEER_GAIN-Formel), aber über
## ECHTE Touch-Eingabe: Ziel = nächste Münze (Checkpoint zählt mit), steer
## = clamp(Winkeldiff × 1.6) und dann die INVERSE von _steer_from — Tap-X
## = Mitte + steer × 0.4 × Breite. Kein Spiel/pausiert → Tap verpufft.
func fahr_punkt() -> Vector2:
	var g := spiel()
	if g == null or not bool(g.get("running")) or bool(g.get("finished")):
		return Vector2.ZERO
	if bool(g.get("game_paused")) or float(g.get("_intro_left")) > 0.0:
		return Vector2.ZERO
	var pos: Vector2 = g.get("van_pos")
	var heading := float(g.get("van_heading"))
	var ziel := _naechste_muenze(g, pos)
	var to := ziel - pos
	if to.length() < 0.5:
		return Vector2.ZERO
	var want := atan2(to.x, -to.y)
	var diff := wrapf(want - heading, -PI, PI)
	var steer := clampf(diff * STEUER_GAIN, -1.0, 1.0)
	var vp := spiel_viewport()
	return spiel_punkt(Vector2(vp.x * (0.5 + steer * 0.4), vp.y * 0.75))


## Sim-Uhr des laufenden Spiels merken (Freeze-Beweis der Pause).
func merke_elapsed(key: String) -> bool:
	var g := spiel()
	if g == null:
		return false
	return _merke(key, float(g.get("elapsed")))


## Steht die Sim-Uhr seit merke_elapsed(key)? (Pause friert WIRKLICH ein —
## der Host schaltet den SubViewport-Ast auf PROCESS_MODE_DISABLED.)
func elapsed_steht(key: String) -> bool:
	var g := spiel()
	if g == null:
		return false
	var vorher := float(zettel.get(key, -1.0))
	var ist := float(g.get("elapsed"))
	print("[PT3] Sim-Uhr: gemerkt %.2f, jetzt %.2f (Pause)" % [vorher, ist])
	return absf(ist - vorher) < 0.05


## Läuft die Sim-Uhr seit merke_elapsed(key) wieder? (Nach Resume.)
func elapsed_laeuft(key: String) -> bool:
	var g := spiel()
	if g == null:
		return false
	var vorher := float(zettel.get(key, -1.0))
	var ist := float(g.get("elapsed"))
	print("[PT3] Sim-Uhr: gemerkt %.2f, jetzt %.2f (nach Resume)" % [vorher, ist])
	return ist > vorher + 0.3


## AppSettings audio.master gegen Sollwert prüfen (Pause-Ton-Schalter).
func ton_pruefen(soll: float) -> bool:
	var settings := harness.root.get_node_or_null("/root/AppSettings")
	if settings == null:
		return false
	var ist := float(settings.call("get_setting", "audio.master", 1.0))
	print("[PT3] audio.master = %.1f (soll %.1f)" % [ist, soll])
	return absf(ist - soll) < 0.01


## Spiegel von _nearest_coin(): nächstliegende Münze oder der Checkpoint.
func _naechste_muenze(g: Node, pos: Vector2) -> Vector2:
	var best: Vector2 = g.get("_checkpoint")
	var best_d := pos.distance_to(best)
	var muenzen: Array = g.get("_coins")
	for coin: Vector2 in muenzen:
		var d := pos.distance_to(coin)
		if d < best_d:
			best_d = d
			best = coin
	return best


## Fahr-Zwischenstand in den Log (Beleg fürs Protokoll).
func fahrt_loggen() -> bool:
	var g := spiel()
	if g == null:
		print("[PT3] Fahrt: kein Spiel (mehr)")
		return true
	print(
		(
			"[PT3] Fahrt: Score %d, Münzen %d, Checkpoints %d, Crashes %d, %.1f s"
			% [
				int(g.get("score")),
				int(g.get("pickups")),
				int(g.get("checkpoints")),
				int(g.get("crashes")),
				float(g.get("elapsed")),
			]
		)
	)
	return true


## Runden-Ausbeute nach dem Ende (Spiel lebt eingefroren unter den Results).
func ausbeute_loggen() -> bool:
	return fahrt_loggen()
