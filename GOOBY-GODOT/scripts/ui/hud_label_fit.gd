class_name HudLabelFit
extends RefCounted
## G7-P50 — PURE Mess-/Einpass-Logik für HUD-Beschriftungen (headless
## testbar, keine Nodes). iPhone-Befund: Kachel-Labels erschienen im
## Querformat abgeschnitten OHNE Ellipsis („IGohbi"/„Garder"/„Gestalt").
## Lösung laut Paket: bestehende Spiel-Begriffe BEHALTEN und die
## Schriftgröße pro Kachel auf die verfügbare Breite eindampfen
## (Font-Autoshrink). Erst wenn selbst MIN_PX nicht reicht, meldet
## `passt=false` — der Aufrufer setzt dann BEWUSST Ellipsis (letzter
## Ausweg statt stillem Abschneiden).

## Unterste lesbare Schriftgröße (Design-px) — darunter Ellipsis.
const MIN_PX := 8


## Gerenderte Textbreite in px für Font/Größe (0 ohne Font — headless-sicher).
static func text_breite(font: Font, text: String, groesse_px: int) -> float:
	if font == null:
		return 0.0
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, groesse_px).x


## Größte Schriftgröße ≤ wunsch_px, mit der `text` in `verfuegbar` px passt.
## Rückgabe: {"px": int, "passt": bool} — passt=false heißt: selbst MIN_PX
## ist zu breit, der Aufrufer muss sichtbar kürzen (Ellipsis).
static func passende_groesse(
	font: Font, text: String, wunsch_px: int, verfuegbar: float
) -> Dictionary:
	var px := maxi(wunsch_px, MIN_PX)
	while px > MIN_PX and text_breite(font, text, px) > verfuegbar:
		px -= 1
	return {"px": px, "passt": text_breite(font, text, px) <= verfuegbar}


## W18/E6 — Einpass-Kaskade: voller Titel zuerst (Autoshrink bis MIN_PX);
## passt selbst das Minimum nicht, übernimmt die KURZFORM (ein kürzeres,
## VOLLSTÄNDIGES Wort — nie ein „IGohb“-Fragment) und schrumpft erneut.
## Passt auch die Kurzform nicht, gewinnt der schmalere Kandidat mit
## passt=false — der Aufrufer setzt dann BEWUSST Ellipsis (letzter Ausweg).
## Rückgabe: {"text": String, "px": int, "passt": bool}.
static func einpassen(
	font: Font, voll: String, kurz: String, wunsch_px: int, verfuegbar: float
) -> Dictionary:
	var fit := passende_groesse(font, voll, wunsch_px, verfuegbar)
	if bool(fit["passt"]) or kurz.is_empty() or kurz == voll:
		return {"text": voll, "px": int(fit["px"]), "passt": bool(fit["passt"])}
	var kurz_fit := passende_groesse(font, kurz, wunsch_px, verfuegbar)
	if bool(kurz_fit["passt"]):
		return {"text": kurz, "px": int(kurz_fit["px"]), "passt": true}
	if text_breite(font, kurz, MIN_PX) < text_breite(font, voll, MIN_PX):
		return {"text": kurz, "px": int(kurz_fit["px"]), "passt": false}
	return {"text": voll, "px": int(fit["px"]), "passt": false}


## Schmalste Textbreite, die eine Kachel für diesen Titel bei MIN_PX braucht
## (Kurzform zählt mit, wenn vorhanden) — Basis der Kachel-Mindestbreite,
## damit `einpassen` IMMER einen vollständig sichtbaren Kandidaten findet.
static func mindest_breite(font: Font, voll: String, kurz: String) -> float:
	var breite := text_breite(font, voll, MIN_PX)
	if not kurz.is_empty():
		breite = minf(breite, text_breite(font, kurz, MIN_PX))
	return breite
