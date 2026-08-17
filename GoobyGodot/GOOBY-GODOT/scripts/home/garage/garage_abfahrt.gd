class_name GarageAbfahrt
extends RefCounted
## „Freie Fahrt“-Anbindung der Garage (W13C, Doc D §7): Ist eine Garage
## gebaut UND hängt ihr Prop gerade sichtbar im Baum (Garten-Raum), rollt
## das Tor auf und das Auto fährt raus, BEVOR der normale Stadt-Übergang
## startet. Ohne Garage/Prop ist der Aufruf ein No-Op — deshalb bleibt der
## Hook am Fahrt-Einstieg (home_entry._on_hud_action) bei einer Zeile.


## Awaitbar; blockt höchstens die kurze Abfahrt-Sequenz lang.
static func vielleicht_abspielen(kontext: Node, gs: Object) -> void:
	if gs == null or kontext == null or not kontext.is_inside_tree():
		return
	if not GarageLogic.gebaut(gs):
		return
	var prop := kontext.get_tree().get_first_node_in_group(GarageProp.GRUPPE) as GarageProp
	if prop == null or not prop.is_inside_tree() or prop.abfahrt_laeuft():
		return
	await prop.abfahrt_spielen(_reduziert(kontext))


static func _reduziert(kontext: Node) -> bool:
	var settings := kontext.get_node_or_null("/root/AppSettings")
	return settings != null and bool(settings.call("is_reduced_motion"))
