class_name UiAnchors
extends RefCounted
## W14/UIKERN — zentrale Anker-Verwaltung für die exklusiven UI-Randzonen
## (User-Feedback: In-App-Banner überdeckte Goobys Text-Bubble). Wer eine
## Randfläche belegt, meldet sie hier an:
##
##   UiAnchors.reserve("top", banner_panel)     Notify-Banner (oben)
##   UiAnchors.reserve("bottom", bubble_kapsel) AcBubble/Gooby-Bubble (unten)
##   UiAnchors.release(zone, node)              beim Ausblenden/Freigeben
##
## Neuankömmlinge fragen die belegten Rects ab und weichen mit `dodge()`
## aus: Zone "bottom" rutscht ÜBER das belegte Rect (+8 px Luft), Zone
## "top" rutscht darunter — statt zu überlappen. Tote/unsichtbare Nodes
## werden automatisch ausgetragen; die Kern-Geometrie (`dodge`) ist pur
## und headless testbar (tests/unit/test_w14_uikern.gd).

const ZONE_TOP := "top"
const ZONE_BOTTOM := "bottom"
const GAP_PX := 8.0

static var _zonen: Dictionary = {}
## W21 (Playtest-Repro Baumodus): Beobachter der Belegungs-Wechsel —
## bereits SICHTBARE Ausweicher (Toast) positionieren sich neu, wenn NACH
## ihrem Einblenden eine Belegung dazukommt/verschwindet (der Tagesbonus-
## Toast stand sonst mitten auf der frisch geöffneten Bau-Lager-Karte).
static var _beobachter: Array[Callable] = []


## Ein Control als Belegung einer Zone anmelden (idempotent).
static func reserve(zone: String, node: Control) -> void:
	if node == null:
		return
	var liste: Array = _zonen.get(zone, [])
	_prune(liste)
	var neu := not liste.has(node)
	if neu:
		liste.append(node)
	_zonen[zone] = liste
	if neu:
		_melde_wechsel(zone)


## Belegung wieder freigeben (fehlende Einträge sind ok).
static func release(zone: String, node: Control) -> void:
	var liste: Array = _zonen.get(zone, [])
	var entfernt := liste.has(node)
	liste.erase(node)
	_prune(liste)
	_zonen[zone] = liste
	if entfernt:
		_melde_wechsel(zone)


## Beobachter für Belegungs-Wechsel anmelden (Callable(zone: String)).
static func beobachte(cb: Callable) -> void:
	if not _beobachter.has(cb):
		_beobachter.append(cb)


static func beobachter_abmelden(cb: Callable) -> void:
	_beobachter.erase(cb)


static func _melde_wechsel(zone: String) -> void:
	for i in range(_beobachter.size() - 1, -1, -1):
		var cb: Callable = _beobachter[i]
		if not cb.is_valid():
			_beobachter.remove_at(i)
			continue
		cb.call(zone)


## Gültige (lebende) Belegungen einer Zone — `except` wird ausgelassen.
static func occupants(zone: String, except: Control = null) -> Array[Control]:
	var liste: Array = _zonen.get(zone, [])
	_prune(liste)
	_zonen[zone] = liste
	var out: Array[Control] = []
	for eintrag: Variant in liste:
		var control := eintrag as Control
		if control != null and control != except:
			out.append(control)
	return out


## Global-Rects der SICHTBAREN Belegungen einer Zone (für dodge()).
static func occupied_rects(zone: String, except: Control = null) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for control in occupants(zone, except):
		if control.is_inside_tree() and control.is_visible_in_tree():
			out.append(control.get_global_rect())
	return out


## PURE: Wunsch-Rect gegen belegte Rects ausweichen lassen. Zone "bottom"
## schiebt das Rect ÜBER jeden Blocker (+gap), Zone "top" DARUNTER. Läuft
## iterativ, bis nichts mehr schneidet (max. eine Runde pro Blocker).
static func dodge(desired: Rect2, blockers: Array, zone: String, gap := GAP_PX) -> Rect2:
	var rect := desired
	for _runde in maxi(blockers.size(), 1):
		var moved := false
		for blocker: Variant in blockers:
			if not (blocker is Rect2):
				continue
			var hindernis: Rect2 = blocker
			if not rect.intersects(hindernis):
				continue
			if zone == ZONE_TOP:
				rect.position.y = hindernis.end.y + gap
			else:
				rect.position.y = hindernis.position.y - gap - rect.size.y
			moved = true
		if not moved:
			break
	return rect


## Tests: alle Zonen leeren.
static func reset_for_tests() -> void:
	_zonen = {}


static func _prune(liste: Array) -> void:
	for i in range(liste.size() - 1, -1, -1):
		# is_instance_valid ZUERST: `x is Object` wirft in Godot 4.4 auf
		# hart gefreiten Instanzen einen SCRIPT ERROR und brach _prune ab —
		# occupants() stolperte dann am as-Cast erneut (416 Log-Zeilen je
		# Voll-Lauf). is_instance_valid ist für genau diesen Fall gebaut:
		# false für freed UND für Nicht-Objekte, ohne Fehler-Log.
		if not is_instance_valid(liste[i]):
			liste.remove_at(i)
