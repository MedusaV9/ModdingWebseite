extends TestCase
## W4-P3 POLISH-6 — HomeLicht (pure Raum-Licht-Profile + Tageszeit-Lerp)
## und das Szenen-Setup: Sonne OHNE Shadow-Map, Blob-Shadow unter Gooby,
## Füll-Licht vorhanden (Budget A §7).

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

const PROFIL_KEYS := [
	"hintergrund",
	"ambient_farbe",
	"ambient_energie",
	"sonnen_farbe",
	"sonnen_energie",
	"sonnen_rotation",
	"fuell_farbe",
	"fuell_energie",
	"fenster_energie",
]


func test_tageslicht_kurve() -> void:
	assert_almost(HomeLicht.tageslicht(12.0), 1.0, 1e-6, "Mittag voll")
	assert_almost(HomeLicht.tageslicht(23.0), 0.0, 1e-6, "Nacht dunkel")
	assert_almost(HomeLicht.tageslicht(3.0), 0.0, 1e-6, "früh morgens dunkel")
	var daemmerung := HomeLicht.tageslicht(6.75)
	assert_true(daemmerung > 0.0 and daemmerung < 1.0, "Morgen-Rampe dazwischen")
	assert_almost(HomeLicht.tageslicht(25.0), HomeLicht.tageslicht(1.0), 1e-6, "24h-Wrap")


func test_jeder_raum_hat_ein_profil() -> void:
	for room_id: String in RoomDefs.ids():
		var outdoor: bool = bool(RoomDefs.room(room_id).get("outdoor", false))
		var profil := HomeLicht.profil(room_id, outdoor, 12.0)
		for key: String in PROFIL_KEYS:
			assert_true(profil.has(key), "%s: Profil-Key %s" % [room_id, key])


func test_raeume_sind_unterschiedlich_gestimmt() -> void:
	var living: Color = HomeLicht.profil("living", false, 12.0)["ambient_farbe"]
	var bad: Color = HomeLicht.profil("bathroom", false, 12.0)["ambient_farbe"]
	var schlaf: Color = HomeLicht.profil("bedroom", false, 12.0)["ambient_farbe"]
	assert_true(living.r > living.b, "Wohnzimmer warm (R > B)")
	assert_true(bad.b > bad.r, "Bad kühl-frisch (B > R)")
	assert_true(schlaf.g < living.g, "Schlafzimmer rosiger als Wohnzimmer")


func test_drinnen_bleibt_nachts_spielbar_hell() -> void:
	var tag := HomeLicht.profil("living", false, 12.0)
	var nacht := HomeLicht.profil("living", false, 23.0)
	assert_true(float(nacht["ambient_energie"]) < float(tag["ambient_energie"]), "nachts gedimmt")
	assert_true(
		(
			float(nacht["ambient_energie"])
			>= HomeLicht.AMBIENT_TAG * HomeLicht.NACHT_FAKTOR_INNEN - 1e-6
		),
		"aber nie dunkler als der Innen-Nachtfaktor"
	)
	assert_true(
		float(nacht["fuell_energie"]) > float(tag["fuell_energie"]), "Füll-Lampe übernimmt nachts"
	)
	assert_true(
		float(nacht["fenster_energie"]) < float(tag["fenster_energie"]),
		"Fenster leuchten nachts nicht"
	)


func test_garten_folgt_der_sonne() -> void:
	var morgen := HomeLicht.profil("garden", true, 7.5)
	var mittag := HomeLicht.profil("garden", true, 12.0)
	var nacht := HomeLicht.profil("garden", true, 23.0)
	assert_true(
		float(mittag["sonnen_energie"]) > float(morgen["sonnen_energie"]),
		"Mittag heller als Morgen"
	)
	assert_true(
		float(nacht["sonnen_energie"]) < float(morgen["sonnen_energie"]), "Nacht = fahler Mond"
	)
	var rot_mittag: Vector3 = mittag["sonnen_rotation"]
	var rot_morgen: Vector3 = morgen["sonnen_rotation"]
	assert_true(absf(rot_mittag.x) > absf(rot_morgen.x), "Sonne steht mittags höher")
	var nacht_himmel: Color = nacht["hintergrund"]
	assert_true(nacht_himmel.r < 0.3, "Nachthimmel dunkel")


func test_raum_szene_nutzt_blob_shadow_statt_sonnen_schatten() -> void:
	var dir := "user://w4p3_tests/licht_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	var scene: PackedScene = load("res://scenes/home/wohnzimmer.tscn")
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	room.stunde_override = 12.0
	tree.root.add_child(room)
	await wait_frames(3)
	var sonne: DirectionalLight3D = room.get_node("Sonne")
	assert_true(sonne != null, "Sonne existiert")
	assert_false(sonne.shadow_enabled, "Sonnen-Schatten AUS (Blob statt Shadow-Map)")
	var fuell: OmniLight3D = room.get_node("FuellLicht")
	assert_true(fuell != null, "Füll-Licht existiert")
	assert_false(fuell.shadow_enabled, "Füll-Licht ohne Schatten")
	var blob := room.gooby().get_node_or_null("BlobShadow")
	assert_true(blob != null, "Blob-Shadow unter Gooby")
	await wait_until(func() -> bool: return not room._rebake_pending, 3000)
	room.queue_free()
	await wait_frames(2)
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()
