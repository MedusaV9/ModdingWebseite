extends TestCase
## W13/HUD-WIRES — „Wo ist mein Gooby?" (P5-Befund F2: totes HUD-Signal):
## pure Tat-Logik (jüngster Akt/Absicht, Frischefenster, Prioritäten),
## pure Chip-Reaktion, DE/EN-Texte der Tat-Bubble und der End-zu-End-Flow
## im echten Wohnzimmer (Bubble-Text + Gooby kommt zum Spieler zurück).

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

const TAT_KEYS := [
	"home.suche.hier",
	"home.suche.unterwegs",
	"home.suche.schlaeft",
	"home.suche.baumodus",
	"home.suche.akt.idle_aufraeumen",
	"home.suche.akt.idle_fernsehen",
	"home.suche.akt.idle_doesen",
	"home.suche.akt.idle_fenster",
	"home.suche.akt.idle_tanzen",
	"home.suche.akt.idle_lieblingsplatz",
	"home.suche.akt.absicht_hunger",
	"home.suche.akt.absicht_langeweile",
	"home.suche.akt.absicht_muede",
	"home.suche.akt.absicht_dreckig",
	"home.suche.akt.absicht_regen",
	"home.auge.hinweis",
]

var _seq := 0


## Fake-Seelen-Runner: nur das Cooldown-Buch, das RoomBase duck-typed liest.
class FakeRunner:
	extends Node

	var _idle_cooldowns: Dictionary = {}


func test_juengster_akt_pure() -> void:
	assert_eq(GoobyHome.juengster_akt({}, 1000, 5000), {}, "leeres Buch → leer")
	var buch := {"idle_doesen": 4000, "idle_fenster": 9000}
	var akt := GoobyHome.juengster_akt(buch, 1000, 8500)
	assert_eq(str(akt.get("id")), "idle_fenster", "jüngster Eintrag gewinnt")
	assert_eq(int(akt.get("alter_ms")), 500, "Alter = now - (Ablauf - Cooldown)")


func test_tat_key_prioritaeten() -> void:
	assert_eq(
		GoobyHome.tat_key({"schlaeft": true, "akt": {"id": "idle_tanzen", "alter_ms": 0}}),
		"home.suche.schlaeft",
		"Schlaf schlägt alles"
	)
	var zwei_taten := {
		"akt": {"id": "idle_fernsehen", "alter_ms": 30_000},
		"absicht": {"id": "absicht_hunger", "alter_ms": 5_000},
	}
	assert_eq(
		GoobyHome.tat_key(zwei_taten),
		"home.suche.akt.absicht_hunger",
		"frischere Tat gewinnt (Absicht vor älterem Akt)"
	)
	var abgestanden := {
		"unterwegs": true,
		"akt": {"id": "idle_doesen", "alter_ms": GoobyHome.TAT_FRISCH_MS + 1},
	}
	assert_eq(
		GoobyHome.tat_key(abgestanden),
		"home.suche.unterwegs",
		"abgestandene Tat fällt aufs Laufen zurück"
	)
	assert_eq(
		GoobyHome.tat_key({"akt": {"id": "idle_doesen", "alter_ms": -50}}),
		"home.suche.hier",
		"Zukunfts-Buchung (kaputte Uhr) wird ignoriert"
	)
	assert_eq(GoobyHome.tat_key({}), "home.suche.hier", "ohne alles: Fallback")


func test_suche_reaktion_pure() -> void:
	assert_eq(GoobyHome.suche_reaktion(false, false), "still", "kein Gooby → still")
	assert_eq(GoobyHome.suche_reaktion(true, true), "bau", "Baumodus → nur Bubble")
	assert_eq(GoobyHome.suche_reaktion(true, false), "fokus", "Normalfall → Fokus")


func test_suche_texte_de_en_vorhanden() -> void:
	I18nService.reset_cache()
	var de := I18nService.table("de")
	var en := I18nService.table("en")
	for key: String in TAT_KEYS:
		assert_true(de.has(key), "DE-Text fehlt: %s" % key)
		assert_true(en.has(key), "EN-Text fehlt: %s" % key)


func test_wo_ist_gooby_bubble_und_rueckkehr() -> void:
	var gs := _fresh_gs()
	var room: RoomBase = await _make_living_room(gs)
	var gooby := room.gooby()
	gooby.set_wander_enabled(false)
	await wait_frames(2)
	# Ohne Seelen-Runner und ohne Laufweg: Fallback-Text.
	gooby.wo_ist_gooby()
	assert_true(_bubble_von(room).is_active(), "Tat-Bubble ist sichtbar")
	assert_eq(
		_bubble_von(room).current_line(),
		I18nService.t("home.suche.hier"),
		"Fallback-Tat ohne Seelen-Runner"
	)
	assert_true(gooby.is_walking(), "Gooby kommt zum Spieler (Kamera) zurück")
	assert_false(room.camera_rig().is_build_mode(), "Kamera bleibt im Follow-Modus")
	# Mit frischem Idle-Akt im (Fake-)Seelen-Runner: Tat wird erzählt.
	gooby.cancel_walk()
	gooby.set_wander_enabled(false)
	var runner := FakeRunner.new()
	runner.name = "GoobyReactions"
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	runner._idle_cooldowns = {"idle_fernsehen": now_ms + GoobyReactions.IDLE_ACT_COOLDOWN_MS}
	room.add_child(runner)
	gooby.wo_ist_gooby()
	assert_eq(
		_bubble_von(room).current_line(),
		I18nService.t("home.suche.akt.idle_fernsehen"),
		"frischer Idle-Akt wird als Tat erzählt"
	)
	await _cleanup(room, gs)


## Die Raum-Bubble hängt am UI-Layer des Raums. W14/UIKERN: RoomBase.say
## erzeugt pro Spruch eine AcBubble (Queue max. 2) — die NEUSTE zählt.
func _bubble_von(room: RoomBase) -> AcBubble:
	var letzte: AcBubble = null
	for kind: Node in room.ui_layer().get_children():
		if kind is AcBubble:
			letzte = kind
	return letzte


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://w13_tests/suche_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	return gs


func _make_living_room(gs: Node) -> RoomBase:
	var scene: PackedScene = load("res://scenes/home/wohnzimmer.tscn")
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	room.stunde_override = 13.0
	tree.root.add_child(room)
	await wait_frames(3)
	await wait_until(func() -> bool: return not room._rebake_pending, 4000)
	await tree.physics_frame
	return room


func _cleanup(room: Node, gs: Node) -> void:
	room.queue_free()
	await wait_frames(2)
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()
