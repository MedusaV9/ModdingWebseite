class_name FuetterVorschau
extends CosmeticPreview
## W14/FRIDGE — Regal-Icons als ECHTE 3D-Vorschau je Speise über den
## GETEILTEN SubViewport-Icon-Renderer der Cosmetics (cosmetic_preview.gd):
## dieselbe Bäckerei (EIN Viewport, PRO_FRAME-Stapel pro Frame, statischer
## Cache, `fertig`-Signal), nur der Bau-Schritt lädt das Speise-Modell
## (FuetterModelle) statt CosmeticBuilders. Cache-/Queue-Keys tragen das
## "food:"-Präfix, damit sie nie mit Cosmetic-Ids kollidieren — das
## `fertig`-Signal feuert entsprechend mit dem präfixierten Key.

const PREFIX := "food:"


## Fertige Textur ODER null — dann wird sie in Auftrag gegeben und kommt
## später per `fertig("food:<id>", textur)`-Signal (Muster CosmeticPreview).
func hole_speise(food_id: String) -> Texture2D:
	var key := PREFIX + food_id
	if _cache.has(key):
		return _cache[key]
	if not _warteschlange.has(key):
		_warteschlange.append(key)
	return null


## Modell-Schritt der Bäckerei: Speise-Keys bauen das Speise-Modell, Render-
## Callback und Abbruch-Lifecycle bleiben in der Cosmetics-Basis.
func _baue_item(id: String) -> Node3D:
	if not id.begins_with(PREFIX):
		return super(id)
	return FuetterModelle.instanz(id.trim_prefix(PREFIX))
