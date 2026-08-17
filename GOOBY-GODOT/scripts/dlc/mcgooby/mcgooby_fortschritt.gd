class_name McGoobyFortschritt
extends RefCounted
## Laden-Sterne-Fortschritt des McGooby-DLC (Welle C, Doc §6.1 — auf die
## JETZT ehrlich messbaren Größen verdichtet): der Rang (0–5 Sterne)
## leitet sich rein aus dem Save-Slice ab (mcgooby.schichten: gespielt,
## bestwert, perfekt) — KEINE Fantasie-Anzeigen für Systeme, die es noch
## nicht gibt (Deko/VIP/Kritiker kommen später und heben die Leiter dann
## per Pack-Update an). Die Stufen-Zahlen leben im Menü-Pack
## (McGoobyKatalog.raenge()), Anzeige im Hub-Detail (DlcScreen) und auf
## der Schicht-Ende-Karte. Pure + static, keine Nodes.

const MAX_STERNE := 5

const STERN_VOLL := "★"
const STERN_LEER := "☆"


## Rang-relevanter Stand aus dem Slice: {gespielt, bestwert, perfekt}.
static func stand(gs: Object) -> Dictionary:
	if gs == null:
		return {"gespielt": 0, "bestwert": 0, "perfekt": 0}
	return {
		"gespielt": maxi(0, int(gs.get_value("mcgooby.schichten.gespielt", 0))),
		"bestwert": maxi(0, int(gs.get_value("mcgooby.schichten.bestwert", 0))),
		"perfekt": maxi(0, int(gs.get_value("mcgooby.schichten.perfekt", 0))),
	}


## Aktueller Rang: höchste Stufe der Leiter, deren Anforderungen ALLE
## erfüllt sind (0 = noch kein Stern).
static func sterne(gs: Object) -> int:
	var ist := stand(gs)
	var erreicht := 0
	for stufe: Variant in McGoobyKatalog.raenge():
		if stufe is Dictionary and _erfuellt(ist, stufe):
			erreicht = maxi(erreicht, int((stufe as Dictionary).get("stern", 0)))
	return clampi(erreicht, 0, MAX_STERNE)


## Nächste Stufe der Leiter mit ehrlichen Rest-Zielen ({} = Leiter voll):
## {stern, fehlt_schichten, fehlt_bestwert, fehlt_perfekt}.
static func naechster_rang(gs: Object) -> Dictionary:
	var ist := stand(gs)
	var aktuell := sterne(gs)
	for stufe: Variant in McGoobyKatalog.raenge():
		if not (stufe is Dictionary):
			continue
		var zeile: Dictionary = stufe
		if int(zeile.get("stern", 0)) != aktuell + 1:
			continue
		return {
			"stern": aktuell + 1,
			"fehlt_schichten": maxi(0, int(zeile.get("schichten", 0)) - int(ist["gespielt"])),
			"fehlt_bestwert": maxi(0, int(zeile.get("bestwert", 0)) - int(ist["bestwert"])),
			"fehlt_perfekt": maxi(0, int(zeile.get("perfekt", 0)) - int(ist["perfekt"])),
		}
	return {}


## Sterne-Band fürs UI („★★☆☆☆“).
static func sterne_band(anzahl: int) -> String:
	var voll := clampi(anzahl, 0, MAX_STERNE)
	return STERN_VOLL.repeat(voll) + STERN_LEER.repeat(MAX_STERNE - voll)


## Rang-Zeile fürs UI („Laden-Rang: ★★☆☆☆“).
static func rang_zeile(gs: Object) -> String:
	return I18nService.t("dlc_mcgooby.fortschritt.rang", {"sterne": sterne_band(sterne(gs))})


## Ehrliche Nächstes-Ziel-Zeile fürs UI: zählt NUR auf, was wirklich noch
## fehlt („Nächster Stern: noch 3 Schichten · Bestwert 130“); bei voller
## Leiter der Fünf-Sterne-Glanz-Satz.
static func ziel_zeile(gs: Object) -> String:
	var naechster := naechster_rang(gs)
	if naechster.is_empty():
		return I18nService.t("dlc_mcgooby.fortschritt.voll")
	var teile: PackedStringArray = PackedStringArray()
	if int(naechster["fehlt_schichten"]) > 0:
		teile.append(
			I18nService.t(
				"dlc_mcgooby.fortschritt.ziel_schichten", {"n": int(naechster["fehlt_schichten"])}
			)
		)
	if int(naechster["fehlt_bestwert"]) > 0:
		var stufe := _stufe(int(naechster["stern"]))
		teile.append(
			I18nService.t(
				"dlc_mcgooby.fortschritt.ziel_bestwert", {"punkte": int(stufe.get("bestwert", 0))}
			)
		)
	if int(naechster["fehlt_perfekt"]) > 0:
		teile.append(
			I18nService.t(
				"dlc_mcgooby.fortschritt.ziel_perfekt", {"n": int(naechster["fehlt_perfekt"])}
			)
		)
	if teile.is_empty():
		# Alle Ziele erfüllt, aber der Rang springt erst mit der nächsten
		# Verbuchung um — ehrlicher Fallback statt leerer Zeile.
		return I18nService.t("dlc_mcgooby.fortschritt.rang", {"sterne": sterne_band(sterne(gs))})
	return I18nService.t("dlc_mcgooby.fortschritt.ziel", {"ziele": " · ".join(teile)})


## ------------------------------------------------- Aufstiegs-Latch (W20)


## Rang-Aufstieg NACH der Schicht-Verbuchung prüfen (W20 Top-10 #1):
## `vorher` = sterne(gs) VOR schicht_verbuchen. Gefeiert wird nur eine
## Stufe, die (1) in DIESER Schicht wirklich erreicht wurde und (2) laut
## Save-Latch (mcgooby.schichten.rangGefeiert) noch nie dran war — genau
## EIN Beat pro Stufe, Reload-fest. Alt-Saves mit Rang, aber ohne Latch
## werden STILL nachgezogen (kein Nachhol-Konfetti für alte Erfolge).
## Rückgabe: {"feiern": bool, "stern": int — aktueller Rang}.
static func aufstieg_pruefen(gs: Object, vorher: int) -> Dictionary:
	if gs == null:
		return {"feiern": false, "stern": 0}
	var neu := sterne(gs)
	var gefeiert := maxi(0, int(gs.get_value("mcgooby.schichten.rangGefeiert", 0)))
	var feiern := neu > vorher and neu > gefeiert
	if neu > gefeiert:
		gs.set_value("mcgooby.schichten.rangGefeiert", neu)
	return {"feiern": feiern, "stern": neu}


static func _erfuellt(ist: Dictionary, stufe: Dictionary) -> bool:
	return (
		int(ist["gespielt"]) >= int(stufe.get("schichten", 0))
		and int(ist["bestwert"]) >= int(stufe.get("bestwert", 0))
		and int(ist["perfekt"]) >= int(stufe.get("perfekt", 0))
	)


static func _stufe(stern: int) -> Dictionary:
	for stufe: Variant in McGoobyKatalog.raenge():
		if stufe is Dictionary and int((stufe as Dictionary).get("stern", 0)) == stern:
			return stufe
	return {}
