class_name UrlaubsSprueche
extends RefCounted
## W15/URLAUB — Goobys Vor-Ort-Erzähl-Lines (AcBubble): 8 Lines je
## Archetyp in strings/de+en/urlaub.json (`urlaub.bubble.<archetyp>`,
## an das soul_lines-Muster angelehnt, aber EIGENE Datei/Domain).
## ROTATION statt Zufall (Muster FuetterSprueche): jede Blase nimmt die
## NÄCHSTE Line ihres Archetyps — nichts wiederholt sich, bevor alle
## 8 dran waren.

static var _zaehler: Dictionary = {}


## Nächste Erzähl-Line des Archetyps ("" bei unbekanntem Archetyp —
## has_key-Guard, damit kein push_error-Rauschen entsteht).
static func naechste(archetyp: String) -> String:
	var key := "urlaub.bubble." + archetyp
	if not I18nService.has_key(key):
		return ""
	var liste := I18nService.items(key)
	if liste.is_empty():
		return ""
	var index := int(_zaehler.get(archetyp, 0)) % liste.size()
	_zaehler[archetyp] = index + 1
	return String(liste[index])


## Nur für Tests: Rotation zurücksetzen.
static func reset_fuer_tests() -> void:
	_zaehler.clear()
