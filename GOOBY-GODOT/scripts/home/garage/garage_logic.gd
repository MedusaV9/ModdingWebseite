class_name GarageLogic
extends RefCounted
## Garage (W13C, Doc D §7) — PURE Kauf- und Rolltor-Regeln.
##
## Die Garage ist ein EINMALIGES Haus-Upgrade im Garten (2×3-Struktur wie
## das Gewächshaus, Muster ShedLogic/GardenWorld.bauen): Kauf kostet Münzen,
## danach parkt das aktive Auto (AutoKatalog.aktives_auto — Autohaus-Besitz)
## sichtbar drin. Der Rolltor-Zustand ist RUNTIME-only (nicht im Save);
## persistiert wird nur die Struktur im `home.garden`-Slice.

const EconomyLogic := preload("res://scripts/logic/economy.gd")

const KIND := "garage"
const PREIS := 1200

## Ablehnungsgründe (stabile Strings für UI/Tests — plus die GardenGrid-Gründe).
const REASON_SCHON_GEBAUT := "schon_gebaut"
const REASON_ZU_TEUER := "zu_teuer"

## Rolltor-Zustandsmaschine: zu → oeffnet → offen → schliesst → zu.
## Ein Toggle mitten in der Fahrt kehrt die Richtung um.
const ROLLTOR_ZU := "zu"
const ROLLTOR_OEFFNET := "oeffnet"
const ROLLTOR_OFFEN := "offen"
const ROLLTOR_SCHLIESST := "schliesst"


static func footprint() -> Vector2i:
	return GardenGrid.structure_size(KIND)


## Steht schon eine Garage im Garten?
static func gebaut(gs: Object) -> bool:
	return not GardenState.grid(gs).structures_of_kind(KIND).is_empty()


static func kann_kaufen(muenzen: int) -> bool:
	return muenzen >= PREIS


## Garage kaufen + platzieren (Daten-Seite; Bau-Animation macht der Aufrufer).
## Fail-closed: erst alle Prüfungen, dann Struktur + Münzabzug in einem Zug.
static func kaufen(gs: Object, at: Vector2i, rot := 0) -> Dictionary:
	var grid := GardenState.grid(gs)
	if not grid.structures_of_kind(KIND).is_empty():
		return {"ok": false, "reason": REASON_SCHON_GEBAUT}
	var check := grid.can_place_structure(KIND, at, rot)
	if not bool(check["ok"]):
		return check
	if not kann_kaufen(int(gs.get_value("economy.coins", 0))):
		return {"ok": false, "reason": REASON_ZU_TEUER}
	grid.place_structure(KIND, at, rot)
	GardenState.save_grid(gs, grid)
	gs.update(
		func(state: Dictionary) -> void: EconomyLogic.spend(state["economy"], PREIS, "garage_bau")
	)
	gs.notify_slice_changed("home")
	return {"ok": true, "reason": ""}


## Der Grid-Eintrag der Garage ({} = keine gebaut).
static func struktur(gs: Object) -> Dictionary:
	var liste := GardenState.grid(gs).structures_of_kind(KIND)
	return liste[0] if not liste.is_empty() else {}


# ── Rolltor-Zustandsmaschine (PURE) ──────────────────────────────────────────


## Nächster Zustand nach einem Tap aufs Tor (auch mitten in der Fahrt).
static func rolltor_toggle(zustand: String) -> String:
	if zustand == ROLLTOR_ZU or zustand == ROLLTOR_SCHLIESST:
		return ROLLTOR_OEFFNET
	return ROLLTOR_SCHLIESST


## End-Zustand, wenn die Tor-Animation ausgelaufen ist.
static func rolltor_ende(zustand: String) -> String:
	if zustand == ROLLTOR_OEFFNET:
		return ROLLTOR_OFFEN
	if zustand == ROLLTOR_SCHLIESST:
		return ROLLTOR_ZU
	return zustand


## Ziel-Öffnungsanteil (0 = ganz unten/zu, 1 = ganz aufgerollt).
static func rolltor_ziel_anteil(zustand: String) -> float:
	if zustand == ROLLTOR_OEFFNET or zustand == ROLLTOR_OFFEN:
		return 1.0
	return 0.0


## Zählt der Zustand als „offen genug zum Rausfahren"?
static func rolltor_ist_offen(zustand: String) -> bool:
	return zustand == ROLLTOR_OFFEN
