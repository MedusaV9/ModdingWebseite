extends TestCase
## G7-P56 EIN-SPIEL-GEFÜHL — Wächter für den gemeinsamen Minigame-RAHMEN
## (User-Feedback: „Viele Sachen fühlen sich wie EINZELNE Games an“):
## (1) Konsistenz-Inventar über die Registry: JEDES Spiel läuft durch den
##     einen Host-Rahmen (Root erbt MinigameBase), kein Spiel navigiert
##     selbst (SceneRouter-Bypass) oder baut eigene Results-/Pause-Overlays.
## (2) Pregame = Arcade-Raum: Arcade-Wallpaper, Spiel-Titel, Cover und der
##     Gooby-Sticker der Lade-Karte (dieselbe Figur durch Wipe→Pregame→Results).
## (3) Host-Countdown: EIN Auftakt-Look für alle 38 (TitleLabel, dominante
##     Ziffer mit Outline, mittig) + Rahmen-Overlays (Pause/Results) da.
## (4) Results: AcCardLg-Plate, Knopf-Reihenfolge Nochmal/Arcade/Home,
##     gleiche Abdunkelung wie das Pause-Modal, Gooby jubelt nur bei Sieg.
## (5) Wipe-Wache: Reisen decken/öffnen IMMER über das Veil (Rein- UND
##     Aus-Weg), Reduced Motion wählt den fade (= schneller Schnitt).

const HOST_SCENE := "res://scripts/minigames/minigame_host.tscn"
const PREGAME_SCENE := "res://scripts/minigames/pregame.tscn"
const RESULTS_SCENE := "res://scripts/minigames/results.tscn"
const ROUTER_SCRIPT := preload("res://scripts/core/scene_router.gd")
const FAKE_VEIL_SCRIPT := preload("res://tests/fixtures/fake_veil.gd")
const VEIL_WIPE := preload("res://scripts/core/loading_veil_wipe.gd")
const ROOM_A := "res://tests/fixtures/room_a.tscn"
const ROOM_B := "res://tests/fixtures/room_b.tscn"


## (1) Inventar-Wache: die Registry ist die EINE Quelle der Arcade — und
## jedes gelistete Spiel hängt am gemeinsamen Rahmen statt daneben.
func test_inventar_alle_spiele_im_gemeinsamen_rahmen() -> void:
	var games := MinigameRegistry.playable()
	assert_true(games.size() >= 38, "Registry kennt alle 38 Spiele (hat %d)" % games.size())
	for game: Dictionary in games:
		var id := str(game.get("id", "?"))
		var scene_path := str(game.get("scene", ""))
		assert_true(ResourceLoader.exists(scene_path), "%s: Szene existiert" % id)
		if not ResourceLoader.exists(scene_path):
			continue
		var root_script := _root_script_pfad(scene_path)
		assert_ne(root_script, "", "%s: Szene hat ein Root-Skript" % id)
		var quelle := _lies(root_script)
		assert_true(
			quelle.contains("extends MinigameBase"),
			"%s: Root erbt MinigameBase — läuft NUR im Host-Rahmen" % id
		)
		# Bypass-Wache: Navigation + Results/Pause gehören dem RAHMEN.
		for datei: String in _gd_dateien(scene_path.get_base_dir()):
			var src := _lies(datei)
			assert_false(src.contains("SceneRouter"), "%s: kein Router-Bypass (%s)" % [id, datei])
			assert_false(
				src.contains("MinigameResults") or src.contains("MinigamePauseModal"),
				"%s: kein eigener Results-/Pause-Eigenbau (%s)" % [id, datei]
			)
		# Einheitliche Pregame-Titel: title_key in BEIDEN Locales.
		var key := str(game.get("title_key", ""))
		assert_true(I18nService.table("de").has(key), "%s: DE-Titel %s fehlt" % [id, key])
		assert_true(I18nService.table("en").has(key), "%s: EN-Titel %s fehlt" % [id, key])


## (2) Pregame-Moment: Arcade-Wallpaper + Titel + Cover + Gooby-Vignette.
func test_pregame_zeigt_titel_cover_und_gooby() -> void:
	var pre: MinigamePregame = (load(PREGAME_SCENE) as PackedScene).instantiate()
	pre.auto_navigate = false
	pre.receive_params({"game_id": "teaParty"})
	tree.root.add_child(pre)
	await wait_frames(2)
	assert_true(pre.get_child(0) is AcWallpaper, "Arcade-Wallpaper statt nacktem ColorRect")
	var cover: TextureRect = pre.get("_cover")
	assert_ne(cover.texture, null, "Spiel-Cover geladen")
	var titel := _finde_title_label(pre.get("_card"))
	assert_ne(titel, null, "Titel-Label (TitleLabel-Typo) vorhanden")
	if titel != null:
		assert_eq(titel.text, I18nService.t("mg.teaParty.title"), "Titel = Spielname")
	var gooby := cover.get_node_or_null("GoobySticker")
	assert_true(gooby is LoadingVeilSticker, "Gooby-Sticker der Lade-Karte im Pregame")
	if gooby is LoadingVeilSticker:
		assert_true((gooby as LoadingVeilSticker).is_animated(), "ohne RM hüpft Gooby")
	pre.free()
	await wait_frames(1)


## (3) Countdown-Optik + Rahmen-Overlays: identisch für jedes Spiel, weil
## der HOST sie baut — die Wache pinnt den Look gegen Drift.
func test_host_countdown_und_overlays_einheitlich() -> void:
	_energie_auffuellen()
	var host: MinigameHost = (load(HOST_SCENE) as PackedScene).instantiate()
	host.auto_navigate = false
	host.countdown_step_sec = 0.0
	host.receive_params({"game_id": "carrotCatch", "difficulty": "normal", "seed": 99})
	tree.root.add_child(host)
	await wait_frames(2)
	var label: Label = host.get("_countdown_label")
	assert_ne(label, null, "Countdown-Label existiert")
	assert_eq(String(label.theme_type_variation), "TitleLabel", "Countdown in Titel-Typo")
	assert_true(
		label.has_theme_font_size_override("font_size"), "Ziffer dominiert (Größen-Override)"
	)
	assert_true(label.get_theme_font_size("font_size") >= 100, "Ziffer bleibt dominant")
	assert_true(label.has_theme_color_override("font_outline_color"), "Outline für jede Spielfarbe")
	assert_almost(label.anchor_left, 0.5, 1e-4, "Countdown mittig verankert")
	assert_true(host.get("_pause_modal") is MinigamePauseModal, "EIN Pause-Modal für alle")
	assert_true(host.get("_results") is MinigameResults, "EIN Results-Screen für alle")
	# Aus-Weg: Beenden meldet die Arcade als Ziel — die Navigation läuft in
	# Produktion über SceneRouter.goto und damit über DENSELBEN Veil-Wipe.
	var ziele: Array = []
	host.exit_requested.connect(
		func(target: StringName, _params: Dictionary) -> void: ziele.append(target)
	)
	host._on_quit_pressed()
	assert_eq(ziele, [&"arcade"] as Array, "Beenden reist zur Arcade (Router-Pfad)")
	host.queue_free()
	await wait_frames(2)


## (4) Results-Plate: EIN Look + EINE Knopf-Reihenfolge (Nochmal/Arcade/
## Home) + Gooby, der bei Sieg jubelt und bei 0 Punkten still bleibt.
func test_results_plate_knopfreihenfolge_und_gooby() -> void:
	var screen: MinigameResults = (load(RESULTS_SCENE) as PackedScene).instantiate()
	tree.root.add_child(screen)
	await wait_frames(1)
	var heim: Array = []
	screen.home_pressed.connect(func() -> void: heim.append(true))
	screen.show_results(
		{"score": 12, "coins": 3, "best": 20, "xp": 4}, {"title_key": "mg.teaParty.title"}
	)
	await wait_frames(2)
	var panel: PanelContainer = screen.get("_panel")
	assert_eq(String(panel.theme_type_variation), "AcCardLg", "Plate = Arcade-Karte")
	var dim := screen.get_child(0) as ColorRect
	assert_ne(dim, null, "Abdunkelung vorhanden")
	if dim != null:
		assert_eq(dim.color, MinigamePauseModal.DIM_COLOR, "gleiche Abdunkelung wie Pause")
	var again: Button = screen.get("_again")
	var back: Button = screen.get("_back")
	var home: Button = screen.get("_home")
	for btn: Button in [again, back, home]:
		assert_true(btn is SquishButton, "Rahmen-Knopf squisht (QW #3)")
	assert_eq(again.text, I18nService.t("mg.results.again"), "Knopf 1 = Nochmal")
	assert_eq(back.text, I18nService.t("mg.results.back"), "Knopf 2 = Zur Arcade")
	assert_eq(home.text, I18nService.t("mg.results.home"), "Knopf 3 = Nach Hause")
	assert_eq(String(again.theme_type_variation), "PrimaryButton", "Nochmal ist primär")
	assert_eq(again.get_parent(), back.get_parent(), "eine Knopf-Reihe")
	assert_eq(back.get_parent(), home.get_parent(), "eine Knopf-Reihe")
	assert_true(
		again.get_index() < back.get_index() and back.get_index() < home.get_index(),
		"Reihenfolge Nochmal → Arcade → Home"
	)
	home.pressed.emit()
	assert_eq(heim.size(), 1, 'Home-Knopf feuert home_pressed (Host reist &"home")')
	var gooby: Variant = screen.get("_gooby")
	assert_true(gooby is LoadingVeilSticker, "Gooby-Sticker auf der Plate")
	if gooby is LoadingVeilSticker:
		assert_true((gooby as LoadingVeilSticker).is_animated(), "Sieg: Gooby jubelt")
	# 0 Punkte: derselbe Rahmen, aber Gooby bleibt still (Trost-Moment).
	screen.show_results({"score": 0}, {"title_key": "mg.teaParty.title"})
	await wait_frames(1)
	gooby = screen.get("_gooby")
	if gooby is LoadingVeilSticker:
		assert_false((gooby as LoadingVeilSticker).is_animated(), "0 Punkte: Gooby still")
	screen.free()
	await wait_frames(1)


## (2/4) RM-Zweig: Reduced Motion friert die Gooby-Sticker in Pregame UND
## Results ein — Töne/Layout bleiben, Bewegung stoppt.
func test_rm_zweig_friert_gooby_ein() -> void:
	var settings: Node = tree.root.get_node_or_null("/root/AppSettings")
	assert_ne(settings, null, "AppSettings-Autoload vorhanden")
	if settings == null:
		return
	var vorher: Variant = settings.get_setting("reduced_motion", false)
	settings.set_setting("reduced_motion", true)
	var pre: MinigamePregame = (load(PREGAME_SCENE) as PackedScene).instantiate()
	pre.auto_navigate = false
	pre.receive_params({"game_id": "teaParty"})
	tree.root.add_child(pre)
	await wait_frames(1)
	var cover: TextureRect = pre.get("_cover")
	var gooby := cover.get_node_or_null("GoobySticker")
	if gooby is LoadingVeilSticker:
		assert_false((gooby as LoadingVeilSticker).is_animated(), "RM: Pregame-Gooby steht")
	pre.free()
	var screen: MinigameResults = (load(RESULTS_SCENE) as PackedScene).instantiate()
	tree.root.add_child(screen)
	await wait_frames(1)
	screen.show_results({"score": 50}, {"title_key": "mg.teaParty.title"})
	var sticker: Variant = screen.get("_gooby")
	if sticker is LoadingVeilSticker:
		assert_false((sticker as LoadingVeilSticker).is_animated(), "RM: Results-Gooby steht")
	screen.free()
	settings.set_setting("reduced_motion", vorher)
	await wait_frames(1)


## (5) Wipe-Wache: JEDE Reise (rein ins Spiel, raus zur Arcade) deckt mit
## dem Veil und öffnet es wieder — Muster test_scene_router (Fake-Veil).
func test_wipe_deckt_rein_und_aus_weg() -> void:
	var router: Node = ROUTER_SCRIPT.new()
	var veil: Node = FAKE_VEIL_SCRIPT.new()
	router.install_veil(veil)
	router.min_shown_ms = 0
	var mount := Node.new()
	tree.root.add_child(mount)
	tree.root.add_child(router)
	router.set_mount_point(mount)
	router.register_route(&"mg_host", ROOM_A)
	router.register_route(&"arcade", ROOM_B)
	var fertig: Array = []
	router.travel_finished.connect(func(target: StringName) -> void: fertig.append(target))
	router.goto(&"mg_host", {"game_id": "teaParty"})
	var rein := await wait_until(func() -> bool: return fertig.size() == 1)
	assert_true(rein, "Rein-Weg kommt an")
	assert_eq(veil.cover_calls, 1, "Rein-Weg deckt über das Veil (Wipe)")
	assert_eq(veil.reveal_calls, 1, "…und öffnet es wieder")
	router.goto(&"arcade", {})
	var raus := await wait_until(func() -> bool: return fertig.size() == 2)
	assert_true(raus, "Aus-Weg kommt an")
	assert_eq(veil.cover_calls, 2, "Aus-Weg nutzt DENSELBEN Wipe (kein harter Schnitt)")
	assert_eq(veil.reveal_calls, 2, "…und öffnet ihn wieder")
	# Reduced Motion wählt den fade (= schneller Schnitt), sonst petal.
	assert_eq(VEIL_WIPE.wipe_variante(true), "fade", "RM = schneller Schnitt")
	assert_eq(VEIL_WIPE.wipe_variante(false), "petal", "Standard = Blütenblätter-Wipe")
	mount.queue_free()
	router.queue_free()
	veil.free()
	await wait_frames(1)


## ── Helfer ───────────────────────────────────────────────────────────────


func _energie_auffuellen() -> void:
	var gs := tree.root.get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("set_value"):
		gs.call("set_value", "gooby.stats.energy", 100.0)


func _lies(pfad: String) -> String:
	var file := FileAccess.open(pfad, FileAccess.READ)
	return file.get_as_text() if file != null else ""


## Skript-Pfad des ROOT-Knotens einer .tscn (Text-Parse, kein Instanziieren
## der 38 teils schweren 3D-Szenen): ext_resource-IDs sammeln, dann die
## `script = ExtResource("…")`-Zeile der ersten Node-Sektion auflösen.
func _root_script_pfad(scene_path: String) -> String:
	var txt := _lies(scene_path)
	var skripte := {}
	var ext := RegEx.new()
	ext.compile('\\[ext_resource type="Script"[^\\]]*path="([^"]+)"[^\\]]*id="([^"]+)"')
	for treffer in ext.search_all(txt):
		skripte[treffer.get_string(2)] = treffer.get_string(1)
	var root_start := txt.find("[node name=")
	if root_start < 0:
		return ""
	var root_ende := txt.find("[node name=", root_start + 1)
	var sektion := txt.substr(root_start, -1 if root_ende < 0 else root_ende - root_start)
	var zeile := RegEx.new()
	zeile.compile('script = ExtResource\\("([^"]+)"\\)')
	var script := zeile.search(sektion)
	if script == null:
		return ""
	return str(skripte.get(script.get_string(1), ""))


## Alle .gd-Dateien unter einem Spiel-Ordner (rekursiv, für die Bypass-Wache).
func _gd_dateien(ordner: String) -> Array[String]:
	var out: Array[String] = []
	var stapel: Array[String] = [ordner]
	while not stapel.is_empty():
		var dir_pfad: String = stapel.pop_back()
		var dir := DirAccess.open(dir_pfad)
		if dir == null:
			continue
		for sub in dir.get_directories():
			stapel.append("%s/%s" % [dir_pfad, sub])
		for datei in dir.get_files():
			if datei.ends_with(".gd"):
				out.append("%s/%s" % [dir_pfad, datei])
	return out


## Erstes Label mit TitleLabel-Typo unter einem Ast (Pregame-Titel).
func _finde_title_label(wurzel: Node) -> Label:
	for node in (wurzel as Control).find_children("*", "Label", true, false):
		if (node as Label).theme_type_variation == &"TitleLabel":
			return node
	return null
