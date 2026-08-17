extends TestCase
## Tortenwerkstatt — Logik-Parität zum Web (MG-3, Batch 3).
## Goldwerte aus `node` auf GOOBY/src/minigames/games/purblePlace.logic.js.

const Logic := preload("res://scripts/minigames/games/purble_place/purble_place_logic.gd")
const Bot := preload("res://scripts/minigames/games/purble_place/purble_place_bot.gd")

const MODES := ["easy", "normal", "hard", "endless"]

## Web: simulateRound(seed, {difficulty}) für Seeds 1..5.
const GOLD_SCORE := {
	"easy": [221, 178, 126, 198, 168],
	"normal": [221, 148, 129, 191, 163],
	"hard": [171, 158, 123, 151, 165],
	"endless": [166, 172, 62, 163, 236],
}
const GOLD_SERVED := {
	"easy": [9, 9, 9, 9, 9],
	"normal": [9, 9, 9, 9, 10],
	"hard": [9, 9, 9, 9, 9],
	"endless": [10, 11, 6, 11, 12],
}
const GOLD_PERFECT := {
	"easy": [5, 3, 3, 4, 5],
	"normal": [5, 2, 3, 3, 5],
	"hard": [3, 3, 3, 2, 4],
	"endless": [3, 3, 2, 2, 5],
}
const GOLD_REJECTED := {
	"easy": [1, 1, 3, 1, 2],
	"normal": [1, 2, 3, 1, 3],
	"hard": [2, 2, 3, 2, 2],
	"endless": [3, 3, 3, 3, 2],
}
const GOLD_EXPIRED := {
	"easy": [0, 0, 0, 0, 0],
	"normal": [0, 0, 0, 0, 0],
	"hard": [0, 0, 0, 0, 0],
	"endless": [0, 0, 0, 0, 1],
}
const GOLD_PERFECT_BAKES := {
	"easy": [6, 6, 6, 7, 6],
	"normal": [6, 7, 7, 8, 6],
	"hard": [7, 9, 7, 9, 6],
	"endless": [7, 10, 4, 10, 8],
}
const GOLD_SPLATS := {
	"easy": [0, 0, 0, 0, 0],
	"normal": [0, 1, 1, 1, 0],
	"hard": [2, 4, 2, 2, 4],
	"endless": [2, 4, 0, 2, 4],
}
const GOLD_TSEC := {
	"easy": [210.033333, 210.033333, 210.033333, 210.033333, 210.033333],
	"normal": [210.033333, 210.033333, 210.033333, 210.033333, 210.033333],
	"hard": [210.033333, 210.033333, 210.033333, 210.033333, 210.033333],
	"endless": [214.333333, 223.8, 143.333333, 226.033333, 258.166667],
}


func _round(mode: String, seed_value: int) -> Dictionary:
	return Logic.simulate_round(seed_value, mode)


## §G1.9-Zertifikat: Bot-Läufe sind zahlengleich zum Web (Seeds 1..5 × 4 Modi).
func test_bot_rounds_match_web_gold() -> void:
	for mode: String in MODES:
		for i in 5:
			var r := _round(mode, i + 1)
			var tag := "%s/seed%d" % [mode, i + 1]
			assert_eq(int(r["score"]), int(GOLD_SCORE[mode][i]), "score %s" % tag)
			assert_eq(int(r["cakesServed"]), int(GOLD_SERVED[mode][i]), "cakesServed %s" % tag)
			assert_eq(int(r["perfectCakes"]), int(GOLD_PERFECT[mode][i]), "perfectCakes %s" % tag)
			assert_eq(int(r["rejected"]), int(GOLD_REJECTED[mode][i]), "rejected %s" % tag)
			assert_eq(int(r["expired"]), int(GOLD_EXPIRED[mode][i]), "expired %s" % tag)
			assert_eq(
				int(r["perfectBakes"]), int(GOLD_PERFECT_BAKES[mode][i]), "perfectBakes %s" % tag
			)
			assert_eq(int(r["splats"]), int(GOLD_SPLATS[mode][i]), "splats %s" % tag)
			assert_eq(int(r["trashed"]), 0, "trashed %s" % tag)
			assert_almost(float(r["tSec"]), float(GOLD_TSEC[mode][i]), 1e-4, "tSec %s" % tag)


## Gleicher Seed → gleicher Lauf (der Bot hat einen eigenen RNG-Strom).
func test_determinism() -> void:
	for mode: String in MODES:
		var a := _round(mode, 7)
		var b := _round(mode, 7)
		assert_eq(a, b, "Wiederholung weicht ab (%s)" % mode)
	assert_ne(_round("normal", 7)["score"], _round("normal", 8)["score"], "Seed ohne Wirkung")


## §G1.6-Monotonie der Schwierigkeitszeilen (Fangfenster/Geduld/Verkohlung).
func test_difficulty_monotone() -> void:
	var easy: Dictionary = Logic.apply_difficulty(Logic.CAKE, "easy")
	var normal: Dictionary = Logic.apply_difficulty(Logic.CAKE, "normal")
	var hard: Dictionary = Logic.apply_difficulty(Logic.CAKE, "hard")
	var endless: Dictionary = Logic.apply_difficulty(Logic.CAKE, "endless")
	assert_true(
		float(easy["CATCH_HALF_M"]) > float(normal["CATCH_HALF_M"]),
		"Leicht muss das großzügigste Fangfenster haben"
	)
	assert_true(
		float(normal["CATCH_HALF_M"]) > float(hard["CATCH_HALF_M"]),
		"Schwer muss enger fangen als Mittel"
	)
	assert_true(
		float(easy["PATIENCE_MULT"]) > float(normal["PATIENCE_MULT"]),
		"Leicht muss geduldigere Gäste haben"
	)
	assert_true(float(normal["PATIENCE_MULT"]) > float(hard["PATIENCE_MULT"]), "Schwer muss hetzen")
	assert_true(float(easy["SINGE_SEC"]) > float(normal["SINGE_SEC"]), "Leicht verkohlt später")
	assert_true(float(normal["SINGE_SEC"]) > float(hard["SINGE_SEC"]), "Schwer verkohlt früher")
	assert_true(
		float(easy["ORDER_INTERVAL_MIN_SEC"]) > float(normal["ORDER_INTERVAL_MIN_SEC"]),
		"Leicht bekommt seltener neue Aufträge"
	)
	assert_true(
		float(hard["ORDER_INTERVAL_MIN_SEC"]) > float(endless["ORDER_INTERVAL_MIN_SEC"]),
		"Endlos muss am dichtesten takten"
	)
	assert_false(bool(normal["ENDLESS"]), "Mittel ist ein Zeitmodus")
	assert_true(bool(endless["ENDLESS"]), "Endlos muss ENDLESS setzen")
	assert_eq(str(Logic.apply_difficulty(Logic.CAKE, "quatsch")["mode"]), "normal")


## Der Bot muss die Werkstatt tatsächlich bedienen (§G1.9-Latte).
func test_bot_plausible() -> void:
	var total := 0
	for i in 8:
		var r := _round("normal", i + 1)
		assert_true(int(r["cakesServed"]) >= 6, "Bot liefert zu wenige Torten (Seed %d)" % (i + 1))
		assert_true(int(r["perfectCakes"]) >= 1, "Bot trifft nie perfekt (Seed %d)" % (i + 1))
		assert_true(int(r["score"]) >= 90, "Bot unter der §G1.9-Latte (Seed %d)" % (i + 1))
		assert_true(int(r["trashed"]) == 0, "Bot wirft Formen weg (Seed %d)" % (i + 1))
		total += int(r["score"])
	assert_true(total / 8 >= 120, "Mittel-Durchschnitt unter dem §G5.4-Ziel")


## Endlos endet an 3 Fehlschlägen — nie am 900-s-Sicherheitsdeckel.
func test_endless_terminates() -> void:
	for i in 6:
		var r := _round("endless", i + 1)
		assert_true(bool(r["over"]), "Endlos endet nicht (Seed %d)" % (i + 1))
		var fails := int(r["rejected"]) + int(r["expired"])
		assert_true(fails >= 3, "Endlos ohne 3 Fehlschläge beendet (Seed %d)" % (i + 1))
		assert_true(float(r["tSec"]) < 900.0, "Endlos läuft in den Deckel (Seed %d)" % (i + 1))


## §C9.4-Punktematrix inkl. Combo-Deckel und Tempobonus-Schwelle.
func test_score_serve_edges() -> void:
	var perfect: Dictionary = Logic.score_serve(0, 0, 1.0)
	assert_eq(int(perfect["points"]), 24)
	assert_eq(int(perfect["base"]), 20)
	assert_eq(int(perfect["speedBonus"]), 4)
	assert_eq(int(perfect["comboAfter"]), 1)
	var capped: Dictionary = Logic.score_serve(0, 9, 0.1)
	assert_eq(int(capped["comboBonus"]), 10, "Combo muss bei +10 deckeln")
	assert_eq(int(capped["points"]), 30)
	assert_eq(int(capped["speedBonus"]), 0, "Unter 50 % Geduld gibt es kein Tempo")
	var one: Dictionary = Logic.score_serve(1, 2, 0.5)
	assert_eq(str(one["outcome"]), "oneWrong")
	assert_eq(int(one["points"]), 16, "Genau 50 % Geduld zählt noch als schnell")
	var bad: Dictionary = Logic.score_serve(3, 5, 1.0)
	assert_eq(str(bad["outcome"]), "rejected")
	assert_eq(int(bad["points"]), -5, "Abgelehnt bekommt weder Combo noch Tempo")
	assert_eq(int(bad["comboAfter"]), 0, "Ablehnung reißt die Combo ab")


## Formeln aus §C9.2/§G1.5/§G1.6 (Goldzeilen aus dem Web).
func test_curves_match_web() -> void:
	assert_almost(Logic.patience_for(0), 45.0)
	assert_almost(Logic.patience_for(5), 37.5)
	assert_almost(Logic.patience_for(10), 30.0)
	assert_almost(Logic.patience_for(20), 30.0, 1e-6, "Geduld muss bei 30 s festhalten")
	assert_almost(Logic.order_interval_at(0), 30.0)
	assert_almost(Logic.order_interval_at(5), 20.0)
	assert_almost(Logic.order_interval_at(10), 14.0)
	assert_almost(Logic.order_interval_at(20), 14.0, 1e-6, "Takt muss bei 14 s festhalten")
	assert_eq(Logic.pan_cap_at(0), 1)
	assert_eq(Logic.pan_cap_at(3), 2)
	assert_eq(Logic.pan_cap_at(6), 3)
	assert_eq(Logic.pan_cap_at(12), 3, "Formen sind bei 3 gedeckelt")
	var want := ["pale", "pale", "perfect", "perfect", "perfect", "over", "singed", "singed"]
	var times := [0.0, 2.2, 2.25, 2.9, 3.0, 3.1, 3.6, 4.0]
	for i in times.size():
		assert_eq(Logic.bake_result_at(float(times[i])), str(want[i]), "bake @%s" % times[i])
	assert_eq(Logic.bake_points("perfect"), 5)
	assert_eq(Logic.bake_points("singed"), -3)
	assert_eq(Logic.bake_points("pale"), 0)
	assert_eq(Logic.bake_points("over"), 0)


## §G1.9-Vorhaltemathematik: 0,45 s Fallzeit × Bandtempo.
func test_drop_impact_and_catch_window() -> void:
	assert_almost(Logic.drop_impact_s(1.0, 0.9), 1.405)
	assert_almost(Logic.drop_impact_s(2.0, -0.7), 1.685)
	assert_almost(Logic.drop_impact_s(3.0, 0.0), 3.0)
	assert_almost(Logic.drop_impact_s(0.0, [{"v": 0.9, "dur": 0.2}, {"v": 0.0}]), 0.18)
	assert_true(Logic.catch_window(1.14, 0.9), "Genau am Rand muss noch fangen")
	assert_false(Logic.catch_window(1.15, 0.9), "Knapp außerhalb darf nicht fangen")
	var hard: Dictionary = Logic.apply_difficulty(Logic.CAKE, "hard")
	assert_true(Logic.catch_window(1.09, 0.9, hard))
	assert_false(Logic.catch_window(1.14, 0.9, hard), "Schwer fängt bei ±0,19 m nicht mehr")


## Gesäter Auftragsgenerator (Goldreihe für Seed 42, serves 0..5).
func test_make_ticket_gold() -> void:
	var rng := GoobyRng.new(42)
	var want := [
		{
			"shape": "square",
			"sponge": "vanilla",
			"icing": "pink",
			"topping": "berries",
			"candles": 2
		},
		{
			"shape": "square",
			"sponge": "chocolate",
			"icing": "chocolate",
			"topping": "cherry",
			"candles": 0
		},
		{
			"shape": "square",
			"sponge": "chocolate",
			"icing": "chocolate",
			"topping": "cherry",
			"candles": 1
		},
		{
			"shape": "square",
			"sponge": "vanilla",
			"icing": "chocolate",
			"topping": "berries",
			"candles": 0
		},
		{
			"shape": "square",
			"sponge": "strawberry",
			"icing": "none",
			"topping": "cherry",
			"candles": 3
		},
		{
			"shape": "heart",
			"sponge": "vanilla",
			"icing": "none",
			"topping": "berries",
			"candles": 2
		},
	]
	for i in want.size():
		assert_eq(Logic.make_ticket(rng, i), want[i], "Auftrag %d" % i)


## Fehlerzählung + Bestpassung eines Auftrags.
func test_wrong_count_and_best_ticket() -> void:
	var spec := {
		"shape": "round", "sponge": "vanilla", "icing": "pink", "topping": "cherry", "candles": 2
	}
	var cake := {
		"shape": "round",
		"sponge": "vanilla",
		"icing": "pink",
		"topping": "cherry",
		"candles": 2,
		"bake": "perfect",
	}
	assert_eq(Logic.wrong_count(cake, spec), 0)
	var singed := cake.duplicate()
	singed["bake"] = "singed"
	assert_eq(Logic.wrong_count(singed, spec), 1, "Verkohlt zählt als ein Fehler")
	var bare := {
		"shape": "heart",
		"sponge": null,
		"icing": null,
		"topping": null,
		"candles": 0,
		"bake": "singed",
	}
	assert_eq(Logic.wrong_count(bare, spec), 6, "Leere Torte = alle sechs Merkmale falsch")
	var tickets: Array[Dictionary] = [{"spec": spec}, {"spec": bare.duplicate()}]
	assert_eq(Logic.best_ticket_index(cake, tickets), 0)
	assert_eq(Logic.serve_outcome(0), "perfect")
	assert_eq(Logic.serve_outcome(1), "oneWrong")
	assert_eq(Logic.serve_outcome(2), "rejected")


## Bandrampe (6 m/s²) — geschlossenes Trapezprofil.
func test_belt_advance() -> void:
	var steady: Dictionary = Logic.belt_advance(0.9, 0.9, 6.0, 1.0)
	assert_almost(float(steady["disp"]), 0.9)
	assert_almost(float(steady["v1"]), 0.9)
	var ramp: Dictionary = Logic.belt_advance(0.0, 0.9, 6.0, 0.1)
	assert_almost(float(ramp["v1"]), 0.6, 1e-6, "0,1 s × 6 m/s² = 0,6 m/s")
	assert_almost(float(ramp["disp"]), 0.03)
	var full: Dictionary = Logic.belt_advance(0.0, 0.9, 6.0, 1.0)
	assert_almost(float(full["v1"]), 0.9)
	assert_almost(float(full["disp"]), 0.0675 + 0.9 * 0.85)
	var brake: Dictionary = Logic.belt_advance(0.9, 0.0, 6.0, 1.0)
	assert_almost(float(brake["v1"]), 0.0)
	assert_almost(float(brake["disp"]), 0.0675)


## Konstanten-Parität: §G1-Bindezahlen und die Stationstabelle.
func test_constant_parity() -> void:
	assert_almost(float(Logic.CAKE["DURATION_SEC"]), 210.0)
	assert_almost(float(Logic.CAKE["BELT_LENGTH_M"]), 6.0)
	assert_almost(float(Logic.CAKE["BELT_FWD_SPEED"]), 0.9)
	assert_almost(float(Logic.CAKE["BELT_REV_SPEED"]), 0.7)
	assert_almost(float(Logic.CAKE["BELT_SLEW"]), 6.0)
	assert_almost(float(Logic.CAKE["FALL_SEC"]), 0.45)
	assert_almost(float(Logic.CAKE["FALL_M"]), 0.55)
	assert_almost(float(Logic.CAKE["CATCH_HALF_M"]), 0.24)
	assert_almost(float(Logic.CAKE["OVEN_START_S"]), 2.25)
	assert_almost(float(Logic.CAKE["OVEN_END_S"]), 3.15)
	assert_almost(float(Logic.CAKE["SHIP_S"]), 5.95)
	assert_almost(float(Logic.CAKE["SHIP_HALF_M"]), 0.3)
	assert_eq(int(Logic.CAKE["MAX_TICKETS"]), 3)
	assert_eq(int(Logic.CAKE["MAX_CANDLES"]), 4)
	assert_eq(int(Logic.CAKE["PERFECT_PTS"]), 20)
	assert_eq(int(Logic.CAKE["ENDLESS_FAIL_COUNT"]), 3)
	assert_eq(Logic.SHAPES.size(), 3)
	assert_eq(Logic.STATIONS.size(), 14)
	var drops := 0
	for row: Dictionary in Logic.STATIONS:
		if bool(row["drop"]):
			drops += 1
		assert_true(
			float(row["s"]) >= 0.0 and float(row["s"]) <= float(Logic.CAKE["BELT_LENGTH_M"]),
			"Station %s liegt außerhalb des Bandes" % row["id"]
		)
	assert_eq(drops, 10, "10 physische Düsen (3 Teig, 3 Guss, 3 Deko, Kerzen)")
	assert_almost(float(Logic.station("versand")["s"]), float(Logic.CAKE["SHIP_S"]))
	assert_true(Logic.station("gibtsnicht").is_empty())


## Bandschritt von Hand: fangen, backen, versenden — ohne Bot.
func test_step_line_manual_flow() -> void:
	var line: Dictionary = Logic.create_line(GoobyRng.new(3), "normal")
	assert_eq(int(line["score"]), 0)
	assert_true(bool(Logic.can_spawn(line)["ok"]))
	Logic.step_line(line, 1.0 / 30.0, {"spawnShape": "round"})
	assert_eq((line["pans"] as Array).size(), 1)
	var pan: Dictionary = (line["pans"] as Array)[0]
	assert_eq(
		str(Logic.can_spawn(line)["reason"]), "cap", "Bei 0 Auslieferungen ist 1 Form Schluss"
	)
	# Ab 3 Auslieferungen wären 2 Formen erlaubt — dann greift der Abstandsgrund.
	line["serves"] = 3
	assert_eq(str(Logic.can_spawn(line)["reason"]), "blocked", "Frisch gesetzt blockiert den Spawn")
	line["serves"] = 0

	# Zur Vanille-Düse (0,9 m) fahren, dort stehend drücken.
	var guard := 0
	while float(pan["s"]) < 0.9 - 0.01 and guard < 600:
		Logic.step_line(line, 1.0 / 30.0, {"belt": 1})
		guard += 1
	while absf(float(line["beltV"])) > 0.001 and guard < 600:
		Logic.step_line(line, 1.0 / 30.0, {})
		guard += 1
	Logic.step_line(line, 1.0 / 30.0, {"press": "teig.vanilla"})
	for i in 20:
		Logic.step_line(line, 1.0 / 30.0, {})
	assert_eq(str(pan["sponge"]), "vanilla", "Der Tropfen muss die stehende Form treffen")

	# Danebenschießen erzeugt einen Klecks mit −2.
	var before := int(line["score"])
	Logic.step_line(line, 1.0 / 30.0, {"press": "deko.berries"})
	for i in 20:
		Logic.step_line(line, 1.0 / 30.0, {})
	assert_eq(int(line["score"]), maxi(0, before - 2), "Danebenschießen kostet 2")
	assert_eq(int(line["splatCount"]), 1)


## Müll: rückwärts über die Spawn-Marke hinaus wirft die Form weg.
func test_trash_and_spawn_cap() -> void:
	var line: Dictionary = Logic.create_line(GoobyRng.new(5), "normal")
	Logic.step_line(line, 1.0 / 30.0, {"spawnShape": "square"})
	var guard := 0
	while (line["pans"] as Array).size() > 0 and guard < 600:
		Logic.step_line(line, 1.0 / 30.0, {"belt": -1})
		guard += 1
	assert_eq(int(line["trashed"]), 1, "Rückwärts über 0 m muss die Form entsorgen")
	assert_true(bool(Logic.can_spawn(line)["ok"]), "Nach dem Müll ist wieder Platz")


## Der Bot liefert immer ein wohlgeformtes Eingabepaket.
func test_bot_input_shape() -> void:
	var line: Dictionary = Logic.create_line(GoobyRng.new(11), "normal")
	var bot: RefCounted = Bot.new(GoobyRng.new(99))
	for i in 900:
		var input: Dictionary = bot.plan(line, 1.0 / 30.0)
		assert_true(int(input["belt"]) >= -1 and int(input["belt"]) <= 1, "belt außerhalb −1..1")
		var press := str(input["press"])
		if not press.is_empty():
			assert_false(Logic.station(press).is_empty(), "Bot drückt Station '%s'" % press)
		var shape := str(input["spawnShape"])
		if not shape.is_empty():
			assert_true(Logic.SHAPES.has(shape), "Bot spawnt Form '%s'" % shape)
		Logic.step_line(line, 1.0 / 30.0, input)
	assert_true(int(line["cakesServed"]) > 0, "30 s Bot ohne Auslieferung")
