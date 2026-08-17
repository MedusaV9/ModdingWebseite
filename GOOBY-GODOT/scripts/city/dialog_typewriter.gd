class_name DialogTypewriter
extends RefCounted
## Buchstaben-Typewriter fürs Dialog-System (W13B, E §2.2-Rest): PURE
## Zustandsmaschine ohne Nodes/Timer — die View (dialog_view.gd) füttert
## `tick(delta)` aus ihrem `_process` und spiegelt `sichtbar` auf
## `Label.visible_characters`. Dadurch ist der Ablauf headless testbar:
## Zeit wird IMMER hereingereicht, n Ticks à 1/Rate = exakt n Zeichen.
##
## Tempo kommt aus der BESTEHENDEN Konfiguration: GoobyVoice.RATE
## (~11 Silben/s, 1 Silbe pro Buchstabe im Gebrabbel-Plan) — die Buchstaben
## erscheinen damit synchron zum Pitch-Gebrabbel (Animal-Crossing-Gefühl).
##
## `start(text, sofort=true)` deckt Reduced-Motion / „Schnelle Dialoge“ ab:
## der Text steht dann ohne Ticks komplett da. `skip()` = Tap auf die Bubble
## (ganze Zeile sofort).

## Buchstaben pro Sekunde — bewusst dieselbe Rate wie das Gebrabbel.
const ZEICHEN_PRO_SEK := GoobyVoice.RATE
## Float-Krümel-Schutz: (1/RATE)*RATE muss verlässlich 1 Zeichen ergeben.
const EPSILON := 0.000001

var text := ""
var sichtbar := 0

var _akku := 0.0
var _laeuft := false


## Neue Zeile starten. `sofort` zeigt alles ohne Ticks (Reduced-Motion,
## „Schnelle Dialoge“, Typewriter aus).
func start(neuer_text: String, sofort := false) -> void:
	text = neuer_text
	_akku = 0.0
	if sofort or text.is_empty():
		sichtbar = text.length()
		_laeuft = false
		return
	sichtbar = 0
	_laeuft = true


## Zeit hereinreichen; gibt die aktuell sichtbare Zeichenzahl zurück.
func tick(delta: float) -> int:
	if not _laeuft:
		return sichtbar
	_akku += maxf(0.0, delta) * ZEICHEN_PRO_SEK
	sichtbar = clampi(int(floorf(_akku + EPSILON)), 0, text.length())
	if sichtbar >= text.length():
		_laeuft = false
	return sichtbar


## Tap: ganze Zeile sofort sichtbar.
func skip() -> void:
	sichtbar = text.length()
	_laeuft = false


func ist_fertig() -> bool:
	return sichtbar >= text.length()


func laeuft() -> bool:
	return _laeuft
