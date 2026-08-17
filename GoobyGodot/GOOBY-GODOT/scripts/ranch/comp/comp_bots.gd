class_name RanchCompBots
extends RefCounted
## Bot-Gegner der Turnier-Liga (RW-5, IDEAS-1 E1 + IDEAS-3 Kap. 5) — PURE.
## Liebevoll benannte Reiter mit eigenen Pferden und Persönlichkeit
## ("Rosalinde auf Donnerkeks"). Deterministisch: gleicher Seed = gleiches
## Ergebnis (GoobyRng); Können kommt aus dem Klassen-Band der Balance
## (KEIN Gummiband gegen den Spieler — Bots würfeln ihren Lauf, bevor der
## Spieler reitet). Talent 0..1 legt den Bot INS Band, die Lieblings-
## Disziplin gibt ±, damit jede Klasse Gesichter mit Stärken hat.
## Die Simulation rechnet durch DIESELBEN Wertungsmodule wie der Spieler.

const Katalog := preload("res://scripts/ranch/comp/comp_katalog.gd")
const WSpringen := preload("res://scripts/ranch/comp/wertung/wertung_springen.gd")
const WDressur := preload("res://scripts/ranch/comp/wertung/wertung_dressur.gd")
const WGelaende := preload("res://scripts/ranch/comp/wertung/wertung_gelaende.gd")
const WRennen := preload("res://scripts/ranch/comp/wertung/wertung_rennen.gd")
const WTrail := preload("res://scripts/ranch/comp/wertung/wertung_trail.gd")
const WSchau := preload("res://scripts/ranch/comp/wertung/wertung_schau.gd")
const WTonnen := preload("res://scripts/ranch/comp/wertung/wertung_tonnen.gd")

## Lieblings-Disziplin macht spürbar besser, der Rest minimal schlechter.
const LIEBLING_BONUS := 0.07
const FREMD_MALUS := 0.02
## Spieler-Proxy (Fairness-Tests): Können = 0,55·Fahrqualität + 0,45·Stats.
const SPIELER_FAHR_GEWICHT := 0.55
const SPIELER_STAT_GEWICHT := 0.45
## Grundzeit einer Oval-Runde (s) fürs Rennen (3 Runden, Kap. 5.2 Nr. 4).
## Geeicht auf RW-2s Reitphysik: ~204-m-Oval (RcompKurs), Galopp zehrt
## Ausdauer → nachhaltiges Spielertempo ≈ 6 m/s ≈ 34 s je Runde.
const RENNEN_RUNDE_BASIS_S := 34.0

## Das Fahrerlager: Namen im GOOBY-Humor, jedes Pferd hat Rasse + Farbe
## (RanchPferd.FELL-Ids), zug = Persönlichkeit (Text + Podium-Gag).
const ROSTER: Array[Dictionary] = [
	{
		"id": "rosalinde",
		"name": "Rosalinde",
		"pferd": "Donnerkeks",
		"rasse": "donnerbommel",
		"farbe": "braun",
		"zug": "gemuetlich",
		"talent": 0.5,
		"liebling": "springen",
	},
	{
		"id": "fjodor",
		"name": "Fjodor Streusel",
		"pferd": "Zimtwölkchen",
		"rasse": "wolkentraber",
		"farbe": "palomino",
		"zug": "vertraeumt",
		"talent": 0.72,
		"liebling": "dressur",
	},
	{
		"id": "waltraud",
		"name": "Oma Waltraud",
		"pferd": "Blitzgurke",
		"rasse": "flitzewind",
		"farbe": "fuchs",
		"zug": "rasant",
		"talent": 0.9,
		"liebling": "rennen",
	},
	{
		"id": "bodo",
		"name": "Bäckermeister Bodo",
		"pferd": "Brezelchen",
		"rasse": "puschelhufer",
		"farbe": "braun",
		"zug": "verfressen",
		"talent": 0.28,
		"liebling": "schau",
	},
	{
		"id": "frieda",
		"name": "Frieda Fussel",
		"pferd": "Kartoffelmus",
		"rasse": "westernwuschel",
		"farbe": "schecke",
		"zug": "ordentlich",
		"talent": 0.45,
		"liebling": "trail",
	},
	{
		"id": "kunibert",
		"name": "Ritter Kunibert",
		"pferd": "Turboschnecke",
		"rasse": "moosmaehne",
		"farbe": "schwarz",
		"zug": "heldenhaft",
		"talent": 0.55,
		"liebling": "gelaende",
	},
	{
		"id": "paula",
		"name": "Postbotin Paula",
		"pferd": "Paketchen",
		"rasse": "knuffpony",
		"farbe": "fuchs",
		"zug": "flink",
		"talent": 0.62,
		"liebling": "tonnen",
	},
	{
		"id": "knuff",
		"name": "Professor Knuff",
		"pferd": "Fußnote",
		"rasse": "toelterle",
		"farbe": "rauchgrau",
		"zug": "gruebelnd",
		"talent": 0.66,
		"liebling": "dressur",
	},
	{
		"id": "miapia",
		"name": "Mia und Pia",
		"pferd": "Doppeldecker",
		"rasse": "zottelgnuff",
		"farbe": "braun",
		"zug": "kichernd",
		"talent": 0.4,
		"liebling": "rennen",
	},
	{
		"id": "gustav",
		"name": "Gärtner Gustav",
		"pferd": "Rasenmäher",
		"rasse": "moosmaehne",
		"farbe": "apricot",
		"zug": "geerdet",
		"talent": 0.35,
		"liebling": "gelaende",
	},
	{
		"id": "klara",
		"name": "Königin Klara",
		"pferd": "Glitzerpüppi",
		"rasse": "miniknopf",
		"farbe": "weiss",
		"zug": "majestaetisch",
		"talent": 0.82,
		"liebling": "schau",
	},
	{
		"id": "hein",
		"name": "Hufschmied Hein",
		"pferd": "Amboss",
		"rasse": "federsprung",
		"farbe": "schwarz",
		"zug": "felsenruhig",
		"talent": 0.76,
		"liebling": "springen",
	},
]


static func bot(id: String) -> Dictionary:
	for eintrag in ROSTER:
		if str(eintrag.get("id", "")) == id:
			return eintrag
	return {}


## Können eines Bots in Klasse×Disziplin: Talent legt ihn ins Klassen-Band,
## die Lieblings-Disziplin gibt +0,07, fremde −0,02. Geklemmt [0,05, 0,98].
static func koennen(
	balance: Dictionary, eintrag: Dictionary, klasse: String, disz: String
) -> float:
	var band := Katalog.bot_band(balance, klasse)
	var basis := lerpf(
		float(band[0]), float(band[1]), clampf(_num(eintrag.get("talent"), 0.5), 0.0, 1.0)
	)
	if str(eintrag.get("liebling", "")) == disz:
		basis += LIEBLING_BONUS
	else:
		basis -= FREMD_MALUS
	return clampf(basis, 0.05, 0.98)


## Das Starterfeld einer Klasse: `anzahl` Bots, deterministisch aus dem
## Seed gezogen (Fisher-Yates über GoobyRng) — jede Woche andere Gesichter.
static func starterfeld(
	balance: Dictionary, klasse: String, disz: String, seed_wert: int, anzahl := 5
) -> Array:
	var rng := GoobyRng.new(seed_wert)
	var indices: Array = range(ROSTER.size())
	for i in range(indices.size() - 1, 0, -1):
		var j := int(rng.next() * (i + 1))
		var tausch: Variant = indices[i]
		indices[i] = indices[j]
		indices[j] = tausch
	var feld: Array = []
	for i in mini(anzahl, indices.size()):
		var eintrag: Dictionary = ROSTER[int(indices[i])]
		var starter := eintrag.duplicate(true)
		starter["koennen"] = koennen(balance, eintrag, klasse, disz)
		feld.append(starter)
	return feld


## Spieler-Proxy fürs Fairness-Testen: Können aus Fahrqualität (0..1,
## wie sauber jemand reitet) + den Disziplin-Stats des Pferds (1–20).
static func spieler_koennen(
	balance: Dictionary, disz: String, stats: Dictionary, fahr: float
) -> float:
	var stat_keys: Variant = Katalog.disziplin(balance, disz).get("stats", [])
	var summe := 0.0
	var anzahl := 0
	if stat_keys is Array:
		for key: Variant in stat_keys:
			summe += clampf(_num(stats.get(str(key)), 10.0), 1.0, 20.0)
			anzahl += 1
	var stat_norm := 0.474 if anzahl == 0 else ((summe / anzahl) - 1.0) / 19.0
	return clampf(
		SPIELER_FAHR_GEWICHT * clampf(fahr, 0.0, 1.0) + SPIELER_STAT_GEWICHT * stat_norm, 0.0, 1.0
	)


## Ein kompletter simulierter Lauf durch die ECHTEN Wertungsmodule.
## → {"wert": float, "zeit_s": float, "detail": Dictionary}; "wert" ist
## bei Punkte-Disziplinen höher = besser, bei Zeit-Disziplinen kleiner.
static func simuliere_lauf(
	balance: Dictionary, disz: String, klasse: String, koennen_wert: float, seed_wert: int
) -> Dictionary:
	var rng := GoobyRng.new(seed_wert)
	var k := clampf(koennen_wert, 0.0, 1.0)
	match disz:
		"springen":
			return _sim_springen(balance, klasse, k, rng)
		"dressur":
			return _sim_dressur(k, rng)
		"gelaende":
			return _sim_gelaende(balance, klasse, k, rng)
		"rennen":
			return _sim_rennen(k, rng)
		"trail":
			return _sim_trail(k, rng)
		"schau":
			return _sim_schau(k, rng)
		"tonnen":
			return _sim_tonnen(klasse, k, rng)
	return {"wert": 0.0, "zeit_s": 0.0, "detail": {}}


## ---------------------------------------------- Disziplin-Simulationen


static func _sim_springen(
	balance: Dictionary, klasse: String, k: float, rng: GoobyRng
) -> Dictionary:
	var n := WSpringen.hindernis_anzahl(klasse)
	var fehler := pow(1.0 - k, 1.6)
	var abwuerfe := _binomial(rng, n, fehler * 0.38)
	var verweigerungen := _binomial(rng, n, fehler * 0.05)
	var perfekte := _binomial(rng, maxi(0, n - abwuerfe), 0.15 + k * 0.5)
	var richtzeit := Katalog.richtzeit_s(balance, "springen", klasse)
	var zeit := richtzeit * (0.92 + (1.0 - k) * 0.22 + rng.next() * 0.08)
	var score := WSpringen.score(abwuerfe, verweigerungen, zeit, richtzeit, perfekte)
	return {
		"wert": float(score),
		"zeit_s": zeit,
		"detail": {"abwuerfe": abwuerfe, "verweigerungen": verweigerungen, "perfekte": perfekte},
	}


static func _sim_dressur(k: float, rng: GoobyRng) -> Dictionary:
	var punkte: Array = []
	var fehler_gesamt := 0
	for _figur in WDressur.FIGUREN.size():
		var d_mittel := (1.0 - k) * 0.8 * (0.6 + rng.next() * 0.8)
		var gangartfehler := 1 if rng.next() < (1.0 - k) * 0.3 else 0
		fehler_gesamt += gangartfehler
		punkte.append(WDressur.figur_punkte(d_mittel, gangartfehler))
	var takt := rng.next() < k * 0.85
	var gesamt := WDressur.gesamt(punkte, takt)
	return {
		"wert": gesamt,
		"zeit_s": 0.0,
		"detail": {"figuren": punkte, "takt": takt, "gangartfehler": fehler_gesamt},
	}


static func _sim_gelaende(
	balance: Dictionary, klasse: String, k: float, rng: GoobyRng
) -> Dictionary:
	var tore := WGelaende.tor_anzahl(klasse)
	var richtzeit := Katalog.richtzeit_s(balance, "gelaende", klasse)
	var zeit := richtzeit * (0.88 + (1.0 - k) * 0.3 + rng.next() * 0.08)
	var verpasst := _binomial(rng, tore, pow(1.0 - k, 2.0) * 0.12)
	var wertung := WGelaende.wertung_s(zeit, verpasst)
	return {"wert": wertung, "zeit_s": zeit, "detail": {"verpasst": verpasst, "tore": tore}}


static func _sim_rennen(k: float, rng: GoobyRng) -> Dictionary:
	var zeit := 0.0
	for _runde in WRennen.RUNDEN:
		var runde := RENNEN_RUNDE_BASIS_S * (1.14 - 0.26 * k + (rng.next() - 0.5) * 0.05)
		# Windschatten-Glück: gute Fahrer nutzen ihn öfter (−3 % auf 3 s).
		if rng.next() < 0.25 + k * 0.4:
			runde -= RENNEN_RUNDE_BASIS_S * WRennen.WINDSCHATTEN_BOOST * 0.6
		zeit += runde
	return {"wert": zeit, "zeit_s": zeit, "detail": {"runden": WRennen.RUNDEN}}


static func _sim_trail(k: float, rng: GoobyRng) -> Dictionary:
	var aufgaben: Array = []
	for _aufgabe in WTrail.AUFGABEN_ANZAHL:
		var ausgelassen := rng.next() < pow(1.0 - k, 2.5) * 0.15
		var beruehrungen := _binomial(rng, 3, (1.0 - k) * 0.42)
		aufgaben.append(WTrail.aufgabe_punkte(beruehrungen, ausgelassen))
	var zeit := 118.0 - k * 34.0 + rng.next() * 12.0
	var gesamt := WTrail.gesamt(aufgaben, zeit)
	return {"wert": float(gesamt), "zeit_s": zeit, "detail": {"aufgaben": aufgaben}}


static func _sim_schau(k: float, rng: GoobyRng) -> Dictionary:
	var pflege := clampf(52.0 + k * 42.0 + rng.next() * 8.0, 0.0, 100.0)
	var stil := clampf(24.0 + k * 62.0 + rng.next() * 12.0, 0.0, 100.0)
	var treffer := _binomial(rng, WSchau.KUER_KOMMANDOS, 0.3 + k * 0.62)
	var gesamt := WSchau.gesamt(pflege, stil, WSchau.kuer(treffer))
	return {
		"wert": gesamt,
		"zeit_s": 0.0,
		"detail": {"pflege": pflege, "stil": stil, "kuer_treffer": treffer},
	}


static func _sim_tonnen(klasse: String, k: float, rng: GoobyRng) -> Dictionary:
	var ideal := WTonnen.idealzeit(klasse)
	var zeit := ideal * (0.94 + (1.0 - k) * 0.3 + rng.next() * 0.08)
	var umgeworfen := _binomial(rng, WTonnen.TONNEN_ANZAHL, pow(1.0 - k, 2.0) * 0.25)
	var wertung := WTonnen.wertung_s(zeit, umgeworfen)
	return {"wert": wertung, "zeit_s": zeit, "detail": {"umgeworfen": umgeworfen}}


## ---------------------------------------------------------------- Helfer


## Binomialzug: n Versuche mit Wahrscheinlichkeit p (deterministisch).
static func _binomial(rng: GoobyRng, n: int, p: float) -> int:
	var treffer := 0
	var wahrscheinlichkeit := clampf(p, 0.0, 1.0)
	for _i in maxi(0, n):
		if rng.next() < wahrscheinlichkeit:
			treffer += 1
	return treffer


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
