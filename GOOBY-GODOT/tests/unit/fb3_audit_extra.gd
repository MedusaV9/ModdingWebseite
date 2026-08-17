extends RefCounted
## FB3-Audit-Erweiterungen (W20/P4, UI-Rework) — KEIN eigener Lauf:
## fb3_ui_audit.gd preloadet diese statischen Checks und ruft sie pro
## Station/Format auf (immer MIT Geräte-Metriken, das Audit setzt
## screen_scale_override + insets_override vorab). Drei neue Dauer-Wachen:
##
##   falz_befunde — Unter-der-Falz-Wache: jedes interaktive Element muss
##     ERREICHBAR sein — großteils sichtbar ODER in einem ScrollContainer
##     (scrollbar). Von clip_contents-Ahnen weggeschnittene Knöpfe OHNE
##     Scroller sind tote UI; die bestehenden offscreen-/safe_area-Checks
##     übersprangen genau diesen Fall (effektives Rect leer → kein Befund).
##
##   stretch_befunde — Aspekt-/Stretch-Wache: (1) Vollbreite-BALKEN
##     (>85 % Canvas-Breite, aber kein Vollflächen-Backdrop) ohne Bezug zur
##     markierten Inhaltsspalte = gestreckte Web-Leiste (Befund-Familie E);
##     (2) COVER-Verzerrung: TextureRect mit STRETCH_SCALE, dessen
##     Anzeige-Aspekt vom Quell-Aspekt abweicht (plattgedrückte Artworks).
##
##   leerflaeche_prozent — Leerflächen-Metrik (REPORT, KEIN Gate): Anteil
##     der Safe-Fläche ohne zeichnende UI (grobes 24×12-Raster;
##     Vollflächen-Kulissen/Scrims ≥80 % Safe zählen nicht als Inhalt).
##     Home-/Raum-Stationen haben die 3D-Kulisse dahinter — Werte dort nur
##     RELATIV deuten (hoher Wert ist da erwartbar und ok).
##
## Befund-Format: {check, node, detail} — das Audit hängt Format/Screen an.

## Balken-Definition: breiter als 85 % Canvas, aber flacher als 45 % (sonst
## Backdrop/Scrim) und dicker als Haarlinie.
const BALKEN_BREITE_ANTEIL := 0.85
const BALKEN_HOEHE_ANTEIL := 0.45
const BALKEN_MIN_PX := 8.0
## Relative Aspekt-Abweichung, ab der ein Cover als verzerrt gilt.
const COVER_TOLERANZ := 0.12
## Ab diesem Safe-Flächen-Anteil ist ein Element Kulisse, kein Inhalt.
const KULISSE_ANTEIL := 0.8
## Sichtbarkeits-Anteil, ab dem ein Element als erreichbar gilt.
const FALZ_SICHT_ANTEIL := 0.5
const RASTER_X := 24
const RASTER_Y := 12


## Unter-der-Falz-Wache über die schon eingesammelten Bedienelemente.
static func falz_befunde(controls: Array[Control], canvas: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var canvas_rect := Rect2(Vector2.ZERO, canvas)
	for ctl in controls:
		var roh := ctl.get_global_rect()
		if roh.size.x <= 0.0 or roh.size.y <= 0.0:
			continue
		var sichtbar := _eff_rect(ctl).intersection(canvas_rect)
		var anteil := _flaeche(sichtbar) / maxf(_flaeche(roh), 1.0)
		if anteil >= FALZ_SICHT_ANTEIL or _hat_scroll_ahn(ctl):
			continue
		(
			out
			. append(
				{
					"check": "falz",
					"node": _beschreibe(ctl),
					"detail":
					(
						"unerreichbar: nur %.0f %% sichtbar und KEIN Scroller (%s)"
						% [anteil * 100.0, roh]
					),
				}
			)
		)
	return out


## Aspekt-/Stretch-Wache über alle zeichnenden Controls des Haupt-Viewports.
## `spalten` = markierte Inhaltsspalten, `im_overlay` = Audit-Rauschfilter
## (HUD/Toast/Blase/PanelSheet — bewusste Rand-Ebenen).
static func stretch_befunde(
	wurzel: Node, canvas: Vector2, spalten: Array[Control], im_overlay: Callable
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ctl in _zeichnende(wurzel):
		if bool(im_overlay.call(ctl)):
			continue
		var rect := ctl.get_global_rect()
		if _ist_balken(ctl, rect, canvas) and not _an_spalte(ctl, spalten):
			(
				out
				. append(
					{
						"check": "stretch",
						"node": _beschreibe(ctl),
						"detail":
						(
							"Vollbreite-Balken %.0f %% Canvas-Breite ohne Inhaltsspalte (%s)"
							% [rect.size.x / canvas.x * 100.0, rect.size]
						),
					}
				)
			)
		var abweichung := _cover_abweichung(ctl, rect)
		if abweichung > COVER_TOLERANZ:
			(
				out
				. append(
					{
						"check": "stretch",
						"node": _beschreibe(ctl),
						"detail":
						(
							"Cover verzerrt: Anzeige-Aspekt weicht %.0f %% vom Quell-Aspekt ab (%s)"
							% [abweichung * 100.0, rect.size]
						),
					}
				)
			)
	return out


## Leerflächen-Metrik (Report): Prozent der Safe-Fläche OHNE zeichnende UI.
static func leerflaeche_prozent(wurzel: Node, safe: Rect2) -> float:
	var zelle := Vector2(safe.size.x / float(RASTER_X), safe.size.y / float(RASTER_Y))
	if zelle.x <= 0.0 or zelle.y <= 0.0:
		return 0.0
	var belegt: Dictionary = {}
	for ctl in _zeichnende(wurzel):
		var rect := _eff_rect(ctl).intersection(safe)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		if _flaeche(rect) >= _flaeche(safe) * KULISSE_ANTEIL:
			continue
		var x0 := maxi(int((rect.position.x - safe.position.x) / zelle.x), 0)
		var x1 := mini(int(ceilf((rect.end.x - safe.position.x) / zelle.x)), RASTER_X)
		var y0 := maxi(int((rect.position.y - safe.position.y) / zelle.y), 0)
		var y1 := mini(int(ceilf((rect.end.y - safe.position.y) / zelle.y)), RASTER_Y)
		for gx in range(x0, x1):
			for gy in range(y0, y1):
				belegt[gx * RASTER_Y + gy] = true
	return 100.0 * (1.0 - float(belegt.size()) / float(RASTER_X * RASTER_Y))


## ---- interne Helfer -------------------------------------------------------


## Balken: sehr breit, aber weder Haarlinie noch Vollflächen-Backdrop.
## Verlaufs-Kanten (ScrollFade & Co.) sind BEWUSSTE Vollbreite-Fades,
## keine gestreckten Web-Leisten — sie zählen nicht (P2-Rauschen Bau-Dock).
static func _ist_balken(ctl: Control, rect: Rect2, canvas: Vector2) -> bool:
	var zeichnet_flaeche := (
		ctl is Panel
		or ctl is PanelContainer
		or ctl is ColorRect
		or ctl is NinePatchRect
		or ctl is TextureRect
	)
	return (
		zeichnet_flaeche
		and not _ist_verlauf(ctl)
		and rect.size.x > canvas.x * BALKEN_BREITE_ANTEIL
		and rect.size.y >= BALKEN_MIN_PX
		and rect.size.y < canvas.y * BALKEN_HOEHE_ANTEIL
	)


## Relative Abweichung Anzeige-Aspekt vs. Quell-Aspekt (nur STRETCH_SCALE
## verzerrt; alle KEEP_*-Modi halten den Aspekt per Definition).
## Verlaufs-Texturen (_ist_verlauf) und Mini-Quellen < 32 px (Haarlinien/
## Kachel-Streifen) STRECKEN per Design und sind kein Cover — sonst wäre
## jede Fade-Kante ein Dauer-Befund.
static func _cover_abweichung(ctl: Control, rect: Rect2) -> float:
	if not (ctl is TextureRect):
		return 0.0
	var tex := (ctl as TextureRect).texture
	if tex == null or (ctl as TextureRect).stretch_mode != TextureRect.STRETCH_SCALE:
		return 0.0
	if _ist_verlauf(ctl):
		return 0.0
	if tex.get_width() < 32 or tex.get_height() < 32:
		return 0.0
	if rect.size.x < 16.0 or rect.size.y < 16.0:
		return 0.0
	var quell := float(tex.get_width()) / float(tex.get_height())
	var anzeige := rect.size.x / rect.size.y
	return absf(anzeige - quell) / maxf(quell, 0.01)


## Verlaufs-Texturen (GradientTexture — ScrollFade-Kanten, Schimmer,
## Scroll-Fades): bewusste Fades, die per Design volle Breite/Höhe ziehen.
static func _ist_verlauf(ctl: Control) -> bool:
	if not (ctl is TextureRect):
		return false
	var tex := (ctl as TextureRect).texture
	return tex is GradientTexture1D or tex is GradientTexture2D


## Gehört das Element zu einer markierten Inhaltsspalte (selbst, Ahn oder
## Nachfahre — ein Balken, der die Spalte TRÄGT, ist kein Streck-Befund)?
static func _an_spalte(ctl: Control, spalten: Array[Control]) -> bool:
	for spalte in spalten:
		if spalte == ctl or spalte.is_ancestor_of(ctl) or ctl.is_ancestor_of(spalte):
			return true
	return false


## Sichtbare zeichnende Controls des HAUPT-Viewports (SubViewport-Inhalte
## gehören den Spielen; reine Layout-Container zeichnen nichts).
static func _zeichnende(wurzel: Node) -> Array[Control]:
	var out: Array[Control] = []
	var stack: Array[Node] = [wurzel]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is SubViewport and node != wurzel:
			continue
		stack.append_array(node.get_children())
		if not (node is Control) or not (node as Control).is_visible_in_tree():
			continue
		var zeichnet := (
			node is BaseButton
			or node is Label
			or node is RichTextLabel
			or node is TextureRect
			or node is ColorRect
			or node is Panel
			or node is PanelContainer
			or node is NinePatchRect
			or node is LineEdit
			or node is TextEdit
			or node is Range
			or node is ItemList
			or node is Tree
		)
		if zeichnet:
			out.append(node as Control)
	return out


static func _hat_scroll_ahn(ctl: Control) -> bool:
	var node: Node = ctl.get_parent()
	while node != null:
		if node is ScrollContainer:
			return true
		node = node.get_parent()
	return false


## Rect nach Clipping durch Ahnen (Spiegel von fb3_ui_audit._effective_rect).
static func _eff_rect(ctl: Control) -> Rect2:
	var rect := ctl.get_global_rect()
	var node: Node = ctl.get_parent()
	while node != null and node is Control:
		var parent := node as Control
		if parent.clip_contents or parent is ScrollContainer:
			rect = rect.intersection(parent.get_global_rect())
			if rect.size.x <= 0.0 or rect.size.y <= 0.0:
				return Rect2()
		node = parent.get_parent()
	return rect


static func _flaeche(rect: Rect2) -> float:
	return maxf(rect.size.x, 0.0) * maxf(rect.size.y, 0.0)


static func _beschreibe(node: Node) -> String:
	var label := node.name
	if node is Button and not (node as Button).text.is_empty():
		label = "%s(%s)" % [node.name, (node as Button).text.left(18)]
	return String(label)
