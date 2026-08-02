class_name McGoobyAbrechnung
extends RefCounted
## Pure Schicht-Abrechnung des McGooby-DLC (Welle A, Doc §2.2.5/§2.4):
## Punkte → Münzen über eine coin_table wie `burger_build` (Divisor + Min/Max)
## plus Trinkgeld über die Combo-Kette (×1,1 … ×2,0 — Verlust der Kette
## kostet NIE Basis-Punkte). Keine Nodes, Zahlen aus dem Balance-Pack.


## Combo-Multiplikator nach n fehlerfreien Bestellungen in Folge.
static func combo_mult(fehlerfreie_in_folge: int, bal: Dictionary) -> float:
	var start := float(bal.get("combo_start", 1.0))
	var schritt := float(bal.get("combo_schritt", 0.1))
	var deckel := float(bal.get("combo_max", 2.0))
	return minf(deckel, start + schritt * float(maxi(0, fehlerfreie_in_folge)))


## Schicht-Kassensturz. ergebnisse = [{punkte: int, fehlerfrei: bool}] in
## Spielreihenfolge. Rückgabe: {punkte, muenzen_basis, trinkgeld, muenzen,
## combo_max_mult, fehlerfreie, buehne_trinkgeld}.
## Welle B ADDITIV: extra_trinkgeld = Bühnen-Bonus („Kunden-Jubel = Trinkgeld-
## Regen“, 1×/Schicht) — fließt NUR ins Trinkgeld, nie in die Punkte, damit
## die Punkte-Goldens (Bot-Zertifizierung) unberührt bleiben.
static func abrechnung(ergebnisse: Array, bal: Dictionary, extra_trinkgeld := 0) -> Dictionary:
	var punkte := 0
	var trinkgeld := 0
	var streak := 0
	var fehlerfreie := 0
	var combo_spitze := combo_mult(0, bal)
	var basis := maxi(0, int(bal.get("trinkgeld_basis", 2)))
	for eintrag: Variant in ergebnisse:
		if not (eintrag is Dictionary):
			continue
		var zeile: Dictionary = eintrag
		punkte += maxi(0, int(zeile.get("punkte", 0)))
		if bool(zeile.get("fehlerfrei", false)):
			streak += 1
			fehlerfreie += 1
			var mult := combo_mult(streak, bal)
			combo_spitze = maxf(combo_spitze, mult)
			trinkgeld += int(round(float(basis) * mult))
		else:
			streak = 0
	var buehne := maxi(0, extra_trinkgeld)
	trinkgeld += buehne
	var muenzen_basis := muenzen_fuer(punkte, bal)
	return {
		"punkte": punkte,
		"muenzen_basis": muenzen_basis,
		"trinkgeld": trinkgeld,
		"muenzen": muenzen_basis + trinkgeld,
		"combo_max_mult": combo_spitze,
		"fehlerfreie": fehlerfreie,
		"buehne_trinkgeld": buehne,
	}


## coin_table-Zeile (Muster burger_build: Punkte/Divisor, geklemmt Min..Max).
static func muenzen_fuer(punkte: int, bal: Dictionary) -> int:
	var divisor := maxi(1, int(bal.get("coin_divisor", 4)))
	var lo := maxi(0, int(bal.get("coin_min", 6)))
	var hi := maxi(lo, int(bal.get("coin_max", 30)))
	return clampi(int(floor(float(maxi(0, punkte)) / float(divisor))), lo, hi)
