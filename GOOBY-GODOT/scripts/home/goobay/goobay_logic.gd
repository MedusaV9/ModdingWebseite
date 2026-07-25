class_name GoobayLogic
extends RefCounted
## Goobay-Verhandlung (Doc D §5.4) — das Emoji-Lese-Spiel als PURE Logik:
## kein Node, keine Uhr, keine UI. Der Zufall kommt ausschließlich aus einem
## übergebenen RandomNumberGenerator → mit festem Seed vollständig
## deterministisch testbar (tests/unit/test_home_goobay.gd).
##
## Ablauf:
##   V = sellBase × tagesNachfrage         (verdeckter Marktwert)
##   B = V × rand(0.95–1.35)               (verdecktes Käufer-Budget)
##   P ∈ {2, 3, 4}                         (verdeckte Geduld in Runden)
##   O₀ = V × rand(0.55–0.75)              (Eröffnungsangebot)
## Der Spieler hat pro Runde drei Knöpfe: „Höher!“, „Deal!“, „Lass gut sein“.
## Nach jedem „Höher!“ steigt das Angebot um 18–25 %, ABER die Stimmung des
## Käufers sinkt sichtbar — das ist das lesbare Signal (Stufen 0–4).
## Überschreitet die Forderung das Budget ODER ist die Geduld aufgebraucht,
## entscheidet ein Münzwurf: „ALLERletztes Angebot!“ oder Abbruch.

## Sitzungs-Status (stabile Strings für UI/Tests).
const STATUS_OFFEN := "offen"
const STATUS_FINAL := "final"
const STATUS_DEAL := "deal"
const STATUS_ABBRUCH := "abbruch"

## Stimmungsstufen 0 (bester Laune) … 4 (sauer) — HomeIcons zeichnet sie.
const STIMMUNG_MAX := 4
## Tagesnachfrage-Band pro Kategorie („heute sind Teppiche gefragt!“).
const NACHFRAGE_MIN := 0.8
const NACHFRAGE_MAX := 1.3
## Budget-, Eröffnungs- und Nachfass-Bänder.
const BUDGET_MIN := 0.95
const BUDGET_MAX := 1.35
const EROEFFNUNG_MIN := 0.55
const EROEFFNUNG_MAX := 0.75
const NACHFASS_MIN := 0.18
const NACHFASS_MAX := 0.25
## Geduld-Band (Runden) und Malus nach einem Abbruch (Doc D §5.4).
const GEDULD_MIN := 2
const GEDULD_MAX := 4
const ABBRUCH_NACHFRAGE_MALUS := 0.1

## Käufertypen: Vielredner haben mehr Geduld, knappe Typen weniger — das
## Textbild verrät also (fair!) etwas über den verdeckten Wert.
const TYP_VIELREDNER := "vielredner"
const TYP_KNAPP := "knapp"


## Tagesnachfrage einer Kategorie würfeln (einmal pro Tag, Doc D §5.4).
static func tages_nachfrage(rng: RandomNumberGenerator) -> float:
	return snappedf(rng.randf_range(NACHFRAGE_MIN, NACHFRAGE_MAX), 0.01)


## Neue Verhandlung. `sell_base` = Katalog-Verkaufswert, `nachfrage` = Faktor
## des Tages. Liefert den vollständigen Sitzungs-Zustand (verdeckte Werte
## inklusive — das UI zeigt sie NICHT an, die Tests prüfen sie).
static func start(
	item_id: String, sell_base: int, nachfrage: float, rng: RandomNumberGenerator
) -> Dictionary:
	var wert := maxi(1, int(round(float(sell_base) * maxf(0.1, nachfrage))))
	var typ := TYP_VIELREDNER if rng.randf() < 0.5 else TYP_KNAPP
	var geduld := rng.randi_range(GEDULD_MIN, GEDULD_MAX)
	if typ == TYP_VIELREDNER:
		geduld = mini(GEDULD_MAX, geduld + 1)
	return {
		"item": item_id,
		"wert": wert,
		"budget": maxi(1, int(round(wert * rng.randf_range(BUDGET_MIN, BUDGET_MAX)))),
		"geduld": geduld,
		"runde": 0,
		"angebot": maxi(1, int(round(wert * rng.randf_range(EROEFFNUNG_MIN, EROEFFNUNG_MAX)))),
		"stimmung": 0,
		"status": STATUS_OFFEN,
		"typ": typ,
		"erloes": 0,
	}


## „Höher!“ — Gegenangebot. Mutiert die Sitzung und liefert sie zurück.
static func hoeher(session: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	if str(session.get("status", "")) != STATUS_OFFEN:
		# Nach dem ALLERletzten Angebot gibt es nichts mehr zu holen.
		if str(session.get("status", "")) == STATUS_FINAL:
			session["status"] = STATUS_ABBRUCH
		return session
	var forderung := int(
		ceil(int(session["angebot"]) * (1.0 + rng.randf_range(NACHFASS_MIN, NACHFASS_MAX)))
	)
	session["runde"] = int(session["runde"]) + 1
	session["stimmung"] = mini(STIMMUNG_MAX, int(session["stimmung"]) + 1)
	var geduld_weg: bool = int(session["runde"]) >= int(session["geduld"])
	if forderung > int(session["budget"]) or geduld_weg:
		if rng.randf() < 0.5:
			session["status"] = STATUS_FINAL
			session["angebot"] = mini(forderung, int(session["budget"]))
		else:
			session["status"] = STATUS_ABBRUCH
		return session
	session["angebot"] = forderung
	return session


## „Deal!“ — annehmen. Nur aus OFFEN/FINAL heraus möglich.
static func annehmen(session: Dictionary) -> Dictionary:
	var status := str(session.get("status", ""))
	if status != STATUS_OFFEN and status != STATUS_FINAL:
		return session
	session["status"] = STATUS_DEAL
	session["erloes"] = int(session["angebot"])
	return session


## „Lass gut sein“ — abbrechen (das Möbel bleibt im Lager).
static func abbrechen(session: Dictionary) -> Dictionary:
	if str(session.get("status", "")) == STATUS_DEAL:
		return session
	session["status"] = STATUS_ABBRUCH
	return session


static func ist_beendet(session: Dictionary) -> bool:
	var status := str(session.get("status", ""))
	return status == STATUS_DEAL or status == STATUS_ABBRUCH


## Versandbonus für „zur Post bringen“ statt Abholung (Doc D §5.4): +10 %,
## ganzzahlig aufgerundet (bewusst OHNE float — 100 ᴳ sollen 110 ᴳ ergeben,
## nicht 111 durch einen 1.1-Rundungsfehler).
static func post_bonus(erloes: int) -> int:
	return (erloes * 11 + 9) / 10


## Nachfrage-Malus nach einem geplatzten Deal (−10 %, Untergrenze bleibt
## das Nachfrage-Band).
static func nachfrage_nach_abbruch(nachfrage: float) -> float:
	return maxf(NACHFRAGE_MIN, snappedf(nachfrage - ABBRUCH_NACHFRAGE_MALUS, 0.01))


## Sichtbarer Sitzungs-Zustand fürs UI — OHNE Budget und Geduld.
static func public_view(session: Dictionary) -> Dictionary:
	return {
		"item": str(session.get("item", "")),
		"angebot": int(session.get("angebot", 0)),
		"stimmung": int(session.get("stimmung", 0)),
		"status": str(session.get("status", STATUS_OFFEN)),
		"typ": str(session.get("typ", TYP_KNAPP)),
		"runde": int(session.get("runde", 0)),
	}
