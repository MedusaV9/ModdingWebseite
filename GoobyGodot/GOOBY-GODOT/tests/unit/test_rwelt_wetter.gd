extends TestCase
## RW-1 — Wetter-Determinismus + Übergänge: der Tagesplan entsteht aus
## Datum + Seed (offline-first, gerätunabhängig), Übergänge sind weich,
## Nässe baut sich auf und trocknet, der Regenbogen kommt abends nach
## Regen. PURE — kein Renderer nötig.

const SEED := 20260726
const DATUM := "2026-07-26"


func test_tagesplan_ist_deterministisch() -> void:
	var a := RanchWetter.tagesplan(DATUM, SEED)
	var b := RanchWetter.tagesplan(DATUM, SEED)
	assert_eq(a, b, "gleiches Datum + Seed = gleicher Plan")
	var c := RanchWetter.tagesplan("2026-07-27", SEED)
	assert_ne(str(a), str(c), "anderes Datum = anderer Plan")
	var d := RanchWetter.tagesplan(DATUM, SEED + 1)
	assert_ne(str(a), str(d), "anderer Seed = anderer Plan")


func test_tagesplan_deckt_24_stunden_ohne_luecken() -> void:
	var plan := RanchWetter.tagesplan(DATUM, SEED)
	assert_true(plan.size() >= 4, "mehrere Segmente am Tag")
	assert_almost(float(plan[0]["von"]), 0.0, 0.001, "beginnt um 0 Uhr")
	assert_almost(float(plan[plan.size() - 1]["bis"]), 24.0, 0.001, "endet um 24 Uhr")
	for i in plan.size() - 1:
		assert_almost(
			float(plan[i]["bis"]), float(plan[i + 1]["von"]), 0.001, "lückenlos bei %d" % i
		)
		assert_ne(plan[i]["typ"], plan[i + 1]["typ"], "nie zweimal derselbe Typ")


func test_alle_wetterlagen_kommen_vor() -> void:
	var gesehen: Array[String] = []
	for tag in 60:
		var datum := "2026-%02d-%02d" % [1 + tag / 28, 1 + tag % 28]
		for segment: Dictionary in RanchWetter.tagesplan(datum, SEED):
			var typ := str(segment["typ"])
			if not gesehen.has(typ):
				gesehen.append(typ)
	for typ: String in RanchWetter.TYPEN:
		assert_true(gesehen.has(typ), "Wetterlage %s kommt vor" % typ)


func test_gewitter_nur_nachmittags_und_nachts_kein_schmetterlingswetter() -> void:
	for tag in 40:
		var datum := "2026-06-%02d" % (1 + tag % 28)
		for segment: Dictionary in RanchWetter.tagesplan(datum, SEED + tag):
			if str(segment["typ"]) == "gewitter":
				assert_true(
					float(segment["von"]) >= 13.0 and float(segment["von"]) < 22.0,
					"Gewitter startet %0.1f" % float(segment["von"])
				)


func test_zustand_blend_und_wertebereiche() -> void:
	for stunde_i in 96:
		var zustand := RanchWetter.zustand(DATUM, float(stunde_i) * 0.25, SEED)
		assert_true(RanchWetter.TYPEN.has(str(zustand["typ"])), "gültiger Typ")
		assert_true(float(zustand["blend"]) >= 0.0 and float(zustand["blend"]) <= 1.0, "blend 0..1")
		assert_true(
			float(zustand["bewoelkung"]) >= 0.0 and float(zustand["bewoelkung"]) <= 1.0,
			"bewoelkung 0..1"
		)
		assert_true(float(zustand["naesse"]) >= 0.0 and float(zustand["naesse"]) <= 1.0)
		assert_true(float(zustand["licht_faktor"]) > 0.0, "nie stockfinster am Tag")


func test_uebergaenge_sind_weich() -> void:
	# Bewölkung springt zwischen 2 Minuten-Samples nie um mehr als das,
	# was der 10-Minuten-Blend erlaubt (kein hartes Umschalten).
	var schritt := 2.0 / 60.0
	var vorher := RanchWetter.zustand(DATUM, 0.0, SEED)
	var stunde := schritt
	while stunde < 24.0:
		var jetzt := RanchWetter.zustand(DATUM, stunde, SEED)
		var sprung := absf(float(jetzt["bewoelkung"]) - float(vorher["bewoelkung"]))
		assert_true(sprung <= 0.25, "Sprung %.2f bei %.2f h" % [sprung, stunde])
		vorher = jetzt
		stunde += schritt


func test_naesse_baut_sich_auf_und_trocknet() -> void:
	var plan: Array[Dictionary] = [
		{"typ": "sonne", "von": 0.0, "bis": 10.0, "intensitaet": 1.0, "wind": 0.2},
		{"typ": "regen", "von": 10.0, "bis": 12.0, "intensitaet": 1.0, "wind": 0.5},
		{"typ": "sonne", "von": 12.0, "bis": 24.0, "intensitaet": 1.0, "wind": 0.2},
	]
	assert_almost(RanchWetter.naesse(plan, 9.5), 0.0, 0.001, "trocken vor dem Regen")
	assert_true(RanchWetter.naesse(plan, 10.1) > 0.2, "wird nass")
	assert_almost(RanchWetter.naesse(plan, 11.0), 1.0, 0.001, "klatschnass im Regen")
	var kurz_danach := RanchWetter.naesse(plan, 12.5)
	var spaeter := RanchWetter.naesse(plan, 13.5)
	assert_true(kurz_danach > spaeter, "trocknet ab")
	assert_almost(RanchWetter.naesse(plan, 15.0), 0.0, 0.001, "nach 2 h wieder trocken")


func test_regenbogen_abends_nach_regen() -> void:
	assert_true(RanchWetter.ist_regenbogen("sonne", 0.5, 18.0), "abends + nass + klar")
	assert_false(RanchWetter.ist_regenbogen("regen", 0.9, 18.0), "nicht IM Regen")
	assert_false(RanchWetter.ist_regenbogen("sonne", 0.5, 11.0), "nicht mittags")
	assert_false(RanchWetter.ist_regenbogen("sonne", 0.0, 18.0), "nicht ohne Nässe")


func test_boe_ist_stetig_und_positiv() -> void:
	for i in 40:
		var wert := RanchWetter.boe(float(i) * 0.35, 0.8)
		assert_true(wert >= 0.0 and wert <= 1.3, "Böe im Rahmen (%.2f)" % wert)
	assert_almost(RanchWetter.boe(3.0, 0.0), 0.0, 0.001, "windstill = keine Böe")
