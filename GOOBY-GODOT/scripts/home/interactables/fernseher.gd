class_name Fernseher
extends Node3D
## Fernseher-Interactable (W13C/GOBTY, Doc H §6.2 + User-Wunsch: „im
## Wohnzimmer GOB.TY schauen und witzige Videos sehen"): dockt an die
## TV-Möbel an (W3d-Muster: setup(host, furniture) + make_tap_area).
##
##   Tap (aus)  → Einschalten: GobtyTvStage (SubViewport) rendert live auf
##                eine Bildschirmfläche vor dem TV-Mesh; Gooby setzt sich
##                davor (bestehende Bewegungs-API) und schaut mit.
##   Tap (an)   → Zapping: nächster GOB.TY-Clip (GobtyClipPlayer-Rotation).
##   Aus-Knopf  → kleiner Knopf in der Raum-UI-Ebene (W3dUiLayer-Muster)
##                schaltet ab und lässt Gooby wieder losziehen.
##
## Wirkung: Fernsehen gibt langsam Spaß (+1 Fun je 30 s, Cap +10 pro
## Sitzung — GobtyClipPlayer.wende_fun_an über die bestehende Stats-API);
## KEIN Energie-/Zeitverbrauch (reines Gemütlichkeits-Feature). Gooby
## reagiert ab und zu mit Emotionen auf den Clip (zuschauer-Schritte).
## Zeit kommt IMMER aus _now_ms() (gs.clock — Tests pinnen sie).
##
## Einhängen (Host-Zeile, s. W13-requests.md): InteractablesHost.rescan
## dockt TV_IDS → Fernseher.new() an.

## Möbel-Ids, die GOB.TY empfangen (Katalog W2a; deskMonitor ist bewusst
## KEIN Fernseher — der PC bleibt ein PC).
const TV_IDS: Array[String] = ["televisionModern", "televisionVintage"]
## Takt der Abspiellogik (die pure Zeitrechnung passiert im Player).
const TAKT_S := 0.25
## Sitzplatz: so weit vor der Bildschirmfläche macht es sich Gooby gemütlich.
const SITZ_ABSTAND := 1.35

var _host: InteractablesHost
var _furniture: Node3D
var _voice: GoobyVoice
var _player: GobtyClipPlayer
var _stage: GobtyTvStage
var _visuals: Node3D
var _aus_knopf: Button
var _an := false
var _takt_rest := 0.0


func setup(host: InteractablesHost, furniture: Node3D) -> void:
	_host = host
	_furniture = furniture
	add_child(InteractablesHost.make_tap_area(furniture, _on_tapped))
	_voice = GoobyVoice.new()
	_voice.name = "TvStimme"
	add_child(_voice)
	set_process(false)


func is_on() -> bool:
	return _an


func spieler() -> GobtyClipPlayer:
	return _player


func stage() -> GobtyTvStage:
	return _stage


## Takt (auch von Tests mit synthetischer Zeit getrieben): Player fragen,
## neue Schritte inszenieren, Fun buchen, Zuschauer-Gooby reagieren lassen.
func takt(now_ms: int) -> void:
	if not _an or _player == null:
		return
	var ergebnis := _player.tick(now_ms)
	if bool(ergebnis["clip_gewechselt"]):
		_stage.zeige_clip(_player.aktueller_clip())
	for schritt: Dictionary in ergebnis["schritte"]:
		_spiele_schritt(schritt)
	_buche_fun(int(ergebnis["fun_delta"]))


func _process(delta: float) -> void:
	_takt_rest -= delta
	if _takt_rest > 0.0:
		return
	_takt_rest = TAKT_S
	takt(_now_ms())


func _exit_tree() -> void:
	# Bau-Commit/Raumwechsel räumt den Host ab — Gooby nie sitzen lassen.
	if _an:
		_lass_gooby_los()


func _on_tapped() -> void:
	if _room_busy():
		return
	if _an:
		_zappen()
	else:
		_einschalten()


# ── Ein/Aus/Zapp ──────────────────────────────────────────────────────────────


func _einschalten() -> void:
	var now := _now_ms()
	var morgen := GobtyClipDefs.datum_morgen(GobtyClipDefs.datum_von_ms(now))
	_player = GobtyClipPlayer.new(GobtyClipDefs.alle(morgen))
	_stage = GobtyTvStage.new()
	_stage.name = "GobtyStage"
	add_child(_stage)
	_stage.set_live(true)
	_baue_bildschirm()
	_zeige_aus_knopf()
	_player.start(now)
	_stage.zeige_clip(_player.aktueller_clip())
	_an = true
	_takt_rest = 0.0
	set_process(true)
	AudioDirector.try_play(self, "ui_toggle")
	_say_key("gobty.an")
	# W14/VOICE-Anbindung: frische Reaktions-Line (Bremse/Anti-Wdh. inklusive).
	SeeleRunner.kommentar_im_raum(_host.room(), "w13.gobty")
	_setz_gooby_hin()


func _zappen() -> void:
	if _player == null or _stage == null:
		return
	_player.zap(_now_ms())
	_stage.zeige_clip(_player.aktueller_clip())
	AudioDirector.try_play(self, "ui_click", 1.1)
	var titel := I18nService.t(str(_player.aktueller_clip().get("titel_key", "")))
	_say_text(I18nService.t("gobty.zapp", {"titel": titel}))


func _ausschalten() -> void:
	if not _an:
		return
	_an = false
	set_process(false)
	AudioDirector.try_play(self, "ui_close")
	if _stage != null:
		_stage.set_live(false)
		_stage.queue_free()
		_stage = null
	if _visuals != null:
		_visuals.queue_free()
		_visuals = null
	if _aus_knopf != null:
		_aus_knopf.queue_free()
		_aus_knopf = null
	_player = null
	_lass_gooby_los()
	_say_key("gobty.aus")


# ── Bildschirm + Aus-Knopf ────────────────────────────────────────────────────


## Bildschirmfläche vor dem TV-Mesh: Quad in Möbel-Ausrichtung, Textur =
## Live-SubViewport (Muster cosmetic_preview, nur dauerhaft statt gebacken).
func _baue_bildschirm() -> void:
	_visuals = Node3D.new()
	_visuals.name = "TvBild"
	add_child(_visuals)
	if _furniture is Node3D:
		_visuals.global_transform = (_furniture as Node3D).global_transform
	var masse := _bildschirm_masse()
	var schirm := MeshInstance3D.new()
	schirm.name = "Schirm"
	var quad := QuadMesh.new()
	quad.size = Vector2(masse["breite"], masse["hoehe"])
	schirm.mesh = quad
	schirm.position = Vector3(0.0, masse["mitte_y"], masse["tiefe"])
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _stage.get_texture()
	schirm.material_override = mat
	schirm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visuals.add_child(schirm)


## Bildschirm-Maße aus dem Möbel ableiten (Footprint + Oberkante) — passt
## für den flachen Fernseher wie den kleinen Röhren-TV.
func _bildschirm_masse() -> Dictionary:
	var breite := 0.8
	var tiefe := 0.28
	var oben := 0.8
	if _furniture is FurnitureNode:
		var def: Dictionary = (_furniture as FurnitureNode).item_def
		var fp: Vector2i = def.get("footprint", Vector2i(2, 1))
		breite = fp.x * GridData.CELL_SIZE * 0.8
		tiefe = fp.y * GridData.CELL_SIZE * 0.5 + 0.03
		oben = maxf(0.4, (_furniture as FurnitureNode).top_y())
	return {
		"breite": breite,
		"hoehe": oben * 0.62,
		"mitte_y": oben * 0.55,
		"tiefe": tiefe,
	}


## Aus-Knopf in der Raum-UI-Ebene (W3dUiLayer-Muster wie Spiegel/Radio):
## Möbel-Taps zappen, DIESER Knopf schaltet ab.
func _zeige_aus_knopf() -> void:
	_aus_knopf = Button.new()
	_aus_knopf.name = "GobtyAusKnopf"
	_aus_knopf.theme = ThemeService.theme()
	_aus_knopf.theme_type_variation = "GhostButton"
	_aus_knopf.text = I18nService.t("gobty.aus_knopf")
	_aus_knopf.focus_mode = Control.FOCUS_NONE
	_aus_knopf.custom_minimum_size = Vector2(0, 44)
	_aus_knopf.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_aus_knopf.offset_left = -170.0
	_aus_knopf.offset_right = -16.0
	_aus_knopf.offset_top = -150.0
	_aus_knopf.offset_bottom = -106.0
	_aus_knopf.pressed.connect(_ausschalten)
	_ui_layer().add_child(_aus_knopf)


# ── Schritte inszenieren ──────────────────────────────────────────────────────


func _spiele_schritt(schritt: Dictionary) -> void:
	var banner := _banner_text(schritt)
	_stage.wende_schritt_an(schritt, banner)
	var sound := str(schritt.get("sound", ""))
	if sound != "":
		AudioDirector.try_play(self, sound)
	if banner != "" and int(schritt.get("sprecher", 0)) >= 0:
		# Gebrabbel-Stimme: der Mini-Gooby „liest" die Bauchbinde vor —
		# der Ton kommt räumlich aus dem Fernseher (Voice im Haupt-World).
		var emotion := str(schritt.get("emotion", ""))
		_voice.sagt(banner, emotion if emotion != "" else "neutral")
	_reagiere_zuschauer(str(schritt.get("zuschauer", "")))


## Bauchbinde eines Schritts auflösen: Wetter-Daten > rotierende
## Schlagzeile > fester Key ("" = Banner bleibt stehen).
func _banner_text(schritt: Dictionary) -> String:
	var wetter: Dictionary = schritt.get("wetter", {})
	if not wetter.is_empty():
		var typ := str(wetter.get("typ", "sonne"))
		return (
			I18nService
			. t(
				"gobty.wetter.banner",
				{
					"stunde": int(wetter.get("stunde", 0.0)),
					"wetter": I18nService.t("gobty.wetter.typ.%s" % typ),
				}
			)
		)
	if str(schritt.get("banner", "")) == "schlagzeile":
		return I18nService.t(_player.schlagzeile_fuer(schritt))
	var key := str(schritt.get("banner_key", ""))
	return I18nService.t(key) if key != "" else ""


## Zuschauer-Reaktion: der ECHTE Raum-Gooby spiegelt ab und zu die
## Stimmung des Clips (nur Emotion — die Sitz-Pose bleibt).
func _reagiere_zuschauer(emotion: String) -> void:
	if emotion == "":
		return
	var gooby := _gooby()
	if gooby != null and "rig" in gooby and gooby.rig != null:
		gooby.rig.set_emotion(emotion)


# ── Wirkung ───────────────────────────────────────────────────────────────────


## Fällige Spaß-Punkte über die bestehende Stats-API buchen (+ Mint-Float
## überm zuschauenden Gooby).
func _buche_fun(delta: int) -> void:
	if delta <= 0:
		return
	var gs := _host.game_state()
	if gs == null:
		return
	gs.update(func(state: Dictionary) -> void: GobtyClipPlayer.wende_fun_an(state, delta))
	var room := _host.room()
	var gooby := _gooby()
	if room != null and gooby is Node3D:
		var pos: Vector3 = (gooby as Node3D).global_position + Vector3(0.0, 0.9, 0.0)
		RewardFx.float_text(room, pos, "+%d" % delta, RewardFx.MINT)


## Gooby macht es sich vor dem Bildschirm gemütlich (bestehende
## Bewegungs-API: walk_to + sit-Loop; Wandern pausiert).
func _setz_gooby_hin() -> void:
	var gooby := _gooby()
	if gooby == null or _visuals == null:
		return
	gooby.set_wander_enabled(false)
	var masse := _bildschirm_masse()
	var vor_ort: Vector3 = (
		_visuals.global_transform * Vector3(0.0, 0.0, float(masse["tiefe"]) + SITZ_ABSTAND)
	)
	await gooby.walk_to(Vector3(vor_ort.x, gooby.global_position.y, vor_ort.z), 5.0)
	if not _an or gooby == null:
		return
	gooby.play_clip("sit")


func _lass_gooby_los() -> void:
	var gooby := _gooby()
	if gooby != null:
		gooby.play_clip("idle")
		gooby.set_wander_enabled(true)


# ── Helfer ────────────────────────────────────────────────────────────────────


func _gooby() -> Node:
	var room := _host.room()
	if room != null and room.has_method("gooby"):
		return room.gooby()
	return null


func _say_key(key: String) -> void:
	_say_text(I18nService.t(key))


func _say_text(text: String) -> void:
	var room := _host.room()
	if room != null and room.has_method("say"):
		room.say(text)


func _room_busy() -> bool:
	var room := _host.room()
	return room != null and room.has_method("is_build_mode_active") and room.is_build_mode_active()


func _now_ms() -> int:
	var gs := _host.game_state()
	if gs != null and "clock" in gs:
		return int(gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)


func _ui_layer() -> CanvasLayer:
	var existing := _host.get_node_or_null("W3dUiLayer")
	if existing is CanvasLayer:
		return existing
	var layer := CanvasLayer.new()
	layer.name = "W3dUiLayer"
	layer.layer = 6
	_host.add_child(layer)
	return layer
