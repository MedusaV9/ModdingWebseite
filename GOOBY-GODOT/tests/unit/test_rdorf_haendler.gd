extends TestCase
## RW-4 — DorfHaendler (Pferdehändlerin Hufingen): Tages-Rotation ist
## DETERMINISTISCH (gleicher Tag = gleiches Angebot), Kauf/Verkauf sind
## ATOMAR, Kapazität und Letztes-Pferd-Regel halten.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _dir_seq := 0


func _fresh_gs(coins: int) -> Node:
	RanchState.register_slice()
	_dir_seq += 1
	var dir := "user://rdorf_tests/haendler_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("economy.coins", coins)
	return gs


func _teardown_gs(gs: Node) -> void:
	gs.free()
	SaveSchema.unregister_slice(RanchState.SLICE_ID)
	RanchState.reset_for_tests()


func _pool() -> Array:
	return DorfKatalog.pferde_pool(DorfKatalog.load_balance())


func test_rotation_ist_deterministisch() -> void:
	var pool := _pool()
	var a := DorfHaendler.tages_angebot("2026-07-26", pool, 3)
	var b := DorfHaendler.tages_angebot("2026-07-26", pool, 3)
	assert_eq(a.size(), 3)
	for i in a.size():
		assert_eq(a[i]["id"], b[i]["id"], "gleicher Tag = gleiches Angebot")


func test_rotation_wechselt_und_jedes_pferd_kehrt_wieder() -> void:
	var pool := _pool()
	var gesehen := {}
	var verschieden := false
	var erster: Array = DorfHaendler.tages_angebot("2026-07-01", pool, 3)
	for tag_nr in range(1, 31):
		var tag := "2026-07-%02d" % tag_nr
		var angebot := DorfHaendler.tages_angebot(tag, pool, 3)
		assert_eq(angebot.size(), 3, "%s: immer volle Auslage" % tag)
		var ids := {}
		for eintrag: Dictionary in angebot:
			gesehen[str(eintrag["id"])] = true
			ids[str(eintrag["id"])] = true
		assert_eq(ids.size(), 3, "%s: keine Doppelten am selben Tag" % tag)
		if str(angebot[0]["id"]) != str(erster[0]["id"]):
			verschieden = true
	assert_true(verschieden, "über den Monat wechselt das Angebot")
	assert_eq(gesehen.size(), pool.size(), "JEDES Pool-Pferd taucht im Monat auf (kein FOMO)")


func test_kauf_bucht_atomar_und_sperrt_fuer_heute() -> void:
	var gs := _fresh_gs(5000)
	var angebot := DorfHaendler.angebot(gs)
	assert_true(angebot.size() >= 1, "Angebot da")
	var ziel: Dictionary = angebot[0]
	var res := DorfHaendler.pferd_kaufen(gs, str(ziel["id"]))
	assert_true(bool(res["ok"]))
	assert_eq(res["preis"], int(ziel["preis"]))
	assert_eq(gs.get_value("economy.coins"), 5000 - int(ziel["preis"]), "exakt abgebucht")
	var pferde: Dictionary = gs.get_value("ranch.tiere.pferde")
	assert_true(pferde.has(str(ziel["id"])), "Pferd zieht in RANCH-2s Bestand ein")
	var pferd: Dictionary = pferde[str(ziel["id"])]
	assert_eq(pferd["kaufpreis"], int(ziel["preis"]), "Kaufpreis reist mit (Wiederverkauf)")
	assert_true(pferd["werte"] is Dictionary, "Pflege-Struktur über neues_pferd")
	assert_eq(int(RanchDorfState.lese(gs)["pferdeGekauft"]), 1)
	# Dasselbe Pferd ist heute raus aus dem Angebot.
	for eintrag: Dictionary in DorfHaendler.angebot(gs):
		assert_ne(str(eintrag["id"]), str(ziel["id"]), "gekauft = heute nicht mehr im Angebot")
	assert_eq(
		str(DorfHaendler.pferd_kaufen(gs, str(ziel["id"]))["fehler"]),
		DorfHaendler.FEHLER_NICHT_IM_ANGEBOT
	)
	_teardown_gs(gs)


func test_zu_teuer_aendert_nichts() -> void:
	var gs := _fresh_gs(1)
	var angebot := DorfHaendler.angebot(gs)
	var ziel: Dictionary = angebot[0]
	var res := DorfHaendler.pferd_kaufen(gs, str(ziel["id"]))
	assert_false(bool(res["ok"]))
	assert_eq(str(res["fehler"]), DorfHaendler.FEHLER_ZU_TEUER)
	assert_eq(gs.get_value("economy.coins"), 1, "Münzen unangetastet")
	assert_eq(gs.get_value("ranch.tiere.pferde"), {}, "kein Pferd eingezogen")
	assert_eq(int(RanchDorfState.lese(gs)["pferdeGekauft"]), 0)
	_teardown_gs(gs)


func test_stall_voll_blockt_den_kauf() -> void:
	var gs := _fresh_gs(99999)
	(
		gs
		. set_value(
			"ranch.tiere.pferde",
			{
				"p1": RanchPlaySlices.neues_pferd("Eins", "braun"),
				"p2": RanchPlaySlices.neues_pferd("Zwei", "weiss"),
			}
		)
	)
	assert_eq(DorfHaendler.kapazitaet(gs), 2, "Basis-Kapazität ohne Ausbau")
	var angebot := DorfHaendler.angebot(gs)
	var res := DorfHaendler.pferd_kaufen(gs, str(angebot[0]["id"]))
	assert_eq(str(res["fehler"]), DorfHaendler.FEHLER_STALL_VOLL)
	# Grid-Stallboxen Stufe 2 hebt die Kapazität -> Kauf geht.
	gs.set_value("ranch.bau", {"anlagen": {"stallboxen": {"stufe": 2}}})
	assert_eq(DorfHaendler.kapazitaet(gs), 4, "Stallboxen Stufe 2 = 4 Plätze")
	assert_true(bool(DorfHaendler.pferd_kaufen(gs, str(angebot[0]["id"]))["ok"]))
	_teardown_gs(gs)


func test_verkauf_atomar_mit_halbem_kaufpreis() -> void:
	var gs := _fresh_gs(5000)
	var angebot := DorfHaendler.angebot(gs)
	var ziel: Dictionary = angebot[0]
	assert_true(bool(DorfHaendler.pferd_kaufen(gs, str(ziel["id"]))["ok"]))
	# Zweites Pferd, damit das letzte nicht verkauft wird.
	gs.set_value("ranch.tiere.pferde." + "extra", RanchPlaySlices.neues_pferd("Extra", "fuchs"))
	var coins_vorher := int(gs.get_value("economy.coins"))
	var erwartet := int(floor(int(ziel["preis"]) * 0.5))
	assert_eq(DorfHaendler.verkaufspreis(gs, str(ziel["id"])), erwartet)
	var res := DorfHaendler.pferd_verkaufen(gs, str(ziel["id"]))
	assert_true(bool(res["ok"]))
	assert_eq(res["erloes"], erwartet, "50% des Kaufpreises")
	assert_eq(gs.get_value("economy.coins"), coins_vorher + erwartet)
	assert_false((gs.get_value("ranch.tiere.pferde") as Dictionary).has(str(ziel["id"])))
	assert_eq(int(RanchDorfState.lese(gs)["pferdeVerkauft"]), 1)
	_teardown_gs(gs)


func test_letztes_pferd_ist_unverkaeuflich() -> void:
	var gs := _fresh_gs(1000)
	gs.set_value("ranch.tiere.pferde", {"einzig": RanchPlaySlices.neues_pferd("Einzig", "braun")})
	var res := DorfHaendler.pferd_verkaufen(gs, "einzig")
	assert_false(bool(res["ok"]))
	assert_eq(str(res["fehler"]), DorfHaendler.FEHLER_LETZTES_PFERD)
	assert_true((gs.get_value("ranch.tiere.pferde") as Dictionary).has("einzig"))
	_teardown_gs(gs)


func test_verkauf_ohne_kaufpreis_nutzt_basiswert() -> void:
	var gs := _fresh_gs(0)
	(
		gs
		. set_value(
			"ranch.tiere.pferde",
			{
				"start": RanchPlaySlices.neues_pferd("Start", "braun"),
				"zweit": RanchPlaySlices.neues_pferd("Zweit", "weiss"),
			}
		)
	)
	var bal := DorfKatalog.load_balance()
	var erwartet := int(floor(DorfKatalog.basis_wert(bal) * DorfKatalog.verkauf_anteil(bal)))
	assert_eq(DorfHaendler.verkaufspreis(gs, "start"), erwartet, "Basiswert ohne Kaufpreis")
	var res := DorfHaendler.pferd_verkaufen(gs, "start")
	assert_true(bool(res["ok"]))
	assert_eq(gs.get_value("economy.coins"), erwartet)
	_teardown_gs(gs)
