class_name HaendlerSheet
extends VBoxContainer
## Generisches Händler-UI (W3a CITY, Doc E §2.3): Warenliste aus JSON
## (CitySortiment), Kauf via GameState-Economy (W1d economy.gd). Wird als
## Inhalt in ein W1c-PanelSheet gehängt. Rezept-Waren (braucht_rezept) sind
## nur mit gesetztem city-Flag `rezept_tropfen` kaufbar — der Kauf VERBRAUCHT
## das Rezept. Root = VBoxContainer, damit das PanelSheet die Mindesthöhe
## des Inhalts sieht (plain Control meldet min-Höhe 0 → Sheet kollabiert).

signal gekauft(ware_id: String)

const Economy := preload("res://scripts/logic/economy.gd")

var gs: Object
var waren: Array = []

var _liste: VBoxContainer
var _coins_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(420.0, 0.0)
	add_theme_constant_override("separation", 10)
	_coins_label = Label.new()
	_coins_label.theme_type_variation = "CaptionLabel"
	add_child(_coins_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 380.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_liste = VBoxContainer.new()
	_liste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_liste.add_theme_constant_override("separation", 8)
	scroll.add_child(_liste)
	aktualisiere()


## Warenliste (neu) rendern — nach jedem Kauf.
func aktualisiere() -> void:
	for kind in _liste.get_children():
		kind.queue_free()
	_coins_label.text = I18nService.t("city.laden.coins").format({"coins": _coins()})
	for ware: Dictionary in waren:
		_liste.add_child(_zeile(ware))


func kann_kaufen(ware: Dictionary) -> bool:
	if int(ware.get("preis", 0)) > _coins():
		return false
	if bool(ware.get("braucht_rezept", false)) and not _hat_rezept():
		return false
	return true


## Kauf: Münzen abziehen, Item ins Inventar, ggf. Rezept verbrauchen.
func kaufe(ware: Dictionary) -> bool:
	if gs == null or not kann_kaufen(ware):
		return false
	var id := str(ware.get("id", ""))
	var inventar := str(ware.get("inventar", ""))
	gs.update(
		func(state: Dictionary) -> void:
			if not Economy.spend(state["economy"], int(ware.get("preis", 0)), "laden"):
				return
			if inventar.is_empty():
				var food: Dictionary = state["inventory"]["food"]
				food[id] = int(food.get(id, 0)) + 1
			else:
				var items: Dictionary = state["inventory"]["items"]
				items[inventar] = int(items.get(inventar, 0)) + 1
	)
	if bool(ware.get("braucht_rezept", false)):
		CityState.set_flag(gs, CityState.FLAG_REZEPT, false)
	gekauft.emit(id)
	aktualisiere()
	return true


func _zeile(ware: Dictionary) -> Control:
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 12)
	var name_label := Label.new()
	name_label.text = str(ware.get("name_de", ware.get("id", "?")))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zeile.add_child(name_label)
	if bool(ware.get("braucht_rezept", false)):
		var rezept := Label.new()
		rezept.theme_type_variation = "CaptionLabel"
		rezept.text = I18nService.t("city.laden.rezept_noetig")
		zeile.add_child(rezept)
	var btn := Button.new()
	btn.theme_type_variation = "AccentButton"
	btn.text = I18nService.t("city.laden.kaufen").format({"preis": int(ware.get("preis", 0))})
	btn.disabled = not kann_kaufen(ware)
	btn.pressed.connect(func() -> void: kaufe(ware))
	zeile.add_child(btn)
	return zeile


func _coins() -> int:
	if gs == null:
		return 0
	return int(gs.get_value("economy.coins", 0))


func _hat_rezept() -> bool:
	return gs != null and CityState.flag(gs, CityState.FLAG_REZEPT)
