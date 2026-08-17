class_name GoobyeLadenBausteine
## W18/4 — UI-/Mesh-Bausteine des Goo-und-Bye-Ladens, ausgelagert
## (laden_scene.gd stand an der gdlint-1000-Zeilen-Kante, Muster
## GoobyeLadenLeben): PURE Statics ohne Szenen-Zustand — die Szene reicht
## Container/Metrics herein und verdrahtet selbst.

## Lieferwagen-Bausteine (W19 Welle C, §4.2/§7.1): Kenney-delivery-Kastenwagen
## im Marken-Teal — s. lieferwagen_modell().
const LIEFERWAGEN_GLB := "res://assets/city/autos/delivery.glb"
const LIEFERWAGEN_TINT := Color("#A7DCD6")


## Waren-Mesh je Katalog-Form (Regal-Slots): klein, ungetintet — die
## Farbe kommt vom Material der Szene.
static func form_mesh(form: String) -> Mesh:
	match form:
		"rund":
			var kugel := SphereMesh.new()
			kugel.radius = 0.05
			kugel.height = 0.1
			return kugel
		"tropfen":
			var kapsel := CapsuleMesh.new()
			kapsel.radius = 0.04
			kapsel.height = 0.12
			return kapsel
		"dreieck":
			var prisma := PrismMesh.new()
			prisma.size = Vector3(0.1, 0.1, 0.1)
			return prisma
		"stern":
			var stern := CylinderMesh.new()
			stern.top_radius = 0.02
			stern.bottom_radius = 0.06
			stern.height = 0.1
			stern.radial_segments = 5
			return stern
		_:
			var box := BoxMesh.new()
			box.size = Vector3(0.09, 0.09, 0.09)
			return box


## Kassensturz-Zeile „Label links, Wert rechts“ (Wert-Node heißt
## `Wert_<key>` — Tests greifen darüber zu).
static func abschluss_zeile(box: VBoxContainer, key: String, wert: String) -> void:
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 10)
	box.add_child(zeile)
	var links := Label.new()
	links.text = I18nService.t("dlc_goobye.abschluss." + key)
	links.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zeile.add_child(links)
	var rechts := Label.new()
	rechts.name = "Wert_" + key
	rechts.theme_type_variation = &"HeadlineLabel"
	rechts.text = wert
	zeile.add_child(rechts)


## „Goo und Bye“-Lieferwagen (W19 Welle C): Marken-Teal + Logo-Schriftzug
## auf beiden Flanken — WIEDERVERWENDET von der Übergabe-Vorfahrt im Laden
## UND der REHWEI-Rampe (kein Modell doppelt). Fahrtrichtung des
## Wurzel-Nodes: +X (delivery_cutscene-Konvention, inneres Modell um +90°
## gedreht) — die Flanken zeigen ±Z.
static func lieferwagen_modell(skala := 1.0) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "GoobyeLieferwagen"
	if ResourceLoader.exists(LIEFERWAGEN_GLB):
		var szene: PackedScene = load(LIEFERWAGEN_GLB)
		if szene != null:
			var modell: Node3D = szene.instantiate()
			modell.scale = Vector3.ONE * skala
			modell.rotation.y = PI * 0.5
			OrtRequisiten.materialien_absichern(modell)
			wurzel.add_child(modell)
			OrtRequisiten.tinte(modell, LIEFERWAGEN_TINT, 0.5)
	for seite: float in [1.0, -1.0]:
		var logo := Label3D.new()
		logo.name = "Logo"
		logo.text = "Goo und Bye"
		logo.pixel_size = 0.0032
		logo.modulate = AcTokens.INK
		logo.outline_modulate = Color.WHITE
		logo.outline_size = 14
		logo.position = Vector3(-0.1 * skala, 0.62 * skala, seite * 0.47 * skala)
		logo.rotation.y = 0.0 if seite > 0.0 else PI
		wurzel.add_child(logo)
	return wurzel


## Abgedunkeltes Overlay + zentrierte AcCard-Karte (Daumenzone-freundlich:
## die Karte sitzt mittig, der Knopf ist ihr unterstes Element).
static func karte_overlay(
	ui: Control, metrics: Dictionary, overlay_name: String, karte_basis: float
) -> Dictionary:
	var overlay := Control.new()
	overlay.name = overlay_name
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(AcTokens.INK.r, AcTokens.INK.g, AcTokens.INK.b, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	var karte := PanelContainer.new()
	karte.name = "Karte"
	karte.theme_type_variation = &"AcCard"
	karte.set_anchors_preset(Control.PRESET_CENTER)
	karte.grow_horizontal = Control.GROW_DIRECTION_BOTH
	karte.grow_vertical = Control.GROW_DIRECTION_BOTH
	var breite := ScreenShell.card_width(metrics, karte_basis)
	karte.custom_minimum_size = Vector2(breite, 0.0)
	overlay.add_child(karte)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	karte.add_child(box)
	return {"overlay": overlay, "karte": karte, "box": box}
