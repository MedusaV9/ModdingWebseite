class_name MorgenSequenz
extends Node
## Morgen-Sequenz (G8/IDEA-SEELE, Idee 1 — Bühnen-Hälfte): serialisiert die
## Overlay-Kette nach dem Home-Start zu Ritual → Tagesbonus → Guide-Tour,
## NACHEINANDER statt gestapelt — genau der PT4-B7/PT1-B6-Befund
## („Tagesbonus-Schleier über der Guide-Tour“). home_entry._start_home hängt
## diesen Node VOR dem Router-goto an; er:
##  1. setzt die Bonus-Bremse am RewardHub (der Hub fragt haelt_bonus() —
##     seine Auto-Angebote warten, bis die Kette den Bonus-Schritt erreicht),
##  2. plant das Ritual (MorgenRitual.faellig, PURE) und stempelt bei Zusage
##     SOFORT Gruß-Tag + Gate + Ambient-Bremse — GoobyReactions._run_enter
##     läuft bei der Ankunft VOR uns und würde sonst doppelt grüßen,
##  3. spielt nach travel_finished die Aufwach-Klammer: Licht-Sweep von
##     Nacht- auf Ist-Profil (HomeLicht), Gooby streckt sich
##     (CLIP_IDLE_STRETCH), EIN warmer Tages-Gruß mit echtem Ausblick
##     (Wetter/Quest/Markttag) — per Tap überspringbar, Reduced Motion =
##     statisch (kein Sweep, kurzer Halt),
##  4. bietet DANN den Tagesbonus an (RewardHub.offer_daily_bonus_now) und
##     wartet, bis das Popup zu ist,
##  5. hängt ZULETZT die Guide-Tour an (OnboardingGuide.attach_to) und räumt
##     sich weg — die Bremse löst sich mit dem Node.
##
## Frische Saves (Tag 0): kein Ritual (MorgenRitual gated), die Kette ist
## dann nur Bonus → Guide — exakt die alte Reihenfolge, nur entzerrt.

signal fertig

const GROUP := &"morgen_sequenz"

## Licht-Sweep-Dauer (Nacht → Ist-Profil).
const LICHT_SWEEP_S := 2.2
## Halte-Dauer der Klammer (Gruß lesbar), per Tap abkürzbar.
const HALT_S := 2.8
const HALT_REDUZIERT_S := 0.4
## Streck-Clip-Dauer (zeitbegrenzter Loop über play_clip_for).
const STRECK_S := 1.6
## Start-Stunde des Nacht-Profils für den Sweep.
const NACHT_STUNDE := 4.0

var _gs: Object = null
var _entry: Node = null
var _ritual_geplant := false
var _bonus_frei := false
var _skip := false
var _skip_layer: CanvasLayer = null
## Licht-Endzustand fürs Skip-Snapping: [Objekt, Property, Zielwert].
var _licht_ziele: Array[Array] = []
var _licht_tween: Tween = null


## Sequenz an den Home-Entry hängen (idempotent, VOR dem Router-goto rufen —
## die Bremse muss stehen, bevor travel_finished den Bonus anstoßen kann).
static func starten(entry: Node, gs: Object) -> MorgenSequenz:
	var tree := entry.get_tree()
	if tree != null:
		var existing := tree.get_first_node_in_group(GROUP)
		if existing is MorgenSequenz:
			return existing
	var sequenz := MorgenSequenz.new()
	sequenz.name = "MorgenSequenz"
	sequenz._gs = gs
	sequenz._entry = entry
	entry.add_child(sequenz)
	return sequenz


func _ready() -> void:
	add_to_group(GROUP)
	if _gs == null:
		_guide_schritt()
		queue_free()
		return
	var hub := RewardHub.find(self)
	if hub != null:
		hub.bonus_bremse_setzen(self)
	_ritual_geplant = _plane_ritual()
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_signal("travel_finished"):
		router.travel_finished.connect(_on_ankunft, CONNECT_ONE_SHOT)
	else:
		_on_ankunft.call_deferred()


## RewardHub-Gate: solange true, hält der Hub seine Auto-Bonus-Angebote
## zurück (Onboarding-Slice-Hook, erste Ankunft, App-Resume).
func haelt_bonus() -> bool:
	return not _bonus_frei


# ── Planung (vor der Ankunft) ─────────────────────────────────────────────────


## Ritual planen + bei Zusage sofort stempeln. Muss VOR travel_finished
## laufen: GoobyReactions._run_enter (hängt früher am Signal) liest
## lastGreetDay und bleibt so still — kein Doppel-Gruß, keine Stapel.
func _plane_ritual() -> bool:
	var state: Dictionary = _gs.state()
	var ctx := _ritual_ctx()
	if not MorgenRitual.faellig(state, ctx):
		return false
	# Steht heute ein ECHTES Seelen-Ritual an (Geburtstag/Jubiläum/Feiertag/
	# erster Schnee)? Dann gehört die Bühne ihm — Probe mit neutralem Roll
	# (die Ritual-Stufe von decide_enter ist roll-unabhängig).
	var slice := SoulState.slice_of(_gs)
	var probe := SoulService.decide_enter(
		state, slice, SoulService.defs_from_registry(), _probe_ctx(ctx), 0.5
	)
	if str(probe.get("kind", "")) == "ritual":
		return false
	SoulState.mutate(_gs, func(s: Dictionary) -> void: MorgenRitual.stempeln(s, ctx))
	return true


## Entscheidungs-Kontext (Uhrzeit IMMER über die pinnbare GameState-Clock).
func _ritual_ctx() -> Dictionary:
	var now := _now_ms()
	var zeit := MorgenRitual.lokale_zeit(now, _offset_min())
	return {
		"now_ms": now,
		"heute": _heute(),
		"stunde": int(zeit.get("hour", 12)),
		"wochentag": int(zeit.get("weekday", 0)),
	}


## decide_enter-Probe-Kontext (nur die Ritual-Stufe interessiert).
func _probe_ctx(ctx: Dictionary) -> Dictionary:
	var zeit := MorgenRitual.lokale_zeit(int(ctx["now_ms"]), _offset_min())
	return {
		"now_ms": int(ctx["now_ms"]),
		"date": zeit,
		"hour": int(ctx["stunde"]),
		"gap_ms": 0,
		"wetter": SoulWetter.zustand(str(ctx["heute"]), float(ctx["stunde"])),
		"player_name": str(_gs.get_value("meta.playerName", "")),
		"nickname": str(_gs.get_value("meta.goobyNickname", "Gooby")),
	}


# ── Kette (nach der Ankunft) ──────────────────────────────────────────────────


func _on_ankunft(_ziel: Variant = null) -> void:
	_kette()


func _kette() -> void:
	if _ritual_geplant:
		await _spiele_ritual()
	await _bonus_schritt()
	_guide_schritt()
	fertig.emit()
	queue_free()


## Aufwach-Klammer im aktuellen Raum — jeder Teil fällt einzeln weich aus
## (kein Raum/kein Gooby/kein Licht → Rest spielt trotzdem).
func _spiele_ritual() -> void:
	var room := _aktueller_raum()
	if room == null:
		return
	_skip = false
	_skip_layer_einbauen()
	var reduced := ThemeService.is_reduced_motion(room)
	var gooby: Variant = room.gooby() if room.has_method("gooby") else null
	if not reduced:
		_licht_sweep_starten(room)
	if gooby != null:
		gooby.set_wander_enabled(false)
		if gooby.get("rig") != null:
			gooby.rig.set_emotion("happy")
			if not reduced:
				gooby.rig.play_clip_for(GoobyRig.CLIP_IDLE_STRETCH, STRECK_S)
	AudioDirector.try_play(self, "ui_open")
	if room.has_method("say"):
		room.say(_gruss_text())
	await _warte_oder_skip(HALT_REDUZIERT_S if reduced else HALT_S)
	_licht_fertigstellen()
	if gooby != null and is_instance_valid(gooby):
		gooby.set_wander_enabled(true)
	_skip_layer_abbauen()


## Tagesbonus JETZT anbieten (Bremse löst sich) und aufs Schließen warten —
## Abholen, Später, Backdrop und Reise-Abbruch enden alle im tree_exited.
func _bonus_schritt() -> void:
	_bonus_frei = true
	var hub := RewardHub.find(self)
	if hub == null:
		return
	var popup := hub.offer_daily_bonus_now()
	if popup == null:
		return
	await popup.tree_exited


func _guide_schritt() -> void:
	if _entry != null and is_instance_valid(_entry) and _gs != null:
		OnboardingGuide.attach_to(_entry, _gs)


# ── Licht-Sweep ───────────────────────────────────────────────────────────────


## Ist-Licht als Ziel EINFANGEN, auf Nacht-Profil schneiden, weich zurück —
## so endet der Sweep exakt im Zustand, den der Raum selbst gebaut hat
## (kein Profil-Nachrechnen, kein Sprung am Ende).
func _licht_sweep_starten(room: Node) -> void:
	_licht_ziele.clear()
	var env_node := room.get_node_or_null("RaumLicht") as WorldEnvironment
	var env := env_node.environment if env_node != null else null
	var outdoor := false
	if room.has_method("room_def"):
		outdoor = bool(room.room_def().get("outdoor", false))
	var nacht := HomeLicht.profil(str(room.get("room_id")), outdoor, NACHT_STUNDE)
	if env != null:
		_licht_merken(env, "background_color", nacht["hintergrund"])
		_licht_merken(env, "ambient_light_color", nacht["ambient_farbe"])
		_licht_merken(env, "ambient_light_energy", nacht["ambient_energie"])
	var sonne := room.get_node_or_null("Sonne") as DirectionalLight3D
	if sonne != null:
		_licht_merken(sonne, "light_color", nacht["sonnen_farbe"])
		_licht_merken(sonne, "light_energy", nacht["sonnen_energie"])
	var fuell := room.get_node_or_null("FuellLicht") as OmniLight3D
	if fuell != null:
		_licht_merken(fuell, "light_energy", nacht["fuell_energie"])
	if _licht_ziele.is_empty():
		return
	_licht_tween = create_tween().set_parallel(true)
	_licht_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for ziel: Array in _licht_ziele:
		_licht_tween.tween_property(ziel[0], str(ziel[1]), ziel[2], LICHT_SWEEP_S)


## Ist-Wert als Ziel merken und den Nacht-Startwert hart setzen.
func _licht_merken(objekt: Object, property: String, nacht_wert: Variant) -> void:
	_licht_ziele.append([objekt, property, objekt.get(property)])
	objekt.set(property, nacht_wert)


## Sweep sauber beenden (auch beim Skip): Tween töten, Zielwerte snappen.
func _licht_fertigstellen() -> void:
	if _licht_tween != null and _licht_tween.is_valid():
		_licht_tween.kill()
	_licht_tween = null
	for ziel: Array in _licht_ziele:
		if is_instance_valid(ziel[0]):
			(ziel[0] as Object).set(str(ziel[1]), ziel[2])
	_licht_ziele.clear()


# ── Gruß aus echten Tagesdaten ────────────────────────────────────────────────


func _gruss_text() -> String:
	var teile: Array[String] = []
	for zeile: Dictionary in MorgenRitual.begruessung(_gruss_ctx()):
		teile.append(I18nService.t(str(zeile["key"]), zeile["args"]))
	return " ".join(teile)


func _gruss_ctx() -> Dictionary:
	var ctx := _ritual_ctx()
	var markt := OrtKatalog.wochentage(OrtKatalog.oeffnung("wochenmarkt"))
	return {
		"player_name": str(_gs.get_value("meta.playerName", "")),
		"wetter": SoulWetter.zustand(str(ctx["heute"]), float(ctx["stunde"])),
		"markt_heute": markt.has(int(ctx["wochentag"])),
		"quest_titel": _offene_quest(),
	}


## Titel der ersten noch offenen Tagesquest ("" = keine/alles fertig).
func _offene_quest() -> String:
	var service := DailyQuestService.find_service()
	if service == null:
		return ""
	service.ensure_roll()
	for reihe: Dictionary in service.board():
		if not bool(reihe.get("complete", false)) and not bool(reihe.get("claimed", false)):
			return I18nService.t(DailyQuestCatalog.title_key(reihe.get("def", {})))
	return ""


# ── Skip / Helfer ─────────────────────────────────────────────────────────────


## Unsichtbarer Tap-Fänger über dem Raum (Layer 60 — unter Guide 70 und
## Bonus 90): EIN Tipp überspringt die Klammer, sonst schluckt er während
## der ~3 s alle Eingaben (Kino-Moment, nichts stapelt sich darüber).
func _skip_layer_einbauen() -> void:
	_skip_layer = CanvasLayer.new()
	_skip_layer.name = "MorgenLayer"
	_skip_layer.layer = 60
	add_child(_skip_layer)
	var faenger := Control.new()
	faenger.name = "MorgenSkip"
	faenger.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	faenger.mouse_filter = Control.MOUSE_FILTER_STOP
	faenger.gui_input.connect(_on_skip_input)
	_skip_layer.add_child(faenger)


func _skip_layer_abbauen() -> void:
	if _skip_layer != null and is_instance_valid(_skip_layer):
		_skip_layer.queue_free()
	_skip_layer = null


func _on_skip_input(event: InputEvent) -> void:
	var tipp: bool = (
		(event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
		or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	)
	if tipp:
		_skip = true


func _warte_oder_skip(sekunden: float) -> void:
	var deadline := Time.get_ticks_msec() + int(sekunden * 1000.0)
	while not _skip and Time.get_ticks_msec() < deadline:
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame


func _aktueller_raum() -> Node:
	var router := get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("get_current_scene"):
		return null
	var szene: Node = router.get_current_scene()
	return szene if szene is RoomBase else null


func _now_ms() -> int:
	if "clock" in _gs:
		return int(_gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)


func _heute() -> String:
	if "clock" in _gs:
		return str(_gs.clock.local_day())
	var d := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


## UTC-Offset der GameState-Clock spiegeln: pinnt ein Test den Offset
## (set_utc_offset_minutes), muss UNSERE Stunden-Rechnung denselben Versatz
## nutzen wie clock.local_day — sonst driften Tag und Stunde auseinander.
## Ohne Override: null → lokale_zeit nimmt die OS-Bias-Regel der Clock.
func _offset_min() -> Variant:
	if "clock" in _gs:
		var clock: Variant = _gs.clock
		if bool(clock.get("_offset_overridden")):
			return int(clock.get("_offset_minutes"))
	return null
