class_name BootPhasen
extends RefCounted
## W14/LOADING — PURE Regeln des Boot-Cover-Screens (kein Node, keine
## Autoload-Abhängigkeit; tests/unit/test_w14_loading.gd treibt sie direkt).
##
## Drei Aufgaben:
## 1. Phasen→Prozent-Mapping des ECHTEN Boot-Fortschritts. Die Phasen spiegeln,
##    was der Boot wirklich nacheinander tut (main.gd meldet sie): Packs
##    mounten (PackLoader-Autoload), Spielstand laden (GameState-Autoload),
##    threaded Load der Zuhause-Szene (echter ResourceLoader-Sub-Fortschritt),
##    Einrichten (HomeEntry instanzieren: Routen + HUD) und die erste
##    Router-Reise ins Wohnzimmer. NICHTS wird gefaket — jede Meldung folgt
##    einem realen Ereignis, der Balken zeigt nie mehr an als passiert ist.
## 2. Deterministische Spruch-Rotation (LCG-Shuffle wie das Web-petalField):
##    gleicher Seed → gleiche Reihenfolge, jeder Spruch einmal pro Runde,
##    nie derselbe zweimal hintereinander (Runden rotieren um 1).
## 3. Cover-Crop-Mathe des Querformat-Artworks: Landscape füllt, Hochkant
##    croppt SANFT mit Fokus auf Gooby; nur wenn der Zoom-Deckel greift
##    (extreme Formate), bleiben Ränder — die füllt die Randfarbe AUS dem
##    Bild statt schwarzer Balken (randfarbe()).

## ECHTE Boot-Phasen in Reihenfolge, je mit End-Prozent (0..1).
## "packs"/"save" laufen als Autoloads VOR dem ersten Frame — main.gd prüft
## nur ihre Ergebnisse und meldet sie als abgeschlossen (ehrlich: sie SIND es).
## W16/G4 (bootperf §4.3): Weil diese beiden Phasen nie live beobachtbar
## sind, sprang der Balken früher sofort auf 22 % — die Gewichte sind jetzt
## klein (je 4 %), damit die Balkenstrecke der real beobachtbaren Arbeit
## gehört: "welt" (gewichteter threaded Warmup-Fortschritt, E3) und
## "zuhause" (Router-Meilensteine). Nur die `bis`-Werte wurden umverteilt;
## IDs, Reihenfolge, Monotonie und Ende 1.0 sind unverändert (Test-Contract).
const PHASEN: Array[Dictionary] = [
	{"id": "packs", "bis": 0.04},
	{"id": "save", "bis": 0.08},
	{"id": "welt", "bis": 0.60},
	{"id": "einrichten", "bis": 0.68},
	{"id": "zuhause", "bis": 1.0},
]

## Gooby sitzt im Boot-Artwork mittig, Gesicht knapp über der Bildmitte —
## Fokuspunkt des Hochkant-Crops UND Zentrum des Kreis-Wipes.
const FOKUS := Vector2(0.5, 0.52)
## „Sanfter“ Crop: maximaler Zoom über der Fit-Skalierung. 9:16-Hochkant auf
## dem 16:9-Artwork braucht ~3.16× — der Deckel greift erst bei extremeren
## Formaten (dann füllt die Bild-Randfarbe statt schwarzer Balken).
const MAX_ZOOM_UEBER_FIT := 3.4
## Fallback der Randfarben-Messung: gemittelte Randpixel des Boot-Artworks
## (assets/boot/boot_cover.png, 8-px-Rand) — falls die Textur zur Laufzeit
## nicht lesbar ist (VRAM-komprimiert), bleibt der Ton trotzdem „aus dem Bild“.
const RANDFARBE_FALLBACK := Color("#D4C1A0")

## Router-Meilensteine der „zuhause“-Phase (SceneRouter.State — Werte sind
## API-FROZEN seit W1, hier gespiegelt, damit die Regel PUR bleibt).
const ROUTER_SUB := {0: 0.0, 1: 0.25, 2: 0.5, 3: 0.75, 4: 0.9}


## Gesamtprozent (0..1) für Phase + Sub-Fortschritt innerhalb der Phase.
## Unbekannte Phase → 0.0 (der Balken springt nie vorwärts auf Verdacht).
static func prozent(phase: String, sub := 1.0) -> float:
	var start := 0.0
	for eintrag in PHASEN:
		var ende := float(eintrag["bis"])
		if str(eintrag["id"]) == phase:
			return clampf(start + clampf(sub, 0.0, 1.0) * (ende - start), 0.0, 1.0)
		start = ende
	return 0.0


static func phasen_ids() -> Array[String]:
	var ids: Array[String] = []
	for eintrag in PHASEN:
		ids.append(str(eintrag["id"]))
	return ids


## Sub-Fortschritt der „zuhause“-Phase aus dem Router-State (ECHTE
## Meilensteine der ersten Reise: COVER→SWAP→WAIT_READY→REVEAL).
static func zuhause_sub_fuer_router_state(state: int) -> float:
	return float(ROUTER_SUB.get(state, 0.0))


## Deterministische Spruch-Reihenfolge: LCG-Fisher-Yates (kein Math.random —
## gleicher Seed liefert auf jedem Gerät dieselbe Permutation).
static func spruch_reihenfolge(anzahl: int, seed_wert: int) -> Array[int]:
	var reihe: Array[int] = []
	if anzahl <= 0:
		return reihe
	for i in anzahl:
		reihe.append(i)
	var s := maxi(1, absi(seed_wert))
	for i in range(anzahl - 1, 0, -1):
		s = int((s * 1664525 + 1013904223) % 4294967296)
		var j := s % (i + 1)
		var tausch := reihe[i]
		reihe[i] = reihe[j]
		reihe[j] = tausch
	return reihe


## Spruch-Index für Rotations-Schritt `schritt` (0, 1, 2, …): innerhalb einer
## Runde jeder Spruch genau einmal; Folgerunden rotieren die Permutation um 1,
## damit über die Rundengrenze nie derselbe Spruch zweimal hintereinander
## kommt (für anzahl > 2). -1 = keine Sprüche.
static func spruch_index(schritt: int, anzahl: int, seed_wert: int) -> int:
	if anzahl <= 0:
		return -1
	var reihe := spruch_reihenfolge(anzahl, seed_wert)
	var runde := maxi(0, schritt) / anzahl
	var pos := maxi(0, schritt) % anzahl
	return reihe[(pos + runde) % anzahl]


## Cover-Layout des Artworks im Viewport: skaliert auf „Cover“ (füllt), aber
## höchstens MAX_ZOOM_UEBER_FIT über der Fit-Skalierung (sanfter Crop). Das
## Fenster wird so verschoben, dass der Fokus (Gooby) möglichst mittig sitzt,
## ohne Bildkanten in den Viewport zu ziehen. Rückgabe:
## { "rect": Rect2 (Zeichenfläche in Viewport-Koordinaten),
##   "gedeckelt": bool (Zoom-Deckel griff → Ränder sichtbar),
##   "fokus_px": Vector2 (Fokuspunkt in Viewport-Koordinaten) }
static func cover_layout(viewport: Vector2, bild: Vector2, fokus := FOKUS) -> Dictionary:
	if viewport.x <= 0.0 or viewport.y <= 0.0 or bild.x <= 0.0 or bild.y <= 0.0:
		return {
			"rect": Rect2(Vector2.ZERO, viewport), "gedeckelt": false, "fokus_px": viewport / 2.0
		}
	var fit := minf(viewport.x / bild.x, viewport.y / bild.y)
	var cover := maxf(viewport.x / bild.x, viewport.y / bild.y)
	var skala := minf(cover, fit * MAX_ZOOM_UEBER_FIT)
	var gedeckelt := skala < cover - 1e-6
	var groesse := bild * skala
	var pos := viewport / 2.0 - fokus * groesse
	pos.x = _achse_klemmen(pos.x, groesse.x, viewport.x)
	pos.y = _achse_klemmen(pos.y, groesse.y, viewport.y)
	return {
		"rect": Rect2(pos, groesse),
		"gedeckelt": gedeckelt,
		"fokus_px": pos + fokus * groesse,
	}


## Randfarbe AUS dem Bild (gemittelte Pixel der vier Kanten) — füllt gedeckelte
## Ränder statt schwarzer Balken. Nicht lesbares/leeres Bild → Fallback.
static func randfarbe(img: Image, fallback := RANDFARBE_FALLBACK) -> Color:
	if img == null or img.is_empty():
		return fallback
	var w := img.get_width()
	var h := img.get_height()
	var summe := Vector3.ZERO
	var anzahl := 0
	var schritt := maxi(1, w / 32)
	for x in range(0, w, schritt):
		for y in [0, h - 1]:
			var c := img.get_pixel(x, y)
			summe += Vector3(c.r, c.g, c.b)
			anzahl += 1
	schritt = maxi(1, h / 32)
	for y in range(0, h, schritt):
		for x in [0, w - 1]:
			var c := img.get_pixel(x, y)
			summe += Vector3(c.r, c.g, c.b)
			anzahl += 1
	if anzahl == 0:
		return fallback
	summe /= float(anzahl)
	return Color(summe.x, summe.y, summe.z)


## Übergangs-Variante beim Öffnen (Spiegel des Web-veilWipeVariant):
## Reduced Motion → schlichter Fade, sonst Kreis-Wipe auf Gooby zentriert.
static func wipe_variante(reduced_motion: bool) -> String:
	return "fade" if reduced_motion else "kreis"


## Position auf einer Achse: Überstand → Fokus zentrieren, aber Kanten nie in
## den Viewport ziehen; kleiner als der Viewport (gedeckelt) → mittig.
static func _achse_klemmen(pos: float, groesse: float, viewport: float) -> float:
	if groesse >= viewport:
		return clampf(pos, viewport - groesse, 0.0)
	return (viewport - groesse) / 2.0
