class_name UrlaubsBonus
extends RefCounted
## W13B/RAUMSTATION (Doc E §3.3) — Urlaubs-Nutzen-Glue über den puren
## W13B-Latches in vacation.gd/reise_logic.gd:
##
## 1. ERHOLUNGS-BOOST: `abholen()` stempelt `vacation.erholtBis` (now+48 h).
##    `sync()` spiegelt das als „erholt“-Buff in den BESTEHENDEN
##    Event-Buff-Slice (GoobyBuffs) — damit hängt die Anzeige an der
##    vorhandenen Buff-Chip-Leiste der Energie-Zeile (KEIN HUD-Umbau; das
##    Sonnen-Icon am Chip ist ein Request an den HUD-Owner). Die eigentliche
##    Drain-Bremse (×0,8) rechnet der Ticker über
##    `Vacation.energie_drain_faktor()` (Request an den Ticker-Owner).
## 2. WELTENGOOBY-TITEL: `abholen()` latcht `weltengoobyAt` bei 9/9
##    besuchten Zielen. `sync()` feiert das GENAU EINMAL (Toast auf der
##    globalen ToastLayer — dieselbe Schiene, auf der der RewardHub feiert;
##    der 9/9-Erfolg „weltenbummler“ bringt parallel Konfetti über den
##    RewardHub-Achievement-Pfad).
##
## `sync()` ist idempotent und darf beliebig oft laufen (Ort-Betreten,
## vacation_changed-Signal) — Zeit wird IMMER injiziert (now_ms).

const Vacation := preload("res://scripts/logic/vacation.gd")

## Buff-Eintrag im GoobyBuffs-Format ({id, stat, wert, until_ms}).
const BUFF_ID := "erholt"
const BUFF_STAT := "energy"
## Sichtbarer Chip-Wert („+5“) — Doc E §3.3 („Aufwachen gibt +5 Laune“);
## der eigentliche Nutzen ist die Drain-Bremse, nicht dieser Zahlwert.
const BUFF_WERT := 5.0
## Regrant-Toleranz: kleiner Rundungs-Drift zwischen until_ms und erholtBis
## (dauer_h-Umrechnung) darf NICHT jede sync()-Runde neu granten.
const BUFF_TOLERANZ_MS := 60_000


## Kompletter Abgleich Save → Buff/Feier. Rückgabe (für Tests):
## {buff_gewaehrt: bool, weltengooby_gefeiert: bool}.
## `host` (optional) = Node im Baum für Toast + Jingle.
static func sync(gs: Object, now_ms: int, host: Node = null) -> Dictionary:
	var result := {"buff_gewaehrt": false, "weltengooby_gefeiert": false}
	if gs == null:
		return result
	var v := Vacation.slice_of(gs.state())
	if _braucht_buff(gs, v, now_ms):
		_gewaehre_buff(gs, int(v["erholtBis"]), now_ms)
		result["buff_gewaehrt"] = true
	if Vacation.weltengooby(v) and not bool(v["weltengoobyGefeiert"]):
		_latche_feier(gs)
		_feiere(host)
		result["weltengooby_gefeiert"] = true
	return result


## Fehlt der „erholt“-Buff (oder endet er deutlich vor erholtBis)?
static func _braucht_buff(gs: Object, v: Dictionary, now_ms: int) -> bool:
	if not Vacation.erholungs_boost_aktiv(v, now_ms):
		return false
	var slice: Variant = gs.get_value("buffs", {})
	if not (slice is Dictionary):
		return true
	var erholt_bis := int(v["erholtBis"])
	for buff: Variant in (slice as Dictionary).get("aktiv", []):
		if buff is Dictionary and str(buff.get("id", "")) == BUFF_ID:
			return int(buff.get("until_ms", 0)) < erholt_bis - BUFF_TOLERANZ_MS
	return true


## Buff über den BESTEHENDEN GoobyBuffs-Pfad granten — Laufzeit exakt bis
## erholtBis (dauer_h rückgerechnet, damit Buff-Chip und Drain-Bremse
## zusammen auslaufen).
static func _gewaehre_buff(gs: Object, erholt_bis: int, now_ms: int) -> void:
	var dauer_h := float(erholt_bis - now_ms) / float(GoobyBuffs.MS_PER_HOUR)
	GoobyBuffs.grant(gs, BUFF_ID, BUFF_STAT, BUFF_WERT, dauer_h, now_ms)


## Feier-Latch in den vacation-Slice schreiben (überlebt slice_of).
static func _latche_feier(gs: Object) -> void:
	gs.update(
		func(state: Dictionary) -> void:
			if state.get("vacation") is Dictionary:
				state["vacation"]["weltengoobyGefeiert"] = true
	)
	if gs.has_method("notify_slice_changed"):
		gs.notify_slice_changed("vacation")


## Feier-Toast auf der globalen ToastLayer (RewardHub-Schiene) + Jingle.
static func _feiere(host: Node) -> void:
	if host == null or not host.is_inside_tree():
		return
	var toasts := host.get_tree().root.find_children("*", "ToastLayer", true, false)
	if not toasts.is_empty():
		toasts[0].show_toast(I18nService.t("raumstation.weltengooby.toast"))
	AudioDirector.try_play(host, "ui_sticker")
