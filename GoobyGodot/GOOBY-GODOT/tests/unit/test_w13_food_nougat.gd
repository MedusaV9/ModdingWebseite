extends TestCase
## W13/FOOD (P1 Punkte 2+17) — sieben neue Speisen (Web-Parität 32→39) und
## die Nougatschleuse: Katalog-Vollständigkeit (jede neue Id hat ein
## existierendes Asset), Web-Delta-Exaktheit, REHWEI-Preise, de/en-Namen,
## Schleusen-Zustandsmaschine (Install→Bereit→Ausgabe→Cooldown, Zeit
## injiziert) und die Glas-Gutschrift ins Inventar.

const NougatLogicScript := preload("res://scripts/logic/nougat_logic.gd")

const ESSEN_DIR := "res://assets/city/essen"

## Web-Referenz verbatim (GOOBY/src/data/constants.js FOOD_TABLE bzw.
## foods.js V4_BAKERY_FOODS/V3-G35): id → {deltas..., junk, preis}.
const WEB_NEUZUGAENGE := {
	"ice-cream": {"hunger": 6, "fun": 15, "energy": 5, "hygiene": 0, "junk": true, "preis": 16},
	"cake": {"hunger": 30, "fun": 20, "energy": 0, "hygiene": 0, "junk": true, "preis": 40},
	"pumpkin": {"hunger": 26, "fun": 4, "energy": 0, "hygiene": 0, "junk": false, "preis": 22},
	"sundae": {"hunger": 7, "fun": 14, "energy": 3, "hygiene": 0, "junk": true, "preis": 18},
	"cinnamonRoll": {"hunger": 16, "fun": 8, "energy": 3, "hygiene": -2, "junk": true, "preis": 16},
	"cupcakePink": {"hunger": 10, "fun": 10, "energy": 2, "hygiene": -2, "junk": true, "preis": 14},
	"nutella": {"hunger": 18, "fun": 6, "energy": 2, "hygiene": -4, "junk": true, "preis": 45},
}


## Voll ausgestatteter v5-artiger Save-Ausschnitt für die Schleusen-Tests.
func _state(hunger := 40.0) -> Dictionary:
	return {
		"gooby":
		{
			"stats": {"hunger": hunger, "fun": 50.0, "energy": 50.0, "hygiene": 50.0},
			"weight": 50.0,
			"health": {"state": "healthy", "junkScore": 0.0},
			"sleep": {"sleeping": false},
		},
		"inventory": {"food": {}},
		"progression": {"xp": 0.0, "level": 1},
		"economy": {"coins": 0},
		"achievements": {"counters": {}},
	}


# ── Teil (a): Speise-Katalog ──────────────────────────────────────────────────


func test_sieben_neue_speisen_mit_exakten_web_deltas() -> void:
	for id: String in WEB_NEUZUGAENGE:
		var web: Dictionary = WEB_NEUZUGAENGE[id]
		assert_true(FoodCatalog.FOODS.has(id), "Katalog-Eintrag fehlt: %s" % id)
		var d := FoodCatalog.deltas(id)
		for stat: String in ["hunger", "fun", "energy", "hygiene"]:
			assert_almost(
				float(d[stat]), float(web[stat]), 1e-6, "Web-Delta %s.%s weicht ab" % [id, stat]
			)
		assert_eq(FoodCatalog.is_junk(id), bool(web["junk"]), "Junk-Flag weicht ab: %s" % id)
		assert_false(FoodCatalog.is_favorite(id), "kein Neuzugang ist Liebling: %s" % id)


func test_rehwei_fuehrt_neuzugaenge_mit_web_preisen() -> void:
	var waren := CitySortiment.laden(CitySortiment.REHWEI_PFAD)
	assert_true(not waren.is_empty(), "REHWEI-Sortiment lädt")
	for id: String in WEB_NEUZUGAENGE:
		var eintrag := CitySortiment.ware(waren, id)
		assert_false(eintrag.is_empty(), "REHWEI führt %s nicht" % id)
		assert_eq(
			int(eintrag.get("preis", -1)),
			int(WEB_NEUZUGAENGE[id]["preis"]),
			"Preis weicht von der Web-Referenz ab: %s" % id
		)
	# Sortiment bleibt preis-aufsteigend sortiert (Katalog-/Tray-Ordnung).
	var vorher := -1
	for eintrag: Dictionary in waren:
		var preis := int(eintrag.get("preis", 0))
		assert_true(preis >= vorher, "Sortiment nicht preis-sortiert bei %s" % eintrag.get("id"))
		vorher = preis


func test_jede_rehwei_ware_hat_existierendes_glb() -> void:
	# Katalog-Vollständigkeit: jede Ware zeigt auf ein real vorhandenes
	# Asset unter assets/city/essen/ (Muster test_ef1, jetzt inkl. Datei-Check).
	for eintrag: Dictionary in CitySortiment.laden(CitySortiment.REHWEI_PFAD):
		var id := str(eintrag.get("id", ""))
		var glb := str(eintrag.get("glb", ""))
		assert_true(glb.ends_with(".glb"), "Ware ohne GLB-Verweis: %s" % id)
		assert_true(
			FileAccess.file_exists("%s/%s" % [ESSEN_DIR, glb]), "GLB fehlt für %s: %s" % [id, glb]
		)
		assert_true(FoodCatalog.FOODS.has(id), "REHWEI-Ware fehlt im FoodCatalog: %s" % id)


func test_neue_speisen_haben_de_und_en_namen() -> void:
	var de: Dictionary = I18nService.table("de")
	var en: Dictionary = I18nService.table("en")
	for id: String in WEB_NEUZUGAENGE:
		var key := "rewards.food." + id
		assert_true(de.has(key), "DE-Name fehlt: %s" % key)
		assert_true(en.has(key), "EN-Name fehlt: %s" % key)


# ── Teil (b): Nougatschleuse ──────────────────────────────────────────────────


func test_moebelkatalog_fuehrt_nougatschleuse_mit_asset() -> void:
	var def := FurnitureCatalog.def(NougatLogicScript.FURNITURE_ID)
	assert_false(def.is_empty(), "Möbelkatalog kennt die Nougatschleuse nicht")
	assert_eq(int(def.get("layer", -1)), int(GridData.Layer.WALL), "Wand-Item wie im Web (§C6.3)")
	assert_eq(str(def.get("kategorie", "")), "kueche", "Küchen-Kategorie")
	assert_eq(int(def.get("preis", 0)), NougatLogicScript.PRICE, "400 Münzen (§C6.3)")
	assert_true(
		FileAccess.file_exists(FurnitureCatalog.glb_path(def)),
		"GLB fehlt: %s" % FurnitureCatalog.glb_path(def)
	)


func test_nougat_strings_de_und_en_vorhanden() -> void:
	var de: Dictionary = I18nService.table("de")
	var en: Dictionary = I18nService.table("en")
	var keys: Array[String] = [
		"nougat.installiert",
		"nougat.schlaeft",
		"nougat.krank",
		"nougat.pause",
		"nougat.klecks1",
		"nougat.klecks2",
		"nougat.klecks3",
		"nougat.glas_bonus",
	]
	for key: String in keys:
		assert_true(de.has(key), "DE-String fehlt: %s" % key)
		assert_true(en.has(key), "EN-String fehlt: %s" % key)


func test_zustandsmaschine_install_bereit_ausgabe_cooldown() -> void:
	var state := _state()
	var now := 1_000_000
	# Install: frisch → true, idempotent → false, Flag persistiert im Slice.
	assert_false(NougatLogicScript.is_installed(state), "frischer Save: nicht installiert")
	assert_true(NougatLogicScript.mark_installed(state), "Erst-Installation meldet true")
	assert_false(NougatLogicScript.mark_installed(state), "zweiter Aufruf ist idempotent")
	assert_true(NougatLogicScript.is_installed(state))
	# Bereit: kein Cooldown, keine Refusal.
	assert_eq(NougatLogicScript.cooldown_remaining_ms(state, now), 0, "frisch = bereit")
	assert_true(bool(NougatLogicScript.can_glob(state, now).get("ok")), "bereit")
	# Ausgabe: Klecks startet den Cooldown (lastGlobAt = now).
	var result := NougatLogicScript.apply_glob(state, now)
	assert_false(result.is_empty(), "Klecks kam durch")
	assert_eq(int(state["easterEggs"]["nougat"]["lastGlobAt"]), now, "Stempel persistiert")
	# Cooldown: 1 min später sind noch 29 min übrig, Refusal-Grund stimmt.
	var spaeter := now + 60_000
	assert_eq(NougatLogicScript.cooldown_remaining_ms(state, spaeter), 29 * 60_000)
	var verdict := NougatLogicScript.can_glob(state, spaeter)
	assert_false(bool(verdict.get("ok")), "Cooldown sperrt")
	assert_eq(str(verdict.get("reason")), "cooldown")
	# Wieder bereit: exakt nach 30 ECHTEN Minuten (§C6.4).
	var danach := now + NougatLogicScript.COOLDOWN_MIN * 60_000
	assert_eq(NougatLogicScript.cooldown_remaining_ms(state, danach), 0)
	assert_true(bool(NougatLogicScript.can_glob(state, danach).get("ok")), "nach 30 min bereit")


func test_refusal_matrix_schlafend_krank_und_zukunfts_clamp() -> void:
	var now := 5_000_000
	# Schlafend gewinnt (Web-Reihenfolge §C6.4).
	var schlaf := _state()
	schlaf["gooby"]["sleep"]["sleeping"] = true
	schlaf["gooby"]["health"]["state"] = "sick"
	assert_eq(str(NougatLogicScript.can_glob(schlaf, now).get("reason")), "sleeping")
	# Krank vor Cooldown.
	var krank := _state()
	krank["gooby"]["health"]["state"] = "sick"
	assert_eq(str(NougatLogicScript.can_glob(krank, now).get("reason")), "sick")
	# V3/FIX-A-Clamp: lastGlobAt weiter in der Zukunft als EIN Cooldown
	# wird wie „gerade gekleckst" behandelt (nie ~285k Jahre Sperre).
	var kaputt := _state()
	NougatLogicScript.slice(kaputt)["lastGlobAt"] = now + 31 * 60_000
	assert_eq(
		NougatLogicScript.cooldown_remaining_ms(kaputt, now),
		NougatLogicScript.COOLDOWN_MIN * 60_000,
		"Zukunfts-Müll = voller Cooldown ab jetzt"
	)


func test_apply_glob_wirkt_auf_stats_pipes_und_inventar() -> void:
	var state := _state()
	var now := 9_000_000
	var result := NougatLogicScript.apply_glob(state, now)
	# Stats über Stats.apply_deltas: +15 Hunger, +10 Spaß, −8 Hygiene.
	assert_almost(float(state["gooby"]["stats"]["hunger"]), 55.0, 1e-6, "Hunger +15")
	assert_almost(float(state["gooby"]["stats"]["fun"]), 60.0, 1e-6, "Spaß +10")
	assert_almost(float(state["gooby"]["stats"]["hygiene"]), 42.0, 1e-6, "Hygiene −8")
	assert_almost(float(state["gooby"]["stats"]["energy"]), 50.0, 1e-6, "Energie unberührt")
	assert_almost(float(result["hunger_gain"]), 15.0, 1e-6, "Anzeigewert fürs Float")
	# DOPPELTER Junk durch die Health-Pipe, EIN Junk-Mahl fürs Gewicht (§C6.4).
	assert_almost(float(state["gooby"]["health"]["junkScore"]), 2.0, 1e-6, "junkScore +2")
	assert_almost(float(state["gooby"]["weight"]), 52.0, 1e-6, "Gewicht +2 (EAT_JUNK ×1)")
	# XP +2 über die Leveling-Pipe (Level 1 bleibt, keine Münzen).
	assert_almost(float(state["progression"]["xp"]), 2.0, 1e-6, "XP +2")
	assert_eq(int(state["progression"]["level"]), 1)
	assert_eq(int(result["coins_awarded"]), 0)
	# Inventar-Gutschrift: EIN nutella-Glas kullert in den Vorrat.
	assert_eq(str(result["jar_id"]), "nutella")
	assert_eq(int(state["inventory"]["food"]["nutella"]), 1, "Glas gutgeschrieben")
	assert_eq(int(result["jars"]), 1)
	# Sticker-Zähler (nutellaGlob/nougatFlood/kueche_nutellabrot lesen ihn).
	assert_eq(int(state["achievements"]["counters"]["nougatGlobs"]), 1)
	assert_eq(int(result["globs"]), 1)
	# Das gutgeschriebene Glas ist FÜTTERBAR und nährt mit Web-Deltas (+18).
	var feed := FoodCatalog.apply_feed(state, "nutella")
	assert_almost(float(feed["hunger_gain"]), 18.0, 1e-6, "Glas füttert mit Web-Delta")
	assert_true(bool(feed["junk"]))
	assert_false(state["inventory"]["food"].has("nutella"), "Glas verbraucht")


func test_apply_glob_levelt_und_bucht_muenzen_ueber_den_einen_geldpfad() -> void:
	var state := _state()
	state["progression"] = {"xp": 99.0, "level": 1}
	var result := NougatLogicScript.apply_glob(state, 42_000)
	assert_eq(int(result["level"]), 2, "99+2 XP überspringt die 100er-Schwelle")
	assert_eq(int(result["levels_gained"]), 1)
	assert_eq(int(result["coins_awarded"]), 50, "25 × neues Level (§C1.5)")
	assert_eq(int(state["economy"]["coins"]), 50, "Economy.award hat gebucht")
	assert_almost(float(state["progression"]["xp"]), 1.0, 1e-6, "Rest-XP")


func test_apply_glob_ist_fail_closed_bei_refusal() -> void:
	var state := _state()
	var now := 7_000_000
	NougatLogicScript.slice(state)["lastGlobAt"] = now - 60_000
	var result := NougatLogicScript.apply_glob(state, now)
	assert_true(result.is_empty(), "Cooldown → keine Wirkung")
	assert_almost(float(state["gooby"]["stats"]["hunger"]), 40.0, 1e-6, "Stats unberührt")
	assert_true(state["inventory"]["food"].is_empty(), "kein Glas erschlichen")
	assert_false(state["achievements"]["counters"].has("nougatGlobs"), "Zähler unberührt")
