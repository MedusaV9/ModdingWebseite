class_name LoadingScreenRules
extends RefCounted
## RW-8 — Regeln der grossen Ranch-Ladebildschirme (PURE, ueberall aufrufbar).
##
## EINE Wahrheit fuer die Frage "wann zeigt das LoadingVeil den vollen
## Artwork-Ladebildschirm?": nur bei LANGEN Reisen (Stadt->Ranch, Ranch-Zonen,
## Turnier, Besuch). Kurze Wege (Hausraeume, Stadt-Orte, Panels, DOOR_TRAVEL)
## bekommen bewusst KEINEN vollen Ladebildschirm — der nervt bei
## Sekunden-Wechseln mehr, als er schmueckt. Ladezeiten werden dabei NIE
## kuenstlich verlaengert: das Veil zeigt nur den echten threaded-Fortschritt.
##
## Zweite Aufgabe: kontextpassende Artwork-Wahl (4 Ladebildschirm-Bilder +
## Key-Artwork, s. docs/godot-rewrite/RANCH-ASSETS.md) und die Tipp-Rotation
## als Shuffle-Bag (jeder Tipp einmal, bevor sich einer wiederholt; nie
## derselbe Tipp zweimal hintereinander).

const ARTWORK_DIR := "res://assets/ranch/artwork"
## Freigestellte Logo-Variante (Alpha statt weisser Karte) — RW-8 aus dem
## Original `logo_gooby_ranch.webp` erzeugt; das Original bleibt unberuehrt.
const LOGO_PFAD := ARTWORK_DIR + "/logo_gooby_ranch_frei.webp"

## Artwork-Id -> Dateiname unter ARTWORK_DIR.
const ARTWORKS := {
	"stall": "ladebildschirm_stall_buersten.webp",
	"galopp": "ladebildschirm_galopp_wiese.webp",
	"nacht": "ladebildschirm_nacht_teich.webp",
	"turnier": "ladebildschirm_turnier_sprung.webp",
	"key": "key_artwork_gooby_ranch.webp",
}

## Lange Reisen: Ziel-Praefixe bzw. exakte Ziele (SceneRouter-Targets).
const LANGE_PRAEFIXE: Array[String] = ["ranch/"]
const LANGE_ZIELE: Array[String] = ["social/visit"]

## Nachtfenster der Artwork-Wahl: ab 20 Uhr bzw. vor 6 Uhr.
const NACHT_AB := 20.0
const NACHT_BIS := 6.0

## SceneRouter.TravelType.DOOR_TRAVEL — hier gespiegelt, damit die Regel
## PURE bleibt (kein Autoload-Import noetig; Wert ist API-FROZEN seit W1).
const DOOR_TRAVEL := 1

## Tipps der grossen Ladebildschirme (I18n-Array, >= 25 Eintraege).
const TIPS_KEY := "loading.tips"


## DIE Regel: voller Ladebildschirm nur bei langen VEIL-Reisen.
## DOOR_TRAVEL (kurzer Tuer-Cut) bekommt NIE den vollen Schirm.
static func ist_lange_reise(target: StringName, travel_type := 0) -> bool:
	if travel_type == DOOR_TRAVEL:
		return false
	var ziel := String(target)
	if LANGE_ZIELE.has(ziel):
		return true
	for praefix in LANGE_PRAEFIXE:
		if ziel.begins_with(praefix):
			return true
	return false


static func ist_nacht(stunde: float) -> bool:
	return stunde >= NACHT_AB or stunde < NACHT_BIS


## Kontextpassende Artwork-Id ("" = Ziel bekommt keinen vollen Schirm):
## Turnier schlaegt Tageszeit, nachts wirkt das Teich-Bild, Reiten/Weite
## nimmt den Galopp, Hof/Stall/Dorf das Stall-Bild, Besuch das Key-Artwork.
static func artwork_id_fuer(target: StringName, stunde := 12.0) -> String:
	if not ist_lange_reise(target):
		return ""
	var ziel := String(target)
	if not ziel.begins_with("ranch/"):
		return "key"
	if ziel.contains("turnier"):
		return "turnier"
	if ist_nacht(stunde):
		return "nacht"
	if ziel == "ranch/welt" or ziel == "ranch/fahrt":
		return "galopp"
	return "stall"


## Ressourcen-Pfad einer Artwork-Id ("" = unbekannt).
static func artwork_pfad(id: String) -> String:
	if not ARTWORKS.has(id):
		return ""
	return "%s/%s" % [ARTWORK_DIR, ARTWORKS[id]]


## Aktuelle Ortszeit als Stunde (0..24) — Fallback der Artwork-Wahl.
static func aktuelle_stunde() -> float:
	var jetzt := Time.get_time_dict_from_system()
	return float(jetzt.get("hour", 12)) + float(jetzt.get("minute", 0)) / 60.0


## Shuffle-Bag-Rotation: liefert den naechsten Tipp-Index und mutiert
## `zustand` ({bag: Array, letzter: int}). Garantien: innerhalb einer Runde
## kommt jeder Index genau einmal; ueber die Rundengrenze folgt nie derselbe
## Index zweimal hintereinander (bei anzahl > 1). -1 = keine Tipps.
static func naechster_tipp_index(anzahl: int, zustand: Dictionary) -> int:
	if anzahl <= 0:
		return -1
	var roh: Variant = zustand.get("bag", [])
	var bag: Array = roh if roh is Array else []
	if bag.is_empty():
		for i in anzahl:
			bag.append(i)
		bag.shuffle()
		var letzter := int(zustand.get("letzter", -1))
		if anzahl > 1 and int(bag[bag.size() - 1]) == letzter:
			var tausch: Variant = bag[0]
			bag[0] = bag[bag.size() - 1]
			bag[bag.size() - 1] = tausch
	var index := int(bag.pop_back())
	zustand["bag"] = bag
	zustand["letzter"] = index
	return index
