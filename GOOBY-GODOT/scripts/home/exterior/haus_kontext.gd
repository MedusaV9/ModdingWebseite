class_name HausKontext
extends Node
## Bündelt die HAUS-SICHT-Anbauten eines Raums — GartenHaus (das eigene
## Haus im Garten), DachInnen (Balken/Dachschräge) und FlurBlick (Nischen
## hinter Türen) — und schaltet sie mit dem Baumodus: Balken/Dachschräge
## würden die Draufsicht verstellen, die Flur-Nischen ragen außen aus der
## Fassade — beides schläft im Baumodus (draußen übernimmt die Vorstadt-
## Kulisse). Das Garten-Haus bleibt sichtbar: es IST die Kulisse des
## Gartens. Eigener Node statt RoomBase-Methoden, damit room_base.gd
## unter dem gdlint-Zeilendeckel bleibt.

var _dach: DachInnen
var _blick: FlurBlick


## An einen RoomBase-Raum hängen (alle Teil-Helfer sind idempotent und
## liefern für fremde Raumtypen null).
static func attach_to(room: Node) -> HausKontext:
	var kontext := HausKontext.new()
	kontext.name = "HausKontext"
	var stunde := 12.0
	if room.has_method("stunde_aktuell"):
		stunde = float(room.call("stunde_aktuell"))
	var garten_haus := GartenHaus.attach_to(room)
	if garten_haus != null:
		garten_haus.stunde_anwenden(stunde)
	var leben := GartenLeben.attach_to(room)
	if leben != null:
		leben.stunde_anwenden(stunde)
	kontext._dach = DachInnen.attach_to(room)
	kontext._blick = FlurBlick.attach_to(room)
	room.add_child(kontext)
	if room.has_signal("build_mode_toggled"):
		room.connect("build_mode_toggled", kontext._on_baumodus)
	return kontext


func _on_baumodus(aktiv: bool) -> void:
	if _dach != null:
		_dach.visible = not aktiv
	if _blick != null:
		_blick.visible = not aktiv
