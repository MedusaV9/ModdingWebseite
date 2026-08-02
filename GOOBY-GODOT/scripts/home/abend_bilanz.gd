class_name AbendBilanz
extends RefCounted
## Gute-Nacht-Mini-Bilanz (G8/IDEA-SEELE, Idee 1 — Abend-Hälfte): 2–3 warme
## Zeilen „was heute schön war“ in der Bett-Nachtkarte, VOR dem Schlafen.
## Alles aus ECHTEN Tagesdaten des Saves — Streichler (achievements.counters
## petsToday/petsDay), abgeholte Tagesquests (quests.day/active.claimed),
## heute gespielte Minispiele (minigames.legacy.lastPlayDay) und die
## Tagesbonus-Serie (daily.streak). KEINE Meter, keine Pflichten — Bilanz
## statt Abrechnung; ohne Befund bleibt die „einfach zusammen sein“-Zeile.
##
## zeilen()/anzeigen() sind PUR (State + Tag/Stunde rein — headless testbar
## mit injizierter Uhr); anbauen() ist der EINE Glue-Aufruf für bett.gd
## (Zeilen-Budget!) und hängt den Block nur an, wenn es Abend ist und Gooby
## noch wach liegt.

const Sleep := preload("res://scripts/logic/sleep.gd")

## Abend-Fenster: ab 18 Uhr bzw. bis 4 Uhr früh (Nachteulen).
const ABEND_AB := 18
const NACHT_BIS := 4
## Höchstens so viele Bilanz-Zeilen (2–3 laut Idee — nie eine Liste).
const MAX_ZEILEN := 3


## Zeigt die Bett-Karte die Bilanz zu dieser lokalen Stunde?
static func anzeigen(stunde: int) -> bool:
	return stunde >= ABEND_AB or stunde < NACHT_BIS


## Bilanz-Zeilen [{key, args, spiel_key?}] in fester Wärme-Reihenfolge:
## Streicheln → Quests → Minispiel → Serie, gedeckelt auf MAX_ZEILEN.
## Ohne Befund EINE ruhige Zusammen-sein-Zeile ({} kommt nie zurück).
static func zeilen(state: Dictionary, heute: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var counters := _map(_map(state.get("achievements")).get("counters"))
	var streichler := int(_num(counters.get("petsToday")))
	if str(counters.get("petsDay", "")) == heute and streichler > 0:
		out.append({"key": "seele_tag.abend.streicheln", "args": {"anzahl": streichler}})
	var quests := _quests_geschafft(state, heute)
	if quests == 1:
		out.append({"key": "seele_tag.abend.quest_eine", "args": {}})
	elif quests > 1:
		out.append({"key": "seele_tag.abend.quest_viele", "args": {"anzahl": quests}})
	var spiel := _spiel_heute(state, heute)
	if not spiel.is_empty() and out.size() < MAX_ZEILEN:
		out.append({"key": "seele_tag.abend.spiel", "args": {}, "spiel_id": spiel})
	var daily := _map(state.get("daily"))
	var serie := int(_num(daily.get("streak")))
	if str(daily.get("lastClaimDay", "")) == heute and serie >= 2 and out.size() < MAX_ZEILEN:
		out.append({"key": "seele_tag.abend.serie", "args": {"tage": serie}})
	while out.size() > MAX_ZEILEN:
		out.pop_back()
	if out.is_empty():
		out.append({"key": "seele_tag.abend.ruhig", "args": {}})
	return out


## Heute ABGEHOLTE Tagesquests (claimed = wirklich gefeiert; das Brett
## gehört über quests.day immer genau EINEM Lokaltag).
static func _quests_geschafft(state: Dictionary, heute: String) -> int:
	var slice := _map(state.get("quests"))
	if str(slice.get("day", "")) != heute or not (slice.get("active") is Array):
		return 0
	var anzahl := 0
	for eintrag: Variant in slice["active"]:
		if eintrag is Dictionary and bool((eintrag as Dictionary).get("claimed", false)):
			anzahl += 1
	return anzahl


## Erstes heute gespielte Minispiel (Id, sortiert = deterministisch).
static func _spiel_heute(state: Dictionary, heute: String) -> String:
	var last_play := _map(_map(_map(state.get("minigames")).get("legacy")).get("lastPlayDay"))
	var ids: Array = last_play.keys()
	ids.sort()
	for spiel_id: Variant in ids:
		if str(last_play[spiel_id]) == heute:
			return str(spiel_id)
	return ""


# ── Glue für die Bett-Nachtkarte ─────────────────────────────────────────────


## EIN Aufruf aus bett.gd._open_panel: hängt den Bilanz-Block an `box`,
## wenn es Abend ist und Gooby nicht schon schläft (die Weck-Karte braucht
## keine Bilanz). Uhrzeit kommt aus der pinnbaren GameState-Clock.
static func anbauen(box: VBoxContainer, gs: Object, now_ms: int) -> void:
	if gs == null or not gs.has_method("state"):
		return
	var state: Dictionary = gs.state()
	if Sleep.is_sleeping(Sleep.flat_of(state)):
		return
	var zeit := MorgenRitual.lokale_zeit(now_ms, _offset_min(gs))
	if not anzeigen(int(zeit.get("hour", 12))):
		return
	var heute := _heute(gs, now_ms)
	box.add_child(_block(zeilen(state, heute)))


## Bilanz-Block (Titel + Zeilen) als eigener Knoten — reine Darstellung.
static func _block(eintraege: Array[Dictionary]) -> Control:
	var spalte := VBoxContainer.new()
	spalte.name = "AbendBilanz"
	spalte.add_theme_constant_override("separation", 2)
	var titel := Label.new()
	titel.name = "BilanzTitel"
	titel.theme_type_variation = &"CaptionLabel"
	titel.text = I18nService.t("seele_tag.abend.titel")
	titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spalte.add_child(titel)
	for i in eintraege.size():
		var eintrag := eintraege[i]
		var args: Dictionary = (eintrag.get("args", {}) as Dictionary).duplicate()
		var spiel_id := str(eintrag.get("spiel_id", ""))
		if not spiel_id.is_empty():
			var meta := MinigameRegistry.get_game(spiel_id)
			args["spiel"] = I18nService.t(str(meta.get("title_key", spiel_id)))
		var zeile := Label.new()
		zeile.name = "BilanzZeile%d" % (i + 1)
		zeile.theme_type_variation = &"SoftLabel"
		zeile.text = I18nService.t(str(eintrag["key"]), args)
		zeile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		zeile.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		spalte.add_child(zeile)
	return spalte


static func _heute(gs: Object, now_ms: int) -> String:
	if "clock" in gs:
		return str(gs.clock.local_day(now_ms))
	var d := Time.get_datetime_dict_from_unix_time(int(now_ms / 1000.0))
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


## Offset-Override der Clock spiegeln (Muster morgen_sequenz._offset_min).
static func _offset_min(gs: Object) -> Variant:
	if "clock" in gs:
		var clock: Variant = gs.clock
		if bool(clock.get("_offset_overridden")):
			return int(clock.get("_offset_minutes"))
	return null


static func _map(raw: Variant) -> Dictionary:
	return raw if raw is Dictionary else {}


static func _num(value: Variant) -> float:
	if value is int or value is float:
		return float(value)
	return 0.0
