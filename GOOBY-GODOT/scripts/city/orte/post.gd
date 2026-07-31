class_name OrtPost
extends OrtScene
## Post (Doc E §2.3, Doc C §3.7): Schalter-Halle mit Frau Zettel hinter der
## Scheibe, Paketberg im Hintergrund. FERTIG-1: statt des gestrichenen
## Multiplayer-Versand-Hooks gibt es hier das echte TAGESPAKET (PostLogic).
## W13B: daneben steht jetzt der echte BRIEF-Schalter (Post/Mail-Multiplayer,
## MailSheet) — Briefe + Fotos + Item-Geschenke an Freunde, offline-first
## über die NetMail-Outbox. Das Tagespaket (PostSheet/PostLogic) bleibt
## unverändert.

const INNEN := "res://assets/city/innen"
const MOEBEL := "res://assets/furniture"


func _baue_innenraum() -> void:
	_prop("%s/kitchencounter_straight.gltf" % INNEN, Vector3(-0.4, 0.0, -1.3), 90.0, 0.95)
	_prop("%s/kitchencounter_sink.gltf" % INNEN, Vector3(1.6, 0.0, -1.3), 90.0, 0.95)
	_prop("%s/bookcaseClosedWide.glb" % MOEBEL, Vector3(-4.4, 0.0, -3.6), 0.0, 1.3)
	_prop("%s/bookcaseClosedWide.glb" % MOEBEL, Vector3(4.4, 0.0, -3.6), 0.0, 1.3)
	_prop("%s/deko/box_A.gltf" % MOEBEL, Vector3(3.2, 0.0, -0.4), 14.0, 1.5)
	_prop("%s/deko/box_B.gltf" % MOEBEL, Vector3(3.6, 0.0, 0.9), -9.0, 1.5)
	_prop("%s/deko/box_A.gltf" % MOEBEL, Vector3(-3.5, 0.0, 0.7), 27.0, 1.5)
	_prop("%s/coatRackStanding.glb" % MOEBEL, Vector3(-5.6, 0.0, -0.6), 0.0, 1.1)
	_prop("%s/pottedPlant.glb" % MOEBEL, Vector3(5.6, 0.0, -0.4), 0.0, 1.1)


func _dialog_pfad() -> String:
	return "res://scripts/city/data/dialoge/post.json"


func _npc_konfig() -> Dictionary:
	return {"tint": Color("#FFD166"), "emotion": "happy", "pos": Vector3(-0.4, 0.0, -2.4)}


## Post hat ein eigenes Schalter-UI: Tagespaket + Postkarten-Archiv (PostSheet,
## unverändert) und daneben der neue Brief-Schalter (W13B).
func oeffne_laden() -> void:
	var inhalt := VBoxContainer.new()
	inhalt.add_theme_constant_override("separation", 12)
	var paket := PostSheet.new()
	paket.gs = game_state()
	paket.schalter_gewaehlt.connect(_on_schalter)
	inhalt.add_child(paket)
	inhalt.add_child(_baue_briefe_schalter())
	zeige_sheet(I18nService.t("city.post.sheet_titel"), inhalt)


func _on_schalter(_schalter: String) -> void:
	if rig != null:
		rig.play_clip("wave")


## Brief-Schalter-Karte: Knopf zum Briefkasten (mit Ungelesen-Badge) plus
## Offline-/Outbox-Hinweis. Ohne /root/Net (z. B. Tests) bleibt der Knopf
## stehen und meldet ehrlich den Offline-Zustand.
func _baue_briefe_schalter() -> Control:
	var wrapper := VBoxContainer.new()
	wrapper.name = "BriefeSchalter"
	var karte := CitySheetBausteine.karte(wrapper)
	CitySheetBausteine.label(karte, I18nService.t("mail.schalter.titel"), "HeadlineLabel")
	CitySheetBausteine.label(karte, I18nService.t("mail.schalter.text"), "CaptionLabel")
	var status := _briefe_status_text()
	if not status.is_empty():
		CitySheetBausteine.label(karte, status, "CaptionLabel")
	var knopf := Button.new()
	knopf.name = "BriefeOeffnen"
	knopf.theme_type_variation = "AccentButton"
	knopf.text = _briefe_knopf_text()
	knopf.pressed.connect(_on_briefe_oeffnen)
	karte.add_child(knopf)
	return wrapper


func _briefe_knopf_text() -> String:
	var text := I18nService.t("mail.schalter.offen")
	var net := get_node_or_null("/root/Net")
	if net == null:
		return text
	var service := NetMail.attach(net)
	if service != null and service.unread > 0:
		text += " · " + I18nService.t("mail.schalter.neu", {"n": service.unread})
	return text


## Offline-Chip + Outbox-Hinweis („wird zugestellt, sobald du online bist“).
func _briefe_status_text() -> String:
	var net := get_node_or_null("/root/Net")
	if net == null:
		return I18nService.t("mail.schalter.offline")
	var service := NetMail.attach(net)
	var teile := PackedStringArray()
	if not (net.has_method("is_online") and net.is_online()):
		teile.append(I18nService.t("mail.schalter.offline"))
	if service != null and service.outbox_count() > 0:
		teile.append(I18nService.t("mail.schalter.outbox", {"n": service.outbox_count()}))
	return " · ".join(teile)


func _on_briefe_oeffnen() -> void:
	if rig != null:
		rig.play_clip("wave")
	var sheet := MailSheet.new()
	sheet.setup(get_node_or_null("/root/Net"), game_state())
	sheet.toast_requested.connect(zeige_toast)
	_ui.add_child(sheet)
