extends TestCase
## SEELE-2: durchgehende Stimmung (SoulMood). Kernversprechen: EINE träge
## Laune, die der Stats-Wahrheit über Stunden folgt (Halbwertszeit), von
## Ereignissen nur gedeckelt gestoßen wird, und deren Verlauf über einen
## simulierten Tag messbar ist. Zeit wird IMMER hereingereicht.

const Stats := preload("res://scripts/logic/stats.gd")

const MS_MIN := 60_000
const MS_H := 3_600_000
const T0 := 1_785_132_000_000


func test_normalize_self_heal() -> void:
	var kaputt := SoulMood.normalize({"wert": "quatsch", "aktualisiertMs": -5})
	assert_almost(float(kaputt["wert"]), SoulMood.DEFAULT_WERT, 1e-6, "kaputter wert → Default")
	assert_eq(int(kaputt["aktualisiertMs"]), 0, "negative Zeit → 0")
	assert_almost(float(SoulMood.normalize(null)["wert"]), SoulMood.DEFAULT_WERT)
	assert_almost(float(SoulMood.normalize({"wert": 400})["wert"]), 100.0, 1e-6, "Klammer oben")
	assert_almost(float(SoulMood.normalize({"wert": -3})["wert"]), 0.0, 1e-6, "Klammer unten")


func test_advance_halbwertszeit() -> void:
	var s := {"wert": 80.0, "aktualisiertMs": T0}
	# Nach genau einer Halbwertszeit liegt der Wert halb zwischen Start und Ziel.
	var nach := SoulMood.advance(s, 20.0, T0 + int(SoulMood.HALBWERT_MIN * MS_MIN))
	assert_almost(float(nach["wert"]), 50.0, 0.01, "Halbwertszeit: 80 → 50 bei Ziel 20")
	# Ohne Zeitfortschritt bewegt sich nichts.
	var still := SoulMood.advance(s, 20.0, T0)
	assert_almost(float(still["wert"]), 80.0, 1e-6, "dt=0 → unverändert")
	# Riesige Lücke (App zu): praktisch konvergiert, aber nie überschossen.
	var lang := SoulMood.advance(s, 20.0, T0 + 48 * MS_H)
	assert_true(float(lang["wert"]) >= 20.0, "nie unter das Ziel schießen")
	assert_true(float(lang["wert"]) < 21.0, "nach 12h+ praktisch am Ziel")


func test_advance_erster_takt_ohne_stempel() -> void:
	# aktualisiertMs=0 (frischer Save): kein Riesen-dt, nur Stempel setzen.
	var nach := SoulMood.advance(SoulMood.default_stimmung(), 10.0, T0)
	assert_almost(float(nach["wert"]), SoulMood.DEFAULT_WERT, 1e-6, "erster Takt springt nicht")
	assert_eq(int(nach["aktualisiertMs"]), T0)


func test_bump_gedeckelt_und_geklammert() -> void:
	var s := {"wert": 50.0, "aktualisiertMs": T0}
	assert_almost(
		float(SoulMood.bump(s, 30.0, T0)["wert"]),
		50.0 + SoulMood.STOSS_MAX,
		1e-6,
		"Stoß ist gedeckelt"
	)
	assert_almost(
		float(SoulMood.bump({"wert": 99.0, "aktualisiertMs": T0}, 8.0, T0)["wert"]), 100.0
	)
	assert_almost(float(SoulMood.bump({"wert": 2.0, "aktualisiertMs": T0}, -8.0, T0)["wert"]), 0.0)


## Der simulierte Tag: Stats verfallen ehrlich (§C1 apply_tick), die
## Stimmung wird stündlich getaktet. Erwartung: sie FÄLLT über den Tag,
## hängt dem Ziel aber träge hinterher (Gedächtnis statt Thermometer).
## Start: Gooby wacht mit der Laune seiner (guten) Morgen-Stats auf.
func test_stimmungsverlauf_ueber_simulierten_tag() -> void:
	var stats := {"hunger": 92.0, "energy": 95.0, "hygiene": 88.0, "fun": 90.0}
	var stimmung := {"wert": SoulMood.ziel(stats), "aktualisiertMs": T0}
	var verlauf: Array[float] = [float(stimmung["wert"])]
	for stunde in range(1, 16):
		var now := T0 + stunde * MS_H
		var heute := Stats.apply_tick(stats, float(stunde) * 60.0)
		var ziel := SoulMood.ziel(heute)
		stimmung = SoulMood.advance(stimmung, ziel, now)
		verlauf.append(float(stimmung["wert"]))
		assert_true(
			float(stimmung["wert"]) >= ziel - 0.01,
			"Trägheit: Wert hängt beim Fallen ÜBER dem Ziel (h=%d)" % stunde
		)
	assert_true(verlauf[0] > 55.0, "morgens gute Laune (start=%f)" % verlauf[0])
	assert_true(
		verlauf[verlauf.size() - 1] < verlauf[0] - 15.0,
		"abends deutlich schlechter (start=%f ende=%f)" % [verlauf[0], verlauf[verlauf.size() - 1]]
	)
	for i in range(1, verlauf.size()):
		assert_true(verlauf[i] <= verlauf[i - 1] + 0.01, "monoton fallend ohne Ereignisse")


func test_ruhe_emotion_ableitung() -> void:
	var fit := {"hunger": 90.0, "energy": 90.0, "hygiene": 90.0, "fun": 90.0}
	assert_eq(SoulMood.ruhe_emotion(85.0, fit), "ecstatic", "Band ecstatic")
	assert_eq(SoulMood.ruhe_emotion(70.0, fit), "happy")
	assert_eq(SoulMood.ruhe_emotion(50.0, fit), "neutral")
	assert_eq(SoulMood.ruhe_emotion(30.0, fit), "angry", "grumpy → Rig-'angry' (Web-Parität)")
	assert_eq(SoulMood.ruhe_emotion(10.0, fit), "sad")
	# statOverride §C1: Erschöpfung schlägt das Band.
	var platt := {"hunger": 90.0, "energy": 10.0, "hygiene": 90.0, "fun": 90.0}
	assert_eq(SoulMood.ruhe_emotion(70.0, platt), "sleepy", "erschöpft → sleepy")
	# Pflege-Vorrang: krank schlägt alles.
	assert_eq(SoulMood.ruhe_emotion(90.0, fit, 1), "sad", "krank → sad")


func test_ausdruck_und_takt_folgen_der_laune() -> void:
	var elend := SoulMood.ausdruck(5.0)
	var mittel := SoulMood.ausdruck(50.0)
	var selig := SoulMood.ausdruck(95.0)
	assert_true(
		float(elend["ohren"]) > float(mittel["ohren"]),
		"Ohren hängen bei Elend mehr als bei Mittelmaß"
	)
	assert_true(float(selig["ohren"]) < 0.0, "beste Laune perkt die Ohren auf")
	assert_true(float(elend["lider"]) > 0.2, "schwere Lider bei Elend")
	assert_almost(float(selig["lider"]), 0.0, 1e-6, "keine schweren Lider bei Seligkeit")
	assert_true(float(elend["energie"]) < float(selig["energie"]), "Energie steigt mit Laune")
	assert_true(
		SoulMood.idle_takt_faktor(5.0) > SoulMood.idle_takt_faktor(95.0),
		"elend = trägerer Idle-Takt"
	)


func test_def_erlaubt_laune_gates() -> void:
	var tanzen := {"id": "idle_tanzen", "mindest_laune": "happy"}
	assert_true(SoulMood.def_erlaubt(tanzen, "ecstatic"))
	assert_true(SoulMood.def_erlaubt(tanzen, "happy"))
	assert_false(SoulMood.def_erlaubt(tanzen, "neutral"), "unter mindest_laune verboten")
	assert_false(SoulMood.def_erlaubt(tanzen, "miserable"))
	var truebsal := {"id": "idle_truebsal", "hoechst_laune": "grumpy"}
	assert_true(SoulMood.def_erlaubt(truebsal, "miserable"))
	assert_false(SoulMood.def_erlaubt(truebsal, "happy"), "über hoechst_laune verboten")
	assert_true(SoulMood.def_erlaubt({"id": "frei"}, "miserable"), "ohne Gate immer erlaubt")


func test_stimme_parameter_folgen_der_laune() -> void:
	var elend := SoulMood.stimme(5.0)
	var selig := SoulMood.stimme(95.0)
	assert_true(float(elend["pitch"]) < float(selig["pitch"]), "elend klingt tiefer")
	assert_true(float(elend["tempo"]) < float(selig["tempo"]), "elend spricht langsamer")
	assert_true(float(elend["laenge"]) < 0.7, "elend ist wortkarg")
	assert_almost(float(selig["laenge"]), 1.0, 1e-6, "selig brabbelt voll")
