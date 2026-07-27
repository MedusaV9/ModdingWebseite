class_name ParkStallSheet
extends VBoxContainer
## Naschgassen-Sheet (REST-4, Web-Vorbild GOOBY/src/ui/parkStall.js):
## drei Jahrmarkt-Stände (Zuckerwolke, Eiswirbel, Waffelzauber). Kaufen
## zahlt über Economy.spend (EIN gs.update: Münzen + inventory.food +
## park.candyBought), danach Slice-Notify für die Sticker-Auswertung
## (candyDay). Preise/Deltas: web data/foods.js V6_PARK_FOODS.

signal gekauft(food_id: String)

const Economy := preload("res://scripts/logic/economy.gd")

var gs: Object

var _coins_label: Label


func _ready() -> void:
	CitySheetBausteine.richte_box_ein(self)
	aktualisiere()


func aktualisiere() -> void:
	for kind in get_children():
		kind.queue_free()
	CitySheetBausteine.label(self, I18nService.t("park.alley.hint"), "CaptionLabel")
	_coins_label = CitySheetBausteine.coins_zeile(self, _coins())
	for stall: Dictionary in ParkState.STALLS:
		_baue_stand(str(stall["id"]), int(stall["preis"]))


func _baue_stand(food_id: String, preis: int) -> void:
	var karte := CitySheetBausteine.karte(self)
	CitySheetBausteine.label(karte, I18nService.t("park.stall.%s.name" % food_id), "HeadlineLabel")
	CitySheetBausteine.label(karte, I18nService.t("park.stall.%s.pitch" % food_id), "CaptionLabel")
	var btn := Button.new()
	btn.theme_type_variation = "AccentButton"
	btn.text = I18nService.t("park.stall.kaufen", {"preis": preis})
	btn.pressed.connect(func() -> void: _kaufe(food_id, preis))
	karte.add_child(btn)


func _kaufe(food_id: String, preis: int) -> void:
	if gs == null:
		return
	# Vorab prüfen (Lambda-Captures sind by-value — kein Out-Flag möglich).
	if _coins() < preis:
		_zeige_toast(I18nService.t("park.ride.zu_teuer"))
		return
	gs.update(
		func(state: Dictionary) -> void:
			if not Economy.spend(state["economy"], preis, "park"):
				return
			var food: Dictionary = state["inventory"]["food"]
			food[food_id] = int(food.get(food_id, 0)) + 1
			state["park"] = ParkState.record_candy(state.get("park"))
	)
	if gs.has_method("notify_slice_changed"):
		gs.notify_slice_changed("park")
	if _coins_label != null:
		_coins_label.text = I18nService.t("city.laden.coins").format({"coins": _coins()})
	_zeige_toast(
		I18nService.t("park.stall.gekauft", {"name": I18nService.t("park.food.%s" % food_id)})
	)
	gekauft.emit(food_id)


func _coins() -> int:
	if gs == null:
		return 0
	return int(gs.get_value("economy.coins", 0))


func _zeige_toast(text: String) -> void:
	var toasts := get_tree().root.find_children("*", "ToastLayer", true, false)
	if not toasts.is_empty():
		toasts[0].show_toast(text)
