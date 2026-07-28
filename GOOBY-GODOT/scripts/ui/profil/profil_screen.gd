class_name ProfilScreen
extends Control
## Profil-/Pass-Screen (REST-1, EVAL-VOLLSTAENDIGKEIT Rang 1 + P1-Fehlroute):
## der HUD-Profil-Knopf landet jetzt HIER (vorher fälschlich „Freunde &
## Besuche“). Aufbau als GOOBY-PASS im AC-Look, eine Scroll-Spalte:
##   1. Pass-Karte — ECHTES 3D-Porträt (GoobyPreview mit den Save-Morphs,
##      drehbar), Name, Level + XP-Balken, „Dabei seit“, Spielzeit und die
##      Tagesbonus-Serie (REST-1 Rang 8: „Anzeige im Profil“).
##   2. Statistik — Lebenszeit-Zähler (Web §C12.1-Reihenfolge + Orte/Reisen/
##      Park), alle aus vorhandenen Slices (achievements.counters, profile,
##      economy, vacation, park, quests).
##   3. Lieblinge — Lieblingsessen (Seele: foodGiven-Spitzenreiter) und
##      Lieblingsmöbel (Seele: favFurniture) mit lokalisierten Namen.
##   4. Erfolge-Vorschau — n/44 + Balken + Sprung zum vollen Erfolgs-Screen.
##   5. Sticker-Album-Fortschritt (Balken).
##   6. Minispiel-Rekorde — alle Registry-Spiele mit Rekord + Runden.
##   7. Freunde-Kurzansicht (online/offline) + Sprung zu „Freunde & Besuche“.
##
## Geometrie: ScreenShell (UiScale + Safe-Area + Touch-Floor), 0-Befund-Regel.

signal ready_for_reveal

const Leveling := preload("res://scripts/logic/leveling.gd")

const ROUTE := &"profil"
const ROUTES := {ROUTE: "res://scripts/ui/profil/profil_screen.tscn"}
const PORTRAIT_BASE := 168.0
const MAX_FRIEND_ROWS := 4

## Tests: Navigation abschaltbar; GameState/NetClient injizierbar.
var auto_navigate := true
var gs_override: Object = null
var net_override: Object = null

var _gs: Object = null
var _net: Object = null
var _rows_box: VBoxContainer
var _list_box: VBoxContainer
var _back_btn: Button
var _nav_btns: Array[Button] = []
var _portrait: Control


## HUD-Dispatch (home_entry._dispatch_to_screens): Profil-Knopf → dieser
## Screen. Registriert die eigene UND die Erfolgs-Route (Vorschau-Sprung).
static func handle_hud_action(action: StringName) -> bool:
	if action != &"profil":
		return false
	register_routes()
	AchievementsScreen.register_routes()
	var router := _router()
	if router == null or not router.has_method("goto"):
		return false
	router.goto(ROUTE, {})
	return true


static func register_routes() -> void:
	var router := _router()
	if router != null and router.has_method("register_routes"):
		router.register_routes(ROUTES)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	register_routes()
	AchievementsScreen.register_routes()
	_gs = gs_override if gs_override != null else get_node_or_null("/root/GameState")
	_net = net_override if net_override != null else get_node_or_null("/root/Net")
	_build_ui()
	_apply_metrics()
	get_viewport().size_changed.connect(_on_viewport_resized)
	ready_for_reveal.emit()


func _build_ui() -> void:
	var wallpaper := AcWallpaper.new()
	wallpaper.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(wallpaper)

	_rows_box = VBoxContainer.new()
	_rows_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rows_box.add_theme_constant_override("separation", 12)
	add_child(_rows_box)
	_rows_box.add_child(_build_header())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 24
	_rows_box.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 12)
	scroll.add_child(_list_box)

	_list_box.add_child(_build_pass_card())
	# FERTIG-1 (EVAL „Rundes Ende“): Spiel-Abschluss als sichtbares
	# Langzeit-Ziel direkt unter dem Pass — Prozent + vier Sammlungen.
	_list_box.add_child(_build_abschluss_card())
	_list_box.add_child(_build_stats_card())
	_list_box.add_child(_build_favorites_card())
	_list_box.add_child(_build_achievements_card())
	_list_box.add_child(_build_sticker_card())
	_list_box.add_child(_build_minigames_card())
	_list_box.add_child(_build_friends_card())


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	_back_btn = SquishButton.new()
	_back_btn.name = "BackBtn"
	_back_btn.theme_type_variation = &"BtnGhost"
	_back_btn.text = I18nService.t("profil.zurueck")
	_back_btn.focus_mode = Control.FOCUS_NONE
	_back_btn.pressed.connect(_on_back_pressed)
	header.add_child(_back_btn)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = I18nService.t("profil.titel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"StatusCapsule"
	var level := Label.new()
	level.name = "LevelChip"
	level.theme_type_variation = &"SoftLabel"
	level.text = I18nService.t("profil.level", {"level": _level()})
	chip.add_child(level)
	header.add_child(chip)
	return header


## Pass-Karte: Porträt (ECHTES 3D, drehbar) links, Pass-Felder rechts.
func _build_pass_card() -> Control:
	var card := PanelContainer.new()
	card.name = "PassCard"
	card.theme_type_variation = &"AcCardLg"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)

	var word := Label.new()
	word.name = "PassWort"
	word.theme_type_variation = &"SoftLabel"
	word.text = I18nService.t("profil.pass_wort")
	word.uppercase = true
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(word)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)

	_portrait = _build_portrait()
	row.add_child(_portrait)

	var fields := VBoxContainer.new()
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.alignment = BoxContainer.ALIGNMENT_CENTER
	fields.add_theme_constant_override("separation", 6)
	row.add_child(fields)

	var name_label := Label.new()
	name_label.name = "GoobyName"
	name_label.theme_type_variation = &"TitleLabel"
	name_label.text = str(_value("meta.goobyNickname", "Gooby"))
	fields.add_child(name_label)

	var since := Label.new()
	since.name = "DabeiSeit"
	since.theme_type_variation = &"SoftLabel"
	since.text = I18nService.t("profil.dabei_seit", {"date": _joined_date()})
	fields.add_child(since)

	fields.add_child(_build_level_row())
	fields.add_child(_field_row("Spielzeit", I18nService.t("profil.spielzeit"), _playtime_text()))
	fields.add_child(
		_field_row(
			"Serie",
			I18nService.t("profil.serie"),
			I18nService.t("profil.serie_wert", {"n": int(_value("daily.streak", 0))})
		)
	)
	return card


## Echte 3D-Vorschau mit den Save-Morphs (kein Platzhalter) — GoobyPreview
## dreht per Drag und zoomt per Rad, wie im Char-Editor.
func _build_portrait() -> Control:
	var preview := GoobyPreview.new()
	preview.name = "PassPortrait"
	var morphs: Variant = _value("meta.charMorphs", {})
	if morphs is Dictionary and not (morphs as Dictionary).is_empty():
		preview.set_morphs(morphs)
	return preview


func _build_level_row() -> Control:
	var row := HBoxContainer.new()
	row.name = "LevelRow"
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.theme_type_variation = &"HeadlineLabel"
	# FERTIG-1 („Rundes Ende“): die Level-Obergrenze steht SICHTBAR im Pass.
	label.text = I18nService.t("profil.level_von", {"level": _level(), "max": Leveling.MAX_LEVEL})
	row.add_child(label)
	if _level() >= Leveling.MAX_LEVEL:
		var voll := Label.new()
		voll.name = "LevelMax"
		voll.theme_type_variation = &"SoftLabel"
		voll.text = I18nService.t("profil.level_max")
		voll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(voll)
		return row
	var bar := ProgressBar.new()
	bar.name = "XpBar"
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = _xp_ratio()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0.0, 12.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	return row


## Abschluss-Karte (FERTIG-1, „Rundes Ende“): Gesamt-Prozent + die vier
## Sammlungen aus AbschlussLogic; bei 100 % ersetzt eine Feier-Zeile den
## Hinweis — DAS ist das sichtbare Endziel des Spiels.
func _build_abschluss_card() -> Control:
	var card := _card("AbschlussCard", I18nService.t("profil.abschluss"))
	var box := card.get_child(0) as VBoxContainer
	var state: Dictionary = _gs.state() if _gs != null and _gs.has_method("state") else {}
	var p := AbschlussLogic.prozent(state)
	var prozent := Label.new()
	prozent.name = "AbschlussProzent"
	prozent.theme_type_variation = &"TitleLabel"
	prozent.text = I18nService.t("profil.abschluss_prozent", {"p": p})
	box.add_child(prozent)
	var bar := _progress_row("AbschlussBar", p, 100)
	box.add_child(bar)
	for teil in AbschlussLogic.komponenten(state):
		var id := str(teil["id"])
		box.add_child(
			_field_row(
				"Abschluss%s" % id.capitalize(),
				I18nService.t("profil.abschluss_teil.%s" % id),
				I18nService.t(
					"profil.abschluss_stand", {"n": int(teil["n"]), "total": int(teil["total"])}
				)
			)
		)
	var zeile := Label.new()
	zeile.name = "AbschlussZeile"
	zeile.theme_type_variation = &"SoftLabel"
	zeile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	zeile.text = I18nService.t(
		"profil.abschluss_fertig" if AbschlussLogic.komplett(state) else "profil.abschluss_hinweis"
	)
	box.add_child(zeile)
	return card


func _build_stats_card() -> Control:
	var card := _card("StatsCard", I18nService.t("profil.statistik"))
	var grid := GridContainer.new()
	grid.name = "StatsGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	for stat: Array in _stat_rows():
		grid.add_child(_stat_cell(str(stat[0]), str(stat[1])))
	(card.get_child(0) as VBoxContainer).add_child(grid)
	return card


## Web §C12.1-Reihenfolge, ergänzt um Orte/Reisen/Park (vorhandene Slices).
func _stat_rows() -> Array:
	var c := "achievements.counters."
	return [
		[I18nService.t("profil.stat.fuetterungen"), _int_text(c + "feeds")],
		[I18nService.t("profil.stat.waeschen"), _int_text(c + "washes")],
		[I18nService.t("profil.stat.nickerchen"), _int_text(c + "sleeps")],
		[I18nService.t("profil.stat.kitzler"), _int_text(c + "tickles")],
		[I18nService.t("profil.stat.ballwuerfe"), _int_text(c + "balls")],
		[I18nService.t("profil.stat.einkaufsfahrten"), _int_text(c + "trips")],
		[I18nService.t("profil.stat.tierarzt"), _int_text(c + "vetTrips")],
		[I18nService.t("profil.stat.lieferungen"), _int_text(c + "deliveries")],
		[I18nService.t("profil.stat.ernten"), _int_text(c + "harvests")],
		[I18nService.t("profil.stat.fotos"), _int_text("profile.photos")],
		[I18nService.t("profil.stat.quests"), _int_text(c + "questsDone")],
		[I18nService.t("profil.stat.muenzen_verdient"), _int_text("economy.coinsEarned")],
		[I18nService.t("profil.stat.muenzen_ausgegeben"), _int_text("economy.coinsSpent")],
		[I18nService.t("profil.stat.strecke"), _distance_text()],
		[I18nService.t("profil.stat.orte"), str(_visited_places())],
		[I18nService.t("profil.stat.reisen"), _int_text("vacation.trips")],
		[I18nService.t("profil.stat.park"), _int_text("park.visits")],
	]


func _stat_cell(key_text: String, value_text: String) -> Control:
	var row := HBoxContainer.new()
	# Zellen müssen im Grid EXPANDIEREN — sonst kollabiert die Autowrap-
	# Spalte auf Minimalbreite und die Schlüssel brechen buchstabenweise.
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	var key := Label.new()
	key.theme_type_variation = &"SoftLabel"
	key.text = key_text
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(key)
	var value := Label.new()
	value.theme_type_variation = &"HeadlineLabel"
	value.text = value_text
	row.add_child(value)
	return row


## Lieblinge aus der Seele: Essen = foodGiven-Spitzenreiter, Möbel =
## favFurniture (beide „Noch unbekannt“, solange die Seele nichts weiß).
func _build_favorites_card() -> Control:
	var card := _card("FavoritesCard", I18nService.t("profil.lieblinge"))
	var box := card.get_child(0) as VBoxContainer
	box.add_child(
		_field_row("Essen", I18nService.t("profil.lieblingsessen"), _favorite_food_text())
	)
	box.add_child(
		_field_row("Moebel", I18nService.t("profil.lieblingsmoebel"), _favorite_furniture_text())
	)
	return card


func _favorite_food_text() -> String:
	var slice := _soul_slice()
	var given: Variant = slice.get("foodGiven", {})
	var best_id := ""
	var best := 0
	if given is Dictionary:
		var ids: Array = (given as Dictionary).keys()
		ids.sort()
		for food_id: Variant in ids:
			var n := int(given[food_id])
			if n > best:
				best = n
				best_id = str(food_id)
	if best_id.is_empty():
		return I18nService.t("profil.unbekannt")
	var key := "rewards.food.%s" % best_id
	return I18nService.t(key) if I18nService.has_key(key) else best_id


func _favorite_furniture_text() -> String:
	var fav := str(_soul_slice().get("favFurniture", ""))
	if fav.is_empty():
		return I18nService.t("profil.unbekannt")
	var item_def := FurnitureCatalog.def(fav)
	if item_def.is_empty():
		return fav
	return FurnitureCatalog.display_name(item_def, I18nService.get_locale())


func _soul_slice() -> Dictionary:
	if _gs == null:
		return {}
	var slice: Variant = _value("soul", {})
	return slice if slice is Dictionary else {}


## Erfolge-Vorschau: n/44-Balken + Sprung zum vollen Erfolgs-Screen (Rang 3).
func _build_achievements_card() -> Control:
	var card := _card("AchievementsCard", I18nService.t("profil.erfolge"))
	var box := card.get_child(0) as VBoxContainer
	var catalog := AchievementsCatalog.all()
	var unlocked := 0
	if _gs != null:
		unlocked = AchievementsEngine.unlocked_count(_gs.state(), catalog)
	box.add_child(_progress_row("ErfolgeBar", unlocked, catalog.size()))
	var stand := Label.new()
	stand.name = "ErfolgeStand"
	stand.theme_type_variation = &"SoftLabel"
	stand.text = I18nService.t("profil.erfolge_stand", {"n": unlocked, "total": catalog.size()})
	box.add_child(stand)
	var btn := SquishButton.new()
	btn.name = "ErfolgeBtn"
	btn.theme_type_variation = &"BtnLeaf"
	btn.text = I18nService.t("profil.erfolge_alle")
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_on_achievements_pressed)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(btn)
	_nav_btns.append(btn)
	return card


func _build_sticker_card() -> Control:
	var card := _card("StickerCard", I18nService.t("profil.sticker"))
	var box := card.get_child(0) as VBoxContainer
	var catalog := StickerCatalog.all()
	var total := StickerCatalog.regular_count(catalog)
	var unlocked := 0
	if _gs != null:
		unlocked = StickerUnlocks.unlocked_count(_gs.state(), catalog)
	box.add_child(_progress_row("StickerBar", unlocked, total))
	var stand := Label.new()
	stand.name = "StickerStand"
	stand.theme_type_variation = &"SoftLabel"
	stand.text = I18nService.t("profil.sticker_stand", {"n": unlocked, "total": total})
	box.add_child(stand)
	return card


func _build_minigames_card() -> Control:
	var card := _card("MinigamesCard", I18nService.t("profil.minigames"))
	var box := card.get_child(0) as VBoxContainer
	var plays: Variant = _value("minigames.plays", {})
	var best: Variant = _value("minigames.legacy.best", {})
	for game: Dictionary in MinigameRegistry.all_games():
		var id := str(game.get("id", ""))
		var n := int(plays.get(id, 0)) if plays is Dictionary else 0
		var record := int(best.get(id, 0)) if best is Dictionary else 0
		var value := (
			I18nService.t("profil.rekord_zeile", {"best": record, "n": n})
			if n > 0
			else I18nService.t("profil.nie_gespielt")
		)
		var row := _field_row(id, I18nService.t(str(game.get("title_key", id))), value)
		if n == 0:
			row.modulate = Color(1.0, 1.0, 1.0, 0.55)
		box.add_child(row)
	return card


func _build_friends_card() -> Control:
	var card := _card("FriendsCard", I18nService.t("profil.freunde"))
	var box := card.get_child(0) as VBoxContainer
	var friends := _friend_rows()
	if friends.is_empty():
		var empty := Label.new()
		empty.name = "FreundeLeer"
		empty.theme_type_variation = &"SoftLabel"
		empty.text = I18nService.t("profil.freunde_leer")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(empty)
	for i in mini(friends.size(), MAX_FRIEND_ROWS):
		var row: Dictionary = friends[i]
		var online: bool = row.get("online", false) == true
		var presence := I18nService.t("profil.online" if online else "profil.offline")
		var line := _field_row("Freund%d" % i, str(row.get("name", "?")), presence)
		if not online:
			line.modulate = Color(1.0, 1.0, 1.0, 0.55)
		box.add_child(line)
	var btn := SquishButton.new()
	btn.name = "FreundeBtn"
	btn.theme_type_variation = &"BtnGhost"
	btn.text = I18nService.t("profil.freunde_oeffnen")
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_on_friends_pressed)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(btn)
	_nav_btns.append(btn)
	return card


func _friend_rows() -> Array:
	if _net == null:
		return []
	var svc: Variant = _net.get("friends")
	if svc == null:
		return []
	var rows: Variant = svc.get("friends")
	return rows if rows is Array else []


## ---- Bausteine -----------------------------------------------------------


func _card(node_name: String, title_text: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = node_name
	card.theme_type_variation = &"AcCard"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	var title := Label.new()
	title.theme_type_variation = &"HeadlineLabel"
	title.text = title_text
	box.add_child(title)
	return card


func _field_row(node_name: String, key_text: String, value_text: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "Row%s" % node_name
	row.add_theme_constant_override("separation", 8)
	var key := Label.new()
	key.theme_type_variation = &"SoftLabel"
	key.text = key_text
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(key)
	var value := Label.new()
	value.name = "Wert"
	value.theme_type_variation = &"HeadlineLabel"
	value.text = value_text
	row.add_child(value)
	return row


func _progress_row(node_name: String, current: int, total: int) -> Control:
	var bar := ProgressBar.new()
	bar.name = node_name
	bar.min_value = 0.0
	bar.max_value = float(maxi(total, 1))
	bar.value = float(current)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0.0, 12.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return bar


## ---- Werte ----------------------------------------------------------------


func _value(path: String, default: Variant) -> Variant:
	if _gs == null:
		return default
	return _gs.get_value(path, default)


func _level() -> int:
	return int(_value("progression.level", 1))


func _xp_ratio() -> float:
	if _gs != null and _gs.has_method("xp_ratio"):
		return clampf(float(_gs.xp_ratio()), 0.0, 1.0)
	return 0.0


func _int_text(path: String) -> String:
	return str(int(_value(path, 0)))


func _distance_text() -> String:
	var meters := float(_value("profile.distanceM", 0))
	return I18nService.t("profil.km", {"km": "%.1f" % (meters / 1000.0)})


func _visited_places() -> int:
	var visited: Variant = _value("vacation.visited", {})
	return (visited as Dictionary).size() if visited is Dictionary else 0


func _playtime_text() -> String:
	var minutes := int(_value("profile.playtimeMin", 0))
	return I18nService.t(
		"profil.spielzeit_wert", {"h": minutes / 60, "mm": "%02d" % (minutes % 60)}
	)


func _joined_date() -> String:
	var created_ms := int(_value("meta.createdAt", 0))
	if created_ms <= 0:
		created_ms = int(Time.get_unix_time_from_system() * 1000.0)
	var d := Time.get_datetime_dict_from_unix_time(created_ms / 1000)
	if I18nService.get_locale() == "de":
		return "%02d.%02d.%04d" % [d.day, d.month, d.year]
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


## ---- Layout / Navigation ---------------------------------------------------


func _on_viewport_resized() -> void:
	if not is_inside_tree():
		return
	_apply_metrics()


func _apply_metrics() -> void:
	var m := ScreenShell.metrics(get_viewport())
	var f: float = m["f"]
	ScreenShell.frame(_rows_box, m, 24.0, 16.0)
	ScreenShell.scale_fonts(self, f)
	ScreenShell.touch_target(_back_btn, m)
	for btn in _nav_btns:
		if is_instance_valid(btn):
			ScreenShell.touch_target(btn, m)
	if _portrait != null:
		var side := maxf(PORTRAIT_BASE * f, float(m["floor_px"]) * 2.4)
		_portrait.custom_minimum_size = Vector2(side, side)


func _on_achievements_pressed() -> void:
	_navigate(AchievementsScreen.ROUTE)


func _on_friends_pressed() -> void:
	SocialScreen.register_routes()
	_navigate(SocialScreen.ROUTE)


func _navigate(target: StringName) -> void:
	if not auto_navigate:
		return
	var router := _router()
	if router != null and router.has_method("goto"):
		router.goto(target, {})


func _on_back_pressed() -> void:
	if not auto_navigate:
		return
	var router := _router()
	if router == null or not router.has_method("goto"):
		return
	if router.has_method("handle_back_request") and router.handle_back_request():
		return
	var routes: Variant = router.get("_routes")
	if routes is Dictionary and (routes as Dictionary).has(&"home"):
		router.goto(&"home", {})


static func _router() -> Node:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null("/root/SceneRouter")
