class_name RanchWirtschaft
extends RefCounted
## Ranch-Wirtschaft (RANCH-2) — PURE Logik über dem `ranch.wirtschaft`-
## Unterschlüssel (Struktur: RanchPlaySlices). Preise/Erträge sind DATEN
## (wirtschaft.json) und über den Balance-Namespace "ranchplay" der
## ContentRegistry Content-Pack-updatebar (Muster = GobnomData).
##
## Alle Funktionen sind static und pure: wirtschaft/coins rein, NEUE
## Strukturen raus ({"ok": bool, "wirtschaft": Dictionary, "coins": int,
## "fehler": String, ...}) — der Aufrufer bucht das Ergebnis in GameState.

const BALANCE_PATH := "res://scripts/ranch/data/wirtschaft.json"
const BALANCE_NAMESPACE := "ranchplay"

const GEAR_SLOTS: Array[String] = ["sattel", "decke", "halfter"]
const AUSBAU_IDS: Array[String] = ["boxen2", "boxen3", "reitplatz", "weidezaun"]


## Effektive Balance: eingebautes JSON + Registry-Override (Deep-Merge).
## registry=null → Autoload /root/ContentRegistry (Duck-Typing; fehlt es,
## z. B. in Pure-Tests, gilt der eingebaute Stand).
static func load_balance(registry: Object = null) -> Dictionary:
	var balance := read_json(BALANCE_PATH)
	var reg := registry if registry != null else _autoload_registry()
	if reg != null and reg.has_method("get_balance"):
		var overrides: Variant = reg.get_balance(BALANCE_NAMESPACE, {})
		if overrides is Dictionary and not (overrides as Dictionary).is_empty():
			_deep_merge(balance, overrides)
	return balance


## Gear-Katalog: alle Slot×Farbe-Kombinationen mit Preis (gold = Multiplikator).
static func gear_katalog(balance: Dictionary) -> Array:
	var out: Array = []
	for slot: String in GEAR_SLOTS:
		for farbe: String in gear_farben(balance):
			(
				out
				. append(
					{
						"id": "%s_%s" % [slot, farbe],
						"slot": slot,
						"farbe": farbe,
						"preis": gear_preis(balance, slot, farbe),
					}
				)
			)
	return out


static func gear_farben(balance: Dictionary) -> Array:
	var farben: Variant = balance.get("gear_farben")
	return farben if farben is Array else []


static func gear_preis(balance: Dictionary, slot: String, farbe: String) -> int:
	var preise: Dictionary = _dict(balance, "preise")
	var basis := _num(_dict(preise, "gear").get(slot), 0.0)
	var mult := _num(preise.get("gold_mult"), 2.0) if farbe == "gold" else 1.0
	return maxi(0, int(round(basis * mult)))


## Ausrüstung kaufen ("sattel_rot" ...). Doppelkauf/zu teuer → ok=false.
static func gear_kaufen(
	wirtschaft: Dictionary, coins: int, id: String, bal: Dictionary
) -> Dictionary:
	var teile := id.split("_")
	if teile.size() != 2 or not GEAR_SLOTS.has(teile[0]) or not gear_farben(bal).has(teile[1]):
		return _fehler(wirtschaft, coins, "unbekannt")
	var w := wirtschaft.duplicate(true)
	var owned: Array = w["gear"]["owned"]
	if owned.has(id):
		return _fehler(wirtschaft, coins, "schonGekauft")
	var preis := gear_preis(bal, teile[0], teile[1])
	if coins < preis:
		return _fehler(wirtschaft, coins, "zuTeuer")
	owned.append(id)
	return {"ok": true, "wirtschaft": w, "coins": coins - preis, "fehler": ""}


## Gekaufte Ausrüstung einem Pferd anlegen (farbe=null legt ab).
static func gear_anlegen(
	wirtschaft: Dictionary, pferd_id: String, slot: String, farbe: Variant
) -> Dictionary:
	if not GEAR_SLOTS.has(slot):
		return _fehler(wirtschaft, 0, "unbekannt")
	var w := wirtschaft.duplicate(true)
	if farbe is String and not (w["gear"]["owned"] as Array).has("%s_%s" % [slot, farbe]):
		return _fehler(wirtschaft, 0, "nichtGekauft")
	var equipped: Dictionary = w["gear"]["equippedByHorse"]
	var eintrag: Dictionary = equipped.get(pferd_id) if equipped.get(pferd_id) is Dictionary else {}
	eintrag[slot] = farbe if farbe is String else null
	equipped[pferd_id] = eintrag
	return {"ok": true, "wirtschaft": w, "coins": 0, "fehler": ""}


## Ranch-Ausbau kaufen: boxen2/boxen3 (Stufen), reitplatz, weidezaun.
static func ausbau_kaufen(
	wirtschaft: Dictionary, coins: int, id: String, bal: Dictionary
) -> Dictionary:
	if not AUSBAU_IDS.has(id):
		return _fehler(wirtschaft, coins, "unbekannt")
	var w := wirtschaft.duplicate(true)
	var ausbau: Dictionary = w["ausbau"]
	var preis := ausbau_preis(bal, id)
	match id:
		"boxen2":
			if int(ausbau["boxen"]) >= 2:
				return _fehler(wirtschaft, coins, "schonGekauft")
		"boxen3":
			if int(ausbau["boxen"]) >= 3:
				return _fehler(wirtschaft, coins, "schonGekauft")
			if int(ausbau["boxen"]) < 2:
				return _fehler(wirtschaft, coins, "vorstufeFehlt")
		_:
			if bool(ausbau[id]):
				return _fehler(wirtschaft, coins, "schonGekauft")
	if coins < preis:
		return _fehler(wirtschaft, coins, "zuTeuer")
	match id:
		"boxen2":
			ausbau["boxen"] = 2
		"boxen3":
			ausbau["boxen"] = 3
		_:
			ausbau[id] = true
	return {"ok": true, "wirtschaft": w, "coins": coins - preis, "fehler": ""}


static func ausbau_preis(balance: Dictionary, id: String) -> int:
	return maxi(0, int(_num(_dict(_dict(balance, "preise"), "ausbau").get(id), 0.0)))


## Maximale Pferdezahl der aktuellen Boxen-Stufe.
static func boxen_kapazitaet(wirtschaft: Dictionary, balance: Dictionary) -> int:
	var stufen: Array = (
		balance.get("boxen_kapazitaet") if balance.get("boxen_kapazitaet") is Array else [2]
	)
	var stufe := clampi(int(_num(_dict(wirtschaft, "ausbau").get("boxen"), 1.0)), 1, stufen.size())
	return int(_num(stufen[stufe - 1], 2.0))


static func ausbau_aktiv(wirtschaft: Dictionary, id: String) -> bool:
	var ausbau := _dict(wirtschaft, "ausbau")
	return ausbau.get(id) is bool and ausbau[id]


## Heu kaufen (Ballenpreis aus der Balance).
static func heu_kaufen(
	wirtschaft: Dictionary, coins: int, anzahl: int, bal: Dictionary
) -> Dictionary:
	if anzahl <= 0:
		return _fehler(wirtschaft, coins, "unbekannt")
	var preis := maxi(0, int(_num(_dict(bal, "preise").get("heu_kauf"), 0.0))) * anzahl
	if coins < preis:
		return _fehler(wirtschaft, coins, "zuTeuer")
	var w := wirtschaft.duplicate(true)
	w["lager"]["heu"] = int(w["lager"]["heu"]) + anzahl
	return {"ok": true, "wirtschaft": w, "coins": coins - preis, "fehler": ""}


## Heufeld mähen: Ballen ins Lager, Feld wächst regrow_min Minuten nach.
static func heu_ernten(wirtschaft: Dictionary, now_ms: int, bal: Dictionary) -> Dictionary:
	var w := wirtschaft.duplicate(true)
	if now_ms < int(_num(w["felder"].get("heuBereitAt"), 0.0)):
		return _fehler(wirtschaft, 0, "nochNichtReif")
	var ertraege := _dict(bal, "ertraege")
	var menge := maxi(1, int(_num(ertraege.get("heu_ballen"), 3.0)))
	w["lager"]["heu"] = int(w["lager"]["heu"]) + menge
	w["felder"]["heuBereitAt"] = now_ms + int(_num(ertraege.get("heu_regrow_min"), 360.0) * 60000.0)
	return {"ok": true, "wirtschaft": w, "coins": 0, "fehler": "", "menge": menge}


## Einen Apfelbaum (0..2) pflücken; Baum trägt nach regrow_min Minuten wieder.
static func apfel_pfluecken(
	wirtschaft: Dictionary, baum_index: int, now_ms: int, bal: Dictionary
) -> Dictionary:
	var w := wirtschaft.duplicate(true)
	var baeume: Array = w["felder"]["baeume"]
	if baum_index < 0 or baum_index >= baeume.size():
		return _fehler(wirtschaft, 0, "unbekannt")
	if now_ms < int(_num(baeume[baum_index], 0.0)):
		return _fehler(wirtschaft, 0, "nochNichtReif")
	var ertraege := _dict(bal, "ertraege")
	var menge := maxi(1, int(_num(ertraege.get("apfel_pro_baum"), 2.0)))
	w["lager"]["apfel"] = int(w["lager"]["apfel"]) + menge
	baeume[baum_index] = now_ms + int(_num(ertraege.get("apfel_regrow_min"), 240.0) * 60000.0)
	return {"ok": true, "wirtschaft": w, "coins": 0, "fehler": "", "menge": menge}


## Futter fürs Füttern entnehmen (heu/apfel aus dem Ranch-Lager). Karotten
## kommen aus dem HAUPT-Inventar (inventory.food.carrot) — dafür liefert
## karotte_nehmen() nur die Buchungs-Anweisung.
static func futter_nehmen(wirtschaft: Dictionary, futter_id: String) -> Dictionary:
	if futter_id != "heu" and futter_id != "apfel":
		return _fehler(wirtschaft, 0, "unbekannt")
	var w := wirtschaft.duplicate(true)
	if int(w["lager"][futter_id]) <= 0:
		return _fehler(wirtschaft, 0, "lagerLeer")
	w["lager"][futter_id] = int(w["lager"][futter_id]) - 1
	return {"ok": true, "wirtschaft": w, "coins": 0, "fehler": ""}


## True, wenn das Haupt-Inventar (inventory.food) noch eine Karotte hat.
static func karotte_verfuegbar(inventory_food: Dictionary) -> bool:
	return int(_num(inventory_food.get("carrot"), 0.0)) > 0


## Sauberkeits-Verfalls-Multiplikator der Weide (Weidezaun pflegt die Koppel).
static func weide_sauberkeit_mult(wirtschaft: Dictionary, balance: Dictionary) -> float:
	if not ausbau_aktiv(wirtschaft, "weidezaun"):
		return 1.0
	return _num(_dict(balance, "effekte").get("weidezaun_sauberkeit_mult"), 0.8)


## Parcours-Coin-Multiplikator des Reitplatzes (Trainings-Bonus).
static func parcours_coin_mult(wirtschaft: Dictionary, balance: Dictionary) -> float:
	if not ausbau_aktiv(wirtschaft, "reitplatz"):
		return 1.0
	return _num(_dict(balance, "effekte").get("reitplatz_parcours_coin_mult"), 1.1)


## JSON-Datei als Dictionary lesen ({} bei Fehler).
static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("RanchWirtschaft: Datei fehlt: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("RanchWirtschaft: JSON kaputt: %s" % path)
		return {}
	return parsed


static func _autoload_registry() -> Object:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("ContentRegistry")
	return null


static func _deep_merge(base: Dictionary, overrides: Dictionary) -> void:
	for k: Variant in overrides.keys():
		if base.get(k) is Dictionary and overrides[k] is Dictionary:
			_deep_merge(base[k], overrides[k])
		else:
			base[k] = overrides[k]


static func _fehler(wirtschaft: Dictionary, coins: int, code: String) -> Dictionary:
	return {"ok": false, "wirtschaft": wirtschaft, "coins": coins, "fehler": code}


static func _dict(source: Dictionary, key: String) -> Dictionary:
	return source[key] if source.get(key) is Dictionary else {}


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
