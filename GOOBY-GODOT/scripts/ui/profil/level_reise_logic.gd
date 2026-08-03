class_name LevelReiseLogic
extends RefCounted
## Level-Reise (W18/R3, G8-IDEE Progression Nr. 2): PURE Ableitungen für die
## Reise-Karte 1→40 im Profil plus die Meilenstein-Fest-Buchhaltung.
##
## GRUNDSATZ (NULL Balance-Risiko): die XP-Kurve wird NUR GELESEN
## (Leveling-Konstanten / xp_to_next / cumulative_xp_to_level — der
## M2-Rework-Hook in leveling.gd bleibt eingefroren). Die Freischalt-Gates
## kommen aus dem ECHTEN Code (Economy.QUICK_DELIVERY_LEVEL, DLC-Kataloge,
## MusicRegistry-Sender, ModifierEngine, CosmeticsCatalog) — nichts wird
## hardgecodet, was es nicht gibt; ein späteres Kurven-Rework rendert die
## Karte einfach neu.
##
## Gefeierte Meilensteine leben ADDITIV unter
## progression.milestonesCelebrated ({"5": at_ms, ...}; at_ms 0 = rückwirkend
## STILL gestempelt, ohne Datum). Bereits überschrittene Meilensteine gelten
## beim ersten Kontakt als gefeiert (backfill_stille — idempotent, kein
## Nachfeier-Spam), nur der Reisepass-Stempel erscheint.

const Leveling := preload("res://scripts/logic/leveling.gd")
const Economy := preload("res://scripts/logic/economy.gd")

## Jedes 5. Level ist ein Meilenstein-Fest; das letzte (MAX_LEVEL) ist die
## „Goldene Möhre“-Zeremonie.
const MEILENSTEIN_SCHRITT := 5
## Additiver Save-Key im progression-Slice (merge_defaults-sicher — extra
## Keys überleben normalize, s. save_schema.merge_defaults).
const GEFEIERT_KEY := "milestonesCelebrated"

## Stempel-/Fest-Glyphen (Torte; Goldene Möhre am Reiseziel L40).
const GLYPH_FEST := "🎂"
const GLYPH_MOEHRE := "🥕"

## ---------------------------------------------------------------- Kurve (nur lesen)


## Alle Meilenstein-Level: 5, 10, …, MAX_LEVEL (aus der Kurve abgeleitet).
static func meilensteine() -> Array[int]:
	var out: Array[int] = []
	var m := MEILENSTEIN_SCHRITT
	while m <= Leveling.MAX_LEVEL:
		out.append(m)
		m += MEILENSTEIN_SCHRITT
	return out


static func ist_meilenstein(level: int) -> bool:
	return level >= MEILENSTEIN_SCHRITT and level % MEILENSTEIN_SCHRITT == 0


## Nächster Meilenstein NACH `level` (0 = keiner mehr — Reise komplett).
static func naechster_meilenstein(level: int) -> int:
	for m in meilensteine():
		if m > level:
			return m
	return 0


## Fortschritt aus dem Save ({level, xp} — defensiv wie save_schema).
static func fortschritt_von(state: Dictionary) -> Dictionary:
	var prog: Variant = state.get("progression")
	if not (prog is Dictionary):
		return {"level": 1, "xp": 0.0}
	var level := clampi(int(_num((prog as Dictionary).get("level"), 1.0)), 1, Leveling.MAX_LEVEL)
	var xp := maxf(0.0, _num((prog as Dictionary).get("xp"), 0.0))
	return {"level": level, "xp": xp}


## Fehlende XP von `progress` bis `ziel_level` (0 wenn erreicht) — reine
## Leveling-Lese-Mathematik (cumulative_xp_to_level).
static func fehlende_xp(progress: Dictionary, ziel_level: int) -> int:
	var level := int(progress.get("level", 1))
	if ziel_level <= level:
		return 0
	var fehlt := (
		Leveling.cumulative_xp_to_level(ziel_level)
		- Leveling.cumulative_xp_to_level(level)
		- int(floor(_num(progress.get("xp"), 0.0)))
	)
	return maxi(0, fehlt)


## Daten für den „noch X XP“-Hinweis am Gooby-Marker/Kartenkopf.
static func hinweis(state: Dictionary) -> Dictionary:
	var p := fortschritt_von(state)
	var level := int(p["level"])
	if level >= Leveling.MAX_LEVEL:
		return {"max": true, "level": level}
	var fest := naechster_meilenstein(level)
	return {
		"max": false,
		"level": level,
		"naechstes_level": level + 1,
		"xp_naechstes": fehlende_xp(p, level + 1),
		"fest_level": fest,
		"xp_fest": fehlende_xp(p, fest) if fest > 0 else 0,
	}


## ---------------------------------------------------------------- Gates (aus dem Code)


## Die ECHTEN Freischalt-Gates, sortiert nach Level. Quellen sind die
## lebenden Code-Konstanten/Kataloge — bei einem Balance-Pack-Update
## (freischalt_level) wandern die Tore automatisch mit.
static func gates() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		{
			"level": Economy.QUICK_DELIVERY_LEVEL,
			"id": "lieferung",
			"glyph": "🚚",
			"label_key": "levelreise.gate.lieferung",
		},
		{
			"level": GoobyeKatalog.freischalt_level(),
			"id": "goobye",
			"glyph": "🛒",
			"label_key": "levelreise.gate.goobye",
		},
		{
			"level": McGoobyKatalog.freischalt_level(),
			"id": "mcgooby",
			"glyph": "🍔",
			"label_key": "levelreise.gate.mcgooby",
		},
		{
			"level": RanchKatalog.freischalt_level(),
			"id": "ranch",
			"glyph": "🐴",
			"label_key": "levelreise.gate.ranch",
		},
	]
	for station: Dictionary in MusicRegistry.STATION_DEFS:
		var unlock := int(station.get("unlock_level", 1))
		if unlock <= 1:
			continue
		(
			out
			. append(
				{
					"level": unlock,
					"id": "radio_%s" % str(station["id"]),
					"glyph": "📻",
					"label_key": str(station["name_key"]),
				}
			)
		)
	out.sort_custom(_gate_sortierung)
	return out


## Gates gruppiert nach Level ({level: Array[gate]}) — für die Stationen.
static func gates_nach_level() -> Dictionary:
	var out := {}
	for gate: Dictionary in gates():
		var level := int(gate["level"])
		if not (out.get(level) is Array):
			out[level] = []
		(out[level] as Array).append(gate)
	return out


## Kleinere Level-Reads pro Level (Vorfreude-Zeilen, keine eigenen Tore):
## Garderoben-Teile (CosmeticsCatalog min_level) und Arcade-Modifier
## (ModifierEngine.TYPES min_level). Ohne ContentRegistry (nackte Tests)
## ist die Garderobe leer — die Ableitung bleibt deterministisch.
static func extras_fuer(level: int) -> Dictionary:
	var garderobe := 0
	for def: Variant in CosmeticsCatalog.all():
		if def is Dictionary and int((def as Dictionary).get("min_level", 1)) == level:
			garderobe += 1
	var modifier := 0
	for typ_id: String in ModifierEngine.TYPE_IDS:
		var typ: Dictionary = ModifierEngine.TYPES[typ_id]
		if int(typ.get("min_level", 1)) == level:
			modifier += 1
	return {"garderobe": garderobe, "modifier": modifier}


## ---------------------------------------------------------------- Stationen


## Die komplette Reise-Karte als Daten: eine Station pro Level 1→MAX_LEVEL.
## Deterministisch (gleicher State ⇒ identisches Array) — Testkontrakt.
static func stationen(state: Dictionary) -> Array[Dictionary]:
	var p := fortschritt_von(state)
	var level := int(p["level"])
	var done := gefeierte(state)
	var tor_map := gates_nach_level()
	var out: Array[Dictionary] = []
	for l in range(1, Leveling.MAX_LEVEL + 1):
		var tore: Array = tor_map.get(l, [])
		(
			out
			. append(
				{
					"level": l,
					"erreicht": l <= level,
					"aktuell": l == level,
					"meilenstein": ist_meilenstein(l),
					"max": l == Leveling.MAX_LEVEL,
					"gefeiert": done.has(str(l)),
					"gates": tore,
					"extras": extras_fuer(l),
				}
			)
		)
	return out


## ---------------------------------------------------------------- Fest-Buchhaltung


## Gefeierte Meilensteine aus dem Save ({"5": at_ms, ...}; leer = keine).
static func gefeierte(state: Dictionary) -> Dictionary:
	var prog: Variant = state.get("progression")
	if not (prog is Dictionary):
		return {}
	var raw: Variant = (prog as Dictionary).get(GEFEIERT_KEY)
	return raw if raw is Dictionary else {}


## Erreichte, aber noch nicht gefeierte Meilensteine (aufsteigend).
static func offene_meilensteine(state: Dictionary) -> Array[int]:
	var level := int(fortschritt_von(state)["level"])
	var done := gefeierte(state)
	var out: Array[int] = []
	for m in meilensteine():
		if m <= level and not done.has(str(m)):
			out.append(m)
	return out


## Rückwirkend-Regel: alles bereits Überschrittene STILL als gefeiert
## stempeln (at_ms 0 — Stempel ohne Datum, keine Nachfeier). Mutiert das
## übergebene State-Dict (im gs.update-Mutator rufen). Gibt die frisch
## gestempelten Level zurück; zweiter Lauf stempelt nichts (idempotent).
static func backfill_stille(state: Dictionary) -> Array[int]:
	var offen := offene_meilensteine(state)
	for m in offen:
		_stempel_setzen(state, m, 0)
	return offen


## Meilenstein als gefeiert stempeln (true = war neu). at_ms > 0 = echtes
## Fest mit Datum auf dem Reisepass-Stempel.
static func stemple_gefeiert(state: Dictionary, level: int, at_ms: int) -> bool:
	if gefeierte(state).has(str(level)):
		return false
	_stempel_setzen(state, level, at_ms)
	return true


## ---------------------------------------------------------------- Reisepass


## Meilenstein-Stempel für die Reisepass-Stempelseite (Chip-Einträge im
## stempel_von-Format; `label` ist vor-lokalisiert, at_ms 0 = ohne Datum).
static func meilenstein_stempel(state: Dictionary) -> Array:
	var level := int(fortschritt_von(state)["level"])
	var done := gefeierte(state)
	var out: Array = []
	for m in meilensteine():
		if m > level:
			break
		var id := "level%d" % m
		(
			out
			. append(
				{
					"id": id,
					"glyph": GLYPH_MOEHRE if m >= Leveling.MAX_LEVEL else GLYPH_FEST,
					"name_key": "",
					"label": I18nService.t("levelreise.stempel_label", {"level": m}),
					"at_ms": int(_num(done.get(str(m)), 0.0)),
					"drehung": stempel_drehung(id),
					"farbe": stempel_farbe(m),
				}
			)
		)
	return out


## Deterministische Stempel-Drehung −6°..+6° (Muster PassportCard).
static func stempel_drehung(id: String) -> float:
	return float(MrzGag.hash_of(id) % 13 - 6)


## Deterministische Stempel-Farbe — NUR AC-Tokens; L40 immer Gold.
static func stempel_farbe(level: int) -> Color:
	if level >= Leveling.MAX_LEVEL:
		return AcTokens.YELLOW_DARK
	var pool: Array[Color] = [AcTokens.TEAL_DARK, AcTokens.PINK_DARK, AcTokens.LEAF_DARK]
	return pool[MrzGag.hash_of("levelreise|%d" % level) % pool.size()]


## Deterministische Jubel-Zeile fürs Fest (kein RNG — Level wählt).
static func jubel_key(level: int) -> String:
	if level >= Leveling.MAX_LEVEL:
		return "levelreise.jubel_max"
	@warning_ignore("integer_division")
	var variante := 1 + (level / MEILENSTEIN_SCHRITT - 1) % 4
	return "levelreise.jubel_%d" % variante


## ---------------------------------------------------------------- Helfer


static func _gate_sortierung(a: Dictionary, b: Dictionary) -> bool:
	if int(a["level"]) != int(b["level"]):
		return int(a["level"]) < int(b["level"])
	return str(a["id"]) < str(b["id"])


static func _stempel_setzen(state: Dictionary, level: int, at_ms: int) -> void:
	if not (state.get("progression") is Dictionary):
		state["progression"] = {"level": 1, "xp": 0}
	var prog: Dictionary = state["progression"]
	if not (prog.get(GEFEIERT_KEY) is Dictionary):
		prog[GEFEIERT_KEY] = {}
	(prog[GEFEIERT_KEY] as Dictionary)[str(level)] = at_ms


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
