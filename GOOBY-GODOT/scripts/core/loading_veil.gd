class_name LoadingVeil
extends CanvasLayer
## LoadingVeil — Transition-Fläche des SceneRouters (W1a; Optik W4/POLISH-3,
## W16/VEIL: Alt-Web-Look).
##
## W16/VEIL: Der Szenenwechsel-Ladebildschirm trägt wieder den Look der
## alten Web-Version (User-Wunsch, Spez /tmp/gooby-reports/g1/ladebild-alt.md
## §2): statisches Blätter-Pattern auf Papier (#FFFAF2) als Vorhang und die
## POLISH-D-Karte — Cover-Zone mit Lese-Shade + weißer Ready-Zeile,
## hüpfender Motiv-Sticker (72 px, weiß umrandet, überlappt die Coverkante),
## Titel, Teal-Verlaufsbalken mit Indeterminate-Sweep, „Lädt… NN%“-Zeile
## (Prozent nur bei echtem Fortschritt) und rotierende Tipps (2,6 s,
## 200-ms-Crossfade). Drei Karten-Modi wie im Web:
## - game: Minigame-Reise (ArcadeScreen-Hint) — Game-Cover + Spieltitel +
##   „Mach dich bereit!“ + Game-Tipps.
## - trip: Shop-/Stadt-/Klinik-Ausflüge — „Auf geht’s!“ / „Zeit für einen
##   kleinen Ausflug…“ + Trip-Tipps.
## - home: alles andere (Rückkehr/Default) — „Trautes Heim“ /
##   „Auf dem Heimweg…“ + Home-Tipps.
## G6/DLC-LOAD: DLC-Orte (Ranch, „Goo und Bye“, McGooby) bekommen beim
## Betreten UND auf dem Rückweg ihre eigene Karten-Identität — dieselbe
## Karte, nur Motiv/Farbstimmung/Tipps datengetrieben getauscht
## (DlcLoadingKarten): DLC-Cover in der Cover-Zone, eigener Motiv-Sticker,
## eigene Titel-/Bereit-Zeile und ein eigener Tipp-Pool (6+ je DLC).
## Vorrang unverändert: Minigame-Hint > Tür-Wisch > Ranch-Vollbildschirm
## (lange Reisen) > DLC-Karte > home/trip. Unbekannte Ziele fallen auf die
## Standard-Karte zurück; fehlende DLC-Assets auf Verlauf/Winke-Gooby
## (Web-onerror-Verhalten). Die Herkunft trackt das Veil selbst über die
## travel_started-Ziele — kein Eingriff in Router oder DLC-Szenen.
##
## Ein/Aus ist seit W16/G2b der Signature-Übergang der Web-Version
## (loadingVeil.js V6/F2, Spez §2.2): der PETAL-SWEEP-WIPE. Backdrop +
## Karte wischen GEMEINSAM links→rechts herein (ease-out) und hinaus
## (ease-in), die Oberkante eilt 15 % voraus, entlang der Kante reiten
## 26 prozedurale Blüten-/Blatt-Stempel (loading_veil_wipe.gd, sitzt als
## Wisch-Maske auf dem FROZEN Root). Varianten-Weiche wie im Web:
## Reduced Motion → "fade" (hier instantan, bestehender Vertrag),
## technischer Fallback "iris" (Kreis-Wipe), Standard "petal". Der
## Karten-Pop-in (220 ms ease-out, scale 0.96→1 + translateY, Web
## polishd-loading-in) läuft parallel zum Wipe weiter.
##
## Weiter unverändert:
## - LANGE Reise (RW-8; LoadingScreenRules): Vollbild-Ladebildschirm
##   (RanchLoadingScreen) mit Artwork, Logo, echtem Balken, `loading.tips`.
## - DOOR_TRAVEL (EF-3/EVAL-1 F1): KEIN Vollveil — cremefarbener Tür-Wisch
##   (~130/200 ms) ohne Karte/Tipps/Panel-Klänge.
## - Travel-Whoosh-Paar (F9) bleibt.
##
## Contract (nach W1 FROZEN, W1a-Handoff): cover(reduced_motion) /
## reveal(reduced_motion) sind awaitbare Coroutinen (Router:
## `await veil.cover(rm)`); Signale covered/revealed feuern zusätzlich.
## set_progress(0..1) bekommt den threaded-Load-Fortschritt vom Router;
## %Progress ist nur im Fenster 0<p<1 sichtbar, der Indeterminate-Sweep
## weicht ihm (Nachfolger der W14-Punkte-Regel). Node-Pfade Root /
## Root/Backdrop / Root/Spinner bleiben erhalten (Tests asserten sie) —
## der Spinner ist nur ausgeblendet. %Gooby ist jetzt der Motiv-Sticker
## (LoadingVeilSticker) und behält die set_animated/is_animated-API.

signal covered
signal revealed

## Ein-/Aus-Blende = Dauer des Petal-Sweep-Wipes. Web PETAL.WIPE_MS wäre
## 450 ms — bewusst auf 0.4 s gedeckelt, weil der Ehrlichkeits-Wächter
## (test_loading_regeln) die Veil-Blenden auf ≤ 0.4 s pinnt.
const COVER_DURATION := 0.4
const REVEAL_DURATION := 0.4
## Wisch-Maske + Stempel des Petal-Wipes (kein class_name — bewusst, damit
## kein --import/Class-Cache-Lauf nötig ist; Zugriff via preload).
const VeilWipe := preload("res://scripts/core/loading_veil_wipe.gd")
## Karten-Pop-in (Web polishd-loading-in): 220 ms ease-out,
## scale 0.96→1 + translateY 0.5rem→0.
const KARTE_POP_S := 0.22
const KARTE_POP_SCALE := 0.96
const KARTE_POP_SHIFT := 8.0
## Tür-Wisch (EF-3 F1): beide zusammen deutlich unter dem 350-ms-Budget.
const DOOR_COVER_DURATION := 0.13
const DOOR_REVEAL_DURATION := 0.2
## Weiche Wisch-Kante links/rechts als Anteil der Bildschirmbreite.
const DOOR_EDGE_FRAC := 0.18
## Web VEIL.TIP_ROTATE_MS = 2600 + 200-ms-Crossfade der Tipp-Zeile.
const TIP_ROTATE_SEC := 2.6
const TIP_FADE_S := 0.2
## Assets der Alt-Web-Karte (portiert aus GOOBY/public/assets, §2.5).
## Fehlt ein Bild, bleibt wie im Web der Akzent-Verlauf (onerror-Fallback).
const COVER_HOME_PFAD := "res://assets/acui/veil_home_cover.png"
const MOTIV_WAVE_PFAD := "res://assets/acui/motif_gooby_wave.png"
const MOTIV_GAME_PFAD := "res://assets/acui/gooby_loading_motif.png"
## Reiseziele im Web-„trip“-Modus (Shop-/Tierarzt-Ausflüge): der IKEA-Shop
## und alle Stadt-Ziele (die Klinik ist der Stadt-Ort city/ort/tierarzt).
const TRIP_ZIELE: Array[String] = ["ikea"]
const TRIP_PRAEFIXE: Array[String] = ["city"]

static var _travel_hint: Dictionary = {}
static var _tip_cursor := 0
## Shuffle-Bag der grossen Ladebildschirm-Tipps (RW-8) — statisch, damit die
## Rotation über Veil-Instanzen hinweg ohne Wiederholung weiterläuft.
static var _loading_tipp_zustand: Dictionary = {}

## Tests/Screenshots: feste Tageszeit für die Artwork-Wahl (-1 = Systemzeit).
var stunde_override := -1.0

var _progress := 0.0
var _active_hint: Dictionary = {}
## Karten-Modus wie im Web: "home" | "trip" | "game".
var _modus := "home"
var _laedt_basis := ""
## G6/DLC-LOAD: aktive DLC-Karte ("" = Standard-Karte) + Reiserichtung.
var _dlc_karte := ""
var _dlc_betreten := false
## Zuletzt bereistes Ziel = Herkunft der NÄCHSTEN Reise (fürs „und zurück“
## der DLC-Karten) — das Veil trackt das selbst, der Router bleibt frozen.
var _herkunft := StringName()
var _ranch_aktiv := false
var _ranch_ziel := StringName()
var _ranch_screen: RanchLoadingScreen
var _tip_timer: Timer
var _tip_tween: Tween
var _tips_animiert := true
## EF-3 F1: aktiver Tür-Wisch-Modus (gesetzt via prepare_for_travel).
var _door_aktiv := false
var _door_wipe: Control

@onready var _root: Control = $Root
## Dasselbe Root-Control, getypt als Wipe (das Skript sitzt im tscn drauf).
@onready var _wipe: VeilWipe = $Root
@onready var _backdrop: AcWallpaper = $Root/Backdrop
@onready var _card: LoadingVeilKarte = %Card
@onready var _cover_rect: TextureRect = %Cover
@onready var _title_label: Label = %Title
@onready var _ready_label: Label = %Ready
@onready var _gooby: LoadingVeilSticker = %Gooby
@onready var _laedt_label: Label = %Laedt
@onready var _tip_label: Label = %Tip
@onready var _sweep: LoadingVeilSweep = %Sweep
@onready var _progress_bar: ProgressBar = %Progress


func _ready() -> void:
	layer = 100
	visible = false
	_root.modulate.a = 0.0
	# CanvasLayer-Gotcha (W3d-Handoff): Window-Theme kommt hier nicht an.
	_root.theme = ThemeService.theme()
	_laedt_basis = I18nService.t("veil.laedt")
	_laedt_label.text = _laedt_basis
	_gooby.set_animated(false)
	_sweep.set_animated(false)
	_tip_timer = Timer.new()
	_tip_timer.wait_time = TIP_ROTATE_SEC
	_tip_timer.timeout.connect(_on_tip_timer)
	add_child(_tip_timer)
	# Godot rendert clip_children-in-clip_children nicht (Backbuffer im
	# Backbuffer): der runde Karten-Clip pausiert daher für die Wipe-Dauer,
	# sonst verschwände der Karteninhalt während des Wisches.
	var karten_clip := _card.get_node_or_null("Clip") as CanvasItem
	if karten_clip != null:
		_wipe.setze_clip_pausen([karten_clip])
	var parent := get_parent()
	if parent != null and parent.has_signal("travel_started"):
		parent.travel_started.connect(_on_travel_started)
	_apply_variant()


## Reise-Kontext fürs nächste Veil (setzt der ArcadeScreen beim Kachel-Tap):
## {game_id, title, cover: Texture2D, targets: [StringName]}. Bleibt über
## die Kette Arcade→Pregame→Host gültig und löscht sich bei jeder Reise zu
## einem Ziel außerhalb von `targets` selbst (kein Aufräum-Zwang für Aufrufer).
static func set_travel_hint(hint: Dictionary) -> void:
	_travel_hint = hint


static func clear_travel_hint() -> void:
	_travel_hint = {}


## Karten-Modus fürs Ziel (Web-Regel §2.4): Shop-/Stadt-/Klinik-Ausflüge
## sind „trip“, alles andere (Rückkehr/Default) „home“; „game“ setzt der
## Minigame-Hint in _apply_variant.
static func modus_fuer_ziel(target: StringName) -> String:
	var ziel := String(target)
	if TRIP_ZIELE.has(ziel):
		return "trip"
	for praefix in TRIP_PRAEFIXE:
		if ziel == praefix or ziel.begins_with(praefix + "/"):
			return "trip"
	return "home"


## I18n-Key der rotierenden Tipps eines Modus (strings/*/veil.json).
static func tips_key(modus: String) -> String:
	return "veil.%s.tips" % modus


## Vom Router-Signal getrieben; Tests dürfen es direkt aufrufen.
## travel_type: SceneRouter.TravelType — DOOR_TRAVEL bekommt nie den
## vollen Ladebildschirm (LoadingScreenRules), sondern den Tür-Wisch.
func prepare_for_travel(target: StringName, travel_type := 0) -> void:
	var targets: Array = _travel_hint.get("targets", [])
	if not _travel_hint.is_empty() and targets.has(target):
		_active_hint = _travel_hint
	else:
		clear_travel_hint()
		_active_hint = {}
	_door_aktiv = travel_type == LoadingScreenRules.DOOR_TRAVEL and _active_hint.is_empty()
	_ranch_ziel = target
	_ranch_aktiv = (
		_active_hint.is_empty()
		and not _door_aktiv
		and LoadingScreenRules.ist_lange_reise(target, travel_type)
	)
	# G6/DLC-LOAD: DLC-Karte datengetrieben wählen (Betreten schlägt
	# Rückweg); der Minigame-Hint behält Vorrang. Danach wird das Ziel
	# zur Herkunft der nächsten Reise.
	if _active_hint.is_empty():
		_dlc_karte = DlcLoadingKarten.karten_id_fuer(target, _herkunft)
		_dlc_betreten = DlcLoadingKarten.ist_betreten(target)
	else:
		_dlc_karte = ""
		_dlc_betreten = false
	_herkunft = target
	_apply_variant()


## Deckt den Bildschirm ab; kehrt zurück, sobald das Veil voll deckt.
func cover(reduced_motion := false) -> void:
	if _door_aktiv:
		await _cover_door(reduced_motion)
		return
	# F9: Reisen haben ihr eigenes Whoosh-Paar — ui_close bleibt Panels.
	AudioDirector.try_play(self, "travel_whoosh_zu")
	visible = true
	_root.visible = true
	set_progress(0.0)
	_tips_animiert = not reduced_motion
	_stoppe_tip_fade()
	_gooby.set_animated(not reduced_motion and not _ranch_aktiv)
	_sweep.set_animated(not reduced_motion and not _ranch_aktiv)
	if _ranch_screen != null:
		_ranch_screen.set_animated(not reduced_motion and _ranch_aktiv)
	if _tip_label.visible or _ranch_aktiv:
		_tip_timer.start()
	if VeilWipe.wipe_variante(reduced_motion) == "fade":
		# Reduced Motion: instantan wie bisher (W1a-Contract) — der
		# Web-160-ms-Fade ist hier bewusst das sofortige Setzen.
		_wipe.sofort_fertig()
		_root.modulate.a = 1.0
	else:
		# Web polishd-loading-in: 220 ms ease-out, scale 0.96→1 +
		# translateY 0.5rem→0 — läuft parallel zum Wipe weiter.
		_card.pivot_offset = _card.size / 2.0
		_card.scale = Vector2.ONE * KARTE_POP_SCALE
		var basis_y := _card.position.y
		_card.position.y = basis_y + KARTE_POP_SHIFT * _card.design_faktor()
		var pop := create_tween().set_parallel()
		(
			pop
			. tween_property(_card, "scale", Vector2.ONE, KARTE_POP_S)
			. set_trans(Tween.TRANS_CUBIC)
			. set_ease(Tween.EASE_OUT)
		)
		(
			pop
			. tween_property(_card, "position:y", basis_y, KARTE_POP_S)
			. set_trans(Tween.TRANS_CUBIC)
			. set_ease(Tween.EASE_OUT)
		)
		# Petal-Sweep deckt ab: Deckkraft steht sofort auf dem FROZEN
		# Endwert (modulate 1.0), animiert wird NUR die Wisch-Maske
		# (Web: opacity 1, clip-path wandert).
		_root.modulate.a = 1.0
		await _wipe.wische_rein(VeilWipe.wipe_variante(false), COVER_DURATION)
	covered.emit()


## Öffnet das Veil wieder; kehrt zurück, sobald es voll transparent ist.
func reveal(reduced_motion := false) -> void:
	if _door_aktiv:
		await _reveal_door(reduced_motion)
		return
	# F9: Reisen haben ihr eigenes Whoosh-Paar — ui_open bleibt Panels.
	AudioDirector.try_play(self, "travel_whoosh_auf")
	_tip_timer.stop()
	_stoppe_tip_fade()
	if VeilWipe.wipe_variante(reduced_motion) == "fade":
		_wipe.sofort_fertig()
		_root.modulate.a = 0.0
	else:
		# Wisch raus (Web sweep-out, ease-in): die Maske gibt links den
		# neuen Raum frei; danach die FROZEN Endwerte setzen.
		await _wipe.wische_raus(VeilWipe.wipe_variante(false), REVEAL_DURATION)
		_root.modulate.a = 0.0
	visible = false
	_gooby.set_animated(false)
	_sweep.set_animated(false)
	if _ranch_screen != null:
		_ranch_screen.set_animated(false)
	revealed.emit()


func set_progress(ratio: float) -> void:
	_progress = clampf(ratio, 0.0, 1.0)
	if _progress_bar != null:
		_progress_bar.value = _progress
		_progress_bar.visible = _progress > 0.0 and _progress < 1.0 and not _ranch_aktiv
	# Web-Regel (Nachfolger der W14-Punkte): der Indeterminate-Sweep weicht
	# dem ECHTEN Balken — nie zwei Ladeanzeigen gleichzeitig.
	if _sweep != null and _progress_bar != null:
		_sweep.visible = not _progress_bar.visible
	_update_laedt_zeile()
	if _ranch_screen != null:
		_ranch_screen.set_progress(_progress if _ranch_aktiv else 0.0)


func get_progress() -> float:
	return _progress


func _on_travel_started(target: StringName, travel_type: int) -> void:
	prepare_for_travel(target, travel_type)


## „Lädt…“-Zeile wie im Web (loadingVeil.js progress()): Prozent NUR bei
## echtem Fortschritt, sonst bleibt das nackte Label (Indeterminate).
func _update_laedt_zeile() -> void:
	if _laedt_label == null or _laedt_basis.is_empty():
		return
	if _progress > 0.0 and _progress < 1.0:
		_laedt_label.text = "%s %d%%" % [_laedt_basis, roundi(_progress * 100.0)]
	else:
		_laedt_label.text = _laedt_basis


## ── Tür-Wisch (EF-3 F1) ─────────────────────────────────────────────────
## Ein cremefarbenes Band mit weichen Kanten wischt in EINER Bewegungs-
## richtung über den Schirm: cover() schiebt es von links herein (deckend,
## SWAP passiert dahinter), reveal() schiebt es nach rechts hinaus. Kein
## Vollbild-Schwarz, keine Karte, kein Klang — ein Schritt durch die Tür.


func _cover_door(reduced_motion := false) -> void:
	visible = true
	_root.visible = false
	var wipe := _ensure_door_wipe()
	var canvas := _canvas_size()
	var edge := DOOR_EDGE_FRAC * canvas.x
	wipe.size = Vector2(canvas.x + 2.0 * edge, canvas.y)
	wipe.visible = true
	# Voll deckend, sobald die opake Mitte (Breite = Canvas) den Schirm füllt.
	var covered_x := -edge
	if reduced_motion:
		wipe.position = Vector2(covered_x, 0.0)
	else:
		wipe.position = Vector2(-wipe.size.x, 0.0)
		var tween := create_tween()
		tween.tween_property(wipe, "position:x", covered_x, DOOR_COVER_DURATION)
		await tween.finished
	covered.emit()


func _reveal_door(reduced_motion := false) -> void:
	var wipe := _door_wipe
	if wipe != null and is_instance_valid(wipe):
		if reduced_motion:
			wipe.visible = false
		else:
			# Bewegung läuft weiter nach rechts — die linke weiche Kante
			# gibt den neuen Raum frei.
			var tween := create_tween()
			tween.tween_property(wipe, "position:x", _canvas_size().x, DOOR_REVEAL_DURATION)
			await tween.finished
			wipe.visible = false
	visible = false
	_root.visible = true
	revealed.emit()


## Wisch-Fläche lazy bauen: ColorRect mit Shader, der links/rechts weich
## in Transparenz ausläuft (Kante = DOOR_EDGE_FRAC der Canvas-Breite).
func _ensure_door_wipe() -> Control:
	if _door_wipe != null and is_instance_valid(_door_wipe):
		return _door_wipe
	var rect := ColorRect.new()
	rect.name = "DoorWipe"
	rect.visible = false
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = _door_wipe_shader()
	mat.set_shader_parameter("kante", DOOR_EDGE_FRAC / (1.0 + 2.0 * DOOR_EDGE_FRAC))
	rect.material = mat
	add_child(rect)
	_door_wipe = rect
	return rect


func _canvas_size() -> Vector2:
	if _root != null and _root.size.x > 0.0:
		return _root.size
	var vp := get_viewport()
	return vp.get_visible_rect().size if vp != null else Vector2(1280, 720)


static func _door_wipe_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec4 farbe : source_color = vec4(1.0, 0.964706, 0.92549, 1.0);
uniform float kante = 0.13;
void fragment() {
	float a = smoothstep(0.0, kante, UV.x) * smoothstep(0.0, kante, 1.0 - UV.x);
	COLOR = vec4(farbe.rgb, a);
}
"""
	return shader


## Karte auf den aktiven Modus stellen (Web buildCard): home/trip nutzen
## das Heim-Cover + Winke-Gooby-Sticker, game das Spiel-Cover aus dem
## Travel-Hint + das Game-Motiv, DLC-Karten (G6/DLC-LOAD) ihr DLC-Cover +
## DLC-Motiv + eigene Farbstimmung/Texte (rein datengetrieben, EIN System).
## Der Vorhang bleibt in ALLEN Modi das statische Blätter-Pattern auf
## Papier (Web .acui-veil).
func _apply_variant() -> void:
	if _root == null:
		return
	var minigame := not _active_hint.is_empty()
	var ranch := _ranch_aktiv and not minigame
	var dlc := "" if minigame else _dlc_karte
	_modus = "game" if minigame else modus_fuer_ziel(_ranch_ziel)
	var cover_tex: Texture2D
	if minigame:
		cover_tex = _active_hint.get("cover")
	elif dlc != "":
		cover_tex = _lade_textur(DlcLoadingKarten.cover_pfad(dlc))
	else:
		cover_tex = _lade_textur(COVER_HOME_PFAD)
	_cover_rect.texture = cover_tex
	_cover_rect.visible = cover_tex != null
	# Farbstimmung des Cover-Fallback-Verlaufs: pro DLC-Karte, sonst Web-Standard.
	_card.setze_fallback_farben(DlcLoadingKarten.fallback_farben(dlc))
	var titel := ""
	if minigame:
		titel = str(_active_hint.get("title", ""))
	elif dlc != "":
		titel = I18nService.t(DlcLoadingKarten.titel_key(dlc, _dlc_betreten))
	else:
		titel = I18nService.t("veil.%s.titel" % _modus)
	_title_label.text = titel
	_title_label.visible = titel != ""
	if dlc != "":
		_ready_label.text = I18nService.t(DlcLoadingKarten.bereit_key(dlc, _dlc_betreten))
	else:
		_ready_label.text = I18nService.t("veil.%s.bereit" % _modus)
	_gooby.set_motiv(_motiv_textur(minigame, dlc))
	_gooby.visible = true
	_laedt_label.visible = true
	_tip_label.visible = true
	_card.visible = not ranch
	_apply_ranch_variant(ranch)
	_advance_tip()


## Motiv-Sticker der Karte: Game-Motiv beim Minigame, DLC-Motiv auf
## DLC-Karten — fehlt dessen Bild, bleibt der Winke-Gooby (Garantie der
## Standard-Karte, Web-onerror-Verhalten).
func _motiv_textur(minigame: bool, dlc: String) -> Texture2D:
	if minigame:
		return _lade_textur(MOTIV_GAME_PFAD)
	if dlc != "":
		var motiv := _lade_textur(DlcLoadingKarten.motiv_pfad(dlc))
		if motiv != null:
			return motiv
	return _lade_textur(MOTIV_WAVE_PFAD)


## Vollbild-Schirm der langen Reisen ein-/ausblenden (RW-8).
func _apply_ranch_variant(ranch: bool) -> void:
	if not ranch:
		if _ranch_screen != null:
			_ranch_screen.visible = false
		return
	if String(_ranch_ziel).begins_with("ranch/") and is_inside_tree():
		# Bootstrap der Ranch-Klangschicht + Ankunftsmomente (lazy, einmalig —
		# beide Knoten hängen sich selbst an SceneRouter.travel_finished).
		RanchAudio.get_or_create(self)
		RanchMoments.get_or_create(self)
	if _ranch_screen == null:
		_ranch_screen = RanchLoadingScreen.new()
		_ranch_screen.name = "RanchScreen"
		_root.add_child(_ranch_screen)
	_ranch_screen.visible = true
	var stunde := stunde_override
	if stunde < 0.0:
		stunde = LoadingScreenRules.aktuelle_stunde()
	_ranch_screen.zeige(LoadingScreenRules.artwork_id_fuer(_ranch_ziel, stunde))
	_ranch_screen.set_progress(0.0)
	_advance_loading_tip()


func _advance_tip() -> void:
	var tips := _tips()
	if tips.is_empty():
		return
	_tip_label.text = str(tips[_tip_cursor % tips.size()])
	_tip_cursor += 1


## Tipp-Wechsel per 200-ms-Crossfade (Web .mg-loading-tip transition) —
## Reduced Motion wechselt hart.
func _wechsle_tip_weich() -> void:
	if not _tips_animiert:
		_advance_tip()
		return
	_stoppe_tip_fade()
	_tip_tween = create_tween()
	_tip_tween.tween_property(_tip_label, "modulate:a", 0.0, TIP_FADE_S)
	_tip_tween.tween_callback(_advance_tip)
	_tip_tween.tween_property(_tip_label, "modulate:a", 1.0, TIP_FADE_S)


func _stoppe_tip_fade() -> void:
	if _tip_tween != null and _tip_tween.is_valid():
		_tip_tween.kill()
	_tip_tween = null
	if _tip_label != null:
		_tip_label.modulate.a = 1.0


## Tipp des Vollbild-Schirms aus dem Shuffle-Bag (nie zweimal derselbe).
func _advance_loading_tip() -> void:
	if _ranch_screen == null:
		return
	var tips := I18nService.items(LoadingScreenRules.TIPS_KEY)
	var index := LoadingScreenRules.naechster_tipp_index(tips.size(), _loading_tipp_zustand)
	if index >= 0:
		_ranch_screen.set_tip(str(tips[index]))


func _on_tip_timer() -> void:
	if not visible:
		return
	if _ranch_aktiv and _ranch_screen != null and _ranch_screen.visible:
		_advance_loading_tip()
	elif _tip_label.visible:
		_wechsle_tip_weich()


## Rotierende Tipps des AKTIVEN Karten-Modus (Web §2.4: 3 je Modus) —
## DLC-Karten bringen ihren eigenen Pool mit (G6/DLC-LOAD, 6+ je DLC).
func _tips() -> Array:
	if _dlc_karte != "" and _active_hint.is_empty():
		var dlc_tips := I18nService.items(DlcLoadingKarten.tips_key(_dlc_karte))
		if not dlc_tips.is_empty():
			return dlc_tips
	return I18nService.items(tips_key(_modus))


## Asset mit Web-onerror-Verhalten: fehlt das Bild, bleibt der Verlauf.
static func _lade_textur(pfad: String) -> Texture2D:
	if not ResourceLoader.exists(pfad):
		push_warning("Veil-Asset fehlt: %s" % pfad)
		return null
	return load(pfad)
