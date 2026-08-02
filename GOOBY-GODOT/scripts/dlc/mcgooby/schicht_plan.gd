class_name McGoobySchichtPlan
extends RefCounted
## Pure Plan-Logik der VOLLEN McGooby-Schicht (Welle B, Doc §2.2/§4.1):
## Seed → deterministische, MEHRSTUFIGE Bestell-Zettel über die
## interaktiven Stationen (Grill-Tap, Fritteuse-Halten mit Salz-Moment,
## Getränke-Zapfen mit Becher-Größen). Keine Nodes, keine Autoloads —
## golden-testbar wie McGoobySchichtLogic; Zahlen aus dem Balance-Pack.
##
## RNG-Zieh-Reihenfolge ist KONTRAKT der Goldwert-Tests: 1× Bestellanzahl,
## je Bestellung 1× Posten-Anzahl, je Posten 1× Rezept-Index (+1× Becher,
## wenn der Posten eine Zapf-Aufgabe trägt). Bot-Strom separat (seed+1),
## je Aufgabe 1× Geschick (+1× Salz-Geschick bei Salz-Aufgaben).

## Aufgaben-Arten: Grill = Timing-Tap (Welle A), Fritteuse/Getränke =
## Halten & im goldenen Fenster loslassen (Doc §2.2 #3, Becher-Variante).
const ART_TAP := "tap"
const ART_HALTEN := "halten"

## Salz-Schritt-Aktionen der Fritteuse (Pommes-Salz-Moment, Doc §3.1).
const SALZ_AKTIONEN: Array[String] = ["salz", "glitzersalz"]


## Deterministische Bestell-Folge der vollen Schicht. rezepte =
## McGoobyKatalog.rezepte_interaktiv() (Pack-Reihenfolge!). Rückgabe:
## [{nr, positionen: [{rezept_id, aufgaben: [{art, station, salz, becher}]}]}]
static func plan(seed_wert: int, rezepte: Array, bal: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if rezepte.is_empty():
		return out
	var rng := GoobyRng.new(seed_wert)
	var lo := maxi(1, int(bal.get("bestellungen_voll_min", 3)))
	var hi := maxi(lo, int(bal.get("bestellungen_voll_max", 5)))
	var anzahl := lo + int(floor(rng.next() * float(hi - lo + 1)))
	var posten_max := maxi(1, int(bal.get("positionen_max", 3)))
	for i in anzahl:
		var posten_anzahl := 1 + int(floor(rng.next() * float(posten_max)))
		var positionen: Array[Dictionary] = []
		for _p in posten_anzahl:
			var idx := mini(rezepte.size() - 1, int(floor(rng.next() * float(rezepte.size()))))
			var rezept_def: Dictionary = rezepte[idx]
			(
				positionen
				. append(
					{
						"rezept_id": str(rezept_def.get("id", "")),
						"aufgaben": aufgaben_fuer(rezept_def, rng),
					}
				)
			)
		out.append({"nr": i + 1, "positionen": positionen})
	return out


## Interaktive Aufgaben eines Rezepts in Schritt-Reihenfolge: Grill-Schritte
## werden zu n Wende-Taps, „frittieren“ zu EINER Halte-Aufgabe (mit
## Salz-Moment, wenn das Rezept einen Salz-Schritt trägt), „zapfen“ zu
## EINER Halte-Aufgabe mit deterministisch gezogener Becher-Größe.
## Nicht-interaktive Schritte (belegen/shake — Welle C) erzeugen KEINE
## Aufgabe (Welle-A-Prinzip: gespielt wird, was die Stationen hergeben).
static func aufgaben_fuer(rezept_def: Dictionary, rng: GoobyRng) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var salz := hat_salz(rezept_def)
	for schritt: Variant in rezept_def.get("schritte", []):
		if not (schritt is Dictionary):
			continue
		var zeile: Dictionary = schritt
		var station := str(zeile.get("station", ""))
		var aktion := str(zeile.get("aktion", ""))
		if station == "grill":
			for _i in maxi(1, int(zeile.get("anzahl", 1))):
				out.append({"art": ART_TAP, "station": "grill", "salz": false, "becher": ""})
		elif station == "fritteuse" and aktion == "frittieren":
			out.append({"art": ART_HALTEN, "station": "fritteuse", "salz": salz, "becher": ""})
		elif station == "getraenke" and aktion == "zapfen":
			(
				out
				. append(
					{
						"art": ART_HALTEN,
						"station": "getraenke",
						"salz": false,
						"becher": becher_ziehen(rng),
					}
				)
			)
	return out


## Trägt das Rezept einen Salz-Schritt? (Pommes Klassik: Salz, Möhren-
## Pommes: Glitzersalz — der Salz-Moment nach dem Korb-Heben.)
static func hat_salz(rezept_def: Dictionary) -> bool:
	for schritt: Variant in rezept_def.get("schritte", []):
		if not (schritt is Dictionary):
			continue
		var zeile: Dictionary = schritt
		if str(zeile.get("station", "")) != "fritteuse":
			continue
		if SALZ_AKTIONEN.has(str(zeile.get("aktion", ""))):
			return true
	return false


## Becher-Größe deterministisch ziehen (verbraucht genau 1 next()).
static func becher_ziehen(rng: GoobyRng) -> String:
	var groessen := McGoobyKatalog.BECHER_GROESSEN
	var idx := mini(groessen.size() - 1, int(floor(rng.next() * float(groessen.size()))))
	return groessen[idx]


## Timing einer Aufgabe: Stations-Fenster (Rezept darf per fenster_mult
## verengen) + Becher-Skalierung bei Zapf-Aufgaben.
static func timing_fuer(aufgabe: Dictionary, rezept_def: Dictionary) -> Dictionary:
	var basis := McGoobyKatalog.timing(str(aufgabe.get("station", "grill")), rezept_def)
	var becher := str(aufgabe.get("becher", ""))
	if becher.is_empty():
		return basis
	return McGoobyKatalog.timing_mit_becher(basis, becher)


## Salz-Moment-Bewertung (Doc §2.2 #3): Tap innerhalb des Salz-Fensters
## nach dem Korb-Heben = Glitzersalz-Bonus; danach passiert NICHTS
## Schlimmes (kein Fail-State, nur kein Bonus).
static func salz_bewerten(t_sec: float, bal: Dictionary) -> Dictionary:
	if t_sec <= salz_fenster_sec(bal):
		return {"getroffen": true, "punkte": maxi(0, int(bal.get("punkte_salz", 4)))}
	return {"getroffen": false, "punkte": 0}


static func salz_fenster_sec(bal: Dictionary) -> float:
	return maxf(0.1, float(bal.get("salz_fenster_sec", 1.2)))


## Aufgaben einer Bestellung zählen (Anzeige + Tests).
static func aufgaben_in(bestellung: Dictionary) -> int:
	var summe := 0
	for position: Variant in bestellung.get("positionen", []):
		if position is Dictionary:
			summe += ((position as Dictionary).get("aufgaben", []) as Array).size()
	return summe


## Deterministische Bot-Zertifizierung der vollen Schicht (Doc §10.4):
## derselbe Seed erzeugt denselben Plan UND dieselben Bot-Griffe → exakte
## Goldwerte. Rückgabe inkl. Abrechnung (McGoobyAbrechnung).
static func simulate_autoplay_voll(seed_wert: int, rezepte: Array, bal: Dictionary) -> Dictionary:
	var folge := plan(seed_wert, rezepte, bal)
	# Eigener Bot-RNG-Strom, versetzt geseedet — unabhängig vom Plan.
	var rng := GoobyRng.new(seed_wert + 1)
	var skill := clampf(float(bal.get("bot_skill", 0.9)), 0.0, 1.0)
	var salz_skill := clampf(float(bal.get("bot_salz_skill", 0.8)), 0.0, 1.0)
	var ergebnisse: Array[Dictionary] = []
	var perfekt := 0
	var roestaroma := 0
	var salz_treffer := 0
	for bestellung: Dictionary in folge:
		var punkte := 0
		var fehlerfrei := true
		for position: Dictionary in bestellung["positionen"]:
			for aufgabe: Dictionary in position["aufgaben"]:
				if rng.next() < skill:
					punkte += int(bal.get("punkte_perfekt", 10))
					perfekt += 1
				else:
					punkte += int(bal.get("punkte_roestaroma", 5))
					roestaroma += 1
					fehlerfrei = false
				if bool(aufgabe.get("salz", false)) and rng.next() < salz_skill:
					punkte += maxi(0, int(bal.get("punkte_salz", 4)))
					salz_treffer += 1
		punkte += int(bal.get("bestellung_fertig_bonus", 15))
		ergebnisse.append({"punkte": punkte, "fehlerfrei": fehlerfrei})
	var kasse := McGoobyAbrechnung.abrechnung(ergebnisse, bal)
	return {
		"seed": seed_wert,
		"bestellungen": folge.size(),
		"perfekt": perfekt,
		"roestaroma": roestaroma,
		"salz_treffer": salz_treffer,
		"punkte": int(kasse["punkte"]),
		"trinkgeld": int(kasse["trinkgeld"]),
		"muenzen": int(kasse["muenzen"]),
	}
