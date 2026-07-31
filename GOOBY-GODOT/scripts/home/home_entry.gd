class_name HomeEntry
extends Node
## Zuhause-Einstieg (W2a HOUSE): registriert die Raum-Routen am W1a-Router,
## zeigt bei frischen Saves das W1c-Onboarding und lädt danach das
## Wohnzimmer. Dazu W1c-HUD (Bau-Button → Baumodus des aktuellen Raums) und
## Live-Werte aus dem W1d-GameState.
##
## main.gd (W1a) soll diese Szene statt des Platzhalter-Homes instanzieren —
## Request: /tmp/gooby-godot/handoffs/W2a-boot-request.md.

const START_ROOM := "living"

const Economy := preload("res://scripts/logic/economy.gd")

var _router: Node
var _gs: Node
var _net: Node
var _hud: Hud
var _toasts: ToastLayer
var _settings: Control
var _safe_mode_banner: Control
## HUD erst nach Onboarding erlaubt; Sichtbarkeit folgt danach dem Router:
## nur in Räumen (RoomBase) an, über Vollbild-Screens aus (E5-F1).
var _hud_enabled := false

@onready var _world: Node3D = $World
@onready var _ui_layer: CanvasLayer = $UiLayer


func _ready() -> void:
	HomeState.register_slice()
	# W3-Integration (Orchestrator): Content-Slices + Routen aller Screens.
	RandomEventEngine.register_slice()
	GoobyBuffs.register_slice()
	BadState.register_slice()
	# W13B: Bücher-Abnutzung der Geschichten-Stunde (story-Slice).
	StoryTime.register_slice()
	_router = get_node_or_null("/root/SceneRouter")
	_gs = get_node_or_null("/root/GameState")
	if _router != null:
		_router.register_routes(RoomDefs.route_table())
		_router.set_mount_point(_world)
		CityScene.register_routes(_router)
	ArcadeScreen.register_routes()
	AlbumScreen.register_routes()
	SocialScreen.register_routes()
	VisitScene.register_routes()
	BattleshipScene.register_routes()
	ChessScene.register_routes()
	_build_hud()
	# EF-1/EVAL-1 D2: globale Sticker-Auswertung + Feier (Toast+Ton+Konfetti)
	# — feuert nach JEDER Handlung, egal welcher Screen offen ist.
	if _gs != null:
		RewardHub.attach_to(self, _gs)
		# REST-2: Tagesquests (Roll/Claim/Bonus + „Was nun?“-Hinweis).
		DailyQuestService.attach_to(self, _gs)
	if _router != null and _router.has_signal("travel_finished"):
		_router.travel_finished.connect(_on_travel_finished)
	if _router != null and _router.has_signal("travel_started"):
		_router.travel_started.connect(_on_travel_started)
	_wire_net()
	_setup_safe_mode_banner()
	_roll_random_event()
	if _gs != null and not bool(_gs.get_value("onboarding.done", false)):
		# W6/FIX-6: erster Start — liegt noch ein Spielstand der alten
		# Capacitor-App im selben Bundle-Container? Dann zuerst das
		# Uebernahme-Angebot zeigen, sonst normal ins Onboarding.
		if _offer_legacy_transfer():
			return
		_show_onboarding()
	else:
		_start_home()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED:
		_roll_random_event()


func _roll_random_event() -> void:
	if _gs == null:
		return
	var defs := RandomEventEngine.defs_from_registry()
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	var uhr := Time.get_datetime_dict_from_system()
	var minuten: int = int(uhr["hour"]) * 60 + int(uhr["minute"])
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	RandomEventEngine.roll_on_start(_gs, defs, now_ms, minuten, rng)


## Beim Reiseantritt sofort ausblenden (der Veil deckt derweil ab) — sonst
## überlappen HUD-Buttons/Status-Kapseln beim Aufdecken kurz den Zielscreen.
## W13: Raumwechsel/Screen-Öffnen schaltet auch das Interaktions-Auge ab
## (der Spotlight im alten Raum stirbt mit der Szene, der HUD-Knopf nicht).
func _on_travel_started(_target: StringName = &"", _travel_type: int = 0) -> void:
	if _hud != null:
		_hud.visible = false
	_spotlight_aus()


func _on_travel_finished(target: Variant = null) -> void:
	_update_hud_visibility()
	_report_presence(target)
	var room := _current_room()
	if room == null:
		return
	# W3d-Hooks: Bad-Suite/Geschichten-Stunde + aktives Random-Event pro Raum.
	InteractablesHost.attach_to(room)
	EventRunner.attach_to(room)
	# FB-6/SEELE-Hook: Begrüßungen, Rituale, Erinnerungen, Idle-Leben.
	GoobyReactions.attach_to(room)
	# REST-3: Schlaf-/Krankheits-/Gewichts-Optik (Pflege-Kreislauf sichtbar).
	PflegeRunner.attach_to(room)


## HUD nur im Raum (RoomBase) zeigen — Album/Arcade/Social/Stadt sind
## Vollbild-Screens, dort verdeckten HUD-Buttons vorher Inhalte (E5-F1).
func _update_hud_visibility() -> void:
	if _hud == null:
		return
	_hud.visible = _hud_enabled and _current_room() != null


func _build_hud() -> void:
	_hud = (load("res://scripts/ui/hud.tscn") as PackedScene).instantiate()
	_hud.visible = false
	_ui_layer.add_child(_hud)
	_toasts = ToastLayer.new()
	_toasts.set_anchors_preset(Control.PRESET_FULL_RECT)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_toasts)
	_hud.action_pressed.connect(_on_hud_action)
	# E12 P1: das HUD-Zahnrad öffnet den Settings-Screen (inkl. Update-Glue).
	if _hud.has_signal("settings_pressed"):
		_hud.settings_pressed.connect(_open_settings)
	# W13/HUD-WIRES: „Wo ist mein Gooby?"-Chip + Interaktions-Auge verdrahten
	# (beide Signale hatten repo-weit keinen Consumer — P5-Befund F2/F11).
	if _hud.has_signal("where_is_gooby_pressed"):
		_hud.where_is_gooby_pressed.connect(_on_where_is_gooby_pressed)
	if _hud.has_signal("eye_toggled"):
		_hud.eye_toggled.connect(_on_eye_toggled)
	if _gs == null:
		return
	_gs.coins_changed.connect(func(coins: int) -> void: _hud.set_coins(coins))
	_gs.stats_changed.connect(_on_stats_changed)
	_gs.level_changed.connect(func(level: int, ratio: float) -> void: _hud.set_level(level, ratio))
	_hud.set_coins(int(_gs.get_value("economy.coins", 0)))
	_on_stats_changed(_gs.get_value("gooby.stats", {}))
	_hud.set_level(int(_gs.get_value("progression.level", 1)), _gs.xp_ratio())


func _on_stats_changed(stats: Dictionary) -> void:
	(
		_hud
		. set_stats(
			{
				"hunger": float(stats.get("hunger", 80.0)),
				"energie": float(stats.get("energy", 90.0)),
				"hygiene": float(stats.get("hygiene", 85.0)),
				"spass": float(stats.get("fun", 70.0)),
			}
		)
	)


func _on_hud_action(action: StringName) -> void:
	if action == &"bau":
		var room := _current_room()
		if room != null:
			room.open_build_mode()
		return
	if _dispatch_to_screens(action):
		return
	if action == &"reise" and _router != null:
		_router.goto(CityScene.ROUTE_CITY)
		return
	_toasts.show_toast(I18nService.t("home.aktion_bald"))


## Reicht die HUD-Aktion der Reihe nach an die selbstregistrierten Screens
## weiter; der erste, der zustaendig ist, gewinnt. Neue Screens haengen hier
## eine Zeile an (statt in `_on_hud_action`, das sonst die Return-Grenze reisst).
func _dispatch_to_screens(action: StringName) -> bool:
	if ArcadeScreen.handle_hud_action(action):
		return true
	if AlbumScreen.handle_hud_action(action):
		return true
	if WardrobeScreen.handle_hud_action(action):
		return true
	if IkeaScreen.handle_hud_action(action):
		return true
	# REST-2: Quests-Knopf öffnet das Tagesquest-Panel (mit Customize geteilt,
	# damit die Return-Grenze des Linters haelt — `or` kurzschliesst wie zuvor).
	# REST-1 (P1-Fix): der Profil-Knopf öffnet jetzt den ECHTEN Profil-Screen
	# (vorher fälschlich der Social-Screen „Freunde & Besuche“ — der bleibt
	# vom Profil aus erreichbar).
	if (
		CustomizeScreen.handle_hud_action(action)
		or DailyQuestService.handle_hud_action(action)
		or ProfilScreen.handle_hud_action(action)
	):
		return true
	# W6: die Handy-Shell ersetzt den direkten GOOBERANDO-Aufruf — sie haengt
	# dieselbe App als Kachel ein und bringt Taxi/Guber/Kamera/Pal dazu.
	return PhoneShell.handle_hud_action(action, self, _gs)


func _current_room() -> RoomBase:
	if _router == null:
		return null
	return _router.get_current_scene() as RoomBase


## --- W13/HUD-WIRES: „Wo ist mein Gooby?" + Interaktions-Auge ---


## Der HUD-Chip holt die Kamera zurück zu Gooby und zeigt die Tat-Bubble
## (Flow + pure Entscheidung leben in GoobyHome.wo_ist_gooby — ohne Gooby
## im Raum bleibt der Chip still, s. GoobyHome.suche_reaktion).
func _on_where_is_gooby_pressed() -> void:
	var room := _current_room()
	if room == null:
		return
	var gooby := room.gooby()
	if gooby != null:
		gooby.wo_ist_gooby()


## Das HUD-Auge schaltet die Interaktions-Anzeige des aktuellen Raums an/aus.
## Schaltet der Spotlight sich selbst ab (Baumodus), folgt der HUD-Knopf
## über das `deaktiviert`-Signal.
func _on_eye_toggled(active: bool) -> void:
	var room := _current_room()
	if room == null:
		if active and _hud != null:
			_hud.set_eye_active(false)
		return
	var spot := InteractionSpotlight.attach_to(room)
	if not spot.deaktiviert.is_connected(_on_spotlight_deaktiviert):
		spot.deaktiviert.connect(_on_spotlight_deaktiviert)
	spot.set_aktiv(active)


func _on_spotlight_deaktiviert() -> void:
	if _hud != null:
		_hud.set_eye_active(false)


## Interaktions-Anzeige + HUD-Auge hart ausschalten (Raumwechsel/Settings).
func _spotlight_aus() -> void:
	if _hud != null:
		_hud.set_eye_active(false)
	var room := _current_room()
	if room == null:
		return
	var spot := room.get_node_or_null("InteractionSpotlight")
	if spot is InteractionSpotlight:
		(spot as InteractionSpotlight).set_aktiv(false)


## Sucht den Alt-Spielstand der Web-App (NSUserDefaults-Spiegelung, gleiche
## Bundle-Id). Fund → Uebernahme-Screen (er routet danach selbst heim) und
## `true`, sonst `false`. Billig: ein Datei-Read; ohne Fund kein Sonderfall.
func _offer_legacy_transfer() -> bool:
	if _router == null:
		return false
	var svc := load("res://scripts/state/import/transfer_service.gd")
	var probe: Dictionary = svc.probe_legacy(int(Time.get_unix_time_from_system() * 1000.0))
	if not bool(probe.get("found", false)):
		return false
	TransferScreen.register_routes()
	_router.goto(TransferScreen.ROUTE)
	return true


func _show_onboarding() -> void:
	var flow: OnboardingFlow = (
		(load("res://scripts/ui/onboarding/onboarding_flow.tscn") as PackedScene).instantiate()
	)
	_ui_layer.add_child(flow)
	flow.completed.connect(
		func(profile: Dictionary) -> void:
			if _gs != null:
				_gs.apply_onboarding_profile(profile)
			flow.queue_free()
			_start_home()
	)


func _start_home() -> void:
	_hud_enabled = true
	_hud.visible = true
	# REST-2: handlungsgeführte erste Viertelstunde (nur frische Saves;
	# Bestands-Saves werden im attach_to still als erledigt markiert).
	if _gs != null:
		OnboardingGuide.attach_to(self, _gs)
	if _router != null:
		_router.goto(RoomDefs.route_target(START_ROOM))


## --- E14-Wiring: Analytics / Server-Events / Redeem / Presence (P1-1/4/5) ---


func _wire_net() -> void:
	_net = get_node_or_null("/root/Net")
	if _net == null:
		return
	# P1-1: Spielzeit zählt ab Sekunde 0 — idempotent (das Net-Autoload hat
	# die Session normalerweise schon beim Boot gestartet + gepuffert).
	var analytics: Variant = _net.get("analytics")
	if analytics != null and analytics.has_method("start_session"):
		analytics.start_session()
	# P1-4: Server-Events (Panel-getriggert) sichtbar machen.
	var events: Variant = _net.get("server_events")
	if events != null and events.has_signal("event_received"):
		events.event_received.connect(_on_server_event)
	# P1-3: Redeem-Ergebnisse (auch aus dem Offline-Outbox-Flush) anwenden.
	var redeem: Variant = _net.get("redeem")
	if redeem != null and redeem.has_signal("redeemed"):
		redeem.redeemed.connect(_on_code_redeemed)
		redeem.redeem_failed.connect(_on_code_redeem_failed)


## P1-4: sichtbare Wirkung — Toast „Event: <name>“ (minimaler Hook ins
## Content-System; RandomEventEngine rollt weiter lokal, s. _roll_random_event).
func _on_server_event(_id: String, type: String, params: Dictionary) -> void:
	var event_name := str(params.get("name", type))
	_toasts.show_toast(I18nService.t("net.server_event.toast", {"name": event_name}))


## P1-3: Reward lokal anwenden (Coins über den EINEN Geld-Pfad) + Toast.
func _on_code_redeemed(code: String, reward: Dictionary) -> void:
	var coins := int(reward.get("coins", 0))
	if coins > 0 and _gs != null and _gs.has_method("update"):
		_gs.update(
			func(s: Dictionary) -> void:
				var econ: Dictionary = s.get("economy", {})
				Economy.award(econ, coins, "code_redeem")
		)
	_toasts.show_toast(I18nService.t("net.redeem.ok", {"code": code}))


func _on_code_redeem_failed(code: String, error: String) -> void:
	_toasts.show_toast(I18nService.t("net.redeem.err", {"code": code, "error": error}))


## P1-5: Aktivität an den Freunde-Tab melden — bei jedem Router-Ziel.
func _report_presence(target: Variant) -> void:
	if _net == null:
		return
	var presence: Variant = _net.get("presence")
	if presence == null or not presence.has_method("set_kind"):
		return
	var game_id := ""
	var scene: Node = _router.get_current_scene() if _router != null else null
	if scene != null and scene.get("game_id") != null:
		game_id = str(scene.get("game_id"))
	presence.set_kind(PresenceService.kind_for_route(str(target), game_id))


## --- E12-Wiring: Settings-Screen + Update-Toasts + Safe-Mode-Banner ---


func _open_settings() -> void:
	if _settings != null and is_instance_valid(_settings):
		return
	# W13: Vollbild-Screen über dem Raum → Interaktions-Auge aus.
	_spotlight_aus()
	_settings = (load("res://scripts/ui/settings_screen.tscn") as PackedScene).instantiate()
	_settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var glue := SettingsUpdateGlue.new()
	glue.name = "UpdateGlue"
	_settings.add_child(glue)
	_ui_layer.add_child(_settings)
	glue.attach(_settings)
	if _settings.has_signal("back_pressed"):
		_settings.back_pressed.connect(_close_settings)
	if _hud != null:
		_hud.visible = false


func _close_settings() -> void:
	if _settings != null and is_instance_valid(_settings):
		_settings.queue_free()
	_settings = null
	_update_hud_visibility()


func _setup_safe_mode_banner() -> void:
	var loader := get_node_or_null("/root/PackLoader")
	if loader == null:
		return
	if loader.has_signal("safe_mode_entered"):
		loader.safe_mode_entered.connect(_show_safe_mode_banner)
	if loader.has_method("is_safe_mode") and loader.is_safe_mode():
		_show_safe_mode_banner()


func _show_safe_mode_banner() -> void:
	if _safe_mode_banner != null and is_instance_valid(_safe_mode_banner):
		return
	var banner := PanelContainer.new()
	banner.name = "SafeModeBanner"
	banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = I18nService.t("updates.safe_mode")
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var retry := Button.new()
	retry.text = I18nService.t("updates.erneut_versuchen")
	retry.custom_minimum_size = Vector2(0, 48)
	retry.focus_mode = Control.FOCUS_NONE
	retry.pressed.connect(_on_safe_mode_retry)
	row.add_child(retry)
	banner.add_child(row)
	_ui_layer.add_child(banner)
	_safe_mode_banner = banner


func _on_safe_mode_retry() -> void:
	var loader := get_node_or_null("/root/PackLoader")
	if loader != null and loader.has_method("reenable_all_packs"):
		loader.reenable_all_packs()
	if _safe_mode_banner != null and is_instance_valid(_safe_mode_banner):
		_safe_mode_banner.queue_free()
		_safe_mode_banner = null
	_toasts.show_toast(I18nService.t("updates.update_geladen"))
