class_name RanchHorseCare
extends RefCounted
## Pferde-Pflege & Bindung (RANCH-2) — PURE Stat-Mathe, gleiche Handschrift
## wie scripts/logic/stats.gd: alles static, Dictionaries rein, NEUE
## Dictionaries raus, keine Nodes/Zeitquellen.
##
## Jedes Pferd hat drei verfallende Werte (hunger/durst/sauberkeit, 0..100),
## eine ABGELEITETE Laune (laune()) und eine persistente Bindung (0..100,
## wächst über Pflege-Aktionen mit Tagesdeckel, verfällt sehr langsam).
## Struktur des Pferde-Dictionaries: RanchPlaySlices.neues_pferd().

const MIN := 0.0
const MAX := 100.0
const KEYS: Array[String] = ["hunger", "durst", "sauberkeit"]

## Verfall pro realer Minute auf der Weide (Tag, wach).
const RATES_WACH := {"hunger": -0.25, "durst": -0.4, "sauberkeit": -0.15}
## Pro realer Minute im Stall (Nacht, schlafend): weniger Hunger/Durst,
## aber der Schlafplatz macht schmutzig.
const RATES_SCHLAF := {"hunger": -0.08, "durst": -0.15, "sauberkeit": -0.2}
## Unter dieser Stall-Sauberkeit verfällt die Pferde-Sauberkeit doppelt.
const STALL_DRECKIG_UNTER := 40.0
const STALL_SAUBERKEIT_FAKTOR := 2.0

const NIEDRIG := 25.0
const KRITISCH := 10.0
## Sehr durstige Pferde (<= 15) deckeln die Laune wie "erschöpft" im Web.
const DURSTIG_AB := 15.0
const DURSTIG_LAUNE_DECKEL := 39.0

const LAUNE_MIN_GEWICHT := 0.35
const LAUNE_AVG_GEWICHT := 0.65
## Bindung schiebt die Laune um bis zu ±5 (linear um die Mitte 50).
const LAUNE_BINDUNG_SPANNE := 5.0
## Bänder werden von oben geprüft: erster Eintrag mit min <= laune gewinnt.
const LAUNE_BAENDER := [
	{"id": "strahlend", "min": 80.0},
	{"id": "froh", "min": 60.0},
	{"id": "zufrieden", "min": 40.0},
	{"id": "muffig", "min": 25.0},
	{"id": "elend", "min": 0.0},
]

## Futter-Wirkung (Heu füllt satt, Obst/Gemüse macht Freude + Bindung).
const FUTTER := {
	"heu": {"hunger": 30.0, "durst": 0.0, "sauberkeit": 0.0},
	"apfel": {"hunger": 12.0, "durst": 4.0, "sauberkeit": 0.0},
	"karotte": {"hunger": 8.0, "durst": 2.0, "sauberkeit": 0.0},
}
const TRAENKEN_DELTA := {"hunger": 0.0, "durst": 45.0, "sauberkeit": 0.0}
const STRIEGELN_DELTA := {"hunger": 0.0, "durst": 0.0, "sauberkeit": 35.0}

## Bindungs-Basen pro Aktion; der Tagesdeckel hält die Kurve ehrlich.
const BOND_BASIS := {
	"heu": 1.0,
	"apfel": 2.0,
	"karotte": 2.0,
	"traenken": 1.0,
	"striegeln": 3.0,
	"ausmisten": 2.0,
	"reiten": 4.0,
}
const BOND_TAGES_DECKEL := 12.0
## Bindung verfällt erst nach 48 h ohne Pflege, dann 1 Punkt je weiterem Tag.
const BOND_VERFALL_KARENZ_MIN := 2880.0
const BOND_VERFALL_PRO_MIN := 1.0 / 1440.0

## Bindungs-Stufen (von oben geprüft, wie LAUNE_BAENDER).
const BINDUNG_STUFEN := [
	{"id": "seelenpferd", "min": 90.0},
	{"id": "vertraut", "min": 70.0},
	{"id": "freund", "min": 45.0},
	{"id": "bekannt", "min": 20.0},
	{"id": "fremd", "min": 0.0},
]

## Ausmisten setzt den Stall wieder auf blitzblank.
const STALL_MAX := 100.0
## Stallverfall je Minute, in der mindestens ein Pferd darin schläft.
const STALL_VERFALL_PRO_MIN := 0.05


## Einzelwert nach [0, 100] klemmen; NaN/Inf/Nicht-Zahl fällt auf MIN.
static func clamp_wert(value: Variant) -> float:
	var n := _num(value)
	if is_nan(n) or is_inf(n):
		return MIN
	return minf(MAX, maxf(MIN, n))


## Alle Werte eines werte-Dictionaries klemmen (neues Dict, fehlende -> 0).
static func clamp_werte(werte: Dictionary) -> Dictionary:
	var out := {}
	for k in KEYS:
		var n := _num(werte.get(k))
		out[k] = clamp_wert(0.0 if is_nan(n) else n)
	return out


## Ein Verfalls-Tick. opts: {"schlaeft": bool, "rateMult": float,
## "stallSauberkeit": float, "sauberkeitMult": float}.
## rateMult 0.3 = Offline-Simulation (§E4-Muster). Der Stall-Dreck-Faktor
## wirkt nur IM Stall (schlaeft), der Weidezaun-Mult nur auf der Weide.
static func tick(werte: Dictionary, dt_min: float, opts: Dictionary = {}) -> Dictionary:
	var schlaeft: bool = opts.get("schlaeft") is bool and bool(opts.get("schlaeft"))
	var rates: Dictionary = RATES_SCHLAF if schlaeft else RATES_WACH
	var mult := _num_or(opts.get("rateMult"), 1.0)
	var stall := _num_or(opts.get("stallSauberkeit"), STALL_MAX)
	var out := {}
	for k in KEYS:
		var rate := float(rates[k])
		if k == "sauberkeit":
			if schlaeft and stall < STALL_DRECKIG_UNTER:
				rate *= STALL_SAUBERKEIT_FAKTOR
			elif not schlaeft:
				rate *= _num_or(opts.get("sauberkeitMult"), 1.0)
		out[k] = clamp_wert(_num(werte.get(k)) + rate * dt_min * mult)
	return out


## Abgeleitete Laune: 0.35·min + 0.65·avg der Werte, plus Bindungs-Schub
## (±5 um Bindung 50), sehr durstig (<= 15) deckelt bei 39. 0..100.
static func laune(werte: Dictionary, bindung: float = 50.0) -> float:
	var lowest := INF
	var sum := 0.0
	for k in KEYS:
		var v := _num(werte.get(k))
		lowest = minf(lowest, v)
		sum += v
	var avg := sum / KEYS.size()
	var m := LAUNE_MIN_GEWICHT * lowest + LAUNE_AVG_GEWICHT * avg
	m += (clamp_wert(bindung) - 50.0) / 50.0 * LAUNE_BINDUNG_SPANNE
	if _num(werte.get("durst")) <= DURSTIG_AB:
		m = minf(m, DURSTIG_LAUNE_DECKEL)
	return minf(MAX, maxf(MIN, m))


## Launen-Band-Id für einen Launen-Wert.
static func laune_band(laune_wert: float) -> String:
	for band: Dictionary in LAUNE_BAENDER:
		if laune_wert >= float(band["min"]):
			return band["id"]
	return "elend"


## Bindungs-Stufen-Id (fremd → seelenpferd) für einen Bindungs-Wert.
static func bindung_stufe(bindung_wert: float) -> String:
	for stufe: Dictionary in BINDUNG_STUFEN:
		if bindung_wert >= float(stufe["min"]):
			return stufe["id"]
	return "fremd"


static func ist_niedrig(value: float) -> bool:
	return value < NIEDRIG


static func ist_kritisch(value: float) -> bool:
	return value < KRITISCH


## Füttern (heu/apfel/karotte). Unbekanntes Futter = unverändert (neues Dict).
static func fuettern(werte: Dictionary, futter_id: String) -> Dictionary:
	if not FUTTER.has(futter_id):
		return clamp_werte(werte)
	return apply_deltas(werte, FUTTER[futter_id])


static func traenken(werte: Dictionary) -> Dictionary:
	return apply_deltas(werte, TRAENKEN_DELTA)


static func striegeln(werte: Dictionary) -> Dictionary:
	return apply_deltas(werte, STRIEGELN_DELTA)


## Werte-Deltas mit Klemmung anwenden. Pure — neues Dict.
static func apply_deltas(werte: Dictionary, deltas: Dictionary) -> Dictionary:
	var out := {}
	for k in KEYS:
		out[k] = clamp_wert(_num(werte.get(k)) + _num(deltas.get(k, 0.0)))
	return out


## Effektiver Bindungs-Gewinn einer Aktion unterm Tagesdeckel:
## min(Basis, Rest bis BOND_TAGES_DECKEL). Klare, monotone Kurve —
## die Summe aller Tages-Gewinne läuft exakt gegen den Deckel.
static func bond_gewinn(aktion: String, bond_heute: float) -> float:
	var basis := _num(BOND_BASIS.get(aktion, 0.0))
	var rest := maxf(0.0, BOND_TAGES_DECKEL - maxf(0.0, bond_heute))
	return minf(basis, rest)


## Bindung nach einer Pflege-Aktion fortschreiben. Pure — liefert
## {"bindung": f, "bondHeute": f, "gewinn": f}; `tag_gewechselt` setzt den
## Tageszähler vor der Buchung zurück (Aufrufer vergleicht bondTag).
static func bond_nach_aktion(
	bindung: float, bond_heute: float, aktion: String, tag_gewechselt := false
) -> Dictionary:
	var heute := 0.0 if tag_gewechselt else maxf(0.0, _num(bond_heute))
	var gewinn := bond_gewinn(aktion, heute)
	return {
		"bindung": clamp_wert(_num(bindung) + gewinn),
		"bondHeute": heute + gewinn,
		"gewinn": gewinn,
	}


## Bindungs-Verfall über dt_min Minuten OHNE Pflege: 48 h Karenz, danach
## 1 Punkt je Tag. `seit_pflege_min` = Minuten seit der letzten Aktion
## VOR diesem Zeitraum (0 = frisch gepflegt).
static func bond_verfall(bindung: float, seit_pflege_min: float, dt_min: float) -> float:
	var start := maxf(0.0, _num(seit_pflege_min))
	var ende := start + maxf(0.0, dt_min)
	var straf_min := maxf(0.0, ende - BOND_VERFALL_KARENZ_MIN)
	straf_min -= maxf(0.0, start - BOND_VERFALL_KARENZ_MIN)
	return clamp_wert(_num(bindung) - straf_min * BOND_VERFALL_PRO_MIN)


## Stall-Sauberkeit nach dt_min Minuten mit schlafenden Pferden.
static func stall_tick(stall_sauberkeit: float, dt_min: float, pferde_im_stall: int) -> float:
	if pferde_im_stall <= 0:
		return clamp_wert(stall_sauberkeit)
	return clamp_wert(_num(stall_sauberkeit) - STALL_VERFALL_PRO_MIN * dt_min)


## Ausmisten: Stall wieder auf 100.
static func ausmisten() -> float:
	return STALL_MAX


## Bindungs-Perks fürs Reiten (ride_feel konsumiert das): hohe Bindung gibt
## bis zu +6 % Galopp-Tempo und +25 % Ausdauer-Regeneration (linear ab 45).
static func reit_perks(bindung: float) -> Dictionary:
	var b := clamp_wert(bindung)
	var f := maxf(0.0, (b - 45.0) / 55.0)
	return {"tempo_mult": 1.0 + 0.06 * f, "ausdauer_regen_mult": 1.0 + 0.25 * f}


## Lenientes Zahlenlesen (JS-Number()-Nachbildung wie in stats.gd).
static func _num(value: Variant) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		TYPE_BOOL:
			return 1.0 if value else 0.0
		_:
			return NAN


static func _num_or(value: Variant, fallback: float) -> float:
	var n := _num(value)
	return fallback if is_nan(n) else n
