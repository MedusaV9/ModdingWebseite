extends TestCase
## W13C/E2E (EVAL-Restliste #30) — semantischer „erste Stunde“-Test: EIN
## zusammenhängendes Szenario mit ECHTEN Aktionen (kein Zufalls-Bot), das die
## erste Spielstunde eines neuen Spielers nachspielt und jeden Schritt
## SEMANTISCH prüft (Zustände, nicht nur „kein Crash“):
##
##   Frisch-Boot → Onboarding-Statemaschine (Name „Testi“, Spitzname,
##   Editor-Skip) → geführte Tour (OnboardingGuide) Schritt für Schritt mit
##   echten Aktionen: streicheln (GoobyReactions.handle_tap → Laune steigt),
##   füttern aus dem Kühlschrank (FoodCatalog.apply_feed → Hunger-Stat
##   steigt = Gooby weniger hungrig, firstNom-Sticker), waschen
##   (BadState.mark_washed), Münzen (Streichel-Treppe: 10. Streichler = +1),
##   erstes Minispiel teaParty (Bot-Logik-API + MinigameAward, Tagesbonus ×2
##   nur beim ERSTEN Spiel des Tages), IKEA-Kauf (ShopPurchase) →
##   Baumodus-Platzierung (GridData) → Garten (Möhre pflanzen/gießen, Uhr
##   3 h vorspulen, ernten → collections.veggies) → Tagesquests (Board
##   deterministisch aus dem Datum, pet5 abschließen + claimen) →
##   Save→Reload → ALLE Zustände identisch.
##
## Alle Zahlen sind DETERMINISTISCH: Uhr gepinnt (2026-07-30 12:00 UTC,
## Sommer), teaParty-Bot mit Seed 42 (Score 84), Quest-Roll gewürfelt aus
## hash32("2026-07-30") → [pet5, golf70, play2distinct]. Der komplette
## Münz-Verlauf ist unten pro Schritt mit assert_eq festgenagelt.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const EconomyLogic := preload("res://scripts/logic/economy.gd")
const LevelingLogic := preload("res://scripts/logic/leveling.gd")

## 2026-07-30 12:00:00 UTC — Mittag, damit die 3-h-Garten-Vorspule den
## Lokaltag NICHT wechselt (Quest-Board/petsToday sind tagesgebunden).
const NOW_MS := 1785412800000
const HEUTE := "2026-07-30"
## Deterministischer Bot-Seed: Score 84 (< Ziel 85, ≥ 60 → teaTime-Sticker).
const TEA_SEED := 42
const BEET := Vector2i(2, 2)


## Raum-Stub für GoobyReactions: nur die Duck-Typing-Oberfläche, die der
## Runner wirklich abfragt (game_state()/gooby()/grid) — kein 3D nötig.
class StubRaum:
	extends Node
	var grid: Object = null
	var gs_ref: Object = null

	func game_state() -> Object:
		return gs_ref

	func gooby() -> Node3D:
		return null


func test_erste_stunde_neuer_spieler() -> void:
	var dir := "user://w13c_tests/erste_stunde_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var save_path := dir + "/save_v5.json"

	# ── Frisch-Boot ohne Save ────────────────────────────────────────────────
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(save_path)
	tree.root.add_child(gs)
	assert_eq(gs.clock.local_day(), HEUTE, "gepinnter Lokaltag")
	assert_false(bool(gs.get_value("onboarding.done")), "frischer Save: Onboarding offen")
	assert_eq(int(gs.get_value("economy.coins")), EconomyLogic.STARTING_COINS, "Start-Münzen 100")
	assert_eq(int(gs.get_value("inventory.food.carrot")), 3, "Starter-Kühlschrank: 3 Möhren")
	assert_almost(float(gs.get_value("gooby.stats.hunger")), 80.0, 1e-6, "Start-Hunger 80")

	# ── Onboarding-Statemaschine: Name „Testi“, Spitzname, Editor-Skip ───────
	var flow := OnboardingLogic.new()
	assert_false(flow.submit_name("   "), "leerer Name wird abgelehnt")
	assert_true(flow.submit_name("Testi"), "Name Testi angenommen")
	flow.submit_nickname("Flauschi")
	assert_eq(flow.step, OnboardingLogic.Step.EDITOR, "nach Spitzname: Editor")
	flow.skip_editor()
	var profil := flow.finish()
	gs.apply_onboarding_profile(profil)
	assert_eq(str(gs.get_value("meta.playerName")), "Testi", "Spielername persistiert")
	assert_eq(str(gs.get_value("meta.goobyNickname")), "Flauschi", "Spitzname persistiert")
	assert_true(bool(gs.get_value("onboarding.done")), "Onboarding abgeschlossen")
	assert_almost(
		float(gs.get_value("meta.charMorphs.eye_scale")), 1.0, 1e-6, "Editor-Skip = Defaults"
	)
	HomeState.ensure_initialized(gs)
	assert_false(
		(gs.get_value("home.rooms", {}) as Dictionary).is_empty(), "Erstbezug legt Räume an"
	)

	# ── Dienste wie im echten Boot: RewardHub, Tagesquests, Tour ────────────
	var host := Node.new()
	tree.root.add_child(host)
	var hub := RewardHub.attach_to(host, gs)
	assert_ne(hub, null, "RewardHub hängt")
	await wait_frames(1)
	# Boot-Auswertung: erster Sticker (erster_boot) → Erfolg firstSticker +10.
	assert_true(
		(gs.get_value("stickers.unlocked", {}) as Dictionary).has("sticker_erster_boot"),
		"Boot-Sticker sofort frei"
	)
	assert_true(
		(gs.get_value("achievements.unlocked", {}) as Dictionary).has("firstSticker"),
		"Erfolg firstSticker"
	)
	assert_eq(int(gs.get_value("economy.coins")), 110, "100 Start + 10 firstSticker")
	assert_eq(int(gs.get_value("economy.coinsEarned")), 10, "Earned-Konto stimmt")

	var quests := DailyQuestService.attach_to(host, gs)
	assert_eq(str(gs.get_value("quests.day")), HEUTE, "Quest-Board für heute gerollt")
	var board_ids: Array[String] = []
	for eintrag: Dictionary in gs.get_value("quests.active", []):
		board_ids.append(str(eintrag["id"]))
	assert_eq(
		board_ids,
		["pet5", "golf70", "play2distinct"] as Array[String],
		"Roll ist deterministisch aus hash32(Tag)"
	)

	var guide := OnboardingGuide.attach_to(host, gs)
	assert_ne(guide, null, "frischer Save startet die Tour")
	await wait_frames(2)
	assert_eq(guide.current_step_id(), "ankunft", "Tour beginnt mit der Ankunft")
	guide._on_next_pressed()
	assert_eq(guide.current_step_id(), "streicheln", "Schritt 1: streicheln")

	# ── Streicheln: echter Tipp über GoobyReactions → Laune + petsToday ─────
	var stub := StubRaum.new()
	stub.gs_ref = gs
	host.add_child(stub)
	var reactions := GoobyReactions.new()
	reactions.name = "GoobyReactions"
	reactions.visuals_enabled = false
	reactions.now_ms_override = NOW_MS
	stub.add_child(reactions)
	reactions.setup(stub)
	# Idle-/Überraschungs-Timer einfrieren: _process würde nach 60/90 s echte
	# Münzfunde gewähren und den deterministischen Münz-Verlauf zerstören.
	reactions.set_process(false)
	var laune_vorher := float(SoulState.slice_of(gs)["stimmung"]["wert"])
	reactions.handle_tap()
	assert_eq(int(gs.get_value("achievements.counters.petsToday")), 1, "1. Streichler gezählt")
	assert_eq(str(gs.get_value("achievements.counters.petsDay")), HEUTE, "tagesgebunden")
	var laune_nachher := float(SoulState.slice_of(gs)["stimmung"]["wert"])
	assert_true(laune_nachher > laune_vorher, "Streicheln hebt die Laune (Stat steigt)")
	# Erster Sommer-Tagesstempel im Save → Jahreszeiten-Sticker.
	assert_true(
		(gs.get_value("stickers.unlocked", {}) as Dictionary).has("jz_sommer"),
		"Sommer-Saisonsticker über petsDay"
	)
	var weiter := await wait_until(
		func() -> bool: return guide.current_step_id() == "fuettern", 10000
	)
	assert_true(weiter, "Tour feiert das Streicheln und schaltet auf füttern")

	# ── Füttern aus dem Kühlschrank: Möhre → Hunger-Stat steigt, firstNom ───
	var hunger_vorher := float(gs.get_value("gooby.stats.hunger"))
	var feed := {}
	gs.update(
		func(state: Dictionary) -> void: feed.merge(FoodCatalog.apply_feed(state, "carrot"), true)
	)
	RewardHub.note_action(gs)
	assert_eq(str(feed.get("id", "")), "carrot", "Fütterung hat stattgefunden")
	assert_true(bool(feed.get("favorit", false)), "Möhre ist Lieblingsessen")
	assert_almost(
		float(gs.get_value("gooby.stats.hunger")),
		hunger_vorher + 10.0,
		1e-6,
		"Möhre +10 Sättigung (Gooby weniger hungrig)"
	)
	assert_eq(int(gs.get_value("inventory.food.carrot")), 2, "Vorrat −1")
	assert_eq(int(gs.get_value("achievements.counters.feeds")), 1, "feeds-Zähler")
	assert_almost(float(gs.get_value("gooby.weight")), 50.5, 1e-6, "gesundes Essen +0.5 Gewicht")
	assert_true(
		(gs.get_value("stickers.unlocked", {}) as Dictionary).has("firstNom"),
		"erster Feed → Sticker firstNom"
	)
	assert_eq(int(gs.get_value("economy.coins")), 120, "+10 Erfolg firstFeed")
	weiter = await wait_until(func() -> bool: return guide.current_step_id() == "waschen", 10000)
	assert_true(weiter, "Tour schaltet auf waschen")

	# ── Waschen (Bad-Suite-Pfad) ─────────────────────────────────────────────
	BadState.mark_washed(gs)
	assert_eq(int(gs.get_value("achievements.counters.washes")), 1, "washes-Zähler")
	assert_true(
		(gs.get_value("stickers.unlocked", {}) as Dictionary).has("squeakyClean"),
		"erste Wäsche → Sticker squeakyClean"
	)
	assert_eq(int(gs.get_value("economy.coins")), 130, "+10 Erfolg firstWash")
	weiter = await wait_until(func() -> bool: return guide.current_step_id() == "muenzen", 10000)
	assert_true(weiter, "Tour schaltet auf Münzen")

	# ── Münzen checken: Streichel-Treppe — der 10. Streichler des Tages ─────
	for _i in 9:
		reactions.handle_tap()
	assert_eq(int(gs.get_value("achievements.counters.petsToday")), 10, "10 Streichler heute")
	assert_eq(int(gs.get_value("achievements.counters.tickles")), 2, "2× kitzlig (3. Tipp)")
	assert_eq(int(gs.get_value("economy.coins")), 131, "10. Streichler = +1 Münze")
	assert_eq(int(gs.get_value("economy.coinsEarned")), 31, "Earned-Konto nach Treppe")
	weiter = await wait_until(func() -> bool: return guide.current_step_id() == "minispiel", 10000)
	assert_true(weiter, "verdiente Münze erfüllt den Münz-Schritt")

	# ── Erstes Minispiel: teaParty über die Logik-API mit Bot ────────────────
	var meta := MinigameRegistry.get_game("teaParty")
	assert_false(meta.is_empty(), "teaParty registriert")
	var sim := TeaPartyLogic.simulate_autoplay("normal", TEA_SEED)
	var score := int(sim["score"])
	assert_eq(score, 84, "Bot-Score deterministisch (Seed 42)")
	var basis := MinigameFrameworkLogic.apply_difficulty_coin_base(
		meta["coin_table"], score, "normal"
	)
	assert_eq(basis, 21, "Coin-Basis §G5.2: floor(84/4) geklemmt auf 4..26")
	var award := {}
	gs.update(
		func(state: Dictionary) -> void:
			award.merge(MinigameAward.award(state, meta, score, "normal", HEUTE), true)
	)
	RewardHub.note_action(gs)
	assert_true(bool(award["firstToday"]), "erstes Spiel des Tages erkannt")
	assert_eq(int(award["coins"]), basis * 2, "Tagesbonus ×2 greift")
	assert_eq(int(award["xp"]), 25, "Runden-XP: 10 + min(15, 42/2)")
	assert_eq(int(gs.get_value("economy.coins")), 173, "131 + 42 Minispiel-Münzen")
	assert_almost(float(gs.get_value("progression.xp")), 25.0, 1e-6, "XP gebucht")
	assert_eq(int(gs.get_value("progression.level")), 1, "Level 1 bleibt (25 < 100 XP)")
	assert_almost(float(gs.get_value("gooby.stats.fun")), 87.0, 1e-6, "+15 Spaß (72 → 87)")
	assert_eq(int(gs.get_value("minigames.plays.teaParty")), 1, "Runde gezählt")
	assert_eq(int(gs.get_value("minigames.legacy.best.teaParty")), 84, "Bestwert-Board")
	assert_eq(str(gs.get_value("minigames.legacy.lastPlayDay.teaParty")), HEUTE, "Tagesstempel")
	assert_true(
		(gs.get_value("stickers.unlocked", {}) as Dictionary).has("teaTime"),
		"Bestwert ≥ 60 → Sticker teaTime"
	)
	# Gegenprobe Tagesbonus: die ZWEITE Runde desselben Tages zahlt nur ×1.
	var award2 := {}
	gs.update(
		func(state: Dictionary) -> void:
			award2.merge(MinigameAward.award(state, meta, score, "normal", HEUTE), true)
	)
	RewardHub.note_action(gs)
	assert_false(bool(award2["firstToday"]), "zweite Runde: kein Tagesbonus mehr")
	assert_eq(int(award2["coins"]), basis, "zweite Runde zahlt ×1")
	assert_false(bool(award2["newBest"]), "84 schlägt 84 nicht")
	assert_eq(int(gs.get_value("economy.coins")), 194, "173 + 21")
	assert_almost(float(gs.get_value("progression.xp")), 45.0, 1e-6, "25 + 20 XP")
	weiter = await wait_until(func() -> bool: return guide.current_step_id() == "moebel", 10000)
	assert_true(weiter, "Tour schaltet auf Möbel")

	# ── IKEA: 1 Möbel kaufen (atomar: Münzen → Lager) ────────────────────────
	var lager_vorher := StorageLogic.count_of(HomeState.storage(gs), "boxA")
	assert_eq(ShopPurchase.buy(gs, "boxA"), ShopPurchase.RESULT_OK, "Kauf ok (10 Münzen)")
	assert_eq(int(gs.get_value("economy.coins")), 184, "194 − 10 Kaufpreis")
	assert_eq(int(gs.get_value("economy.coinsSpent")), 10, "Ausgaben-Konto")
	assert_eq(
		StorageLogic.count_of(HomeState.storage(gs), "boxA"), lager_vorher + 1, "Kiste im Lager"
	)
	# Möbel- und Sticker-Schritt feiern durch (Sticker gibt es längst) …
	weiter = await wait_until(func() -> bool: return guide.current_step_id() == "ausblick", 12000)
	assert_true(weiter, "Kauf + vorhandene Sticker: Tour steht am Ausblick")
	guide._on_next_pressed()
	weiter = await wait_until(
		func() -> bool: return bool(gs.get_value("onboarding.guide.done", false)), 8000
	)
	assert_true(weiter, "Tour sauber abgeschlossen (guide.done)")

	# ── Baumodus: Kiste aus dem Lager platzieren (GridData-API) ─────────────
	assert_true(HomeState.take_from_storage(gs, "boxA"), "Kiste aus dem Lager genommen")
	var grid := HomeState.load_room_grid(gs, "living")
	var box_def := FurnitureCatalog.def("boxA")
	var zelle := Vector2i(-1, -1)
	for y in grid.size.y:
		for x in grid.size.x:
			if bool(grid.can_place(box_def, Vector2i(x, y), 0)["ok"]):
				zelle = Vector2i(x, y)
				break
		if zelle.x >= 0:
			break
	assert_true(zelle.x >= 0, "freie Zelle im Wohnzimmer gefunden")
	var uid := HomeState.next_uid(gs)
	assert_true(bool(grid.place(box_def, zelle, 0, uid)["ok"]), "Platzierung kollisionsfrei")
	HomeState.save_room_grid(gs, "living", grid)
	assert_eq(_raum_item(gs, "living", uid).get("item"), "boxA", "Kiste liegt persistiert im Raum")

	# ── Garten: Möhre pflanzen, gießen, 3 h vorspulen, ernten ────────────────
	var t0_s := float(gs.clock.now_ms()) / 1000.0
	GardenState.tick(gs, t0_s)
	assert_true(GardenState.pflanzen(gs, BEET, "carrot"), "Möhre gepflanzt")
	assert_true(GardenState.giessen(gs, BEET, t0_s), "Beet gegossen (hält 8 h)")
	assert_eq(int(gs.get_value("achievements.counters.plantings")), 1, "plantings-Zähler")
	assert_eq(int(gs.get_value("achievements.counters.waterings")), 1, "waterings-Zähler")
	# Realistische Zeitinjektion: 3 h + 2 min vorspulen (3 Stufen à 60 min).
	gs.clock.advance(3 * 3_600_000 + 120_000)
	var t1_s := float(gs.clock.now_ms()) / 1000.0
	assert_eq(GardenState.tick(gs, t1_s), 1, "genau 1 Beet ist gewachsen")
	var beet_daten := GardenState.grid(gs).cell(BEET)
	assert_eq(int(beet_daten.get("stage", -1)), 3, "Möhre auf Endstufe 3")
	assert_true(GardenGrowth.ist_erntereif(beet_daten), "erntereif")
	assert_eq(GardenState.ernten(gs, BEET), 2, "Ernte: 2 Möhren")
	assert_eq(int(gs.get_value("inventory.food.carrot")), 4, "2 Vorrat + 2 Ernte")
	assert_eq(int(GardenState.ernte(gs).get("carrot", 0)), 2, "Wochenmarkt-Lager gefüllt")
	assert_eq(int(gs.get_value("achievements.counters.harvests")), 1, "harvests-Zähler")
	# collections.veggies gebucht! (Map-Key enthält einen Punkt → state()-Read)
	var sammlung: Dictionary = gs.state()["collections"]["entries"]
	assert_eq(int(sammlung.get("veggies.carrot", 0)), 1, "Album-Set veggies: carrot gebucht")
	assert_true(
		(gs.get_value("stickers.unlocked", {}) as Dictionary).has("firstSprout"),
		"erste Ernte → Sticker firstSprout"
	)
	assert_eq(int(gs.get_value("economy.coins")), 199, "+15 Erfolg firstHarvest")

	# ── Tagesquest-Fortschritt prüfen + pet5 claimen ─────────────────────────
	var pool_by_id := DailyQuestEngine.pool_by_id(DailyQuestCatalog.pool())
	assert_eq(_quest_fortschritt(gs, pool_by_id, "pet5"), 5, "pet5: 10 Streichler ≥ Ziel 5")
	assert_eq(_quest_fortschritt(gs, pool_by_id, "golf70"), 0, "golf70: nie gespielt")
	assert_eq(_quest_fortschritt(gs, pool_by_id, "play2distinct"), 1, "1 von 2 Spielen probiert")
	# BEKANNTER SERVICE-BUG (Request „E2E“ in W13-requests.md): quests.claim()
	# reassigned sein result-Dict INNERHALB der update-Lambda — GDScript-
	# Lambdas kapseln per Kopie, der Rückgabewert bleibt {"ok": false}, obwohl
	# Claim + Auszahlung im State durchlaufen. Bis zum Fix prüfen wir den
	# Claim deshalb SEMANTISCH über den State statt über das Result-Dict.
	var muenzen_vor_claim := int(gs.get_value("economy.coins"))
	var xp_vor_claim := float(gs.get_value("progression.xp"))
	quests.claim("pet5")
	assert_eq(
		int(gs.get_value("economy.coins")) - muenzen_vor_claim,
		15 + 10,
		"Claim zahlt 15 Quest-Münzen + 10 Erfolg firstQuest"
	)
	assert_almost(float(gs.get_value("progression.xp")) - xp_vor_claim, 8.0, 1e-6, "Quest-XP 8")
	assert_true(_quest_geclaimt(gs, "pet5"), "pet5 im Board als geclaimt markiert")
	assert_eq(int(gs.get_value("quests.completedTotal")), 1, "completedTotal gestempelt")
	assert_eq(int(gs.get_value("achievements.counters.questsDone")), 1, "questsDone-Zähler")
	assert_true(
		(gs.get_value("achievements.unlocked", {}) as Dictionary).has("firstQuest"),
		"Erfolg firstQuest"
	)
	assert_eq(int(gs.get_value("economy.coins")), 224, "199 + 15 Quest + 10 firstQuest")
	assert_almost(float(gs.get_value("progression.xp")), 53.0, 1e-6, "45 + 8 Quest-XP")

	# ── Save → Reload: ALLE Zustände identisch ───────────────────────────────
	# Erst die 3 h Offline-Zeit deterministisch verticken (Stats-Verfall),
	# dann speichern — jeder weitere Tick ist bei stehender Uhr ein No-op.
	gs.run_live_tick()
	assert_true(gs.save_now(), "Save geschrieben")
	var gs2: Node = GameStateScript.new()
	gs2.clock.pin(gs.clock.now_ms())
	gs2.clock.set_utc_offset_minutes(0)
	gs2.initialize(save_path)
	for pfad: String in [
		"economy.coins",
		"economy.coinsEarned",
		"economy.coinsSpent",
		"progression.level",
		"progression.xp",
		"meta.playerName",
		"meta.goobyNickname",
		"onboarding.done",
		"onboarding.guide.done",
		"inventory.food.carrot",
		"achievements.counters.feeds",
		"achievements.counters.washes",
		"achievements.counters.petsToday",
		"achievements.counters.tickles",
		"achievements.counters.plantings",
		"achievements.counters.waterings",
		"achievements.counters.harvests",
		"achievements.counters.questsDone",
		"minigames.plays.teaParty",
		"minigames.legacy.best.teaParty",
		"home.storageCapacity",
		"quests.day",
		"quests.completedTotal",
		"gooby.weight",
		"gooby.stats.hunger",
		"gooby.stats.fun",
		"gooby.stats.energy",
		"gooby.stats.hygiene",
	]:
		_gleich(gs, gs2, pfad)
	assert_eq(int(gs2.get_value("economy.coins")), 224, "Reload: Münzen exakt")
	# JSON.stringify(sort_keys) sortiert Map-Keys beim Speichern → für den
	# Mengen-Vergleich beide Seiten sortieren.
	assert_eq(
		_sortierte_keys(gs2, "stickers.unlocked"),
		_sortierte_keys(gs, "stickers.unlocked"),
		"Sticker-Satz identisch"
	)
	assert_eq(
		_sortierte_keys(gs2, "achievements.unlocked"),
		_sortierte_keys(gs, "achievements.unlocked"),
		"Erfolgs-Satz identisch"
	)
	assert_eq(
		_raum_item(gs2, "living", uid).get("item"), "boxA", "Reload: Möbel steht noch im Raum"
	)
	var grid2 := HomeState.load_room_grid(gs2, "living")
	var item2: Dictionary = _raum_item(gs2, "living", uid)
	assert_eq(int(item2["at"][0]), zelle.x, "Reload: Zelle x")
	assert_eq(int(item2["at"][1]), zelle.y, "Reload: Zelle y")
	assert_false(bool(grid2.can_place(box_def, zelle, 0)["ok"]), "Reload: Zelle belegt")
	assert_eq(str(GardenState.grid(gs2).cell(BEET).get("crop", "?")), "", "Reload: Beet geerntet")
	assert_eq(int(GardenState.ernte(gs2).get("carrot", 0)), 2, "Reload: Ernte-Lager")
	var sammlung2: Dictionary = gs2.state()["collections"]["entries"]
	assert_eq(int(sammlung2.get("veggies.carrot", 0)), 1, "Reload: Album-Set")
	var board2_ids: Array[String] = []
	var pet5_claimed := false
	for eintrag: Dictionary in gs2.get_value("quests.active", []):
		board2_ids.append(str(eintrag["id"]))
		if str(eintrag["id"]) == "pet5":
			pet5_claimed = bool(eintrag.get("claimed", false))
	assert_eq(board2_ids, board_ids, "Reload: Quest-Board identisch")
	assert_true(pet5_claimed, "Reload: pet5 bleibt geclaimt")
	assert_eq(
		_quest_fortschritt(gs2, pool_by_id, "play2distinct"),
		1,
		"Reload: Quest-Fortschritt identisch (Baseline eingefroren)"
	)

	# ── Aufräumen ────────────────────────────────────────────────────────────
	host.queue_free()
	await wait_frames(1)
	tree.root.remove_child(gs)
	gs.free()
	gs2.free()


## Fortschritt eines Board-Eintrags über die Engine (wie das Quest-Panel).
func _quest_fortschritt(gs: Object, pool_by_id: Dictionary, quest_id: String) -> int:
	for eintrag: Dictionary in gs.get_value("quests.active", []):
		if str(eintrag["id"]) == quest_id:
			var def: Dictionary = pool_by_id.get(quest_id, {})
			return DailyQuestEngine.progress_of(eintrag, def, gs.state())
	fail_test("Quest %s nicht auf dem Board" % quest_id)
	return -1


## Claimed-Flag eines Board-Eintrags.
func _quest_geclaimt(gs: Object, quest_id: String) -> bool:
	for eintrag: Dictionary in gs.get_value("quests.active", []):
		if str(eintrag["id"]) == quest_id:
			return bool(eintrag.get("claimed", false))
	return false


## Map-Keys eines Slice-Pfads, alphabetisch sortiert (Save sortiert Keys).
func _sortierte_keys(gs: Object, pfad: String) -> Array:
	var keys: Array = (gs.get_value(pfad, {}) as Dictionary).keys()
	keys.sort()
	return keys


## Persistierter Raum-Eintrag (home.rooms.<raum>.items) zu einer uid.
func _raum_item(gs: Object, raum_id: String, uid: String) -> Dictionary:
	for eintrag: Variant in gs.get_value("home.rooms.%s.items" % raum_id, []):
		if eintrag is Dictionary and str((eintrag as Dictionary).get("uid", "")) == uid:
			return eintrag
	return {}


## Save→Reload-Vergleich mit Zahlentyp-Koerzierung (JSON macht int → float).
func _gleich(gs: Object, gs2: Object, pfad: String) -> void:
	var a: Variant = gs.get_value(pfad)
	var b: Variant = gs2.get_value(pfad)
	if (a is int or a is float) and (b is int or b is float):
		assert_almost(float(a), float(b), 1e-6, "Reload-Drift bei %s" % pfad)
	else:
		assert_eq(b, a, "Reload-Drift bei %s" % pfad)
