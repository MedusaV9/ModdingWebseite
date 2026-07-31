class_name GartenDiorama
extends Node3D
## Garten-Diorama hinter Fenstern mit Vista „garten" (HAUS-SICHT, User:
## „der Garten vor dem Fenster"). Gegenstück zum Straßen-Diorama
## (street_diorama.gd) für Küche/Bad: Rasen im Grundstücks-Belag des
## Spielers (HouseStyleState!), Beete mit Möhren, Blumen, Büsche, ein
## Bäumchen und die Gartenhecke — alles unterhalb der Wandkrone, damit von
## innen nichts über die Außenwand lugt.
##
## Bewusst billig: kein _process, Wiederhol-Grün als MultiMesh, aufgebaut
## NUR wenn an der Wand wirklich ein Fenster hängt (RoomBase ruft
## attach_if_needed) — im Baumodus übernimmt die Vorstadt-Kulisse.

const ASSETS := "res://assets/city"
## So weit hinter der Wand liegt das Diorama.
const TIEFE := 3.0
const BREITE_MIN := 18.0
## Alles bleibt unter RoomBase.WALL_HEIGHT (sonst lugt es ins Zimmer).
const MAX_HOEHE := 2.35

## W13/WETTER-FX: Tests/Screenshots erzwingen eine Wetterlage
## ({} = echter SoulWetter-Tagesplan von heute).
var wetter_override: Dictionary = {}
## Uhrzeit für den Wetterplan (< 0 = Systemuhr; kommt aus RoomBase).
var stunde_override := -1.0

var _laenge := BREITE_MIN
var _style: Dictionary = {}
var _wetter_fx: WetterFx
var _blitz_tafel: MeshInstance3D
var _blitz_mat: StandardMaterial3D
var _blitz_rest := 0.0


## Vista-Weiche für RoomBase: „garten" bekommt dieses Diorama, alle
## anderen Vistas das Straßen-Diorama (street_diorama.gd).
static func fuer_vista(
	room: Node3D, grid: GridData, world_size: Vector2, wall: String, vista: String
) -> Node3D:
	if vista == "garten":
		return attach_if_needed(room, grid, world_size, wall)
	return StreetDiorama.attach_if_needed(room, grid, world_size, wall, vista)


## Baut das Diorama für `wall` hinter einem Raum der Größe `world_size`,
## wenn dort ein Fenster hängt. Liefert das Diorama oder null.
static func attach_if_needed(
	room: Node3D, grid: GridData, world_size: Vector2, wall: String
) -> GartenDiorama:
	if not _hat_fenster(grid, wall):
		return null
	var diorama := GartenDiorama.new()
	diorama.name = "Diorama_%s" % wall
	diorama._laenge = maxf(BREITE_MIN, maxf(world_size.x, world_size.y) * 2.5)
	if room.has_method("game_state"):
		diorama._style = HouseStyleState.style(room.call("game_state"))
	var stunde: Variant = room.get("stunde_override")
	if stunde is float:
		diorama.stunde_override = float(stunde)
	room.add_child(diorama)
	diorama.position = _diorama_position(wall, world_size)
	diorama.rotation.y = _diorama_yaw(wall)
	return diorama


## Hängt an dieser Wand mindestens ein Fenster (WALL-Item mit `exterior`)?
static func _hat_fenster(grid: GridData, wall: String) -> bool:
	for offset in grid.wall_width(wall):
		var uid := grid.wall_item_at(wall, offset)
		if uid == "":
			continue
		if bool(grid.get_item(uid).get("def", {}).get("exterior", false)):
			return true
	return false


func _ready() -> void:
	if _style.is_empty():
		_style = HouseStyleState.normalize({})
	_baue_boden()
	_baue_hecke()
	_baue_beete()
	_baue_gruen()
	_baue_himmel()
	_haenge_wetter()


## Blitz-Abklingen ist der EINZIGE _process-Grund dieses Dioramas —
## deshalb schläft _process, bis wirklich ein Blitz zündet.
func _process(delta: float) -> void:
	if _blitz_rest <= 0.0 or _blitz_tafel == null:
		set_process(false)
		return
	_blitz_rest -= delta
	var faktor := HomeLicht.blitz_faktor(_blitz_rest)
	_blitz_mat.albedo_color = Color(HomeLicht.BLITZ_FARBE, 0.55 * faktor)
	_blitz_tafel.visible = faktor > 0.01


## W13/WETTER-FX: dezenter Regen-/Schnee-Vorhang hinter der Scheibe
## (Indoor-Band ohne Spritzer) + Blitz-Tafel vor der Himmels-Rückwand bei
## Gewitter; das gedämpfte Donner-Grollen kommt aus den WetterFx-Loops.
## Der Plan kommt IMMER aus SoulWetter (deterministisch pro Tag+Stunde).
func _haenge_wetter() -> void:
	var zustand := wetter_override
	if zustand.is_empty():
		zustand = SoulWetter.zustand(RanchWetter.datum_heute(), _stunde())
	_wetter_fx = WetterFx.fuer_diorama(_laenge, zustand)
	add_child(_wetter_fx)
	_wetter_fx.position = Vector3(0.0, 0.0, -0.5)
	_wetter_fx.blitz_gezuendet.connect(_on_blitz_gezuendet)
	_baue_blitz_tafel()
	set_process(false)


func wetter_fx() -> WetterFx:
	return _wetter_fx


func _stunde() -> float:
	if stunde_override >= 0.0:
		return stunde_override
	var jetzt := Time.get_time_dict_from_system()
	return float(jetzt["hour"]) + float(jetzt["minute"]) / 60.0


## Unshaded Flash-Quad knapp vor der Himmel-Wand — EIGENES Material
## (HomeProps-Materialien sind geteilt und dürfen nicht blinken).
func _baue_blitz_tafel() -> void:
	_blitz_tafel = MeshInstance3D.new()
	_blitz_tafel.name = "BlitzTafel"
	var quad := QuadMesh.new()
	# Nur Fensterhöhe: bleibt unter der Wandkrone (Budget-Test), mehr ist
	# durch die Scheibe ohnehin nicht sichtbar.
	quad.size = Vector2(_laenge, 2.3)
	_blitz_mat = StandardMaterial3D.new()
	_blitz_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_blitz_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blitz_mat.albedo_color = Color(HomeLicht.BLITZ_FARBE, 0.0)
	quad.material = _blitz_mat
	_blitz_tafel.mesh = quad
	_blitz_tafel.position = Vector3(0.0, 1.15, -3.4)
	_blitz_tafel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blitz_tafel.visible = false
	add_child(_blitz_tafel)


func _on_blitz_gezuendet(_staerke: float) -> void:
	_blitz_rest = HomeLicht.BLITZ_DAUER_S
	set_process(true)


## Rasen im Belag des Spieler-Grundstücks (derselbe wie im echten Garten).
func _baue_boden() -> void:
	var boden := MeshInstance3D.new()
	boden.name = "Rasen"
	var box := BoxMesh.new()
	box.size = Vector3(_laenge, 0.1, TIEFE + 2.6)
	boden.mesh = box
	boden.material_override = HouseExterior.teil_material("grund", _style)
	boden.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	boden.position = Vector3(0.0, -0.05, -0.8)
	add_child(boden)


## Hecke am hinteren Gartenrand — hoch genug, dass sie durchs Fenster
## (Brüstung 1.28 m) auch aus Augenhöhe als grüne Wand sichtbar ist.
func _baue_hecke() -> void:
	var hecke := MeshInstance3D.new()
	hecke.name = "Hecke"
	var box := BoxMesh.new()
	box.size = Vector3(_laenge, 1.5, 0.5)
	hecke.mesh = box
	hecke.material_override = CustomizeMaterials.surface("rasen", "tannengruen")
	hecke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hecke.position = Vector3(0.0, 0.75, -2.9)
	add_child(hecke)


## Zwei Beete mit Möhren — der Garten „lebt" hinterm Fenster.
func _baue_beete() -> void:
	for i in 2:
		var x := -1.6 + i * 3.4
		var beet := HomeProps.box(Vector3(1.5, 0.14, 0.9), "holz_dunkel")
		beet.position = Vector3(x, 0.07, -1.1)
		add_child(beet)
		var crop := HomeProps.modell_glb(str(HomeProps.CROP_GLBS.get("carrot", "")), 0.3)
		if crop != null:
			crop.position = Vector3(x, 0.14, -1.1)
			add_child(crop)


## Blumen, Büsche und ein Bäumchen als MultiMesh (LOD spart Fern-Kosten).
func _baue_gruen() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_laenge * 100.0)
	var blumen: Array[Transform3D] = []
	for i in 10:
		var pos := Vector3(-_laenge * 0.42 + i * _laenge * 0.084, 0.0, -2.35)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * 0.55)
		blumen.append(Transform3D(basis, pos))
	var blumen_glbs: Array[String] = ["flower_redA", "flower_yellowA"]
	for i in blumen_glbs.size():
		var teil: Array[Transform3D] = []
		for j in blumen.size():
			if j % blumen_glbs.size() == i:
				teil.append(blumen[j])
		HomeProps.multi_glb(
			self, "%s/natur/%s.glb" % [ASSETS, blumen_glbs[i]], teil, "Blumen%d" % i, 60.0
		)
	var bueshe: Array[Transform3D] = []
	for i in 4:
		var pos := Vector3(-_laenge * 0.35 + i * _laenge * 0.24, 0.0, -2.0)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * 1.15)
		bueshe.append(Transform3D(basis, pos))
	HomeProps.multi_glb(self, "%s/natur/plant_bush.glb" % ASSETS, bueshe, "Busch", 70.0)
	# Baumreihe vor der Hecke — die Kronen füllen das Fenster mit Grün.
	for i in 3:
		var baum := HomeProps.modell_glb(
			"%s/natur/tree_default.glb" % ASSETS, MAX_HOEHE - 0.15 - 0.2 * float(i % 2)
		)
		if baum == null:
			break
		baum.position = Vector3(_laenge * (-0.3 + 0.29 * i), 0.0, -2.45)
		add_child(baum)


## Weiche Himmels-Rückwand wie beim Straßen-Diorama.
func _baue_himmel() -> void:
	var himmel := HomeProps.box(Vector3(_laenge, 6.0, 0.1), "glas")
	himmel.name = "Himmel"
	himmel.position = Vector3(0.0, 2.4, -3.6)
	add_child(himmel)


static func _diorama_position(wall: String, world_size: Vector2) -> Vector3:
	match wall:
		"N":
			return Vector3(world_size.x * 0.5, 0.0, -TIEFE)
		"S":
			return Vector3(world_size.x * 0.5, 0.0, world_size.y + TIEFE)
		"W":
			return Vector3(-TIEFE, 0.0, world_size.y * 0.5)
	return Vector3(world_size.x + TIEFE, 0.0, world_size.y * 0.5)


static func _diorama_yaw(wall: String) -> float:
	if wall == "W" or wall == "E":
		return PI / 2.0
	return 0.0
