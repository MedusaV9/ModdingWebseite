class_name GoobyePreis
extends RefCounted
## Preis- und Margen-Rechnung des „Goo und Bye“ (G5/P24, Doc §2.2/§4.4) —
## PURE + static, ohne Node- und ohne Uhr-Abhängigkeit. EINE fühlbare Kurve,
## kein BWL-Excel: der „empfohlene Preis“ ist der Default-Knopf (§2.5), der
## Preis-Schieber bewegt sich ±30 % um den Richtwert, der Großmarkt-Einkauf
## kostet 60 % des empfohlenen Verkaufspreises. Alle Stellschrauben kommen
## aus dem Balance-Pack (GoobyeKatalog), Fallback = eingebaute Defaults.

## Griff-Kurve (§2.2): teurer ⇒ Kunden lassen eher liegen (streng fallend),
## billiger ⇒ kleiner Spontankauf-Bonus. Deckel halten alles gutmütig.
const GRIFF_STEIGUNG := 1.2
const GRIFF_MIN := 0.3
const GRIFF_MAX := 1.0
const SPONTAN_STEIGUNG := 0.8
const SPONTAN_MAX := 0.24


## Der „empfohlene Preis“-Knopf: Richtwert `vk` aus dem Pack, Eigenmarke
## −20 % (§4.1), Bio +10 % (§2.2). Nie unter 1 Münze.
static func empfohlener_preis(ware: Dictionary) -> int:
	var basis := maxf(0.0, float(ware.get("vk", 0)))
	if bool(ware.get("eigenmarke", false)):
		basis *= 1.0 - GoobyeKatalog.eigenmarke_rabatt()
	if bool(ware.get("bio", false)):
		basis *= 1.0 + GoobyeKatalog.bio_aufschlag()
	return maxi(1, roundi(basis))


## Großmarkt-Einkaufspreis = ek_faktor × empfohlener Verkaufspreis (§2.2).
static func einkaufspreis(ware: Dictionary) -> int:
	return maxi(1, roundi(float(empfohlener_preis(ware)) * GoobyeKatalog.ek_faktor()))


## Preis-Schieber-Stellung auf die erlaubte Spanne klemmen (±30 %, §2.2).
static func faktor_begrenzen(faktor: float) -> float:
	var spanne := GoobyeKatalog.preis_spanne()
	return clampf(faktor, 1.0 - spanne, 1.0 + spanne)


## Tatsächlicher Stückpreis einer Schieber-Stellung — der Kunde zahlt IMMER
## genau das (Muster MarktSim.stueckpreis).
static func verkaufspreis(ware: Dictionary, faktor := 1.0) -> int:
	return maxi(1, roundi(float(empfohlener_preis(ware)) * faktor_begrenzen(faktor)))


## Marge pro Stück bei einer Schieber-Stellung (kann bei −30 % negativ
## werden — sichtbar im Sheet, das ist die Lernkurve, keine Strafe).
static func marge(ware: Dictionary, faktor := 1.0) -> int:
	return verkaufspreis(ware, faktor) - einkaufspreis(ware)


## Griff-Wahrscheinlichkeit (0..1) je Schieber-Stellung: bei ≤ Richtwert
## greifen Kunden sicher zu, darüber fällt die Lust linear (streng monoton —
## Golden-Tests und Balance bleiben erklärbar).
static func griff_chance(faktor := 1.0) -> float:
	var f := faktor_begrenzen(faktor)
	return clampf(GRIFF_MAX - maxf(0.0, f - 1.0) * GRIFF_STEIGUNG, GRIFF_MIN, GRIFF_MAX)


## Spontankauf-Bonus (0..SPONTAN_MAX) unterhalb des Richtwerts: billiger =
## größere Körbe (§2.2) — als Zusatz-Chance auf +1 Artikel im Bon.
static func spontan_bonus(faktor := 1.0) -> float:
	var f := faktor_begrenzen(faktor)
	return clampf((1.0 - f) * SPONTAN_STEIGUNG, 0.0, SPONTAN_MAX)
