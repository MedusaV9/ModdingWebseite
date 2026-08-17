class_name MarktSim
extends RefCounted
## W15/MARKT — DETERMINISTISCHE Verkaufs-Sim des eigenen Marktstands
## (Doc D §6.3) — PURE, ohne GameState und ohne Uhr.
##
## Ein Markttag ist vollständig durch (Slots, Tages-Seed) bestimmt: der Seed
## würfelt VORAB je Kunde Ankunftsminute, Wunsch-Ware und Kauf-Los — die
## Preis-Slider verändern nur noch die Kaufwahrscheinlichkeit, NIE die
## Zufallsfolge. Dadurch gilt beweisbar: gleicher Seed + gleiche Preise =
## gleiches Ergebnis, und billiger ⇒ nie weniger Absatz (Monotonie; die
## Sättigung hängt nur vom Verkaufs-ZÄHLER ab, nicht von der Historie).
##
## Kaufwahrscheinlichkeit = Preis-Attraktivität × Tages-Nachfrage ×
## Sättigung. Die Sättigung nutzt DIESELBEN Konstanten wie der Markt-Ankauf
## (markt_preise.json: elastizitaet_pro_stueck/preis_boden — „Elastizität
## wie Doc“): jede schon verkaufte Einheit drückt die Lust um 5 %, Boden 50 %.

## Kundenstrom über die Marktzeit (Doc E: Samstag 8–14 Uhr).
const KUNDEN_MIN := 16
const KUNDEN_MAX := 28

## Tagesmodifikator („Heute lieben alle Kürbisse!“) — Nachfrage-Faktor der
## Tages-Lieblingsware.
const NACHFRAGE_MULT := 1.5

## Kaufwahrscheinlichkeit bei Basispreis (Faktor 1.0) — Attraktivität fällt
## linear mit dem Slider: 0.5× ⇒ ~0.88, 1.0× ⇒ 0.5, 1.5× ⇒ ~0.13.
const ATTRAKTIV_ACHSE := 1.25
const ATTRAKTIV_STEIGUNG := 0.75
const P_MIN := 0.05
const P_MAX := 0.95


## Stabiler Tages-Seed aus dem Markttag-Key ("YYYY-MM-DD").
static func tages_seed(tag_key: String) -> int:
	return tag_key.hash()


## Tages-Lieblingsware („Heute lieben alle …!“) — deterministisch über den
## Seed, gewählt aus dem GESAMTEN Waren-Katalog (steht auch am Info-Schild,
## wenn man die Ware gar nicht dabei hat).
static func tagesmodifikator(seed_wert: int, pfad := MarktWaren.WAREN_PFAD) -> Dictionary:
	var alle := MarktWaren.waren(pfad)
	if alle.is_empty():
		return {"ware": "", "mult": 1.0}
	var idx := posmod(seed_wert, alle.size())
	return {"ware": str(alle[idx]["id"]), "mult": NACHFRAGE_MULT}


## Fester Stückpreis einer Slider-Stellung (der Kunde zahlt IMMER genau das).
static func stueckpreis(ware_id: String, faktor: float, pfad := MarktWaren.WAREN_PFAD) -> int:
	var basis := MarktWaren.basis(ware_id, pfad)
	if basis <= 0:
		return 0
	return maxi(1, roundi(float(basis) * faktor))


## Preis-Attraktivität (0..1) einer Slider-Stellung — streng fallend.
static func attraktivitaet(faktor: float) -> float:
	return clampf(ATTRAKTIV_ACHSE - ATTRAKTIV_STEIGUNG * faktor, P_MIN, P_MAX)


## Sättigung nach `schon_verkauft` Einheiten — Elastizität wie Doc D §6.3
## (Konstanten aus markt_preise.json, gleicher Deckel wie der Ankauf).
static func saettigung(schon_verkauft: int) -> float:
	var d := MarktPreise.daten()
	var elastizitaet := float(d.get("elastizitaet_pro_stueck", 0.05))
	var boden := float(d.get("preis_boden", 0.5))
	return maxf(boden, 1.0 - elastizitaet * float(maxi(0, schon_verkauft)))


## Kaufwahrscheinlichkeit eines Kunden vor Slot `slot` mit Tagesnachfrage.
static func kauf_chance(slot: Dictionary, schon_verkauft: int, modifikator: Dictionary) -> float:
	var p := attraktivitaet(float(slot.get("faktor", 1.0)))
	if str(modifikator.get("ware", "")) == str(slot.get("ware", "")):
		p *= float(modifikator.get("mult", 1.0))
	p *= saettigung(schon_verkauft)
	return clampf(p, 0.0, 0.98)


## Der ganze Markttag: Slots [{ware, menge, faktor}] + Seed → Ergebnis
## {events[], verkauft{}, erloes, kunden, modifikator}. Events tragen
## {minute, ware, preis, gekauft} für Zuschau-Replay und Abrechnung.
static func simulate(
	slots: Array, seed_wert: int, von_stunde := 8, bis_stunde := 14, pfad := MarktWaren.WAREN_PFAD
) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_wert
	var modifikator := tagesmodifikator(seed_wert, pfad)
	var kunden := rng.randi_range(KUNDEN_MIN, KUNDEN_MAX)
	var minuten := maxi(1, (bis_stunde - von_stunde) * 60)
	# Zufallsfolge VORAB ziehen (je Kunde: Minuten-Jitter, Wunsch-Los,
	# Kauf-Los) — sie darf NIE von Preisen oder Käufen abhängen (Monotonie).
	var lose: Array = []
	for i in kunden:
		lose.append([rng.randf(), rng.randf(), rng.randf()])
	var verkauft: Dictionary = {}
	var events: Array = []
	var erloes := 0
	for i in kunden:
		var los: Array = lose[i]
		var minute := int((float(i) + float(los[0])) * float(minuten) / float(kunden))
		if slots.is_empty():
			break
		var slot: Dictionary = slots[mini(int(float(los[1]) * slots.size()), slots.size() - 1)]
		var ware := str(slot.get("ware", ""))
		var schon := int(verkauft.get(ware, 0))
		if schon >= int(slot.get("menge", 0)):
			# Ausverkauft: der Kunde zieht enttäuscht weiter (kein Wechsel —
			# hält die Sim erklärbar und die Monotonie beweisbar).
			continue
		var gekauft := float(los[2]) < kauf_chance(slot, schon, modifikator)
		var preis := stueckpreis(ware, float(slot.get("faktor", 1.0)), pfad)
		if gekauft:
			verkauft[ware] = schon + 1
			erloes += preis
		(
			events
			. append(
				{
					"minute": clampi(minute, 0, minuten - 1),
					"ware": ware,
					"preis": preis,
					"gekauft": gekauft,
				}
			)
		)
	return {
		"events": events,
		"verkauft": verkauft,
		"erloes": erloes,
		"kunden": kunden,
		"modifikator": modifikator,
	}


## Abrechnungs-Karte aus Slots + Sim-Ergebnis: je Ware eine exakte Zeile
## (verkauft × Stückpreis), Summe, übrig und die BESTE Ware (höchster Erlös).
static func abrechnung(
	slots: Array, ergebnis: Dictionary, pfad := MarktWaren.WAREN_PFAD
) -> Dictionary:
	var verkauft: Dictionary = ergebnis.get("verkauft", {})
	var zeilen: Array = []
	var summe := 0
	var beste := ""
	var beste_erloes := -1
	for slot: Dictionary in slots:
		var ware := str(slot.get("ware", ""))
		var menge := int(slot.get("menge", 0))
		var weg := mini(int(verkauft.get(ware, 0)), menge)
		var preis := stueckpreis(ware, float(slot.get("faktor", 1.0)), pfad)
		var zeile_erloes := weg * preis
		summe += zeile_erloes
		if zeile_erloes > beste_erloes and weg > 0:
			beste_erloes = zeile_erloes
			beste = ware
		(
			zeilen
			. append(
				{
					"ware": ware,
					"bestueckt": menge,
					"verkauft": weg,
					"uebrig": menge - weg,
					"stueckpreis": preis,
					"erloes": zeile_erloes,
				}
			)
		)
	return {
		"zeilen": zeilen,
		"erloes": summe,
		"beste_ware": beste,
		"modifikator": ergebnis.get("modifikator", {"ware": "", "mult": 1.0}),
	}
