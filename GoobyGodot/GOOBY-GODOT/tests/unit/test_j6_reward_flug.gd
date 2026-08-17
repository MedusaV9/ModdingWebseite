extends TestCase
## W18/J6-Wache — „Belohnungen reisen sichtbar" (Münzflug + HUD-Puls):
## (a) PURE Flug-Geometrie: Bezier-Kurve trifft Start/Ziel exakt, biegt
##     mittig sichtbar aus (Bogen ≥ BOGEN_MIN_PX/2), Seiten alternieren je
##     Sprite; Staffelung/Dauer streng monoton; Spin alterniert; Scale
##     landet exakt in Ruhegröße; Sprite-Anzahl 3..8 nach Betrag.
## (b) INTEGRATION: eine ECHTE GameState-Gutschrift (Economy.award in
##     gs.update → coins_changed) startet den Flug, und die HUD-Kapsel
##     pulst nach der Ankunft (RewardFlug.kapsel_squish-Meta am Chip).
## (c) RM-Pfad: Reduced Motion → KEIN Flug, Kapsel pulst genau einmal.
## (d) HUD geduckt (PanelSheet offen) → Zähler-Toast sammelt statt Kapsel.
## (e) Ebenen: Overlay UNTER den Modal-Ebenen (Quest-Sheet 60, Guide 70,
##     RewardHub 90) und ÜBER Home-UI/Telefon (10/30) — keine Kollision.
## (f) Minispiel-Schutz: aktiver MinigameHost → der Flug schweigt.

const Economy := preload("res://scripts/logic/economy.gd")
const GameStateScript := preload("res://scripts/state/game_state.gd")
const HUD_SCENE := preload("res://scripts/ui/hud.tscn")
const SHEET_SCENE := preload("res://scripts/ui/panel_sheet.tscn")

const NOW_MS := 1768478400000
const TAG := "2026-01-15"

var _seq := 0


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://j6_tests/flug_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	return gs


## Reduced Motion global setzen (Muster test_g7_hud_dynamik).
func _set_reduced_motion(an: bool) -> bool:
	var svc := tree.root.get_node_or_null("/root/UiTheme")
	if svc == null:
		return false
	var vorher: bool = svc.reduced_motion
	svc.reduced_motion = an
	return vorher


## Münzen ECHT gutschreiben — über den EINEN Wallet-Pfad (Economy.award in
## gs.update), exakt wie Quests/Verkäufe/Tagesbonus buchen.
func _muenzen_buchen(gs: Node, betrag: int) -> void:
	gs.update(func(s: Dictionary) -> void: Economy.award(s["economy"], betrag, "quest", TAG))


func _aufbau(rm: bool) -> Dictionary:
	var rm_vorher := _set_reduced_motion(rm)
	var gs := _fresh_gs()
	var hud: Hud = HUD_SCENE.instantiate()
	tree.root.add_child(hud)
	var host := Node.new()
	tree.root.add_child(host)
	var dienst := RewardFlug.attach_to(host, gs)
	await wait_frames(2)
	# Statischer Quelle-Hinweis darf nicht aus einem früheren Test lecken.
	RewardFlug._quelle_hinweis = Vector2.INF
	return {"gs": gs, "hud": hud, "host": host, "dienst": dienst, "rm_vorher": rm_vorher}


func _abbau(welt: Dictionary) -> void:
	_set_reduced_motion(bool(welt["rm_vorher"]))
	(welt["hud"] as Node).queue_free()
	(welt["host"] as Node).queue_free()
	await wait_frames(1)
	(welt["gs"] as Node).free()
	# Ausklingende Münz-Klimper-Player stoppen — sonst meldet der Prozess-
	# Exit „ObjectDB instances leaked" für die noch aktiven Ogg-Playbacks.
	for pfad in ["/root/Audio", "/root/" + AudioDirector.NODE_NAME]:
		var audio := tree.root.get_node_or_null(NodePath(pfad))
		if audio == null:
			continue
		for kind in audio.get_children():
			if kind is AudioStreamPlayer:
				(kind as AudioStreamPlayer).stop()


# ── (a) Pure Flug-Geometrie ──────────────────────────────────────────────────


func test_kurve_trifft_start_und_ziel() -> void:
	var start := Vector2(100, 400)
	var ziel := Vector2(900, 80)
	for i in 3:
		var k := RewardFlug.kontrollpunkt(start, ziel, i)
		var p0 := RewardFlug.kurven_punkt(start, k, ziel, 0.0)
		var p1 := RewardFlug.kurven_punkt(start, k, ziel, 1.0)
		assert_almost(p0.distance_to(start), 0.0, 0.001, "t=0 startet an der Quelle (i=%d)" % i)
		assert_almost(p1.distance_to(ziel), 0.0, 0.001, "t=1 trifft die Kapsel (i=%d)" % i)


func test_kurve_biegt_sichtbar_und_seiten_alternieren() -> void:
	var start := Vector2(0, 0)
	var ziel := Vector2(400, 0)
	var mitte := (start + ziel) / 2.0
	var k0 := RewardFlug.kontrollpunkt(start, ziel, 0)
	var k1 := RewardFlug.kontrollpunkt(start, ziel, 1)
	# Scheitel der quadratischen Bezier bei t=0.5 liegt (kontrolle-mitte)/2
	# neben der Gerade — mindestens der halbe Mindestbogen.
	var scheitel := RewardFlug.kurven_punkt(start, k0, ziel, 0.5)
	assert_true(
		scheitel.distance_to(mitte) >= RewardFlug.BOGEN_MIN_PX / 2.0 - 0.01,
		"Bogen ist sichtbar (Scheitel %.1f px neben der Gerade)" % scheitel.distance_to(mitte)
	)
	var richtung := ziel - start
	var seite0 := signf(richtung.cross(k0 - mitte))
	var seite1 := signf(richtung.cross(k1 - mitte))
	assert_true(seite0 != 0.0 and seite1 != 0.0, "Kontrollpunkte liegen neben der Gerade")
	assert_true(seite0 != seite1, "Bogen-Seite alterniert je Sprite-Index")
	# Nullstrecke crasht nicht und biegt trotzdem aus.
	var k_null := RewardFlug.kontrollpunkt(start, start, 0)
	assert_true(k_null.is_finite(), "Nullstrecke → endlicher Kontrollpunkt")


func test_staffelung_dauer_spin_scale() -> void:
	assert_almost(RewardFlug.staffel_verzoegerung(0), 0.0, 1e-6, "1. Sprite startet sofort")
	for i in 7:
		assert_true(
			RewardFlug.staffel_verzoegerung(i + 1) > RewardFlug.staffel_verzoegerung(i),
			"Staffelung streng monoton (i=%d)" % i
		)
		assert_true(
			RewardFlug.flug_dauer(i + 1) > RewardFlug.flug_dauer(i),
			"spätere Sprites fliegen länger (i=%d)" % i
		)
	assert_almost(RewardFlug.spin_winkel(0, 0.0), 0.0, 1e-6, "Spin startet bei 0")
	assert_almost(RewardFlug.spin_winkel(0, 1.0), RewardFlug.SPIN_RAD, 1e-6, "voller Spin")
	assert_almost(
		RewardFlug.spin_winkel(1, 1.0), -RewardFlug.SPIN_RAD, 1e-6, "Spin-Richtung alterniert"
	)
	assert_almost(RewardFlug.flug_scale(0.0), 0.72, 1e-6, "klein starten")
	assert_almost(RewardFlug.flug_scale(1.0), 1.0, 1e-6, "exakt in Ruhegröße ankommen")
	assert_true(RewardFlug.flug_scale(0.5) > 1.0, "mittig überschwingen")


func test_sprite_anzahl_nach_betrag() -> void:
	assert_eq(RewardFlug.sprite_anzahl(0), 0, "0 Münzen → kein Flug")
	assert_eq(RewardFlug.sprite_anzahl(-5), 0, "negativ → kein Flug")
	assert_eq(RewardFlug.sprite_anzahl(1), 3, "Minimum 3 Sprites")
	assert_eq(RewardFlug.sprite_anzahl(11), 3, "unter 12 bleibt Minimum")
	assert_eq(RewardFlug.sprite_anzahl(12), 4, "+1 je 12 Münzen")
	assert_eq(RewardFlug.sprite_anzahl(60), 8, "Deckel 8 Sprites")
	assert_eq(RewardFlug.sprite_anzahl(9999), 8, "Deckel hält auch bei Riesenbeträgen")


func test_minigame_schutz() -> void:
	var mg := MinigameHost.new()
	assert_true(RewardFlug.soll_schweigen(mg), "MinigameHost aktiv → Flug schweigt")
	mg.free()
	var normal := Node.new()
	assert_false(RewardFlug.soll_schweigen(normal), "normale Szene → Flug erlaubt")
	normal.free()
	assert_false(RewardFlug.soll_schweigen(null), "keine Szene → Flug erlaubt")


# ── (b)–(e) Integration ─────────────────────────────────────────────────────


func test_gutschrift_startet_flug_und_kapsel_pulst() -> void:
	var welt: Dictionary = await _aufbau(false)
	var dienst := welt["dienst"] as RewardFlug
	var hud := welt["hud"] as Hud
	var fluege: Array = []
	dienst.flug_gestartet.connect(
		func(art: StringName, anzahl: int) -> void: fluege.append([art, anzahl])
	)
	_muenzen_buchen(welt["gs"] as Node, 25)
	await wait_frames(1)
	assert_eq(fluege.size(), 1, "genau EIN Flug pro Gutschrift")
	if fluege.size() == 1:
		assert_eq(fluege[0][0], &"muenzen", "Flug-Art = Münzen")
		assert_eq(fluege[0][1], RewardFlug.sprite_anzahl(25), "Sprite-Anzahl nach Betrag")
	assert_true(dienst.aktive_sprites() > 0, "Sprites fliegen")
	assert_false(dienst.toast_offen(), "Kapsel sichtbar → kein Sammel-Toast")
	var angekommen := await wait_until(func() -> bool: return dienst.aktive_sprites() == 0, 5000)
	assert_true(angekommen, "alle Sprites kommen an")
	assert_true(
		(hud._coin_chip as Control).has_meta(&"_rf_puls"),
		"Münz-Kapsel pulst nach der Ankunft (Squish-Meta gesetzt)"
	)
	# XP-Gutschrift → gleicher Mechanismus Richtung Level-Kapsel.
	fluege.clear()
	(welt["gs"] as Node).update(
		func(s: Dictionary) -> void: s["progression"]["xp"] = float(s["progression"]["xp"]) + 9.0
	)
	await wait_frames(1)
	assert_eq(fluege.size(), 1, "XP-Gutschrift startet einen Flug")
	if fluege.size() == 1:
		assert_eq(fluege[0][0], &"xp", "Flug-Art = XP")
	await wait_until(func() -> bool: return dienst.aktive_sprites() == 0, 5000)
	assert_true(
		(hud._level_ring.get_parent() as Control).has_meta(&"_rf_puls"),
		"Level-Kapsel pulst nach der XP-Ankunft"
	)
	await _abbau(welt)


func test_reduced_motion_kein_flug_ein_puls() -> void:
	var welt: Dictionary = await _aufbau(true)
	var dienst := welt["dienst"] as RewardFlug
	var hud := welt["hud"] as Hud
	var fluege: Array = []
	dienst.flug_gestartet.connect(
		func(_art: StringName, anzahl: int) -> void: fluege.append(anzahl)
	)
	_muenzen_buchen(welt["gs"] as Node, 25)
	await wait_frames(1)
	assert_eq(fluege.size(), 0, "RM: Flug entfällt")
	assert_eq(dienst.aktive_sprites(), 0, "RM: keine Sprites unterwegs")
	assert_true(
		(hud._coin_chip as Control).has_meta(&"_rf_puls"), "RM: Kapsel pulst (genau einmal)"
	)
	await _abbau(welt)


func test_hud_geduckt_sammelt_zaehler_toast() -> void:
	var welt: Dictionary = await _aufbau(false)
	var dienst := welt["dienst"] as RewardFlug
	var hud := welt["hud"] as Hud
	var blatt: PanelSheet = SHEET_SCENE.instantiate()
	tree.root.add_child(blatt)
	await wait_frames(1)
	blatt.open()
	await wait_frames(2)
	assert_true(hud.sichtbarkeit().verdeckt(), "Blatt offen → HUD weicht")
	assert_false(
		bool(hud.kapsel_anker(&"muenzen").get("sichtbar", true)),
		"kapsel_anker meldet die Kapsel als weg"
	)
	_muenzen_buchen(welt["gs"] as Node, 10)
	await wait_frames(1)
	assert_true(dienst.toast_offen(), "HUD geduckt → Zähler-Toast sammelt")
	assert_true(dienst.aktive_sprites() > 0, "Flug läuft trotzdem (Ziel = Toast)")
	# Zweite Buchung im selben Fenster: der Toast SAMMELT (10 + 5).
	_muenzen_buchen(welt["gs"] as Node, 5)
	await wait_until(func() -> bool: return dienst.aktive_sprites() == 0, 5000)
	assert_eq(dienst._toast_muenzen, 15, "Toast summiert beide Gutschriften")
	blatt.close()
	blatt.queue_free()
	await _abbau(welt)


func test_ebene_unter_modals_und_eingabe_durchlaessig() -> void:
	var welt: Dictionary = await _aufbau(false)
	var dienst := welt["dienst"] as RewardFlug
	assert_eq(dienst._layer.layer, RewardFlug.EBENE, "Layer trägt die dokumentierte Ebene")
	# Quest-/Sheet-Layer 60 (quest_service.gd), Guide 70, RewardHub 90 —
	# der Flug bleibt DARUNTER; Home-UI 10 / Telefon 30 bleiben darunter.
	assert_true(RewardFlug.EBENE < 60, "unter den Modal-Ebenen (PanelSheet/Quest 60)")
	assert_true(RewardFlug.EBENE > 30, "über Home-UI (10) und Telefon (30)")
	assert_eq(
		dienst._buehne.mouse_filter, Control.MOUSE_FILTER_IGNORE, "Overlay schluckt keine Eingaben"
	)
	assert_eq(RewardFlug.attach_to(welt["host"] as Node, welt["gs"]), dienst, "attach idempotent")
	await _abbau(welt)


func test_melde_quelle_ttl_und_fallback() -> void:
	var welt: Dictionary = await _aufbau(false)
	var dienst := welt["dienst"] as RewardFlug
	var quelle := Vector2(123, 45)
	RewardFlug.melde_quelle(quelle)
	assert_eq(dienst._quelle_oder_mitte(), quelle, "frischer Hinweis → Flug startet an der Quelle")
	# Abgelaufener Hinweis → Bildmitte (deterministisch über den Stempel).
	RewardFlug._quelle_stempel_ms = Time.get_ticks_msec() - RewardFlug.QUELLE_TTL_MS - 1
	var mitte := dienst._quelle_oder_mitte()
	assert_ne(mitte, quelle, "abgelaufener Hinweis zählt nicht mehr")
	assert_true(mitte.is_finite(), "Fallback ist die Bildmitte")
	RewardFlug.melde_quelle(Vector2.INF)
	assert_true(dienst._quelle_oder_mitte().is_finite(), "INF-Hinweis ist ein No-op")
	await _abbau(welt)
