class_name MrzGag
extends RefCounted
## Reisepass 2.0 (W13B, Doc H §2.2): der MRZ-GAG — zwei Zeilen "maschinen-
## lesbares" Kauderwelsch unten auf der Stempelseite, generiert aus
## Spielername + Gooby-Spitzname. PUR + DETERMINISTISCH (Test-Kontrakt):
## gleiche Namen ⇒ byte-gleiche Zeilen, Zeichensatz STRIKT A–Z und `<`
## (echtes MRZ-Feeling, Inhalt = Quatsch: `P<GOOFLAUSCHI<<...` +
## `MAMPF<NOM<NOM<...`). Umlaute werden amtlich transliteriert (AE/OE/UE/SS)
## — die Umlaut-Literale stehen als Codepoints da, nicht als Zeichen.

## Zeilenlänge (Kinderpass-Format — kürzer als die echten 44 Zeichen).
const LINE_LEN := 30

## Quatsch-Wortpool für Zeile 2 (NUR A–Z!) — deterministisch "gewürfelt".
const QUATSCH := [
	"MAMPF",
	"NOM",
	"FLAUSCH",
	"MOEHRE",
	"KAROTTE",
	"HOPPEL",
	"SCHNUFF",
	"WACKELPO",
	"PLUESCH",
	"KNUFF",
	"BOING",
	"MJAM",
]

## Fallbacks, falls (Spitz-)Name leer oder komplett unlesbar ist.
const FALLBACK_GOOBY := "GOOBY"
const FALLBACK_MENSCH := "FLAUSCHFREUND"


## Beide MRZ-Zeilen: [zeile_1, zeile_2].
static func zeilen(spieler_name: String, spitzname: String) -> Array:
	return [zeile_1(spieler_name, spitzname), zeile_2(spieler_name, spitzname)]


## Zeile 1 — "Dokumentenzeile": P<GOO + Spitzname << Spielername.
static func zeile_1(spieler_name: String, spitzname: String) -> String:
	var gooby := sanitize(spitzname)
	if gooby.is_empty():
		gooby = FALLBACK_GOOBY
	var mensch := sanitize(spieler_name)
	if mensch.is_empty():
		mensch = FALLBACK_MENSCH
	return _pad("P<GOO" + gooby + "<<" + mensch)


## Zeile 2 — Quatsch-Wörter, deterministisch aus dem Namens-Hash gewählt.
static func zeile_2(spieler_name: String, spitzname: String) -> String:
	var streuung := hash_of(sanitize(spieler_name) + "|" + sanitize(spitzname))
	var teile: Array[String] = []
	for i in 4:
		teile.append(QUATSCH[(streuung + i * 7) % QUATSCH.size()])
	return _pad("<".join(teile))


## Name → MRZ-Zeichen: Umlaute amtlich (AE/OE/UE/SS), Rest A–Z,
## Leerzeichen/Bindestrich → `<`, alles andere fliegt raus.
static func sanitize(text: String) -> String:
	var gross := _translit(text).to_upper()
	var out := ""
	for i in gross.length():
		var c := gross.unicode_at(i)
		if c >= 65 and c <= 90:
			out += char(c)
		elif c == 32 or c == 45:
			out += "<"
	return out


## Deterministischer Streu-Hash (KEIN String.hash() — eigener, damit der
## Test-Kontrakt nicht an Engine-Interna hängt).
static func hash_of(text: String) -> int:
	var h := 7
	for i in text.length():
		h = (h * 31 + text.unicode_at(i)) % 1000003
	return h


## Umlaut-Transliteration über Codepoints (ä→ae, Ö→Oe, ß→ss, ...).
static func _translit(text: String) -> String:
	var tafel := {
		char(0x00E4): "ae",
		char(0x00F6): "oe",
		char(0x00FC): "ue",
		char(0x00C4): "Ae",
		char(0x00D6): "Oe",
		char(0x00DC): "Ue",
		char(0x00DF): "ss",
	}
	var out := text
	for k: String in tafel:
		out = out.replace(k, tafel[k])
	return out


## Auf LINE_LEN kappen und mit `<` auffüllen.
static func _pad(text: String) -> String:
	return text.left(LINE_LEN).rpad(LINE_LEN, "<")
