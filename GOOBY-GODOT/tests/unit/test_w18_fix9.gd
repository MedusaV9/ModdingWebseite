extends TestCase
## W18/R3 FIX-9 — Ökonomie-/Verhaltens-Restbefunde der R1-Playtests:
##  - PT2-B13: passiver Münz-Zuwachs im Leerlauf. Quelle (Diagnose): das
##    Seelen-System bucht `soul_sofa_fund` (Mini-Fund +1 alle ~90 s,
##    Sofa-Fund-Überraschung +3). Fix: eigenes 10-ᴳ-Tagesbuch in Economy,
##    Ledger-Wache via Economy.award_tap, Toast macht Funde sichtbar,
##    voller Deckel lässt den Moment KOMPLETT aus.
##  - PT2-B10: Wochenmarkt-Öffnungszeiten (Sa 8–14) mit Charme: Platz immer
##    betretbar, außerhalb ruhen die Stände (Planen, „Bis Samstag!“-Schild,
##    Greta weg), Ankauf vertröstet, Eigenstand bleibt über den
##    „Mein Marktstand“-Knopf erreichbar. Zeit via zeit_override injiziert.
##  - PT2-B11: FahrdienstApp.aktualisiere() — remove_child VOR queue_free
##    hält Knopf-Namen stabil (kein @RufenButton@-Umnummerieren).
##  - PT3-B5: cityDrive-Checkpoint ankert auf der aktiven Münz-Kette im
##    Band [24, 90] m — Münz-Jäger fahren zwangsläufig durch den Ring
##    (Pickup-Radius 3 m liegt IM Ring-Radius 4 m).

const Economy := preload("res://scripts/logic/economy.gd")
const GameStateScript := preload("res://scripts/state/game_state.gd")
const DriveLogic := preload("res://scripts/minigames/games/city_drive/city_drive_logic.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

## Do 15.01.2026 12:00 UTC (EF-1-Anker) — Lokaltag "2026-01-15".
const NOW_MS := 1768478400000
const TAG := "2026-01-15"

var _seq := 0


class RoomStub:
	extends Node3D
	## Minimaler RoomBase-Ersatz für den GoobyReactions-Runner (EF-1-Muster).

	var grid: Variant = null
	var gs_ref: Object = null
	var lines: Array = []

	func game_state() -> Object:
		return gs_ref

	func gooby() -> Node3D:
		return null

	func say(text: String) -> void:
		lines.append(text)

	func is_build_mode_active() -> bool:
		return false


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://w18_fix9/gs_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	CityState.register_slice()
	SoulState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	return gs


func _runner(gs: Node) -> Array:
	var room := RoomStub.new()
	room.gs_ref = gs
	tree.root.add_child(room)
	var runner := GoobyReactions.new()
	runner.name = "GoobyReactions"
	runner.now_ms_override = NOW_MS
	runner.visuals_enabled = false
	room.add_child(runner)
	runner.setup(room)
	return [room, runner]


## ------------------------------------------------------------ PT2-B13


func test_b13_slice_und_schema_kennen_das_seelen_buch() -> void:
	var slice := Economy.default_slice()
	assert_eq(int(slice["soulCoins"]), 0, "frisches Buch ist leer")
	assert_eq(str(slice["soulCoinsDay"]), "", "kein Tag gebunden")
	# normalize heilt Alt-Saves ohne die neuen Keys (und klemmt Unsinn).
	var raw := SaveSchema.default_state(NOW_MS)
	(raw["economy"] as Dictionary).erase("soulCoins")
	(raw["economy"] as Dictionary)["soulCoinsDay"] = 7
	var heil := SaveSchema.normalize(raw, NOW_MS)
	assert_true(bool(heil["ok"]), "normalize akzeptiert den Alt-Save")
	var econ: Dictionary = (heil["state"] as Dictionary)["economy"]
	assert_eq(int(econ["soulCoins"]), 0, "fehlender Key → 0")
	assert_eq(str(econ["soulCoinsDay"]), "", "falscher Typ → ''")


func test_b13_tagesdeckel_kappt_seelen_funde() -> void:
	var econ := Economy.default_slice()
	assert_eq(Economy.soul_headroom(econ, TAG), Economy.SOUL_DAY_CAP, "voller Spielraum")
	for _i in 3:
		assert_eq(Economy.award(econ, 3, "soul_sofa_fund", TAG), 3, "Fund unterm Deckel")
	assert_eq(Economy.award(econ, 3, "soul_sofa_fund", TAG), 1, "Deckel kappt auf den Rest")
	assert_eq(Economy.soul_headroom(econ, TAG), 0, "Buch ist voll")
	assert_eq(Economy.award(econ, 1, "soul_sofa_fund", TAG), 0, "voll = 0 gewährt")
	assert_eq(
		int(econ["coins"]),
		Economy.STARTING_COINS + Economy.SOUL_DAY_CAP,
		"aufs Konto ging exakt der Deckel"
	)
	assert_eq(int(econ["soulCoins"]), Economy.SOUL_DAY_CAP)
	assert_eq(str(econ["soulCoinsDay"]), TAG)
	# Neuer Lokaltag → das Buch startet frisch; andere Reasons bleiben frei.
	assert_eq(Economy.soul_headroom(econ, "2026-01-16"), Economy.SOUL_DAY_CAP)
	assert_eq(Economy.award(econ, 2, "soul_sofa_fund", "2026-01-16"), 2, "neuer Tag zählt neu")
	assert_eq(Economy.award(econ, 500, "minigame"), 500, "fremde Reasons ungedeckelt")


func test_b13_award_tap_meldet_jede_buchung() -> void:
	var buchungen: Array = []
	Economy.award_tap = func(reason: String, angefragt: int, gewaehrt: int) -> void:
		buchungen.append([reason, angefragt, gewaehrt])
	var econ := Economy.default_slice()
	Economy.award(econ, 3, "soul_sofa_fund", TAG)
	Economy.award(econ, 9, "soul_sofa_fund", TAG)
	Economy.award(econ, 5, "soul_sofa_fund", TAG)
	Economy.award(econ, 4, "minigame")
	Economy.award_tap = Callable()
	assert_eq(buchungen.size(), 4, "JEDE Buchung wird gemeldet (auch gewährte 0)")
	assert_eq(buchungen[0], ["soul_sofa_fund", 3, 3])
	assert_eq(buchungen[1], ["soul_sofa_fund", 9, 7], "Kappung sichtbar: 9 angefragt, 7 gewährt")
	assert_eq(buchungen[2], ["soul_sofa_fund", 5, 0], "voller Deckel meldet 0")
	assert_eq(buchungen[3], ["minigame", 4, 4])
	Economy.award(econ, 1, "minigame")
	assert_eq(buchungen.size(), 4, "ausgehängter Tap ist still")


func test_b13_leerlauf_bucht_nur_erklaerte_muenzen() -> void:
	var gs := _fresh_gs()
	var pair := _runner(gs)
	var room: RoomStub = pair[0]
	var runner: GoobyReactions = pair[1]
	var coins0 := int(gs.get_value("economy.coins", 0))
	var buchungen: Array = []
	Economy.award_tap = func(reason: String, angefragt: int, gewaehrt: int) -> void:
		buchungen.append([reason, angefragt, gewaehrt])
	# ~45 min Leerlauf im Zeitraffer: alle 91 s ein Mini-Fund-Versuch —
	# OHNE Deckel wären das 30 Münzen (Playtest-Befund „+5 ᴳ / 4 min“).
	for i in 30:
		runner.now_ms_override = NOW_MS + 91_000 * (i + 1)
		runner._run_mini_fund()
	Economy.award_tap = Callable()
	var summe := 0
	for buchung: Array in buchungen:
		assert_eq(str(buchung[0]), "soul_sofa_fund", "Leerlauf bucht NUR den Seelen-Reason")
		summe += int(buchung[2])
	assert_eq(summe, Economy.SOUL_DAY_CAP, "der Tag summiert exakt auf den Deckel")
	assert_eq(
		int(gs.get_value("economy.coins", 0)),
		coins0 + Economy.SOUL_DAY_CAP,
		"Konto-Delta == erklärte Buchungssumme (nichts Unsichtbares)"
	)
	# Voller Deckel: der Moment entfällt KOMPLETT (keine Zeile ohne Münze).
	var lines_voll := room.lines.size()
	runner.now_ms_override = NOW_MS + 91_000 * 40
	runner._run_mini_fund()
	assert_eq(room.lines.size(), lines_voll, "kein Fund-Spruch ohne echte Münze")
	assert_true(runner._fund_deckel_erreicht(), "Deckel-Wächter meldet voll")
	assert_eq(runner._grant_coins(1), 0, "direkte Buchung liefert 0")
	room.queue_free()
	await wait_frames(1)
	gs.free()


func test_b13_fund_toast_macht_buchung_sichtbar() -> void:
	var gs := _fresh_gs()
	var pair := _runner(gs)
	var room: RoomStub = pair[0]
	var runner: GoobyReactions = pair[1]
	var toast := ToastLayer.new()
	toast.theme = ThemeService.theme()
	tree.root.add_child(toast)
	await wait_frames(1)
	assert_eq(runner._grant_coins(1), 1, "Fund wird gebucht")
	await wait_frames(2)
	var gefunden := false
	for layer in tree.root.find_children("*", "ToastLayer", true, false):
		for label in (layer as Node).find_children("*", "Label", true, false):
			if str((label as Label).text).contains("ᴳ gefunden"):
				gefunden = true
	assert_true(gefunden, "Toast „… hat 1 ᴳ gefunden!“ ist sichtbar")
	toast.queue_free()
	room.queue_free()
	await wait_frames(1)
	gs.free()


## ------------------------------------------------------------ PT2-B10


func test_b10_oeffnungsregel_am_unix_stempel() -> void:
	var sa9 := int(Time.get_unix_time_from_datetime_string("2026-08-08T09:00:00"))
	var sa6 := int(Time.get_unix_time_from_datetime_string("2026-08-08T06:00:00"))
	var sa15 := int(Time.get_unix_time_from_datetime_string("2026-08-08T15:00:00"))
	var so10 := int(Time.get_unix_time_from_datetime_string("2026-08-02T10:00:00"))
	assert_true(OrtKatalog.ist_offen("wochenmarkt", sa9), "Sa 9 Uhr offen")
	assert_false(OrtKatalog.ist_offen("wochenmarkt", sa6), "Sa 6 Uhr noch zu")
	assert_false(OrtKatalog.ist_offen("wochenmarkt", sa15), "Sa 15 Uhr Feierabend")
	assert_false(OrtKatalog.ist_offen("wochenmarkt", so10), "Sonntag zu")


func test_b10_marktsheet_vertroestet_ausserhalb() -> void:
	var gs := _fresh_gs()
	var sheet := MarktSheet.new()
	sheet.gs = gs
	sheet.zeit_override = int(Time.get_unix_time_from_datetime_string("2026-08-08T06:00:00"))
	tree.root.add_child(sheet)
	await wait_frames(1)
	var pause := I18nService.t("markt.geschlossen.titel")
	assert_true(_hat_label(sheet, pause), "geschlossen: Ankauf zeigt die Pausen-Karte")
	assert_true(
		_hat_label(sheet, I18nService.t("markt.geschlossen.ankauf")),
		"… samt Hinweis auf Sa 8–14 + Eigenstand-Tipp"
	)
	# Zur Marktzeit verschwindet die Karte und der Ankauf arbeitet normal.
	sheet.zeit_override = int(Time.get_unix_time_from_datetime_string("2026-08-08T09:00:00"))
	sheet.aktualisiere()
	await wait_frames(1)
	assert_false(_hat_label(sheet, pause), "offen: keine Pausen-Karte mehr")
	# Frische Saves haben STARTER_FOOD im Korb — offen zeigt der Ankauf
	# also echte Verkaufszeilen („Eins verkaufen“-Knöpfe).
	assert_true(
		_hat_knopf(sheet, I18nService.t("city.markt.verkauf_eins")),
		"offen: das normale Angebots-UI läuft (Verkaufs-Knopf steht)"
	)
	sheet.queue_free()
	await wait_frames(1)
	gs.free()


func test_b10_wochenmarkt_geschlossen_charme_und_flip() -> void:
	var gs := _fresh_gs()
	var sa6 := int(Time.get_unix_time_from_datetime_string("2026-08-08T06:00:00"))
	var sa9 := int(Time.get_unix_time_from_datetime_string("2026-08-08T09:00:00"))
	var ort: OrtWochenmarkt = (
		(load("res://scenes/city/orte/wochenmarkt.tscn") as PackedScene).instantiate()
	)
	ort.game_state_override = gs
	ort.leben_stumm_override = true
	ort.zeit_override = sa6
	tree.root.add_child(ort)
	await wait_frames(2)
	assert_false(ort.markt_offen(), "Sa 6 Uhr: Markt ruht")
	assert_true(ort.rig != null and not ort.rig.visible, "Greta ist NICHT da")
	var deko := ort.get_node_or_null("GeschlossenDeko") as Node3D
	assert_true(deko != null and deko.visible, "Planen + Schild stehen")
	var schild := deko.find_child("SchildText", true, false) as Label3D
	assert_true(schild != null, "das Schild hat Text")
	assert_eq(schild.text, I18nService.t("markt.geschlossen.schild"), "„Bis Samstag!“-Schild")
	assert_false(ort._dialog_lief, "kein Greta-Dialog beim ruhenden Markt")
	assert_true(ort.find_child("StandKnopf", true, false) != null, "„Mein Marktstand“ steht")
	assert_true(
		ort.leben != null and not ort.leben.visible, "Markt-Leben (Bummler/Glocke) ruht unsichtbar"
	)
	assert_eq(int(ort.leben.process_mode), int(Node.PROCESS_MODE_DISABLED), "… und eingefroren")
	# Zeit-Flip auf Marktzeit: Greta kommt (samt Dialog-Nachstart), Deko weg.
	ort.zeit_override = sa9
	ort.aktualisiere_marktzustand()
	await wait_frames(1)
	assert_true(ort.rig.visible, "Sa 9 Uhr: Greta steht am Platz")
	assert_false(deko.visible, "Planen/Schild sind weggeräumt")
	assert_true(ort._dialog_lief, "Gretas Dialog ist nachgestartet")
	assert_true(ort.leben.visible, "das Markt-Leben bummelt wieder")
	assert_eq(int(ort.leben.process_mode), int(Node.PROCESS_MODE_INHERIT), "… und läuft")
	# Der Stand-Knopf öffnet den Eigenstand-Tab MIT der Ort-Uhr.
	ort.oeffne_stand()
	await wait_frames(1)
	var stand := _finde_stand_sheet(ort)
	assert_true(stand != null, "Eigenstand-Tab steht im Sheet")
	assert_eq(stand.zeit_override, sa9, "Ort-Uhr wird in den Tab durchgereicht (PT2-B10)")
	ort.queue_free()
	await wait_frames(2)
	gs.free()


## ------------------------------------------------------------ PT2-B11


func test_b11_fahrdienst_knopfnamen_bleiben_stabil() -> void:
	var gs := _fresh_gs()
	var app := FahrdienstApp.new()
	app.gs = gs
	app.now_ms_override = NOW_MS
	app.stunde_override = 10.0
	tree.root.add_child(app)
	await wait_frames(1)
	# Stolperfalle PT2-B11: Neubau im SELBEN Frame — vor dem Fix erbte der
	# neue Knopf einen @RufenButton@-Namen, weil der sterbende Vorgänger
	# den Namen bis Frame-Ende blockierte.
	app.aktualisiere()
	app.aktualisiere()
	_pruefe_knopf_eindeutig(app, "vor dem Frame-Ende")
	await wait_frames(1)
	_pruefe_knopf_eindeutig(app, "nach dem queue_free-Flush")
	app.queue_free()
	await wait_frames(1)
	gs.free()


func _pruefe_knopf_eindeutig(app: FahrdienstApp, wann: String) -> void:
	var exakt := 0
	var krumm := 0
	for kind in app.get_children():
		if str(kind.name) == "RufenButton":
			exakt += 1
			assert_false(
				kind.is_queued_for_deletion(), "RufenButton lebt (kein Zombie) — %s" % wann
			)
		elif str(kind.name).contains("RufenButton"):
			krumm += 1
	assert_eq(exakt, 1, "genau EIN RufenButton — %s" % wann)
	assert_eq(krumm, 0, "kein umnummerierter @RufenButton@… — %s" % wann)
	assert_true(app.get_node_or_null("RufenButton") != null, "get_node findet ihn — %s" % wann)


## ------------------------------------------------------------ PT3-B5


func test_b5_ring_geometrie_konstanten() -> void:
	assert_almost(DriveLogic.CHECKPOINT_MIN_DIST_M, 24.0, 1e-9, "Ring rückt näher (40 → 24 m)")
	assert_almost(DriveLogic.CHECKPOINT_MAX_DIST_M, 90.0, 1e-9, "… und bleibt unter 90 m")
	assert_true(
		(
			float(DriveLogic.ARCADE["PICKUP_RADIUS_M"])
			< float(DriveLogic.ARCADE["CHECKPOINT_RADIUS_M"])
		),
		"Pickup-Radius (3) liegt IM Ring-Radius (4): Anker-Münze holen = Ring durchfahren"
	)


func test_b5_checkpoint_ankert_auf_der_muenzkette() -> void:
	# Startposition der Szene: unten auf der Ringstraße (city_drive.gd).
	var from := Vector2(0.0, 40.0)
	for seed_value in range(1, 21):
		var coins := DriveLogic.scatter_coins(
			GoobyRng.new(seed_value), int(DriveLogic.ARCADE["COINS_ACTIVE"])
		)
		var cp := DriveLogic.next_checkpoint(GoobyRng.new(seed_value * 31), from, coins)
		assert_true(coins.has(cp), "Ring ankert AUF einer aktiven Münze (Seed %d)" % seed_value)
		var tile := DriveLogic.world_to_tile(cp.x, cp.y)
		assert_true(DriveLogic.is_road(tile.x, tile.y), "Anker liegt auf der Straße")
		var band_da := false
		var fernste: Vector2 = coins[0]
		for coin in coins:
			var d := from.distance_to(coin)
			if d >= DriveLogic.CHECKPOINT_MIN_DIST_M and d <= DriveLogic.CHECKPOINT_MAX_DIST_M:
				band_da = true
			if d > from.distance_to(fernste):
				fernste = coin
		if band_da:
			var dist := from.distance_to(cp)
			assert_true(
				(
					dist >= DriveLogic.CHECKPOINT_MIN_DIST_M
					and dist <= DriveLogic.CHECKPOINT_MAX_DIST_M
				),
				"Ring steht im erreichbaren Band [24, 90] m (Seed %d: %.1f)" % [seed_value, dist]
			)
		else:
			assert_eq(cp, fernste, "ohne Band-Kandidat: fernste Münze (nie gratis)")
		assert_eq(
			DriveLogic.next_checkpoint(GoobyRng.new(seed_value * 31), from, coins),
			cp,
			"gesäte Wahl ist deterministisch (Seed %d)" % seed_value
		)


func test_b5_checkpoint_fallbacks() -> void:
	var from := Vector2(0.0, 40.0)
	# Alle Münzen zu nah (< 24 m): die fernste gewinnt — nie „Ankunft gratis“.
	var nah: Array[Vector2] = [
		from + Vector2(3.0, 0.0), from + Vector2(0.0, 10.0), from + Vector2(-20.0, 0.0)
	]
	assert_eq(
		DriveLogic.next_checkpoint(GoobyRng.new(7), from, nah),
		from + Vector2(-20.0, 0.0),
		"Band leer → fernste Münze"
	)
	# Ganz ohne Münzen bleibt die alte Kachel-Logik (Bestands-Rufe).
	for seed_value in range(1, 9):
		var cp := DriveLogic.next_checkpoint(GoobyRng.new(seed_value), from)
		assert_true(
			from.distance_to(cp) >= DriveLogic.CHECKPOINT_MIN_DIST_M,
			"Kachel-Fallback hält den Mindestabstand (Seed %d)" % seed_value
		)


## ------------------------------------------------------------ Helfer


func _hat_label(wurzel: Node, text: String) -> bool:
	for label in wurzel.find_children("*", "Label", true, false):
		if str((label as Label).text) == text:
			return true
	return false


func _hat_knopf(wurzel: Node, text: String) -> bool:
	for knopf in wurzel.find_children("*", "Button", true, false):
		if str((knopf as Button).text) == text:
			return true
	return false


func _finde_stand_sheet(wurzel: Node) -> MarktStandSheet:
	var stapel: Array[Node] = [wurzel]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is MarktStandSheet:
			return aktuell
		for kind in aktuell.get_children():
			stapel.append(kind)
	return null
