class_name RanchPlaySlices
extends RefCounted
## Save-Unterschlüssel des Ranch-Gameplays (RANCH-2): `ranch.tiere`,
## `ranch.wirtschaft`, `ranch.spiele` — ADDITIV im `ranch`-Slice, KEIN
## SAVE-Version-Bump (Slice-Registry-Muster, s. save_schema.gd Header).
##
## Absprache mit RANCH-1 (s. /tmp/gooby-godot/handoffs/RANCH2-needs.md):
## RANCH-1 besitzt den Top-Level-Slice `ranch`; seine default/normalize
## sollen für diese drei Unterschlüssel HIERHER delegieren. Solange sein
## Code fehlt, registriert ensure_registered() den Slice defensiv selbst —
## und weicht aus, wenn `ranch` bereits registriert ist. Das normalize hier
## erhält FREMDE Schlüssel (RANCH-1s Welt/Kauf-Daten) VERBATIM.

const SaveSchema := preload("res://scripts/state/save_schema.gd")

const SLICE_ID := "ranch"
const FELLFARBEN: Array[String] = ["braun", "schwarz", "weiss", "fuchs", "palomino", "schecke"]
const GEAR_SLOTS: Array[String] = ["sattel", "decke", "halfter"]

## Frische Pflege-Startwerte eines neuen Pferds.
const START_WERTE := {"hunger": 80.0, "durst": 85.0, "sauberkeit": 75.0}

static var _registered := false


## Slice defensiv registrieren (idempotent). Ist `ranch` schon registriert
## (RANCH-1 zuerst), passiert hier bewusst NICHTS — Re-Registrierung würde
## seine Registrierung ersetzen.
static func ensure_registered() -> void:
	if _registered:
		return
	if SaveSchema.registered_slice_ids().has(SLICE_ID):
		_registered = true
		return
	SaveSchema.register_slice(SLICE_ID, default_slice, normalize_slice)
	_registered = true


## Nur für Tests: Registrier-Merker zurücksetzen (Registry ist prozessweit).
static func reset_for_tests() -> void:
	_registered = false


## Kompletter ranch-Slice-Default (nur MEINE Unterschlüssel; RANCH-1 ergänzt
## seine eigenen additiv).
static func default_slice() -> Dictionary:
	return {
		"v": 1,
		"tiere": default_tiere(),
		"wirtschaft": default_wirtschaft(),
		"spiele": default_spiele(),
	}


## Self-Heal des ranch-Slices: MEINE Unterschlüssel normalisieren, alle
## fremden Schlüssel VERBATIM erhalten (RANCH-1-Daten überleben).
static func normalize_slice(raw: Variant) -> Dictionary:
	var ranch: Dictionary = raw.duplicate(true) if raw is Dictionary else {}
	ranch["v"] = maxi(1, int(_num(ranch.get("v"), 1.0)))
	ranch["tiere"] = normalize_tiere(ranch.get("tiere"))
	ranch["wirtschaft"] = normalize_wirtschaft(ranch.get("wirtschaft"))
	ranch["spiele"] = normalize_spiele(ranch.get("spiele"))
	return ranch


static func default_tiere() -> Dictionary:
	return {"v": 1, "pferde": {}, "stall": {"sauberkeit": 100.0}, "lastTickAt": 0}


## Fabrik für ein neues Pferd (RANCH-1s Pferdekauf ruft das auf).
static func neues_pferd(name: String, farbe: String) -> Dictionary:
	return {
		"name": name,
		"farbe": farbe if FELLFARBEN.has(farbe) else "braun",
		"werte": START_WERTE.duplicate(),
		"bindung": 0.0,
		"bondHeute": 0.0,
		"bondTag": "",
		"letztePflegeAt": 0,
		"ausruestung": {"sattel": null, "decke": null, "halfter": null},
	}


## tiere-Unterschlüssel heilen: Typen reparieren, Werte klemmen,
## gültige Pferde VERBATIM erhalten.
static func normalize_tiere(raw: Variant) -> Dictionary:
	var tiere: Dictionary = raw if raw is Dictionary else default_tiere()
	tiere["v"] = maxi(1, int(_num(tiere.get("v"), 1.0)))
	var roh_pferde: Dictionary = tiere.get("pferde") if tiere.get("pferde") is Dictionary else {}
	var pferde := {}
	for id: Variant in roh_pferde.keys():
		if roh_pferde[id] is Dictionary:
			pferde[str(id)] = _normalize_pferd(roh_pferde[id])
	tiere["pferde"] = pferde
	var stall: Dictionary = tiere.get("stall") if tiere.get("stall") is Dictionary else {}
	tiere["stall"] = {"sauberkeit": clampf(_num(stall.get("sauberkeit"), 100.0), 0.0, 100.0)}
	tiere["lastTickAt"] = maxi(0, int(_num(tiere.get("lastTickAt"), 0.0)))
	return tiere


static func default_wirtschaft() -> Dictionary:
	return {
		"v": 1,
		"lager": {"heu": 4, "apfel": 2},
		"ausbau": {"boxen": 1, "reitplatz": false, "weidezaun": false},
		"gear": {"owned": [], "equippedByHorse": {}},
		"felder": {"heuBereitAt": 0, "baeume": [0, 0, 0]},
	}


static func normalize_wirtschaft(raw: Variant) -> Dictionary:
	var w: Dictionary = raw if raw is Dictionary else default_wirtschaft()
	w["v"] = maxi(1, int(_num(w.get("v"), 1.0)))
	var lager: Dictionary = w.get("lager") if w.get("lager") is Dictionary else {}
	w["lager"] = {
		"heu": maxi(0, int(_num(lager.get("heu"), 0.0))),
		"apfel": maxi(0, int(_num(lager.get("apfel"), 0.0))),
	}
	var ausbau: Dictionary = w.get("ausbau") if w.get("ausbau") is Dictionary else {}
	w["ausbau"] = {
		"boxen": clampi(int(_num(ausbau.get("boxen"), 1.0)), 1, 3),
		"reitplatz": ausbau.get("reitplatz") is bool and ausbau["reitplatz"],
		"weidezaun": ausbau.get("weidezaun") is bool and ausbau["weidezaun"],
	}
	var gear: Dictionary = w.get("gear") if w.get("gear") is Dictionary else {}
	var owned: Array = gear.get("owned") if gear.get("owned") is Array else []
	var owned_clean: Array = []
	for id: Variant in owned:
		if id is String and not owned_clean.has(id):
			owned_clean.append(id)
	var equipped: Dictionary = (
		gear.get("equippedByHorse") if gear.get("equippedByHorse") is Dictionary else {}
	)
	w["gear"] = {"owned": owned_clean, "equippedByHorse": equipped.duplicate(true)}
	var felder: Dictionary = w.get("felder") if w.get("felder") is Dictionary else {}
	var baeume_raw: Array = felder.get("baeume") if felder.get("baeume") is Array else []
	var baeume: Array = []
	for i in 3:
		var at: Variant = baeume_raw[i] if i < baeume_raw.size() else 0
		baeume.append(maxi(0, int(_num(at, 0.0))))
	w["felder"] = {
		"heuBereitAt": maxi(0, int(_num(felder.get("heuBereitAt"), 0.0))),
		"baeume": baeume,
	}
	return w


static func default_spiele() -> Dictionary:
	return {
		"v": 1,
		"parcours": {"stars": {}, "best": {}, "cleared": {}},
		"herde": {"stars": {}, "best": {}, "cleared": {}},
	}


static func normalize_spiele(raw: Variant) -> Dictionary:
	var spiele: Dictionary = raw if raw is Dictionary else default_spiele()
	spiele["v"] = maxi(1, int(_num(spiele.get("v"), 1.0)))
	for spiel: String in ["parcours", "herde"]:
		var eintrag: Dictionary = spiele.get(spiel) if spiele.get(spiel) is Dictionary else {}
		for key: String in ["stars", "best", "cleared"]:
			if not (eintrag.get(key) is Dictionary):
				eintrag[key] = {}
		spiele[spiel] = eintrag
	return spiele


static func _normalize_pferd(raw: Dictionary) -> Dictionary:
	var pferd := neues_pferd("", "braun")
	pferd["name"] = str(raw.get("name", "")) if raw.get("name") is String else ""
	if raw.get("farbe") is String and FELLFARBEN.has(raw["farbe"]):
		pferd["farbe"] = raw["farbe"]
	var werte: Dictionary = raw.get("werte") if raw.get("werte") is Dictionary else {}
	pferd["werte"] = RanchHorseCare.clamp_werte(werte)
	pferd["bindung"] = clampf(_num(raw.get("bindung"), 0.0), 0.0, 100.0)
	pferd["bondHeute"] = clampf(
		_num(raw.get("bondHeute"), 0.0), 0.0, RanchHorseCare.BOND_TAGES_DECKEL
	)
	pferd["bondTag"] = str(raw.get("bondTag", "")) if raw.get("bondTag") is String else ""
	pferd["letztePflegeAt"] = maxi(0, int(_num(raw.get("letztePflegeAt"), 0.0)))
	var ausr: Dictionary = raw.get("ausruestung") if raw.get("ausruestung") is Dictionary else {}
	for slot: String in GEAR_SLOTS:
		var farbe: Variant = ausr.get(slot)
		pferd["ausruestung"][slot] = farbe if farbe is String else null
	# Fremde Zusatz-Schlüssel (z. B. RANCH-1-Kaufdaten am Pferd) VERBATIM erhalten.
	for k: Variant in raw.keys():
		if not pferd.has(k):
			pferd[k] = (
				raw[k].duplicate(true) if (raw[k] is Dictionary or raw[k] is Array) else raw[k]
			)
	return pferd


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
