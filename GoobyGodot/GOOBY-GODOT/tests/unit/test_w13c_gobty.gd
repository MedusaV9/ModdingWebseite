extends TestCase
## W13C/GOBTY — GOB.TY, der Gooby-Fernsehsender (Doc H §6.2, P6 Punkt 7):
## Programm-Defs (5 Puppet-Clips, datengetrieben), deterministischer
## Schritt-Ablauf (Zeit injiziert), Zapping-/Auto-Rotation, Fun-Gutschrift
## mit Sitzungs-Cap über die Stats-API, Schlagzeilen-Rotation, der
## Wetter-Clip liest den ECHTEN SoulWetter-Plan von morgen, DE↔EN-Strings
## und das Host-Docking im echten Wohnzimmer (Muster test_w13_auge/
## test_w13_food_nougat) inkl. An/Zapp/Aus-Sitzung mit gepinnter Uhr.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

## Festes Test-Datum: alle() bekommt IMMER das Morgen-Datum injiziert.
const HEUTE := "2026-03-10"

var _seq := 0

# ── Programm-Defs ─────────────────────────────────────────────────────────────


func test_programm_hat_fuenf_clips_in_sendeplatz_reihenfolge() -> void:
	var programm := GobtyClipDefs.alle(GobtyClipDefs.datum_morgen(HEUTE))
	assert_eq(programm.size(), 5, "5 Puppet-Clips (Doc H §6.2)")
	for i in programm.size():
		assert_eq(str(programm[i]["id"]), GobtyClipDefs.CLIP_IDS[i], "Sendeplatz %d stimmt" % i)
		_pruefe_clip(programm[i])


func _pruefe_clip(clip: Dictionary) -> void:
	var id := str(clip["id"])
	assert_true(float(clip["dauer_s"]) > 0.0, "%s: Dauer > 0" % id)
	var schritte: Array = clip["schritte"]
	assert_true(not schritte.is_empty(), "%s: hat Schritte" % id)
	assert_almost(float((schritte[0] as Dictionary)["t"]), 0.0, 1e-6, "%s: Schritt 0 bei t=0" % id)
	var vorher := -1.0
	for schritt: Dictionary in schritte:
		var t := float(schritt["t"])
		assert_true(t > vorher, "%s: t streng aufsteigend (%f)" % [id, t])
		assert_true(t < float(clip["dauer_s"]), "%s: Schritt liegt im Clip (%f)" % [id, t])
		vorher = t
		for feld: String in ["emotion", "zuschauer"]:
			var wert := str(schritt[feld])
			assert_true(
				wert == "" or GoobyRig.EMOTIONS.has(wert),
				"%s: %s '%s' ist eine Rig-Emotion" % [id, feld, wert]
			)
		assert_true(int(schritt["sprecher"]) >= -1 and int(schritt["sprecher"]) <= 1)


func test_strings_de_en_paritaetisch_fuer_alle_referenzierten_keys() -> void:
	I18nService.reset_cache()
	var de: Dictionary = I18nService.table("de")
	var en: Dictionary = I18nService.table("en")
	var keys: Array[String] = ["gobty.an", "gobty.aus", "gobty.aus_knopf", "gobty.zapp"]
	keys.append_array(["gobty.news.intro", "gobty.wetter.intro", "gobty.wetter.banner"])
	for i in GobtyClipDefs.SCHLAGZEILEN_ANZAHL:
		keys.append("gobty.news.schlagzeile%d" % (i + 1))
	for typ: String in RanchWetter.TYPEN + ["schnee"] as Array[String]:
		keys.append("gobty.wetter.typ.%s" % typ)
	for clip: Dictionary in GobtyClipDefs.alle(GobtyClipDefs.datum_morgen(HEUTE)):
		keys.append(str(clip["titel_key"]))
		for schritt: Dictionary in clip["schritte"]:
			if str(schritt["banner_key"]) != "":
				keys.append(str(schritt["banner_key"]))
	for key: String in keys:
		assert_true(de.has(key), "DE-String fehlt: %s" % key)
		assert_true(en.has(key), "EN-String fehlt: %s" % key)


# ── Deterministischer Ablauf (Zeit injiziert) ─────────────────────────────────


func test_schritt_index_deterministisch_schritt_n_zur_zeit_t() -> void:
	for clip: Dictionary in GobtyClipDefs.alle(GobtyClipDefs.datum_morgen(HEUTE)):
		var schritte: Array = clip["schritte"]
		for i in schritte.size():
			var t := float((schritte[i] as Dictionary)["t"])
			assert_eq(
				GobtyClipPlayer.schritt_index(clip, t),
				i,
				"%s: zur Zeit t=%f läuft Schritt %d" % [clip["id"], t, i]
			)
			assert_eq(
				GobtyClipPlayer.schritt_index(clip, t - 0.001),
				i - 1,
				"%s: kurz vor t=%f läuft noch Schritt %d" % [clip["id"], t, i - 1]
			)
		assert_eq(
			GobtyClipPlayer.schritt_index(clip, float(clip["dauer_s"])),
			schritte.size() - 1,
			"%s: am Clip-Ende ist der letzte Schritt aktiv" % clip["id"]
		)


func test_tick_liefert_neue_schritte_genau_einmal() -> void:
	var player := GobtyClipPlayer.new(GobtyClipDefs.alle(GobtyClipDefs.datum_morgen(HEUTE)))
	player.start(1_000_000)
	var erster := player.tick(1_000_000)
	assert_eq((erster["schritte"] as Array).size(), 1, "t=0: genau Schritt 0")
	var t1 := 1_000_000 + int(float(player.aktueller_clip()["schritte"][1]["t"]) * 1000.0)
	var zweiter := player.tick(t1)
	assert_eq((zweiter["schritte"] as Array).size(), 1, "Schritt 1 kommt genau einmal")
	assert_eq(zweiter["schritte"][0], player.aktueller_clip()["schritte"][1], "… und ist Schritt 1")
	assert_eq((player.tick(t1)["schritte"] as Array).size(), 0, "gleicher Takt: nichts doppelt")


func test_zapping_rotation_ueber_alle_sendeplaetze() -> void:
	var player := GobtyClipPlayer.new(GobtyClipDefs.alle(GobtyClipDefs.datum_morgen(HEUTE)))
	player.start(0)
	assert_eq(str(player.aktueller_clip()["id"]), "news", "Einschalten: Sendeplatz 1")
	var reihenfolge: Array[String] = []
	for i in 5:
		player.zap(1_000 * (i + 1))
		reihenfolge.append(str(player.aktueller_clip()["id"]))
	assert_eq(
		reihenfolge,
		["kochen", "sport", "wetter", "nacht", "news"] as Array[String],
		"Zapping rotiert und wickelt um"
	)


func test_auto_rotation_am_clip_ende() -> void:
	var player := GobtyClipPlayer.new(GobtyClipDefs.alle(GobtyClipDefs.datum_morgen(HEUTE)))
	player.start(0)
	player.tick(0)
	var dauer_ms := int(float(player.aktueller_clip()["dauer_s"]) * 1000.0)
	var kurz_davor := player.tick(dauer_ms - 1)
	assert_false(bool(kurz_davor["clip_gewechselt"]), "kurz vor Clip-Ende: kein Wechsel")
	var wechsel := player.tick(dauer_ms)
	assert_true(bool(wechsel["clip_gewechselt"]), "Clip-Ende: Auto-Rotation")
	assert_eq(str(player.aktueller_clip()["id"]), "kochen", "… zum nächsten Sendeplatz")
	assert_eq((wechsel["schritte"] as Array).size(), 1, "neuer Clip startet sofort mit Schritt 0")


func test_fun_gutschrift_mit_sitzungs_cap() -> void:
	var player := GobtyClipPlayer.new(GobtyClipDefs.alle(GobtyClipDefs.datum_morgen(HEUTE)))
	player.start(0)
	assert_eq(int(player.tick(0)["fun_delta"]), 0, "Einschalten: noch kein Spaß")
	assert_eq(int(player.tick(29_999)["fun_delta"]), 0, "unter 30 s: nichts")
	assert_eq(int(player.tick(30_000)["fun_delta"]), 1, "30 s: +1 Spaß")
	assert_eq(int(player.tick(90_000)["fun_delta"]), 2, "90 s: +2 nachgeholt")
	player.zap(100_000)
	assert_eq(int(player.tick(150_000)["fun_delta"]), 2, "Zapping resetted die Sitzung NICHT")
	assert_eq(int(player.tick(400_000)["fun_delta"]), 5, "Cap: nur noch bis +10 gesamt")
	assert_eq(int(player.tick(9_999_000)["fun_delta"]), 0, "über dem Cap: nichts mehr")
	assert_eq(player.fun_gutgeschrieben(), GobtyClipPlayer.FUN_CAP, "Sitzung ausgeschöpft")


func test_wende_fun_an_nutzt_stats_api_mit_clamp() -> void:
	var state := {
		"gooby": {"stats": {"hunger": 40.0, "energy": 50.0, "hygiene": 60.0, "fun": 70.0}}
	}
	GobtyClipPlayer.wende_fun_an(state, 3)
	assert_almost(float(state["gooby"]["stats"]["fun"]), 73.0, 1e-6, "+3 Spaß gebucht")
	assert_almost(float(state["gooby"]["stats"]["energy"]), 50.0, 1e-6, "Energie unberührt")
	state["gooby"]["stats"]["fun"] = 95.0
	GobtyClipPlayer.wende_fun_an(state, 10)
	assert_almost(float(state["gooby"]["stats"]["fun"]), 100.0, 1e-6, "Stats.clamp deckelt bei 100")
	GobtyClipPlayer.wende_fun_an(state, 0)
	assert_almost(float(state["gooby"]["stats"]["fun"]), 100.0, 1e-6, "0-Delta ist ein No-op")


# ── Schlagzeilen + Wetter ─────────────────────────────────────────────────────


func test_schlagzeilen_rotation_deckt_alle_zehn() -> void:
	var gesehen: Dictionary = {}
	for rotation in 10:
		for slot in GobtyClipDefs.SCHLAGZEILEN_SLOTS:
			gesehen[GobtyClipDefs.schlagzeilen_key(rotation, slot)] = true
	assert_eq(
		gesehen.size(),
		GobtyClipDefs.SCHLAGZEILEN_ANZAHL,
		"Rotation erreicht alle %d Schlagzeilen" % GobtyClipDefs.SCHLAGZEILEN_ANZAHL
	)
	var player := GobtyClipPlayer.new(GobtyClipDefs.alle(GobtyClipDefs.datum_morgen(HEUTE)))
	player.start(0)
	var erster_durchlauf := player.schlagzeile_fuer({"slot": 0})
	assert_eq(erster_durchlauf, GobtyClipDefs.schlagzeilen_key(0, 0), "Durchlauf 0, Slot 0")
	for i in 5:
		player.zap(1_000 * (i + 1))  # einmal rum → wieder News
	assert_eq(str(player.aktueller_clip()["id"]), "news")
	assert_eq(
		player.schlagzeile_fuer({"slot": 0}),
		GobtyClipDefs.schlagzeilen_key(1, 0),
		"zweiter News-Durchlauf zeigt die nächsten Schlagzeilen"
	)


func test_datum_morgen_inkl_monats_und_jahreswechsel() -> void:
	assert_eq(GobtyClipDefs.datum_morgen("2026-03-10"), "2026-03-11")
	assert_eq(GobtyClipDefs.datum_morgen("2026-01-31"), "2026-02-01", "Monatswechsel")
	assert_eq(GobtyClipDefs.datum_morgen("2026-12-31"), "2027-01-01", "Jahreswechsel")
	assert_eq(GobtyClipDefs.datum_morgen("2028-02-28"), "2028-02-29", "Schaltjahr")


func test_wetter_clip_liest_echten_plan_von_morgen() -> void:
	var morgen := GobtyClipDefs.datum_morgen(HEUTE)
	var programm := GobtyClipDefs.alle(morgen)
	var wetter_clip: Dictionary = programm[3]
	assert_eq(str(wetter_clip["id"]), "wetter")
	var symbol_schritte: Array[Dictionary] = []
	for schritt: Dictionary in wetter_clip["schritte"]:
		if not (schritt["wetter"] as Dictionary).is_empty():
			symbol_schritte.append(schritt)
	assert_eq(
		symbol_schritte.size(),
		GobtyClipDefs.WETTER_STUNDEN.size(),
		"je Abtast-Stunde ein Symbol-Schritt"
	)
	for schritt: Dictionary in symbol_schritte:
		var daten: Dictionary = schritt["wetter"]
		var stunde := float(daten["stunde"])
		assert_true(GobtyClipDefs.WETTER_STUNDEN.has(stunde), "Abtast-Stunde aus der Def-Liste")
		assert_eq(
			str(daten["typ"]),
			str(SoulWetter.zustand(morgen, stunde)["typ"]),
			"Symbol %s Uhr = ECHTER SoulWetter-Plan von morgen" % stunde
		)
		assert_eq(str(schritt["fx"]), "symbol", "Wetter-Schritt tauscht das Symbol")
	# Winter-Gag bleibt erhalten: im Januar kann der Plan Schnee ansagen —
	# der Typ ist dann einer, für den es ein Symbol + einen String gibt.
	for eintrag: Dictionary in GobtyClipDefs.wetter_symbole("2026-01-15"):
		var typ := str(eintrag["typ"])
		assert_true(
			(RanchWetter.TYPEN + ["schnee"] as Array[String]).has(typ),
			"Wintertyp bekannt: %s" % typ
		)


# ── Host-Docking + Sitzung im echten Wohnzimmer ───────────────────────────────


func test_tv_mapping_dockt_im_wohnzimmer_an() -> void:
	assert_true(Fernseher.TV_IDS.has("televisionModern"), "Flach-TV empfängt GOB.TY")
	assert_true(Fernseher.TV_IDS.has("televisionVintage"), "Röhren-TV empfängt GOB.TY")
	assert_false(Fernseher.TV_IDS.has("deskMonitor"), "der PC-Monitor bleibt ein PC")
	var gs := _fresh_gs()
	var room: RoomBase = await _make_living_room(gs)
	var host := InteractablesHost.attach_to(room)
	await wait_frames(2)
	var fernseher := _finde_fernseher(host)
	assert_true(fernseher != null, "Standard-Wohnzimmer (televisionModern) dockt Fernseher an")
	if fernseher != null:
		assert_true(fernseher.get_node_or_null("TapArea") != null, "Tap-Zone existiert")
		assert_false(fernseher.is_on(), "frisch angedockt: aus")
	await _cleanup(room, gs)


func test_einschalten_zappen_ausschalten_sitzung() -> void:
	var gs := _fresh_gs()
	gs.clock.pin(1_772_000_000_000)  # feste Uhr: Sitzung ist deterministisch
	var room: RoomBase = await _make_living_room(gs)
	var host := InteractablesHost.attach_to(room)
	await wait_frames(2)
	var fernseher := _finde_fernseher(host)
	assert_true(fernseher != null, "Fernseher angedockt")
	if fernseher == null:
		await _cleanup(room, gs)
		return
	var fun_vorher := float(gs.get_value("gooby.stats.fun", 0.0))
	fernseher._on_tapped()
	await wait_frames(3)
	assert_true(fernseher.is_on(), "Tap 1: an")
	assert_true(fernseher.stage() != null, "SubViewport-Bühne steht")
	assert_eq(str(fernseher.spieler().aktueller_clip()["id"]), "news", "Sendeplatz 1 läuft")
	fernseher._on_tapped()
	await wait_frames(1)
	assert_true(fernseher.is_on(), "Tap 2 schaltet NICHT aus …")
	assert_eq(str(fernseher.spieler().aktueller_clip()["id"]), "kochen", "… sondern zappt weiter")
	# 65 s fernsehen (gepinnte Uhr): +2 Spaß über die Stats-API.
	gs.clock.advance(65_000)
	fernseher.takt(gs.clock.now_ms())
	assert_almost(
		float(gs.get_value("gooby.stats.fun", 0.0)),
		minf(100.0, fun_vorher + 2.0),
		1e-6,
		"+1 Spaß je 30 s Sitzung"
	)
	fernseher._ausschalten()
	await wait_frames(2)
	assert_false(fernseher.is_on(), "Aus-Knopf-Pfad: aus")
	assert_true(fernseher.stage() == null, "Bühne abgebaut")
	await _warte_bis_gooby_steht(room)
	await _cleanup(room, gs)


# ── Helfer (Muster test_w13_auge) ─────────────────────────────────────────────


func _finde_fernseher(host: InteractablesHost) -> Fernseher:
	for child in host.get_children():
		if child is Fernseher:
			return child
	return null


## Der Einschalt-Lauf (walk_to) darf beim Teardown nicht mehr laufen —
## sonst greift die Koroutine auf einen freigegebenen Raum zu.
func _warte_bis_gooby_steht(room: RoomBase) -> void:
	var gooby := room.gooby()
	if gooby == null:
		return
	await wait_until(func() -> bool: return not gooby.is_walking(), 8000)


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://w13_tests/gobty_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	return gs


func _make_living_room(gs: Node) -> RoomBase:
	var scene: PackedScene = load("res://scenes/home/wohnzimmer.tscn")
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	room.stunde_override = 13.0
	tree.root.add_child(room)
	await wait_frames(3)
	await wait_until(func() -> bool: return not room._rebake_pending, 4000)
	await tree.physics_frame
	return room


func _cleanup(room: Node, gs: Node) -> void:
	room.queue_free()
	await wait_frames(2)
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()
