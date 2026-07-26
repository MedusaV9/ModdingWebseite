class_name RanchBauEffekte
extends RefCounted
## Spürbarer Nutzen der Ausbaustufen (RW-4, IDEAS-3 §6) — PURE Ableitungen
## aus dem ranch.bau-Stand + Balance. Jede Stufe ändert Optik UND Spiel:
## mehr Boxen = mehr Pferde, Reithalle = Training bei Regen, Führanlage =
## passives Training, Waschplatz = schnellere Pflege, Tribüne = Publikum,
## Heulager = Vorratshaltung. Alle Werte kommen aus bau_balance.json
## („effekte“) — Content-Pack-updatebar, KEIN Code-Wissen über Zahlen.


## Stufen-Wert einer Effekt-Reihe: reihe[stufe-1], geklemmt; Stufe 0
## (nicht gebaut) liefert den Fallback.
static func stufen_wert(
	balance: Dictionary, anlage_id: String, effekt: String, stufe: int, fallback: Variant
) -> Variant:
	if stufe <= 0:
		return fallback
	var reihe: Variant = _dict(_effekte(balance), anlage_id).get(effekt)
	if not (reihe is Array) or (reihe as Array).is_empty():
		return fallback
	return (reihe as Array)[clampi(stufe, 1, (reihe as Array).size()) - 1]


## Maximale Pferdezahl: Stallboxen-Kapazität 2/4/6/8 (Basis 2 ohne Boxen).
static func boxen_kapazitaet(bau: Dictionary, balance: Dictionary) -> int:
	var basis := int(_num(_effekte(balance).get("boxen_kapazitaet_basis"), 2.0))
	var stufe := RanchBauState.anlage_stufe(bau, "stallboxen")
	return int(_num(stufen_wert(balance, "stallboxen", "kapazitaet", stufe, basis), 2.0))


## Hunger-Verfalls-Multiplikator (Weide Stufe 2: sattes Gras ×0,85).
static func hunger_mult(bau: Dictionary, balance: Dictionary) -> float:
	var stufe := RanchBauState.anlage_stufe(bau, "weide")
	return _num(stufen_wert(balance, "weide", "hunger_mult", stufe, 1.0), 1.0)


## Laune-Bonus pro Stunde bis zum Deckel 70 (Weide Stufe 3: Kräuterweide).
static func laune_bonus_pro_h(bau: Dictionary, balance: Dictionary) -> int:
	var stufe := RanchBauState.anlage_stufe(bau, "weide")
	return int(_num(stufen_wert(balance, "weide", "laune_bonus_h", stufe, 0), 0.0))


## Sauberkeits-Verfalls-Multiplikator (Weidezaun 0,8/0,7/0,6; ohne 1,0).
static func sauberkeit_mult(bau: Dictionary, balance: Dictionary) -> float:
	var stufe := RanchBauState.anlage_stufe(bau, "weidezaun")
	return _num(stufen_wert(balance, "weidezaun", "sauberkeit_mult", stufe, 1.0), 1.0)


## Durst-Verfalls-Multiplikator (Wasserstelle ×0,7).
static func durst_mult(bau: Dictionary, balance: Dictionary) -> float:
	var stufe := RanchBauState.anlage_stufe(bau, "wasserstelle")
	return _num(stufen_wert(balance, "wasserstelle", "durst_mult", stufe, 1.0), 1.0)


## Selbsttränke aktiv? (Wasserstelle Stufe 2: Weidepferde trinken selbst.)
static func selbsttraenke_aktiv(bau: Dictionary, balance: Dictionary) -> bool:
	var stufe := RanchBauState.anlage_stufe(bau, "wasserstelle")
	return bool(stufen_wert(balance, "wasserstelle", "selbsttraenke", stufe, false))


## Heulager-Kapazität in Ballen (12/24/48; Basis 8 ohne Lager).
static func heu_kapazitaet(bau: Dictionary, balance: Dictionary) -> int:
	var basis := int(_num(_effekte(balance).get("heu_kapazitaet_basis"), 8.0))
	var stufe := RanchBauState.anlage_stufe(bau, "heulager")
	return int(_num(stufen_wert(balance, "heulager", "heu_kapazitaet", stufe, basis), 8.0))


## Striegel-Wert pro Pflege (Waschplatz: +50 statt +35 Basis).
static func striegel_wert(bau: Dictionary, balance: Dictionary) -> int:
	var basis := int(_num(_effekte(balance).get("striegel_wert_basis"), 35.0))
	var stufe := RanchBauState.anlage_stufe(bau, "waschplatz")
	return int(_num(stufen_wert(balance, "waschplatz", "striegel_wert", stufe, basis), 35.0))


## Warmwasser-Bonus-Bindung 1×/Tag/Pferd (Waschplatz Stufe 2).
static func warmwasser_bonus(bau: Dictionary, balance: Dictionary) -> int:
	var stufe := RanchBauState.anlage_stufe(bau, "waschplatz")
	return int(_num(stufen_wert(balance, "waschplatz", "warmwasser_bonus", stufe, 0), 0.0))


## Passives Führanlagen-Training: Stat-XP pro Tag (0/40/60/80).
static func fuehranlage_xp_pro_tag(bau: Dictionary, balance: Dictionary) -> int:
	var stufe := RanchBauState.anlage_stufe(bau, "fuehranlage")
	return int(_num(stufen_wert(balance, "fuehranlage", "xp_pro_tag", stufe, 0), 0.0))


## Training trotz Regen? (Reithalle ab Stufe 1.)
static func training_bei_regen(bau: Dictionary, balance: Dictionary) -> bool:
	var stufe := RanchBauState.anlage_stufe(bau, "reithalle")
	return bool(stufen_wert(balance, "reithalle", "regen_training", stufe, false))


## Dressur-XP-Multiplikator der Reithalle (+20 %).
static func dressur_xp_mult(bau: Dictionary, balance: Dictionary) -> float:
	var stufe := RanchBauState.anlage_stufe(bau, "reithalle")
	return _num(stufen_wert(balance, "reithalle", "dressur_xp_mult", stufe, 1.0), 1.0)


## Trainings-Coin-Multiplikator des Parcours (×1,1 — Bestand Reitplatz).
static func parcours_coin_mult(bau: Dictionary, balance: Dictionary) -> float:
	var stufe := RanchBauState.anlage_stufe(bau, "parcours")
	return _num(stufen_wert(balance, "parcours", "coin_mult", stufe, 1.0), 1.0)


## NPC-Zuschauer bei Heim-Schauen (Tribüne 6/12; 0 ohne).
static func tribuene_zuschauer(bau: Dictionary, balance: Dictionary) -> int:
	var stufe := RanchBauState.anlage_stufe(bau, "tribuene")
	return int(_num(stufen_wert(balance, "tribuene", "zuschauer", stufe, 0), 0.0))


## Heimturnier-Gold-Multiplikator (Tribüne Stufe 2: +15 %).
static func heim_gold_mult(bau: Dictionary, balance: Dictionary) -> float:
	var stufe := RanchBauState.anlage_stufe(bau, "tribuene")
	return _num(stufen_wert(balance, "tribuene", "heim_gold_mult", stufe, 1.0), 1.0)


## Stilpunkte der Deko: je `deko_stil_pro` Objekte +1, Deckel `deko_stil_max`.
static func deko_stilpunkte(bau: Dictionary, balance: Dictionary) -> int:
	var eff := _effekte(balance)
	var pro := maxi(1, int(_num(eff.get("deko_stil_pro"), 5.0)))
	var deckel := maxi(0, int(_num(eff.get("deko_stil_max"), 10.0)))
	var defs := RanchBauKatalog.defs(balance)
	var anzahl := 0
	for eintrag: Variant in bau.get("items", []):
		if not (eintrag is Dictionary):
			continue
		var def := _dict(defs, str(eintrag.get("item", "")))
		if str(def.get("kategorie", "")) == "deko":
			anzahl += 1
	return mini(deckel, anzahl / pro)


## Zusammenfassung aller Effekte (fürs Ausbau-Panel/HUD).
static func zusammenfassung(bau: Dictionary, balance: Dictionary) -> Dictionary:
	return {
		"boxen_kapazitaet": boxen_kapazitaet(bau, balance),
		"hunger_mult": hunger_mult(bau, balance),
		"laune_bonus_pro_h": laune_bonus_pro_h(bau, balance),
		"sauberkeit_mult": sauberkeit_mult(bau, balance),
		"durst_mult": durst_mult(bau, balance),
		"selbsttraenke": selbsttraenke_aktiv(bau, balance),
		"heu_kapazitaet": heu_kapazitaet(bau, balance),
		"striegel_wert": striegel_wert(bau, balance),
		"warmwasser_bonus": warmwasser_bonus(bau, balance),
		"fuehranlage_xp_pro_tag": fuehranlage_xp_pro_tag(bau, balance),
		"training_bei_regen": training_bei_regen(bau, balance),
		"dressur_xp_mult": dressur_xp_mult(bau, balance),
		"parcours_coin_mult": parcours_coin_mult(bau, balance),
		"tribuene_zuschauer": tribuene_zuschauer(bau, balance),
		"heim_gold_mult": heim_gold_mult(bau, balance),
		"deko_stilpunkte": deko_stilpunkte(bau, balance),
	}


static func _effekte(balance: Dictionary) -> Dictionary:
	return _dict(balance, "effekte")


static func _dict(source: Dictionary, key: String) -> Dictionary:
	return source[key] if source.get(key) is Dictionary else {}


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
