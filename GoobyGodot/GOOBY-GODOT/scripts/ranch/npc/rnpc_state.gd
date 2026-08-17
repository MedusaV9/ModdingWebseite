class_name RNpcState
extends RefCounted
## GameState-Anbindung des Freundschafts-Systems (RW-3): liest/schreibt
## `ranch.npc` (RQuestSlices-Form, normalize-on-read) über Duck-Typing
## (`gs` = /root/GameState oder Test-Instanz) — Muster RanchState.
## Die Mathematik liegt PURE in RNpcFreundschaft; hier nur Save-Glue.

const SLICE_ID := "ranch"


## Normalisierter npc-Unterschlüssel ({} -Default bei fehlendem gs).
static func npc_daten(gs: Object) -> Dictionary:
	if gs == null:
		return RQuestSlices.default_npc()
	return RQuestSlices.normalize_npc(gs.get_value("ranch.npc", null))


## Freund-Eintrag eines NPC (frisch, mit angewendetem Verfall).
static func freund(gs: Object, npc_id: String, now_ms: int) -> Dictionary:
	var eintrag: Variant = npc_daten(gs).get("freunde", {}).get(npc_id)
	var daten: Dictionary = eintrag if eintrag is Dictionary else RQuestSlices.neuer_freund()
	daten = daten.duplicate(true)
	daten["punkte"] = RNpcFreundschaft.punkte_nach_verfall(
		float(daten.get("punkte", 0.0)), int(daten.get("letzteBegegnungAt", 0)), now_ms
	)
	return daten


## Herz-Stufe eines NPC (inkl. Verfall).
static func herzen(gs: Object, npc_id: String, now_ms: int) -> int:
	return RNpcFreundschaft.herzen(float(freund(gs, npc_id, now_ms).get("punkte", 0.0)))


## npcId → Herz-Stufe für alle Katalog-NPCs (Quest-Gates, UI).
static func herzen_map(gs: Object, now_ms: int) -> Dictionary:
	var out := {}
	for npc_id: String in RNpcKatalog.ids():
		out[npc_id] = herzen(gs, npc_id, now_ms)
	return out


## Gespräch buchen → {neu_freigeschaltet:[...]} (für Toasts/UI).
static func reden(gs: Object, npc_id: String, tag: String, now_ms: int) -> Dictionary:
	var vorher := freund(gs, npc_id, now_ms)
	var nachher := RNpcFreundschaft.reden(vorher, tag, now_ms)
	_speichere_freund(gs, npc_id, nachher)
	return _delta(npc_id, vorher, nachher)


## Geschenk buchen → {reaktion, neu_freigeschaltet}.
static func geschenk(
	gs: Object, npc_id: String, item: String, tag: String, now_ms: int
) -> Dictionary:
	var def := RNpcKatalog.npc(npc_id)
	var vorher := freund(gs, npc_id, now_ms)
	var nachher := RNpcFreundschaft.geschenk(vorher, def, item, tag, now_ms)
	_speichere_freund(gs, npc_id, nachher)
	var out := _delta(npc_id, vorher, nachher)
	out["reaktion"] = RNpcFreundschaft.geschenk_reaktion(def, item)
	return out


## Quest-Abgabe beim Geber + Belohnungs-Herzen buchen.
static func quest_bonus(gs: Object, npc_id: String, extra_punkte: float, now_ms: int) -> Dictionary:
	var vorher := freund(gs, npc_id, now_ms)
	var nachher := RNpcFreundschaft.quest_abgeschlossen(vorher, now_ms)
	nachher = RNpcFreundschaft.bonus(nachher, extra_punkte, now_ms)
	_speichere_freund(gs, npc_id, nachher)
	return _delta(npc_id, vorher, nachher)


## Persönliche Geschichte als gehört markieren (Dialog-Gate: einmalig).
static func geschichte_gehoert(gs: Object, npc_id: String, knoten: String, now_ms: int) -> void:
	var daten := freund(gs, npc_id, now_ms)
	if not (daten["geschichtenGehoert"] as Array).has(knoten):
		(daten["geschichtenGehoert"] as Array).append(knoten)
	_speichere_freund(gs, npc_id, daten)


static func _delta(npc_id: String, vorher: Dictionary, nachher: Dictionary) -> Dictionary:
	return {
		"punkte": float(nachher.get("punkte", 0.0)),
		"herzen": RNpcFreundschaft.herzen(float(nachher.get("punkte", 0.0))),
		"neu_freigeschaltet":
		RNpcFreundschaft.neue_freischaltungen(
			RNpcKatalog.npc(npc_id),
			float(vorher.get("punkte", 0.0)),
			float(nachher.get("punkte", 0.0))
		),
	}


static func _speichere_freund(gs: Object, npc_id: String, daten: Dictionary) -> void:
	if gs == null:
		return
	gs.update(
		func(state: Dictionary) -> void:
			if not (state.get(SLICE_ID) is Dictionary):
				state[SLICE_ID] = {}
			var ranch: Dictionary = state[SLICE_ID]
			ranch["npc"] = RQuestSlices.normalize_npc(ranch.get("npc"))
			(ranch["npc"]["freunde"] as Dictionary)[npc_id] = daten
	)
	gs.notify_slice_changed(SLICE_ID)
