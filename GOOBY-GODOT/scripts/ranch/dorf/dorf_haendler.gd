class_name DorfHaendler
extends RefCounted
## Pferdehändlerin in Hufingen (RW-4) — Tagesangebot + atomarer Kauf/Verkauf.
##
## Das Angebot ROTIERT TÄGLICH und ist DETERMINISTISCH: gleicher Tag =
## gleiches Angebot (Seed = hash des lokalen Tages-Strings), egal wie oft
## man den Laden betritt oder das Spiel neu startet. Jedes Pferd des Pools
## kehrt über die Tage wieder — bewusst KEIN FOMO (Forschung: Fairness
## schlägt Druck). Gekaufte Pferde ziehen als RanchPlaySlices.neues_pferd
## in `ranch.tiere.pferde` ein (Pflege/Reiten funktionieren sofort);
## der Kaufpreis reist als Zusatz-Schlüssel mit (normalize erhält ihn
## VERBATIM) und bestimmt den Wiederverkaufswert.
##
## ALLE Buchungen atomar in EINEM gs.update()-Block (Muster RanchKauf).

const Economy := preload("res://scripts/logic/economy.gd")
const RanchPlaySlices := preload("res://scripts/ranch/data/ranch_play_slices.gd")

const SPEND_REASON := "ranch_dorf"

const FEHLER_UNBEKANNT := "unbekannt"
const FEHLER_NICHT_IM_ANGEBOT := "nichtImAngebot"
const FEHLER_STALL_VOLL := "stallVoll"
const FEHLER_ZU_TEUER := "zuTeuer"
const FEHLER_LETZTES_PFERD := "letztesPferd"
const FEHLER_KEIN_PFERD := "keinPferd"


## PURE Tagesrotation: deterministische Auswahl von `anzahl` Pool-Einträgen
## für den Tages-String `tag` (seeded Fisher-Yates — stabil pro Tag).
static func tages_angebot(tag: String, pool: Array, anzahl: int) -> Array:
	if pool.is_empty() or anzahl <= 0:
		return []
	var indizes: Array = range(pool.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("hufingen|%s" % tag)
	for i in range(indizes.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tausch: Variant = indizes[i]
		indizes[i] = indizes[j]
		indizes[j] = tausch
	var out: Array = []
	for i in mini(anzahl, indizes.size()):
		var eintrag: Variant = pool[indizes[i]]
		if eintrag is Dictionary:
			out.append((eintrag as Dictionary).duplicate(true))
	return out


## Heutiges Angebot für DIESEN Spielstand: Tagesrotation minus bereits
## besessene Pferde minus heute schon gekaufte (kehren morgen wieder).
static func angebot(gs: Object, balance := {}) -> Array:
	var bal := balance if not balance.is_empty() else DorfKatalog.load_balance()
	var tag := RanchDorfState.heute(gs)
	var roh := tages_angebot(tag, DorfKatalog.pferde_pool(bal), DorfKatalog.angebot_anzahl(bal))
	var pferde := _pferde(gs)
	var dorf := RanchDorfState.lese(gs)
	var gesperrt: Array = []
	if str(dorf["verkauft"]["tag"]) == tag:
		gesperrt = dorf["verkauft"]["angebote"]
	var out: Array = []
	for eintrag: Dictionary in roh:
		var id := str(eintrag.get("id", ""))
		if not pferde.has(id) and not gesperrt.has(id):
			out.append(eintrag)
	return out


## Maximale Pferdezahl: das BESSERE aus Alt-System (ranch.wirtschaft.ausbau)
## und Grid-Stallboxen — niemand verliert Kapazität durch den Umstieg.
static func kapazitaet(gs: Object, bau_balance := {}) -> int:
	if gs == null:
		return 0
	var bbal := bau_balance if not bau_balance.is_empty() else RanchBauKatalog.load_balance()
	var wbal := RanchWirtschaft.load_balance()
	var wirtschaft: Variant = gs.get_value("ranch.wirtschaft", {})
	var alt := RanchWirtschaft.boxen_kapazitaet(
		wirtschaft if wirtschaft is Dictionary else {}, wbal
	)
	var neu := RanchBauEffekte.boxen_kapazitaet(RanchBauState.lese(gs), bbal)
	return maxi(alt, neu)


## Pferd aus dem Tagesangebot kaufen — atomar: Gold runter, Pferd in
## `ranch.tiere.pferde`, Angebots-Sperre für heute, Statistik hoch.
static func pferd_kaufen(gs: Object, pool_id: String, balance := {}) -> Dictionary:
	var bal := balance if not balance.is_empty() else DorfKatalog.load_balance()
	if gs == null:
		return {"ok": false, "fehler": FEHLER_UNBEKANNT, "preis": 0}
	var eintrag := {}
	for kandidat: Dictionary in angebot(gs, bal):
		if str(kandidat.get("id", "")) == pool_id:
			eintrag = kandidat
			break
	if eintrag.is_empty():
		return {"ok": false, "fehler": FEHLER_NICHT_IM_ANGEBOT, "preis": 0}
	if _pferde(gs).size() >= kapazitaet(gs):
		return {"ok": false, "fehler": FEHLER_STALL_VOLL, "preis": 0}
	var preis := maxi(0, int(_num(eintrag.get("preis"), 0.0)))
	var tag := RanchDorfState.heute(gs)
	var pferd := _pferd_aus_pool(eintrag, preis)
	var bezahlt := [false]
	gs.update(
		func(state: Dictionary) -> void:
			if not Economy.spend(state["economy"], preis, SPEND_REASON):
				return
			bezahlt[0] = true
			_pferde_im_state(state)[pool_id] = pferd
			var dorf := RanchDorfState.dorf_im_state(state)
			var verkauft: Dictionary = dorf["verkauft"]
			if str(verkauft["tag"]) != tag:
				verkauft["tag"] = tag
				verkauft["angebote"] = []
			(verkauft["angebote"] as Array).append(pool_id)
			dorf["pferdeGekauft"] = int(dorf["pferdeGekauft"]) + 1
	)
	if not bool(bezahlt[0]):
		return {"ok": false, "fehler": FEHLER_ZU_TEUER, "preis": preis}
	gs.notify_slice_changed(RanchDorfState.SLICE_ID)
	return {"ok": true, "fehler": "", "preis": preis}


## Wiederverkaufswert eines Pferds: verkauf_anteil × gemerkter Kaufpreis
## (Start-/Pack-Pferde ohne Kaufpreis zählen mit basis_wert).
static func verkaufspreis(gs: Object, pferd_id: String, balance := {}) -> int:
	var bal := balance if not balance.is_empty() else DorfKatalog.load_balance()
	var pferde := _pferde(gs)
	if not pferde.has(pferd_id):
		return 0
	var pferd: Dictionary = pferde[pferd_id]
	var wert := int(_num(pferd.get("kaufpreis"), float(DorfKatalog.basis_wert(bal))))
	return int(floor(wert * DorfKatalog.verkauf_anteil(bal)))


## Pferd an die Händlerin verkaufen — atomar: Pferd raus, Gold rein,
## Gear-/Hufeisen-Zuordnungen aufräumen. Das LETZTE Pferd ist unverkäuflich
## (man muss ja noch nach Hause reiten).
static func pferd_verkaufen(gs: Object, pferd_id: String, balance := {}) -> Dictionary:
	var bal := balance if not balance.is_empty() else DorfKatalog.load_balance()
	if gs == null:
		return {"ok": false, "fehler": FEHLER_UNBEKANNT, "erloes": 0}
	var pferde := _pferde(gs)
	if not pferde.has(pferd_id):
		return {"ok": false, "fehler": FEHLER_KEIN_PFERD, "erloes": 0}
	if pferde.size() <= 1:
		return {"ok": false, "fehler": FEHLER_LETZTES_PFERD, "erloes": 0}
	var erloes := verkaufspreis(gs, pferd_id, bal)
	gs.update(
		func(state: Dictionary) -> void:
			_pferde_im_state(state).erase(pferd_id)
			var ranch: Dictionary = state["ranch"]
			if ranch.get("wirtschaft") is Dictionary:
				var gear: Variant = (ranch["wirtschaft"] as Dictionary).get("gear")
				if gear is Dictionary and gear.get("equippedByHorse") is Dictionary:
					(gear["equippedByHorse"] as Dictionary).erase(pferd_id)
			var dorf := RanchDorfState.dorf_im_state(state)
			(dorf["hufeisen"]["proPferd"] as Dictionary).erase(pferd_id)
			dorf["pferdeVerkauft"] = int(dorf["pferdeVerkauft"]) + 1
			if erloes > 0:
				Economy.award(state["economy"], erloes, SPEND_REASON)
	)
	gs.notify_slice_changed(RanchDorfState.SLICE_ID)
	return {"ok": true, "fehler": "", "erloes": erloes}


# ── intern ───────────────────────────────────────────────────────────────────


## Pool-Eintrag → Pferd-Dictionary (RANCH-2-Struktur + Händler-Metadaten).
static func _pferd_aus_pool(eintrag: Dictionary, preis: int) -> Dictionary:
	var name_key := str(eintrag.get("name_key", ""))
	var name := name_key.get_slice(".", name_key.get_slice_count(".") - 1).capitalize()
	var pferd := RanchPlaySlices.neues_pferd(name, str(eintrag.get("fell_id", "braun")))
	pferd["packId"] = str(eintrag.get("id", ""))
	pferd["nameKey"] = name_key
	pferd["farbeHex"] = str(eintrag.get("farbe", "#D9A066"))
	pferd["maehneHex"] = str(eintrag.get("maehne", ""))
	pferd["kaufpreis"] = preis
	return pferd


static func _pferde(gs: Object) -> Dictionary:
	if gs == null:
		return {}
	var raw: Variant = gs.get_value("ranch.tiere.pferde", {})
	return raw if raw is Dictionary else {}


## `ranch.tiere.pferde` innerhalb eines gs.update()-Blocks (heilt fehlende
## Ebenen defensiv — RANCH-2s normalize glättet später).
static func _pferde_im_state(state: Dictionary) -> Dictionary:
	var ranch: Dictionary = state.get("ranch") if state.get("ranch") is Dictionary else {}
	if not (state.get("ranch") is Dictionary):
		state["ranch"] = ranch
	var tiere: Dictionary = ranch.get("tiere") if ranch.get("tiere") is Dictionary else {}
	if not (ranch.get("tiere") is Dictionary):
		ranch["tiere"] = tiere
	var pferde: Dictionary = tiere.get("pferde") if tiere.get("pferde") is Dictionary else {}
	if not (tiere.get("pferde") is Dictionary):
		tiere["pferde"] = pferde
	return pferde


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
