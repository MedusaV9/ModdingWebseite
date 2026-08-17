class_name RanchRassen
extends RefCounted
## Pferde-Rassen + Individuen (RW-2, RANCH-DLC-IDEAS-3 Kap. 1) — PURE.
## Rassen-Basiswerte/Preise sind DATEN (rassen.json, Balance-Namespace
## "ranchplay" wie wirtschaft.json); Eigenheiten/Charakterzuege sind
## KONSTANTEN mit spuerbaren Effekten, die ride_feel/horse_levels/
## horse_care konsumieren. Erzeugung neuer Pferde ist DETERMINISTISCH
## aus einem Seed (gleicher Seed = gleiches Pferd, Tests verlassen sich
## darauf).
##
## Gen-Modell (Kap. 1.2): drei Gen-Orte + Glitzer, je zwei Allele.
##   G Grundfarbe  B > F > Z (Dominanz von links)
##   H Aufhellung  h0 / h+ (unvollstaendig dominant)
##   S Schecke     Sch (dominant) / s0
##   ✨ Glitzer    g0 / gx (rezessiv; "gx" statt Emoji — Daten, nie UI)

const BALANCE_PATH := "res://scripts/ranch/data/rassen.json"
const BALANCE_NAMESPACE := "ranchplay"

const STAT_KEYS: Array[String] = ["tempo", "ausdauer", "sprungkraft", "wendigkeit", "gelassenheit"]
const RARITAETEN: Array[String] = ["start", "haeufig", "ungewoehnlich", "selten", "legendaer"]

## Allele je Gen-Ort; Reihenfolge = Dominanz (G) bzw. nur Aufzaehlung.
const GEN_G: Array[String] = ["B", "F", "Z"]
const GEN_H: Array[String] = ["h0", "h+"]
const GEN_S: Array[String] = ["s0", "Sch"]
const GEN_GLITZER: Array[String] = ["g0", "gx"]

## Grundfarbe (dominantestes G-Allel) × Anzahl h+ → Fellfarben-Id.
const FARBE_TABELLE := {
	"B": ["braun", "palomino", "weiss"],
	"F": ["fuchs", "apricot", "weiss"],
	"Z": ["schwarz", "rauchgrau", "weiss"],
}

const MAEHNENFORMEN: Array[String] = ["glatt", "wellig", "puschel"]
const ABZEICHEN_MERKMALE: Array[String] = ["blesse", "stern", "schnippe"]
## Abzeichen-Chance fuer Laden-/Wildpferde ohne Eltern (Zucht: horse_breeding).
const ABZEICHEN_CHANCE_NEU := 0.18

## Charakterzuege (Kap. 1.3) — jedes Pferd hat 2; Effekte docken an
## bestehende Konstanten an. Zug 2 zeigt sich erst ab Bindung >= 45.
const CHARAKTERZUEGE: Array[String] = [
	"mutig",
	"scheu",
	"verfressen",
	"verspielt",
	"gelassen",
	"fleissig",
	"eitel",
	"anhaenglich",
	"stur",
	"neugierig",
]
const CHARAKTER_EFFEKTE := {
	"mutig": {"scheu_mult": 0.0, "sprungfenster_bonus_ms": 30.0},
	"scheu": {"scheu_mult": 1.0, "striegel_bindung_mult": 1.5},
	"verfressen": {"futter_hunger_mult": 1.3, "hunger_rate_pro_min": -0.30},
	"verspielt": {"stern_xp_mult": 1.15, "spielball_laune": 5.0},
	"gelassen": {"ausdauer_regen_mult": 1.1, "nick_amp_mult": 0.8},
	"fleissig": {"frische_verbrauch": 30.0},
	"eitel": {"stilpunkte_mult": 1.1, "sauberkeit_verfall_mult": 1.2},
	"anhaenglich": {"bond_tagesdeckel": 14.0},
	"stur": {"erster_wechsel_verzoegerung_s": 0.4, "gelassenheit_statxp_mult": 1.2},
	"neugierig": {"sammelitem_chance": 0.35},
}

## Rassen-Eigenheiten (Kap. 1.1, Spalte "Eigenheit") — spuerbare Effekte.
const EIGENHEIT_EFFEKTE := {
	"allrounder": {},
	"slalom_ass": {"schmale_tore": true},
	"kuschelherz": {"bindung_mult": 1.25, "bond_tagesdeckel": 15.0},
	"taktgefuehl": {"takt_fenster_mult": 1.2},
	"langer_antritt": {"kick_dauer_s": 1.2},
	"gelaende_profi": {"gelaende_malus_mult": 0.5},
	"unerschrocken": {"scheu_mult": 0.0, "satteltaschen_bonus": 1},
	"sprunggefuehl": {"sprungfenster_bonus_ms": 50.0},
	"trail_praezision": {"rueckwaerts_raster": true},
	"toelt": {"toelt": true},
	"schauliebling": {"stilpunkte_mult": 1.1},
	"glitzerfell": {"glitzer": true},
}


## Effektive Balance: eingebautes JSON + Registry-Override (Deep-Merge,
## Muster RanchWirtschaft.load_balance). registry=null → Autoload.
static func load_balance(registry: Object = null) -> Dictionary:
	var balance := RanchWirtschaft.read_json(BALANCE_PATH)
	var reg := registry
	if reg == null:
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			reg = (loop as SceneTree).root.get_node_or_null("ContentRegistry")
	if reg != null and reg.has_method("get_balance"):
		var overrides: Variant = reg.get_balance(BALANCE_NAMESPACE, {})
		if overrides is Dictionary and not (overrides as Dictionary).is_empty():
			_merge(balance, overrides)
	return balance


static func rassen_liste(balance: Dictionary) -> Array:
	var raw: Variant = balance.get("rassen")
	return raw if raw is Array else []


## Rassen-Eintrag per Id; unbekannt → Puschelhufer (Startpferd).
static func rasse(balance: Dictionary, rasse_id: String) -> Dictionary:
	var fallback := {}
	for eintrag: Variant in rassen_liste(balance):
		if not (eintrag is Dictionary):
			continue
		if str(eintrag.get("id", "")) == rasse_id:
			return eintrag
		if str(eintrag.get("id", "")) == "puschelhufer":
			fallback = eintrag
	return fallback


## Basiswerte (1–20) einer Rasse als Stat-Dictionary.
static func basis_stats(rassen_eintrag: Dictionary) -> Dictionary:
	var out := {}
	for k in STAT_KEYS:
		out[k] = clampi(int(_num(rassen_eintrag.get(k), 10.0)), 1, 20)
	return out


static func eigenheit_effekte(eigenheit_id: String) -> Dictionary:
	var raw: Variant = EIGENHEIT_EFFEKTE.get(eigenheit_id, {})
	return raw if raw is Dictionary else {}


static func charakter_effekte(zug_id: String) -> Dictionary:
	var raw: Variant = CHARAKTER_EFFEKTE.get(zug_id, {})
	return raw if raw is Dictionary else {}


## Neues Individuum DETERMINISTISCH aus Seed: alle additiven DLC-Felder
## fuers Pferde-Dict (RanchPlaySlices.neues_pferd mergt sie). Gleicher
## Seed + gleiche Rasse ⇒ identisches Pferd.
static func neues_individuum(rasse_id: String, seed_wert: int, balance: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%d" % [rasse_id, seed_wert])
	var eintrag := rasse(balance, rasse_id)
	var eff_id := str(eintrag.get("id", "puschelhufer"))
	var gene := _wuerfle_gene(rng, eff_id)
	var varianz := _num(balance.get("statur_varianz"), 0.08)
	var groesse := _num(eintrag.get("groesse"), 1.0) * (1.0 + rng.randf_range(-varianz, varianz))
	var pitch_min := _num(balance.get("stimme_pitch_min"), 0.85)
	var pitch_max := _num(balance.get("stimme_pitch_max"), 1.15)
	return {
		"rasse": eff_id,
		"gene": gene,
		"farbe": fellfarbe_aus_genen(gene),
		"abzeichen": _wuerfle_abzeichen(rng),
		"charakter": _wuerfle_charakter(rng),
		"groesse": snappedf(groesse, 0.001),
		"stimmPitch": snappedf(rng.randf_range(pitch_min, pitch_max), 0.001),
		"phasenOffset": snappedf(rng.randf(), 0.001),
		"stats": basis_stats(eintrag),
		"alter": "ausgewachsen",
		"eltern": [],
		"geborenAm": 0,
	}


## Fellfarben-Id aus den Genen (Kap. 1.2): dominanteste Grundfarbe,
## unvollstaendig dominante Aufhellung (1× hell, 2× weiss).
static func fellfarbe_aus_genen(gene: Dictionary) -> String:
	var g := allele(gene, "g", "B")
	var basis := "Z"
	for kandidat in GEN_G:
		if g.has(kandidat):
			basis = kandidat
			break
	var hell := allele(gene, "h", "h0").count("h+")
	var reihe: Array = FARBE_TABELLE[basis]
	return str(reihe[clampi(hell, 0, 2)])


## Schecken-Overlay, wenn mindestens ein dominantes Sch-Allel da ist.
static func ist_schecke(gene: Dictionary) -> bool:
	return allele(gene, "s", "s0").has("Sch")


## Glitzer nur reinerbig (gx/gx) — Sternschnuppler sind es immer.
static func ist_glitzer(gene: Dictionary) -> bool:
	return allele(gene, "glitzer", "g0").count("gx") >= 2


## Allel-Paar eines Gen-Orts defensiv lesen (kaputt → [fallback ×2]).
static func allele(gene: Dictionary, ort: String, fallback: String) -> Array:
	var raw: Variant = gene.get(ort)
	if raw is Array and (raw as Array).size() == 2:
		return raw
	return [fallback, fallback]


## ------------------------------------------------------------ Wuerfel-Helfer


static func _wuerfle_gene(rng: RandomNumberGenerator, rasse_id: String) -> Dictionary:
	var gene := {
		"g": [GEN_G[rng.randi_range(0, 2)], GEN_G[rng.randi_range(0, 2)]],
		"h": [_chance_allel(rng, 0.25, "h+", "h0"), _chance_allel(rng, 0.25, "h+", "h0")],
		"s": [_chance_allel(rng, 0.2, "Sch", "s0"), _chance_allel(rng, 0.2, "Sch", "s0")],
		"glitzer": [_chance_allel(rng, 0.08, "gx", "g0"), _chance_allel(rng, 0.08, "gx", "g0")],
	}
	if rasse_id == "sternschnuppler":
		gene["glitzer"] = ["gx", "gx"]
	return gene


static func _chance_allel(
	rng: RandomNumberGenerator, chance: float, treffer: String, sonst: String
) -> String:
	return treffer if rng.randf() < chance else sonst


static func _wuerfle_abzeichen(rng: RandomNumberGenerator) -> Dictionary:
	var out := {"maehnenform": MAEHNENFORMEN[rng.randi_range(0, MAEHNENFORMEN.size() - 1)]}
	for merkmal in ABZEICHEN_MERKMALE:
		out[merkmal] = rng.randf() < ABZEICHEN_CHANCE_NEU
	var socken: Array = []
	for _i in 4:
		socken.append(1 if rng.randf() < ABZEICHEN_CHANCE_NEU else 0)
	out["socken"] = socken
	return out


## 2 verschiedene Zuege: [0] steht am Verkaufsschild, [1] zeigt sich
## erst ab Bindung >= 45 ("freund").
static func _wuerfle_charakter(rng: RandomNumberGenerator) -> Array:
	var erster := CHARAKTERZUEGE[rng.randi_range(0, CHARAKTERZUEGE.size() - 1)]
	var zweiter := erster
	while zweiter == erster:
		zweiter = CHARAKTERZUEGE[rng.randi_range(0, CHARAKTERZUEGE.size() - 1)]
	return [erster, zweiter]


static func _merge(ziel: Dictionary, quelle: Dictionary) -> void:
	for k: Variant in quelle.keys():
		if ziel.get(k) is Dictionary and quelle[k] is Dictionary:
			_merge(ziel[k], quelle[k])
		else:
			ziel[k] = quelle[k]


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
