extends Node3D
## 3D-Welt des Einkaufs-Surfs (Agent 3D-B): eine Pastell-Einkaufsstraße aus
## echten Kenney-City-Modellen — dieselbe Bauart wie die Web-Fassung
## (GOOBY/src/minigames/games/shoppingSurf.js), nur als MultiMesh-Band statt
## als N Szenenknoten.
##
## Achsen: x = Spur (Logik-Meter, unverändert), y = hoch, −z = vorne.
## Die Web-Fassung fährt nach +z; die Godot-Logik zählt Hindernisse mit
## negativem z nach vorne. Deshalb ist hier ALLES gespiegelt eingebaut —
## keine Zahl der Logik wird angefasst.
##
## Kulisse (recycelt, nie neu instanziert):
##   Straßen-/Gehweg-/Bordstein-Bänder, laufende Spurpunkte
##   Ladenzeile links/rechts + Pastell-Markisen darüber
##   Straßenmöbel (Bank, Hydrant, Busch) und Laternen
## Requisiten (pro Frame neu eingereiht, feste Pools):
##   Einkaufswagen, Kisten, Passanten, Markisen-Durchfahrten, Pfützen,
##   Bordsteinlücken, Münzen, Power-ups

const Models := preload("res://scripts/minigames/games/_3db_stage/model_bank.gd")
const MultiProp := preload("res://scripts/minigames/games/_3db_stage/multi_prop.gd")
const ScrollBand := preload("res://scripts/minigames/games/_3db_stage/scroll_band.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")

## Bandlänge des Kulissen-Laufbands (Web: LOOP_LEN) und Rückwärts-Grenze.
const LOOP_LEN := 121.0
const DESPAWN_Z := 8.0
## Straßenmaße aus der Web-Fassung (m).
const ROAD_W := 6.4
const WALK_X := 4.35
const WALK_W := 2.3
const CURB_X := 3.15
## Fassadenflucht: die Ladenfront steht bei |x| = 5.6, direkt hinter dem Gehweg.
const FACADE_X := 5.6
const SHOP_W := 9.0
const SHOP_STEP := 11.0
const DOT_STEP := 2.6
## Wimpelketten näher als das (Meter vor der Kamera) werden ausgeblendet —
## hochkant hing die nächste sonst formatfüllend im Bild.
const BUNTING_HIDE_Z := -13.0

## Straßenfarben der Web-Fassung (0xe8cfd6 rosiges Pflaster, 0xf6e7d7 Gehweg).
## Erst lagen sie zu hell (Straße = Himmel), dann zu tief (matschig-magenta).
## Diese Werte treffen den Web-Ton (rgb 182/154/147 Fahrbahn) und halten die
## Fahrbahn trotzdem klar dunkler als Gehweg und Himmel.
const ROSY := Color(0.88, 0.75, 0.76)
const CREAM := Color(0.93, 0.86, 0.77)
const CURB_COLOR := Color(0.76, 0.62, 0.65)

## Ladenzeile: die BUNTEN KayKit-Häuser der Web-Fassung. Die weißen
## Kenney-Häuser (assets/city/gebaeude) sahen unter Tageslicht wie eine
## Gipsschlucht aus — die Einkaufsstraße lebt von Rot/Ocker/Grün/Blau.
const KAY := "res://assets/minigames/shopping_surf/kaykit-city/"
const SHOPS: Array[String] = [
	KAY + "building_A_withoutBase.gltf",
	KAY + "building_B_withoutBase.gltf",
	KAY + "building_C_withoutBase.gltf",
	KAY + "building_D_withoutBase.gltf",
	KAY + "building_E_withoutBase.gltf",
	KAY + "building_F_withoutBase.gltf",
]
const PROPS: Array[String] = [
	KAY + "bench.gltf",
	KAY + "firehydrant.gltf",
	KAY + "bush.gltf",
	KAY + "trash_A.gltf",
]
const LAMP := KAY + "streetlight.gltf"
const CRATE := "res://assets/minigames/shopping_surf/car-kit/box.glb"
const AWNING := "res://assets/minigames/shopping_surf/city-kit-commercial/detail-awning-wide.glb"
## Kleines Vordach + Kistenpaar = Marktstand am Gehwegrand (MP-F).
const AWNING_SMALL := "res://assets/minigames/shopping_surf/city-kit-commercial/detail-awning.glb"
const STALL_BOX_A := KAY + "box_A.gltf"
const STALL_BOX_B := KAY + "box_B.gltf"
const COIN := "res://assets/minigames/shopping_surf/toy-car-kit/item-coin-gold.glb"
## Ferne Dachlinie hinter der Ladenzeile — rosiger Dunst statt leerem Himmel.
const SKYLINE_TINT := Color(0.93, 0.78, 0.83)
## Pastelltöne der Ladenmarkisen (Web: canopyMats).
const CANOPY_TINTS: Array[Color] = [
	Color(1.0, 0.56, 0.67),
	Color(0.48, 0.82, 0.66),
	Color(1.0, 0.79, 0.3),
	Color(0.49, 0.72, 1.0),
	Color(0.77, 0.56, 1.0),
]

var band: RefCounted

var cart_prop: Node3D
var crate_prop: Node3D
var npc_prop: Node3D
var awning_prop: Node3D
var puddle_prop: Node3D
var gap_prop: Node3D
var coin_prop: Node3D
var power_prop: Node3D


func build(awning_gap: float) -> void:
	_build_ground()
	_build_band()
	_build_props(awning_gap)


## Draw-Calls der gesamten Welt (Kulisse + Requisiten, ohne Gooby/Partikel).
func layer_count() -> int:
	var total: int = band.call("layer_count") + 5
	for prop in _all_props():
		total += prop.call("layer_count")
	return total


func begin_props() -> void:
	for prop in _all_props():
		prop.call("begin")


func flush_props() -> void:
	for prop in _all_props():
		prop.call("flush")


## Ein Hindernis einreihen. `spin`/`bob` sind reine Zierde.
func push_obstacle(kind: String, x: float, z: float, half_w: float, spin: float) -> void:
	match kind:
		"cart":
			cart_prop.call("push", _pose(x, 0.0, z, sin(spin) * 0.12))
		"crate":
			crate_prop.call("push", _pose(x, 0.0, z, spin * 0.2))
		"npc":
			npc_prop.call("push", _pose(x, 0.0, z, PI * 0.5))
		"awning":
			awning_prop.call("push", _stretched(x, z, half_w))
		"puddle":
			puddle_prop.call("push", _pose(x, 0.0, z, spin * 0.05))
		_:
			gap_prop.call("push", _pose(0.0, 0.0, z, 0.0))


func push_coin(x: float, y: float, z: float, spin: float) -> void:
	coin_prop.call("push", _pose(x, y, z, spin))


func push_power(x: float, y: float, z: float, spin: float, tint: Color) -> void:
	power_prop.call("push", _pose(x, y, z, spin), tint)


func _all_props() -> Array[Node3D]:
	return [
		cart_prop,
		crate_prop,
		npc_prop,
		awning_prop,
		puddle_prop,
		gap_prop,
		coin_prop,
		power_prop,
	]


func _pose(x: float, y: float, z: float, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(x, y, z))


## Markise über mehreren Spuren: dieselbe Requisite, nur in x gestreckt.
func _stretched(x: float, z: float, half_w: float) -> Transform3D:
	var basis := Basis.IDENTITY.scaled(Vector3(maxf(0.6, half_w / 1.1), 1.0, 1.0))
	return Transform3D(basis, Vector3(x, 0.0, z))


func _build_ground() -> void:
	# Web §G4.4: EINE Pflastertextur trägt Fahrbahn und Gehweg — die Fugen
	# alle 4 m sind das, was die Straße als Straße lesbar macht.
	var seams := _pavement_texture()
	var road := Fx.ground(Vector2(ROAD_W, 240.0), ROSY, 0.0)
	_pave(road, seams, ROAD_W)
	road.position.z = -60.0
	add_child(road)
	for sx: float in [-WALK_X, WALK_X]:
		var walk := Fx.ground(Vector2(WALK_W, 240.0), CREAM, 0.02)
		_pave(walk, seams, WALK_W)
		walk.position = Vector3(sx, 0.02, -60.0)
		add_child(walk)
	for sx: float in [-CURB_X, CURB_X]:
		var curb := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.16, 0.09, 240.0)
		mesh.material = Fx.flat(CURB_COLOR)
		curb.mesh = mesh
		curb.position = Vector3(sx, 0.045, -60.0)
		curb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(curb)


## 64×64-Pflaster: weiß mit dunklen Fugen alle 16 px. Die Textur TÖNT nur, die
## Grundfarbe steckt weiter im Material (wie in der Web-Fassung).
func _pavement_texture() -> ImageTexture:
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	# Mit Deckkraft 0,16 waren die Fugen auf dem rosa Belag praktisch weiß —
	# das Nahfeld lag als leere Fläche im Bild. Deutlicher gefugt liest die
	# Straße auch direkt vor Gooby noch als Pflaster.
	# ACHTUNG: `dunkel.blend(WEISS)` legt WEISS ÜBER Dunkel und ergibt reines
	# Weiß — die Fugen waren dadurch schlicht nicht vorhanden. `lerp` mischt in
	# die richtige Richtung.
	var seam := Color(0.29, 0.23, 0.21)
	for y in range(0, 64, 16):
		img.fill_rect(Rect2i(0, y, 64, 2), Color.WHITE.lerp(seam, 0.3))
	img.fill_rect(Rect2i(31, 0, 2, 64), Color.WHITE.lerp(seam, 0.12))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Pflastertextur auf eine Bodenplatte legen; 4-m-Kachel wie im Web.
func _pave(plane: MeshInstance3D, tex: Texture2D, width: float) -> void:
	var mat := (plane.mesh as PlaneMesh).material as StandardMaterial3D
	mat.albedo_texture = tex
	mat.uv1_scale = Vector3(maxf(1.0, width / 4.0), 60.0, 1.0)
	# Ohne anisotrope Filterung flimmern die Fugen im flachen Blickwinkel.
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


func _build_band() -> void:
	band = ScrollBand.new(LOOP_LEN, DESPAWN_Z)
	_build_dots()
	_build_crosswalks()
	_build_manholes()
	_build_ground_confetti()
	_build_shops()
	_build_skyline()
	_build_street_furniture()
	_build_market_stalls()


## Zebrastreifen quer über die Fahrbahn — alle ~40 m ein Taktschlag, der die
## Straße in Blöcke gliedert (vorher: EIN Fugenmuster in Endlosschleife).
func _build_crosswalks() -> void:
	var stripe := BoxMesh.new()
	stripe.size = Vector3(0.72, 0.022, 1.7)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 5:
		var sx := (float(k) - 2.0) * 1.3
		tool.append_from(stripe, 0, Transform3D(Basis.IDENTITY, Vector3(sx, 0.0, 0.0)))
	tool.set_material(Fx.flat(Color(0.99, 0.97, 0.93)))
	var mesh := tool.commit()
	var prop := _prop([{"mesh": mesh, "xform": Transform3D.IDENTITY}], 4)
	prop.call("set_shadows", false)
	var items: Array = []
	for i in 3:
		items.append({"x": 0.0, "y": 0.012, "z": -float(i) * (LOOP_LEN / 3.0) - 17.0})
	band.call("add_group", prop, items)


## Gullydeckel auf der Fahrbahn — kleine dunkle Anker fürs Nahfeld, das
## vorher als leere rosa Fläche ein Drittel des Hochformats füllte.
func _build_manholes() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.42
	mesh.bottom_radius = 0.42
	mesh.height = 0.016
	mesh.radial_segments = 14
	mesh.rings = 1
	mesh.material = Fx.flat(Color(0.52, 0.42, 0.44), 0.7)
	var prop := _prop([{"mesh": mesh, "xform": Transform3D.IDENTITY}], 8)
	prop.call("set_shadows", false)
	var items: Array = []
	for i in 6:
		var sx := fmod(float(i) * 2.17, 4.4) - 2.2
		items.append({"x": sx, "y": 0.012, "z": -float(i) * (LOOP_LEN / 6.0) - 7.0})
	band.call("add_group", prop, items)


## Konfetti-Sticker/Blütenblätter auf Fahrbahn und Gehweg (W17, Audit C §4):
## deterministische Farbtupfer fürs NAHFELD — hochkant lag unter Gooby sonst
## nacktes Rosa-Pflaster über die halbe Bildhöhe. Streuung über den goldenen
## Schnitt statt RNG (kein Zufallsstrom, bit-gleiche Läufe bleiben es).
func _build_ground_confetti() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.2, 0.014, 0.28)
	var mat := Fx.flat(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	var count := 30
	var prop := _prop([{"mesh": mesh, "xform": Transform3D.IDENTITY}], count + 4, true)
	prop.call("set_shadows", false)
	var items: Array = []
	for i in count:
		var frac := fmod(float(i) * 0.61803, 1.0)
		# Zwei von drei Tupfern liegen auf der Fahrbahn, jeder dritte auf dem
		# Gehweg — dort spielen zwar keine Requisiten, aber das Auge schon.
		# Der Gehweg-Versatz streut SYMMETRISCH um die Gehwegmitte (±0,6 m),
		# sonst rutschte die linke Reihe auf die Fahrbahn statt aufs Pflaster.
		var x := lerpf(-2.9, 2.9, frac)
		if i % 3 == 2:
			x = (WALK_X - 0.7 + (frac - 0.5) * 1.2) * (1.0 if i % 2 == 0 else -1.0)
		(
			items
			. append(
				{
					"x": x,
					"y": 0.032,
					"z": -fmod(float(i) * (LOOP_LEN / float(count)) + frac * 3.0, LOOP_LEN),
					"yaw": frac * TAU,
					"color": CANOPY_TINTS[i % CANOPY_TINTS.size()],
				}
			)
		)
	band.call("add_group", prop, items)


## Ferne Hochhaus-Dachlinie HINTER der Ladenzeile: dieselben KayKit-Häuser,
## rosig getönt und hochskaliert — im Hochformat stand über den Läden sonst
## nur leerer Himmel.
func _build_skyline() -> void:
	var tint := Fx.flat(SKYLINE_TINT, 1.0)
	var rows := int(LOOP_LEN / SHOP_STEP)
	for i in 3:
		var prop := _prop(Models.parts(SHOPS[i * 2], SHOP_W), 6, false, tint)
		prop.call("set_shadows", false)
		var items: Array = []
		for row in rows:
			for side: int in [-1, 1]:
				if (row + (1 if side > 0 else 0)) % 3 != i:
					continue
				var stretch := 1.5 + 0.5 * float((row + i) % 3)
				(
					items
					. append(
						{
							"x": side * (FACADE_X + 8.5),
							"z": -row * SHOP_STEP - 8.0,
							"yaw": -PI * 0.5 if side > 0 else PI * 0.5,
							"scale": Vector3(1.3, stretch, 1.3),
						}
					)
				)
		band.call("add_group", prop, items)


## Marktstände am Gehwegrand: Kistenpaar unter kleinem Vordach — die
## „Einkaufsstraße" bekommt Handel, nicht nur Fassade.
func _build_market_stalls() -> void:
	var parts: Array = []
	for entry: Dictionary in Models.parts(STALL_BOX_A, 0.9):
		parts.append(entry)
	var shift := Transform3D(Basis(Vector3.UP, 0.5), Vector3(0.55, 0.0, 0.35))
	for entry: Dictionary in Models.parts(STALL_BOX_B, 0.7):
		parts.append({"mesh": entry["mesh"], "xform": shift * (entry["xform"] as Transform3D)})
	var roof_lift := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.25, 1.5, 0.1))
	for entry: Dictionary in Models.parts(AWNING_SMALL, 1.9, false):
		parts.append({"mesh": entry["mesh"], "xform": roof_lift * (entry["xform"] as Transform3D)})
	var prop := _prop(parts, 4)
	var items: Array = []
	for i in 3:
		var side := -1.0 if i % 2 == 0 else 1.0
		(
			items
			. append(
				{
					"x": side * 4.2,
					"z": -float(i) * (LOOP_LEN / 3.0) - 28.0,
					"yaw": side * PI * 0.5,
				}
			)
		)
	band.call("add_group", prop, items)


## Laufende Spurpunkte auf der Mittellinie — sie verkaufen das Tempo.
func _build_dots() -> void:
	# Flache Striche statt Zylinderknöpfe: als Knöpfe lasen sie sich wie
	# hingeworfene Kaugummis auf der Fahrbahn.
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.1, 0.02, 0.9)
	mesh.material = Fx.flat(Color(1.0, 0.98, 0.95))
	var count := int(LOOP_LEN / DOT_STEP)
	var prop := _prop([{"mesh": mesh, "xform": Transform3D.IDENTITY}], count * 2 + 4)
	var items: Array = []
	for i in count:
		for sx: float in [-1.6, 1.6]:
			items.append({"x": sx, "y": 0.025, "z": DESPAWN_Z - i * DOT_STEP})
	band.call("add_group", prop, items)


func _build_shops() -> void:
	var rows := int(LOOP_LEN / SHOP_STEP)
	for i in SHOPS.size():
		var size := Models.fitted_size(SHOPS[i], SHOP_W)
		# Die Modelle sind unterschiedlich tief; nach der 90°-Drehung wird aus
		# der Tiefe die Straßenfront. Wir schieben jede Fassade auf |x| = 5.6,
		# sonst verschlucken tiefe Häuser den Gehweg (Web-FIX-3D).
		var inset := size.z * 0.5
		var prop := _prop(Models.parts(SHOPS[i], SHOP_W), 8)
		# Die Ladenzeile wirft keinen Schatten: die flache Morgensonne legte
		# sonst eine harte Diagonale quer über die halbe Fahrbahn, und genau
		# dort laufen Münzen und Hindernisse. Das Web rendert dort gar keine
		# Schattenkarte — Gooby und die Requisiten behalten ihre.
		prop.call("set_shadows", false)
		var items: Array = []
		for row in rows:
			for side: int in [-1, 1]:
				if (row * 2 + (1 if side > 0 else 0)) % SHOPS.size() != i:
					continue
				(
					items
					. append(
						{
							"x": side * (FACADE_X + inset),
							"z": -row * SHOP_STEP - 3.0,
							"yaw": -PI * 0.5 if side > 0 else PI * 0.5,
						}
					)
				)
		band.call("add_group", prop, items)
	_build_canopies(rows)


## Pastellstreifen-Markisen über dem Gehweg — der „Einkaufsstraße"-Lesbarkeit.
func _build_canopies(rows: int) -> void:
	var mat := Fx.flat(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	# Die Markise ragt 1,3 m aus der Fassade und ist 3 m BREIT (entlang der
	# Straße). Vorher war es andersherum: 3,4 m weit in die Fahrbahn hinein,
	# nur 1,1 m breit — im Bild lagen dann bunte Balken QUER über der Straße.
	var deck := BoxMesh.new()
	deck.size = Vector3(1.3, 0.14, 3.0)
	deck.material = mat
	# Ohne Blende las die Markise als schwebendes Brett; der senkrechte Saum
	# an der Außenkante macht daraus ein Vordach.
	var skirt := BoxMesh.new()
	skirt.size = Vector3(0.1, 0.34, 3.0)
	skirt.material = mat
	var parts: Array = [{"mesh": deck, "xform": Transform3D.IDENTITY}]
	for sx: float in [-0.6, 0.6]:
		parts.append({"mesh": skirt, "xform": Transform3D(Basis.IDENTITY, Vector3(sx, -0.2, 0.0))})
	for i in CANOPY_TINTS.size():
		var prop := _prop(parts, 8, true)
		var items: Array = []
		for row in rows:
			for side: int in [-1, 1]:
				if (row * 2 + (1 if side > 0 else 0)) % CANOPY_TINTS.size() != i:
					continue
				(
					items
					. append(
						{
							"x": side * 4.9,
							"y": 2.5,
							"z": -row * SHOP_STEP - 3.0,
							"color": CANOPY_TINTS[i],
						}
					)
				)
		band.call("add_group", prop, items)
	_build_bunting(rows)


## Wimpelketten quer über die Straße — das Markenbild der Web-Fassung. Sie
## schließen die Gasse nach oben und geben dem Tempo einen Taktschlag.
func _build_bunting(rows: int) -> void:
	var cord := BoxMesh.new()
	cord.size = Vector3(FACADE_X * 2.0, 0.05, 0.05)
	cord.material = Fx.flat(Color(0.96, 0.95, 0.94))
	var cord_prop := _prop([{"mesh": cord, "xform": Transform3D.IDENTITY}], 8)
	cord_prop.call("set_shadows", false)
	var cords: Array = []
	# Die neun Wimpel einer Kette werden zu EINEM Mesh verschmolzen. Als neun
	# Einzelteile kostete jede Kette zehn Draw-Calls — die Wimpel allein
	# sprengten das Perf-Budget fast so weit wie die ganze Ladenzeile.
	var flags := _flag_row_mesh()
	for i in CANOPY_TINTS.size():
		var prop := _prop([{"mesh": flags, "xform": Transform3D.IDENTITY}], 4, true)
		prop.call("set_shadows", false)
		var items: Array = []
		for row in rows:
			if row % CANOPY_TINTS.size() != i:
				continue
			var at := {"x": 0.0, "y": 4.6, "z": -row * SHOP_STEP - 8.0}
			cords.append(at)
			var tinted := at.duplicate()
			tinted["color"] = CANOPY_TINTS[i]
			items.append(tinted)
		band.call("add_group", prop, items, BUNTING_HIDE_Z)
	band.call("add_group", cord_prop, cords, BUNTING_HIDE_Z)


## Neun Wimpel als ein Mesh (Prismen auf dem Kopf, unter der Schnur hängend).
func _flag_row_mesh() -> ArrayMesh:
	var flag := PrismMesh.new()
	flag.size = Vector3(0.44, 0.5, 0.02)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var flip := Basis(Vector3.BACK, PI)
	for k in 9:
		var fx := (float(k) - 4.0) * (FACADE_X * 2.0 / 9.0)
		tool.append_from(flag, 0, Transform3D(flip, Vector3(fx, -0.3, 0.0)))
	var mat := Fx.flat(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tool.set_material(mat)
	return tool.commit()


func _build_street_furniture() -> void:
	for i in PROPS.size():
		var target := 0.9
		if PROPS[i].ends_with("bench.gltf"):
			target = 0.6
		elif PROPS[i].ends_with("trash_A.gltf"):
			target = 0.72
		var prop := _prop(Models.parts_by_height(PROPS[i], target), 6)
		var items: Array = []
		for k in 8:
			if k % PROPS.size() != i:
				continue
			var side := -1.0 if k % 2 == 0 else 1.0
			(
				items
				. append(
					{
						"x": side * 4.1,
						"z": -k * (LOOP_LEN / 8.0) - 6.0,
						"yaw": side * PI * 0.5,
					}
				)
			)
		band.call("add_group", prop, items)

	var lamp := _prop(Models.parts_by_height(LAMP, 3.1), 8)
	var lamp_items: Array = []
	for i in 6:
		var side := -1.0 if i % 2 == 0 else 1.0
		lamp_items.append(
			{"x": side * 3.7, "z": -i * (LOOP_LEN / 6.0) - 1.5, "yaw": side * PI * 0.5}
		)
	band.call("add_group", lamp, lamp_items)


func _build_props(awning_gap: float) -> void:
	cart_prop = _prop(_cart_parts(), 10)
	crate_prop = _prop(Models.parts(CRATE, 1.15), 10)
	npc_prop = _prop(_npc_parts(), 8)
	awning_prop = _prop(_awning_parts(awning_gap), 6)
	puddle_prop = _prop(_puddle_parts(), 8)
	gap_prop = _prop(_gap_parts(), 4)
	coin_prop = _prop(Models.parts(COIN, 0.42, false), 40)
	var tint := Fx.glow(Color.WHITE, 1.4)
	tint.vertex_color_use_as_albedo = true
	power_prop = _prop(_power_parts(), 6, true, tint)


## Einkaufswagen: Korb, Ware, Griff — wie im Web aus einfachen Kästen.
func _cart_parts() -> Array:
	var basket := BoxMesh.new()
	basket.size = Vector3(0.95, 0.62, 0.95)
	basket.material = Fx.flat(Color(0.8, 0.85, 0.9))
	var goods := BoxMesh.new()
	goods.size = Vector3(0.7, 0.3, 0.7)
	goods.material = Fx.flat(Color(1.0, 0.7, 0.78))
	var handle := BoxMesh.new()
	handle.size = Vector3(1.0, 0.06, 0.06)
	handle.material = Fx.flat(Color(0.29, 0.23, 0.21))
	return [
		{"mesh": basket, "xform": Transform3D(Basis.IDENTITY, Vector3(0.0, 0.42, 0.0))},
		{"mesh": goods, "xform": Transform3D(Basis.IDENTITY, Vector3(0.0, 0.86, 0.0))},
		{"mesh": handle, "xform": Transform3D(Basis.IDENTITY, Vector3(0.0, 0.82, 0.5))},
	]


## Passant: Rumpf + Kopf, bewusst schlicht (er quert nur die Straße).
func _npc_parts() -> Array:
	var body := CapsuleMesh.new()
	body.radius = 0.22
	body.height = 0.95
	body.radial_segments = 10
	body.rings = 4
	body.material = Fx.flat(Color(0.42, 0.53, 0.78))
	var head := SphereMesh.new()
	head.radius = 0.19
	head.height = 0.38
	head.radial_segments = 12
	head.rings = 7
	head.material = Fx.flat(Color(0.96, 0.83, 0.71))
	return [
		{"mesh": body, "xform": Transform3D(Basis.IDENTITY, Vector3(0.0, 0.48, 0.0))},
		{"mesh": head, "xform": Transform3D(Basis.IDENTITY, Vector3(0.0, 1.08, 0.0))},
	]


## Markisen-Durchfahrt: das Kenney-Vordach auf Kopfhöhe plus zwei Pfosten.
func _awning_parts(gap_y: float) -> Array:
	var out := Models.parts(AWNING, 2.2, false)
	var lift := Transform3D(Basis.IDENTITY, Vector3(0.0, gap_y + 0.28, 0.0))
	var shifted: Array = []
	for entry: Dictionary in out:
		shifted.append({"mesh": entry["mesh"], "xform": lift * (entry["xform"] as Transform3D)})
	var post := BoxMesh.new()
	post.size = Vector3(0.09, gap_y + 0.3, 0.09)
	post.material = Fx.flat(Color(0.69, 0.33, 0.18))
	for sx: float in [-1.05, 1.05]:
		(
			shifted
			. append(
				{
					"mesh": post,
					"xform": Transform3D(Basis.IDENTITY, Vector3(sx, (gap_y + 0.3) * 0.5, 0.0)),
				}
			)
		)
	return shifted


func _puddle_parts() -> Array:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.62
	mesh.bottom_radius = 0.62
	mesh.height = 0.02
	mesh.radial_segments = 14
	mesh.rings = 1
	mesh.material = Fx.glass(Color(0.56, 0.78, 0.91, 0.75))
	return [{"mesh": mesh, "xform": Transform3D(Basis.IDENTITY, Vector3(0.0, 0.04, 0.0))}]


func _gap_parts() -> Array:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(ROAD_W, 0.5, 0.9)
	mesh.material = Fx.flat(Color(0.23, 0.19, 0.21))
	return [{"mesh": mesh, "xform": Transform3D(Basis.IDENTITY, Vector3(0.0, -0.24, 0.0))}]


## Power-up: leuchtender Würfel, Farbe kommt pro Exemplar (MultiMesh-Farben).
func _power_parts() -> Array:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.42, 0.42, 0.42)
	return [{"mesh": mesh, "xform": Transform3D.IDENTITY}]


func _prop(parts: Array, cap: int, colored := false, material: Material = null) -> Node3D:
	var node: Node3D = MultiProp.new()
	add_child(node)
	node.call("build", parts, cap, colored, material)
	return node
