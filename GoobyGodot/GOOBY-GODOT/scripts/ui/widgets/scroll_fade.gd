class_name ScrollFade
extends MarginContainer
## G7 — Scroll-Affordance für Listen/Grids: legt weiche Fade-Kanten über
## einen ScrollContainer und zeigt sie nur, wenn es in der jeweiligen
## Richtung wirklich weitergeht. So liest sich eine angeschnittene Zeile
## als Einladung zum Scrollen statt als Layout-Fehler (User-Befund
## Garderobe/Gestalten: „letzter Eintrag hart halbiert, ohne Hinweis“).
##
## Nutzung zur Bauzeit (Scroll noch OHNE Parent):
##   var huelle := ScrollFade.um(scroll)
##   spalte.add_child(huelle)
## Der Wrapper ist ein MarginContainer: beide Kinder (Scroll + Fade-Deck)
## liegen auf demselben Rechteck, das Deck zeichnet obendrüber.
## `rand_inset()` schiebt den Scroll samt Scrollbar vom Spalten-/
## Display-Rand weg (User-Befund: „Scrollbar klebt am Bildschirmrand“).
##
## Die Kanten sind STATISCHE Affordance (kein Motion) — sie bewegen sich
## nicht von selbst, darum braucht es hier kein Reduced-Motion-Gate.

## Dicke einer Fade-Kante in Design-px (Screens skalieren mit f nach).
const KANTE := 34.0
## Ab diesem Scroll-Rest (px) gilt eine Richtung als „geht noch weiter“.
const REST_EPSILON := 1.0

var _scroll: ScrollContainer
var _kante_px := KANTE
var _oben: TextureRect
var _unten: TextureRect
var _links: TextureRect
var _rechts: TextureRect


## Wrapper um einen (noch elternlosen) ScrollContainer bauen. Übernimmt
## dessen Size-Flags, damit er im Layout an dieselbe Stelle rückt.
static func um(scroll: ScrollContainer) -> ScrollFade:
	var huelle := ScrollFade.new()
	huelle._scroll = scroll
	huelle.size_flags_horizontal = scroll.size_flags_horizontal
	huelle.size_flags_vertical = scroll.size_flags_vertical
	huelle.add_child(scroll)
	huelle.add_child(huelle._deck_bauen())
	return huelle


func _ready() -> void:
	if _scroll == null:
		return
	# Range.changed feuert bei max/page-Änderungen (Inhalt/Resize),
	# value_changed beim Scrollen selbst — beide halten die Kanten frisch.
	var vbar := _scroll.get_v_scroll_bar()
	vbar.value_changed.connect(_on_scroll_bewegt)
	vbar.changed.connect(_aktualisieren)
	var hbar := _scroll.get_h_scroll_bar()
	hbar.value_changed.connect(_on_scroll_bewegt)
	hbar.changed.connect(_aktualisieren)
	resized.connect(_aktualisieren)
	_aktualisieren()


## Abstand des Scrolls (und damit seiner Scrollbar) zum rechten
## Wrapper-Rand — die Bar klebt nie mehr am äußersten Display-Rand.
func rand_inset(px: int) -> void:
	add_theme_constant_override("margin_right", maxi(px, 0))


## Kanten-Dicke nachziehen (Metrik-Pass der Screens: KANTE × f).
func kanten_hoehe(px: float) -> void:
	_kante_px = maxf(px, 8.0)
	_kanten_layouten()
	_aktualisieren()


## Test-Introspektion: lädt die Unten-Kante gerade zum Weiterscrollen ein?
func unten_aktiv() -> bool:
	return _unten != null and _unten.visible


func _on_scroll_bewegt(_wert: float) -> void:
	_aktualisieren()


## Kanten nur zeigen, wenn es in der Richtung wirklich weitergeht.
func _aktualisieren() -> void:
	if _scroll == null or _unten == null:
		return
	var vbar := _scroll.get_v_scroll_bar()
	var v_aktiv := _scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
	_unten.visible = v_aktiv and vbar.max_value - vbar.page - vbar.value > REST_EPSILON
	_oben.visible = v_aktiv and vbar.value > REST_EPSILON
	var hbar := _scroll.get_h_scroll_bar()
	var h_aktiv := _scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
	_rechts.visible = h_aktiv and hbar.max_value - hbar.page - hbar.value > REST_EPSILON
	_links.visible = h_aktiv and hbar.value > REST_EPSILON


## Deck über dem Scroll (MarginContainer legt beide aufs selbe Rechteck).
func _deck_bauen() -> Control:
	var deck := Control.new()
	deck.name = "FadeDeck"
	deck.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_oben = _kante_bauen("FadeOben", Vector2(0.0, 1.0), Vector2.ZERO)
	_unten = _kante_bauen("FadeUnten", Vector2.ZERO, Vector2(0.0, 1.0))
	_links = _kante_bauen("FadeLinks", Vector2(1.0, 0.0), Vector2.ZERO)
	_rechts = _kante_bauen("FadeRechts", Vector2.ZERO, Vector2(1.0, 0.0))
	for kante: TextureRect in [_oben, _unten, _links, _rechts]:
		deck.add_child(kante)
	_kanten_layouten()
	return deck


## Eine Kante: Verlauf von durchsichtig (von) zur Wandfarbe (nach) — der
## Inhalt „löst sich“ Richtung Rand im Wallpaper-Creme auf.
func _kante_bauen(kanten_name: String, von: Vector2, nach: Vector2) -> TextureRect:
	var kante := TextureRect.new()
	kante.name = kanten_name
	kante.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kante.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	kante.stretch_mode = TextureRect.STRETCH_SCALE
	kante.visible = false
	var verlauf := Gradient.new()
	verlauf.set_color(0, Color(AcTokens.BG_CREAM, 0.0))
	verlauf.set_color(1, AcTokens.BG_CREAM)
	var textur := GradientTexture2D.new()
	textur.gradient = verlauf
	textur.fill_from = von
	textur.fill_to = nach
	kante.texture = textur
	return kante


func _kanten_layouten() -> void:
	if _oben == null:
		return
	_oben.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_oben.offset_bottom = _kante_px
	_unten.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_unten.offset_top = -_kante_px
	_links.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_links.offset_right = _kante_px
	_rechts.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_rechts.offset_left = -_kante_px
