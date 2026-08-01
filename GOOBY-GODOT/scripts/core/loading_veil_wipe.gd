extends Control
## W16/G2b — Signature-Wipe des LoadingVeils (Web loadingVeil.js V6/F2,
## Spez ladebild-alt.md §2.2): das GANZE Veil (Backdrop + Karte) wischt
## links→rechts herein/hinaus, die Oberkante der Wischkante eilt 15 %
## voraus (Slant), und entlang der Kante reiten 26 prozedural gezeichnete
## Blütenblatt-Stempel (deterministisches LCG-Feld, Seed 7, ~72 % rosa
## Blüten / 28 % grüne Blätter — petalField/petalStampPose 1:1 portiert).
##
## Umsetzungswahl (einfachste robuste Variante):
## - Die Wisch-Maske ist DIESES Control (das FROZEN `Root` des Veils):
##   während des Wipes zeichnet _draw das Web-clip-Polygon und
##   `clip_children = CLIP_CHILDREN_ONLY` schneidet ALLE Kinder (Backdrop,
##   Spinner, Karte) screen-space darauf zu — das Godot-Äquivalent des CSS
##   `clip-path` auf `.acui-veil`. Im Ruhezustand ist der Clip AUS (kein
##   Renderaufwand, keine Endwert-Nebenwirkung: modulate/visible gehören
##   weiter loading_veil.gd, der W1a-Contract bleibt unberührt).
## - Die Stempel leben als Geschwister ÜBER dem geclippten Root (Web:
##   `.acui-veil-petals`-Canvas, z-index +1) und werden rein prozedural
##   gezeichnet (kein Asset, kein --import).
##
## Varianten wie im Web (`veilWipeVariant`): Reduced Motion → "fade"
## (das Veil setzt instantan — bestehender Reduced-Motion-Vertrag),
## technischer Fallback "iris" (Kreis-Wipe circle(0%→141% at 50% 44%),
## Mathe-Vorlage boot_cover_screen.gd), Standard "petal".

## Web PETAL.WIPE_MS = 450 — bewusst 400 ms: der Ehrlichkeits-Wächter
## (test_loading_regeln) pinnt die Veil-Blenden auf ≤ 0.4 s.
const PETAL_S := 0.4
## Web VEIL.IRIS_IN_MS / IRIS_OUT_MS (Kreis-Wipe-Fallback).
const IRIS_REIN_S := 0.32
const IRIS_RAUS_S := 0.34
## Web PETAL.SLANT/COUNT/SIZE_MIN/SIZE_MAX + petalField-Defaults.
const SLANT := 0.15
const STEMPEL_ANZAHL := 26
const STEMPEL_SEED := 7
const GROESSE_MIN := 0.035
const GROESSE_MAX := 0.06
const ROSA_ANTEIL := 0.72
## Web-Iris: circle(… at 50% 44%).
const IRIS_ZENTRUM := Vector2(0.5, 0.44)

var _aktiv := false
var _rein := true
var _variante := "petal"
var _u := 0.0
var _tween: Tween
var _stempel: Stempel
var _feld_cache: Array[Dictionary] = []
var _clip_pausen: Array[CanvasItem] = []
var _clip_pausen_modi: Array[int] = []


## Varianten-Weiche (Web veilWipeVariant): Reduced Motion → fade, ohne
## Stempel-Zeichner → iris, sonst der Standard-Petal-Sweep.
static func wipe_variante(reduced_motion: bool, petal_ok := true) -> String:
	if reduced_motion:
		return "fade"
	if not petal_ok:
		return "iris"
	return "petal"


## Deterministisches Stempel-Feld (Web petalField, LCG 1664525/1013904223,
## Seed 7): gleiche Reise, gleiches Blütentreiben — testbar ohne Zufall.
static func petal_feld(anzahl := STEMPEL_ANZAHL, seed := STEMPEL_SEED) -> Array[Dictionary]:
	var rng: Array[int] = [maxi(1, seed & 0xFFFFFFFF)]
	var n := maxi(1, anzahl)
	var feld: Array[Dictionary] = []
	for i in n:
		(
			feld
			. append(
				{
					"lane": minf(1.0, (float(i) + _lcg(rng) * 0.9) / float(n)),
					"ahead": (_lcg(rng) - 0.35) * 0.16,
					"size": GROESSE_MIN + _lcg(rng) * (GROESSE_MAX - GROESSE_MIN),
					"spin": (_lcg(rng) - 0.5) * 9.0,
					"phase": _lcg(rng) * TAU,
					"sway": 0.02 + _lcg(rng) * 0.03,
					"sprite": 0 if _lcg(rng) < ROSA_ANTEIL else 1,
				}
			)
		)
	return feld


## Pose eines Stempels bei Wisch-Fortschritt u (Web petalStampPose):
## Position in Viewport-Anteilen, Drehung + Sinus-Schwanken, Alpha blendet
## an beiden Wipe-Enden. Die Kante läuft links→rechts, oben eilt SLANT vor.
static func stempel_pose(blatt: Dictionary, u: float) -> Dictionary:
	var k := clampf(u, 0.0, 1.0)
	var lane := float(blatt["lane"])
	var phase := float(blatt["phase"])
	var sway := float(blatt["sway"])
	var kante := -0.25 + k * 1.45 + SLANT * (1.0 - lane)
	return {
		"x": kante + float(blatt["ahead"]) + sin(k * TAU + phase) * sway,
		"y": lane + sin(k * PI * 3.0 + phase) * sway * 0.6,
		"rot": phase + k * float(blatt["spin"]),
		"alpha": clampf(minf(k, 1.0 - k) * 6.0, 0.0, 1.0),
	}


## Cover-Polygon (Web acui-veil-sweep-in): Oberkante 0→115 %, Unterkante
## 15 % dahinter. Linker Rand liegt bewusst VOR dem Schirm, damit das
## Polygon nie selbstschneidend wird (offscreen zeichnen ist harmlos).
static func clip_punkte_rein(u: float, groesse: Vector2) -> PackedVector2Array:
	var oben := u * (1.0 + SLANT) * groesse.x
	var unten := oben - SLANT * groesse.x
	var links := minf(0.0, unten) - 1.0
	return PackedVector2Array(
		[
			Vector2(links, 0.0),
			Vector2(oben, 0.0),
			Vector2(unten, groesse.y),
			Vector2(links, groesse.y),
		]
	)


## Reveal-Polygon (Web acui-veil-sweep-out): die linke Kante des noch
## deckenden Rests läuft 0→115 % (oben) bzw. −15 %→100 % (unten).
static func clip_punkte_raus(u: float, groesse: Vector2) -> PackedVector2Array:
	var oben := u * (1.0 + SLANT) * groesse.x
	var unten := oben - SLANT * groesse.x
	var rechts := maxf(groesse.x, oben) + 1.0
	return PackedVector2Array(
		[
			Vector2(oben, 0.0),
			Vector2(rechts, 0.0),
			Vector2(rechts, groesse.y),
			Vector2(unten, groesse.y),
		]
	)


static func _lcg(rng: Array[int]) -> float:
	rng[0] = (rng[0] * 1664525 + 1013904223) & 0xFFFFFFFF
	return float(rng[0]) / 4294967296.0


## Wischt das Veil herein (cover, ease-out wie Web); awaitbar.
## Für "iris" gilt die Web-Dauer 320 ms statt der übergebenen.
func wische_rein(variante: String, dauer := PETAL_S) -> void:
	await _wische(true, variante, IRIS_REIN_S if variante == "iris" else dauer)


## Wischt das Veil hinaus (reveal, ease-in wie Web); awaitbar.
func wische_raus(variante: String, dauer := PETAL_S) -> void:
	await _wische(false, variante, IRIS_RAUS_S if variante == "iris" else dauer)


## Verschachtelte Kind-Clips (z. B. der runde Karten-Clip), die während
## des Wipes AUSSETZEN müssen: clip_children-in-clip_children rendert der
## Godot-Canvas nicht (Backbuffer im Backbuffer) — die Kinder des inneren
## Clips verschwänden sonst für die Wipe-Dauer. Am Wipe-Ende wird der
## gemerkte Modus exakt restauriert (empirisch via xvfb verifiziert).
func setze_clip_pausen(knoten: Array[CanvasItem]) -> void:
	_clip_pausen = knoten


## Setzt den Ruhezustand: Clip aus, Stempel weg, innere Clips restauriert —
## Endwerte (modulate, visible) bleiben Sache von loading_veil.gd. Auch der
## Reduced-Motion-Pfad ruft das auf, damit kein Wipe-Rest hängen bleibt.
func sofort_fertig() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_aktiv = false
	clip_children = CanvasItem.CLIP_CHILDREN_DISABLED
	for i in _clip_pausen_modi.size():
		_clip_pausen[i].clip_children = _clip_pausen_modi[i] as CanvasItem.ClipChildrenMode
	_clip_pausen_modi.clear()
	if _stempel != null and is_instance_valid(_stempel):
		_stempel.visible = false
		_stempel.zeige([] as Array[Dictionary])
	queue_redraw()


func ist_aktiv() -> bool:
	return _aktiv


func _wische(rein: bool, variante: String, dauer: float) -> void:
	sofort_fertig()
	_rein = rein
	_variante = variante
	_aktiv = true
	# Screen-space-Maske scharf schalten, BEVOR der Aufrufer sichtbar
	# macht (alles synchron im selben Frame — kein Vollbild-Blitzer).
	clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	for knoten in _clip_pausen:
		_clip_pausen_modi.append(knoten.clip_children)
		knoten.clip_children = CanvasItem.CLIP_CHILDREN_DISABLED
	if variante == "petal":
		_hole_stempel().visible = true
	_setze_u(0.0)
	_tween = create_tween()
	_tween.tween_method(_setze_u, 0.0, 1.0, dauer).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT if rein else Tween.EASE_IN
	)
	await _tween.finished
	sofort_fertig()


func _setze_u(u: float) -> void:
	_u = u
	queue_redraw()
	if _stempel != null and is_instance_valid(_stempel) and _stempel.visible:
		_stempel.zeige(_posen(u))


func _draw() -> void:
	if not _aktiv:
		return
	var flaeche := _flaeche()
	if _variante == "iris":
		_zeichne_iris(flaeche)
		return
	if _rein and _u <= 0.0:
		return
	if not _rein and _u >= 1.0:
		return
	var punkte := clip_punkte_rein(_u, flaeche) if _rein else clip_punkte_raus(_u, flaeche)
	draw_colored_polygon(punkte, Color.WHITE)


## Kreis-Wipe-Fallback (Vorlage: boot_cover_screen.gd _oeffne_kreis —
## dort Shader-Iris, hier dieselbe Radius-Mathe als Maskenfläche).
func _zeichne_iris(flaeche: Vector2) -> void:
	var zentrum := Vector2(IRIS_ZENTRUM.x * flaeche.x, IRIS_ZENTRUM.y * flaeche.y)
	var max_r := 0.0
	for ecke: Vector2 in [Vector2.ZERO, Vector2(flaeche.x, 0.0), Vector2(0.0, flaeche.y), flaeche]:
		max_r = maxf(max_r, zentrum.distance_to(ecke))
	var radius := (_u if _rein else 1.0 - _u) * max_r
	if radius > 0.5:
		draw_circle(zentrum, radius, Color.WHITE)


## Stempel-Posen in Pixeln fürs Overlay (Web runPetalCanvas-Frame):
## Größe relativ zur kürzeren Viewport-Seite, unsichtbare überspringen.
func _posen(u: float) -> Array[Dictionary]:
	var flaeche := _flaeche()
	var einheit := minf(flaeche.x, flaeche.y)
	var posen: Array[Dictionary] = []
	for blatt in _feld():
		var pose := stempel_pose(blatt, u)
		var alpha := float(pose["alpha"])
		if alpha <= 0.0:
			continue
		(
			posen
			. append(
				{
					"pos": Vector2(float(pose["x"]) * flaeche.x, float(pose["y"]) * flaeche.y),
					"rot": float(pose["rot"]),
					"alpha": alpha,
					"groesse": float(blatt["size"]) * einheit,
					"sprite": int(blatt["sprite"]),
				}
			)
		)
	return posen


func _feld() -> Array[Dictionary]:
	if _feld_cache.is_empty():
		_feld_cache = petal_feld()
	return _feld_cache


func _flaeche() -> Vector2:
	if size.x > 0.0 and size.y > 0.0:
		return size
	var vp := get_viewport()
	return vp.get_visible_rect().size if vp != null else Vector2(1280, 720)


## Stempel-Overlay lazy anlegen: Geschwister NACH Root am CanvasLayer,
## damit es ÜBER dem geclippten Veil liegt (Web z-index +1) und selbst
## nicht mitgeclippt wird. Verschwindet mit dem Veil (visible-Kaskade).
func _hole_stempel() -> Stempel:
	if _stempel != null and is_instance_valid(_stempel):
		return _stempel
	_stempel = Stempel.new()
	_stempel.name = "WipeStempel"
	get_parent().add_child(_stempel)
	_stempel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return _stempel


class Stempel:
	extends Control
	## Prozedural gezeichnete Blüten-/Blatt-Stempel entlang der Wischkante
	## (Web paintPetalSprite/paintLeafSprite als Godot-_draw, kein Asset).
	## Der Radial-Verlauf der Blüte ist als 3 geschichtete Füllungen um das
	## Web-Verlaufszentrum angenähert, das Blatt nutzt echte Vertex-Farben
	## für den Linear-Verlauf; Konturen/Ader wie die Web-Strokes.

	## Web-Blüte: radial #FFE1EB → #FFB9D0 → #FF9EC0, Kontur
	## rgba(232,101,146,0.55); Verlaufszentrum (0.42,0.4) − Sprite-Mitte.
	const BLUETE_AUSSEN := Color("#FF9EC0")
	const BLUETE_MITTE := Color("#FFB9D0")
	const BLUETE_HELL := Color("#FFE1EB")
	const BLUETE_RAND := Color(0.909804, 0.396078, 0.572549, 0.55)
	const BLUETE_ZENTRUM := Vector2(-0.08, -0.1)
	## Web-Blatt: linear #C9E9AE → #8CC978, Ader rgba(106,152,86,0.7).
	const BLATT_HELL := Color("#C9E9AE")
	const BLATT_DUNKEL := Color("#8CC978")
	const BLATT_ADER := Color(0.415686, 0.596078, 0.337255, 0.7)

	var _posen: Array[Dictionary] = []
	var _bluete := PackedVector2Array()
	var _blatt := PackedVector2Array()
	var _blatt_farben := PackedColorArray()
	var _ader := PackedVector2Array()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false
		_bluete = _baue_bluete()
		_blatt = _baue_blatt()
		_blatt_farben = _baue_blatt_farben(_blatt)
		_ader = _baue_ader()

	func zeige(posen: Array[Dictionary]) -> void:
		_posen = posen
		queue_redraw()

	func _draw() -> void:
		for pose in _posen:
			var groesse := float(pose["groesse"])
			draw_set_transform(pose["pos"], float(pose["rot"]), Vector2.ONE * groesse)
			if int(pose["sprite"]) == 0:
				_zeichne_bluete(float(pose["alpha"]))
			else:
				_zeichne_blatt(float(pose["alpha"]))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	## Sakura-Tropfenform mit Kerbe (Web-Pfad), 3-Schicht-Radialverlauf.
	func _zeichne_bluete(alpha: float) -> void:
		draw_colored_polygon(_bluete, _mit_alpha(BLUETE_AUSSEN, alpha))
		draw_colored_polygon(_um_zentrum(_bluete, 0.74), _mit_alpha(BLUETE_MITTE, alpha))
		draw_colored_polygon(_um_zentrum(_bluete, 0.42), _mit_alpha(BLUETE_HELL, alpha))
		var kontur := _bluete.duplicate()
		kontur.append(_bluete[0])
		draw_polyline(kontur, _mit_alpha(BLUETE_RAND, alpha), 0.03)

	## Blattform mit Mittelader (Web-Pfad), Linearverlauf per Vertex-Farbe.
	func _zeichne_blatt(alpha: float) -> void:
		var farben := PackedColorArray()
		for farbe in _blatt_farben:
			farben.append(_mit_alpha(farbe, alpha))
		draw_polygon(_blatt, farben)
		draw_polyline(_ader, _mit_alpha(BLATT_ADER, alpha), 0.035)

	static func _mit_alpha(farbe: Color, alpha: float) -> Color:
		return Color(farbe.r, farbe.g, farbe.b, farbe.a * alpha)

	static func _um_zentrum(punkte: PackedVector2Array, faktor: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in punkte:
			out.append(BLUETE_ZENTRUM + (p - BLUETE_ZENTRUM) * faktor)
		return out

	## Web paintPetalSprite: moveTo(0.5,0.06) → Bezier-Bauch rechts →
	## Kerbe unten → Bezier-Bauch links; hier gesampelt + zentriert.
	static func _baue_bluete() -> PackedVector2Array:
		var punkte := PackedVector2Array()
		punkte.append(Vector2(0.5, 0.06))
		punkte.append_array(
			_cubic(
				Vector2(0.5, 0.06), Vector2(0.92, 0.2), Vector2(0.94, 0.66), Vector2(0.62, 0.9), 10
			)
		)
		punkte.append_array(_quad(Vector2(0.62, 0.9), Vector2(0.5, 0.8), Vector2(0.38, 0.9), 5))
		punkte.append_array(
			_cubic(
				Vector2(0.38, 0.9), Vector2(0.06, 0.66), Vector2(0.08, 0.2), Vector2(0.5, 0.06), 10
			)
		)
		punkte.remove_at(punkte.size() - 1)
		return _zentriert(punkte)

	## Web paintLeafSprite: zwei Quadratik-Bögen zur Blattspitze.
	static func _baue_blatt() -> PackedVector2Array:
		var punkte := PackedVector2Array()
		punkte.append(Vector2(0.5, 0.08))
		punkte.append_array(_quad(Vector2(0.5, 0.08), Vector2(0.94, 0.36), Vector2(0.5, 0.92), 10))
		punkte.append_array(_quad(Vector2(0.5, 0.92), Vector2(0.06, 0.36), Vector2(0.5, 0.08), 10))
		punkte.remove_at(punkte.size() - 1)
		return _zentriert(punkte)

	## Web createLinearGradient((0.2,0.2)→(0.8,0.85)) als Vertex-Farben.
	static func _baue_blatt_farben(punkte: PackedVector2Array) -> PackedColorArray:
		var von := Vector2(-0.3, -0.3)
		var richtung := Vector2(0.6, 0.65)
		var farben := PackedColorArray()
		for p in punkte:
			var k := clampf((p - von).dot(richtung) / richtung.length_squared(), 0.0, 1.0)
			farben.append(BLATT_HELL.lerp(BLATT_DUNKEL, k))
		return farben

	static func _baue_ader() -> PackedVector2Array:
		var punkte := PackedVector2Array()
		punkte.append(Vector2(0.5, 0.14))
		punkte.append_array(_quad(Vector2(0.5, 0.14), Vector2(0.56, 0.5), Vector2(0.5, 0.86), 8))
		return _zentriert(punkte)

	static func _cubic(
		p0: Vector2, c1: Vector2, c2: Vector2, p1: Vector2, schritte: int
	) -> PackedVector2Array:
		var punkte := PackedVector2Array()
		for i in range(1, schritte + 1):
			punkte.append(p0.bezier_interpolate(c1, c2, p1, float(i) / float(schritte)))
		return punkte

	static func _quad(p0: Vector2, c: Vector2, p1: Vector2, schritte: int) -> PackedVector2Array:
		var punkte := PackedVector2Array()
		for i in range(1, schritte + 1):
			var t := float(i) / float(schritte)
			punkte.append(p0.lerp(c, t).lerp(c.lerp(p1, t), t))
		return punkte

	static func _zentriert(punkte: PackedVector2Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in punkte:
			out.append(p - Vector2(0.5, 0.5))
		return out
