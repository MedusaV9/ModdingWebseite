class_name RQuestState
extends RefCounted
## GameState-Anbindung der Quest-Engine (RW-3): liest/schreibt
## `ranch.quests` (normalize-on-read), wendet Belohnungen an und verdrahtet
## Warte-Quests mit NotifyStub/Live-Activity. Duck-Typing (`gs` =
## /root/GameState oder Test-Instanz), Muster RanchState/RNpcState.
##
## Zeitquelle: gs.clock (pinnbare Uhr, W1d) wenn vorhanden, sonst
## Systemzeit — Tests pinnen die Uhr und springen durch Warte-Quests.

const SLICE_ID := "ranch"


## Aktuelle Zeit in epoch-ms (gs.clock bevorzugt).
static func now_ms(gs: Object) -> int:
	if gs != null:
		var clock: Variant = gs.get("clock")
		if clock is Object and (clock as Object).has_method("now_ms"):
			return int(clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)


## Lokaler Kalendertag (YYYY-MM-DD; gs.clock.local_day bevorzugt).
static func datum(gs: Object) -> String:
	if gs != null:
		var clock: Variant = gs.get("clock")
		if clock is Object and (clock as Object).has_method("local_day"):
			return str(clock.local_day())
	var d := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system()))
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


## Normalisierter quests-Unterschlüssel.
static func quests(gs: Object) -> Dictionary:
	if gs == null:
		return RQuestSlices.default_quests()
	return RQuestSlices.normalize_quests(gs.get_value("ranch.quests", null))


## Abgeleiteter Status einer Quest-Id (inkl. Herz-Gates).
static func status(gs: Object, quest_id: String) -> String:
	var def := RQuestKatalog.quest(quest_id)
	if def.is_empty():
		return RQuestEngine.STATUS_GESPERRT
	return RQuestEngine.status_von(quests(gs), def, RNpcState.herzen_map(gs, now_ms(gs)), datum(gs))


## Alle jetzt annehmbaren Quests (inkl. Tagesaufgaben).
static func verfuegbare(gs: Object) -> Array:
	return RQuestEngine.verfuegbare(quests(gs), RNpcState.herzen_map(gs, now_ms(gs)), datum(gs))


## Quest annehmen; startet ein führendes Warte-Ziel inkl. Notification/
## Live-Activity. true = angenommen.
static func annehmen(gs: Object, quest_id: String) -> bool:
	var def := RQuestKatalog.quest(quest_id)
	if def.is_empty():
		return false
	var jetzt := now_ms(gs)
	var alt := quests(gs)
	var neu := RQuestEngine.annehmen(alt, def, jetzt, RNpcState.herzen_map(gs, jetzt))
	if neu == alt:
		return false
	_speichere(gs, neu)
	_warte_verdrahten(def, neu, jetzt)
	return true


## Spiel-Ereignis (z. B. {typ:"sprich_mit", npc:"rosi"}) auf ALLE aktiven
## Quests buchen → Liste der geänderten Quest-Ids.
static func ereignis(gs: Object, was: Dictionary) -> Array:
	var jetzt := now_ms(gs)
	var stand := quests(gs)
	var geaendert: Array = []
	for quest_id: String in (stand.get("aktiv", {}) as Dictionary).keys():
		var def := RQuestKatalog.quest(quest_id)
		if def.is_empty():
			continue
		var ergebnis := RQuestEngine.ereignis(stand, def, was, jetzt)
		if bool(ergebnis["geaendert"]):
			stand = ergebnis["quests"]
			geaendert.append(quest_id)
			_warte_verdrahten(def, stand, jetzt)
	if not geaendert.is_empty():
		_speichere(gs, stand)
	return geaendert


## Fällige Warte-Ziele auflösen (App-Start, Resume, Minuten-Timer) →
## Liste fertig gewarteter Quest-Ids.
static func tick(gs: Object) -> Array:
	var jetzt := now_ms(gs)
	var ergebnis := RQuestEngine.tick(quests(gs), jetzt)
	var fertig: Array = ergebnis["fertig"]
	if not fertig.is_empty():
		_speichere(gs, ergebnis["quests"])
		for quest_id: String in fertig:
			RQuestWarte.warte_fertig(quest_id)
			var def := RQuestKatalog.quest(quest_id)
			_warte_verdrahten(def, ergebnis["quests"], jetzt)
	return fertig


## Erfüllbare Quest abgeben: Belohnung anwenden (Münzen → economy.coins,
## Items → ranch.wirtschaft.lager, Herzen → Freundschaft, freischalten →
## ranch.quests.freigeschaltet) + Geber-Bonus. true = abgegeben.
static func abgeben(gs: Object, quest_id: String) -> bool:
	var def := RQuestKatalog.quest(quest_id)
	if def.is_empty():
		return false
	var ergebnis := RQuestEngine.abgeben(quests(gs), def, datum(gs))
	if not bool(ergebnis["ok"]):
		return false
	_speichere(gs, ergebnis["quests"])
	RQuestWarte.aufraeumen(quest_id)
	_belohnung_anwenden(gs, def, ergebnis["belohnung"])
	return true


## Aktueller Kapitel-Stand (1..11; 11 = Reihe durchgespielt).
static func kapitel(gs: Object) -> int:
	return RQuestEngine.kapitel(quests(gs))


static func _speichere(gs: Object, neu: Dictionary) -> void:
	if gs == null:
		return
	gs.update(
		func(state: Dictionary) -> void:
			if not (state.get(SLICE_ID) is Dictionary):
				state[SLICE_ID] = {}
			(state[SLICE_ID] as Dictionary)["quests"] = neu
	)
	gs.notify_slice_changed(SLICE_ID)


## Falls der aktuelle Lauf einer Quest gerade WARTET: Notification +
## (optional) Live-Activity sicherstellen — id-idempotent, doppelte
## Aufrufe ersetzen nur den Eintrag.
static func _warte_verdrahten(def: Dictionary, stand: Dictionary, _jetzt: int) -> void:
	var quest_id := str(def.get("id", ""))
	var lauf: Variant = (stand.get("aktiv", {}) as Dictionary).get(quest_id)
	if not (lauf is Dictionary):
		return
	if str((lauf as Dictionary).get("status")) != RQuestSlices.STATUS_WARTEND:
		return
	var ziel := RQuestEngine.aktuelles_ziel(def, lauf)
	RQuestWarte.warte_gestartet(quest_id, ziel, lauf, I18nService.t("rquest.q.%s.titel" % quest_id))


static func _belohnung_anwenden(gs: Object, def: Dictionary, belohnung: Dictionary) -> void:
	if gs == null or belohnung.is_empty():
		return
	var muenzen := maxi(0, int(belohnung.get("muenzen", 0)))
	var items: Dictionary = belohnung.get("items") if belohnung.get("items") is Dictionary else {}
	if muenzen > 0 or not items.is_empty():
		gs.update(
			func(state: Dictionary) -> void:
				if muenzen > 0 and state.get("economy") is Dictionary:
					var economy: Dictionary = state["economy"]
					economy["coins"] = int(economy.get("coins", 0)) + muenzen
				if not items.is_empty() and state.get(SLICE_ID) is Dictionary:
					var ranch: Dictionary = state[SLICE_ID]
					if not (ranch.get("wirtschaft") is Dictionary):
						ranch["wirtschaft"] = {}
					var wirtschaft: Dictionary = ranch["wirtschaft"]
					if not (wirtschaft.get("lager") is Dictionary):
						wirtschaft["lager"] = {}
					var lager: Dictionary = wirtschaft["lager"]
					for item: String in items:
						lager[item] = int(lager.get(item, 0)) + maxi(0, int(items[item]))
		)
	var jetzt := now_ms(gs)
	var herzen: Dictionary = (
		belohnung.get("herzen") if belohnung.get("herzen") is Dictionary else {}
	)
	var geber := str(def.get("geber", ""))
	if not geber.is_empty():
		RNpcState.quest_bonus(gs, geber, float(herzen.get(geber, 0.0)), jetzt)
	for npc_id: String in herzen:
		if npc_id != geber:
			RNpcState.quest_bonus(gs, npc_id, float(herzen[npc_id]), jetzt)
