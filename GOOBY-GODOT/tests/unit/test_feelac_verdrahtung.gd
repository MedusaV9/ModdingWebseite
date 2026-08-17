extends TestCase
## FEEL-AC: Verdrahtung im SeeleRunner — echte Ereignisse (Füttern,
## Lieblingsessen, Grüße, Ertappt, Rekord, Münz-Fund, Dunkelheit, Kitzeln)
## werden deterministisch zu Gefühls-Buchungen im Soul-Slice. Headless ohne
## Rig: die Entscheidung + Frequenzbremse laufen trotzdem (gebucht wird in
## feelings.je) — die Optik hängt am GoobyFeelings-Layer und ist separat
## getestet (test_feelac_gefuehle_layer).

const GameStateScript := preload("res://scripts/state/game_state.gd")

## 2026-01-15 12:00 UTC (Mittag) und 23:00 UTC (Nacht).
const MITTAG_MS := 1_768_478_400_000
const NACHT_MS := 1_768_518_000_000
## Großzügiger Schritt zwischen Ereignissen (> JE_EMOTION_GAP_MS).
const SCHRITT_MS := 300_000

var _seq := 0


class RoomStub:
	extends Node3D

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


func _fresh_gs(now_ms: int) -> Node:
	_seq += 1
	var dir := "user://feelac_tests/wire_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(now_ms)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	return gs


func _runner(gs: Node, now_ms: int) -> Array:
	var room := RoomStub.new()
	room.gs_ref = gs
	tree.root.add_child(room)
	var runner := GoobyReactions.new()
	runner.name = "GoobyReactions"
	runner.now_ms_override = now_ms
	runner.visuals_enabled = false
	room.add_child(runner)
	runner.setup(room)
	# Erst NACH dem Betreten-Moment starten die Test-Ereignisse (frische Bremse).
	runner.now_ms_override += SCHRITT_MS
	return [room, runner]


func _je(gs: Node) -> Dictionary:
	return SoulState.slice_of(gs)["feelings"]["je"]


func _feelings(gs: Node) -> Dictionary:
	return SoulState.slice_of(gs)["feelings"]


func test_fuettern_freut_und_lieblingsessen_verliebt() -> void:
	var gs := _fresh_gs(MITTAG_MS)
	var paar := _runner(gs, MITTAG_MS)
	var runner: GoobyReactions = paar[1]
	var seele: SeeleRunner = runner._seele
	SoulState.mutate(gs, func(s: Dictionary) -> void: s["foodGiven"] = {"apple": 1})
	seele.stoss(SeeleRunner.STOSS_FUETTERN)
	assert_true(_je(gs).has("freude"), "normales Essen macht Freude")
	assert_false(_je(gs).has("verliebtheit"), "1× gefüttert ist noch keine Liebe")
	runner.now_ms_override += SCHRITT_MS
	SoulState.mutate(gs, func(s: Dictionary) -> void: s["foodGiven"] = {"apple": 3})
	seele.stoss(SeeleRunner.STOSS_FUETTERN)
	assert_true(_je(gs).has("verliebtheit"), "Lieblingsessen (3×, meistgegeben) macht verliebt")
	paar[0].free()
	gs.free()


func test_gruesse_und_kitzeln_werden_gefuehle() -> void:
	var gs := _fresh_gs(MITTAG_MS)
	var paar := _runner(gs, MITTAG_MS)
	var runner: GoobyReactions = paar[1]
	var seele: SeeleRunner = runner._seele
	seele.stoss_gruss("gruss_vermisst")
	assert_true(_je(gs).has("begeisterung"), "Wiedersehen nach langer Zeit begeistert")
	runner.now_ms_override += SCHRITT_MS
	seele.stoss(SeeleRunner.STOSS_KITZELN)
	assert_true(_je(gs).has("begeisterung"), "Kitzeln begeistert")
	runner.now_ms_override += SCHRITT_MS
	seele.stoss_gruss("gruss_eingeschnappt")
	assert_true(_je(gs).has("trotz"), "Eingeschnappt = Trotz")
	paar[0].free()
	gs.free()


func test_ertappt_nur_waehrend_einer_absicht() -> void:
	var gs := _fresh_gs(MITTAG_MS)
	var paar := _runner(gs, MITTAG_MS)
	var runner: GoobyReactions = paar[1]
	var seele: SeeleRunner = runner._seele
	seele.aufmerken()
	assert_false(_je(gs).has("verlegenheit"), "ohne Absicht kein Ertappt")
	seele._intent_bis_ms = runner.now_ms_override + SeeleRunner.ERTAPPT_FENSTER_MS
	seele.aufmerken()
	assert_true(_je(gs).has("verlegenheit"), "mitten in der Absicht angetippt = verlegen")
	paar[0].free()
	gs.free()


func test_rekord_macht_stolz_aber_nur_einmal() -> void:
	var gs := _fresh_gs(MITTAG_MS)
	var paar := _runner(gs, MITTAG_MS)
	var runner: GoobyReactions = paar[1]
	var seele: SeeleRunner = runner._seele
	gs.update(func(s: Dictionary) -> void: s["minigames"] = {"legacy": {"best": {"gap": 42}}})
	seele._feel_beobachte()
	assert_true(_je(gs).has("stolz"), "neuer Rekord macht stolz")
	assert_eq(int(_feelings(gs)["bestMax"]), 42, "Bestwert gemerkt")
	var buchungen := int(_feelings(gs)["count"])
	runner.now_ms_override += SCHRITT_MS
	seele._feel_beobachte()
	assert_eq(int(_feelings(gs)["count"]), buchungen, "derselbe Rekord feuert nicht doppelt")
	paar[0].free()
	gs.free()


func test_muenzfund_ueberrascht() -> void:
	var gs := _fresh_gs(MITTAG_MS)
	var paar := _runner(gs, MITTAG_MS)
	var runner: GoobyReactions = paar[1]
	var seele: SeeleRunner = runner._seele
	gs.update(
		func(s: Dictionary) -> void:
			var econ: Dictionary = s.get("economy", {})
			econ["coins"] = int(econ.get("coins", 0)) + 5
	)
	seele._feel_beobachte()
	assert_true(_je(gs).has("ueberraschung"), "Münz-Zuwachs überrascht")
	paar[0].free()
	gs.free()


func test_dunkelheit_aengstigt_nachts_und_mittags_nicht() -> void:
	var mittag_gs := _fresh_gs(MITTAG_MS)
	var mittag := _runner(mittag_gs, MITTAG_MS)
	(mittag[1] as GoobyReactions)._seele._feel_beobachte()
	assert_false(_je(mittag_gs).has("angst"), "mittags keine Dunkel-Angst")
	mittag[0].free()
	mittag_gs.free()
	var nacht_gs := _fresh_gs(NACHT_MS)
	var nacht := _runner(nacht_gs, NACHT_MS)
	(nacht[1] as GoobyReactions)._seele._feel_beobachte()
	assert_true(_je(nacht_gs).has("angst"), "nachts wird es Gooby mulmig")
	nacht[0].free()
	nacht_gs.free()


func test_bremse_wirkt_auch_im_runner() -> void:
	var gs := _fresh_gs(MITTAG_MS)
	var paar := _runner(gs, MITTAG_MS)
	var runner: GoobyReactions = paar[1]
	var seele: SeeleRunner = runner._seele
	assert_eq(seele.melde_gefuehl("fund"), "ueberraschung", "erstes Gefühl läuft")
	assert_eq(seele.melde_gefuehl("ertappt"), "", "direkt danach: Mindestabstand bremst")
	assert_eq(seele.melde_gefuehl("donner"), "schreck", "starkes Ereignis überstimmt")
	runner.now_ms_override += SCHRITT_MS
	assert_eq(seele.melde_gefuehl("ertappt"), "verlegenheit", "nach dem Abstand wieder frei")
	paar[0].free()
	gs.free()


func test_unbekanntes_ereignis_bleibt_stumm() -> void:
	var gs := _fresh_gs(MITTAG_MS)
	var paar := _runner(gs, MITTAG_MS)
	var seele: SeeleRunner = (paar[1] as GoobyReactions)._seele
	assert_eq(seele.melde_gefuehl("quatsch"), "", "unbekannte Ereignisse tun nichts")
	paar[0].free()
	gs.free()
