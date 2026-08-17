extends TestCase
## W3d — Bad-Suite: pure Timer-Logik (Klo-Bedürfnis, Duschvorhang-Peek,
## Bürsten-Bruch), Slice-Selbstheilung und der GameState-Glue der
## Bad-Interactables. Plus bad.*-String-Parität.

const GameStateScript := preload("res://scripts/state/game_state.gd")

const NOW_MS := 1768478400000
const HOUR_MS := 3_600_000
const BAD_KEYS := [
	"bad.lampe.titel",
	"bad.lampe.umlegen",
	"bad.lampe.komme",
	"bad.lampe.klick",
	"bad.dusche.start",
	"bad.dusche.fertig",
	"bad.dusche.peek1",
	"bad.dusche.peek2",
	"bad.dusche.peek3",
	"bad.klo.gang",
	"bad.klo.fertig",
	"bad.spiegel.titel",
	"bad.spiegel.augenabstand",
	"bad.spiegel.augengroesse",
	"bad.spiegel.ohrlaenge",
	"bad.spiegel.pausbacken",
	"bad.zahnputz.warte",
	"bad.zahnputz.rubbel",
	"bad.zahnputz.fertig",
	"bad.zahnputz.bruch",
]

var _dir_seq := 0


func _fresh_gs() -> Node:
	BadState.register_slice()
	_dir_seq += 1
	var dir := "user://w3d_tests/bad_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	return gs


func test_klo_timer_pure() -> void:
	assert_almost(BadState.klo_need01(0, NOW_MS), 0.0, 1e-9, "nie gewesen = kein Drang")
	assert_almost(BadState.klo_need01(NOW_MS, NOW_MS + 2 * HOUR_MS), 0.5, 1e-9, "halbvoll")
	assert_almost(BadState.klo_need01(NOW_MS, NOW_MS + 9 * HOUR_MS), 1.0, 1e-9, "gedeckelt")
	assert_false(BadState.klo_due(0, NOW_MS), "ohne Timer nie fällig")
	assert_false(BadState.klo_due(NOW_MS, NOW_MS + 4 * HOUR_MS - 1))
	assert_true(BadState.klo_due(NOW_MS, NOW_MS + 4 * HOUR_MS), "nach 4 h MUSS Gooby")


func test_shower_peek_und_brush_break_pure() -> void:
	assert_false(BadState.shower_peek_due(0, NOW_MS), "keine Dusche aktiv")
	assert_false(BadState.shower_peek_due(NOW_MS, NOW_MS + 44_999))
	assert_true(BadState.shower_peek_due(NOW_MS, NOW_MS + 45_000), "Peek nach 45 s")
	assert_true(BadState.brush_breaks(0.0, 0.02), "Roll unter Chance bricht")
	assert_false(BadState.brush_breaks(0.02, 0.02), "Roll auf Chance bricht nicht")
	assert_false(BadState.brush_breaks(0.5, -1.0), "Chance wird geclampt")
	assert_true(BadState.brush_breaks(0.999, 2.0), "Chance > 1 = sicher")


func test_normalize_slice_selbstheilung() -> void:
	var healed := BadState.normalize_slice(
		{"kloLastMs": -5, "needsBrushing": "ja", "lights": [], "brushBrokenCount": -2}
	)
	assert_eq(healed["kloLastMs"], 0, "negative Stamps geklemmt")
	assert_eq(healed["needsBrushing"], false, "nur echtes true zählt")
	assert_eq(healed["lights"], {}, "lights muss Dictionary sein")
	assert_eq(healed["brushBrokenCount"], 0)
	assert_eq(healed["showerStartedMs"], 0, "fehlende Keys ergänzt")
	var lit := BadState.normalize_slice({"lights": {"a": "an", "b": true}})
	assert_eq(lit["lights"], {"a": false, "b": true}, "lights-Werte typisiert")
	var fresh := BadState.normalize_slice("quatsch")
	assert_eq(fresh, BadState.default_slice(), "Nicht-Dict → Defaults")


func test_glue_woke_up_und_brushed() -> void:
	var gs := _fresh_gs()
	assert_false(BadState.needs_brushing(gs), "frisch: keine Putz-Pflicht")
	BadState.mark_woke_up(gs)
	assert_true(BadState.needs_brushing(gs), "nach Schlaf-Ende Pflicht")
	BadState.mark_brushed(gs, false)
	assert_false(BadState.needs_brushing(gs), "geputzt = Pflicht weg")
	assert_eq(int(gs.get_value("achievements.counters.teeth_brushed", 0)), 1, "Sticker-Counter")
	assert_eq(int(gs.get_value("bad.brushBrokenCount", 0)), 0)
	BadState.mark_woke_up(gs)
	BadState.mark_brushed(gs, true)
	assert_eq(int(gs.get_value("bad.brushBrokenCount", 0)), 1, "Bürsten-Bruch gezählt")
	assert_eq(int(gs.get_value("achievements.counters.teeth_brushed", 0)), 2)
	gs.free()


func test_glue_klo_timer_und_lights() -> void:
	var gs := _fresh_gs()
	BadState.ensure_klo_timer(gs, NOW_MS)
	assert_eq(int(gs.get_value("bad.kloLastMs", 0)), NOW_MS, "Erstkontakt startet Timer")
	BadState.ensure_klo_timer(gs, NOW_MS + 999)
	assert_eq(int(gs.get_value("bad.kloLastMs", 0)), NOW_MS, "ensure überschreibt nicht")
	BadState.mark_klo_done(gs, NOW_MS + HOUR_MS)
	assert_eq(int(gs.get_value("bad.kloLastMs", 0)), NOW_MS + HOUR_MS, "Klo-Gang resettet")
	assert_true(BadState.light_on(gs, "lamp_1"), "Lampen default an")
	BadState.set_light_on(gs, "lamp_1", false)
	assert_false(BadState.light_on(gs, "lamp_1"), "Toggle persistiert")
	assert_true(BadState.light_on(gs, "lamp_2"), "andere uid unberührt")
	BadState.set_shower_started(gs, NOW_MS)
	assert_eq(int(gs.get_value("bad.showerStartedMs", 0)), NOW_MS)
	gs.free()


func test_de_en_paritaet_bad_domain() -> void:
	I18nService.reset_cache()
	var de := I18nService.table("de")
	var en := I18nService.table("en")
	for key: String in BAD_KEYS:
		assert_true(de.has(key), "DE fehlt Key: %s" % key)
	for key: String in de:
		if key.begins_with("bad."):
			assert_true(en.has(key), "EN fehlt Key: %s" % key)
	for key: String in en:
		if key.begins_with("bad."):
			assert_true(de.has(key), "DE fehlt Key: %s" % key)
