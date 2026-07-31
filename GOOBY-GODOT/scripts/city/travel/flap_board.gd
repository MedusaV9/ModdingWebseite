class_name FlapBoard
extends PanelContainer
## Abflugtafel im Split-Flap-Look (W13B, Doc H §2.4): dunkles Board, gelbe
## Monospace-Lettern (NUR AC-Tokens), Zeilen "Ziel | Abflug | Status".
## Beim Öffnen/Zielwechsel flippen die Zeichen ANIMIERT durch — jede Stelle
## klappert zyklisch durchs Flap-Alphabet, bis ihr Zielzeichen erreicht ist
## (echtes Fallblatt-Verhalten). Die Sequenz-Logik ist PUR + DETERMINISTISCH
## (`zeichen_schritt`/`text_schritt`/`flap_sequenz`) und die Zeit wird über
## `advance(delta)` injiziert (Tests takten von Hand; `_process` füttert im
## Spiel). Reduced Motion = Zieltext sofort, kein Geklapper.

signal alle_zeilen_fertig

## Fallblatt-Alphabet — Zeichen laufen zyklisch VORWÄRTS durch diese Kette.
## Zeichen außerhalb (z. B. ᴳ/Emojis) schnappen sofort aufs Ziel.
const FLAP_ZEICHEN := " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.:·-"
## Sekunden pro Flap-Frame.
const SCHRITT_S := 0.035
## Not-Deckel für die Sequenzlänge (Alphabet = 41 Zeichen → nie erreicht).
const MAX_SCHRITTE := 64
## Spaltenbreiten in Monospace-Zeichen (inkl. 2 Zeichen Spaltenluft).
const SPALTE_ZIEL := 17
const SPALTE_ABFLUG := 15
const SPALTE_STATUS := 15
## Gag-Status-Pool (Keys unter reisepass.tafel.*) — deterministisch je Ziel.
const STATUS_POOL := ["status_boarding", "status_puenktlich", "status_mampft", "status_flauscht"]

static var _mono_cache: Font = null

## Tests: true/false erzwingt Reduced Motion; null = ThemeService fragen.
var reduziert_override: Variant = null

var _zeilen_box: VBoxContainer
var _labels: Array[Label] = []
var _frames: Array = []
var _akku := 0.0


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = AcTokens.INK
	sb.set_corner_radius_all(AcTokens.RADIUS_ROW)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	add_theme_stylebox_override("panel", sb)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_zeilen_box = VBoxContainer.new()
	_zeilen_box.add_theme_constant_override("separation", 2)
	add_child(_zeilen_box)
	var titel := Label.new()
	titel.name = "TafelTitel"
	titel.text = I18nService.t("reisepass.tafel.titel")
	_stil(titel, AcTokens.YELLOW_DARK, 13)
	_zeilen_box.add_child(titel)
	var kopf := Label.new()
	kopf.name = "TafelKopf"
	kopf.text = zeile_text_von(
		{
			"ziel": I18nService.t("reisepass.tafel.ziel"),
			"abflug": I18nService.t("reisepass.tafel.abflug"),
			"status": I18nService.t("reisepass.tafel.status"),
		}
	)
	_stil(kopf, AcTokens.YELLOW_DARK, 13)
	_zeilen_box.add_child(kopf)


func _process(delta: float) -> void:
	advance(delta)


## ------------------------------------------------------ pure Flap-Logik


## EIN Flap-Schritt eines Zeichens: zyklisch vorwärts durchs Alphabet.
## Unbekannte Zeichen (ᴳ, Emojis, …) schnappen sofort aufs Ziel.
static func zeichen_schritt(von: String, nach: String) -> String:
	if von == nach:
		return von
	var i := FLAP_ZEICHEN.find(von)
	if i < 0 or FLAP_ZEICHEN.find(nach) < 0:
		return nach
	return FLAP_ZEICHEN[(i + 1) % FLAP_ZEICHEN.length()]


## EIN Flap-Schritt einer ganzen Zeile (kürzere Seite wird mit Luft gefüllt).
static func text_schritt(aktuell: String, ziel: String) -> String:
	var breite := maxi(aktuell.length(), ziel.length())
	var von := aktuell.rpad(breite, " ")
	var nach := ziel.rpad(breite, " ")
	var out := ""
	for i in breite:
		out += zeichen_schritt(von[i], nach[i])
	return out


## Komplette deterministische Frame-Sequenz von `von` nach `nach`
## (ohne den Startzustand, inklusive Endzustand).
static func flap_sequenz(von: String, nach: String) -> Array:
	var frames: Array = []
	var breite := maxi(von.length(), nach.length())
	var aktuell := von.rpad(breite, " ")
	var ziel := nach.rpad(breite, " ")
	while aktuell != ziel and frames.size() < MAX_SCHRITTE:
		aktuell = text_schritt(aktuell, ziel)
		frames.append(aktuell)
	if aktuell != ziel:
		frames.append(ziel)
	return frames


## Zieltext einer Board-Zeile: 3 Spalten, fest gerastert, GROSS.
static func zeile_text_von(eintrag: Dictionary) -> String:
	return (
		norm(str(eintrag.get("ziel", "")), SPALTE_ZIEL)
		+ norm(str(eintrag.get("abflug", "")), SPALTE_ABFLUG)
		+ norm(str(eintrag.get("status", "")), SPALTE_STATUS)
	)


## Spaltentext: GROSSBUCHSTABEN, auf Breite gekappt + mit Luft gefüllt
## (2 Zeichen Spaltenabstand bleiben immer frei).
static func norm(text: String, breite: int) -> String:
	return text.to_upper().left(breite - 2).rpad(breite, " ")


## Gag-Status je Ziel (deterministisch); zu teuer schlägt alles.
static func status_key(ziel_id: String, kann_zahlen: bool) -> String:
	if not kann_zahlen:
		return "reisepass.tafel.status_zu_teuer"
	return "reisepass.tafel.%s" % STATUS_POOL[_streu(ziel_id) % STATUS_POOL.size()]


## ------------------------------------------------------ Board-Steuerung


## Zeilen setzen (Dicts mit ziel/abflug/status). Vorhandene Zeilen flippen
## animiert auf die neuen Texte; Reduced Motion springt sofort.
func set_zeilen(eintraege: Array) -> void:
	while _labels.size() < eintraege.size():
		var label := Label.new()
		label.name = "TafelZeile%d" % _labels.size()
		_stil(label, AcTokens.YELLOW, 15)
		_zeilen_box.add_child(label)
		_labels.append(label)
		_frames.append([])
	for i in _labels.size():
		var sichtbar := i < eintraege.size()
		_labels[i].visible = sichtbar
		if not sichtbar:
			_frames[i] = []
			continue
		var ziel := zeile_text_von(eintraege[i])
		if _ist_reduziert():
			_labels[i].text = ziel
			_frames[i] = []
		else:
			_frames[i] = flap_sequenz(_labels[i].text, ziel)


## Injizierte Zeit: schiebt die Flap-Animation um `delta` Sekunden weiter.
func advance(delta: float) -> void:
	if not _hat_offene_frames():
		return
	_akku += delta
	while _akku >= SCHRITT_S:
		_akku -= SCHRITT_S
		for i in _labels.size():
			var frames: Array = _frames[i]
			if frames.is_empty():
				continue
			_labels[i].text = str(frames.pop_front())
		if not _hat_offene_frames():
			alle_zeilen_fertig.emit()
			return


## Aktueller Anzeigetext einer Zeile (Test-Sonde).
func zeile_text(index: int) -> String:
	if index < 0 or index >= _labels.size():
		return ""
	return _labels[index].text


## true = kein Flap mehr offen (alle Zeilen zeigen ihren Zieltext).
func fertig() -> bool:
	return not _hat_offene_frames()


func _hat_offene_frames() -> bool:
	for frames: Array in _frames:
		if not frames.is_empty():
			return true
	return false


func _ist_reduziert() -> bool:
	if reduziert_override is bool:
		return reduziert_override
	return ThemeService.is_reduced_motion(self)


func _stil(label: Label, farbe: Color, groesse: int) -> void:
	label.add_theme_font_override("font", _mono_font())
	label.add_theme_font_size_override("font_size", groesse)
	label.add_theme_color_override("font_color", farbe)
	label.clip_text = true


static func _mono_font() -> Font:
	if _mono_cache == null:
		var sys := SystemFont.new()
		sys.font_names = PackedStringArray(
			["JetBrains Mono", "DejaVu Sans Mono", "Menlo", "Consolas", "monospace"]
		)
		_mono_cache = sys
	return _mono_cache


static func _streu(text: String) -> int:
	var h := 7
	for i in text.length():
		h = (h * 31 + text.unicode_at(i)) % 1000003
	return h
