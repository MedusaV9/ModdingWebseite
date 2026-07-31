class_name FuetterModelle
extends RefCounted
## W14/FRIDGE — Speise-Id → 3D-Modell fürs Regal-Grid und die Mampf-Sequenz.
## Primärquelle ist die REHWEI-Konvention `assets/city/essen/<id>.glb`
## (rehwei_sortiment.json `glb`-Feld zeigt dorthin); Ids ohne eigene Datei
## dort laufen über die ALIAS-Tabelle (deutsche Garten-Ids, W13-Umbenennungen,
## Minigame-Kits). Der Rest bekommt einen knuffigen Knubbel-Fallback in der
## passenden Farbe — die Auswahl darf NIE an einem fehlenden Asset scheitern.

const ESSEN_DIR := "res://assets/city/essen"

## Ids ohne eigenes GLB unter assets/city/essen/ → existierender Ersatz.
const ALIAS := {
	"donut-sprinkles": "res://assets/city/essen/donut.glb",
	"cinnamonRoll": "res://assets/city/essen/cinnamon-roll.glb",
	"cupcakePink": "res://assets/city/essen/cupcake-pink.glb",
	"tomate": "res://assets/city/essen/tomato.glb",
	"melone": "res://assets/city/essen/watermelon.glb",
	"salat": "res://assets/city/essen/salad.glb",
	"weltraumMoehre": "res://assets/city/essen/carrot.glb",
	"softServe": "res://assets/city/essen/ice-cream.glb",
	"pilz": "res://assets/minigames/veggie_chop/mushroom.glb",
	"waffle": "res://assets/minigames/purble_place/waffle.glb",
}

## Fallback-Knubbel-Farben (Park-Stall-Tints bzw. Garten-Farben).
const FALLBACK_FARBEN := {
	"cottonCandy": Color("#F781B0"),
	"ananas": Color("#F5C518"),
	"chili": Color("#E2564A"),
}
const FALLBACK_FARBE_NEUTRAL := Color("#F2B15C")


## Auflösbarer GLB-Pfad einer Speise ("" = keiner — Knubbel-Fallback).
static func glb_pfad(food_id: String) -> String:
	var direkt := "%s/%s.glb" % [ESSEN_DIR, food_id]
	if ResourceLoader.exists(direkt):
		return direkt
	var alias := str(ALIAS.get(food_id, ""))
	if not alias.is_empty() and ResourceLoader.exists(alias):
		return alias
	return ""


## Instanziertes Speise-Modell (GLB-Szene oder Knubbel) — nie null.
static func instanz(food_id: String) -> Node3D:
	var pfad := glb_pfad(food_id)
	if not pfad.is_empty():
		var scene: Variant = load(pfad)
		if scene is PackedScene:
			var node := (scene as PackedScene).instantiate()
			if node is Node3D:
				return node
			node.queue_free()
	return _knubbel(food_id)


## Knuffiger Snack-Knubbel: leicht gestauchte Kugel in Speise-Farbe.
static func _knubbel(food_id: String) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "SnackKnubbel"
	var mesh := MeshInstance3D.new()
	var kugel := SphereMesh.new()
	kugel.radius = 0.09
	kugel.height = 0.14
	var material := StandardMaterial3D.new()
	material.albedo_color = FALLBACK_FARBEN.get(food_id, FALLBACK_FARBE_NEUTRAL)
	material.roughness = 0.7
	kugel.material = material
	mesh.mesh = kugel
	mesh.position = Vector3(0.0, 0.07, 0.0)
	wurzel.add_child(mesh)
	return wurzel
