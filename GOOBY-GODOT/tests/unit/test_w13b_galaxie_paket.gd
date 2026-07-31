extends TestCase
## W13B/GALAXIE — Paket-Tests für die drei unabhängigen Teile der Welle:
## (a) GALAXIE-Fellfarbe: Katalog-Eintrag valide, Shader-Datei existiert,
##     equip über die CosmeticsState-Logik, apply_fell wechselt das Material
##     (ShaderMaterial NUR bei Galaxie, Palette-Duplikat sonst, null bei
##     Standard-Fell), Reduced-Motion friert den Shader ein (bewegung=0).
## (b) KLOPAPIER-MUMIE-Event: Def schema-valide (M1-Rest, context home),
##     5-Tap-Zustandsmaschine im EventRunner (Fake-Raum, Muster
##     test_events_runner), Fun-Buff-Belohnung, Timeout-Fail-Text.
## (c) BUCHSTABEN-TYPEWRITER: deterministisch (Zeit injiziert — n Ticks =
##     n sichtbare Zeichen), Tap-Skip (ganze Zeile sofort), Sofort-Modus,
##     View-Integration (Tap-Fänger → erst Zeile komplett, dann weiter).

const GameStateScript := preload("res://scripts/state/game_state.gd")
const Economy := preload("res://scripts/logic/economy.gd")

const NOW_MS := 1768478400000
const EVENTS_JSON := "res://content/events/data/events.json"
const SHADER_PFAD := "res://assets/shaders/fell_galaxie.gdshader"
const GALAXIE_ID := "fell_galaxie"
const MUMIE_FAIL := "Gooby hat es schon alleine hingekriegt -_-"

var _dir_seq := 0

# ── Fakes (Muster test_events_runner.gd — Runner braucht Raum + Gooby) ───────


class FakeRig:
	extends Node3D

	var emotions: Array[String] = []

	func set_emotion(id: String) -> void:
		emotions.append(id)


class FakeGooby:
	extends Node3D

	var rig: FakeRig = FakeRig.new()
	var wander := true
	var clips: Array[String] = []

	func _init() -> void:
		add_child(rig)

	func set_wander_enabled(enabled: bool) -> void:
		wander = enabled

	func play_clip(clip: String) -> void:
		clips.append(clip)


class FakeRoom:
	extends Node3D

	var gs: Object = null
	var gooby_node: FakeGooby = FakeGooby.new()
	var bubbles: Array[String] = []

	func _init() -> void:
		add_child(gooby_node)

	func game_state() -> Object:
		return gs

	func gooby() -> Node:
		return gooby_node

	func say(text: String) -> void:
		bubbles.append(text)


# ── (a) GALAXIE-Fellfarbe ────────────────────────────────────────────────────


func test_galaxie_katalogeintrag_valide() -> void:
	CosmeticsCatalog.reset_cache()
	var def := CosmeticsCatalog.by_id(GALAXIE_ID)
	assert_false(def.is_empty(), "fell_galaxie steht im ausgelieferten Katalog")
	assert_eq(str(def["kategorie"]), "fell", "Fellfarbe-Typ")
	assert_eq(int(def["preis"]), 2500, "Premium-Preis")
	assert_eq(str(def["rarity"]), "legendaer", "legendär")
	assert_false(bool(def["standard"]), "kein Gratis-Fell")
	assert_eq((def["farben"] as Array).size(), 3, "3 Palettenfarben (body/bauch/ohr)")
	for hex: Variant in def["farben"]:
		assert_true(str(hex).is_valid_html_color(), "Farbe %s ist gültiges Hex" % hex)
	assert_eq(str(CosmeticParts.param(def, "shader", "")), "galaxie", "Shader-Marker")
	assert_ne(str(def["desc_en"]), str(def["desc_de"]), "EN-Beschreibung übersetzt")
	assert_eq(CosmeticsCatalog.validate(CosmeticsCatalog.raw_items()), [], "Katalog bleibt heil")


func test_galaxie_shader_datei_existiert() -> void:
	assert_true(FileAccess.file_exists(SHADER_PFAD), "Shader-Datei liegt im Repo")
	var shader := load(SHADER_PFAD) as Shader
	assert_true(shader != null, "Shader lädt als Resource")


func test_galaxie_equip_ueber_cosmetics_state() -> void:
	CosmeticsCatalog.reset_cache()
	var slice := CosmeticsState.default_slice()
	var econ := Economy.default_slice()
	econ["coins"] = 2500
	assert_false(bool(CosmeticsState.equip(slice, GALAXIE_ID)["ok"]), "nicht besessen → kein equip")
	var quest := CosmeticsState.grant(slice, GALAXIE_ID, "quest")
	assert_eq(str(quest["grund"]), "nur_im_shop", "Fell gibt es NUR im Shop")
	var kauf := CosmeticsState.buy(slice, econ, GALAXIE_ID)
	assert_true(bool(kauf["ok"]), "Kauf klappt: %s" % str(kauf.get("grund", "")))
	assert_eq(int(econ["coins"]), 0, "2500 Münzen abgebucht")
	var equip := CosmeticsState.equip(slice, GALAXIE_ID)
	assert_true(bool(equip["ok"]), "equip klappt")
	assert_eq(CosmeticsState.equipped(slice, "fell"), GALAXIE_ID, "Galaxie ist angelegt")
	CosmeticsState.unequip(slice, "fell")
	assert_eq(CosmeticsState.equipped(slice, "fell"), "cream", "unequip fällt aufs Standard-Fell")


func test_galaxie_apply_fell_wechselt_material() -> void:
	CosmeticsCatalog.reset_cache()
	var rig := _fake_rig()
	tree.root.add_child(rig)
	var attach := CosmeticAttach.fuer_rig(rig)
	assert_true(attach != null, "Attach findet Skelett + Mesh")
	attach.reduced_motion_override = 0
	var mesh := rig.get_node("Mesh") as MeshInstance3D

	attach.apply_fell(GALAXIE_ID)
	var override := mesh.get_surface_override_material(0)
	assert_true(override is ShaderMaterial, "Galaxie → ShaderMaterial-Override")
	if override is ShaderMaterial:
		var material := override as ShaderMaterial
		assert_eq(material.shader.resource_path, SHADER_PFAD, "es ist DER Galaxie-Shader")
		assert_almost(
			float(material.get_shader_parameter("bewegung")), 1.0, 1e-6, "Motion an → bewegt"
		)
		var palette := material.get_shader_parameter("palette") as ImageTexture
		assert_true(palette != null, "umgefärbte Palette hängt am Shader")
		if palette != null:
			var body := palette.get_image().get_pixel(32, 32)
			var soll := Color("#241E3F").srgb_to_linear()
			assert_almost(body.r, soll.r, 0.02, "Fell-Zelle 0 trägt die Galaxie-Körperfarbe")
			assert_almost(body.b, soll.b, 0.02, "…auch im Blau-Kanal")

	attach.apply_fell("snow")
	assert_true(
		mesh.get_surface_override_material(0) is StandardMaterial3D,
		"normale Fellfarbe → Palette-Duplikat (bestehender Pfad unangetastet)"
	)
	attach.apply_fell("cream")
	assert_true(
		mesh.get_surface_override_material(0) == null, "Standard-Fell → Override wieder weg"
	)
	rig.queue_free()
	await wait_frames(2)


func test_galaxie_reduced_motion_ist_statisch() -> void:
	CosmeticsCatalog.reset_cache()
	var rig := _fake_rig()
	tree.root.add_child(rig)
	var attach := CosmeticAttach.fuer_rig(rig)
	attach.reduced_motion_override = 1
	attach.apply_fell(GALAXIE_ID)
	var mesh := rig.get_node("Mesh") as MeshInstance3D
	var material := mesh.get_surface_override_material(0) as ShaderMaterial
	assert_true(material != null, "Galaxie-Material liegt an")
	if material != null:
		assert_almost(
			float(material.get_shader_parameter("bewegung")),
			0.0,
			1e-6,
			"Reduced-Motion → Shader statisch"
		)
	rig.queue_free()
	await wait_frames(2)


## Minimal-Rig für apply_fell: Skelett mit den Anker-Bones + Mesh, dessen
## Surface-0-Material eine Palette-Textur trägt (wie das echte GLB).
func _fake_rig() -> Node3D:
	var rig := Node3D.new()
	var skelett := Skeleton3D.new()
	for bone: String in ["head", "chest", "spine"]:
		skelett.add_bone(bone)
	rig.add_child(skelett)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	var material := StandardMaterial3D.new()
	var bild := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	bild.fill(Color("#F6EAD7"))
	material.albedo_texture = ImageTexture.create_from_image(bild)
	box.material = material
	mesh.mesh = box
	rig.add_child(mesh)
	return rig


# ── (b) KLOPAPIER-MUMIE ──────────────────────────────────────────────────────


func test_mumie_def_schema_valide() -> void:
	var def := RandomEventEngine.def_by_id(_defs(), "klopapier_mumie")
	assert_false(def.is_empty(), "Def existiert in events.json")
	assert_eq(str(def.get("context", "home")), "home", "Haus-Event")
	assert_eq(str(def.get("szene_setup", "")), "klopapier_mumie", "Setup-Hook")
	assert_eq(int(def.get("props", 0)), 5, "5 Wicklungen = 5 Taps")
	assert_true(
		str(def.get("notification_text_de", "")).contains("Klopapier-Mumie"),
		"Notification erzählt die Mumie"
	)
	assert_eq(str(def.get("fail_text_de", "")), MUMIE_FAIL, "Fail-Text im Bestands-Stil")
	var timeout := int(def.get("timeout_min", 0))
	assert_true(timeout >= 5 and timeout <= 10, "timeout_min 5-10 wie die Bestands-Defs")
	var window: Array = def.get("trigger_window", [])
	assert_eq(window.size(), 2, "Fenster [von,bis]")
	for edge: Variant in window:
		assert_ne(RandomEventEngine.parse_minutes(str(edge)), -1, "Fensterkante parst")
	var reward: Dictionary = def.get("reward", {})
	assert_eq(str(reward.get("buff_id", "")), "spass_plus", "kleiner Fun-Buff")
	assert_eq(str(reward.get("stat", "")), "fun", "…auf Spaß")
	assert_true(float(reward.get("wert", 0)) > 0.0, "…mit positivem Wert")
	assert_true(float(reward.get("dauer_h", 0)) > 0.0, "…und Dauer")


func test_mumie_fuenf_taps_zustandsmaschine() -> void:
	var ctx := _stage("klopapier_mumie")
	var runner: EventRunner = ctx["runner"]
	assert_true(runner.is_running(), "Szene läuft")
	assert_eq(runner._remaining, 5, "5 Wicklungen liegen an")
	assert_eq(runner._props.size(), 6, "5 Bänder + 1 Tap-Zone im Raum")
	for i in 4:
		MumieSzene.tap(runner)
		assert_true(runner.is_running(), "Tap %d/5: noch eingewickelt" % (i + 1))
	assert_eq(runner._remaining, 1, "eine Wicklung übrig")
	MumieSzene.tap(runner)
	assert_false(runner.is_running(), "5. Tap: ausgewickelt")
	var gs: Object = ctx["gs"]
	assert_true(RandomEventEngine.active_of(gs).is_empty(), "Event aufgelöst")
	assert_eq(int(gs.get_value("events.resolvedTotal", 0)), 1, "resolvedTotal zählt")
	var buffs: Dictionary = gs.get_value("buffs", {})
	assert_almost(GoobyBuffs.stat_bonus(buffs, "fun", NOW_MS), 8.0, 1e-9, "+8 Spaß-Buff")
	var gooby := (ctx["room"] as FakeRoom).gooby_node
	assert_true(gooby.clips.has("hop"), "Befreiungs-Hop")
	await _teardown(ctx)


func test_mumie_timeout_fail_text() -> void:
	NotifyStub.reset_for_tests()
	var gs := _fresh_gs()
	var defs := _defs()
	var def := RandomEventEngine.def_by_id(defs, "klopapier_mumie")
	RandomEventEngine.activate(gs, def, NOW_MS)
	RandomEventEngine.fail_active(gs, defs, NOW_MS + 9 * 60_000)
	assert_eq(RandomEventEngine.take_fail_notice(gs), MUMIE_FAIL, "Fail-Bubble im Bestands-Stil")
	assert_eq(RandomEventEngine.fail_prop_of(gs), "", "keine Fail-Requisite")
	gs.free()


func test_mumie_strings_de_en_paritaet() -> void:
	I18nService.reset_cache()
	var de := I18nService.table("de")
	var en := I18nService.table("en")
	for key: String in ["events.mumie.bubble", "events.mumie.wickel", "events.mumie.danke"]:
		assert_true(de.has(key), "DE hat %s" % key)
		assert_true(en.has(key), "EN hat %s" % key)
	assert_true(
		str(de.get("events.mumie.danke", "")).begins_with("Nie wieder!"), "Abschluss-Gag sitzt"
	)


# ── (c) BUCHSTABEN-TYPEWRITER ────────────────────────────────────────────────


func test_typewriter_deterministisch() -> void:
	var tw := DialogTypewriter.new()
	tw.start("Hallo Gooby!")
	assert_eq(tw.sichtbar, 0, "startet bei 0 Zeichen")
	assert_true(tw.laeuft(), "läuft")
	var schritt := 1.0 / DialogTypewriter.ZEICHEN_PRO_SEK
	for n in range(1, 13):
		tw.tick(schritt)
		assert_eq(tw.sichtbar, n, "%d Ticks = %d sichtbare Zeichen" % [n, n])
	assert_true(tw.ist_fertig(), "nach 12 Ticks fertig (12 Zeichen)")
	tw.tick(schritt)
	assert_eq(tw.sichtbar, 12, "kein Überlauf nach dem Ende")


func test_typewriter_tap_skip_und_sofort() -> void:
	var tw := DialogTypewriter.new()
	tw.start("Eine ziemlich lange Zeile für den Skip.")
	tw.tick(3.0 / DialogTypewriter.ZEICHEN_PRO_SEK)
	assert_eq(tw.sichtbar, 3, "3 Ticks = 3 Zeichen")
	tw.skip()
	assert_eq(tw.sichtbar, tw.text.length(), "Tap = ganze Zeile sofort")
	assert_true(tw.ist_fertig())
	assert_false(tw.laeuft(), "nach Skip kein Weiterticken")
	var sofort := DialogTypewriter.new()
	sofort.start("Reduced-Motion oder Schnelle Dialoge.", true)
	assert_eq(sofort.sichtbar, sofort.text.length(), "Sofort-Modus zeigt alles ohne Ticks")
	assert_false(sofort.laeuft())


func test_typewriter_view_integration_tap_erst_zeile_dann_weiter() -> void:
	var view := OrtDialogView.new()
	view.sofort_override = 0
	tree.root.add_child(view)
	await wait_frames(1)
	var fertig := [false]
	view.beendet.connect(func() -> void: fertig[0] = true)
	var lange_zeile := "Diese Zeile ist absichtlich sehr, sehr lang, damit der Typewriter "
	lange_zeile += "während des Tests garantiert noch nicht fertig getickt hat, ehrlich."
	var baum := {
		"start": "a",
		"nodes": {"a": {"sprecher": "Test", "text": lange_zeile, "ende": true}},
	}
	view.starte(baum, {})
	var label := view._label as Label
	assert_true(label != null, "View kennt das Bubble-Label")
	assert_true(
		label.visible_characters >= 0 and label.visible_characters < lange_zeile.length(),
		"Typewriter-Modus: Zeile ist NICHT sofort komplett"
	)
	var klick := InputEventMouseButton.new()
	klick.pressed = true
	klick.button_index = MOUSE_BUTTON_LEFT
	(view._fang as Control).gui_input.emit(klick)
	assert_eq(label.visible_characters, -1, "1. Tap: ganze Zeile sofort sichtbar")
	assert_false(fertig[0], "…aber noch nicht weitergeblättert")
	(view._fang as Control).gui_input.emit(klick)
	assert_true(fertig[0], "2. Tap: blättert weiter → Dialog beendet")
	view.queue_free()
	await wait_frames(2)


func test_typewriter_sofort_modus_in_der_view() -> void:
	var view := OrtDialogView.new()
	view.sofort_override = 1
	tree.root.add_child(view)
	await wait_frames(1)
	var baum := {
		"start": "a",
		"nodes": {"a": {"sprecher": "Test", "text": "Zack, alles da.", "ende": true}},
	}
	view.starte(baum, {})
	var label := view._label as Label
	assert_eq(label.visible_characters, -1, "Sofort-Modus: Zeile komplett ohne Ticks")
	view.queue_free()
	await wait_frames(2)


# ── Helfer ───────────────────────────────────────────────────────────────────


func _fresh_gs() -> Node:
	RandomEventEngine.register_slice()
	GoobyBuffs.register_slice()
	_dir_seq += 1
	var dir := "user://w13b_tests/ev_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	return gs


func _defs() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EVENTS_JSON))
	assert_true(parsed is Dictionary, "events.json parst")
	return parsed.get("items", []) if parsed is Dictionary else []


func _stage(event_id: String) -> Dictionary:
	var gs := _fresh_gs()
	var defs := _defs()
	var def := RandomEventEngine.def_by_id(defs, event_id)
	assert_false(def.is_empty(), event_id + ": Def existiert")
	RandomEventEngine.activate(gs, def, NOW_MS)
	var room := FakeRoom.new()
	room.gs = gs
	tree.root.add_child(room)
	var runner := EventRunner.attach_to(room, defs)
	return {"room": room, "gs": gs, "runner": runner, "def": def}


func _teardown(ctx: Dictionary) -> void:
	(ctx["room"] as Node).queue_free()
	await wait_frames(2)
	(ctx["gs"] as Node).free()
