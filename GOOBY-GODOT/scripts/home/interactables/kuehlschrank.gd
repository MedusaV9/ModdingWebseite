class_name Kuehlschrank
extends Node3D
## Kühlschrank-Interactable (EF-1, EVAL-1 D1+D3): schließt die größte Lücke
## im Kernloop — `hunger` fiel, aber Füttern existierte nicht (der Veil-Tipp
## „Kühlschrank checken!“ lief ins Leere). Tap auf einen Kühlschrank öffnet
## die Vorrats-Auswahl (inventory.food, Starter: Möhre/Apfel/Törtchen);
## ein Tap auf ein Essen lässt Gooby SICHTBAR essen: hinlaufen, Kau-Squash,
## drei Nom-Töne (Pitch 0,9/1,0/1,1), „+{hunger}“-Float, Herz-Burst.
## Wirkung über FoodCatalog.apply_feed (PURE): Stats + Junk-Gewicht +
## `feeds`-Counter (Sticker firstNom/snackStack, Recap-Zeile) — danach stößt
## RewardHub.note_action die globale Sticker-Auswertung an.

const NOM_PITCHES: Array[float] = [0.9, 1.0, 1.1]
const NOM_ABSTAND_S := 0.32
const HERZ_TEILE := 12
const MJAM_KEYS: Array[String] = [
	"rewards.fuettern.mjam1", "rewards.fuettern.mjam2", "rewards.fuettern.mjam3"
]

var _host: InteractablesHost
var _rng := RandomNumberGenerator.new()
var _panel: PanelContainer
var _busy := false


func setup(host: InteractablesHost, furniture: Node3D) -> void:
	_host = host
	_rng.randomize()
	add_child(InteractablesHost.make_tap_area(furniture, _on_tapped))


func is_busy() -> bool:
	return _busy


func _on_tapped() -> void:
	if _busy or _room_busy():
		return
	var gs := _host.game_state()
	if gs == null:
		return
	if FoodCatalog.too_full(gs.state()):
		_say_text(I18nService.t("rewards.fuettern.satt"))
		return
	_open_panel()


# ── Vorrats-Panel ─────────────────────────────────────────────────────────────


func _open_panel() -> void:
	_close_panel()
	AudioDirector.try_play(self, "ui_open")
	_panel = PanelContainer.new()
	_panel.name = "KuehlschrankPanel"
	_panel.theme = ThemeService.theme()
	_panel.theme_type_variation = "AcCard"
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)
	var titel := Label.new()
	titel.theme_type_variation = &"TitleLabel"
	titel.text = I18nService.t("rewards.kuehlschrank.titel")
	titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(titel)
	var gs := _host.game_state()
	var entries := FoodCatalog.inventory_entries(gs.state()) if gs != null else []
	if entries.is_empty():
		_build_empty_state(box)
	else:
		_build_food_list(box, entries)
	var schliessen := Button.new()
	schliessen.theme_type_variation = "GhostButton"
	schliessen.text = I18nService.t("rewards.kuehlschrank.schliessen")
	schliessen.custom_minimum_size = Vector2(0, 44)
	schliessen.focus_mode = Control.FOCUS_NONE
	schliessen.pressed.connect(
		func() -> void:
			AudioDirector.try_play(self, "ui_close")
			_close_panel()
	)
	box.add_child(schliessen)
	_ui_layer().add_child(_panel)


func _build_empty_state(box: VBoxContainer) -> void:
	var leer := Label.new()
	leer.text = I18nService.t("rewards.kuehlschrank.leer")
	leer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(leer)
	var tipp := Label.new()
	tipp.theme_type_variation = &"CaptionLabel"
	tipp.text = I18nService.t("rewards.kuehlschrank.tipp")
	tipp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tipp.custom_minimum_size = Vector2(280, 0)
	tipp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tipp)


func _build_food_list(box: VBoxContainer, entries: Array[Dictionary]) -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, minf(64.0 * entries.size(), 300.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var liste := VBoxContainer.new()
	liste.add_theme_constant_override("separation", 8)
	liste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(liste)
	for entry: Dictionary in entries:
		var food_id := str(entry["id"])
		var deltas := FoodCatalog.deltas(food_id)
		var btn := Button.new()
		btn.theme_type_variation = "PrimaryButton"
		btn.custom_minimum_size = Vector2(0, 52)
		btn.focus_mode = Control.FOCUS_NONE
		btn.text = (
			I18nService
			. t(
				"rewards.kuehlschrank.eintrag",
				{
					"essen": FoodCatalog.display_name(food_id),
					"anzahl": int(entry["count"]),
					"hunger": int(deltas["hunger"]),
				}
			)
		)
		btn.pressed.connect(_on_food_chosen.bind(food_id))
		liste.add_child(btn)


func _close_panel() -> void:
	if _panel != null and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null


# ── Fütter-Ablauf ─────────────────────────────────────────────────────────────


func _on_food_chosen(food_id: String) -> void:
	AudioDirector.try_play(self, "ui_click")
	_close_panel()
	_feed(food_id)


func _feed(food_id: String) -> void:
	if _busy:
		return
	_busy = true
	var gs := _host.game_state()
	var result := {}
	if gs != null:
		gs.update(
			func(state: Dictionary) -> void:
				var applied := FoodCatalog.apply_feed(state, food_id)
				result.merge(applied, true)
		)
	if result.is_empty():
		_busy = false
		return
	RewardHub.note_action(gs)
	var gooby := _gooby()
	if gooby != null:
		gooby.set_wander_enabled(false)
		await gooby.walk_to(global_position + Vector3(0.3, 0.0, 0.7), 5.0)
	_say_mjam(food_id, bool(result.get("favorit", false)))
	await _chew(gooby, bool(result.get("favorit", false)))
	_show_reward(gooby, result)
	if gooby != null:
		gooby.play_clip("hop")
		gooby.set_wander_enabled(true)
	_busy = false


## Kau-Moment: drei Nom-Töne mit Pitch-Treppe + Squash-Wippen am Rig.
## Reduced Motion: Töne bleiben, das Wippen fällt weg.
func _chew(gooby: Node, favorit: bool) -> void:
	var rig: Node3D = gooby.get("rig") if gooby != null else null
	if rig != null:
		rig.set_emotion("ecstatic")
	var reduced := RewardFx.reduced_motion(self)
	for pitch: float in NOM_PITCHES:
		AudioDirector.try_play(self, "mg_good", pitch)
		if rig != null and not reduced:
			var tween := rig.create_tween()
			tween.tween_property(rig, "scale:y", 0.88, NOM_ABSTAND_S * 0.4)
			tween.tween_property(rig, "scale:y", 1.0, NOM_ABSTAND_S * 0.5)
		if is_inside_tree():
			await get_tree().create_timer(NOM_ABSTAND_S).timeout
	if favorit:
		AudioDirector.try_play(self, "mg_perfect", 1.1)
	if rig != null:
		rig.set_emotion("happy")


## Sichtbare Wirkung: „+{hunger}“-Float in Mint + Herz-Burst über Gooby.
func _show_reward(gooby: Node, result: Dictionary) -> void:
	var room := _host.room()
	if room == null:
		return
	var pos: Vector3 = global_position + Vector3(0.3, 0.9, 0.7)
	if gooby is Node3D:
		pos = (gooby as Node3D).global_position + Vector3(0.0, 0.9, 0.0)
	var gain := int(roundf(float(result.get("hunger_gain", 0.0))))
	if gain > 0:
		RewardFx.float_text(room, pos, "+%d" % gain, RewardFx.MINT)
	RewardFx.herz_burst(room, pos + Vector3(0.0, -0.3, 0.0), HERZ_TEILE)


func _say_mjam(food_id: String, favorit: bool) -> void:
	var essen := FoodCatalog.display_name(food_id)
	if favorit:
		_say_text(I18nService.t("rewards.fuettern.favorit", {"essen": essen}))
		return
	var key: String = MJAM_KEYS[_rng.randi_range(0, MJAM_KEYS.size() - 1)]
	_say_text(I18nService.t(key, {"essen": essen}))


# ── Helfer ────────────────────────────────────────────────────────────────────


func _gooby() -> Node:
	var room := _host.room()
	if room != null and room.has_method("gooby"):
		return room.gooby()
	return null


func _say_text(text: String) -> void:
	var room := _host.room()
	if room != null and room.has_method("say"):
		room.say(text)


func _room_busy() -> bool:
	var room := _host.room()
	return room != null and room.has_method("is_build_mode_active") and room.is_build_mode_active()


func _ui_layer() -> CanvasLayer:
	var existing := _host.get_node_or_null("W3dUiLayer")
	if existing is CanvasLayer:
		return existing
	var layer := CanvasLayer.new()
	layer.name = "W3dUiLayer"
	layer.layer = 6
	_host.add_child(layer)
	return layer
