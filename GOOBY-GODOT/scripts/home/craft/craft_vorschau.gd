class_name CraftVorschau
extends CosmeticPreview
## W15/MARKT — 3D-Vorschau des Ergebnis-Items im Craft-Panel über den
## GETEILTEN SubViewport-Icon-Renderer der Cosmetics (cosmetic_preview.gd,
## Muster FuetterVorschau/Kühlschrank): dieselbe Bäckerei (EIN Viewport,
## PRO_FRAME-Stapel pro Frame, statischer Cache, `fertig`-Signal), nur der
## Bau-Schritt lädt das Möbel-GLB des Rezept-Outputs (FurnitureCatalog).
## Cache-/Queue-Keys tragen das "craft:"-Präfix, damit sie nie mit
## Cosmetic-Ids kollidieren — `fertig` feuert mit dem präfixierten Key.

const PREFIX := "craft:"


## Fertige Textur ODER null — dann wird sie in Auftrag gegeben und kommt
## später per `fertig("craft:<item_id>", textur)`-Signal.
func hole_item(item_id: String) -> Texture2D:
	var key := PREFIX + item_id
	if _cache.has(key):
		return _cache[key]
	if not _warteschlange.has(key):
		_warteschlange.append(key)
	return null


## Bau-Schritt der Bäckerei: Craft-Keys laden das Katalog-GLB des Items,
## alles andere läuft unverändert über die Cosmetics-Basis.
func _backe(id: String) -> Texture2D:
	if not id.begins_with(PREFIX):
		return await super(id)
	var item := _modell(id.trim_prefix(PREFIX))
	if item == null:
		return null
	_halter.add_child(item)
	_rahme(item)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var bild := _viewport.get_texture().get_image()
	item.queue_free()
	if bild == null:
		return null
	return ImageTexture.create_from_image(bild)


## Möbel-Modell eines Katalog-Items (null bei proc-Möbeln/Fehlpfad —
## das Panel degradiert dann einfach auf „keine Vorschau“).
static func _modell(item_id: String) -> Node3D:
	var def := FurnitureCatalog.def(item_id)
	if def.is_empty() or str(def.get("proc", "")) != "":
		return null
	var pfad := FurnitureCatalog.glb_path(def)
	if not ResourceLoader.exists(pfad):
		return null
	var szene: PackedScene = load(pfad)
	return szene.instantiate() if szene != null else null
