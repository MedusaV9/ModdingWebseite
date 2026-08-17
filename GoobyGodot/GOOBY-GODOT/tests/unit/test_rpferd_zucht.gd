extends TestCase
## RW-2 — Zucht & Fohlen (RanchHorseBreeding, IDEAS-3 Kap. 4): Zucht-Gates,
## Traechtigkeit als 48-h-Wartequest mit Fuersorge-Checkpoints, Geburt +
## Ruhezeit, Vererbung STATISTISCH ueber 10k Wuerfe (Stat-Wuerfel,
## Abzeichen-Chancen, Rassensprung, Glitzer-Rezessiv) und die 4
## sichtbaren Fohlen-Phasen.

const Zucht := preload("res://scripts/ranch/gameplay/horse_breeding.gd")

const STUNDE_MS := 3_600_000
const TAG_MS := 86_400_000


func test_zucht_gates_liefern_alle_fehler_ids() -> void:
	var stute := _elter("stute", 8, 50.0)
	var hengst := _elter("hengst", 8, 50.0)
	var leer := {"traechtigkeiten": {}, "ruhezeitBis": {}}
	assert_true(bool(Zucht.zucht_erlaubt("s1", stute, hengst, 80.0, leer, 0)["ok"]))
	var jung := _elter("stute", 7, 50.0)
	assert_eq(str(Zucht.zucht_erlaubt("s1", jung, hengst, 80.0, leer, 0)["fehler"]), "level")
	var fremd := _elter("stute", 8, 44.0)
	assert_eq(str(Zucht.zucht_erlaubt("s1", fremd, hengst, 80.0, leer, 0)["fehler"]), "bindung")
	assert_eq(str(Zucht.zucht_erlaubt("s1", stute, hengst, 59.0, leer, 0)["fehler"]), "laune")
	var ruhe := {"traechtigkeiten": {}, "ruhezeitBis": {"s1": 99}}
	assert_eq(str(Zucht.zucht_erlaubt("s1", stute, hengst, 80.0, ruhe, 50)["fehler"]), "ruhezeit")
	var selbst := {"traechtigkeiten": {"s1": {}}, "ruhezeitBis": {}}
	assert_eq(str(Zucht.zucht_erlaubt("s1", stute, hengst, 80.0, selbst, 0)["fehler"]), "traechtig")
	var voll := {"traechtigkeiten": {"a": {}, "b": {}}, "ruhezeitBis": {}}
	assert_eq(str(Zucht.zucht_erlaubt("s1", stute, hengst, 80.0, voll, 0)["fehler"]), "voll")


func test_checkpoints_verkuerzen_und_schaden_nie() -> void:
	var z := Zucht.traechtigkeit_starten({}, "s1", _elter("hengst", 9, 60.0), 0, 7)
	var eintrag: Dictionary = z["traechtigkeiten"]["s1"]
	assert_eq(Zucht.checkpoint_faellig(eintrag, 0), 0, "Checkpoint 0 sofort offen")
	var r1: Dictionary = Zucht.checkpoint_pflegen(z, "s1", 0)
	assert_true(bool(r1["ok"]))
	z = r1["zucht"]
	assert_false(bool(Zucht.checkpoint_pflegen(z, "s1", 100)["ok"]), "kein Doppel-Checkpoint")
	# Checkpoints 1+2 VERPASSEN, erst bei Slot 3 wieder pflegen: kein Malus.
	var slot3_ms := 3 * Zucht.CHECKPOINT_INTERVALL_MS + 1
	assert_eq(Zucht.checkpoint_faellig(z["traechtigkeiten"]["s1"], slot3_ms), 3)
	var r2: Dictionary = Zucht.checkpoint_pflegen(z, "s1", slot3_ms)
	assert_true(bool(r2["ok"]))
	z = r2["zucht"]
	assert_eq(int(z["traechtigkeiten"]["s1"]["checkpoints"]), 2, "2 erledigt, 2 verpasst = ok")
	assert_eq(Zucht.dauer_ms(0), 48 * STUNDE_MS)
	assert_eq(Zucht.dauer_ms(2), 44 * STUNDE_MS)
	assert_eq(Zucht.dauer_ms(5), 38 * STUNDE_MS, "alle 5 Checkpoints = minimal 38 h")
	assert_eq(Zucht.dauer_ms(99), 38 * STUNDE_MS, "Bonus gedeckelt")


func test_geburt_beendet_und_setzt_ruhezeit() -> void:
	var mutter := _elter("stute", 9, 60.0)
	var vater := _elter("hengst", 9, 60.0)
	var z := Zucht.traechtigkeit_starten({}, "s1", vater, 0, 42)
	assert_false(Zucht.geburt_bereit(z, "s1", 47 * STUNDE_MS), "vor 48 h nichts")
	assert_false(bool(Zucht.gebaeren(z, "s1", mutter, 47 * STUNDE_MS)["ok"]))
	var geburt_ms := 48 * STUNDE_MS
	assert_true(Zucht.geburt_bereit(z, "s1", geburt_ms))
	var r: Dictionary = Zucht.gebaeren(z, "s1", mutter, geburt_ms)
	assert_true(bool(r["ok"]))
	var fohlen: Dictionary = r["fohlen"]
	assert_eq(str(fohlen["alter"]), "fohlen")
	assert_eq(int(fohlen["geborenAm"]), geburt_ms)
	assert_eq(str((fohlen["eltern"] as Array)[0]), "s1")
	assert_true(fohlen["ahnen"]["mutter"] is Dictionary and fohlen["ahnen"]["vater"] is Dictionary)
	var z2: Dictionary = r["zucht"]
	assert_false((z2["traechtigkeiten"] as Dictionary).has("s1"), "Traechtigkeit beendet")
	assert_eq(int(z2["ruhezeitBis"]["s1"]), geburt_ms + 5 * TAG_MS, "Ruhezeit 5 Tage")


func test_fohlen_ist_deterministisch() -> void:
	var mutter := _elter("stute", 9, 60.0)
	var vater := _elter("hengst", 9, 60.0)
	var a := Zucht.wuerfle_fohlen(mutter, vater, 1234)
	var b := Zucht.wuerfle_fohlen(mutter, vater, 1234)
	assert_eq(a, b, "gleicher Seed = gleiches Fohlen")
	assert_ne(a, Zucht.wuerfle_fohlen(mutter, vater, 1235), "anderer Seed = anderes Fohlen")


## Kern-DoD: Vererbung statistisch ueber 10.000 Wuerfe (Kap. 4.2).
## Erwartungen: Stat-Wuerfel +0,27 im Mittel, Abzeichen 75/40/5 %,
## Rassensprung 10 % bei Mischlingen, Maehne 40/40/20.
func test_vererbung_statistisch_10k() -> void:
	var mutter := _elter("stute", 9, 60.0)
	mutter["rasse"] = "wolkentraber"
	mutter["abzeichen"] = {
		"blesse": true,
		"stern": false,
		"schnippe": true,
		"socken": [1, 1, 0, 0],
		"maehnenform": "puschel",
	}
	var vater := _elter("hengst", 9, 60.0)
	vater["rasse"] = "puschelhufer"
	vater["abzeichen"] = {
		"blesse": true,
		"stern": false,
		"schnippe": false,
		"socken": [0, 0, 0, 0],
		"maehnenform": "glatt",
	}
	var n := 10_000
	var stat_summe := 0.0
	var blesse := 0
	var stern := 0
	var schnippe := 0
	var rein := 0
	var maehne_puschel := 0
	for i in n:
		var f := Zucht.wuerfle_fohlen(mutter, vater, i)
		for k in RanchRassen.STAT_KEYS:
			stat_summe += float(f["stats"][k])
		var abz: Dictionary = f["abzeichen"]
		blesse += 1 if bool(abz["blesse"]) else 0
		stern += 1 if bool(abz["stern"]) else 0
		schnippe += 1 if bool(abz["schnippe"]) else 0
		maehne_puschel += 1 if str(abz["maehnenform"]) == "puschel" else 0
		if str(f["rasse"]) != Zucht.MISCHLING_RASSE:
			rein += 1
			assert_true(
				str(f["rasse"]) == "wolkentraber" or str(f["rasse"]) == "puschelhufer",
				"Rassensprung schlaegt nach einem Elternteil"
			)
		else:
			assert_true((f["mixEigenheiten"] as Array).size() >= 1, "Mix erbt Eigenheiten")
	var stat_mittel := stat_summe / float(n * RanchRassen.STAT_KEYS.size())
	assert_almost(stat_mittel, 10.27, 0.05, "Stat-Wuerfel: Erwartungswert +0,27 auf Mittel 10")
	assert_almost(float(blesse) / n, 0.75, 0.02, "beide Eltern Blesse -> 75 %")
	assert_almost(float(stern) / n, 0.05, 0.01, "kein Elter Stern -> 5 %")
	assert_almost(float(schnippe) / n, 0.40, 0.02, "ein Elter Schnippe -> 40 %")
	assert_almost(float(rein) / n, 0.10, 0.015, "Rassensprung 10 %")
	# Maehne: 40 % Mutter (puschel) + 20 % Ueberraschung / 3 Formen.
	assert_almost(float(maehne_puschel) / n, 0.4 + 0.2 / 3.0, 0.02, "Maehne 40/40/20")


## Gen-Orte statistisch: Glitzer nur rezessiv (gx/gx = 25 % bei zwei
## Traegern), Farb-Dominanz B > F (75 % Braun-Basis bei B/F-Eltern).
func test_gene_statistisch_glitzer_und_dominanz() -> void:
	var mutter := _elter("stute", 9, 60.0)
	mutter["gene"] = {
		"g": ["B", "F"], "h": ["h0", "h0"], "s": ["s0", "s0"], "glitzer": ["g0", "gx"]
	}
	var vater := _elter("hengst", 9, 60.0)
	vater["gene"] = mutter["gene"].duplicate(true)
	var n := 10_000
	var funkelt := 0
	var braun_basis := 0
	for i in n:
		var f := Zucht.wuerfle_fohlen(mutter, vater, 100_000 + i)
		funkelt += 1 if RanchRassen.ist_glitzer(f["gene"]) else 0
		var g: Array = f["gene"]["g"]
		braun_basis += 1 if g.has("B") else 0
	assert_almost(float(funkelt) / n, 0.25, 0.015, "gx/gx aus zwei Traegern = 25 %")
	assert_almost(float(braun_basis) / n, 0.75, 0.015, "mind. ein B aus B/F x B/F = 75 %")


func test_fohlen_phasen_skala_und_reitbarkeit() -> void:
	var geboren := 10 * TAG_MS
	assert_eq(Zucht.alter_fuer(geboren, geboren), "fohlen")
	assert_eq(Zucht.alter_fuer(geboren, geboren + 3 * TAG_MS - 1), "fohlen", "Tage 0-2")
	assert_eq(Zucht.alter_fuer(geboren, geboren + 3 * TAG_MS), "jaehrling", "Tage 3-6")
	assert_eq(Zucht.alter_fuer(geboren, geboren + 7 * TAG_MS - 1), "jaehrling")
	assert_eq(Zucht.alter_fuer(geboren, geboren + 7 * TAG_MS), "jungpferd", "Tage 7-9")
	assert_eq(Zucht.alter_fuer(geboren, geboren + 10 * TAG_MS), "ausgewachsen", "ab Tag 10")
	assert_eq(Zucht.alter_fuer(0, 999), "ausgewachsen", "ohne Geburtsstempel erwachsen")
	assert_almost(Zucht.phasen_skala("fohlen"), 0.55, 1e-6)
	assert_almost(Zucht.phasen_skala("jaehrling"), 0.75, 1e-6)
	assert_almost(Zucht.phasen_skala("jungpferd"), 0.90, 1e-6)
	assert_almost(Zucht.phasen_skala("ausgewachsen"), 1.0, 1e-6)
	assert_false(Zucht.reitbar("fohlen"))
	assert_false(Zucht.reitbar("jaehrling"))
	assert_true(Zucht.reitbar("jungpferd"))
	assert_true(Zucht.reitbar("ausgewachsen"))
	assert_almost(Zucht.bein_bonus("fohlen"), 0.15, 1e-6, "Fohlen-Beine +15 %")
	assert_almost(Zucht.bein_bonus("ausgewachsen"), 0.0, 1e-6)


func test_eltern_snapshot_haelt_drei_generationen_flach() -> void:
	var oma := _elter("oma", 9, 60.0)
	var mutter := _elter("stute", 9, 60.0)
	mutter["ahnen"] = {"mutter": Zucht.eltern_snapshot(oma), "vater": {}}
	(mutter["ahnen"]["mutter"] as Dictionary)["ahnen"] = {"mutter": {"name": "uroma"}}
	var snap := Zucht.eltern_snapshot(mutter)
	assert_eq(str(snap["rasse"]), "puschelhufer")
	assert_true(snap["ahnen"]["mutter"] is Dictionary, "eine Ahnen-Ebene bleibt")
	assert_false((snap["ahnen"]["mutter"] as Dictionary).has("ahnen"), "keine tiefe Rekursion")


func test_erbe_badges_zeigen_wuerfelglueck_und_glitzer() -> void:
	var fohlen := {
		"stats":
		{"tempo": 12, "ausdauer": 10, "sprungkraft": 9, "wendigkeit": 10, "gelassenheit": 10},
		"gene": {"glitzer": ["gx", "gx"]},
		"ahnen":
		{
			"mutter":
			{
				"stats":
				{
					"tempo": 10,
					"ausdauer": 10,
					"sprungkraft": 10,
					"wendigkeit": 10,
					"gelassenheit": 10
				}
			},
			"vater":
			{
				"stats":
				{
					"tempo": 10,
					"ausdauer": 10,
					"sprungkraft": 10,
					"wendigkeit": 10,
					"gelassenheit": 10
				}
			},
		},
	}
	var badges := Zucht.erbe_badges(fohlen)
	assert_true(badges.has("tempo"), "Wuerfel-Glueck ueber Eltern-Mittel = Badge")
	assert_false(badges.has("sprungkraft"), "unter Mittel = kein Badge")
	assert_false(badges.has("ausdauer"), "exakt Mittel = kein Badge")
	assert_true(badges.has("glitzer"), "gx-Traeger = Glitzer-Geheimnis")


func _elter(name: String, level: int, bindung: float) -> Dictionary:
	var stats := {}
	for k in RanchRassen.STAT_KEYS:
		stats[k] = 10
	return {
		"name": name,
		"rasse": "puschelhufer",
		"level": level,
		"bindung": bindung,
		"gene": {"g": ["B", "B"], "h": ["h0", "h0"], "s": ["s0", "s0"], "glitzer": ["g0", "g0"]},
		"stats": stats,
		"abzeichen":
		{
			"blesse": false,
			"stern": false,
			"schnippe": false,
			"socken": [0, 0, 0, 0],
			"maehnenform": "glatt"
		},
		"charakter": ["mutig", "verspielt"],
		"groesse": 1.0,
	}
