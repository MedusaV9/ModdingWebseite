class_name McGoobyStationenUi
extends HBoxContainer
## Stations-Pills der vollen McGooby-Schicht (G6/MCGOOBY-B, Doc §2.2):
## eine EIGENE Layout-Zeile mit einer Pill pro interaktiver Station —
## die aktive Station leuchtet, ein Tipp auf eine Pill ruft ihre
## Gesten-Hilfe (Callout-Text aus dem Menü-Pack) auf.
##
## Playtest-Befund B2 (G8-PT2, Pill-Overlays verdecken Regal-Slots): diese
## Pills liegen bewusst IM Spalten-Fluss (VBox-Zeile) statt als Overlay —
## sie KÖNNEN den Aktions-Knopf konstruktiv nicht verdecken; der
## Geometrie-Test prüft die Überlappungsfreiheit trotzdem explizit.
## Dazu der Stil-Helfer fürs Aktions-Knopf-Gesicht (stil_fuer): Stations-
## Präsentation gehört hierher, die Szene bleibt Ablauf-Logik.

signal hilfe_gewuenscht(station_id: String)

## Patty-/Stations-Zustandsfarben (Welle-A-Palette + Sprudel-Blau).
const FARBE_ROH := Color("#E8A18B")
const FARBE_GOLDBRAUN := Color("#E8C25A")
const FARBE_KOHLE := Color("#54382A")
const FARBE_SPRUDEL := Color("#9ED9E8")
const FARBE_SALZ := Color("#F4EFE2")
const FARBE_TEXT_HELL := Color("#FFF3DC")
const FARBE_TEXT_DUNKEL := Color("#6B4A2B")

var _pills: Dictionary = {}


func _ready() -> void:
	name = "StationenZeile"
	add_theme_constant_override("separation", 10)
	for station_id in McGoobyKatalog.STATIONEN_INTERAKTIV:
		var pill := SquishButton.new()
		pill.name = "Pill_" + station_id
		pill.theme_type_variation = &"BtnGhost"
		pill.text = McGoobyKatalog.text_von(McGoobyKatalog.station(station_id), "name")
		pill.focus_mode = Control.FOCUS_NONE
		pill.custom_minimum_size = Vector2(0.0, AcTokens.TOUCH_FLOOR)
		pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pill.pressed.connect(_on_pill_pressed.bind(station_id))
		add_child(pill)
		_pills[station_id] = pill


## Aktive Station hervorheben (Teal = dran, Ghost = wartet).
func aktiviere(station_id: String) -> void:
	for id: String in _pills:
		var pill: Button = _pills[id]
		pill.theme_type_variation = &"BtnTeal" if id == station_id else &"BtnGhost"


func pills() -> Array[Button]:
	var out: Array[Button] = []
	for id: String in _pills:
		out.append(_pills[id])
	return out


func apply_metrics(m: Dictionary) -> void:
	for pill: Button in pills():
		ScreenShell.touch_target(pill, m)


## Gesten-Hilfe-Text einer Station (aus dem Pack, lokalisiert).
static func geste_von(station_id: String) -> String:
	return McGoobyKatalog.text_von(McGoobyKatalog.station(station_id), "geste")


## Aktions-Knopf-Gesicht für eine Voll-Schicht-Aufgabe: Farbe + Prompt je
## Station/Zustand (Halten-Aufgaben zeigen ohne Griff die Aufforderung,
## mit Griff den Gar-Zustand; der Salz-Moment übersteuert alles).
## Rückgabe: {"farbe": Color, "text_farbe": Color, "text": String}.
static func stil_fuer(aufgabe: Dictionary, zustand: String, haelt: bool, salz: bool) -> Dictionary:
	if salz:
		return {
			"farbe": FARBE_SALZ,
			"text_farbe": FARBE_TEXT_DUNKEL,
			"text": I18nService.t("dlc_mcgooby.schicht.salz_jetzt"),
		}
	var station := str(aufgabe.get("station", "grill"))
	var halten := str(aufgabe.get("art", "")) == McGoobySchichtPlan.ART_HALTEN
	if halten and not haelt and zustand == McGoobySchichtLogic.ZUSTAND_ROH:
		return {
			"farbe": FARBE_SPRUDEL if station == "getraenke" else FARBE_ROH,
			"text_farbe": FARBE_TEXT_DUNKEL,
			"text": I18nService.t("dlc_mcgooby.schicht.halten_" + station),
		}
	match zustand:
		McGoobySchichtLogic.ZUSTAND_GOLDBRAUN:
			return {
				"farbe": FARBE_GOLDBRAUN,
				"text_farbe": FARBE_TEXT_DUNKEL,
				"text":
				I18nService.t(
					"dlc_mcgooby.schicht.loslassen" if halten else "dlc_mcgooby.schicht.goldbraun"
				),
			}
		McGoobySchichtLogic.ZUSTAND_KOHLE:
			return {
				"farbe": FARBE_KOHLE,
				"text_farbe": FARBE_TEXT_HELL,
				"text":
				I18nService.t(
					(
						"dlc_mcgooby.schicht.schaum"
						if station == "getraenke"
						else "dlc_mcgooby.schicht.kohle"
					)
				),
			}
		_:
			var key := "dlc_mcgooby.schicht.roh"
			if station == "getraenke":
				key = "dlc_mcgooby.schicht.blubbert"
			elif station == "fritteuse":
				key = "dlc_mcgooby.schicht.blass"
			return {
				"farbe": FARBE_SPRUDEL if station == "getraenke" else FARBE_ROH,
				"text_farbe": FARBE_TEXT_DUNKEL,
				"text": I18nService.t(key),
			}


## Stil aufs Aktions-Knopf-Gesicht anwenden (Pillenform: Radius = halbe
## Wunschhöhe; Text-Farbe für alle Druck-Zustände gleich — der Knopf soll
## unter dem Finger die FARBE des Gar-Zustands behalten).
static func stil_anwenden(knopf: Button, farbe: Color, text_farbe: Color, text: String) -> void:
	knopf.text = text
	knopf.add_theme_color_override("font_color", text_farbe)
	knopf.add_theme_color_override("font_pressed_color", text_farbe)
	knopf.add_theme_color_override("font_hover_color", text_farbe)
	var stil := StyleBoxFlat.new()
	stil.bg_color = farbe
	stil.set_corner_radius_all(int(knopf.custom_minimum_size.y / 2.0))
	knopf.add_theme_stylebox_override("normal", stil)
	knopf.add_theme_stylebox_override("hover", stil)
	knopf.add_theme_stylebox_override("pressed", stil)


func _on_pill_pressed(station_id: String) -> void:
	AudioDirector.try_play(self, "ui_tick")
	hilfe_gewuenscht.emit(station_id)
