class_name OrtFlughafen
extends OrtScene
## Flughafen-Terminal (Doc E §3): Reise-Schalter — Ziel wählen →
## Bestätigungs-Dialog (Preis/Dauer/WARNUNG/NUTZEN) → Taxi bestellen
## (ReiseApp). Die eigentliche Abreise passiert NACH der realen Taxi-
## Wartezeit über die Reise-Cutscene.

const INNEN := "res://assets/city/innen"


func _baue_innenraum() -> void:
	# Basisgrößen: Counter 2 m, Menu-Tafel 0,8 m — Skalen klein (s. rehwei.gd).
	_prop("%s/kitchencounter_straight.gltf" % INNEN, Vector3(0.0, 0.0, -1.2), 90.0, 0.9)
	_prop("%s/menu.gltf" % INNEN, Vector3(-2.6, 0.0, -3.4), 0.0, 2.0)
	_prop("%s/menu.gltf" % INNEN, Vector3(2.6, 0.0, -3.4), 0.0, 2.0)


func _npc_konfig() -> Dictionary:
	return {"tint": Color("#9BB7E8"), "emotion": "happy", "pos": Vector3(0.0, 0.0, -2.2)}


func _baue_ui() -> void:
	super._baue_ui()
	var reise_btn := Button.new()
	reise_btn.text = I18nService.t("travel.schalter.knopf")
	reise_btn.theme_type_variation = "PrimaryButton"
	reise_btn.custom_minimum_size = Vector2(220.0, 56.0)
	reise_btn.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 24
	)
	reise_btn.pressed.connect(_on_reise)
	_ui.add_child(reise_btn)


func _on_reise() -> void:
	ReiseApp.oeffne(self, game_state())
