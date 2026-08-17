class_name UrlaubsBesuch
extends RefCounted
## W15/URLAUB (User-Wunsch „Gooby im Urlaub begleiten“): Gate + Routing für
## den „Gooby besuchen“-Knopf der Reise-App. Solange Gooby VOR ORT ist
## (Phase away — returnReady wartet er schon am Flughafen), kann der Spieler
## zu ihm in eine URLAUBS-SZENE reisen. Drei wiederverwendbare Archetypen
## (strand/berge/stadt, scripts/city/urlaub/urlaubs_ort.gd) decken die 9
## Katalog-Ziele ab; `space` nutzt die BESTEHENDE Raumstation GOOB-1
## (OrtRaumstation — hier wird NUR der Einstieg verdrahtet).
##
## Der Besuch ist eine reine ANSICHT (Kuschel-Feature, keine Energie-
## Kosten): er ändert KEINE Vacation-Phase/Timestamps — nur die additiven
## Erinnerungs-Flags `vacation.besuche` (vacation.gd, W15-additiv) werden
## gelatcht. Rückweg: SceneRouter.back() (urlaubs_ort._on_verlassen).

const Vacation := preload("res://scripts/logic/vacation.gd")

const ARCHETYP_STRAND := "strand"
const ARCHETYP_BERGE := "berge"
const ARCHETYP_STADT := "stadt"
const ARCHETYP_SPACE := "space"

## Ziel → Szenen-Archetyp (Mapping in DATEN — deckt alle 9 Katalog-Ziele).
const ZIEL_ARCHETYP := {
	"beach": ARCHETYP_STRAND,
	"harbor": ARCHETYP_STRAND,
	"meadowTrip": ARCHETYP_BERGE,
	"spookGarden": ARCHETYP_BERGE,
	"nightSky": ARCHETYP_BERGE,
	"bigCity": ARCHETYP_STADT,
	"bakery": ARCHETYP_STADT,
	"toyRoom": ARCHETYP_STADT,
	"space": ARCHETYP_SPACE,
}

## Routen/Szenen der drei neuen Archetypen (space → OrtRaumstation.ROUTE).
const ROUTEN := {
	ARCHETYP_STRAND: &"city/urlaub/strand",
	ARCHETYP_BERGE: &"city/urlaub/berge",
	ARCHETYP_STADT: &"city/urlaub/stadt",
}
const SZENEN := {
	ARCHETYP_STRAND: "res://scenes/city/urlaub/urlaub_strand.tscn",
	ARCHETYP_BERGE: "res://scenes/city/urlaub/urlaub_berge.tscn",
	ARCHETYP_STADT: "res://scenes/city/urlaub/urlaub_stadt.tscn",
}

## Seelen-Kategorie der Vor-Ort-Kommentare (Lines: urlaub.soul.<n> in
## strings/de+en/urlaub.json; Registrierung in SoulLinien.KATEGORIEN ist
## ein >>-Request an den SOUL-Owner — der Aufruf ist bereits verdrahtet
## und bleibt bis dahin still).
const SOUL_KATEGORIE := "w15.urlaub"


## Archetyp eines Ziels ("" = unbekanntes Ziel).
static func archetyp_fuer(dest_id: String) -> String:
	return str(ZIEL_ARCHETYP.get(dest_id, ""))


## Besuchs-Gate: NUR solange Gooby wirklich vor Ort ist (Phase away mit
## bekanntem Ziel). returnReady/overdue = er packt schon/wartet am Gate.
static func verfuegbar(state: Dictionary, now_ms: int) -> bool:
	var v := Vacation.slice_of(state)
	if Vacation.phase_at(v, now_ms) != Vacation.PHASE_AWAY:
		return false
	return ZIEL_ARCHETYP.has(str(v["destId"]))


## Router-Ziel eines Besuchs (space fährt zur bestehenden GOOB-1).
static func route_fuer(dest_id: String) -> StringName:
	var archetyp := archetyp_fuer(dest_id)
	if archetyp == ARCHETYP_SPACE:
		return OrtRaumstation.ROUTE
	return ROUTEN.get(archetyp, &"")


## Route idempotent anmelden (Muster OrtRaumstation.registriere_route) —
## die Urlaubs-Szenen hängen bewusst NICHT an der city_map.
static func registriere_route(router: Object, dest_id: String) -> void:
	if router == null or not router.has_method("register_route"):
		return
	var archetyp := archetyp_fuer(dest_id)
	if archetyp == ARCHETYP_SPACE:
		OrtRaumstation.registriere_route(router)
		return
	if SZENEN.has(archetyp):
		router.register_route(ROUTEN[archetyp], SZENEN[archetyp])


## Besuch starten: Route anmelden + hinreisen. false, wenn Gate zu ist
## oder der Router fehlt/beschäftigt ist.
static func besuche(gs: Object, router: Object, now_ms: int) -> bool:
	if gs == null or router == null or not verfuegbar(gs.state(), now_ms):
		return false
	if router.has_method("is_busy") and router.is_busy():
		return false
	var dest_id := str(Vacation.slice_of(gs.state())["destId"])
	registriere_route(router, dest_id)
	if not router.has_method("goto"):
		return false
	router.goto(route_fuer(dest_id), {"dest_id": dest_id})
	return true


## Erinnerungs-Flag latchen (idempotent, NUR additiv — Phasen/Timestamps
## bleiben unangetastet). Rückgabe true = das war der ERSTE Besuch dort.
static func merke_besuch(gs: Object, dest_id: String) -> bool:
	if gs == null or not ZIEL_ARCHETYP.has(dest_id):
		return false
	var vorher: Dictionary = Vacation.slice_of(gs.state())["besuche"]
	if bool(vorher.get(dest_id, false)):
		return false
	gs.update(
		func(state: Dictionary) -> void:
			var v := Vacation.slice_of(state)
			v["besuche"][dest_id] = true
			state["vacation"] = v
	)
	if gs.has_method("notify_slice_changed"):
		gs.notify_slice_changed("vacation")
	return true
