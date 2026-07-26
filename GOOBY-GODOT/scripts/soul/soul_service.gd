class_name SoulService
extends RefCounted
## Seelen-Orchestrator (FB-6/SEELE): entscheidet PRO RAUMBETRETEN höchstens
## EINEN Moment (nie stapeln, nie aufdringlich) und wählt Idle-Handlungen/
## Überraschungen fürs Hintergrund-Leben. PURE Statics — State/Slice/Defs/
## Zeit/Roll werden hereingereicht, Buchhaltung passiert getrennt in
## book_enter() (Tests: decide → book → decide muss gaten).
##
## Datengetrieben: Momente kommen als Defs aus dem Content-Pack
## `content/soul` (Domain "soul", append-by-id — Pack-Updates können Momente
## ergänzen/ersetzen). Fehlt ein Def, fällt der Moment stumm aus (kein Crash).
##
## Prioritäten beim Betreten (erste Übereinstimmung gewinnt):
##   1 Ritual: Spieler-Geburtstag > Gooby-Geburtstag > Jubiläum > Feiertag >
##     erster Schnee (je Schlüssel 1×/Tag bzw. 1×/Saison, KEIN Ambient-Deckel)
##   2 Begrüßung: Abwesenheit (gefreut/eingeschnappt/vermisst) sonst
##     Tageszeit — je 1×/Tag, zählt gegen die Frequenzbremse
##   3 Wetter-Kommentar (Frequenzbremse)
##   4 Persönliche Erinnerung (Frequenzbremse + 3-Tage-Cooldown je Erinnerung)

const DOMAIN := "soul"

## Wie oft eine Erinnerung statt nichts kommt, wenn Platz ist (roll-Gate).
const MEMORY_CHANCE := 0.35
## Geburtstags-Nachfrage: erst nach ein paar Kennen-Tagen, dann selten.
const ASK_BIRTHDAY_MIN_DAYS := 3
const ASK_BIRTHDAY_RETRY_MS := 7 * 86_400_000


## Defs aus der ContentRegistry (leer ohne Autoload — Tests reichen direkt).
static func defs_from_registry() -> Array:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return []
	var registry := (loop as SceneTree).root.get_node_or_null("/root/ContentRegistry")
	if registry == null or not registry.has_method("get_items"):
		return []
	return registry.get_items(DOMAIN)


## Der EINE Moment beim Raumbetreten ({} = Stille ist auch okay).
## ctx: {now_ms, date: Dictionary, hour, gap_ms, wetter: {typ,regen,schnee},
##       player_name, nickname}
static func decide_enter(
	state: Dictionary, slice: Dictionary, defs: Array, ctx: Dictionary, roll: float
) -> Dictionary:
	var ritual := _decide_ritual(slice, defs, ctx, roll)
	if not ritual.is_empty():
		return ritual
	var today := SoulTriggers.day_string(ctx["date"])
	if not SoulTriggers.ambient_allowed(slice["ambient"], int(ctx["now_ms"]), today):
		return {}
	var greeting := _decide_greeting(slice, defs, ctx, roll)
	if not greeting.is_empty():
		return greeting
	var weather := _decide_weather(slice, defs, ctx, roll)
	if not weather.is_empty():
		return weather
	return _decide_memory(state, slice, defs, ctx, roll)


## Buchhaltung NACH dem Zeigen (mutiert die hereingereichte Slice-Kopie;
## der Aufrufer persistiert via SoulState.mutate). Rituale buchen ihren
## celebrated-Schlüssel, ambiente Momente die Frequenzbremse.
static func book_enter(slice: Dictionary, moment: Dictionary, ctx: Dictionary) -> void:
	if moment.is_empty():
		return
	var now_ms := int(ctx["now_ms"])
	var today := SoulTriggers.day_string(ctx["date"])
	slice["totalMoments"] = int(slice.get("totalMoments", 0)) + 1
	if str(moment.get("kind", "")) == "ritual":
		slice["celebrated"][str(moment["gate_key"])] = str(moment["gate_stamp"])
		return
	slice["ambient"] = SoulTriggers.note_ambient(slice["ambient"], now_ms, today)
	# Nicht-rituale Momente mit Tagesgate (Wetter) buchen den Schlüssel mit.
	if moment.has("gate_key"):
		slice["celebrated"][str(moment["gate_key"])] = str(moment["gate_stamp"])
	match str(moment.get("kind", "")):
		"gruss":
			slice["lastGreetDay"] = today
			slice["lastGreetKind"] = str(moment["id"])
		"erinnerung":
			slice["memoryShownAt"][str(moment["memory_id"])] = now_ms


## Idle-Handlung fürs Hintergrund-Leben ({} = weiter dösen). `cooldowns` ist
## die In-Memory-Map des Aufrufers {def_id: ablauf_ms} — Idle-Akte sind
## flüchtig und gehören nicht in den Save.
static func pick_idle(
	defs: Array, ctx: Dictionary, cooldowns: Dictionary, roll: float
) -> Dictionary:
	var now_ms := int(ctx["now_ms"])
	var available: Array[Dictionary] = []
	var total := 0.0
	for def: Variant in _defs_of_kind(defs, "idle"):
		if now_ms < int(cooldowns.get(str(def["id"]), 0)):
			continue
		if not _idle_requirement_met(def, ctx):
			continue
		available.append(def)
		total += maxf(0.0, float(def.get("weight", 1)))
	if available.is_empty() or total <= 0.0:
		return {}
	var at := clampf(roll, 0.0, 0.999999) * total
	for def: Dictionary in available:
		var weight := maxf(0.0, float(def.get("weight", 1)))
		if at < weight:
			return def
		at -= weight
	return available[available.size() - 1]


## Überraschungen: sehr selten, je Id ein langer Slice-Cooldown; chance
## (0..1 aus dem Def) gegen roll_gate. {} = keine.
static func pick_surprise(
	slice: Dictionary, defs: Array, ctx: Dictionary, roll_pick: float, roll_gate: float
) -> Dictionary:
	var now_ms := int(ctx["now_ms"])
	var available: Array[Dictionary] = []
	for def: Variant in _defs_of_kind(defs, "ueberraschung"):
		var last := int(slice["surpriseAt"].get(str(def["id"]), 0))
		var cooldown_ms := int(float(def.get("cooldown_h", 72.0)) * 3_600_000.0)
		if last <= 0 or now_ms - last >= cooldown_ms:
			available.append(def)
	if available.is_empty():
		return {}
	var chosen: Dictionary = available[int(clampf(roll_pick, 0.0, 0.999999) * available.size())]
	if roll_gate >= float(chosen.get("chance", 0.1)):
		return {}
	return _moment_from_def(chosen, "ueberraschung", {}, roll_pick)


static func book_surprise(slice: Dictionary, moment: Dictionary, now_ms: int) -> void:
	if moment.is_empty():
		return
	slice["surpriseAt"][str(moment["id"])] = now_ms
	slice["totalMoments"] = int(slice.get("totalMoments", 0)) + 1


## Soll Gooby (jetzt) nach dem Spieler-Geburtstag fragen? Nie drängeln:
## erst nach ein paar Kennen-Tagen, dann höchstens alle 7 Tage, und nur
## wenn die Frequenzbremse Platz lässt.
static func should_ask_birthday(slice: Dictionary, ctx: Dictionary) -> bool:
	var birthday: Dictionary = slice["playerBirthday"]
	if int(birthday.get("month", 0)) > 0:
		return false
	var now_ms := int(ctx["now_ms"])
	var days := SoulTriggers.days_known(int(slice["firstMetAt"]), now_ms)
	if days < ASK_BIRTHDAY_MIN_DAYS:
		return false
	var asked := int(slice["askedBirthdayAt"])
	if asked > 0 and now_ms - asked < ASK_BIRTHDAY_RETRY_MS:
		return false
	return SoulTriggers.ambient_allowed(
		slice["ambient"], now_ms, SoulTriggers.day_string(ctx["date"])
	)


static func def_by_id(defs: Array, id: String) -> Dictionary:
	for def: Variant in defs:
		if def is Dictionary and str(def.get("id", "")) == id:
			return def
	return {}


# ── Entscheidungs-Stufen ──────────────────────────────────────────────────────


static func _decide_ritual(
	slice: Dictionary, defs: Array, ctx: Dictionary, roll: float
) -> Dictionary:
	var date: Dictionary = ctx["date"]
	var today := SoulTriggers.day_string(date)
	var celebrated: Dictionary = slice["celebrated"]
	var args := _base_args(slice, ctx)

	if SoulTriggers.is_birthday(slice["playerBirthday"], date):
		var gate := "geburtstag_spieler"
		if not SoulTriggers.celebrated_today(celebrated, gate, today):
			return _ritual(defs, "ritual_geburtstag_spieler", gate, today, args, roll)
	var gooby_birthday := SoulTriggers.birthday_from_ms(int(slice["firstMetAt"]))
	if int(slice["firstMetAt"]) > 0 and SoulTriggers.is_birthday(gooby_birthday, date):
		var gate := "geburtstag_gooby"
		if not SoulTriggers.celebrated_today(celebrated, gate, today):
			return _ritual(defs, "ritual_geburtstag_gooby", gate, today, args, roll)
	var days := SoulTriggers.days_known(int(slice["firstMetAt"]), int(ctx["now_ms"]))
	var milestone := SoulTriggers.anniversary_milestone(days)
	if milestone > 0:
		var gate := "jubilaeum_%d" % milestone
		if not SoulTriggers.celebrated_today(celebrated, gate, today):
			args["tage"] = milestone
			return _ritual(defs, "ritual_jubilaeum", gate, today, args, roll)
	var holiday := SoulTriggers.holiday_for(date)
	if not holiday.is_empty():
		var gate := "feiertag_" + holiday
		if not SoulTriggers.celebrated_today(celebrated, gate, today):
			return _ritual(defs, "ritual_" + holiday, gate, today, args, roll)
	var wetter: Dictionary = ctx.get("wetter", {})
	if bool(wetter.get("schnee", false)):
		var season := SoulTriggers.snow_season(date)
		var gate := "erster_schnee"
		if not SoulTriggers.celebrated_today(celebrated, gate, season):
			var moment := _ritual(defs, "ritual_erster_schnee", gate, season, args, roll)
			return moment
	return {}


static func _decide_greeting(
	slice: Dictionary, defs: Array, ctx: Dictionary, roll: float
) -> Dictionary:
	var today := SoulTriggers.day_string(ctx["date"])
	if str(slice["lastGreetDay"]) == today:
		return {}
	var args := _base_args(slice, ctx)
	var absence := SoulTriggers.absence_kind(int(ctx.get("gap_ms", 0)))
	var def_id := ""
	if not absence.is_empty():
		def_id = "gruss_" + absence
	else:
		def_id = "gruss_" + SoulTriggers.daypart(int(ctx.get("hour", 12)))
	var def := def_by_id(defs, def_id)
	if def.is_empty():
		return {}
	return _moment_from_def(def, "gruss", args, roll)


static func _decide_weather(
	slice: Dictionary, defs: Array, ctx: Dictionary, roll: float
) -> Dictionary:
	var wetter: Dictionary = ctx.get("wetter", {})
	var typ := str(wetter.get("typ", ""))
	if typ != "regen" and typ != "gewitter" and typ != "schnee":
		return {}
	# Wetter nur 1x pro Tag kommentieren (celebrated-Map, aber als Ambient
	# gebucht — zählt gegen die Frequenzbremse, blockt keine Rituale).
	var today := SoulTriggers.day_string(ctx["date"])
	if SoulTriggers.celebrated_today(slice["celebrated"], "wetter_" + typ, today):
		return {}
	var def := def_by_id(defs, "wetter_" + typ)
	if def.is_empty():
		return {}
	var moment := _moment_from_def(def, "wetter", _base_args(slice, ctx), roll)
	# Wetter-Tagesgate über book_enter mitschreiben.
	moment["gate_key"] = "wetter_" + typ
	moment["gate_stamp"] = today
	return moment


static func _decide_memory(
	state: Dictionary, slice: Dictionary, defs: Array, ctx: Dictionary, roll: float
) -> Dictionary:
	if roll >= MEMORY_CHANCE:
		return {}
	var candidates := SoulMemories.candidates(state)
	# roll unterhalb MEMORY_CHANCE auf 0..1 strecken → eine Zufallsquelle.
	var pick_roll := roll / MEMORY_CHANCE
	var memory := SoulMemories.pick(
		candidates, slice["memoryShownAt"], int(ctx["now_ms"]), pick_roll
	)
	if memory.is_empty():
		return {}
	var def := def_by_id(defs, "erinnerung")
	if def.is_empty():
		return {}
	var args := _base_args(slice, ctx)
	args.merge(memory.get("args", {}), true)
	var moment := _moment_from_def(def, "erinnerung", args, pick_roll)
	moment["text_key"] = str(memory["text_key"])
	moment["memory_id"] = str(memory["id"])
	return moment


# ── Bau-Helfer ────────────────────────────────────────────────────────────────


static func _ritual(
	defs: Array, def_id: String, gate_key: String, stamp: String, args: Dictionary, roll: float
) -> Dictionary:
	var def := def_by_id(defs, def_id)
	if def.is_empty():
		return {}
	var moment := _moment_from_def(def, "ritual", args, roll)
	moment["gate_key"] = gate_key
	moment["gate_stamp"] = stamp
	return moment


## Moment aus einem Def: Textvariante deterministisch über roll wählen,
## Anzeige-Metadaten (Emotion/Clip/SFX) durchreichen.
static func _moment_from_def(
	def: Dictionary, kind: String, args: Dictionary, roll: float
) -> Dictionary:
	var keys: Array = def.get("text_keys", [])
	var text_key := ""
	if not keys.is_empty():
		text_key = str(keys[int(clampf(roll, 0.0, 0.999999) * keys.size())])
	return {
		"id": str(def.get("id", "")),
		"kind": kind,
		"text_key": text_key,
		"args": args,
		"emotion": str(def.get("emotion", "happy")),
		"clip": str(def.get("clip", "")),
		"sfx": str(def.get("sfx", "")),
		"aktion": str(def.get("aktion", "")),
	}


## Basis-Platzhalter aller Texte. `namek` = ", <Name>" (Anrede-Komma) bzw.
## leer, wenn der Spieler keinen Namen gesetzt hat — so liest sich
## "Guten Morgen{namek}!" in beiden Fällen natürlich.
static func _base_args(slice: Dictionary, ctx: Dictionary) -> Dictionary:
	var days := SoulTriggers.days_known(int(slice["firstMetAt"]), int(ctx["now_ms"]))
	var player_name := str(ctx.get("player_name", ""))
	return {
		"name": player_name,
		"namek": (", " + player_name) if not player_name.is_empty() else "",
		"gooby": str(ctx.get("nickname", "Gooby")),
		"tage": days,
	}


static func _defs_of_kind(defs: Array, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for def: Variant in defs:
		if def is Dictionary and str(def.get("kind", "")) == kind:
			out.append(def)
	return out


static func _idle_requirement_met(def: Dictionary, ctx: Dictionary) -> bool:
	var requirement := str(def.get("braucht", ""))
	if requirement.is_empty():
		return true
	return bool(ctx.get(requirement, false))
