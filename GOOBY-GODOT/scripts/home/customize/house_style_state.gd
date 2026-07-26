class_name HouseStyleState
extends RefCounted
## Save-Anbindung des Gestalten-Modus (HAUS-CUSTOM): liegt ADDITIV im
## bestehenden `home`-Slice unter `home.style` — KEIN Save-Version-Bump.
## Alte Stände kennen den Key nicht: JEDER Lesepfad läuft durch
## `normalize()`, fehlende/kaputte Werte fallen auf die Katalog-Defaults
## zurück (dieselbe Selbstheil-Philosophie wie HomeState.normalize_slice).
##
## Struktur:
##   home.style.gekauft     {art: [optionIds]}   — Kauf/Besitz je Art
##   home.style.raeume      {roomId: {wand, wandFarbe, boden, bodenFarbe}}
##   home.style.haus        Fassade/Dach/Tür/Fenster/Nummer/Briefkasten/Vordach
##   home.style.grundstueck Bodenbelag/Weg/Zaun
##
## Preis-0-Optionen gelten IMMER als gekauft. Käufe buchen Münzen über den
## EINEN Geld-Pfad (Economy.spend, Reason "gestalten") — atomar wie
## ShopPurchase.buy.

const Economy := preload("res://scripts/logic/economy.gd")

const RESULT_OK := "ok"
const RESULT_UNKNOWN := "unknown_option"
const RESULT_BROKE := "not_enough_coins"
const RESULT_OWNED := "already_owned"
const REASON := "gestalten"
const NUMMER_MIN := 1
const NUMMER_MAX := 99

## Schlüssel in home.style.haus, die eine kaufbare Options-Art referenzieren.
const HAUS_OPTION_KEYS := {
	"dachForm": "dachForm",
	"hausnummer": "hausnummer",
	"briefkasten": "briefkasten",
	"vordach": "vordach",
}
## Schlüssel in home.style.haus mit freier Farbwahl → Katalog-Farbbereich.
const HAUS_FARB_KEYS := {
	"fassade": "fassade",
	"dachFarbe": "dach",
	"tuerFarbe": "tuer",
	"fensterFarbe": "fenster",
}


## Kompletter, geheilter Stil (Kopie — Schreiben nur über die Setter).
static func style(gs: Object) -> Dictionary:
	var raw: Variant = gs.get_value("home.style", {}) if gs != null else {}
	return normalize(raw)


## Selbstheilung (pur, headless-testbar): fehlende Werte = Standard,
## unbekannte IDs/Farben = Standard, gültige Daten bleiben VERBATIM.
static func normalize(raw: Variant) -> Dictionary:
	var quelle: Dictionary = raw if raw is Dictionary else {}
	var out := {
		"gekauft": _norm_gekauft(quelle.get("gekauft")),
		"raeume": {},
		"haus": _norm_haus(quelle.get("haus")),
		"grundstueck": _norm_grundstueck(quelle.get("grundstueck")),
	}
	var raeume: Variant = quelle.get("raeume", {})
	if raeume is Dictionary:
		for room_id: Variant in raeume:
			out["raeume"][str(room_id)] = _norm_raum(str(room_id), raeume[room_id])
	return out


## Wand/Boden eines Raums (geheilt; unbekannter Raum → Basis-Standard).
static func raum_style(gs: Object, room_id: String) -> Dictionary:
	var raeume: Dictionary = style(gs).get("raeume", {})
	if raeume.has(room_id):
		return raeume[room_id]
	return _norm_raum(room_id, {})


## Wand ODER Boden eines Raums setzen (art ∈ {wand, boden}).
## false = unbekannte Option / Farbe / nicht gekauft — dann ändert sich nichts.
static func set_raum_flaeche(
	gs: Object, room_id: String, art: String, id: String, farb_id: String
) -> bool:
	if not ["wand", "boden"].has(art) or CustomizeCatalog.def(art, id).is_empty():
		return false
	if not CustomizeCatalog.farben(art, id).has(farb_id):
		return false
	if not ist_gekauft(gs, art, id):
		return false
	_write(
		gs,
		func(st: Dictionary) -> void:
			if not (st.get("raeume") is Dictionary):
				st["raeume"] = {}
			var raum: Dictionary = _norm_raum(room_id, st["raeume"].get(room_id))
			raum[art] = id
			raum["%sFarbe" % art] = farb_id
			st["raeume"][room_id] = raum
	)
	return true


## Haus-Außenstil setzen (key s. HAUS_OPTION_KEYS/HAUS_FARB_KEYS oder
## "hausnummerZahl"). Validiert gegen Katalog + Besitz.
static func set_haus(gs: Object, key: String, value: Variant) -> bool:
	if key == "hausnummerZahl":
		var zahl := clampi(int(value), NUMMER_MIN, NUMMER_MAX)
		_write(gs, func(st: Dictionary) -> void: st["haus"]["hausnummerZahl"] = zahl)
		return true
	if HAUS_OPTION_KEYS.has(key):
		var art: String = HAUS_OPTION_KEYS[key]
		if CustomizeCatalog.def(art, str(value)).is_empty() or not ist_gekauft(gs, art, str(value)):
			return false
		_write(gs, func(st: Dictionary) -> void: st["haus"][key] = str(value))
		return true
	if HAUS_FARB_KEYS.has(key):
		if not CustomizeCatalog.farb_wahl(HAUS_FARB_KEYS[key]).has(str(value)):
			return false
		_write(gs, func(st: Dictionary) -> void: st["haus"][key] = str(value))
		return true
	if ["briefkastenFarbe", "vordachFarbe"].has(key):
		var traeger := "briefkasten" if key == "briefkastenFarbe" else "vordach"
		var aktuell := str(style(gs)["haus"][traeger])
		if not CustomizeCatalog.farben(traeger, aktuell).has(str(value)):
			return false
		_write(gs, func(st: Dictionary) -> void: st["haus"][key] = str(value))
		return true
	return false


## Grundstück setzen (key ∈ {boden, bodenFarbe, weg, wegFarbe, zaun,
## zaunFarbe}). Validiert gegen Katalog + Besitz.
static func set_grundstueck(gs: Object, key: String, value: Variant) -> bool:
	var arten := {"boden": "grundBoden", "weg": "weg", "zaun": "zaun"}
	if arten.has(key):
		var art: String = arten[key]
		if CustomizeCatalog.def(art, str(value)).is_empty() or not ist_gekauft(gs, art, str(value)):
			return false
		_write(gs, func(st: Dictionary) -> void: st["grundstueck"][key] = str(value))
		return true
	var farb_traeger := {"bodenFarbe": "boden", "wegFarbe": "weg", "zaunFarbe": "zaun"}
	if farb_traeger.has(key):
		var traeger: String = farb_traeger[key]
		var aktuell := str(style(gs)["grundstueck"][traeger])
		if not CustomizeCatalog.farben(arten[traeger], aktuell).has(str(value)):
			return false
		_write(gs, func(st: Dictionary) -> void: st["grundstueck"][key] = str(value))
		return true
	return false


## Besitz: Preis 0 und Start-Look-Defaults = immer gekauft, sonst Blick in
## home.style.gekauft.
static func ist_gekauft(gs: Object, art: String, id: String) -> bool:
	var option := CustomizeCatalog.def(art, id)
	if option.is_empty():
		return false
	if int(option.get("preis", 0)) <= 0 or CustomizeCatalog.ist_default(art, id):
		return true
	var gekauft: Dictionary = style(gs).get("gekauft", {})
	return (gekauft.get(art, []) as Array).has(id)


## Kauf (IKEA/Baumarkt rufen das): atomar Münzen abbuchen UND freischalten.
static func kaufen(gs: Object, art: String, id: String) -> String:
	var option := CustomizeCatalog.def(art, id)
	if option.is_empty() or gs == null:
		return RESULT_UNKNOWN
	if ist_gekauft(gs, art, id):
		return RESULT_OWNED
	var preis := int(option.get("preis", 0))
	var bezahlt := [false]
	gs.update(
		func(state: Dictionary) -> void:
			if not Economy.spend(state["economy"], preis, REASON):
				return
			bezahlt[0] = true
			var st := _ensure_style(state)
			if not (st["gekauft"].get(art) is Array):
				st["gekauft"][art] = []
			st["gekauft"][art].append(id)
	)
	if not bool(bezahlt[0]):
		return RESULT_BROKE
	gs.notify_slice_changed(HomeState.SLICE_ID)
	return RESULT_OK


## Zufalls-Look für einen Raum — nur aus GEKAUFTEN Optionen.
static func zufall_raum(gs: Object, room_id: String, rng: RandomNumberGenerator) -> void:
	for art: String in ["wand", "boden"]:
		var id := _zufalls_option(gs, art, rng)
		var farben := CustomizeCatalog.farben(art, id)
		set_raum_flaeche(gs, room_id, art, id, farben[rng.randi_range(0, farben.size() - 1)])


## Zufalls-Außenstil (Farben frei, Optionen nur aus dem Besitz).
static func zufall_haus(gs: Object, rng: RandomNumberGenerator) -> void:
	for key: String in HAUS_FARB_KEYS:
		var farben := CustomizeCatalog.farb_wahl(HAUS_FARB_KEYS[key])
		set_haus(gs, key, farben[rng.randi_range(0, farben.size() - 1)])
	for key: String in HAUS_OPTION_KEYS:
		set_haus(gs, key, _zufalls_option(gs, HAUS_OPTION_KEYS[key], rng))
	for paar: Array in [["briefkastenFarbe", "briefkasten"], ["vordachFarbe", "vordach"]]:
		var traeger := str(style(gs)["haus"][paar[1]])
		var farben := CustomizeCatalog.farben(paar[1], traeger)
		if not farben.is_empty():
			set_haus(gs, paar[0], farben[rng.randi_range(0, farben.size() - 1)])


static func zufall_grundstueck(gs: Object, rng: RandomNumberGenerator) -> void:
	var arten := {"boden": "grundBoden", "weg": "weg", "zaun": "zaun"}
	for key: String in arten:
		var id := _zufalls_option(gs, arten[key], rng)
		set_grundstueck(gs, key, id)
		var farben := CustomizeCatalog.farben(arten[key], id)
		if not farben.is_empty():
			set_grundstueck(gs, "%sFarbe" % key, farben[rng.randi_range(0, farben.size() - 1)])


## Zurücksetzen auf die Katalog-Defaults (Besitz bleibt!).
static func reset_raum(gs: Object, room_id: String) -> void:
	_write(
		gs,
		func(st: Dictionary) -> void:
			if st.get("raeume") is Dictionary:
				st["raeume"].erase(room_id)
	)


static func reset_haus(gs: Object) -> void:
	_write(gs, func(st: Dictionary) -> void: st["haus"] = CustomizeCatalog.default_haus())


static func reset_grundstueck(gs: Object) -> void:
	_write(
		gs, func(st: Dictionary) -> void: st["grundstueck"] = CustomizeCatalog.default_grundstueck()
	)


# ── intern ───────────────────────────────────────────────────────────────────


static func _zufalls_option(gs: Object, art: String, rng: RandomNumberGenerator) -> String:
	var eigene: Array = []
	for id: Variant in CustomizeCatalog.ids(art):
		if ist_gekauft(gs, art, str(id)):
			eigene.append(str(id))
	if eigene.is_empty():
		return ""
	return eigene[rng.randi_range(0, eigene.size() - 1)]


## Schreibpfad: home.style im Save heilen, mutieren, Slice-Signal feuern.
static func _write(gs: Object, mutator: Callable) -> void:
	if gs == null:
		return
	gs.update(func(state: Dictionary) -> void: mutator.call(_ensure_style(state)))
	gs.notify_slice_changed(HomeState.SLICE_ID)


static func _ensure_style(state: Dictionary) -> Dictionary:
	if not (state.get(HomeState.SLICE_ID) is Dictionary):
		state[HomeState.SLICE_ID] = {}
	var home: Dictionary = state[HomeState.SLICE_ID]
	home["style"] = normalize(home.get("style"))
	return home["style"]


static func _norm_gekauft(raw: Variant) -> Dictionary:
	var quelle: Dictionary = raw if raw is Dictionary else {}
	var out: Dictionary = {}
	for art: String in CustomizeCatalog.OPTION_ARTEN:
		var liste: Array = []
		var roh: Variant = quelle.get(art, [])
		if roh is Array:
			for id: Variant in roh:
				if not CustomizeCatalog.def(art, str(id)).is_empty() and not liste.has(str(id)):
					liste.append(str(id))
		out[art] = liste
	return out


static func _norm_raum(room_id: String, raw: Variant) -> Dictionary:
	var quelle: Dictionary = raw if raw is Dictionary else {}
	var out := CustomizeCatalog.raum_default(room_id)
	for art: String in ["wand", "boden"]:
		var id := str(quelle.get(art, out.get(art, "")))
		if CustomizeCatalog.def(art, id).is_empty():
			id = str(out.get(art, ""))
		out[art] = id
		var farb_key := "%sFarbe" % art
		var farbe := str(quelle.get(farb_key, out.get(farb_key, "")))
		var erlaubt := CustomizeCatalog.farben(art, id)
		if not erlaubt.has(farbe):
			farbe = str(out.get(farb_key, ""))
			if not erlaubt.has(farbe) and not erlaubt.is_empty():
				farbe = str(erlaubt[0])
		out[farb_key] = farbe
	return out


static func _norm_haus(raw: Variant) -> Dictionary:
	var quelle: Dictionary = raw if raw is Dictionary else {}
	var out := CustomizeCatalog.default_haus()
	for key: String in HAUS_FARB_KEYS:
		var farbe := str(quelle.get(key, out.get(key, "")))
		if CustomizeCatalog.farb_wahl(HAUS_FARB_KEYS[key]).has(farbe):
			out[key] = farbe
	for key: String in HAUS_OPTION_KEYS:
		var id := str(quelle.get(key, out.get(key, "")))
		if not CustomizeCatalog.def(HAUS_OPTION_KEYS[key], id).is_empty():
			out[key] = id
	out["hausnummerZahl"] = clampi(
		int(quelle.get("hausnummerZahl", out.get("hausnummerZahl", 5))), NUMMER_MIN, NUMMER_MAX
	)
	for paar: Array in [["briefkastenFarbe", "briefkasten"], ["vordachFarbe", "vordach"]]:
		var farbe := str(quelle.get(paar[0], out.get(paar[0], "")))
		var erlaubt := CustomizeCatalog.farben(paar[1], str(out[paar[1]]))
		if erlaubt.has(farbe):
			out[paar[0]] = farbe
		elif not erlaubt.has(str(out.get(paar[0], ""))) and not erlaubt.is_empty():
			out[paar[0]] = str(erlaubt[0])
	return out


static func _norm_grundstueck(raw: Variant) -> Dictionary:
	var quelle: Dictionary = raw if raw is Dictionary else {}
	var out := CustomizeCatalog.default_grundstueck()
	var arten := {"boden": "grundBoden", "weg": "weg", "zaun": "zaun"}
	for key: String in arten:
		var id := str(quelle.get(key, out.get(key, "")))
		if not CustomizeCatalog.def(arten[key], id).is_empty():
			out[key] = id
		var farb_key := "%sFarbe" % key
		var farbe := str(quelle.get(farb_key, out.get(farb_key, "")))
		var erlaubt := CustomizeCatalog.farben(arten[key], str(out[key]))
		if erlaubt.has(farbe):
			out[farb_key] = farbe
		elif not erlaubt.has(str(out.get(farb_key, ""))) and not erlaubt.is_empty():
			out[farb_key] = str(erlaubt[0])
	return out
