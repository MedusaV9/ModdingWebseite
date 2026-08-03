class_name BeuteFlug
extends CanvasLayer
## G8/IDEA-J1 „Beute-Flug-Dreiklang“ — der universelle Reward-Flug-Layer:
## Münz-Sprites starten an der globalen Rect der Quelle (Claim-Knopf,
## Kassensturz-Karte, Popup) und fliegen in gestaffelten Bogen-Bahnen
## (Quad-Bezier; TRANS_BACK/EASE_OUT schießt über t=1 hinaus → leichter
## Überschwung ÜBER die Pille) zur HUD-Münz-Pille. JEDE Ankunft klingt als
## ui_tick mit Pitch-Treppe (0.9→1.6 über die Serie, AUDIO-GRAMMATIK
## „semantische Steigerungsreihe“), kitzelt als 3-ms-Haptik-Tick
## (Haptics.zaehl_tick) und pulst die Pille mini — der HUD-Zähler läuft
## SYNCHRON zur Ankunftsserie (hud.muenzflug_*-API) statt sofort.
## Abschluss = ui_coins + Haptics.success (Münz-EINNAHME, §3-Grammatik);
## Aufrufer, die ihre Erfolgs-Haptik schon am Claim feuern, geben
## {"erfolgs_haptik": false} mit (kein Doppelimpuls).
##
## Reduced Motion (Ersatz-Grammatik, Bestandsregel squish_button.gd/J1):
## KEIN Flug, aber Pitch-Treppe + synchrones Zählen bleiben — Sound und
## Haptik sind keine Motion.
##
## Ohne Home-HUD (Minispiel-/Stadt-/DLC-Routen) fliegen die Münzen zum
## „Börsen-Anker“ oben rechts (wo die Pille zuhause wohnt) — die Serie
## bleibt überall dieselbe, nur die Zähler-Übernahme entfällt.
##
## Performance: fester Sprite-Pool (TextureRects, unsichtbar geparkt) —
## kein Node-Churn pro Feier. LEDGER-NEUTRAL: dieser Layer bucht NIE
## Münzen (nur Economy bucht), er liest Beträge nur für die Choreo.

const NODE_NAME := "BeuteFlug"
## Über RewardHub-Toasts (90), unter LoadingVeil (100).
const LAYER_NR := 95

## 6–14 Münzen je Feier: Basis + 1 je 10 Münzen Betrag, hart gedeckelt
## (J1-Wachpunkt: kein Tick-Spam bei großen Beträgen).
const MIN_SPRITES := 6
const MAX_SPRITES := 14
const MUENZEN_JE_SPRITE := 10

## Start-Staffelung > AudioDirector.DEBOUNCE_MSEC (45 ms): jede Ankunft
## bleibt einzeln hörbar.
const STAFFEL_S := 0.06
## Grund-Flugdauer; spätere Münzen fliegen MINIMAL länger (Schweif-Gefühl).
## Die Streckung wächst monoton mit dem Index — so kippt die Ankunfts-
## Reihenfolge nie und der Tick-Abstand fällt nie unter die Staffelung.
const FLUG_S := 0.5
const FLUG_STRECKUNG_S := 0.12
## Pitch-Treppe über die Serie (J1/AUDIO-GRAMMATIK).
const PITCH_VON := 0.9
const PITCH_BIS := 1.6
## Luft zwischen letzter Ankunft und dem ui_coins-Abschluss.
const ABSCHLUSS_PAUSE_S := 0.12

const SPRITE_PX := 26.0
const COIN_TEX := "res://assets/ui/coin.png"
## Bogen-Auslenkung als Anteil der Luftlinie, Seite alterniert je Sprite.
const BOGEN_FAKTOR := 0.18
const BOGEN_VAR := 0.08
## Münzen schrumpfen Richtung Pille (Ziel „schluckt“ sie).
const ZIEL_SCHRUMPF := 0.6
## Pool-Deckel: zwei volle Serien parallel, mehr Sprites gibt es nie.
const POOL_MAX := MAX_SPRITES * 2
## Börsen-Anker oben rechts, falls kein Home-HUD im Baum hängt.
const ANKER_RAND_X := 110.0
const ANKER_Y := 70.0

## Duplikat-Schutz (Muster AudioDirector): das deferred add_child ist erst
## einen Frame später sichtbar — Aufrufe im selben Frame teilen die Instanz.
static var _instanz: BeuteFlug

var _pool_frei: Array[TextureRect] = []
var _pool_gesamt := 0
## Nur EINE Serie treibt den HUD-Zähler; Überlapp fliegt rein visuell.
var _zaehler_aktiv := false


## Bequemer One-Liner für alle Belohnungs-Stellen: lässt `betrag` Münzen von
## `quelle` (Control oder globale Canvas-Position) zur HUD-Münz-Pille
## fliegen. Gibt false zurück (still, no-op), wenn nichts zu feiern ist —
## Aufrufer können dann ihren bisherigen Klang behalten.
## opts: {"ziel": Control-Override, "erfolgs_haptik": bool (Default true)}.
static func fliegen(from: Node, quelle: Variant, betrag: int, opts: Dictionary = {}) -> bool:
	if from == null or not from.is_inside_tree() or betrag <= 0:
		return false
	var layer := get_or_create(from)
	# Quell-Rect SOFORT einfrieren — Popups/Overlays sterben oft direkt
	# nach dem Claim (daily_bonus_popup.queue_free im selben Frame).
	var start := _quelle_punkt(quelle, from)
	# Deferred: reiht sich hinter das deferred add_child der Erst-Erzeugung.
	layer._starte_serie.call_deferred(start, betrag, opts)
	return true


## Autoload-frei (Muster AudioDirector.get_or_create): lazy unter /root.
static func get_or_create(from: Node) -> BeuteFlug:
	var existing := from.get_node_or_null("/root/%s" % NODE_NAME)
	if existing is BeuteFlug:
		return existing
	if _instanz != null and is_instance_valid(_instanz):
		return _instanz
	var layer := BeuteFlug.new()
	layer.name = NODE_NAME
	layer.layer = LAYER_NR
	_instanz = layer
	from.get_tree().root.add_child.call_deferred(layer)
	return layer


# ── PURE Flug-Planung (deterministisch, headless testbar) ────────────────────


## Sprite-Anzahl skaliert mit dem Betrag und ist gedeckelt (6–14).
static func anzahl_sprites(betrag: int) -> int:
	if betrag <= 0:
		return 0
	return clampi(MIN_SPRITES + betrag / MUENZEN_JE_SPRITE, MIN_SPRITES, MAX_SPRITES)


## Pitch-Treppe 0.9→1.6 über die Serie; Einzel-Ankunft bleibt beim Start.
static func pitch_fuer(i: int, n: int) -> float:
	if n <= 1:
		return PITCH_VON
	return lerpf(PITCH_VON, PITCH_BIS, float(i) / float(n - 1))


## Kompletter Serien-Plan: Starts, Flugdauern, Ankünfte, Pitches, Ende.
## Reduced Motion: sprites=0 (kein Flug), aber die Tick-/Pitch-Serie bleibt
## als kompaktes Arpeggio (Ankunft = Startzeit) — Ersatz-Grammatik.
static func plan_erstellen(betrag: int, reduziert: bool) -> Dictionary:
	var n := anzahl_sprites(betrag)
	var starts: Array[float] = []
	var dauern: Array[float] = []
	var ankuenfte: Array[float] = []
	var pitches: Array[float] = []
	for i in n:
		var start_s := float(i) * STAFFEL_S
		var dauer_s := FLUG_S + FLUG_STRECKUNG_S * (float(i) / float(maxi(n - 1, 1)))
		starts.append(start_s)
		dauern.append(dauer_s)
		ankuenfte.append(start_s if reduziert else start_s + dauer_s)
		pitches.append(pitch_fuer(i, n))
	var letzte := ankuenfte[n - 1] if n > 0 else 0.0
	return {
		"sprites": 0 if reduziert else n,
		"ticks": n,
		"starts_s": starts,
		"dauern_s": dauern,
		"ankuenfte_s": ankuenfte,
		"pitches": pitches,
		"ende_s": letzte + ABSCHLUSS_PAUSE_S,
	}


# ── Serien-Choreo (Tree-Timer: überlebt den Tod der Quell-Nodes) ─────────────


func _starte_serie(start: Vector2, betrag: int, opts: Dictionary) -> void:
	if not is_inside_tree():
		return
	var reduziert := RewardFx.reduced_motion(self)
	var plan := plan_erstellen(betrag, reduziert)
	var ticks := int(plan["ticks"])
	if ticks <= 0:
		return
	var hud := _finde_hud()
	var ziel := _ziel_punkt(hud, opts)
	var zaehler_hud: Control = null
	var von := 0
	var bis := 0
	if hud != null and not _zaehler_aktiv:
		_zaehler_aktiv = true
		zaehler_hud = hud
		var uebernahme: Dictionary = hud.muenzflug_start(betrag)
		von = int(uebernahme["von"])
		bis = int(uebernahme["bis"])
	var starts: Array = plan["starts_s"]
	var dauern: Array = plan["dauern_s"]
	var ankuenfte: Array = plan["ankuenfte_s"]
	var pitches: Array = plan["pitches"]
	var tree := get_tree()
	for i in ticks:
		if i < int(plan["sprites"]):
			tree.create_timer(float(starts[i])).timeout.connect(
				_sprite_starten.bind(start, ziel, float(dauern[i]), i)
			)
		# Zähler-Zwischenstand dieser Ankunft (letzte zeigt exakt `bis`).
		var wert := von + int(roundf(float(bis - von) * float(i + 1) / float(ticks)))
		tree.create_timer(float(ankuenfte[i])).timeout.connect(
			_ankunft.bind(float(pitches[i]), zaehler_hud, wert)
		)
	tree.create_timer(float(plan["ende_s"])).timeout.connect(
		_abschluss.bind(zaehler_hud, bool(opts.get("erfolgs_haptik", true)))
	)


## Eine Ankunft: Tick (Pitch-Treppe) + 3-ms-Haptik + Zähler-Schritt/Puls.
func _ankunft(pitch: float, zaehler_hud: Control, wert: int) -> void:
	if not is_inside_tree():
		return
	AudioDirector.try_play(self, "ui_tick", pitch)
	Haptics.zaehl_tick(self)
	if zaehler_hud != null and is_instance_valid(zaehler_hud) and zaehler_hud.is_inside_tree():
		zaehler_hud.muenzflug_schritt(wert)


## Serienende: Münz-EINNAHME klingt (ui_coins), Erfolgs-Doppelimpuls (falls
## nicht schon der Claim summte), Zähler zeigt garantiert die Wahrheit.
func _abschluss(zaehler_hud: Control, erfolgs_haptik: bool) -> void:
	if zaehler_hud != null:
		_zaehler_aktiv = false
		if is_instance_valid(zaehler_hud) and zaehler_hud.is_inside_tree():
			zaehler_hud.muenzflug_abschluss()
	if not is_inside_tree():
		return
	AudioDirector.try_play(self, "ui_coins")
	if erfolgs_haptik:
		Haptics.success(self)


# ── Sprites (Pool, Quad-Bezier-Bogen) ────────────────────────────────────────


func _sprite_starten(von: Vector2, nach: Vector2, dauer_s: float, idx: int) -> void:
	if not is_inside_tree():
		return
	var sprite := _sprite_holen()
	if sprite == null:
		return
	# Start leicht gestreut (Goldwinkel, deterministisch je Index) — die
	# Serie startet als „Handvoll Münzen“, nicht als Punktstrahl.
	var start := von + Vector2.from_angle(float(idx) * 2.399963) * (8.0 + 4.0 * float(idx % 3))
	var richtung := nach - start
	var normale := Vector2(-richtung.y, richtung.x).normalized()
	var seite := 1.0 if idx % 2 == 0 else -1.0
	var hub := richtung.length() * (BOGEN_FAKTOR + BOGEN_VAR * float(idx % 3))
	var kontrolle := (start + nach) * 0.5 + normale * (seite * hub)
	_sprite_setzen(0.0, sprite, start, kontrolle, nach)
	# Tween auf dem LAYER (nicht dem Sprite): der Pool lebt weiter, das
	# TRANS_BACK/EASE_OUT-t schießt über 1 hinaus → Überschwung überm Ziel.
	var tween := create_tween()
	(
		tween
		. tween_method(_sprite_setzen.bind(sprite, start, kontrolle, nach), 0.0, 1.0, dauer_s)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	tween.tween_callback(_sprite_zuruecklegen.bind(sprite))


## Quad-Bezier-Punkt + Schrumpfen/Ausblenden Richtung Pille. t darf über 1
## hinauslaufen (Überschwung) — die Sicht-Parameter bleiben geklemmt.
func _sprite_setzen(
	t: float, sprite: TextureRect, von: Vector2, kontrolle: Vector2, nach: Vector2
) -> void:
	if not is_instance_valid(sprite):
		return
	var a := von.lerp(kontrolle, t)
	var b := kontrolle.lerp(nach, t)
	sprite.position = a.lerp(b, t) - sprite.size * 0.5
	var sicht := clampf(t, 0.0, 1.0)
	sprite.scale = Vector2.ONE * lerpf(1.0, ZIEL_SCHRUMPF, sicht)
	sprite.modulate.a = 1.0 - maxf(sicht - 0.85, 0.0) / 0.15 * 0.35


func _sprite_holen() -> TextureRect:
	while not _pool_frei.is_empty():
		var wieder: TextureRect = _pool_frei.pop_back()
		if is_instance_valid(wieder):
			wieder.visible = true
			return wieder
	if _pool_gesamt >= POOL_MAX:
		return null
	var sprite := TextureRect.new()
	sprite.texture = load(COIN_TEX)
	sprite.size = Vector2.ONE * SPRITE_PX
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite.pivot_offset = Vector2.ONE * (SPRITE_PX * 0.5)
	add_child(sprite)
	_pool_gesamt += 1
	return sprite


func _sprite_zuruecklegen(sprite: TextureRect) -> void:
	if not is_instance_valid(sprite):
		return
	sprite.visible = false
	sprite.modulate.a = 1.0
	sprite.scale = Vector2.ONE
	_pool_frei.append(sprite)


# ── Quelle/Ziel auflösen ─────────────────────────────────────────────────────


static func _quelle_punkt(quelle: Variant, from: Node) -> Vector2:
	if quelle is Control:
		var ctl := quelle as Control
		if is_instance_valid(ctl) and ctl.is_inside_tree():
			return ctl.get_global_rect().get_center()
	if quelle is Vector2:
		return quelle
	var viewport := from.get_viewport()
	if viewport != null:
		return viewport.get_visible_rect().size * 0.5
	return Vector2.ZERO


## Home-HUD über die Gruppe (Muster DialogBubble/WhatsNextHint) — nur wenn
## es die J1-Pillen-API wirklich anbietet.
func _finde_hud() -> Control:
	var hud := get_tree().get_first_node_in_group(&"hud")
	if hud is Control and hud.has_method("coin_ziel_rect"):
		return hud
	return null


func _ziel_punkt(hud: Control, opts: Dictionary) -> Vector2:
	var ziel: Variant = opts.get("ziel")
	if ziel is Control:
		var ctl := ziel as Control
		if is_instance_valid(ctl) and ctl.is_inside_tree():
			return ctl.get_global_rect().get_center()
	if hud != null:
		var rect: Rect2 = hud.coin_ziel_rect()
		if rect.size != Vector2.ZERO:
			return rect.get_center()
	# Börsen-Anker: oben rechts in der Canvas (wo die Pille zuhause wohnt).
	var canvas := get_viewport().get_visible_rect().size
	return Vector2(canvas.x - ANKER_RAND_X, ANKER_Y)
