class_name GoobyeLadenUiTeile
extends RefCounted
## W18/4 — kleine, pure UI-Teile der GooUndBye-Laden-Szene (CI-Split wegen
## gdlint max-file-lines, Muster wie mumie_szene.gd/event_props.gd):
## - Slot-Chip-Layout über den 3D-Regal-Ankern: auf kleinen/hochkanten
##   Canvases ist der 44-pt-Touch-Floor BREITER als der projizierte
##   Ankerabstand — die Chips stapelten sich (Befund W18/4). Die X-Mitten
##   spreizen auf mindestens Chipbreite + Lücke, zentriert um die
##   Anker-Mitte; die Y-Position bleibt am jeweiligen Anker.
## - W19-Playtest-Blocker (hochkant): die gespreizte Reihe ragte links aus
##   dem Canvas — Slot-0-Taps gingen ins Leere. `reihe_in_grenzen` schiebt
##   die ganze Reihe zurück ins Bild, `kamera_z_fuer_punkte` rechnet das
##   Kamera-Z, damit auch die 3D-Anker selbst im Sichtfeld liegen.
## - Kassensturz-Umsatz-Label: die große Zähl-Zahl bekommt ihr Label (der
##   Key dlc_goobye.abschluss.umsatz existierte, war aber unbenutzt).

## Mindest-Lücke zwischen zwei Slot-Chips (Design-px, ×f) — der
## 44-pt-Touch-Floor kann breiter sein als der projizierte Ankerabstand.
const CHIP_LUECKE := 6.0


## Slot-Knöpfe über die 3D-Anker legen (unproject je Relayout, nie pro
## Frame — die Kamera steht still); überlappende Chips spreizen und die
## Reihe in den Canvas-Grenzen halten (W19-Hochkant-Blocker).
static func slots_platzieren(
	cam: Camera3D, knoepfe: Array[Button], anker: Array[Node3D], m: Dictionary
) -> void:
	var anzahl := mini(knoepfe.size(), anker.size())
	var punkte: Array[Vector2] = []
	var chip_breite := 0.0
	for i in anzahl:
		ScreenShell.touch_target(knoepfe[i], m)
		chip_breite = maxf(chip_breite, knoepfe[i].size.x)
		punkte.append(cam.unproject_position(anker[i].global_position))
	var anker_x: Array[float] = []
	for punkt in punkte:
		anker_x.append(punkt.x)
	var luecke := CHIP_LUECKE * float(m["f"])
	var xs := chip_spalten_x(anker_x, chip_breite + luecke)
	var canvas: Vector2 = m["canvas"]
	var insets: Dictionary = m["insets"]
	xs = reihe_in_grenzen(
		xs, chip_breite / 2.0 + luecke, float(insets["left"]), canvas.x - float(insets["right"])
	)
	for i in anzahl:
		var knopf := knoepfe[i]
		var mitte := Vector2(xs[i], punkte[i].y)
		knopf.position = mitte - knopf.size / 2.0 - Vector2(0.0, knopf.size.y * 0.8)


## Überlappungsfreie Chip-X-Mitten (pur, für Tests): behält die projizierten
## Anker-Mitten, solange sie weit genug auseinander liegen, spreizt sonst
## gleichmäßig auf `mindest_schritt` — zentriert um den Anker-Mittelwert,
## damit die Reihe optisch am Regal bleibt.
static func chip_spalten_x(anker_x: Array[float], mindest_schritt: float) -> Array[float]:
	var n := anker_x.size()
	if n <= 1:
		return anker_x.duplicate()
	var schritt := (anker_x[n - 1] - anker_x[0]) / float(n - 1)
	if schritt >= mindest_schritt:
		return anker_x.duplicate()
	var mitte := (anker_x[0] + anker_x[n - 1]) / 2.0
	var xs: Array[float] = []
	for i in n:
		xs.append(mitte + (float(i) - float(n - 1) / 2.0) * mindest_schritt)
	return xs


## Die (ggf. gespreizte) Chip-Reihe KOMPLETT in die Canvas-Grenzen schieben
## (pur): auf schmalen Hochkant-Canvases ragte die um die Anker-Mitte
## zentrierte Reihe links über den Rand — der Slot-0-Tap ging ins Leere
## (W19-Playtest, Blocker). Verschiebt die GANZE Reihe (Abstände bleiben);
## stünden beide Seiten über, gewinnt der linke Rand (Slot 0 zuerst).
static func reihe_in_grenzen(
	xs: Array[float], halb_breite: float, links: float, rechts: float
) -> Array[float]:
	if xs.is_empty():
		return xs.duplicate()
	var min_x := xs[0]
	var max_x := xs[0]
	for x in xs:
		min_x = minf(min_x, x)
		max_x = maxf(max_x, x)
	var schub := 0.0
	if max_x + halb_breite > rechts:
		schub = rechts - halb_breite - max_x
	if min_x + schub - halb_breite < links:
		schub = links + halb_breite - min_x
	var verschoben: Array[float] = []
	for x in xs:
		verschoben.append(x + schub)
	return verschoben


## Mindest-Kamera-Z (pur), damit alle Welt-Punkte plus Seitenrand (Meter)
## im HORIZONTALEN Sichtfeld liegen: Hochformat sieht horizontal wenig
## Welt — ein FESTES Kamera-Z schnitt den linken Regal-Rand samt Slot-0-
## Anker ab (W19-Playtest, Blocker). Annahmen wie im Laden-Diorama:
## Kamera bei x = 0, Blick entlang −Z, nur um X geneigt (pitch_rad),
## `tan_halb_h` = tan(FOV/2) × Seitenverhältnis (KEEP_HEIGHT).
static func kamera_z_fuer_punkte(
	cam_y: float, pitch_rad: float, tan_halb_h: float, punkte: Array[Vector3], rand_m: float
) -> float:
	var noetig := 0.0
	for punkt in punkte:
		var tiefe := (absf(punkt.x) + rand_m) / maxf(tan_halb_h, 0.01)
		var z := (tiefe - (punkt.y - cam_y) * sin(pitch_rad)) / maxf(cos(pitch_rad), 0.1) + punkt.z
		noetig = maxf(noetig, z)
	return noetig


## Szenen-Griff dazu: Kamera-Z aus dem echten Kamera-Setup + den
## Slot-Ankern — nie näher als `basis_z` (das Quer-Diorama bleibt exakt
## wie gehabt, nur schmale Formate rücken dynamisch zurück).
static func kamera_z_fuer_anker(
	cam: Camera3D, anker: Array[Node3D], canvas: Vector2, basis_z: float, rand_m: float
) -> float:
	if cam == null or anker.is_empty():
		return basis_z
	var punkte: Array[Vector3] = []
	for knoten in anker:
		punkte.append(knoten.position)
	var tan_halb_h := tan(deg_to_rad(cam.fov) * 0.5) * (canvas.x / maxf(canvas.y, 1.0))
	var noetig := kamera_z_fuer_punkte(
		cam.position.y, deg_to_rad(cam.rotation_degrees.x), tan_halb_h, punkte, rand_m
	)
	return maxf(basis_z, noetig)


## Label über der großen Kassensturz-Zähl-Zahl — vorher stand dort ein
## nackter Betrag ohne Einordnung.
static func umsatz_titel() -> Label:
	var titel := Label.new()
	titel.name = "UmsatzTitel"
	titel.theme_type_variation = &"CaptionLabel"
	titel.text = I18nService.t("dlc_goobye.abschluss.umsatz")
	titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return titel
