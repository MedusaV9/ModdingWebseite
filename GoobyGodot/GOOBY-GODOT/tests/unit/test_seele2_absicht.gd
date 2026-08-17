extends TestCase
## SEELE-2: Eigenleben mit Absicht (SoulIntent). Kernversprechen: Gooby tut
## Dinge, WEIL er etwas will — die Wahl ist plausibel (dringendstes
## Bedürfnis zuerst), braucht ein SICHTBARES Ziel im Raum, respektiert
## Schlaf und Cooldowns, und Regen ist nur ein leiser Nachgedanke.

const T0 := 1_785_132_000_000


func _fit() -> Dictionary:
	return {"hunger": 90.0, "energy": 90.0, "hygiene": 90.0, "fun": 90.0}


func _alles_da() -> Dictionary:
	return {
		"item:kitchenFridge": true,
		"tuer:kitchen": true,
		"item:bear": true,
		"item:television": true,
		"item:bed": true,
		"tuer:bedroom": true,
		"item:bathtub": true,
		"tuer:bathroom": true,
	}


func test_satt_und_munter_will_nichts() -> void:
	var ctx := {"regen": false, "schlaeft": false, "vorhanden": _alles_da()}
	assert_true(SoulIntent.kandidaten(_fit(), ctx).is_empty(), "ohne Bedürfnis keine Absicht")
	assert_true(SoulIntent.waehle(_fit(), ctx, {}, T0).is_empty())


func test_hunger_geht_zum_kuehlschrank() -> void:
	var stats := _fit()
	stats["hunger"] = 20.0
	var ctx := {"regen": false, "schlaeft": false, "vorhanden": _alles_da()}
	var absicht := SoulIntent.waehle(stats, ctx, {}, T0)
	assert_eq(str(absicht.get("id", "")), "absicht_hunger")
	assert_eq(str(absicht.get("ziel_art", "")), "item")
	assert_eq(str(absicht.get("ziel", "")), "kitchenFridge", "Kühlschrank ist das erste Ziel")


func test_ziel_fallback_auf_kuechentuer() -> void:
	var stats := _fit()
	stats["hunger"] = 20.0
	var vorhanden := _alles_da()
	vorhanden["item:kitchenFridge"] = false
	var ctx := {"regen": false, "schlaeft": false, "vorhanden": vorhanden}
	var absicht := SoulIntent.waehle(stats, ctx, {}, T0)
	assert_eq(str(absicht.get("ziel_art", "")), "tuer", "ohne Kühlschrank → Küchentür")
	assert_eq(str(absicht.get("ziel", "")), "kitchen")


func test_ohne_aufloesbares_ziel_keine_absicht() -> void:
	var stats := _fit()
	stats["hunger"] = 20.0
	var ctx := {"regen": false, "schlaeft": false, "vorhanden": {}}
	assert_true(
		SoulIntent.waehle(stats, ctx, {}, T0).is_empty(),
		"Wollen ohne sichtbares Wohin wirkt kaputt — also keine Absicht"
	)


func test_dringendstes_beduerfnis_gewinnt() -> void:
	var stats := _fit()
	stats["hunger"] = 30.0  # Drang 5
	stats["fun"] = 5.0  # Drang 25
	var ctx := {"regen": false, "schlaeft": false, "vorhanden": _alles_da()}
	var kandidaten := SoulIntent.kandidaten(stats, ctx)
	assert_eq(str(kandidaten[0]["id"]), "absicht_langeweile", "größter Drang zuerst")
	assert_eq(str(SoulIntent.waehle(stats, ctx, {}, T0).get("id", "")), "absicht_langeweile")


func test_cooldown_laesst_naechste_absicht_dran() -> void:
	var stats := _fit()
	stats["hunger"] = 10.0
	stats["fun"] = 15.0
	var ctx := {"regen": false, "schlaeft": false, "vorhanden": _alles_da()}
	var cooldowns := {"absicht_hunger": T0 + SoulIntent.COOLDOWN_MS}
	var absicht := SoulIntent.waehle(stats, ctx, cooldowns, T0)
	assert_eq(str(absicht.get("id", "")), "absicht_langeweile", "Hunger im Cooldown → nächste")
	var spaeter := SoulIntent.waehle(stats, ctx, cooldowns, T0 + SoulIntent.COOLDOWN_MS)
	assert_eq(str(spaeter.get("id", "")), "absicht_hunger", "nach Ablauf wieder Hunger")


func test_schlaf_hat_keine_absichten() -> void:
	var stats := _fit()
	stats["hunger"] = 5.0
	var ctx := {"regen": false, "schlaeft": true, "vorhanden": _alles_da()}
	assert_true(SoulIntent.kandidaten(stats, ctx).is_empty(), "Schlafende wollen nichts")


func test_regen_ist_leiser_nachgedanke() -> void:
	var ctx := {"regen": true, "schlaeft": false, "vorhanden": _alles_da()}
	var ohne_not := SoulIntent.waehle(_fit(), ctx, {}, T0)
	assert_eq(str(ohne_not.get("id", "")), "absicht_regen", "Regen + keine Not → Fensterplatz")
	assert_eq(str(ohne_not.get("ziel_art", "")), "fenster")
	var stats := _fit()
	stats["hunger"] = 20.0
	var mit_not := SoulIntent.waehle(stats, ctx, {}, T0)
	assert_eq(str(mit_not.get("id", "")), "absicht_hunger", "echte Not schlägt Regen-Romantik")
	var trocken := {"regen": false, "schlaeft": false, "vorhanden": _alles_da()}
	assert_true(SoulIntent.waehle(_fit(), trocken, {}, T0).is_empty(), "ohne Regen kein Fenster")


func test_schwellen_liegen_vor_der_warnstufe() -> void:
	# Absichten sollen VOR den "low"-Alarmen (25) sichtbar werden —
	# Vorahnung statt Sirene (Hunger/Spaß/Hygiene; Energie hat den
	# Schlafdruck vom Pflege-System und bleibt bewusst darunter).
	assert_true(SoulIntent.SCHWELLE_HUNGER > 25.0)
	assert_true(SoulIntent.SCHWELLE_SPASS > 25.0)
	assert_true(SoulIntent.SCHWELLE_HYGIENE > 25.0)


func test_content_defs_fuer_alle_absichten_vorhanden() -> void:
	# Jede wählbare Absicht braucht ihr Def im Content-Pack (Text/Emotion),
	# sonst läuft Gooby stumm los und der Moment wirkt kaputt.
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/soul/data/soul.json")
	)
	var defs: Array = parsed.get("items", [])
	for absicht_id: String in SoulIntent.ZIELE.keys():
		var def := SoulService.def_by_id(defs, absicht_id)
		assert_false(def.is_empty(), "Def fehlt: %s" % absicht_id)
		if not def.is_empty():
			assert_eq(str(def.get("kind", "")), "absicht", "kind=absicht für %s" % absicht_id)
			assert_false(
				(def.get("text_keys", []) as Array).is_empty(),
				"Absicht %s braucht mindestens eine Zeile" % absicht_id
			)
