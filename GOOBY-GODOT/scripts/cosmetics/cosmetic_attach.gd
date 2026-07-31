class_name CosmeticAttach
extends Node3D
## Hängt Cosmetics an den GoobyRig (CONTENT-A).
##
## Ein Knoten pro Rig, als Kind des Rigs. Er legt vier `BoneAttachment3D`-Anker
## an (Hut/Brille am `head`-Bone, Hals am `chest`, Rücken am `spine`) und hängt
## die prozeduralen Meshes von `CosmeticBuilders` dort hinein. Weil die Anker
## echte Bone-Attachments sind, machen Kopfdrehung, Hüpfen und jede Animation
## automatisch mit — es gibt keinen eigenen Nachzieh-Code.
##
## MASSSTAB: Die Builder rechnen im Rezept-Raum der Web-Referenz. Der Anker
## trägt die Umrechnung: Kopf-Anker ×0.7044 (RIG_SCALE × Kopfgruppe 1.08),
## Körper-Anker ×0.6522. Kein Builder rechnet selbst um.
##
## OHREN: `ear.L/R.01` stehen bei x = ±0.091 (Spitze ±0.130) und ragen bis
## y ≈ 0.84 — also DURCH die Ebene des Hut-Ankers (y ≈ 0.757). Die Hüte weichen
## deshalb in `HutBuilders` nach vorn aus; hier oben kommt nur die Morph-
## Korrektur dazu: längere Ohren heben den Hut minimal an.
##
## FELL ist kein Mesh: `apply_fell()` schreibt die drei Fellfarben in eine
## KOPIE der Palette-Textur und hängt sie als Surface-Override an das Mesh —
## das GLB-Material selbst bleibt unangetastet (sonst färbt sich jeder Gooby
## in jeder Szene mit um).
##
## W13B/GALAXIE (additiv): Fellfarben mit `params.shader == "galaxie"` laufen
## über denselben Pfad, bekommen aber statt des StandardMaterial-Duplikats
## ein ShaderMaterial (fell_galaxie.gdshader) mit derselben umgefärbten
## Palette — Sterne/Nebel nur auf den Fell-Zellen, Augen/Nase bleiben heil.
## Reduced-Motion friert den Shader ein (bewegung = 0.0).

## Bones, Anker-Positionen und Maßstäbe stehen alle in KoerperForm — dort
## liegen auch die Oberflächen-Radien, mit denen die Builder rechnen.
const BONES := KoerperForm.BONE

## Palette-Zellen (4×4-Raster, 64 px, Reihenfolge aus gooby_params.PALETTE_ORDER).
const PALETTE_GRID := 4
const PALETTE_ZELLE := 64
const FELL_ZELLEN := {"body": 0, "belly": 1, "earInner": 2}
## W13B: Premium-Fell-Shader (params.shader == "galaxie").
const GALAXIE_SHADER_PFAD := "res://assets/shaders/fell_galaxie.gdshader"

## Wie stark ein rundes Gooby (`charMorphs.chubby`) die Körperanker aufweitet.
const CHUBBY_WEITE := 0.18
## Wie stark lange Ohren (`charMorphs.ear_len`) den Hut anheben.
const OHR_HUB := 0.03
## Wie stark große Augen (`charMorphs.eye_scale`) die Brille mitwachsen lassen.
const AUGEN_WEITE := 0.3

## Dreh-/Schwenktempo der animierten Teile (Meta "animation" am Knoten).
const PROPELLER_SPEED := 8.5
const BALLON_SPEED := 1.35
const FLUEGEL_SPEED := 8.0

## Test-Hook (Muster wetter_fx.gd): -1 = AppSettings fragen, 0/1 = erzwingen.
var reduced_motion_override := -1

var _skeleton: Skeleton3D
var _mesh: MeshInstance3D
var _anker: Dictionary = {}  # kategorie -> BoneAttachment3D
var _getragen: Dictionary = {}  # kategorie -> Node3D (das gebaute Item)
var _ids: Dictionary = {}  # kategorie -> aktuell angelegte Item-Id
var _animiert: Array[Node3D] = []
var _fell_id := ""
var _zeit := 0.0
var _chubby := 0.0
var _ohr_len := 1.0
var _augen := 1.0


## Baut den Attach-Knoten in ein Rig (oder eine Szene, die eins enthält) und
## gibt ihn zurück. `null`, wenn da kein Skelett drin ist.
static func fuer_rig(rig: Node3D) -> CosmeticAttach:
	if rig == null:
		return null
	var attach := CosmeticAttach.new()
	attach.name = "CosmeticAttach"
	rig.add_child(attach)
	if not attach.verbinde(rig):
		attach.queue_free()
		return null
	return attach


## Sucht Skelett + Mesh im Rig und legt die Anker an. Muss laufen, bevor
## irgendetwas angelegt wird; `fuer_rig()` erledigt das selbst.
func verbinde(rig: Node3D) -> bool:
	_skeleton = _finde(rig, "Skeleton3D")
	_mesh = _finde(rig, "MeshInstance3D")
	if _skeleton == null:
		return false
	for kategorie: String in BONES:
		var idx := _skeleton.find_bone(str(BONES[kategorie]))
		if idx < 0:
			continue
		var anker := BoneAttachment3D.new()
		anker.name = "Anker_%s" % kategorie
		anker.bone_idx = idx
		anker.bone_name = str(BONES[kategorie])
		_skeleton.add_child(anker)
		var traeger := Node3D.new()
		traeger.name = "Sitz"
		anker.add_child(traeger)
		_anker[kategorie] = traeger
	_sitz_neu_setzen()
	return not _anker.is_empty()


## Angelegte Ausrüstung setzen: {kategorie: id}. Leere Id = Slot leeren.
## Unbekannte Ids landen als Platzhalter statt als Crash. Ist ein Item bereits
## angelegt, wird es NICHT neu gebaut (das Grid ruft das pro Tap auf).
func apply_equipped(map: Dictionary) -> void:
	for kategorie: String in CosmeticsCatalog.KATEGORIEN:
		var id := str(map.get(kategorie, ""))
		if kategorie == CosmeticsCatalog.FELL:
			apply_fell(id)
			continue
		_setze(kategorie, id)


## Ein einzelnes Item anlegen ("" = ablegen).
func apply_item(kategorie: String, id: String) -> void:
	if kategorie == CosmeticsCatalog.FELL:
		apply_fell(id)
		return
	_setze(kategorie, id)


## Fellfarbe setzen. "" oder unbekannt = Standard-Fell (Palette-Override weg).
func apply_fell(id: String) -> void:
	if id == _fell_id:
		return
	_fell_id = id
	if _mesh == null:
		return
	var def := CosmeticsCatalog.by_id(id)
	if def.is_empty() or def["kategorie"] != CosmeticsCatalog.FELL or bool(def["standard"]):
		_mesh.set_surface_override_material(0, null)
		return
	var material: Material = null
	var ist_galaxie := str(CosmeticParts.param(def, "shader", "")) == "galaxie"
	if ist_galaxie:
		material = _galaxie_material(def)
	if material == null:
		material = _palette_material(def)
	if material != null:
		_mesh.set_surface_override_material(0, material)
		# W15/VOICE2 (W13-Request): Galaxie-Fell angelegt → Gooby staunt
		# (None-sicher; ohne lebenden SeeleRunner bleibt es still).
		if ist_galaxie:
			SeeleRunner.kommentar_global("w13.galaxie")


## Charakter-Morphs übernehmen (`meta.charMorphs` aus dem Save):
## `chubby` weitet Hals-/Rückenanker, `ear_len` hebt den Hut, `eye_scale`
## lässt die Brille mitwachsen.
func set_morphs(chubby: float, ear_len := 1.0, eye_scale := 1.0) -> void:
	_chubby = clampf(chubby, 0.0, 1.0)
	_ohr_len = clampf(ear_len, 0.7, 1.4)
	_augen = clampf(eye_scale, 0.7, 1.4)
	_sitz_neu_setzen()


## Bequemer Weg aus dem GameState: Ausrüstung + Fell + Morphs in einem Rutsch.
func apply_from_state(game_state: Object) -> void:
	if game_state == null or not game_state.has_method("get_value"):
		return
	var morphs: Variant = game_state.get_value("meta.charMorphs", {})
	if morphs is Dictionary:
		set_morphs(
			float((morphs as Dictionary).get("chubby", 0.0)),
			float((morphs as Dictionary).get("ear_len", 1.0)),
			float((morphs as Dictionary).get("eye_scale", 1.0))
		)
	var slice: Variant = game_state.get_value("cosmetics", {})
	if slice is Dictionary:
		apply_equipped(CosmeticsState.equipped_map(slice))


## Aktuell angelegte Id einer Kategorie ("" = frei).
func getragene_id(kategorie: String) -> String:
	if kategorie == CosmeticsCatalog.FELL:
		return _fell_id
	return str(_ids.get(kategorie, ""))


## Alles ablegen (Vorschau-Reset).
func clear() -> void:
	for kategorie: String in _anker:
		_setze(kategorie, "")
	apply_fell("")


func _process(delta: float) -> void:
	if _animiert.is_empty():
		return
	_zeit += delta
	for node in _animiert:
		match str(node.get_meta("animation", "")):
			"propeller":
				node.rotation.z = _zeit * PROPELLER_SPEED
			"ballon":
				node.rotation.z = sin(_zeit * BALLON_SPEED) * 0.09
				node.rotation.x = cos(_zeit * BALLON_SPEED * 0.8) * 0.045
			"fluegel":
				node.rotation.y = sin(_zeit * FLUEGEL_SPEED) * 0.16 * signf(node.scale.x)


func _setze(kategorie: String, id: String) -> void:
	if str(_ids.get(kategorie, "")) == id:
		return
	var alt: Variant = _getragen.get(kategorie)
	if alt is Node3D:
		_animiert = _animiert.filter(
			func(node: Node3D) -> bool: return not (alt as Node3D).is_ancestor_of(node)
		)
		(alt as Node3D).queue_free()
	_getragen.erase(kategorie)
	_ids[kategorie] = id
	if id.is_empty() or not _anker.has(kategorie):
		return
	var def := CosmeticsCatalog.by_id(id)
	if def.is_empty() or def["kategorie"] != kategorie:
		_ids[kategorie] = ""
		return
	var item := CosmeticBuilders.build(def)
	if item == null:
		_ids[kategorie] = ""
		return
	(_anker[kategorie] as Node3D).add_child(item)
	_getragen[kategorie] = item
	_sammle_animierte(item)


## Setzt Position/Skalierung aller Anker aus Rezept-Maßen + Morphs neu.
func _sitz_neu_setzen() -> void:
	var tier := 1.0 + _chubby * CHUBBY_WEITE
	for kategorie: String in _anker:
		var traeger: Node3D = _anker[kategorie]
		var pos := KoerperForm.bone_versatz(kategorie)
		var skala := float(KoerperForm.ANKER_SCALE[kategorie])
		match kategorie:
			"hut":
				pos.y += (_ohr_len - 1.0) * OHR_HUB
				traeger.scale = Vector3.ONE * skala
			"brille":
				traeger.scale = Vector3.ONE * skala * (1.0 + (_augen - 1.0) * AUGEN_WEITE)
			_:
				# Runder Gooby: Hals-/Rückenteile weiten sich in x/z mit und
				# rutschen entsprechend weiter nach vorn bzw. hinten.
				pos.z *= tier
				traeger.scale = Vector3(skala * tier, skala, skala * tier)
		traeger.position = pos


func _sammle_animierte(item: Node3D) -> void:
	if item.has_meta("animation"):
		_animiert.append(item)
	for child in item.get_children():
		if child is Node3D:
			_sammle_animierte(child)


## Palette-Kopie mit den drei Fellfarben (linear kodiert wie im GLB).
func _palette_material(def: Dictionary) -> Material:
	var basis := _mesh.mesh.surface_get_material(0)
	if not (basis is StandardMaterial3D):
		return null
	var textur := _palette_textur(basis as StandardMaterial3D, def)
	if textur == null:
		return null
	var material := (basis as StandardMaterial3D).duplicate() as StandardMaterial3D
	material.albedo_texture = textur
	material.metallic = float(CosmeticParts.param(def, "metallic", 0.0))
	if material.metallic > 0.0:
		material.roughness = 0.45
	return material


## W13B: Galaxie-Fell — ShaderMaterial statt Palette-Duplikat. Nutzt dieselbe
## umgefärbte Palette (Fell-Zellen = die drei Katalogfarben), der Shader legt
## Nebel + Sterne NUR auf die Fell-Zellen. Reduced-Motion → statisch.
func _galaxie_material(def: Dictionary) -> Material:
	var basis := _mesh.mesh.surface_get_material(0)
	if not (basis is StandardMaterial3D):
		return null
	var textur := _palette_textur(basis as StandardMaterial3D, def)
	if textur == null:
		return null
	var shader := load(GALAXIE_SHADER_PFAD) as Shader
	if shader == null:
		return null
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("palette", textur)
	material.set_shader_parameter("bewegung", 0.0 if _reduced_motion() else 1.0)
	return material


## Umgefärbte Palette-Kopie (Fell-Zellen ← def.farben, linear wie im GLB).
func _palette_textur(basis: StandardMaterial3D, def: Dictionary) -> ImageTexture:
	var quelle := basis.albedo_texture
	if quelle == null:
		return null
	var img := quelle.get_image()
	if img == null:
		return null
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var farben: Array = def["farben"]
	var teile := ["body", "belly", "earInner"]
	for i in teile.size():
		if i >= farben.size():
			break
		var hex := str(farben[i])
		if not hex.is_valid_html_color():
			continue
		_male_zelle(img, int(FELL_ZELLEN[teile[i]]), Color(hex).srgb_to_linear())
	return ImageTexture.create_from_image(img)


func _reduced_motion() -> bool:
	if reduced_motion_override >= 0:
		return reduced_motion_override == 1
	var settings := get_node_or_null("/root/AppSettings")
	return settings != null and bool(settings.call("is_reduced_motion"))


func _male_zelle(img: Image, index: int, farbe: Color) -> void:
	var spalte := index % PALETTE_GRID
	var zeile := index / PALETTE_GRID
	img.fill_rect(
		Rect2i(spalte * PALETTE_ZELLE, zeile * PALETTE_ZELLE, PALETTE_ZELLE, PALETTE_ZELLE), farbe
	)


func _finde(node: Node, klass: String) -> Variant:
	if node.is_class(klass):
		return node
	for child in node.get_children():
		var found: Variant = _finde(child, klass)
		if found != null:
			return found
	return null
