extends TestCase
## A2 „Rekord-Puls“ (G8-IDEEN A2) — Wächter für die Live-Dramaturgie im
## Minigame-Host: (1) pure Stufen-Logik RekordPuls (80 %-Schwelle,
## Überhol-Trigger EINMALIG pro Lauf, Ziel-Anker-Pfad für Erstrunden,
## Endlos ohne Ziel), (2) Host-Integration über die ECHTE Score-Pipeline
## (_on_game_score): Pill-Stufen/Gold-Override, Rekord-Banner,
## rekord_moment_fired-Signal, Grace-Marke gegen Doppel-Feuerwerk,
## (3) Reduced-Motion-Pfad: statisches Gold statt Schimmer-Tween.

const HOST_SCENE := "res://scripts/minigames/minigame_host.tscn"


## (1a) 80 %-Schwelle: Annäherung zündet genau EINMAL, erst ab ceil(0.8·best).
func test_puls_annaeherung_ab_80_prozent_einmalig() -> void:
	var puls := RekordPuls.new()
	puls.reset(100, 85)
	assert_false(puls.zeigt_ziel(), "mit Bestwert kein Ziel-Anker")
	var vorher := puls.bewerte(79)
	assert_eq(int(vorher["stufe"]), 0, "unter 80 % bleibt die Pill neutral")
	assert_false(bool(vorher["annaeherung"]), "unter 80 % kein Puls")
	var schwelle := puls.bewerte(80)
	assert_true(bool(schwelle["annaeherung"]), "ab 80 % zündet der Herzschlag")
	assert_eq(int(schwelle["stufe"]), 1, "Pill schimmert golden (Stufe 1)")
	var wieder := puls.bewerte(90)
	assert_false(bool(wieder["annaeherung"]), "Herzschlag nur EINMAL pro Runde")
	assert_eq(int(wieder["stufe"]), 1, "Stufe bleibt golden")
	var gleichstand := puls.bewerte(100)
	assert_false(bool(gleichstand["rekord"]), "Gleichstand ist noch KEIN Rekord")
	assert_eq(int(gleichstand["stufe"]), 1, "Gleichstand bleibt Stufe 1")


## (1b) Überholen: Rekord zündet einmalig bei score > best; danach nie wieder.
func test_puls_rekord_beim_ueberholen_einmalig() -> void:
	var puls := RekordPuls.new()
	puls.reset(100, 0)
	puls.bewerte(80)
	var rekord := puls.bewerte(101)
	assert_true(bool(rekord["rekord"]), "score > best zündet den Rekord-Moment")
	assert_eq(int(rekord["stufe"]), 2, "Pill wird Rekord-Gold (Stufe 2)")
	var danach := puls.bewerte(150)
	assert_false(bool(danach["rekord"]), "Rekord-Moment nur EINMAL pro Lauf")
	assert_eq(int(danach["stufe"]), 2, "Stufe 2 bleibt für den Rest der Runde")


## (1c) Sprung DIREKT über den Rekord: Annäherung wird mit verbraucht
## (max. 1 Puls pro Runde — Reizfrequenz-Bremse aus dem Ideen-Doc).
func test_puls_direktsprung_verbraucht_annaeherung() -> void:
	var puls := RekordPuls.new()
	puls.reset(10, 0)
	var sprung := puls.bewerte(25)
	assert_true(bool(sprung["rekord"]), "Direktsprung zündet den Rekord")
	assert_false(bool(sprung["annaeherung"]), "…aber keinen Annäherungs-Puls mehr")
	assert_true(puls.annaeherung_gefeuert, "Annäherung gilt als verbraucht")


## (1d) Schwellen-Mathe: ceil + Mindestwert 1 (kleine Bestwerte).
func test_puls_schwelle_ceil_und_minimum() -> void:
	assert_eq(RekordPuls.annaeherung_schwelle(100), 80, "80 % von 100")
	assert_eq(RekordPuls.annaeherung_schwelle(5), 4, "ceil(4.0) = 4")
	assert_eq(RekordPuls.annaeherung_schwelle(3), 3, "ceil(2.4) = 3")
	assert_eq(RekordPuls.annaeherung_schwelle(1), 1, "Minimum 1 Punkt")
	assert_eq(RekordPuls.annaeherung_schwelle(2), 2, "ceil(1.6) = 2")


## (1e) Erstrunde ohne Bestwert: Ziel-Anker-Pfad (einmaliger Ziel-Puls).
func test_puls_ziel_anker_erstrunde() -> void:
	var puls := RekordPuls.new()
	puls.reset(0, 85)
	assert_true(puls.zeigt_ziel(), "ohne Bestwert zeigt der Host das Ziel")
	var unterwegs := puls.bewerte(84)
	assert_false(bool(unterwegs["ziel"]), "unterm Ziel kein Puls")
	assert_eq(int(unterwegs["stufe"]), 0, "Pill bleibt neutral")
	var erreicht := puls.bewerte(85)
	assert_true(bool(erreicht["ziel"]), "Ziel erreicht → Puls")
	assert_eq(int(erreicht["stufe"]), 1, "Pill golden (Stufe 1)")
	var danach := puls.bewerte(120)
	assert_false(bool(danach["ziel"]), "Ziel-Puls nur EINMAL")
	assert_false(bool(danach["rekord"]), "ohne Bestwert gibt es keinen Rekord-Moment")


## (1f) Endlos/ohne Ziel: nichts zündet, Pill bleibt neutral.
func test_puls_ohne_best_und_ziel_still() -> void:
	var puls := RekordPuls.new()
	puls.reset(0, 0)
	assert_false(puls.zeigt_ziel(), "ohne Ziel kein Anker")
	var tick := puls.bewerte(9999)
	assert_eq(int(tick["stufe"]), 0, "nichts hebt die Stufe")
	assert_false(
		bool(tick["annaeherung"]) or bool(tick["ziel"]) or bool(tick["rekord"]),
		"kein Ereignis ohne Bestwert und Ziel"
	)


## (1g) reset() macht alle Einmal-Trigger für die nächste Runde frisch.
func test_puls_reset_macht_runde_frisch() -> void:
	var puls := RekordPuls.new()
	puls.reset(10, 0)
	puls.bewerte(11)
	assert_eq(puls.stufe, 2, "Rekord gezündet")
	puls.reset(11, 0)
	assert_eq(puls.stufe, 0, "reset → neutral")
	assert_false(puls.rekord_gefeuert, "Rekord-Trigger wieder scharf")
	assert_false(puls.annaeherung_gefeuert, "Annäherungs-Trigger wieder scharf")
	var wieder := puls.bewerte(12)
	assert_true(bool(wieder["rekord"]), "neue Runde kann wieder Rekord feiern")


## (2) Host-Integration: echte Score-Pipeline hebt die Pill-Stufen, zündet
## das Banner + Signal genau einmal und setzt die Grace-Marke (kein
## Doppel-Feuerwerk, wenn die Runde direkt nach dem Rekord endet).
func test_host_zuendet_rekord_moment_ueber_score_pipeline() -> void:
	_energie_auffuellen()
	var gs := tree.root.get_node_or_null("/root/GameState")
	assert_ne(gs, null, "GameState-Autoload vorhanden")
	if gs == null:
		return
	# Niedriger Bestwert (4, Modus normal) für carrotCatch — die „Runde“
	# unten überholt ihn sofort.
	gs.update(
		func(state: Dictionary) -> void:
			var legacy: Dictionary = state["minigames"]["legacy"]
			legacy["best"]["carrotCatch"] = 4
	)
	var host: MinigameHost = (load(HOST_SCENE) as PackedScene).instantiate()
	host.auto_navigate = false
	host.countdown_step_sec = 0.0
	host.receive_params({"game_id": "carrotCatch", "difficulty": "normal", "seed": 7})
	tree.root.add_child(host)
	await wait_frames(2)
	var gefeuert: Array = []
	host.rekord_moment_fired.connect(func() -> void: gefeuert.append(true))
	var anzeige: RekordPuls.Anzeige = host.get("_puls_anzeige")
	assert_ne(anzeige, null, "Rekord-Puls-Anzeige hängt am Host")
	var pill: Label = host.get("_score_label")
	assert_false(pill.has_theme_color_override("font_color"), "Start: Pill neutral")
	var ziel_label: Label = host.get("_ziel_label")
	assert_false(ziel_label.visible, "mit Bestwert KEIN Ziel-Anker")
	# 4 = Bestwert (Schwelle ceil(3.2)=4): Annäherung → goldener Schimmer.
	host._on_game_score(4, 4)
	assert_eq(anzeige.stufe, 1, "80 %-Zone → Stufe 1")
	assert_eq(pill.get_theme_color("font_color"), RekordPuls.PULS_GOLD, "Pill golden")
	assert_eq(gefeuert.size(), 0, "Annäherung ist noch kein Rekord")
	# 5 > Bestwert: der Live-Rekord-Moment zündet SOFORT im Host.
	host._on_game_score(5, 1)
	assert_eq(anzeige.stufe, 2, "Überholen → Stufe 2")
	assert_eq(pill.get_theme_color("font_color"), RekordPuls.REKORD_GOLD, "Rekord-Gold")
	assert_eq(gefeuert.size(), 1, "rekord_moment_fired genau einmal")
	var banner: Label = anzeige.banner
	assert_ne(banner, null, "Rekord-Banner gebaut")
	if banner != null:
		assert_true(banner.visible, "Banner sichtbar (nicht spielunterbrechend)")
		assert_eq(banner.text, I18nService.t("mg.host.rekord"), "Banner-Text aus mg.host.rekord")
		assert_eq(banner.mouse_filter, Control.MOUSE_FILTER_IGNORE, "Banner frisst keine Eingaben")
	# Grace-Marke: ein Rundenende direkt nach dem Rekord darf KEIN zweites
	# Feuerwerk stapeln (dieselbe Logik wie END_MOMENT_GRACE_MS).
	var kit: JuiceKit = host.get("juice")
	assert_true(
		Time.get_ticks_msec() - kit.win_moment_msec <= MinigameHost.END_MOMENT_GRACE_MS,
		"Rekord-Moment setzt die Grace-Marke"
	)
	# Weitere Ticks über dem Bestwert: alles bleibt bei EINEM Moment.
	host._on_game_score(9, 4)
	assert_eq(gefeuert.size(), 1, "Überhol-Trigger einmalig pro Lauf")
	host.queue_free()
	await wait_frames(2)


## (2b) Erstrunden-Pfad im Host: Ziel-Anker sichtbar, wird beim Erreichen
## golden — und der Neustart liest den frischen Bestwert (Anker weg).
func test_host_ziel_anker_und_restart_liest_best_neu() -> void:
	_energie_auffuellen()
	var gs := tree.root.get_node_or_null("/root/GameState")
	if gs == null:
		return
	# teaParty ohne Bestwert (frisch) — Ziel 85 aus der Registry.
	gs.update(
		func(state: Dictionary) -> void:
			var legacy: Dictionary = state["minigames"]["legacy"]
			legacy["best"].erase("teaParty")
	)
	var host: MinigameHost = (load(HOST_SCENE) as PackedScene).instantiate()
	host.auto_navigate = false
	host.countdown_step_sec = 0.0
	host.receive_params({"game_id": "teaParty", "difficulty": "normal", "seed": 7})
	tree.root.add_child(host)
	await wait_frames(2)
	var anzeige: RekordPuls.Anzeige = host.get("_puls_anzeige")
	var ziel_label: Label = host.get("_ziel_label")
	assert_true(ziel_label.visible, "Erstrunde → Ziel-Anker sichtbar")
	assert_eq(ziel_label.text, I18nService.t("mg.host.ziel", {"n": 85}), "Anker nennt meta.target")
	host._on_game_score(85, 85)
	assert_eq(anzeige.stufe, 1, "Ziel erreicht → Pill golden")
	assert_true(ziel_label.has_theme_color_override("font_color"), "Anker wird gold")
	# Bestwert taucht auf (wie nach einer gebuchten Runde) → der interne
	# Neustart liest ihn frisch und versteckt den Anker.
	gs.update(
		func(state: Dictionary) -> void:
			var legacy: Dictionary = state["minigames"]["legacy"]
			legacy["best"]["teaParty"] = 90
	)
	host._restart_round()
	await wait_frames(2)
	assert_false(ziel_label.visible, "mit Bestwert verschwindet der Anker")
	assert_eq(anzeige.stufe, 0, "Neustart → Pill neutral")
	var puls: RekordPuls = host.get("_puls")
	assert_eq(puls.best, 90, "Neustart liest den NEUEN Bestwert")
	host.queue_free()
	await wait_frames(2)


## (3) Reduced Motion: statisches Gold (kein Schimmer-Tween), Banner bleibt.
func test_host_reduced_motion_statisch_golden() -> void:
	_energie_auffuellen()
	var settings: Node = tree.root.get_node_or_null("/root/AppSettings")
	var gs := tree.root.get_node_or_null("/root/GameState")
	if settings == null or gs == null:
		return
	var vorher: Variant = settings.get_setting("reduced_motion", false)
	settings.set_setting("reduced_motion", true)
	gs.update(
		func(state: Dictionary) -> void:
			var legacy: Dictionary = state["minigames"]["legacy"]
			legacy["best"]["carrotCatch"] = 10
	)
	var host: MinigameHost = (load(HOST_SCENE) as PackedScene).instantiate()
	host.auto_navigate = false
	host.countdown_step_sec = 0.0
	host.receive_params({"game_id": "carrotCatch", "difficulty": "normal", "seed": 7})
	tree.root.add_child(host)
	await wait_frames(2)
	var anzeige: RekordPuls.Anzeige = host.get("_puls_anzeige")
	host._on_game_score(8, 8)
	assert_eq(anzeige.stufe, 1, "RM: Stufe hebt normal")
	assert_eq(anzeige.tween, null, "RM: KEIN Schimmer-Tween — statisch golden")
	var pill: Label = host.get("_score_label")
	assert_eq(pill.get_theme_color("font_color"), RekordPuls.PULS_GOLD, "RM: statisches Gold")
	host._on_game_score(11, 3)
	var banner: Label = anzeige.banner
	assert_true(banner != null and banner.visible, "RM: Banner erscheint trotzdem")
	settings.set_setting("reduced_motion", vorher)
	host.queue_free()
	await wait_frames(2)


func _energie_auffuellen() -> void:
	var gs := tree.root.get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("set_value"):
		gs.call("set_value", "gooby.stats.energy", 100.0)
