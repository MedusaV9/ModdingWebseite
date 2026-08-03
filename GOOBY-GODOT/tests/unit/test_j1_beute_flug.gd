extends TestCase
## J1 „Beute-Flug-Dreiklang“ (beute_flug.gd) — Wachen für:
## 1. die PURE Flug-Planung (deterministisch: Betrag→Sprites gedeckelt,
##    Staffelung schlägt den 45-ms-Audio-Debounce, Pitch-Treppe 0.9→1.6),
## 2. den Reduced-Motion-Zweig (kein Flug, aber Treppe + Zähler bleiben),
## 3. die 3-ms-Haptik-Partitur `zaehl_tick`,
## 4. die HUD-Zähler-Übernahme (muenzflug_start/schritt/abschluss) und
## 5. die LEDGER-NEUTRALITÄT: der Flug bucht NIE — nur Economy bucht.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const HUD_SCENE := preload("res://scripts/ui/hud.tscn")
const Economy := preload("res://scripts/logic/economy.gd")

var _seq := 0

# ── 1. PURE Flug-Planung ──────────────────────────────────────────────────────


func test_sprite_anzahl_skaliert_mit_betrag_und_ist_gedeckelt() -> void:
	assert_eq(BeuteFlug.anzahl_sprites(0), 0, "ohne Betrag keine Serie")
	assert_eq(BeuteFlug.anzahl_sprites(-5), 0, "negativ bleibt no-op")
	assert_eq(BeuteFlug.anzahl_sprites(1), BeuteFlug.MIN_SPRITES, "Kleinstbetrag = Basis 6")
	assert_eq(BeuteFlug.anzahl_sprites(20), 8, "20 Münzen → 6 + 2 Sprites")
	assert_eq(BeuteFlug.anzahl_sprites(80), BeuteFlug.MAX_SPRITES, "ab 80 greift der Deckel")
	assert_eq(BeuteFlug.anzahl_sprites(100000), BeuteFlug.MAX_SPRITES, "Deckel hält (kein Spam)")


func test_plan_staffelung_pitch_treppe_und_debounce_abstand() -> void:
	var plan := BeuteFlug.plan_erstellen(42, false)
	var n := int(plan["ticks"])
	assert_eq(n, BeuteFlug.anzahl_sprites(42), "Ticks = geplante Sprite-Anzahl")
	assert_eq(int(plan["sprites"]), n, "ohne Reduced Motion fliegt jede Münze")
	var starts: Array = plan["starts_s"]
	var ankuenfte: Array = plan["ankuenfte_s"]
	var pitches: Array = plan["pitches"]
	assert_eq(starts.size(), n)
	assert_eq(ankuenfte.size(), n)
	assert_eq(pitches.size(), n)
	assert_almost(float(pitches[0]), BeuteFlug.PITCH_VON, 1e-6, "Treppe startet bei 0.9")
	assert_almost(float(pitches[n - 1]), BeuteFlug.PITCH_BIS, 1e-6, "… und endet bei 1.6")
	for i in range(1, n):
		assert_true(float(pitches[i]) > float(pitches[i - 1]), "Pitch-Treppe steigt strikt")
		assert_almost(
			float(starts[i]) - float(starts[i - 1]),
			BeuteFlug.STAFFEL_S,
			1e-6,
			"Starts sind gleichmäßig gestaffelt"
		)
		var abstand := float(ankuenfte[i]) - float(ankuenfte[i - 1])
		assert_true(
			abstand > 0.045,
			"Ankunfts-Abstand %f schlägt den 45-ms-Debounce des AudioDirector" % abstand
		)
	assert_true(
		float(plan["ende_s"]) > float(ankuenfte[n - 1]),
		"ui_coins-Abschluss kommt NACH der letzten Ankunft"
	)


func test_plan_einzelfall_und_pitchfolge_helfer() -> void:
	assert_almost(BeuteFlug.pitch_fuer(0, 1), BeuteFlug.PITCH_VON, 1e-6, "Einzeltick bleibt tief")
	assert_almost(BeuteFlug.pitch_fuer(0, 14), BeuteFlug.PITCH_VON, 1e-6)
	assert_almost(BeuteFlug.pitch_fuer(13, 14), BeuteFlug.PITCH_BIS, 1e-6)
	var leer := BeuteFlug.plan_erstellen(0, false)
	assert_eq(int(leer["ticks"]), 0, "Betrag 0 → leerer Plan")
	assert_eq((leer["ankuenfte_s"] as Array).size(), 0)


func test_plan_reduced_motion_zweig() -> void:
	var voll := BeuteFlug.plan_erstellen(30, false)
	var ruhig := BeuteFlug.plan_erstellen(30, true)
	assert_eq(int(ruhig["sprites"]), 0, "Reduced Motion: KEIN Flug")
	assert_eq(int(ruhig["ticks"]), int(voll["ticks"]), "… aber die Serie bleibt vollzählig")
	assert_eq(ruhig["pitches"], voll["pitches"], "… mit identischer Pitch-Treppe")
	var ankuenfte: Array = ruhig["ankuenfte_s"]
	for i in range(1, ankuenfte.size()):
		assert_almost(
			float(ankuenfte[i]) - float(ankuenfte[i - 1]),
			BeuteFlug.STAFFEL_S,
			1e-6,
			"RM-Arpeggio tickt im Staffel-Raster (> 45-ms-Debounce)"
		)
	assert_true(
		float(ruhig["ende_s"]) < float(voll["ende_s"]),
		"RM-Serie ist kompakter als der Flug (keine Flugdauer)"
	)


# ── 3. Haptik-Partitur ────────────────────────────────────────────────────────


func test_zaehl_tick_partitur_ist_drei_ms_und_skaliert() -> void:
	var normal := Haptics.plan("zaehl_tick")
	assert_eq(normal.size(), 1, "EIN Mikro-Impuls je Ankunft")
	assert_eq(int(normal[0]), Haptics.ZAEHL_TICK_MS, "3 ms laut J1-Partitur")
	assert_eq(int(Haptics.plan("zaehl_tick", "dezent")[0]), 2, "dezent: 3×0.6 → 2 ms")
	assert_eq(int(Haptics.plan("zaehl_tick", "stark")[0]), 5, "stark: 3×1.6 → 5 ms")
	assert_true(int(normal[0]) < Haptics.TAP_MS, "Zähl-Tick bleibt UNTER dem Knopf-Tap (kitzeln)")


# ── 4. HUD-Zähler-Übernahme (nur Pillen-API, deterministisch) ─────────────────


func test_hud_muenzflug_uebernahme_schritt_und_abschluss() -> void:
	var hud: Hud = HUD_SCENE.instantiate()
	tree.root.add_child(hud)
	await wait_frames(2)
	var label := hud.find_child("CoinValue", true, false) as Label
	assert_true(label != null, "Münz-Label der Pille gefunden")
	hud.set_coins(50)
	# Buchung landet zuerst (Signal-Reihenfolge der Call-Sites) …
	hud.set_coins(70)
	# … dann übernimmt der Flug: Label zurück auf den Stand VOR der Buchung.
	var uebernahme: Dictionary = hud.muenzflug_start(20)
	assert_eq(int(uebernahme["von"]), 50, "von = Stand vor der Buchung")
	assert_eq(int(uebernahme["bis"]), 70, "bis = gebuchte Wahrheit")
	assert_eq(label.text, "50", "Label startet die Serie beim alten Stand")
	hud.muenzflug_schritt(60)
	assert_eq(label.text, "60", "Ankunft schiebt den Zwischenstand")
	# Parallel-Buchung während des Flugs: Label bleibt bei der Serie …
	hud.set_coins(75)
	assert_eq(label.text, "60", "set_coins übersteuert die laufende Serie nicht")
	hud.muenzflug_schritt(70)
	assert_eq(label.text, "70")
	# … und der Abschluss zeigt IMMER die aktuelle Wahrheit.
	hud.muenzflug_abschluss()
	assert_eq(label.text, "75", "Abschluss zeigt die (mitgewachsene) Wahrheit")
	assert_true(hud.coin_ziel_rect().size.x > 0.0, "Pillen-Ziel-Rect ist bemessen")
	# Danach arbeitet set_coins wieder normal (Folge-Buchungen zählen selbst).
	hud.set_coins(80)
	assert_eq(hud._coin_shown, 80)
	hud.queue_free()
	await wait_frames(2)


# ── 5. Ledger-Neutralität + synchroner Endstand (End-to-End) ──────────────────


func test_flug_ist_ledger_neutral_nur_economy_bucht() -> void:
	var gs := _fresh_gs()
	tree.root.add_child(gs)
	gs.set_value("economy.coins", 100)
	# Flug OHNE Buchung: nach der kompletten Serie steht der Ledger unverändert.
	assert_true(BeuteFlug.fliegen(gs, Vector2(80.0, 200.0), 44), "Serie startet")
	await tree.create_timer(1.8).timeout
	assert_eq(int(gs.get_value("economy.coins", -1)), 100, "Flug bucht NIE Münzen")
	# Buchung + Flug (der echte Claim-Pfad): GENAU der Economy-Betrag kommt an.
	gs.update(func(state: Dictionary) -> void: Economy.award(state["economy"], 44, "test_j1"))
	BeuteFlug.fliegen(gs, Vector2(80.0, 200.0), 44)
	await tree.create_timer(1.8).timeout
	assert_eq(int(gs.get_value("economy.coins", -1)), 144, "nur Economy.award hat gebucht")
	gs.queue_free()
	await wait_frames(2)


func test_flug_treibt_hud_zaehler_bis_zum_wahren_endstand() -> void:
	var hud: Hud = HUD_SCENE.instantiate()
	tree.root.add_child(hud)
	await wait_frames(2)
	var label := hud.find_child("CoinValue", true, false) as Label
	hud.set_coins(100)
	# Claim-Moment wie an den Call-Sites: erst bucht das Signal, dann fliegt es.
	hud.set_coins(120)
	assert_true(BeuteFlug.fliegen(hud, Vector2(200.0, 300.0), 20), "Serie startet")
	# Nach dem deferred Serienstart (vor der ersten Ankunft bei ~0,5 s):
	# die Pille wurde auf den Stand VOR der Buchung zurückgespult.
	await wait_frames(3)
	assert_true(hud._muenzflug_aktiv, "Flug hat den Zähler übernommen")
	assert_eq(label.text, "100", "Serie startet die Pille beim alten Stand")
	# Fertig = Abschluss hat die Übernahme freigegeben UND die Wahrheit steht.
	var fertig := await wait_until(
		func() -> bool: return not hud._muenzflug_aktiv and label.text == "120", 5000
	)
	assert_true(fertig, "Ankunftsserie zählt die Pille bis zur Wahrheit hoch")
	hud.queue_free()
	await wait_frames(2)


# ── Helfer ────────────────────────────────────────────────────────────────────


## Frisches, ECHTES GameState mit eigenem user://-Ordner (Muster test_ui_rest1).
func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://j1_tests/gs_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	return gs
