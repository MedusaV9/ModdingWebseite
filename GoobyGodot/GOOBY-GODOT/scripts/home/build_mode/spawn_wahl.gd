class_name BuildSpawnWahl
extends RefCounted
## Spawn-Zellen-Wahl des Bau-Ghosts (W18 Befund 2, report_bau.md): Die
## blinde Grid-Mitte lag im Leitformat quer exakt hinter der Aktions-
## Knopfleiste des Bau-Docks (ihr Bildschirmpunkt war UI-verdeckt — ein
## Drag ab Spawn verpuffte in der Leiste) und hochkant auf belegten Zellen
## der Standard-Einrichtung („Platzieren" ausgegraut).
##
## Deshalb: ab Raummitte ringweise die NÄCHSTE Zelle suchen, die FREI ist
## UND deren Bildschirmpunkt in der sichtbaren freien Canvas-Zone liegt.
## Vorrang: frei UND sichtbar > sichtbar (belegt, aber greifbar — der
## Spieler kann den roten Ghost wegziehen) > frei (verdeckt, z. B. wenn
## eine Vollbild-Karte alles deckt) > Mitte.
##
## Die Kern-Suche `waehle` ist PUR (Belegungs-Check und Projektion kommen
## als Callables herein — headless testbar, tests/unit/test_w18_bau_fixes
## .gd); `spawn_zelle` ist der Node-Wrapper für BuildMode.

## Rand-Luft der Sichtzone: der Spawnpunkt soll nicht an der Bildkante
## oder haarscharf neben einer Klick-Zone kleben (Fingerbreite).
const RAND := 24.0


## Node-Wrapper für BuildMode: Spawnzelle für `def` (rot 0) in `grid`.
## `pose` = Transform3D der Kamera-ENDPOSE (die Bau-Kamera fliegt nach
## open() erst hin) oder null = Ist-Pose; `blocker` = klick-schluckende
## Canvas-Zonen (voll ausgebaute Dock-Zone + sichtbare STOP-Controls).
static func spawn_zelle(
	def: Dictionary,
	grid: GridData,
	kamera: Camera3D,
	pose: Variant,
	mount: Node3D,
	sicht: Rect2,
	blocker: Array[Rect2]
) -> Vector2i:
	var frei_check := func(at: Vector2i) -> bool: return bool(grid.can_place(def, at, 0, "")["ok"])
	var punkt_von := func(at: Vector2i) -> Vector2: return spawn_punkt(def, at, kamera, pose, mount)
	return waehle(grid.size, def["footprint"], frei_check, punkt_von, sicht, blocker)


## PURE Kern-Suche. `frei_check`: func(at: Vector2i) -> bool (can_place
## ok?); `punkt_von`: func(at: Vector2i) -> Vector2 (Canvas-Punkt der
## Footprint-Mitte; (-1,-1) = nicht projizierbar).
static func waehle(
	grid_size: Vector2i,
	fp: Vector2i,
	frei_check: Callable,
	punkt_von: Callable,
	sicht: Rect2,
	blocker: Array[Rect2]
) -> Vector2i:
	var mitte := Vector2i(grid_size.x / 2, grid_size.y / 2) - fp / 2
	var frei_fallback := mitte
	var frei_gefunden := false
	var sichtbar_fallback := mitte
	var sichtbar_gefunden := false
	for ring in maxi(grid_size.x, grid_size.y) + 1:
		for at in ring_zellen(mitte, ring):
			if not footprint_in_bounds(at, fp, grid_size):
				continue
			var frei := bool(frei_check.call(at))
			var sichtbar := punkt_frei(punkt_von.call(at), sicht, blocker)
			if frei and sichtbar:
				return at
			if frei and not frei_gefunden:
				frei_gefunden = true
				frei_fallback = at
			if sichtbar and not sichtbar_gefunden:
				sichtbar_gefunden = true
				sichtbar_fallback = at
	if sichtbar_gefunden:
		return sichtbar_fallback
	if frei_gefunden:
		return frei_fallback
	return mitte


## Zellen mit Chebyshev-Abstand `ring` um `mitte` — Ring 0 = die Mitte
## selbst; obere Reihe zuerst (deterministisch, und im Leitformat quer
## liegen obere Raumzellen am ehesten ÜBER dem unteren Dock).
static func ring_zellen(mitte: Vector2i, ring: int) -> Array[Vector2i]:
	if ring == 0:
		return [mitte]
	var out: Array[Vector2i] = []
	for dy in range(-ring, ring + 1):
		for dx in range(-ring, ring + 1):
			if maxi(absi(dx), absi(dy)) == ring:
				out.append(mitte + Vector2i(dx, dy))
	return out


## Liegt der unrotierte Footprint komplett im Grid?
static func footprint_in_bounds(at: Vector2i, fp: Vector2i, grid_size: Vector2i) -> bool:
	return at.x >= 0 and at.y >= 0 and at.x + fp.x <= grid_size.x and at.y + fp.y <= grid_size.y


## Punkt sichtbar (in der Sichtzone) und von keinem Blocker-Rect gedeckt?
static func punkt_frei(punkt: Vector2, sicht: Rect2, blocker: Array[Rect2]) -> bool:
	if not sicht.has_point(punkt):
		return false
	for rect in blocker:
		if rect.has_point(punkt):
			return false
	return true


## Bildschirmpunkt der Footprint-Mitte einer Kandidaten-Zelle (rot 0) —
## bei `pose` != null kurz auf die Endpose gesetzt, gemessen und wieder
## zurück (bleibt im selben Frame unsichtbar). (-1,-1) = nicht
## projizierbar (hinter der Kamera/keine Kamera).
static func spawn_punkt(
	def: Dictionary, at: Vector2i, kamera: Camera3D, pose: Variant, mount: Node3D
) -> Vector2:
	if kamera == null or not kamera.is_inside_tree() or mount == null:
		return Vector2(-1.0, -1.0)
	var lokal: Vector3 = GridData.world_center(at, def["footprint"], 0)
	if int(def["layer"]) == GridData.Layer.CEILING:
		lokal.y = GridData.DECKEN_HOEHE
	var welt := mount.to_global(lokal)
	var vorher := kamera.global_transform
	if pose is Transform3D:
		kamera.global_transform = pose
	var punkt := (
		Vector2(-1.0, -1.0) if kamera.is_position_behind(welt) else kamera.unproject_position(welt)
	)
	kamera.global_transform = vorher
	return punkt


## Sichtbare Canvas-Zone mit Rand-Luft.
static func sichtzone(viewport: Viewport, rand := RAND) -> Rect2:
	if viewport == null:
		return Rect2(-1.0e9, -1.0e9, 2.0e9, 2.0e9)
	return viewport.get_visible_rect().grow(-rand)


## Global-Rects aller sichtbaren klick-schluckenden Controls (mouse_filter
## STOP) im Viewport — Spiegel der Playtest-Messung flow_baumodus.
## _ui_verdeckt. SubViewport-Inhalte zählen nicht (eigener Koordinaten-
## raum, liegt nie über dem Raum).
static func stop_rects(viewport: Viewport) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if viewport == null:
		return out
	var stapel: Array[Node] = [viewport]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell != viewport and aktuell is Viewport:
			continue
		if aktuell is Control:
			var control := aktuell as Control
			if control.is_visible_in_tree() and control.mouse_filter == Control.MOUSE_FILTER_STOP:
				out.append(control.get_global_rect())
		for kind in aktuell.get_children():
			stapel.append(kind)
	return out
