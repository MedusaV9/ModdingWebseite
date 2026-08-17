class_name ShedLogic
extends RefCounted
## Shed-Stufen (Doc D §2.3) — PURE Kapazitäts-/Preis-Tabelle.
##
## Das Shed ist eine 2×2-Garten-Struktur, die das Lager vergrößert:
##   Stufe 0 = kein Shed (Basis 100 Lagerpunkte)
##   Stufe 1 = Holzhütte            (+50  → 150 LP,  500 Münzen)
##   Stufe 2 = gestrichen + Fenster (+100 → 200 LP, 1500 Münzen)
##   Stufe 3 = groß, Doppeltür      (+200 → 300 LP, 4000 Münzen)
## Ein Upgrade belegt denselben Grid-Platz — nur das Modell wird getauscht
## (Bau-Animation, Doc D §3.1).

const BASIS_KAPAZITAET := 100
const MAX_STUFE := 3
## Bonus-Lagerpunkte je Stufe (Index = Stufe).
const BONUS: Array[int] = [0, 50, 100, 200]
## Kosten für den Sprung AUF Stufe i (Index = Zielstufe, 0 = unbenutzt).
const PREISE: Array[int] = [0, 500, 1500, 4000]
## Sichtbare Größe/Ausstattung pro Stufe (der Renderer liest genau das).
## Farben kommen NICHT von hier, sondern aus der Theme-Palette in HomeProps.
const MODELLE: Array[Dictionary] = [
	{"hoehe": 0.0, "anstrich": false, "fenster": false, "wetterhahn": false},
	{"hoehe": 1.6, "anstrich": false, "fenster": false, "wetterhahn": false},
	{"hoehe": 1.9, "anstrich": true, "fenster": true, "wetterhahn": false},
	{"hoehe": 2.3, "anstrich": true, "fenster": true, "wetterhahn": true},
]


static func clamp_stufe(stufe: int) -> int:
	return clampi(stufe, 0, MAX_STUFE)


## Lagerkapazität bei Shed-Stufe `stufe`.
static func kapazitaet(stufe: int) -> int:
	return BASIS_KAPAZITAET + BONUS[clamp_stufe(stufe)]


## Preis des nächsten Upgrades (0 = maximal ausgebaut).
static func upgrade_preis(stufe: int) -> int:
	var ziel := clamp_stufe(stufe) + 1
	return 0 if ziel > MAX_STUFE else PREISE[ziel]


static func kann_upgraden(stufe: int, muenzen: int) -> bool:
	var preis := upgrade_preis(stufe)
	return preis > 0 and muenzen >= preis


## Optik-Daten der Stufe (Renderer: sichtbar größer/schöner).
static func modell(stufe: int) -> Dictionary:
	return MODELLE[clamp_stufe(stufe)].duplicate()
