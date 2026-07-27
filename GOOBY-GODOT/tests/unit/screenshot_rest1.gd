extends SceneTree
## REST-1-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert die
## Review-Artefakte für Profil-Screen (2 Formate), Erfolgs-Screen
## (Kategorien + frisch freigeschaltet), Freischalt-Feier (Toast+Konfetti
## vom RewardHub) und Tagesbonus-Popup (Serie + Kulanz). Braucht einen
## echten Renderer:
##   xvfb-run -a godot --path GOOBY-GODOT --rendering-method \
##     gl_compatibility --rendering-driver opengl3 \
##     --script res://tests/unit/screenshot_rest1.gd

const GameStateScript := preload("res://scripts/state/game_state.gd")

const OUT_DIR := "/tmp/gooby-godot/artifacts/REST1"
const SETTLE_FRAMES := 16
const NOW_MS := 1_750_000_000_000


class FriendsStub:
	var friends := [
		{"friendCode": "GOOBY-AAA", "name": "Mira", "goobyName": "Bommel", "online": true},
		{"friendCode": "GOOBY-BBB", "name": "Jonas", "goobyName": "Keks", "online": false},
	]


class NetStub:
	var friends := FriendsStub.new()


var _gs: Node
var _net := NetStub.new()


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.theme = ThemeService.theme()
	RenderingServer.set_default_clear_color(AcTokens.BG_CREAM)
	_gs = _lived_in_gs()
	root.add_child(_gs)
	await _shot_profil(Vector2i(1280, 720), "profil_quer_1280x720.png")
	await _shot_profil(Vector2i(720, 1280), "profil_hoch_720x1280.png")
	await _shot_profil(Vector2i(720, 1280), "profil_hoch_mitte_720x1280.png", 0.26)
	await _shot_profil(Vector2i(720, 1280), "profil_hoch_unten_720x1280.png", 1.0)
	await _shot_erfolge_kategorien(Vector2i(1280, 720), "erfolge_kategorien.png")
	await _shot_freischalt_feier(Vector2i(1280, 720), "erfolge_freischalt_feier.png")
	await _shot_daily(Vector2i(1280, 720), "tagesbonus_popup_serie4.png", false)
	await _shot_daily(Vector2i(720, 1280), "tagesbonus_popup_kulanz.png", true)
	print("Screenshots fertig → %s" % OUT_DIR)
	quit(0)


## Belebter Spielstand: Zähler, Serie, Sticker, Lieblinge — die Erfolgs-
## Freischaltungen dazu kommen im Feier-Shot vom echten Service.
func _lived_in_gs() -> Node:
	var dir := "user://rest1_shots/%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	var yesterday := DailyBonus.prev_day(str(gs.clock.local_day()))
	gs.update(
		func(state: Dictionary) -> void:
			state["meta"]["goobyNickname"] = "Gooby"
			state["meta"]["createdAt"] = NOW_MS - 90 * 86_400_000
			state["meta"]["charMorphs"] = {
				"eyes_apart": 0.2, "eye_scale": 1.1, "ear_len": 1.15, "chubby": 0.4
			}
			state["progression"]["level"] = 7
			state["progression"]["xp"] = 40
			state["economy"]["coins"] = 610
			state["economy"]["coinsEarned"] = 1220
			state["economy"]["coinsSpent"] = 610
			state["profile"] = {"playtimeMin": 312, "distanceM": 8460, "photos": 7}
			state["daily"] = {"lastClaimDay": yesterday, "streak": 3}
			var counters: Dictionary = state["achievements"]["counters"]
			counters["feeds"] = 23
			counters["washes"] = 12
			counters["sleeps"] = 4
			counters["tickles"] = 57
			counters["balls"] = 31
			counters["trips"] = 6
			counters["vetTrips"] = 1
			counters["deliveries"] = 3
			counters["harvests"] = 18
			counters["photosTaken"] = 7
			counters["questsDone"] = 9
			state["vacation"]["trips"] = 2
			state["vacation"]["visited"] = {"strand": NOW_MS, "berge": NOW_MS, "stadt": NOW_MS}
			state["park"]["visits"] = 2
			state["park"]["rides"]["wheel"] = 1
			var sticker_ids := StickerCatalog.all().slice(0, 9)
			for def: Dictionary in sticker_ids:
				state["stickers"]["unlocked"][str(def.get("id", ""))] = NOW_MS
			state["soul"] = SoulState.default_slice()
			state["soul"]["foodGiven"] = {"cupcake": 7, "carrot": 3}
			var moebel := FurnitureCatalog.ids()
			if not moebel.is_empty():
				state["soul"]["favFurniture"] = str(moebel[mini(3, moebel.size() - 1)])
			state["minigames"]["plays"] = {"teaParty": 6, "carrotCatch": 3}
			state["minigames"]["legacy"]["best"] = {"teaParty": 118, "carrotCatch": 74}
	)
	return gs


## Vorab freigeschaltete Erfolge (einmalig): der echte Service wertet die
## Zähler aus und stempelt/zahlt — genau der Produktiv-Pfad.
func _unlock_via_service() -> void:
	var service := AchievementsService.new()
	root.add_child(service)
	service.attach(_gs)
	service.free()


func _resize(win_size: Vector2i) -> void:
	DisplayServer.window_set_size(win_size)
	root.size = win_size


## scroll_anteil: 0 = oben, 0.26 = Mitte (Lieblinge/Erfolge/Sticker),
## 1.0 = Ende (Rekorde/Freunde) — für die Sichtprüfung der ganzen Spalte.
func _shot_profil(win_size: Vector2i, file: String, scroll_anteil := 0.0) -> void:
	_resize(win_size)
	_unlock_via_service()
	var screen := ProfilScreen.new()
	screen.auto_navigate = false
	screen.gs_override = _gs
	screen.net_override = _net
	root.add_child(screen)
	if scroll_anteil > 0.0:
		await process_frame
		await process_frame
		var scroll: ScrollContainer = screen.find_children("", "ScrollContainer", true, false)[0]
		var max_scroll := scroll.get_v_scroll_bar().max_value - scroll.size.y
		scroll.scroll_vertical = int(max_scroll * scroll_anteil)
	await _snap(file)
	screen.free()


func _shot_erfolge_kategorien(win_size: Vector2i, file: String) -> void:
	_resize(win_size)
	_unlock_via_service()
	var screen := AchievementsScreen.new()
	screen.auto_navigate = false
	screen.gs_override = _gs
	root.add_child(screen)
	await process_frame
	screen.show_category("pflege")
	await _snap(file)
	screen.free()


## Frische Freischaltung MIT Feier: RewardHub (Toast + Konfetti auf der
## obersten Layer) über dem offenen Erfolgs-Screen. Vorher werden alle vom
## belebten Spielstand bereits erfüllten STICKER UND ERFOLGE still
## gestempelt — sonst drängeln sich deren Feiern in der Hub-Queue VOR den
## frischen Erfolg und der Screenshot zeigt den falschen Toast.
func _shot_freischalt_feier(win_size: Vector2i, file: String) -> void:
	_resize(win_size)
	var pre := StickerUnlocks.new()
	root.add_child(pre)
	pre.attach(_gs)
	pre.free()
	_unlock_via_service()
	var hub := RewardHub.attach_to(root, _gs)
	var screen := AchievementsScreen.new()
	screen.auto_navigate = false
	screen.gs_override = _gs
	root.add_child(screen)
	await process_frame
	# Der 100. Streichler → tickle100 „Kicherfabrik“ feuert JETZT.
	_gs.update(func(state: Dictionary) -> void: state["achievements"]["counters"]["tickles"] = 100)
	RewardHub.note_action(_gs)
	for i in 10:
		await process_frame
	await _snap(file)
	screen.free()
	hub.free()


func _shot_daily(win_size: Vector2i, file: String, kulanz: bool) -> void:
	_resize(win_size)
	var today := str(_gs.clock.local_day())
	var last := DailyBonus.prev_day(today)
	if kulanz:
		last = DailyBonus.prev_day(last)
	_gs.update(
		func(state: Dictionary) -> void: state["daily"] = {"lastClaimDay": last, "streak": 3}
	)
	PanelStack.clear()
	var popup := DailyBonusPopup.new()
	popup.theme = ThemeService.theme()
	popup.setup(_gs)
	root.add_child(popup)
	await _snap(file)
	popup.free()


func _snap(file: String) -> void:
	for i in SETTLE_FRAMES:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
