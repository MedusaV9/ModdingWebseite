class_name IkeaSchaufenster
extends Control
## G7-P55 „Läden lebendig“ — lebendiger Vitrinen-Hintergrund für den
## IKEA-Katalog-Screen: eine verschwommene Ausstellungs-Szene (weiche
## Möbel-Blobs vor Wand + Boden) mit wandelnden Gooby-Silhouetten. IKEA
## ist bewusst NUR ein Screen (Stadt-Gebäude ist Deko) — der Hintergrund
## gibt dem Katalog das Gefühl, mitten im Möbelhaus zu stehen.
##
## Billig: EIN Control-`_draw` (Kreise/Rechtecke, „Blur“ = konzentrische
## Alpha-Schichten), kein Shader, kein Viewport. Liegt HINTER dem
## transparenten FurnitureShowcase-Viewport in derselben Karte.
## Reduced Motion: Silhouetten stehen still (kein _process).
## Deterministisch über den Tages-Seed (Test-Hook `seed_override`).

## Anzahl wandelnder Silhouetten + verschwommener Möbel-Blobs.
const SILHOUETTEN := 3
const MOEBEL_BLOBS := 4
## Wander-Tempo in Kanvas-Breiten pro Sekunde (gemütliches Schlendern).
const TEMPO_MIN := 0.010
const TEMPO_MAX := 0.022
## Sichtbarkeits-Deckel: alles bleibt dezent HINTER dem Möbel-Star.
const SILHOUETTE_ALPHA := 0.14
const BLOB_ALPHA := 0.16
## Möbel-Blob-Pastelltöne (gedeckt, wie durch Milchglas).
const BLOB_FARBEN: Array[String] = ["#8FB6D9", "#A9CDA1", "#E3C68A", "#D9A5B5"]

## Test-Hooks: fester Seed, Reduced-Motion erzwingen, Zeit von Hand füttern.
var seed_override := -1
var reduced_override := -1
var auto_zeit := true

var _zeit := 0.0
var _silhouetten: Array[Dictionary] = []
var _blobs: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	_plane()
	set_process(not _reduziert())
	queue_redraw()


func _process(delta: float) -> void:
	if auto_zeit:
		advance_zeit(delta)


## Zeit hereinreichen (auch von Tests): bewegt die Silhouetten.
func advance_zeit(delta: float) -> void:
	if _reduziert():
		return
	_zeit += delta
	queue_redraw()


## ------------------------------------------------------------- Test-API


func silhouetten_anzahl() -> int:
	return _silhouetten.size()


## Horizontale Position (0..1) einer Silhouette zur aktuellen Zeit.
func silhouette_frac(index: int) -> float:
	if index < 0 or index >= _silhouetten.size():
		return 0.0
	return _frac_bei(_silhouetten[index], _zeit)


## ---------------------------------------------------------------- intern


## Deterministischer Plan: Blobs (Position/Größe/Farbe) + Silhouetten
## (Startphase, Tempo, Größe, Bob-Phase) aus dem Tages-Seed.
func _plane() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_override if seed_override >= 0 else _tages_seed()
	_blobs.clear()
	for i in MOEBEL_BLOBS:
		(
			_blobs
			. append(
				{
					"x": 0.08 + (float(i) + rng.randf() * 0.6) / float(MOEBEL_BLOBS),
					"breite": rng.randf_range(0.10, 0.20),
					"hoehe": rng.randf_range(0.22, 0.40),
					"farbe": Color(BLOB_FARBEN[i % BLOB_FARBEN.size()]),
				}
			)
		)
	_silhouetten.clear()
	for i in SILHOUETTEN:
		(
			_silhouetten
			. append(
				{
					"phase": rng.randf(),
					"tempo": rng.randf_range(TEMPO_MIN, TEMPO_MAX),
					"groesse": rng.randf_range(0.16, 0.24),
					"bob": rng.randf() * TAU,
					"tiefe": 0.55 + 0.4 * float(i) / maxf(1.0, float(SILHOUETTEN - 1)),
				}
			)
		)


func _tages_seed() -> int:
	var d := Time.get_date_dict_from_system()
	var tag := "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]
	return int(hash("%s|ikea_schaufenster" % tag)) & 0x7FFFFFFF


func _reduziert() -> bool:
	if reduced_override >= 0:
		return reduced_override == 1
	return ThemeService.is_reduced_motion(self)


## Ping-Pong über die Breite (0.06..0.94), Startphase versetzt.
func _frac_bei(plan: Dictionary, sekunden: float) -> float:
	var lauf := fposmod(float(plan["phase"]) + sekunden * float(plan["tempo"]), 2.0)
	var hin := lauf if lauf < 1.0 else 2.0 - lauf
	return 0.06 + 0.88 * hin


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 2.0 or h <= 2.0:
		return
	# Wand + Boden: warmes Ausstellungs-Licht, unten ein dunklerer Streifen.
	draw_rect(Rect2(0.0, 0.0, w, h), Color(0.98, 0.95, 0.88, 0.45))
	draw_rect(Rect2(0.0, h * 0.78, w, h * 0.22), Color(0.82, 0.72, 0.58, 0.35))
	for blob in _blobs:
		_zeichne_moebel_blob(blob, w, h)
	for plan in _silhouetten:
		_zeichne_silhouette(plan, w, h)


## „Verschwommenes“ Ausstellungs-Möbel: drei konzentrische Alpha-Schichten
## um dieselbe Grundfläche — liest als Blur, kostet drei Rechtecke.
func _zeichne_moebel_blob(blob: Dictionary, w: float, h: float) -> void:
	var breite := float(blob["breite"]) * w
	var hoehe := float(blob["hoehe"]) * h
	var x := float(blob["x"]) * w - breite / 2.0
	var y := h * 0.78 - hoehe
	var farbe: Color = blob["farbe"]
	for schicht in 3:
		var rand := float(schicht) * breite * 0.08
		var alpha := BLOB_ALPHA * (1.0 - float(schicht) * 0.3)
		draw_rect(
			Rect2(x - rand, y - rand, breite + rand * 2.0, hoehe + rand),
			Color(farbe.r, farbe.g, farbe.b, alpha)
		)


## Gooby-Silhouette: Körper-Ellipse + Kopf + zwei lange Ohren, halb
## transparent in Theme-Tinte — wandert per Ping-Pong, wippt leicht.
func _zeichne_silhouette(plan: Dictionary, w: float, h: float) -> void:
	var frac := _frac_bei(plan, _zeit)
	var groesse := float(plan["groesse"]) * h * float(plan["tiefe"])
	var bob := sin(_zeit * 1.6 + float(plan["bob"])) * groesse * 0.04
	if _reduziert():
		bob = 0.0
	var fuss := h * 0.78 + (float(plan["tiefe"]) - 0.55) * h * 0.06
	var mitte := Vector2(frac * w, fuss - groesse * 0.5 + bob)
	var tinte := AcTokens.INK
	var alpha := SILHOUETTE_ALPHA * float(plan["tiefe"])
	var farbe := Color(tinte.r, tinte.g, tinte.b, alpha)
	# Körper (Ellipse via skaliertem Kreis).
	draw_set_transform(mitte, 0.0, Vector2(0.72, 1.0))
	draw_circle(Vector2.ZERO, groesse * 0.5, farbe)
	# Kopf.
	var kopf := mitte + Vector2(0.0, -groesse * 0.62)
	draw_set_transform(kopf, 0.0, Vector2.ONE)
	draw_circle(Vector2.ZERO, groesse * 0.30, farbe)
	# Ohren: zwei schmale, leicht gekippte Ellipsen.
	for seite: float in [-1.0, 1.0]:
		var ohr := kopf + Vector2(seite * groesse * 0.16, -groesse * 0.42)
		draw_set_transform(ohr, seite * 0.28, Vector2(0.30, 1.0))
		draw_circle(Vector2.ZERO, groesse * 0.30, farbe)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
