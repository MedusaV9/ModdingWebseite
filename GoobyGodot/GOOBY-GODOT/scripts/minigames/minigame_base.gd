class_name MinigameBase
extends Node2D
## Basisklasse/Vertrag aller Minigames (Doc G; Konsument u. a. W3b GvZ).
## Node2D-Wurzel: 2D-Spiele zeichnen direkt (_draw), 3D-Spiele hängen ihre
## eigene 3D-Welt (SubViewport/Node3D) als Kind darunter — der Vertrag
## bleibt identisch.
## Lifecycle (der Host ruft GENAU in dieser Reihenfolge):
##   setup(ctx) → [Countdown] → start() → pause()/resume()* → end()
## Spiele überschreiben die Hooks und rufen super.…() auf; Punkte und
## Rundenende laufen ausschließlich über ctx.report_score()/ctx.report_end().
## end() ist das HOST-erzwungene Ende (Quit aus dem Pause-Overlay) — danach
## darf das Spiel nichts mehr melden.

var ctx: MinigameCtx
var running := false
var game_paused := false


## Einmalig vor dem Countdown; Szene ist bereits im SubViewport gemountet.
func setup(context: MinigameCtx) -> void:
	ctx = context


## Rundenstart nach dem 3-2-1-Countdown.
func start() -> void:
	running = true
	game_paused = false


func pause() -> void:
	if running:
		game_paused = true


func resume() -> void:
	if running:
		game_paused = false


## Host-erzwungenes Ende (Quit) — KEIN report_end() mehr senden.
func end() -> void:
	running = false
	game_paused = false


## True solange die Simulation ticken darf (Hilfe für _process-Guards).
func is_active() -> bool:
	return running and not game_paused
