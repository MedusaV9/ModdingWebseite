class_name RcompRichterRennen
extends RefCounted
## Richter Grasbahn-Rennen (RW-5): 3 Runden Oval gegen vorsimulierte
## Bot-Zeiten. Abkürzen zählt nicht (Viertel-Checkpoints der Reihe nach);
## Windschatten (< 2 m hinter einem Bot, 1 s Aufbau) gibt +3 % — als
## Extra-Bahnfortschritt verbucht (Doc-Formel via RcompWertungRennen).
## PURE (Positionen + Zeit rein).

const Kurs := preload("res://scripts/ranch/comp/szene/comp_kurs.gd")
const Wertung := preload("res://scripts/ranch/comp/wertung/wertung_rennen.gd")

const RUNDEN := 3
const BOT_NAH_M := 4.0

var bots: Array[Dictionary] = []
var viertel_treffer := 0
var extra_s := 0.0
var im_ziel := false
var boost_aktiv := false

var _zustand := Wertung.neuer_zustand()
var _s_jetzt := 0.0
var _boost_s_summe := 0.0


## bots = [{id, zeit_s}] (Gesamtzeit über 3 Runden, aus der Simulation).
func setup_bots(bot_zeiten: Array[Dictionary]) -> void:
	bots = bot_zeiten


func fertig() -> bool:
	return im_ziel


## Bahnfortschritt (m) eines Bots zur Zeit t (konstantes Renntempo).
func bot_fortschritt_m(bot: Dictionary, t: float) -> float:
	var zeit := maxf(1.0, float(bot.get("zeit_s", 90.0)))
	return clampf(t / zeit, 0.0, 1.0) * RUNDEN * Kurs.rennen_umfang()


## Spieler-Bahnfortschritt (m) inkl. Windschatten-Gutschrift.
func spieler_fortschritt_m() -> float:
	var umfang := Kurs.rennen_umfang()
	var viertel := umfang * 0.25
	var basis := float(viertel_treffer) * viertel
	var rest := fposmod(_s_jetzt, viertel)
	return basis + minf(rest, viertel) + extra_s


func runde_jetzt() -> int:
	return mini(viertel_treffer / 4 + 1, RUNDEN)


func tick(_vorher: Vector3, jetzt: Vector3, _gait: String, _in_luft: bool, dt: float) -> Array:
	if im_ziel:
		return []
	var events: Array = []
	var umfang := Kurs.rennen_umfang()
	_s_jetzt = Kurs.rennen_s_bei(jetzt)
	# Viertel-Checkpoints der Reihe nach — verhindert Abkürzen übers Feld.
	var naechstes_viertel := fposmod(float(viertel_treffer + 1) * umfang * 0.25, umfang)
	if absf(_s_jetzt - naechstes_viertel) < 6.0:
		viertel_treffer += 1
		if viertel_treffer % 4 == 0 and viertel_treffer < RUNDEN * 4:
			events.append({"typ": "runde", "nummer": viertel_treffer / 4 + 1})
	if viertel_treffer >= RUNDEN * 4:
		im_ziel = true
		events.append({"typ": "ziel"})
		return events
	_windschatten(jetzt, dt, events)
	return events


func ergebnis(zeit_s: float) -> Dictionary:
	return {
		"wert": zeit_s,
		"zeit_s": zeit_s,
		"detail": {"boost_s": _boost_s_summe, "extra_m": extra_s},
	}


func hud() -> Dictionary:
	return {"key": "rcomp.hud.runde", "params": {"n": runde_jetzt(), "max": RUNDEN}}


func _windschatten(jetzt: Vector3, dt: float, events: Array) -> void:
	var eigenes := spieler_fortschritt_m() - extra_s
	var dahinter := false
	for bot in bots:
		var vorsprung := float(bot.get("fortschritt_m", 0.0)) - eigenes
		var pos: Variant = bot.get("pos")
		var nah := true
		if pos is Vector3:
			nah = (
				Vector2(jetzt.x - (pos as Vector3).x, jetzt.z - (pos as Vector3).z).length()
				< BOT_NAH_M
			)
		if nah and Wertung.im_fenster(vorsprung, 1.0):
			dahinter = true
			break
	_zustand = Wertung.step_windschatten(_zustand, dahinter, dt)
	var boost := Wertung.tempo_mult(_zustand) > 1.0
	if boost and not boost_aktiv:
		events.append({"typ": "windschatten"})
	boost_aktiv = boost
	if boost:
		_boost_s_summe += dt
		# +3 % Tempo als Bahn-Gutschrift (die Physik gehört RW-2 und
		# bleibt unangetastet) — 6 m/s Renntempo angenommen.
		extra_s += 6.0 * Wertung.WINDSCHATTEN_BOOST * dt
