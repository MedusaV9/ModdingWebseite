extends RefCounted
## Endloses Streckenband (Agent 3D-B) für die Korridor-Spiele (runner,
## shopping_surf, harbor_hopper).
##
## DAS ist die geforderte Recycling-Regel: die Kulisse besteht aus einer FESTEN
## Menge Exemplare, die pro Frame nur ihr z verschieben. Wer hinter der Kamera
## herauswandert (z > despawn_z), springt um genau eine Bandlänge nach vorn.
## Es wird NIE etwas instanziert oder gelöscht — und weil jede Gruppe eine
## MultiProp ist, kostet die ganze Kulisse nur einen Draw-Call pro Modell.

var length := 104.0
var despawn_z := 9.0

var _groups: Array = []


func _init(band_length := 104.0, despawn := 9.0) -> void:
	length = band_length
	despawn_z = despawn


## Eine Modell-Gruppe anmelden. `items` sind Dictionaries mit
## x/y/z (+ optional yaw, scale, color) — sie werden IN PLACE fortgeschrieben.
##
## `hide_after_z`: Exemplare, die näher als dieses z an der Kamera sind, werden
## nicht gezeichnet. Gedacht für Kulisse ÜBER der Straße (Wimpelketten): im
## Hochformat öffnet die Blickwinkel-Umrechnung fast 96° senkrecht, und die
## nächste Kette hing dann als formatfüllender Wimpel im Bild.
func add_group(prop: Node3D, items: Array, hide_after_z := INF) -> void:
	_groups.append({"prop": prop, "items": items, "hide": hide_after_z})


## Alle Exemplare um dz nach hinten schieben und hinten Herausfallende
## nach vorn umsetzen.
func advance(dz: float) -> void:
	for group: Dictionary in _groups:
		for item: Dictionary in group["items"]:
			var z := float(item["z"]) + dz
			if z > despawn_z:
				z -= length
			item["z"] = z


## Aktuelle Posen in die MultiMeshes schreiben.
func flush() -> void:
	for group: Dictionary in _groups:
		var prop: Node3D = group["prop"]
		var hide := float(group.get("hide", INF))
		prop.begin()
		for item: Dictionary in group["items"]:
			if float(item["z"]) > hide:
				continue
			prop.push(pose_of(item), item.get("color", Color.WHITE))
		prop.flush()


## Anzahl Draw-Calls des ganzen Bandes.
func layer_count() -> int:
	var total := 0
	for group: Dictionary in _groups:
		total += (group["prop"] as Node3D).call("layer_count")
	return total


## Pose eines Eintrags (x/y/z + yaw + optional nicht-uniforme Skalierung).
static func pose_of(item: Dictionary) -> Transform3D:
	var basis := Basis.IDENTITY
	var scale_v: Vector3 = item.get("scale", Vector3.ONE)
	if scale_v != Vector3.ONE:
		basis = basis.scaled(scale_v)
	var yaw := float(item.get("yaw", 0.0))
	if not is_zero_approx(yaw):
		basis = Basis(Vector3.UP, yaw) * basis
	return Transform3D(
		basis, Vector3(float(item["x"]), float(item.get("y", 0.0)), float(item["z"]))
	)
