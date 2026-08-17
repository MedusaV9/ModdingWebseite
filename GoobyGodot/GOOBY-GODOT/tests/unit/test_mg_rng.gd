extends TestCase
## GoobyRng-Goldwerte — BIT-IDENTISCH zum Web-mulberry32. Die u32-Konstanten
## wurden mit Node aus der Web-Referenz erzeugt (identischer Code wie
## GOOBY/src/minigames/framework.js createRng):
##   node -e 'let a=SEED>>>0; const u=()=>{a|=0;a=(a+0x6d2b79f5)|0;
##     let t=Math.imul(a^(a>>>15),1|a);t=(t+Math.imul(t^(t>>>7),61|t))|0;
##     return (t^(t>>>14))>>>0;};
##     console.log(Array.from({length:10},()=>u()))'
## Der Beweis läuft über die ROHEN uint32-Werte (Ganzzahl-==): Godots
## Dezimal-Literal-/JSON-Parser rundet 17-stellige Float-Literale um bis zu
## 1 ulp anders als Node — die Ganzzahlen sind davon unberührt, und
## next() == u32 / 2^32 ist in IEEE-754 exakt (Beweis im zweiten Test).

const GOLDEN_U32 := {
	1:
	[
		836030678,
		3573139372,
		2406128446,
		3440132465,
		990995412,
		566152158,
		2306088265,
		1507483903,
		4058411412,
		6273008,
	],
	2:
	[
		1166597653,
		376940509,
		115800693,
		1667315164,
		249449276,
		2161099376,
		1846299430,
		297839945,
		3145447259,
		786846407,
	],
	3:
	[
		3697814089,
		1661656721,
		1388217562,
		621193299,
		412574171,
		3917535926,
		2059470754,
		3358741458,
		782768924,
		2102429158,
	],
	42:
	[
		2584728083,
		675079005,
		2044641832,
		3177845137,
		4260166277,
		1707203624,
		2431888439,
		4247398957,
		999558721,
		370696628,
	],
	123456789:
	[
		1993201692,
		396308321,
		610571235,
		338421643,
		1792375622,
		3170114952,
		1150699997,
		2442602125,
		2524629674,
		2672565055,
	],
}


func test_golden_u32_bit_identical() -> void:
	for seed_value: int in GOLDEN_U32:
		var rng := GoobyRng.new(seed_value)
		var want: Array = GOLDEN_U32[seed_value]
		for i in want.size():
			var got := rng.next_u32()
			assert_eq(got, int(want[i]), "seed=%d i=%d" % [seed_value, i])


func test_next_is_exact_u32_division() -> void:
	# next() == next_u32() / 2^32 — exakt, keine Epsilon-Toleranz.
	var a := GoobyRng.new(42)
	var b := GoobyRng.new(42)
	for i in 50:
		var f := a.next()
		var u := b.next_u32()
		assert_true(f == float(u) / 4294967296.0, "i=%d: %.20f != %d/2^32" % [i, f, u])


func test_fixture_file_matches() -> void:
	var fixture: Variant = JsonFixtures.load_json("res://tests/expected/rng.json")
	assert_true(
		fixture is Dictionary, "rng.json fehlt/kaputt — tools/cross_check.mjs laufen lassen"
	)
	if not (fixture is Dictionary):
		return
	var u32_table: Dictionary = fixture.get("u32", {})
	assert_true(u32_table.size() >= 5, "rng.json ohne u32-Sektion — cross_check.mjs aktualisieren")
	for key: String in u32_table:
		var rng := GoobyRng.new(int(key))
		var want: Array = u32_table[key]
		for i in want.size():
			assert_eq(rng.next_u32(), int(want[i]), "fixture seed=%s i=%d" % [key, i])


func test_deterministic_and_seed_sensitive() -> void:
	var a := GoobyRng.new(7)
	var b := GoobyRng.new(7)
	var c := GoobyRng.new(8)
	var differs := false
	for _i in 20:
		var va := a.next()
		assert_eq(va, b.next(), "gleicher Seed muss gleiche Folge liefern")
		if va != c.next():
			differs = true
	assert_true(differs, "verschiedene Seeds muessen verschiedene Folgen liefern")
	for _i in 1000:
		var v := a.next()
		assert_true(v >= 0.0 and v < 1.0, "Wertebereich [0,1) verletzt: %f" % v)


func test_range_f_consumes_one_value() -> void:
	var a := GoobyRng.new(5)
	var b := GoobyRng.new(5)
	var lo := 2.0
	var hi := 6.0
	var got := a.range_f(lo, hi)
	var want := lo + b.next() * (hi - lo)
	assert_eq(got, want, "range_f muss genau 1 next() verbrauchen")
