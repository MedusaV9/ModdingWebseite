class_name RewardFlug
extends Node
## J6 (I-31) „Belohnungen reisen sichtbar": Münz-/XP-Gutschriften fliegen als
## 3–8 Sprites auf einer Bezier-Kurve (gestaffelt, mit Spin) von der Quelle
## zur HUD-Kapsel; die Kapsel pulst beim Eintreffen (Squish-Grammatik,
## `Hud.kapsel_puls`), der Zähler tickt über die bestehende Count-Up-Mechanik.
##
## ZENTRAL angedockt: der Dienst hört auf die EINE Wallet-Gutschrift —
## `GameState.coins_changed`/`xp_changed` (alle Aufrufer buchen über
## `Economy.award`/`Leveling.apply_xp` in `gs.update`, s. game_state.gd).
## Kein Aufrufer wird einzeln verdrahtet; eine Gutschrift KANN ihre
## Quelle-Position optional vorab mit `melde_quelle(pos)` mitmelden
## (kurzlebiger Hinweis, sonst startet der Flug in der Bildmitte).
##
## Verhaltensregeln:
## - HUD-Kapsel sichtbar → Flug zielt auf die Kapsel (`Hud.kapsel_anker`).
## - HUD geduckt/weg (Blatt offen, Vollbild-Screen) → ein kleiner
##   Zähler-Toast am Kapsel-Ort sammelt die Beträge und pulst stattdessen.
## - Aktiver MinigameHost → der Flug SCHWEIGT: der Results-Screen zählt
##   selbst hoch und nichts darf ihn spoilern (W18 B7).
## - Reduced Motion → Flug entfällt, Kapsel pulst genau EINMAL, der Zähler
##   zählt weiter (Count-Up snappt RM-konform, s. UiMotion).
##
## Performance: Sprite-Pool (max POOL_MAX TextureRects, wiederverwendet),
## keine Physik, GENAU EIN Tween pro Sprite (Intervall → Flug → Ankunft).

## Ein Flug ist gestartet (Wächter-Tests hören mit).
signal flug_gestartet(art: StringName, anzahl: int)

const GROUP := &"reward_flug"
## Overlay-Ebene: ÜBER Home-HUD (UiLayer 10) und Telefon (30), UNTER den
## Modal-Ebenen — Quest-/Sheet-Layer 60, Onboarding-Guide 70, RewardHub 90.
const EBENE := 50
## Sprite-Budget des Pools (harte Obergrenze gleichzeitiger Flug-Sprites).
const POOL_MAX := 16
const MIN_SPRITES := 3
const MAX_SPRITES := 8
## Ein Sprite mehr je BETRAG_PRO_SPRITE Münzen/XP (bis MAX_SPRITES).
const BETRAG_PRO_SPRITE := 12
const MUENZ_TEXTUR := "res://assets/ui/coin.png"
const XP_TEXTUR := "res://assets/ui/icons/sparkle.svg"
## Sprite-Kantenlänge in Design-px (skaliert mit UiScale).
const SPRITE_PX := 26.0
## Flugzeit des ersten Sprites; jedes weitere fliegt minimal länger.
const FLUG_DAUER_S := 0.42
const FLUG_DAUER_STAFFEL_S := 0.03
## Startversatz zwischen zwei Sprites (Staffelung).
const STAFFEL_S := 0.045
## Bogenstärke: Anteil der Flugstrecke, mindestens BOGEN_MIN_PX.
const BOGEN_ANTEIL := 0.22
const BOGEN_MIN_PX := 36.0
## Gesamtdrehung eines Sprites über den Flug (alternierende Richtung).
const SPIN_RAD := TAU * 1.25
## Quelle-Hinweis verfällt nach dieser Zeit (melde_quelle → Gutschrift).
const QUELLE_TTL_MS := 750
## Standzeit des Zähler-Toasts nach der letzten Sammlung.
const TOAST_HALTE_S := 1.8

## Quelle-Hinweis der nächsten Gutschrift (INF = keiner gemeldet).
static var _quelle_hinweis := Vector2.INF
static var _quelle_stempel_ms := 0

var _gs: Object = null
var _layer: CanvasLayer
var _buehne: Control
var _pool: Array[TextureRect] = []
## Beobachtete Stände (Sentinels: erst nach Baseline wird geflogen).
var _muenzen_stand := -1
var _xp_stand := -1.0
## Zähler-Toast (lazy gebaut) + Sammelstände.
var _toast: PanelContainer
var _toast_muenz_zeile: Control
var _toast_muenz_label: Label
var _toast_xp_zeile: Control
var _toast_xp_label: Label
var _toast_muenzen := 0
var _toast_xp := 0
var _toast_timer: Timer
var _toast_fade: Tween


## Dienst erzeugen und an den Home-Entry hängen (idempotent, Gruppe) —
## Muster RewardHub.attach_to.
static func attach_to(parent: Node, gs: Object) -> RewardFlug:
	var tree := parent.get_tree()
	if tree != null:
		var existing := tree.get_first_node_in_group(GROUP)
		if existing is RewardFlug:
			return existing
	var dienst := RewardFlug.new()
	dienst.name = "RewardFlug"
	dienst._gs = gs
	parent.add_child(dienst)
	return dienst


## Aktiver Dienst im Baum (null ohne Home-Entry, z. B. nackte Tests).
static func find(node: Node) -> RewardFlug:
	if node == null or not node.is_inside_tree():
		return null
	var found := node.get_tree().get_first_node_in_group(GROUP)
	return found if found is RewardFlug else null


## Optionale Quelle-Meldung einer Gutschrift: die nächste Buchung (innerhalb
## QUELLE_TTL_MS) startet ihren Flug an `pos` statt in der Bildmitte.
## Vector2.INF = kein Hinweis (No-op).
static func melde_quelle(pos: Vector2) -> void:
	_quelle_hinweis = pos
	_quelle_stempel_ms = Time.get_ticks_msec()


## Kapsel-/Toast-Puls in Squish-Grammatik (Druck → Overshoot → federnd
## zurück, wie SquishButton). `reduziert` = Reduced Motion: genau EIN
## sanfter Mini-Puls statt Feder-Squish (Auftrag: „Kapsel pulst nur einmal").
static func kapsel_squish(ctl: Control, reduziert: bool) -> Tween:
	if ctl == null or not ctl.is_inside_tree():
		return null
	ctl.pivot_offset = ctl.size / 2.0
	# Anti-Stapeln (UiMotion-_fresh_tween-Muster): alten Puls kappen.
	if ctl.has_meta(&"_rf_puls"):
		var alt: Variant = ctl.get_meta(&"_rf_puls")
		if alt is Tween and (alt as Tween).is_valid():
			(alt as Tween).kill()
	ctl.scale = Vector2.ONE
	var tween := ctl.create_tween()
	ctl.set_meta(&"_rf_puls", tween)
	if reduziert:
		tween.tween_property(ctl, "scale", Vector2.ONE * 1.04, 0.09)
		tween.tween_property(ctl, "scale", Vector2.ONE, 0.12)
		return tween
	(
		tween
		. tween_property(ctl, "scale", Vector2.ONE * AcTokens.PRESS_SCALE, AcTokens.DUR_POP * 0.4)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		tween
		. tween_property(ctl, "scale", Vector2.ONE * 1.08, AcTokens.DUR_POP * 0.5)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		tween
		. tween_property(ctl, "scale", Vector2.ONE, AcTokens.DUR_POP * 0.7)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	return tween


# ── Pure Flug-Geometrie (headless testbar) ───────────────────────────────────


## Sprite-Anzahl einer Gutschrift: 3 Basis + 1 je BETRAG_PRO_SPRITE, 3..8.
static func sprite_anzahl(betrag: int) -> int:
	if betrag <= 0:
		return 0
	var extra := int(floor(float(betrag) / float(BETRAG_PRO_SPRITE)))
	return clampi(MIN_SPRITES + extra, MIN_SPRITES, MAX_SPRITES)


## Kontrollpunkt der quadratischen Bezier-Kurve: Mittelpunkt plus seitlicher
## Bogen (Seite alterniert je Sprite-Index, Stärke wächst leicht mit).
static func kontrollpunkt(start: Vector2, ziel: Vector2, index: int) -> Vector2:
	var mitte := (start + ziel) / 2.0
	var strecke := ziel - start
	if strecke.length() < 0.001:
		return mitte + Vector2(0.0, -BOGEN_MIN_PX)
	var seite := 1.0 if index % 2 == 0 else -1.0
	var staerke := maxf(strecke.length() * BOGEN_ANTEIL, BOGEN_MIN_PX)
	staerke *= 1.0 + 0.12 * float(index)
	return mitte + strecke.orthogonal().normalized() * seite * staerke


## Punkt der quadratischen Bezier-Kurve bei t (0 = Start, 1 = Ziel).
static func kurven_punkt(start: Vector2, kontrolle: Vector2, ziel: Vector2, t: float) -> Vector2:
	var tt := clampf(t, 0.0, 1.0)
	var u := 1.0 - tt
	return start * u * u + kontrolle * 2.0 * u * tt + ziel * tt * tt


## Startversatz des i-ten Sprites (streng monoton — Staffelung).
static func staffel_verzoegerung(index: int) -> float:
	return float(maxi(index, 0)) * STAFFEL_S


## Flugdauer des i-ten Sprites (spätere fliegen minimal länger).
static func flug_dauer(index: int) -> float:
	return FLUG_DAUER_S + float(maxi(index, 0)) * FLUG_DAUER_STAFFEL_S


## Drehwinkel bei t — Richtung alterniert je Sprite.
static func spin_winkel(index: int, t: float) -> float:
	var richtung := 1.0 if index % 2 == 0 else -1.0
	return richtung * SPIN_RAD * clampf(t, 0.0, 1.0)


## Größenverlauf über den Flug: klein starten, mittig überschwingen,
## bei 1.0 exakt in Ruhegröße ankommen.
static func flug_scale(t: float) -> float:
	var tt := clampf(t, 0.0, 1.0)
	return lerpf(0.72, 1.0, tt) + 0.22 * sin(PI * tt)


## Minispiel-Schutz (pur testbar): während ein MinigameHost die aktive
## Szene ist, schweigt der Flug — Results zählt selbst (W18 B7, kein
## Count-Up-Spoiler).
static func soll_schweigen(aktuelle_szene: Object) -> bool:
	return aktuelle_szene is MinigameHost


# ── Aufbau / Signale ─────────────────────────────────────────────────────────


func _ready() -> void:
	add_to_group(GROUP)
	_layer = CanvasLayer.new()
	_layer.name = "RewardFlugLayer"
	_layer.layer = EBENE
	add_child(_layer)
	_buehne = Control.new()
	_buehne.name = "FlugBuehne"
	_buehne.theme = ThemeService.theme()
	_buehne.set_anchors_preset(Control.PRESET_FULL_RECT)
	_buehne.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_buehne)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(_on_toast_timeout)
	add_child(_toast_timer)
	if _gs is Node:
		var gs := _gs as Node
		if gs.has_signal("coins_changed"):
			gs.coins_changed.connect(_on_coins_changed)
		if gs.has_signal("xp_changed"):
			gs.xp_changed.connect(_on_xp_changed)
		# Frischer Load/Import: Stände neu ankern statt Differenz zu fliegen.
		if gs.has_signal("state_loaded"):
			gs.state_loaded.connect(func(_fresh: bool, _recovered: bool) -> void: _baseline())
	_baseline()


## Anzahl gerade fliegender Sprites (Wächter-Tests).
func aktive_sprites() -> int:
	var n := 0
	for sprite in _pool:
		if bool(sprite.get_meta(&"_rf_aktiv", false)):
			n += 1
	return n


## Sichtbarer Sammel-Toast? (Wächter-Tests)
func toast_offen() -> bool:
	return _toast != null and is_instance_valid(_toast) and _toast.visible


func _baseline() -> void:
	if _gs == null or not (_gs.has_method("is_loaded") and _gs.is_loaded()):
		return
	_muenzen_stand = int(_gs.get_value("economy.coins", 0))
	_xp_stand = float(_gs.get_value("progression.xp", 0.0))


func _on_coins_changed(coins: int) -> void:
	var vorher := _muenzen_stand
	_muenzen_stand = coins
	if vorher < 0 or coins <= vorher:
		return
	_gutschrift(&"muenzen", coins - vorher)


func _on_xp_changed(xp: float) -> void:
	var vorher := _xp_stand
	_xp_stand = xp
	if vorher < 0.0 or is_equal_approx(xp, vorher):
		return
	# Level-Up rollt die XP herunter (apply_xp zieht xp_to_next ab) — auch
	# das ist ein Verdien-Moment; der Betrag ist dann nur eine Schätzung.
	_gutschrift(&"xp", maxi(1, int(roundf(absf(xp - vorher)))))


# ── Gutschrift → Flug/Toast/Puls ─────────────────────────────────────────────


func _gutschrift(art: StringName, betrag: int) -> void:
	if betrag <= 0 or not is_inside_tree():
		return
	if _minigame_aktiv():
		return
	var start := _quelle_oder_mitte()
	var hud := _finde_hud()
	var anker := hud.kapsel_anker(art) if hud != null else {"pos": Vector2.INF, "sichtbar": false}
	var kapsel_da := bool(anker.get("sichtbar", false))
	var anker_pos: Vector2 = anker.get("pos", Vector2.INF)
	if ThemeService.is_reduced_motion(self):
		# RM-Pfad (Auftrag): Flug entfällt, Kapsel pulst genau EINMAL,
		# der Zähler zählt über die bestehende Count-Up-Mechanik.
		if kapsel_da:
			hud.kapsel_puls(art)
		else:
			_toast_sammle(art, betrag, anker_pos)
		AudioDirector.try_play(self, "ui_coins")
		return
	var ziel := anker_pos
	if not kapsel_da:
		# HUD geduckt/weg: der Zähler-Toast sammelt am Kapsel-Ort.
		_toast_sammle(art, betrag, anker_pos)
		ziel = _toast.get_global_rect().get_center()
	_fliege(art, betrag, start, ziel)


func _fliege(art: StringName, betrag: int, start: Vector2, ziel: Vector2) -> void:
	var textur: Texture2D = load(MUENZ_TEXTUR if art == &"muenzen" else XP_TEXTUR)
	if textur == null:
		return
	var kante := SPRITE_PX * UiScale.for_viewport(get_viewport())
	var gestartet := 0
	for i in sprite_anzahl(betrag):
		var sprite := _hole_sprite()
		if sprite == null:
			break
		sprite.texture = textur
		sprite.self_modulate = Color.WHITE if art == &"muenzen" else AcTokens.GOLD
		sprite.size = Vector2.ONE * kante
		sprite.pivot_offset = sprite.size / 2.0
		sprite.rotation = 0.0
		sprite.scale = Vector2.ONE
		sprite.position = start - sprite.pivot_offset
		sprite.set_meta(&"_rf_aktiv", true)
		# GENAU EIN Tween pro Sprite: Staffel-Intervall → sichtbar →
		# Kurvenflug (tween_method) → Ankunft.
		var tween := sprite.create_tween()
		sprite.set_meta(&"_rf_flug", tween)
		tween.tween_interval(maxf(staffel_verzoegerung(i), 0.001))
		tween.tween_callback(func() -> void: sprite.visible = true)
		var kontrolle := kontrollpunkt(start, ziel, i)
		(
			tween
			. tween_method(
				_flug_tick.bind(sprite, start, kontrolle, ziel, i), 0.0, 1.0, flug_dauer(i)
			)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)
		tween.tween_callback(_ankunft.bind(sprite, art, i == 0))
		gestartet += 1
	if gestartet > 0:
		flug_gestartet.emit(art, gestartet)


func _flug_tick(
	t: float, sprite: TextureRect, start: Vector2, kontrolle: Vector2, ziel: Vector2, index: int
) -> void:
	sprite.position = kurven_punkt(start, kontrolle, ziel, t) - sprite.pivot_offset
	sprite.rotation = spin_winkel(index, t)
	sprite.scale = Vector2.ONE * flug_scale(t)


func _ankunft(sprite: TextureRect, art: StringName, mit_ton: bool) -> void:
	sprite.visible = false
	sprite.set_meta(&"_rf_aktiv", false)
	if mit_ton:
		# Münz-Klimper-Tick über die vorhandene SFX-API (einmal pro Flug).
		AudioDirector.try_play(self, "ui_coins")
	var hud := _finde_hud()
	if hud != null and bool(hud.kapsel_anker(art).get("sichtbar", false)):
		hud.kapsel_puls(art)
	elif toast_offen():
		kapsel_squish(_toast, false)


# ── Sprite-Pool ──────────────────────────────────────────────────────────────


func _hole_sprite() -> TextureRect:
	for sprite in _pool:
		if not bool(sprite.get_meta(&"_rf_aktiv", false)):
			_kappe_flug(sprite)
			return sprite
	if _pool.size() >= POOL_MAX:
		return null
	var sprite := TextureRect.new()
	sprite.name = "FlugSprite%d" % _pool.size()
	sprite.visible = false
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_buehne.add_child(sprite)
	_pool.append(sprite)
	return sprite


func _kappe_flug(sprite: TextureRect) -> void:
	if sprite.has_meta(&"_rf_flug"):
		var alt: Variant = sprite.get_meta(&"_rf_flug")
		if alt is Tween and (alt as Tween).is_valid():
			(alt as Tween).kill()


# ── Zähler-Toast (HUD geduckt/weg) ──────────────────────────────────────────


func _toast_sammle(art: StringName, betrag: int, anker_pos: Vector2) -> void:
	_toast_bauen()
	if _toast_fade != null and _toast_fade.is_valid():
		_toast_fade.kill()
		_toast_fade = null
	var neu_sichtbar := not _toast.visible
	if art == &"muenzen":
		var alt := _toast_muenzen
		_toast_muenzen += betrag
		_toast_muenz_zeile.visible = true
		UiMotion.count_to(_toast_muenz_label, alt, _toast_muenzen, _plus_format())
	else:
		var alt_xp := _toast_xp
		_toast_xp += betrag
		_toast_xp_zeile.visible = true
		UiMotion.count_to(_toast_xp_label, alt_xp, _toast_xp, _plus_format())
	_toast.visible = true
	_toast.modulate.a = 1.0
	_toast_positionieren(anker_pos)
	if neu_sichtbar:
		UiMotion.pop_in(_toast)
	_toast_timer.start(TOAST_HALTE_S)


func _plus_format() -> Callable:
	return func(v: int) -> String: return "+%d" % v


## Toast mittig auf den Kapsel-Ort legen (Fallback: oben mittig), im
## sichtbaren Bild geklemmt.
func _toast_positionieren(anker_pos: Vector2) -> void:
	var rect := get_viewport().get_visible_rect()
	var pos := anker_pos
	if not pos.is_finite():
		pos = rect.position + Vector2(rect.size.x / 2.0, rect.size.y * 0.12)
	_toast.reset_size()
	var groesse := _toast.get_combined_minimum_size()
	_toast.size = groesse
	var lo := rect.position + Vector2.ONE * 8.0
	var hi := rect.position + rect.size - groesse - Vector2.ONE * 8.0
	_toast.position = (pos - groesse / 2.0).clamp(lo, hi.max(lo))


func _toast_bauen() -> void:
	if _toast != null and is_instance_valid(_toast):
		return
	_toast = PanelContainer.new()
	_toast.name = "ZaehlerToast"
	_toast.theme_type_variation = &"StatusCapsule"
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_child(box)
	_toast_muenz_zeile = _toast_zeile(box, MUENZ_TEXTUR, Color.WHITE)
	_toast_muenz_label = _toast_zeile_label(_toast_muenz_zeile)
	_toast_xp_zeile = _toast_zeile(box, XP_TEXTUR, AcTokens.GOLD)
	_toast_xp_label = _toast_zeile_label(_toast_xp_zeile)
	_buehne.add_child(_toast)


func _toast_zeile(parent: Control, textur_pfad: String, tint: Color) -> Control:
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 4)
	zeile.visible = false
	zeile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.texture = load(textur_pfad)
	icon.custom_minimum_size = Vector2.ONE * 18.0
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.self_modulate = tint
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zeile.add_child(icon)
	var label := Label.new()
	label.name = "Wert"
	label.add_theme_font_override("font", ThemeService.font(800))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zeile.add_child(label)
	parent.add_child(zeile)
	return zeile


func _toast_zeile_label(zeile: Control) -> Label:
	return zeile.get_node("Wert") as Label


func _on_toast_timeout() -> void:
	if _toast == null or not is_instance_valid(_toast):
		return
	_toast_fade = UiMotion.fade_out(_toast)
	if _toast_fade != null:
		_toast_fade.tween_callback(_toast_reset)
	else:
		_toast_reset()


func _toast_reset() -> void:
	if _toast == null or not is_instance_valid(_toast):
		return
	_toast.visible = false
	_toast.modulate.a = 1.0
	_toast_muenzen = 0
	_toast_xp = 0
	_toast_muenz_zeile.visible = false
	_toast_xp_zeile.visible = false


# ── Ziel-/Quelle-Findung ─────────────────────────────────────────────────────


func _finde_hud() -> Hud:
	var hud := get_tree().get_first_node_in_group(&"hud")
	return hud if hud is Hud else null


func _minigame_aktiv() -> bool:
	var router := get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("get_current_scene"):
		return false
	return soll_schweigen(router.get_current_scene())


func _quelle_oder_mitte() -> Vector2:
	# Hinweis verfällt per TTL statt One-Shot: EIN Claim bucht Münzen UND XP
	# direkt nacheinander — beide Flüge starten am selben getappten Knopf.
	var frisch := Time.get_ticks_msec() - _quelle_stempel_ms <= QUELLE_TTL_MS
	if frisch and _quelle_hinweis.is_finite():
		return _quelle_hinweis
	var rect := get_viewport().get_visible_rect()
	return rect.position + rect.size / 2.0
