class_name Kuehlschrank
extends Node3D
## Kühlschrank-Interactable (EF-1 → W14/FRIDGE „Kühlschrank 2.0"). Tap öffnet
## statt der flachen Text-Liste ein appetitliches Regal-Grid (FuetterGrid:
## AC-Karten mit echter 3D-Vorschau, Vorrats-Badge, Stat-Pillen, Kategorien-
## Chips; leerer Vorrat = Gähn-Leerzustand + „Zu REHWEI fahren"-Route).
## Nach der Auswahl wird NICHT mehr sofort gebucht: die FuetterRegie spielt
## die Mampf-Sequenz (Speise schwebt zu Gooby, mouth_open-Bisse, Krümel,
## Schluck, Emotion — ~2,5 s, Doppel-Tap abgewehrt, Reduced Motion =
## Kurzfassung), ERST DANACH bucht FoodCatalog.apply_feed wie bisher (Stats +
## Junk-Gewicht + feeds-Counter + treats-Sammlung — Semantik unverändert),
## gefolgt von RewardHub.note_action, Reward-Floats, Bubble-Spruch
## (AcBubble-Vertrag, 8 rotierende Sprüche je Kategorie) und Erfolgs-Haptik.
## Refusals bleiben EXAKT wie bisher: satt wird VOR Panel/Sequenz geprüft
## (FoodCatalog.too_full), apply_feed bleibt fail-closed.

const HERZ_TEILE := 12

var _host: InteractablesHost
var _panel: FuetterGrid
var _busy := false


func setup(host: InteractablesHost, furniture: Node3D) -> void:
	_host = host
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


# ── Regal-Panel ───────────────────────────────────────────────────────────────


func _open_panel() -> void:
	_close_panel()
	AudioDirector.try_play(self, "ui_open")
	var gs := _host.game_state()
	var entries: Array[Dictionary] = []
	if gs != null:
		entries = FoodCatalog.inventory_entries(gs.state())
	_panel = FuetterGrid.new()
	_panel.name = "KuehlschrankPanel"
	_panel.setup(entries)
	_panel.speise_gewaehlt.connect(_on_food_chosen)
	_panel.rehwei_gewuenscht.connect(_on_rehwei_gewuenscht)
	_panel.schliessen_gewuenscht.connect(
		func() -> void:
			AudioDirector.try_play(self, "ui_close")
			_close_panel()
	)
	_ui_layer().add_child(_panel)


func _close_panel() -> void:
	if _panel != null and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null


## Leerzustands-Knopf: NUR der Route-Aufruf zum REHWEI-Laden.
func _on_rehwei_gewuenscht() -> void:
	AudioDirector.try_play(self, "ui_click")
	_close_panel()
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("goto"):
		router.goto(&"city/ort/rehwei", {})


# ── Fütter-Ablauf ─────────────────────────────────────────────────────────────


func _on_food_chosen(food_id: String) -> void:
	AudioDirector.try_play(self, "ui_click")
	_close_panel()
	_fuettere(food_id)


func _fuettere(food_id: String) -> void:
	if _busy:
		return  # Doppel-Tap-Guard (zweite Sicherung neben FuetterSequenz.start)
	var gs := _host.game_state()
	if gs == null:
		return
	# Refusal-Kurzschluss VOR der Sequenz — bestehende Gates, nicht dupliziert.
	var grund := FuetterSequenz.refusal(gs.state(), food_id)
	if grund == "satt":
		_say_text(I18nService.t("rewards.fuettern.satt"))
		return
	if not grund.is_empty():
		return
	_busy = true
	var gooby := _gooby()
	if gooby != null:
		gooby.set_wander_enabled(false)
		await gooby.walk_to(global_position + Vector3(0.3, 0.0, 0.7), 5.0)
	var regie := FuetterRegie.new()
	add_child(regie)
	var durchgelaufen := await regie.ablauf(
		gooby, food_id, global_position + Vector3(0.0, 0.95, 0.35), RewardFx.reduced_motion(self)
	)
	regie.queue_free()
	# Buchung ERST NACH dem Sequenz-Ende — Semantik unverändert (apply_feed
	# prüft satt/Vorrat selbst fail-closed nach).
	var result := {}
	if durchgelaufen:
		gs.update(
			func(state: Dictionary) -> void:
				var applied := FoodCatalog.apply_feed(state, food_id)
				result.merge(applied, true)
		)
	if not result.is_empty():
		RewardHub.note_action(gs)
		_show_reward(gooby, result)
		# W14/UIKERN-Vertrag direkt: AcBubble-Spruch (Tail auf Gooby) + Haptik.
		var opts := {}
		if gooby is Node3D:
			opts["speaker_3d"] = gooby
		AcBubble.show_bubble(_ui_layer(), FuetterSprueche.naechster(food_id), opts)
		Haptics.success(self)
	if gooby != null:
		gooby.set_wander_enabled(true)
	_busy = false


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
