class_name SnapAGooby
extends CanvasLayer
## W13C FOTOWERK — „Snap A Gooby!“-Besuchs-Selfie (Doc C §3.9): beide Goobys
## posieren fürs Selfie. Der eigene Gooby hält das Handy (phone_up-Clip,
## wave-Fallback — Battleship-Tomaten-Muster), der Gast-Gooby hoppelt ins
## Bild (POS-Ziel neben dem eigenen Gooby + hop-Clip), 3-2-1-Countdown,
## Klick. Das Foto landet lokal im Album (city.fotos, wie der Fotomodus)
## UND als Mail-Foto beim Freund (W13B-Mail-Vertrag: NetMail.send_mail mit
## fotoPfad → REST photoB64; offline fängt die Outbox).
##
## Der Ablauf (Countdown) ist eine PURE, zeitinjizierte Statemaschine
## (`Ablauf.takt(dt)`) — headless testbar ohne Szene. Zum Peer wird das
## Posieren als vorhandenes „laugh“-Emote relayt (wave + happy), weil das
## Emote-Rad-Vokabular BoardEmotes gehört; ein echtes selfie-Emote ist als
## Request an den Emote-Owner vermerkt.

signal fertig(pfad: String)

## Relay-Emote zum Peer (vorhandenes Vokabular, wave-basiert).
const RELAY_EMOTE := "laugh"
## Der Gast hoppelt seitlich neben den eigenen Gooby ins Bild.
const GAST_VERSATZ := Vector3(0.9, 0.0, 0.15)

var gs: Object
## Tests: Uhr (Unix-Sekunden) und Foto-Quelle injizieren.
var uhr_unix_s: Callable = Callable()
## Tests: liefert den Pfad der Aufnahme statt Viewport-Capture.
var foto_quelle: Callable = Callable()
## Tests: Net-Node (FakeLink-Rig) statt /root/Net.
var net_override: Node = null

var ablauf := Ablauf.new()

var _szene: Node = null
var _zahl: Label
var _hinweis: Label
var _blitz: ColorRect
var _mein_rig_angefasst := false


## PURE Countdown-Statemaschine: Pose-Beat → 3 → 2 → 1 → „ausloesen“.
## `takt(dt)` liefert die Ereignisse dieses Schritts — Zeit kommt IMMER
## von außen (testbar ohne Timer/Engine-Uhr).
class Ablauf:
	extends RefCounted

	const POSE_BEAT_S := 0.8
	const SEKUNDE_S := 1.0
	const COUNTDOWN_START := 3

	var phase := "pose"  # pose → countdown → fertig
	var countdown := COUNTDOWN_START

	var _rest_s := POSE_BEAT_S

	func takt(dt_s: float) -> Array[String]:
		var ereignisse: Array[String] = []
		if phase == "fertig":
			return ereignisse
		_rest_s -= maxf(dt_s, 0.0)
		while _rest_s <= 0.0:
			if phase == "pose":
				phase = "countdown"
				ereignisse.append("zeige_%d" % countdown)
				_rest_s += SEKUNDE_S
			elif countdown > 1:
				countdown -= 1
				ereignisse.append("zeige_%d" % countdown)
				_rest_s += SEKUNDE_S
			else:
				phase = "fertig"
				ereignisse.append("ausloesen")
				break
		return ereignisse


## Overlay über der Besuchs-Szene starten (Szene duck-typed: my_gooby/remote/
## visit_service — so bleibt visit_scene.gd unangetastet).
static func starte(szene: Node, game_state: Object) -> SnapAGooby:
	var selfie := SnapAGooby.new()
	selfie.name = "SnapAGooby"
	selfie.gs = game_state
	selfie._szene = szene
	szene.add_child(selfie)
	return selfie


func _ready() -> void:
	layer = 30
	_baue_ui()
	_posiere()


func _process(delta: float) -> void:
	for ereignis in ablauf.takt(delta):
		verarbeite(ereignis)


## Ein Statemaschinen-Ereignis anwenden (öffentlich für zeitinjizierte Tests).
func verarbeite(ereignis: String) -> void:
	if ereignis.begins_with("zeige_"):
		_zahl.text = ereignis.trim_prefix("zeige_")
		_zahl.visible = true
	elif ereignis == "ausloesen":
		_knipse_und_sende()


# ---------------------------------------------------------------- Posieren


## Beide Goobys in Position: eigener Gooby hält das Handy (phone_up→wave),
## der Gast-Gooby hoppelt neben ihn, der Peer sieht das Relay-Emote.
func _posiere() -> void:
	var rig := _mein_rig()
	if rig != null and rig.has_method("play_clip"):
		var clips: Array = rig.clip_names() if rig.has_method("clip_names") else []
		rig.play_clip(FotoWerkzeuge.selfie_clip(clips))
		_mein_rig_angefasst = true
	var remote: Node = _feld("remote")
	var mein_gooby: Node = _feld("my_gooby")
	if remote != null and mein_gooby is Node3D and remote.has_method("apply_state"):
		var ziel := (mein_gooby as Node3D).global_position + GAST_VERSATZ
		remote.apply_state(ziel, "hop")
	var vs := _dienst()
	if vs != null and vs.has_method("send_emote"):
		vs.send_emote(RELAY_EMOTE)


func _entspanne() -> void:
	var rig := _mein_rig()
	if _mein_rig_angefasst and rig != null and rig.has_method("play_clip"):
		rig.play_clip("idle")
	_mein_rig_angefasst = false


# ---------------------------------------------------------------- Auslösen


func _knipse_und_sende() -> void:
	var pfad := await _knipse_datei()
	_zahl.visible = false
	if pfad.is_empty():
		_hinweis.text = I18nService.t("social.selfie.fehler")
		_beende("")
		return
	FotoModus.merke_foto(
		gs, pfad, _jetzt_unix() * 1000, "", {"selfie": true, "emote": "snap_a_gooby"}
	)
	_blitze()
	var versand := await sende_an_freund(pfad)
	var name := _peer_anzeigename()
	if versand.get("ok", false) or str(versand.get("code", "")) == "QUEUED":
		_hinweis.text = I18nService.t("social.selfie.gesendet", {"name": name})
	else:
		_hinweis.text = I18nService.t("social.selfie.nur_lokal")
	_beende(pfad)


## Kopie an den Freund: Mail-Foto über den W13B-Vertrag (fotoPfad → photoB64).
## Öffentlich + awaitbar, damit der FakeLink-Test den Versand direkt prüft.
func sende_an_freund(pfad: String) -> Dictionary:
	var vs := _dienst()
	if vs == null:
		return {"ok": false, "code": "NO_VISIT"}
	var peer_code := _peer_code(vs)
	if peer_code.is_empty():
		return {"ok": false, "code": "NO_PEER"}
	var net: Node = net_override
	if net == null:
		net = get_node_or_null("/root/Net")
	var mail := NetMail.attach(net)
	if mail == null:
		return {"ok": false, "code": "NO_NET"}
	var text := I18nService.t("social.selfie.mail_text")
	return await mail.send_mail(peer_code, text, pfad)


## Aufnahme auf Platte: injizierte Quelle (Tests) oder Viewport-Capture wie
## im Fotomodus (Overlay-UI EIN Frame ausblenden, Rahmenlos).
func _knipse_datei() -> String:
	if foto_quelle.is_valid():
		return str(foto_quelle.call())
	visible = false
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var bild := get_viewport().get_texture().get_image()
	visible = true
	if bild == null:
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FotoModus.FOTO_DIR))
	var pfad := FotoModus.foto_pfad(_jetzt_unix())
	if bild.save_png(pfad) != OK:
		return ""
	return pfad


func _beende(pfad: String) -> void:
	_entspanne()
	fertig.emit(pfad)
	# Hinweis kurz stehen lassen, dann räumt sich das Overlay selbst weg.
	var timer := get_tree().create_timer(1.6)
	timer.timeout.connect(queue_free)


# ------------------------------------------------------------------ Helfer


func _jetzt_unix() -> int:
	if uhr_unix_s.is_valid():
		return int(uhr_unix_s.call())
	return int(Time.get_unix_time_from_system())


func _feld(feld: String) -> Node:
	if _szene == null:
		return null
	var wert: Variant = _szene.get(feld)
	return wert if wert is Node else null


func _mein_rig() -> Object:
	var mein_gooby: Node = _feld("my_gooby")
	if mein_gooby == null:
		return null
	var rig: Variant = mein_gooby.get("rig")
	return rig if rig is Object and rig != null else null


func _dienst() -> Node:
	if _szene != null and _szene.has_method("visit_service"):
		var vs: Variant = _szene.visit_service()
		if vs is Node:
			return vs
	return null


## Freundes-Code des Peers: als Host ist es der Gast, als Gast der Host.
func _peer_code(vs: Node) -> String:
	if str(vs.get("role")) == VisitService.ROLE_HOST:
		return str(vs.get("guest_code"))
	return str(vs.get("host_code"))


func _peer_anzeigename() -> String:
	var vs := _dienst()
	if vs == null:
		return ""
	var name := str(vs.get("peer_gooby_name"))
	return name if not name.is_empty() else str(vs.get("peer_name"))


func _blitze() -> void:
	if ThemeService.is_reduced_motion(_blitz):
		return
	_blitz.color = Color(1.0, 1.0, 1.0, 0.75)
	var tween := create_tween()
	tween.tween_property(_blitz, "color", Color(1.0, 1.0, 1.0, 0.0), 0.35)


func _baue_ui() -> void:
	var wurzel := Control.new()
	wurzel.set_anchors_preset(Control.PRESET_FULL_RECT)
	wurzel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wurzel.theme = ThemeService.theme()
	add_child(wurzel)
	_zahl = Label.new()
	_zahl.name = "Countdown"
	_zahl.visible = false
	_zahl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zahl.add_theme_font_size_override("font_size", 120)
	_zahl.add_theme_color_override("font_outline_color", Color(0.25, 0.18, 0.12))
	_zahl.add_theme_constant_override("outline_size", 14)
	_zahl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	wurzel.add_child(_zahl)
	_hinweis = Label.new()
	_hinweis.name = "Hinweis"
	_hinweis.text = I18nService.t("social.selfie.hinweis")
	_hinweis.theme_type_variation = "CaptionLabel"
	_hinweis.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hinweis.add_theme_color_override("font_outline_color", Color(0.25, 0.18, 0.12))
	_hinweis.add_theme_constant_override("outline_size", 6)
	_hinweis.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 64
	)
	wurzel.add_child(_hinweis)
	_blitz = ColorRect.new()
	_blitz.color = Color(1.0, 1.0, 1.0, 0.0)
	_blitz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blitz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wurzel.add_child(_blitz)
