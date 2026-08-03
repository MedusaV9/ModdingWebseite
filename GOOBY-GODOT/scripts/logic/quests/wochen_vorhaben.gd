class_name WochenVorhaben
extends RefCounted
## Wochen-Vorhaben-Engine (G8 IDEA-WOCHE, Progression-Top-1): pro Woche EIN
## erzählter 3–5-Schritte-Bogen mit Mini-Geschichte — PURE Statics nach dem
## Muster von DailyQuestEngine (Slice, Pool, Kontext und Zeit werden
## hereingereicht, alles headless testbar).
##
## Semantik (bindend, Wohlfühl-Regeln aus G8-IDEEN-progression.md Nr. 1):
## - Das ANGEBOT der Woche ist deterministisch: mulberry32(hash32(
##   "vorhaben:" + iso_woche)) wählt aus dem gefilterten Katalog — alle
##   Spieler mit gleicher Historie sehen in derselben Woche denselben Bogen.
## - KEINE Deadline: ein unfertiger Bogen läuft über Wochen einfach weiter;
##   der nächste startet erst nach Abschluss, frühestens am nächsten
##   Wochenanfang (der Seed bestimmt nur das Angebot, nie einen Verfall).
## - Schritte laufen SEQUENZIELL (Ranch-Vorbild rquest_engine.gd:
##   zielIndex/zaehler): pro aktivem Schritt wird die Baseline der
##   VORHANDENEN Zähler eingefroren (DailyQuestEngine.baseline_of), der
##   Fortschritt ist die Differenz seither — kein neues Tracking-System.
## - feiern() markiert nur und liefert die Belohnung; die Auszahlung macht
##   der Aufrufer über den EINEN Geld/XP-Pfad (quest_service._pay, reason
##   "vorhaben"). Doppel-Feiern ist unmöglich (aktiv-Slot wird geleert).
##
## Save-Slice (ADDITIV im bestehenden `quests`-Dict, KEIN Version-Bump):
##   quests.vorhaben = {id, woche, schritt, base:{...}, fertigIds:[],
##                      letzteId, fertigWoche}

## Erlaubte Schritt-Spanne pro Bogen (Katalog-Wache + Tests).
const SCHRITTE_MIN := 3
const SCHRITTE_MAX := 5
## Seed-Präfix — getrennt vom Tagesquest-Strom (hash32(day)).
const SEED_PREFIX := "vorhaben:"
## Sekunden eines Tages (Wochen-Mathe auf Mittags-Stempeln, DST-frei).
const TAG_S := 86_400


## ISO-8601-Woche eines Lokaltags (YYYY-MM-DD → "YYYY-Www", Montag =
## Wochenanfang). Donnerstag-Trick: die Woche gehört ins Jahr ihres
## Donnerstags (deckt Jahreswechsel in beide Richtungen ab).
static func woche_von(day: String) -> String:
	var teile := day.split("-")
	if teile.size() != 3:
		return ""
	var mittag := _unix_mittag(int(teile[0]), int(teile[1]), int(teile[2]))
	var donnerstag := mittag + (4 - _iso_wochentag(mittag)) * TAG_S
	var jahr := int(Time.get_datetime_dict_from_unix_time(donnerstag)["year"])
	var tag_im_jahr := int((donnerstag - _unix_mittag(jahr, 1, 1)) / TAG_S)
	return "%04d-W%02d" % [jahr, tag_im_jahr / 7 + 1]


## Vorhaben-Unterslice im `quests`-Dict sicherstellen/normalisieren
## (additiv, fremde Schlüssel bleiben unangetastet).
static func slice_von(quests: Dictionary) -> Dictionary:
	if not (quests.get("vorhaben") is Dictionary):
		quests["vorhaben"] = {}
	var v: Dictionary = quests["vorhaben"]
	v["id"] = str(v.get("id", ""))
	v["woche"] = str(v.get("woche", ""))
	v["schritt"] = maxi(0, int(_num(v.get("schritt"), 0.0)))
	if not (v.get("base") is Dictionary):
		v["base"] = {}
	if not (v.get("fertigIds") is Array):
		v["fertigIds"] = []
	v["letzteId"] = str(v.get("letzteId", ""))
	v["fertigWoche"] = str(v.get("fertigWoche", ""))
	return v


## Ist ein Katalog-Def formal gültig (id + 3–5 Schritte mit Messung)?
static func def_gueltig(def: Variant) -> bool:
	if not (def is Dictionary) or str((def as Dictionary).get("id", "")).is_empty():
		return false
	var s := schritte_von(def)
	if s.size() < SCHRITTE_MIN or s.size() > SCHRITTE_MAX:
		return false
	for schritt: Variant in s:
		if not (schritt is Dictionary) or not (schritt.get("messung") is Dictionary):
			return false
		if int(_num((schritt as Dictionary).get("ziel"), 0.0)) < 1:
			return false
	return true


static func schritte_von(def: Variant) -> Array:
	if not (def is Dictionary):
		return []
	var s: Variant = (def as Dictionary).get("schritte")
	return s if s is Array else []


## Gültige + `braucht`-erfüllte Bögen (Filter wie beim Tagesbrett).
static func eligible_defs(pool: Array, ctx: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for def: Variant in pool:
		if (
			def_gueltig(def)
			and DailyQuestEngine.requires_met((def as Dictionary).get("braucht"), ctx)
		):
			out.append(def)
	return out


## Deterministisches Wochen-Angebot: Seed hash32("vorhaben:"+woche) wählt den
## Start-Index; von dort läuft die Suche zyklisch. Schon erlebte Bögen
## (fertig_ids) werden übersprungen, solange es unerlebte gibt; der zuletzt
## gefeierte Bogen (letzte_id) wiederholt sich nie direkt hintereinander.
static func angebot_fuer(
	woche: String, pool: Array, ctx: Dictionary, fertig_ids: Array, letzte_id: String
) -> Dictionary:
	var eligible := eligible_defs(pool, ctx)
	if eligible.is_empty():
		return {}
	var rng := {"a": DailyQuestEngine.hash32(SEED_PREFIX + woche) & 0xFFFFFFFF}
	var start := int(DailyQuestEngine.rand_next(rng) * eligible.size()) % eligible.size()
	var zweitbester := {}
	for i in eligible.size():
		var def: Dictionary = eligible[(start + i) % eligible.size()]
		var id := str(def.get("id", ""))
		if id == letzte_id and eligible.size() > 1:
			continue
		if not fertig_ids.has(id):
			return def
		if zweitbester.is_empty():
			zweitbester = def
	return zweitbester


## Aktives Vorhaben sicherstellen (mutiert `quests` in place, innerhalb von
## GameState.update aufrufen). Startet NUR, wenn kein Bogen läuft und diese
## Woche noch keiner gefeiert wurde. true = neuer Bogen gestartet.
static func ensure_aktiv(
	quests: Dictionary, woche: String, pool: Array, ctx: Dictionary, state: Dictionary
) -> bool:
	var v := slice_von(quests)
	if woche.is_empty() or not str(v["id"]).is_empty():
		return false
	if str(v["fertigWoche"]) == woche and not str(v["letzteId"]).is_empty():
		return false
	var def := angebot_fuer(woche, pool, ctx, v["fertigIds"], str(v["letzteId"]))
	if def.is_empty():
		return false
	_starte(v, def, woche, state)
	return true


## Einen BESTIMMTEN Bogen starten (Debug-/Flow-Stellung; überschreibt einen
## laufenden Bogen bewusst). false, wenn der Def ungültig ist.
static func starte_bogen(
	quests: Dictionary, def: Dictionary, woche: String, state: Dictionary
) -> bool:
	if not def_gueltig(def):
		return false
	_starte(slice_von(quests), def, woche, state)
	return true


## Fortschritt des AKTUELLEN Schritts (0..ziel) aus den Live-Zählern.
static func schritt_fortschritt(v: Dictionary, def: Dictionary, state: Dictionary) -> int:
	var s := schritte_von(def)
	var index := int(_num(v.get("schritt"), 0.0))
	if index < 0 or index >= s.size():
		return 0
	return DailyQuestEngine.progress_of({"base": v.get("base", {})}, _pseudo_def(s[index]), state)


## Fällige Schritte weiterschalten (mutiert `quests`; Baseline des jeweils
## nächsten Schritts wird BEIM Wechsel eingefroren — Sequenz-Semantik wie
## rquest_engine._ziel_weiter). Liefert die Zahl der geschafften Schritte.
static func fortschreiben(quests: Dictionary, def: Dictionary, state: Dictionary) -> int:
	var v := slice_von(quests)
	if str(v["id"]).is_empty() or str(v["id"]) != str(def.get("id", "")):
		return 0
	var s := schritte_von(def)
	var geschafft := 0
	while int(v["schritt"]) < s.size():
		var schritt: Dictionary = s[int(v["schritt"])]
		var pseudo := _pseudo_def(schritt)
		if DailyQuestEngine.progress_of({"base": v["base"]}, pseudo, state) < int(pseudo["ziel"]):
			break
		v["schritt"] = int(v["schritt"]) + 1
		geschafft += 1
		if int(v["schritt"]) < s.size():
			v["base"] = DailyQuestEngine.baseline_of(_pseudo_def(s[int(v["schritt"])]), state)
		else:
			v["base"] = {}
	return geschafft


## Alle Schritte durch → das Finale wartet auf seinen Feier-Tap.
static func erfuellbar(v: Dictionary, def: Dictionary) -> bool:
	var s := schritte_von(def)
	return (
		not str(v.get("id", "")).is_empty()
		and not s.is_empty()
		and int(_num(v.get("schritt"), 0.0)) >= s.size()
	)


## Finale feiern: markiert den Bogen als erledigt und liefert die Belohnung
## ({ok, muenzen, xp}); die Auszahlung übernimmt der Aufrufer (_pay-Muster).
## Mutiert `quests`. Idempotent: der aktiv-Slot wird geleert, ein zweiter
## Aufruf liefert ok=false (kein Doppel-Payout).
static func feiern(quests: Dictionary, def: Dictionary, woche: String) -> Dictionary:
	var v := slice_von(quests)
	if not erfuellbar(v, def) or str(v["id"]) != str(def.get("id", "")):
		return {"ok": false, "muenzen": 0, "xp": 0}
	var id := str(v["id"])
	if not (v["fertigIds"] as Array).has(id):
		(v["fertigIds"] as Array).append(id)
	v["letzteId"] = id
	v["fertigWoche"] = woche
	v["id"] = ""
	v["woche"] = ""
	v["schritt"] = 0
	v["base"] = {}
	return {
		"ok": true,
		"muenzen": maxi(0, int(_num(def.get("muenzen"), 0.0))),
		"xp": maxi(0, int(_num(def.get("xp"), 0.0))),
	}


## Wurde das Wochen-Vorhaben DIESER Woche schon gefeiert (Feier-Zustand im
## Blatt: „geschafft — nächste Woche geht’s weiter“)?
static func fertig_diese_woche(v: Dictionary, woche: String) -> bool:
	return (
		str(v.get("id", "")).is_empty()
		and not str(v.get("letzteId", "")).is_empty()
		and str(v.get("fertigWoche", "")) == woche
	)


# ── intern ────────────────────────────────────────────────────────────────────


static func _starte(v: Dictionary, def: Dictionary, woche: String, state: Dictionary) -> void:
	v["id"] = str(def.get("id", ""))
	v["woche"] = woche
	v["schritt"] = 0
	var s := schritte_von(def)
	v["base"] = DailyQuestEngine.baseline_of(_pseudo_def(s[0]), state) if not s.is_empty() else {}


## Schritt → Pseudo-Quest-Def für die DailyQuestEngine-Messmaschine.
static func _pseudo_def(schritt: Dictionary) -> Dictionary:
	return {
		"messung": schritt.get("messung", {}),
		"ziel": maxi(1, int(_num(schritt.get("ziel"), 1.0))),
	}


## Mittags-Unixstempel eines Kalendertags (keine DST-/Randfälle).
static func _unix_mittag(jahr: int, monat: int, tag: int) -> int:
	return int(
		Time.get_unix_time_from_datetime_dict(
			{"year": jahr, "month": monat, "day": tag, "hour": 12, "minute": 0, "second": 0}
		)
	)


## ISO-Wochentag (1 = Montag … 7 = Sonntag) eines Unixstempels.
static func _iso_wochentag(unix: int) -> int:
	var wd := int(Time.get_datetime_dict_from_unix_time(unix)["weekday"])
	return 7 if wd == 0 else wd


static func _num(value: Variant, fallback: float) -> float:
	return float(value) if (value is int or value is float) else fallback
