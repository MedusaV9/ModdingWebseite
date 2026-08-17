class_name GoobyeAngebot
extends RefCounted
## Tagesangebot des „Goo und Bye“ (W19 Welle B, Doc §4.4) — PURE + static.
## Der Spieler markiert 1 Warengruppe pro Tag als „Tagesangebot“: −15 % auf
## den Stückpreis, +40 % Griff-Wahrscheinlichkeit in der Kunden-Sim — der
## deterministische Zwilling von McGoobys Tages-Special, hier vom SPIELER
## gewählt (Manager-Gefühl). Der „Tag“ kommt IMMER aus der injizierten Uhr
## (tag_key aus now_ms, Clock-Muster game_state.gd) — kein OS-Datum in der
## Logik, golden-testbar.
##
## Determinismus-Vertrag mit GoobyeMarkttag: das Angebot verändert NUR
## Vergleiche (Griff-Chance) und Preise, NIE die vorab gezogene
## Zufallsfolge — mit Angebot verkauft die Gruppe nie weniger (Monotonie).

## §4.4: −15 % Preis, +40 % Griff-Wahrscheinlichkeit.
const RABATT := 0.15
const GRIFF_BONUS := 0.4

## 6 Gooby-Kritzel-Schild-Varianten (§4.4) — Welle B: einfache prozedurale
## Schilder; die Variante ist deterministisch aus Tag + Gruppe.
const SCHILD_VARIANTEN := 6

const RESULT_OK := "ok"
const RESULT_SCHON_GEWAEHLT := "schon_gewaehlt"
const RESULT_UNBEKANNT := "unbekannte_gruppe"

## ------------------------------------------------------------ Preis-Seite


## Angebots-Stückpreis: Schieber-Stellung wie üblich, dann −15 % — EINE
## Rundung am Ende (nie unter 1 Münze, Muster GoobyePreis.verkaufspreis).
static func angebots_preis(ware: Dictionary, faktor := 1.0) -> int:
	var basis := float(GoobyePreis.empfohlener_preis(ware))
	basis *= GoobyePreis.faktor_begrenzen(faktor)
	return maxi(1, roundi(basis * (1.0 - RABATT)))


## Stückpreis einer Sortiments-Zeile — Angebots-Zeilen zahlen den
## Angebots-Preis, alle anderen exakt den Welle-A-Preis (Golden-stabil).
static func preis_fuer_zeile(ware: Dictionary, faktor: float, angebot: bool) -> int:
	if angebot:
		return angebots_preis(ware, faktor)
	return GoobyePreis.verkaufspreis(ware, faktor)


## ------------------------------------------------------------ Tages-Logik


## Tag-Key ("YYYY-MM-DD") aus der injizierten Uhr — identische Rechnung
## wie der Markttag-Seed der Laden-Szene (gleiche Tagesgrenze).
static func tag_key(now_ms: int) -> String:
	return Time.get_date_string_from_unix_time(floori(float(now_ms) / 1000.0))


## Gilt das gespeicherte Angebot {gruppe, tag} heute noch?
static func ist_aktiv(angebot: Dictionary, tag: String) -> bool:
	return not str(angebot.get("gruppe", "")).is_empty() and str(angebot.get("tag", "")) == tag


## Aktive Angebots-Gruppe ("" = heute keine).
static func aktive_gruppe(angebot: Dictionary, tag: String) -> String:
	return str(angebot.get("gruppe", "")) if ist_aktiv(angebot, tag) else ""


## Sortiments-Zeilen fürs Markttag-Modul markieren (PURE, tiefe Kopien):
## Zeilen der Angebots-Gruppe bekommen `angebot: true`.
static func sortiment_markieren(sortiment: Array, gruppe_id: String) -> Array:
	var out: Array = []
	for zeile: Variant in sortiment:
		if not (zeile is Dictionary):
			out.append(zeile)
			continue
		var kopie: Dictionary = (zeile as Dictionary).duplicate(true)
		if not gruppe_id.is_empty():
			var ware := GoobyeKatalog.ware(str(kopie.get("id", "")))
			if str(ware.get("gruppe", "")) == gruppe_id:
				kopie["angebot"] = true
		out.append(kopie)
	return out


## Kritzel-Schild-Variante 0..5 — deterministisch aus Tag + Gruppe (gleicher
## Tag + gleiche Gruppe = gleiches Schild, auch nach App-Neustart).
static func schild_variante(tag: String, gruppe_id: String) -> int:
	return absi(("%s|%s" % [tag, gruppe_id]).hash()) % SCHILD_VARIANTEN


## ------------------------------------------------------------ Save-Flüsse


## Gespeichertes Angebot {gruppe, tag} (Kopie).
static func angebot_von(gs: Object) -> Dictionary:
	if gs == null:
		return {"gruppe": "", "tag": ""}
	var raw: Variant = gs.get_value("dlc.goobye.tagesangebot", {})
	if not (raw is Dictionary):
		return {"gruppe": "", "tag": ""}
	return {
		"gruppe": str((raw as Dictionary).get("gruppe", "")),
		"tag": str((raw as Dictionary).get("tag", ""))
	}


## Aktive Angebots-Gruppe für den Spielstand ("" = keine heute).
static func aktive_gruppe_von(gs: Object, now_ms := -1) -> String:
	return aktive_gruppe(angebot_von(gs), tag_key(_now(gs, now_ms)))


## Tagesangebot wählen: EINE Gruppe pro Tag (§4.4). Dieselbe Gruppe erneut
## wählen ist ein stilles OK; eine ANDERE Gruppe am selben Tag blockt —
## morgen wieder (kein Fail-State, nur eine Manager-Entscheidung pro Tag).
static func waehle(gs: Object, gruppe_id: String, now_ms := -1) -> String:
	if gs == null or GoobyeKatalog.gruppe(gruppe_id).is_empty():
		return RESULT_UNBEKANNT
	var tag := tag_key(_now(gs, now_ms))
	var bisher := angebot_von(gs)
	if ist_aktiv(bisher, tag):
		if str(bisher["gruppe"]) == gruppe_id:
			return RESULT_OK
		return RESULT_SCHON_GEWAEHLT
	gs.update(
		func(state: Dictionary) -> void:
			var goobye := GoobyeState.ensure_goobye(state)
			goobye["tagesangebot"] = {"gruppe": gruppe_id, "tag": tag}
	)
	gs.notify_slice_changed(GoobyeState.SLICE_ID)
	return RESULT_OK


static func _now(gs: Object, now_ms: int) -> int:
	if now_ms >= 0:
		return now_ms
	if gs != null and "clock" in gs:
		return int(gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)
