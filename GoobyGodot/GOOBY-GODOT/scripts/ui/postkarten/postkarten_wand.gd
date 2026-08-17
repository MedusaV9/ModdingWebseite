class_name PostkartenWand
extends Node3D
## Postkarten-Interactable (REST-4, EVAL Rang 15): dockt per
## InteractablesHost an die Postkartenwand und das Souvenirregal und öffnet
## auf Tap das Postkarten-Archiv (Route `postkarten` — Karten ansehen,
## Souvenirregal, Set-Bonus).

var _host: InteractablesHost


func setup(host: InteractablesHost, furniture: Node3D) -> void:
	_host = host
	add_child(InteractablesHost.make_tap_area(furniture, _on_tapped))


func _on_tapped() -> void:
	if _room_busy():
		return
	AudioDirector.try_play(self, "ui_open")
	PostkartenScreen.register_routes()
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("goto"):
		router.goto(PostkartenScreen.ROUTE, {})


func _room_busy() -> bool:
	var room := _host.room()
	return room != null and room.has_method("is_build_mode_active") and room.is_build_mode_active()
