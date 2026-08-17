class_name McGoobyStationBelegen
extends RefCounted
## Pure Belegstation-Logik des McGooby-DLC (Welle B, Doc §2.2 #2): das
## Bestell-Ticket zeigt den Zutaten-Turm, Zutaten werden in Ticket-
## Reihenfolge aus einer Leiste aufs Brötchen gewischt. Direkter Erbe von
## `burger_build_logic.gd` (Punkte-Grammatik +5 richtige Lage / −2 falsche;
## der Fertig-Bonus bleibt der Schicht-weite `bestellung_fertig_bonus`) —
## nur ohne Zutaten-Regen: hier WÄHLT der Spieler, das Tempo kommt von der
## Kundenschlange, nicht von der Physik. Keine Nodes, keine Autoloads —
## bot-zertifizierbar via simulate_autoplay (Doc §10.4). Zahlen kommen
## IMMER aus dem Balance-Block des Menü-Packs (McGoobyKatalog.balance()).

const STATION_ID := "belegen"

const WERTUNG_RICHTIG := "richtig"
const WERTUNG_FALSCH := "falsch"


## Zutaten-Turm des ERSTEN Belegen-Schritts eines Rezepts (unten → oben);
## leer = das Rezept braucht die Belegstation nicht.
static func ticket_von(rezept_def: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for schritt: Variant in rezept_def.get("schritte", []):
		if not (schritt is Dictionary):
			continue
		if str((schritt as Dictionary).get("station", "")) != STATION_ID:
			continue
		var zutaten: Variant = (schritt as Dictionary).get("zutaten", [])
		if zutaten is Array:
			for zutat: Variant in zutaten:
				out.append(str(zutat))
		return out
	return out


## Auswahl-Leiste zum Ticket: jede Zutat GENAU einmal, in Erst-Auftauch-
## Reihenfolge — deterministisch ohne RNG (Zugänglichkeit §2.2.7: stabile
## Plätze, die Reihenfolge des Turms bleibt die eigentliche Aufgabe).
static func leiste(ticket: Array) -> Array[String]:
	var out: Array[String] = []
	for zutat: Variant in ticket:
		if not out.has(str(zutat)):
			out.append(str(zutat))
	return out


## Nächste benötigte Zutat, "" sobald der Turm vollständig ist.
static func naechste_zutat(ticket: Array, platziert: int) -> String:
	if platziert >= 0 and platziert < ticket.size():
		return str(ticket[platziert])
	return ""


static func ist_fertig(ticket: Array, platziert: int) -> bool:
	return platziert >= ticket.size()


## Einen Wisch werten: richtige Zutat landet auf dem Turm (+punkte),
## falsche kostet den Malus und der Turm bleibt stehen (burger_build-
## Grammatik; nie unter 0 — der Aufruf klemmt auf Bestellungs-Ebene).
## Rückgabe: {wertung, punkte, platziert}.
static func bewerte_wisch(
	ticket: Array, platziert: int, zutat_id: String, bal: Dictionary
) -> Dictionary:
	if zutat_id == naechste_zutat(ticket, platziert) and not zutat_id.is_empty():
		return {
			"wertung": WERTUNG_RICHTIG,
			"punkte": punkte_richtig(bal),
			"platziert": platziert + 1,
		}
	return {
		"wertung": WERTUNG_FALSCH,
		"punkte": -malus_falsch(bal),
		"platziert": platziert,
	}


static func punkte_richtig(bal: Dictionary) -> int:
	return maxi(0, int(bal.get("belegen_punkte_richtig", 5)))


static func malus_falsch(bal: Dictionary) -> int:
	return maxi(0, int(bal.get("belegen_malus_falsch", 2)))


## Bot-Runde über EIN Ticket auf einem GETEILTEN RNG-Strom — die Schicht-
## Zertifizierung (McGoobySchichtLogic.simulate_autoplay) hängt sich mit
## demselben Strom hier ein. Fehlgriff-Modell: pro Zutat würfelt der Bot
## einmal; daneben = Malus (auf Bestellungs-Ebene geklemmt) + Korrektur.
static func bot_runde(rng: GoobyRng, ticket: Array, bal: Dictionary, skill: float) -> Dictionary:
	var punkte := 0
	var fehlgriffe := 0
	for _zutat: Variant in ticket:
		if rng.next() >= skill:
			fehlgriffe += 1
			punkte = maxi(0, punkte - malus_falsch(bal))
		punkte += punkte_richtig(bal)
	return {
		"zutaten": ticket.size(),
		"fehlgriffe": fehlgriffe,
		"punkte": punkte,
		"fehlerfrei": fehlgriffe == 0,
	}


## Deterministische Bot-Zertifizierung der Station allein (Doc §10.4):
## derselbe Seed + dasselbe Ticket → exakt dieselben Goldwerte.
static func simulate_autoplay(seed_wert: int, ticket: Array, bal: Dictionary) -> Dictionary:
	var skill := clampf(float(bal.get("bot_skill", 0.9)), 0.0, 1.0)
	var ergebnis := bot_runde(GoobyRng.new(seed_wert), ticket, bal, skill)
	ergebnis["seed"] = seed_wert
	return ergebnis
