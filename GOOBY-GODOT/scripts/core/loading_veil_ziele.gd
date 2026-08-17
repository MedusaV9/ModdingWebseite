extends RefCounted
## LoadingVeilZiele — Ziel→Karten-Registry des Reise-Veils (W20 Top-10 #2,
## erledigt das seit W17 wartende G6-Paket „DLC-Ladebildschirme“).
##
## SO FUNKTIONIERT DIE ZIEL-WAHL: Der SceneRouter setzt bei goto() sein
## _current_target und feuert travel_started(target, travel_type); das
## LoadingVeil (Kind des Routers) hört darauf und ruft prepare_for_travel().
## Dort gewinnt zuerst der Minigame-Travel-Hint („game“-Karte), dann die
## lange Reise (Vollbild-RanchLoadingScreen), sonst bestimmt DIESE Registry
## die Variante der kleinen Reise-Karte. Vor W20 kannte die Wahl nur
## ikea/city* („trip“) — JEDES andere Ziel (auch die DLC-Bibliothek) lud
## unter der „Trautes Heim“-Karte (verifizierter Playtest-Fund). Jetzt:
## exakte Ziele zuerst, dann Präfix-Familien in Prioritätsreihenfolge
## (spezifisch vor generisch), unbekannte Ziele bekommen den ehrlichen
## „Unterwegs…“-Fallback statt der falschen Heim-Karte.
##
## Kein class_name (Muster loading_veil_wipe.gd): Zugriff via preload —
## so braucht eine frische Kopie keinen --import-/Class-Cache-Lauf.
##
## Texte: strings/<locale>/veil.json (veil.<modus>.titel/bereit/tips —
## Domain-Owner TEXT, s. strings/OWNERSHIP.md, Eintrag W20 VEIL-ZIELE).
## Cover: home/trip behalten das Heim-Artwork (Web-Parität, gepinnt von
## test_ui_veil.gd) — die neuen Familien malen sich EINMAL je Sitzung ein
## deterministisches Stimmungs-Bild im bestehenden prozeduralen Stil
## (Verlaufs-/Formen-Malerei wie LoadingVeilKarte._fallback_textur; wo
## Streuung nötig ist, der feste LCG aus loading_veil_wipe.petal_feld —
## kein OS-Zufall, Tests sehen immer dieselben Pixel).

## Exakte Ziele → Karten-Variante. `arcade` (der Screen selbst) bleibt
## BEWUSST auf der Home-Karte — W16-Web-Regel „Sonstige Screens = home“,
## gepinnt in test_ui_veil.gd; die Arcade-Karte greift nur für die
## Minigame-Durchgangsstationen OHNE Travel-Hint (mit Hint gewinnt „game“).
const EXAKTE_ZIELE := {
	"ikea": "trip",
	"arcade": "home",
	"mg_pregame": "arcade",
	"mg_host": "arcade",
	"mcgooby_schicht": "dlc",
	"city/ort/flughafen": "reise",
	"city/ort/raumstation": "reise",
}

## Präfix-Familien [Präfix, Variante] — Reihenfolge = Priorität, spezifisch
## vor generisch (city/urlaub sticht city). Match wie die alte Web-Regel:
## Ziel == Präfix ODER Ziel beginnt mit „Präfix/“.
const FAMILIEN_PRAEFIXE: Array[Array] = [
	["city/urlaub", "reise"],
	["city", "trip"],
	["home", "home"],
	["ranch", "ranch"],
	["dlc", "dlc"],
]

## Ehrlicher Fallback für unbekannte Ziele (neutraler „Unterwegs…“-Look).
const FALLBACK_MODUS := "unterwegs"

## Diese Modi behalten das Heim-Artwork der Karte (Web-Parität; „game“
## bekommt sein Cover aus dem Travel-Hint) — kein prozedurales Cover.
const HEIM_COVER_MODI: Array[String] = ["home", "trip", "game"]

## Malfläche der Stimmungs-Cover: 2× die 320×152-Cover-Zone der Karte.
const COVER_BREITE := 640
const COVER_HOEHE := 304

## Einmal gemalte Cover je Variante (das Veil läuft bei JEDEM Routenwechsel
## — nie pro Reise neu malen).
static var _cover_cache: Dictionary = {}


## Karten-Variante fürs Router-Ziel: exakt → Familie → Fallback.
static func modus_fuer_ziel(target: StringName) -> String:
	var ziel := String(target)
	if EXAKTE_ZIELE.has(ziel):
		return EXAKTE_ZIELE[ziel]
	for eintrag: Array in FAMILIEN_PRAEFIXE:
		var praefix: String = eintrag[0]
		if ziel == praefix or ziel.begins_with(praefix + "/"):
			return eintrag[1]
	return FALLBACK_MODUS


## Stimmungs-Cover einer Variante — null für home/trip/game (Aufrufer
## nimmt dann das Heim-Artwork bzw. das Hint-Cover, Web-Verhalten).
static func cover_fuer_modus(modus: String) -> Texture2D:
	if HEIM_COVER_MODI.has(modus):
		return null
	if not _cover_cache.has(modus):
		_cover_cache[modus] = _male_cover(modus)
	return _cover_cache[modus]


## ── Prozedurale Stimmungs-Cover ─────────────────────────────────────────


static func _male_cover(modus: String) -> Texture2D:
	var bild := Image.create(COVER_BREITE, COVER_HOEHE, false, Image.FORMAT_RGBA8)
	match modus:
		"dlc":
			_male_bibliothek(bild)
		"ranch":
			_male_ranch(bild)
		"arcade":
			_male_arcade(bild)
		"reise":
			_male_reise(bild)
		_:
			_male_unterwegs(bild)
	return ImageTexture.create_from_image(bild)


## DLC-Bibliothek: warmes Papier, zwei Holzborde, gedeckt-bunte Buchrücken
## mit Lichtkante (Breiten/Höhen deterministisch aus dem festen LCG).
static func _male_bibliothek(bild: Image) -> void:
	_verlauf(bild, Color("#F9EFDF"), Color("#EAD3B1"))
	var rng: Array[int] = [23]
	var buch_farben: Array[Color] = [
		Color("#4FA8A0"),
		Color("#E78FB3"),
		Color("#E0B04A"),
		Color("#8FD06C"),
		Color("#6F9BD6"),
		Color("#C98D5F"),
	]
	for bord_y: int in [150, 268]:
		var x := 22
		while x < bild.get_width() - 46:
			var breite := 24 + int(_lcg(rng) * 22.0)
			var hoehe := 72 + int(_lcg(rng) * 32.0)
			var farbe: Color = buch_farben[int(_lcg(rng) * 6.0) % buch_farben.size()]
			bild.fill_rect(Rect2i(x, bord_y - hoehe, breite, hoehe), farbe)
			var kante := farbe.lerp(Color.WHITE, 0.35)
			bild.fill_rect(Rect2i(x + 3, bord_y - hoehe + 5, 3, hoehe - 10), kante)
			x += breite + 5 + int(_lcg(rng) * 6.0)
		bild.fill_rect(Rect2i(0, bord_y, bild.get_width(), 14), Color("#B98A5C"))
		bild.fill_rect(Rect2i(0, bord_y + 14, bild.get_width(), 5), Color("#9A6E44"))


## Ranch: warmer Himmel, Sonne, sanfte Hügel, Wiese, Koppelzaun.
static func _male_ranch(bild: Image) -> void:
	_verlauf(bild, Color("#CDE8F7"), Color("#FDF7EC"))
	_kreis(bild, Vector2(520, 74), 44.0, Color("#F2C463"))
	_kreis(bild, Vector2(520, 74), 33.0, Color("#F7DE9C"))
	_kreis(bild, Vector2(140, 330), 150.0, Color("#9CCF7C"))
	_kreis(bild, Vector2(440, 360), 190.0, Color("#8CC46B"))
	bild.fill_rect(Rect2i(0, 238, bild.get_width(), 66), Color("#7FBF62"))
	bild.fill_rect(Rect2i(0, 232, bild.get_width(), 8), Color("#C99A6C"))
	for zaun_x: int in [70, 190, 310, 430, 550]:
		bild.fill_rect(Rect2i(zaun_x, 214, 10, 60), Color("#B98A5C"))


## Arcade: Abenddämmer-Violett mit glimmenden Pixel-Quadraten + Boden-Glow.
static func _male_arcade(bild: Image) -> void:
	_verlauf(bild, Color("#6B5AA0"), Color("#3A3158"))
	var rng: Array[int] = [7]
	var neon: Array[Color] = [
		Color("#FF7BA9"),
		Color("#59C9B9"),
		Color("#E0B04A"),
		Color("#F3EFFA"),
	]
	for i in 26:
		var x := int(_lcg(rng) * 616.0)
		var y := int(_lcg(rng) * 236.0)
		var seite := 6 + int(_lcg(rng) * 12.0)
		bild.fill_rect(Rect2i(x, y, seite, seite), neon[i % neon.size()])
	bild.fill_rect(Rect2i(0, 272, bild.get_width(), 32), Color("#4A3E70"))
	bild.fill_rect(Rect2i(0, 268, bild.get_width(), 4), Color("#9B7FD6"))


## Flughafen/Reise: Himmelblau, Schäfchenwolken, Startbahn mit Mittellinie.
static func _male_reise(bild: Image) -> void:
	_verlauf(bild, Color("#A9D3F2"), Color("#EFF6FB"))
	for wolke: Vector2 in [Vector2(120, 84), Vector2(360, 52), Vector2(540, 120)]:
		_kreis(bild, wolke + Vector2(-26, 8), 20.0, Color.WHITE)
		_kreis(bild, wolke, 28.0, Color.WHITE)
		_kreis(bild, wolke + Vector2(30, 10), 22.0, Color.WHITE)
	bild.fill_rect(Rect2i(0, 232, bild.get_width(), 72), Color("#9AA4B0"))
	bild.fill_rect(Rect2i(0, 232, bild.get_width(), 6), Color("#7C8794"))
	var x := 16
	while x < bild.get_width():
		bild.fill_rect(Rect2i(x, 264, 44, 8), Color("#F4F7FA"))
		x += 88


## Ehrlicher Fallback „Unterwegs…“: neutrales Creme + Trittstein-Pfad,
## der in die Ferne kleiner wird (kein falsches Heim-Artwork mehr).
static func _male_unterwegs(bild: Image) -> void:
	_verlauf(bild, Color("#FFF6EC"), Color("#EEDDC4"))
	var punkte: Array[Array] = [
		[Vector2(96, 268), 26.0],
		[Vector2(210, 236), 22.0],
		[Vector2(310, 206), 18.0],
		[Vector2(396, 178), 15.0],
		[Vector2(468, 152), 12.0],
		[Vector2(526, 130), 9.0],
	]
	for punkt: Array in punkte:
		_kreis(bild, punkt[0], float(punkt[1]) + 3.0, Color("#E4CFAF"))
		_kreis(bild, punkt[0], punkt[1], Color("#D9C4A8"))


## ── Mal-Helfer ──────────────────────────────────────────────────────────


## Vertikaler Farbverlauf über die volle Fläche (Basis jeder Stimmung).
static func _verlauf(bild: Image, oben: Color, unten: Color) -> void:
	var hoehe := bild.get_height()
	for y in hoehe:
		var farbe := oben.lerp(unten, float(y) / float(hoehe - 1))
		bild.fill_rect(Rect2i(0, y, bild.get_width(), 1), farbe)


## Gefüllter Kreis mit weicher 1-px-Kante (blendet über den Untergrund).
static func _kreis(bild: Image, mitte: Vector2, radius: float, farbe: Color) -> void:
	var x0 := maxi(0, int(mitte.x - radius) - 1)
	var x1 := mini(bild.get_width() - 1, int(mitte.x + radius) + 1)
	var y0 := maxi(0, int(mitte.y - radius) - 1)
	var y1 := mini(bild.get_height() - 1, int(mitte.y + radius) + 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var abstand := Vector2(x + 0.5, y + 0.5).distance_to(mitte)
			var deckung := clampf(radius - abstand + 0.5, 0.0, 1.0)
			if deckung <= 0.0:
				continue
			bild.set_pixel(x, y, bild.get_pixel(x, y).lerp(farbe, deckung))


## Fester LCG (identisches Muster loading_veil_wipe._lcg): deterministische
## Streuung ohne OS-Zufall — Injektions-Regel bleibt gewahrt.
static func _lcg(rng: Array[int]) -> float:
	rng[0] = (rng[0] * 1664525 + 1013904223) & 0xFFFFFFFF
	return float(rng[0]) / 4294967296.0
