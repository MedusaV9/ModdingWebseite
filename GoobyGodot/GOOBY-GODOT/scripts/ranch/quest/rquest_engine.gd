class_name RQuestEngine
extends RefCounted
## Quest-Zustandsmaschine des Ranch-DLC (RW-3) — PURE + static: kennt weder
## Nodes noch GameState, arbeitet nur auf dem `ranch.quests`-Unterschlüssel
## (RQuestSlices-Form) + Quest-Definitionen (RQuestKatalog-Form).
##
## Zustände pro Quest: gesperrt → verfügbar → aktiv → (wartend ⇄ aktiv) →
## erfüllbar → erledigt. „gesperrt/verfügbar/erledigt“ sind abgeleitet,
## im Save liegen nur aktive Läufe + die erledigt-Liste.
##
## Ziele laufen SEQUENZIELL (zielIndex/zaehler); Ziel-Typen:
##   gehe_zu {ort} · sprich_mit {npc} · sammle {item, n} ·
##   pflege {aktion, n} · reite_strecke {strecke} ·
##   gewinne_wettbewerb {disziplin, platz} · warte_bis {dauerMin}
## warte_bis ist NICHT ereignisgetrieben: wird es aktuelles Ziel, wechselt
## der Lauf auf „wartend“ (bereitAt = now + dauer); tick() löst fällige
## Warte-Ziele. Warten blockiert NIE andere Quests (C4-Designregel).
##
## Ereignis-Form (von Spiel-Systemen gemeldet): {typ, ...} mit denselben
## Feldern wie das Ziel; gewinne_wettbewerb matcht bei platz <= Ziel-platz.

const STATUS_GESPERRT := "gesperrt"
const STATUS_VERFUEGBAR := "verfuegbar"
const STATUS_AKTIV := RQuestSlices.STATUS_AKTIV
const STATUS_WARTEND := RQuestSlices.STATUS_WARTEND
const STATUS_ERFUELLBAR := RQuestSlices.STATUS_ERFUELLBAR
const STATUS_ERLEDIGT := "erledigt"

const MS_PRO_MIN := 60_000


## Abgeleiteter Zustand einer Quest ({def} + quests-Save + Kontext).
## `herzen` = npcId → Herz-Stufe (RNpcFreundschaft.herzen), für Herz-Gates.
## `datum` (YYYY-MM-DD) lässt gestrige Tagesaufgaben-Erledigungen verfallen
## ("" = Datum nicht prüfen).
static func status_von(quests: Dictionary, def: Dictionary, herzen := {}, datum := "") -> String:
	var id := str(def.get("id", ""))
	if _tages_heute_erledigt(quests, def, datum):
		return STATUS_ERLEDIGT
	if (quests.get("erledigt", []) as Array).has(id):
		return STATUS_ERLEDIGT
	var lauf: Variant = (quests.get("aktiv", {}) as Dictionary).get(id)
	if lauf is Dictionary:
		return str((lauf as Dictionary).get("status", STATUS_AKTIV))
	if voraussetzungen_erfuellt(def, quests, herzen):
		return STATUS_VERFUEGBAR
	return STATUS_GESPERRT


## Voraussetzungen ({quests:[], herzen:{npc:stufe}, kapitel:n}) prüfen.
static func voraussetzungen_erfuellt(
	def: Dictionary, quests: Dictionary, herzen: Dictionary
) -> bool:
	var vor: Dictionary = (
		def.get("voraussetzungen") if def.get("voraussetzungen") is Dictionary else {}
	)
	var erledigt: Array = quests.get("erledigt", [])
	for noetig: Variant in vor.get("quests", []):
		if not erledigt.has(str(noetig)):
			return false
	var herz_gates: Dictionary = vor.get("herzen") if vor.get("herzen") is Dictionary else {}
	for npc_id: Variant in herz_gates:
		if int(herzen.get(str(npc_id), 0)) < int(herz_gates[npc_id]):
			return false
	if vor.has("kapitel") and kapitel(quests) < int(vor.get("kapitel", 1)):
		return false
	return true


## Aktuelles Kapitel = erledigte Haupt-Quests + 1 (Katalogliste = Wahrheit).
static func kapitel(quests: Dictionary, hauptreihe := RQuestKatalog.hauptreihe()) -> int:
	var erledigt: Array = quests.get("erledigt", [])
	var n := 0
	for def: Dictionary in hauptreihe:
		if erledigt.has(str(def.get("id", ""))):
			n += 1
	return n + 1


## Alle JETZT annehmbaren Quests (verfügbar + Tagesaufgaben des Datums).
static func verfuegbare(
	quests: Dictionary, herzen: Dictionary, datum: String, katalog := RQuestKatalog.alle()
) -> Array:
	var out: Array = []
	var tages_ids := {}
	for def: Dictionary in RQuestKatalog.tagesaufgaben(datum):
		tages_ids[str(def.get("id", ""))] = true
	for def: Dictionary in katalog:
		if str(def.get("typ", "")) == RQuestKatalog.TYP_TAEGLICH:
			if not tages_ids.has(str(def.get("id", ""))):
				continue
		if status_von(quests, def, herzen, datum) == STATUS_VERFUEGBAR:
			out.append(def)
	return out


## Quest annehmen → neuer quests-Stand (Kopie). Startet ein führendes
## Warte-Ziel sofort. Bereits aktive/erledigte Quests: unverändert.
static func annehmen(quests: Dictionary, def: Dictionary, now_ms: int, herzen := {}) -> Dictionary:
	if status_von(quests, def, herzen) != STATUS_VERFUEGBAR:
		return quests
	var neu: Dictionary = quests.duplicate(true)
	var lauf := RQuestSlices.neuer_lauf(now_ms)
	_warte_pruefen(def, lauf, now_ms)
	(neu["aktiv"] as Dictionary)[str(def["id"])] = lauf
	return neu


## Spiel-Ereignis auf einen aktiven Lauf buchen → {quests, geaendert}.
## Nur das AKTUELLE Ziel zählt (sequenziell); wartende Läufe ignorieren
## Ereignisse (das Warten löst nur tick()).
static func ereignis(
	quests: Dictionary, def: Dictionary, was: Dictionary, now_ms: int
) -> Dictionary:
	var id := str(def.get("id", ""))
	var lauf: Variant = (quests.get("aktiv", {}) as Dictionary).get(id)
	if not (lauf is Dictionary) or str((lauf as Dictionary).get("status")) != STATUS_AKTIV:
		return {"quests": quests, "geaendert": false}
	var ziel := aktuelles_ziel(def, lauf)
	if not _ziel_matcht(ziel, was):
		return {"quests": quests, "geaendert": false}
	var neu: Dictionary = quests.duplicate(true)
	var neu_lauf: Dictionary = (neu["aktiv"] as Dictionary)[id]
	neu_lauf["zaehler"] = int(neu_lauf["zaehler"]) + maxi(1, int(was.get("n", 1)))
	if int(neu_lauf["zaehler"]) >= ziel_n(ziel):
		_ziel_weiter(def, neu_lauf, now_ms)
	return {"quests": neu, "geaendert": true}


## Fällige Warte-Ziele ALLER aktiven Läufe auflösen → {quests, fertig:[ids]}.
## `fertig` = Quest-Ids, deren Warte-Ziel gerade aufgelöst wurde (für
## Notification-/Live-Activity-Abschluss durch den Aufrufer).
static func tick(quests: Dictionary, now_ms: int, katalog := RQuestKatalog.alle()) -> Dictionary:
	var neu: Dictionary = quests.duplicate(true)
	var fertig: Array = []
	var defs := {}
	for def: Dictionary in katalog:
		defs[str(def.get("id", ""))] = def
	var aktiv: Dictionary = neu.get("aktiv", {})
	for id: String in aktiv.keys():
		var lauf: Dictionary = aktiv[id]
		if str(lauf.get("status")) != STATUS_WARTEND:
			continue
		if int(lauf.get("bereitAt", 0)) > now_ms:
			continue
		if not (defs.get(id) is Dictionary):
			continue
		lauf["status"] = STATUS_AKTIV
		lauf["bereitAt"] = 0
		_ziel_weiter(defs[id], lauf, now_ms)
		fertig.append(id)
	return {"quests": neu, "fertig": fertig}


## Erfüllbare Quest abgeben → {quests, ok, belohnung}. Tagesaufgaben landen
## in tages.erledigt (morgen wieder da), alles andere in erledigt.
static func abgeben(quests: Dictionary, def: Dictionary, datum: String) -> Dictionary:
	var id := str(def.get("id", ""))
	var lauf: Variant = (quests.get("aktiv", {}) as Dictionary).get(id)
	var erfuellbar := (
		lauf is Dictionary and str((lauf as Dictionary).get("status")) == STATUS_ERFUELLBAR
	)
	if not erfuellbar:
		return {"quests": quests, "ok": false, "belohnung": {}}
	var neu: Dictionary = quests.duplicate(true)
	(neu["aktiv"] as Dictionary).erase(id)
	if str(def.get("typ", "")) == RQuestKatalog.TYP_TAEGLICH:
		var tages: Dictionary = neu["tages"]
		if str(tages.get("datum", "")) != datum:
			tages["datum"] = datum
			tages["erledigt"] = []
		(tages["erledigt"] as Array).append(id)
	elif not (neu["erledigt"] as Array).has(id):
		(neu["erledigt"] as Array).append(id)
	for frei: Variant in _belohnung(def).get("freischalten", []):
		if not (neu["freigeschaltet"] as Array).has(str(frei)):
			(neu["freigeschaltet"] as Array).append(str(frei))
	return {"quests": neu, "ok": true, "belohnung": _belohnung(def)}


## Das aktuelle Ziel eines Laufs ({} = alle Ziele fertig).
static func aktuelles_ziel(def: Dictionary, lauf: Dictionary) -> Dictionary:
	var ziele: Array = def.get("ziele") if def.get("ziele") is Array else []
	var index := int(lauf.get("zielIndex", 0))
	if index < 0 or index >= ziele.size():
		return {}
	return ziele[index] if ziele[index] is Dictionary else {}


## Soll-Anzahl eines Ziels (Default 1).
static func ziel_n(ziel: Dictionary) -> int:
	return maxi(1, int(ziel.get("n", 1)))


## Ziel bestanden → zum nächsten; folgende Warte-Ziele sofort starten;
## nach dem letzten Ziel: erfüllbar.
static func _ziel_weiter(def: Dictionary, lauf: Dictionary, now_ms: int) -> void:
	lauf["zielIndex"] = int(lauf["zielIndex"]) + 1
	lauf["zaehler"] = 0
	_warte_pruefen(def, lauf, now_ms)


## Ist das aktuelle Ziel ein Warte-Ziel → Lauf auf „wartend“ stellen;
## sind alle Ziele durch → „erfüllbar“.
static func _warte_pruefen(def: Dictionary, lauf: Dictionary, now_ms: int) -> void:
	var ziele: Array = def.get("ziele") if def.get("ziele") is Array else []
	if int(lauf["zielIndex"]) >= ziele.size():
		lauf["status"] = STATUS_ERFUELLBAR
		return
	var ziel := aktuelles_ziel(def, lauf)
	if str(ziel.get("typ", "")) == "warte_bis":
		lauf["status"] = STATUS_WARTEND
		lauf["bereitAt"] = now_ms + int(ziel.get("dauerMin", 0)) * MS_PRO_MIN
	else:
		lauf["status"] = STATUS_AKTIV


static func _ziel_matcht(ziel: Dictionary, was: Dictionary) -> bool:
	var typ := str(ziel.get("typ", ""))
	if typ != str(was.get("typ", "")):
		return false
	match typ:
		"gehe_zu":
			return str(ziel.get("ort", "")) == str(was.get("ort", ""))
		"sprich_mit":
			return str(ziel.get("npc", "")) == str(was.get("npc", ""))
		"sammle":
			return str(ziel.get("item", "")) == str(was.get("item", ""))
		"pflege":
			return str(ziel.get("aktion", "")) == str(was.get("aktion", ""))
		"reite_strecke":
			return str(ziel.get("strecke", "")) == str(was.get("strecke", ""))
		"gewinne_wettbewerb":
			return (
				str(ziel.get("disziplin", "")) == str(was.get("disziplin", ""))
				and int(was.get("platz", 99)) <= int(ziel.get("platz", 1))
			)
		_:
			return false


static func _belohnung(def: Dictionary) -> Dictionary:
	return def.get("belohnung") if def.get("belohnung") is Dictionary else {}


static func _tages_heute_erledigt(quests: Dictionary, def: Dictionary, datum := "") -> bool:
	if str(def.get("typ", "")) != RQuestKatalog.TYP_TAEGLICH:
		return false
	var tages: Dictionary = quests.get("tages") if quests.get("tages") is Dictionary else {}
	if not datum.is_empty() and str(tages.get("datum", "")) != datum:
		return false
	return (tages.get("erledigt", []) as Array).has(str(def.get("id", "")))
