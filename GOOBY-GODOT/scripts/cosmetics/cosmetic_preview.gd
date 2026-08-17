class_name CosmeticPreview
extends Node
## Vorschau-Bäckerei für das Garderoben-Grid (CONTENT-A).
##
## Die Items sind prozedurale Meshes — es gibt also KEINE Icon-PNGs, die man
## ins Grid legen könnte, und 92 gleichzeitige SubViewports wären Wahnsinn.
## Stattdessen rendert dieser Knoten EIN geteiltes 3D-Viewport und backt die
## Items nacheinander in `ImageTexture`s (max. `PRO_FRAME` pro Frame, damit das
## Aufklappen eines Tabs nicht ruckelt). Fertige Bilder liegen im statischen
## Cache und überleben Tab-Wechsel.
##
## Fell hat kein Mesh: dafür kommt ein gemaltes Drei-Farb-Plättchen
## (Körper/Bauch/Ohr) direkt aus den Katalogfarben.

signal fertig(id: String, textur: Texture2D)

const GROESSE := 192
const PRO_FRAME := 3
## Blickrichtung auf das Teil (leicht von vorn/oben/rechts).
const BLICK := Vector3(0.55, 0.42, 1.0)

static var _cache: Dictionary = {}

var _viewport: SubViewport
var _kamera: Camera3D
var _halter: Node3D
var _warteschlange: Array[String] = []
var _laeuft := false
var _wird_abgebaut := false
var _aktuelle_id := ""
var _aktuelles_item: Node3D


## Fertige Textur ODER null — dann wird sie in Auftrag gegeben und kommt
## später per `fertig`-Signal.
func hole(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var def := CosmeticsCatalog.by_id(id)
	if def.is_empty():
		return null
	if def["kategorie"] == CosmeticsCatalog.FELL:
		var swatch := _fell_plaettchen(def)
		_cache[id] = swatch
		return swatch
	if not _warteschlange.has(id):
		_warteschlange.append(id)
	return null


static func leere_cache() -> void:
	_cache.clear()


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(GROESSE, GROESSE)
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.own_world_3d = true
	add_child(_viewport)
	var welt := Node3D.new()
	_viewport.add_child(welt)
	_halter = Node3D.new()
	welt.add_child(_halter)
	_kamera = Camera3D.new()
	_kamera.projection = Camera3D.PROJECTION_ORTHOGONAL
	welt.add_child(_kamera)
	_kamera.current = true
	var sonne := DirectionalLight3D.new()
	sonne.rotation_degrees = Vector3(-35.0, 32.0, 0.0)
	sonne.light_energy = 1.1
	welt.add_child(sonne)
	var fuell := DirectionalLight3D.new()
	fuell.rotation_degrees = Vector3(-8.0, -145.0, 0.0)
	fuell.light_energy = 0.55
	welt.add_child(fuell)
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AcTokens.PAPER
	env.ambient_light_energy = 1.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	welt.add_child(world_env)
	set_process(true)


func _process(_delta: float) -> void:
	if _laeuft or _warteschlange.is_empty():
		return
	_starte_naechstes()


func _exit_tree() -> void:
	_wird_abgebaut = true
	_warteschlange.clear()
	var callback := Callable(self, "_on_render_abgeschlossen")
	if RenderingServer.frame_post_draw.is_connected(callback):
		RenderingServer.frame_post_draw.disconnect(callback)
	_aktuelles_item = null
	_aktuelle_id = ""
	_laeuft = false


## Startet höchstens einen Render pro Frame. Die alte await-Kette hielt beim
## Abbau sowohl `_backe` als auch den aufrufenden Stapel als
## GDScriptFunctionState fest, falls `frame_post_draw` nicht mehr kam.
## Der Callback-Zustandsautomat besitzt keine suspendierte Coroutine.
func _starte_naechstes() -> void:
	for _i in PRO_FRAME:
		if _wird_abgebaut or _warteschlange.is_empty():
			return
		var id: String = _warteschlange.pop_front()
		if _cache.has(id):
			continue
		var item := _baue_item(id)
		if item == null:
			continue
		_aktuelle_id = id
		_aktuelles_item = item
		_laeuft = true
		_halter.add_child(item)
		_rahme(item)
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		RenderingServer.frame_post_draw.connect(_on_render_abgeschlossen, CONNECT_ONE_SHOT)
		return


## Unterklassen ersetzen nur den Modellbau; Render-Lifecycle und Teardown
## bleiben zentral und damit für Cosmetics, Futter und Craft identisch.
func _baue_item(id: String) -> Node3D:
	return CosmeticBuilders.build_id(id)


func _on_render_abgeschlossen() -> void:
	if _wird_abgebaut:
		return
	var id := _aktuelle_id
	var item := _aktuelles_item
	var bild := _viewport.get_texture().get_image()
	_aktuelle_id = ""
	_aktuelles_item = null
	_laeuft = false
	if item != null and is_instance_valid(item):
		item.queue_free()
	if bild == null:
		return
	var textur := ImageTexture.create_from_image(bild)
	_cache[id] = textur
	fertig.emit(id, textur)


## Kamera so stellen, dass genau dieses Teil das Bild füllt.
func _rahme(item: Node3D) -> void:
	var box := _aabb(item, Transform3D.IDENTITY)
	if box.size.length() < 0.0001:
		box = AABB(Vector3(-0.1, -0.1, -0.1), Vector3(0.2, 0.2, 0.2))
	var mitte := box.get_center()
	var radius := maxf(0.05, box.size.length() * 0.5)
	_kamera.size = radius * 2.1
	_kamera.near = 0.01
	_kamera.far = radius * 12.0
	_kamera.look_at_from_position(mitte + BLICK.normalized() * radius * 4.0, mitte, Vector3.UP)


static func _aabb(node: Node3D, eltern: Transform3D) -> AABB:
	var lokal := eltern * node.transform
	var box := AABB()
	var erste := true
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		box = lokal * (node as MeshInstance3D).mesh.get_aabb()
		erste = false
	for child in node.get_children():
		if not (child is Node3D):
			continue
		var kind := _aabb(child as Node3D, lokal)
		if kind.size.length() < 0.0001:
			continue
		box = kind if erste else box.merge(kind)
		erste = false
	return box


## Fell-Plättchen: drei Streifen in Körper-/Bauch-/Ohrfarbe.
static func _fell_plaettchen(def: Dictionary) -> Texture2D:
	var bild := Image.create(GROESSE, GROESSE, false, Image.FORMAT_RGBA8)
	bild.fill(Color(0, 0, 0, 0))
	var farben: Array = def["farben"]
	var mitte := Vector2(GROESSE, GROESSE) * 0.5
	var radius := float(GROESSE) * 0.42
	for y in GROESSE:
		for x in GROESSE:
			var p := Vector2(float(x), float(y))
			if p.distance_to(mitte) > radius:
				continue
			var index := 0
			if p.y > mitte.y + radius * 0.28:
				index = 1
			elif p.x > mitte.x + radius * 0.3 and p.y < mitte.y:
				index = 2
			var hex := str(farben[index]) if index < farben.size() else "#F6EAD7"
			bild.set_pixel(x, y, Color(hex) if hex.is_valid_html_color() else Color("#F6EAD7"))
	return ImageTexture.create_from_image(bild)
