class_name FotoWerkzeuge
extends RefCounted
## W13C FOTOWERK (P1 Punkt 16) — PURER Werkzeug-Zustand des Fotomodus:
## POSE (vorhandene Rig-Clips), EMOTION (die 12 W12-FeelEmotions, gehalten
## über die öffentliche Rig-Override-API) und RAHMEN (FotoRahmen-Katalog).
## Headless testbar: Kataloge, Rotation, Clip-Auflösung mit Fallback
## (Battleship-Tomaten-Muster) und das Metadaten-Dict fürs Foto-Album.

## Posen = vorhandene W1b-Clips (rg gooby_rig.gd: sit/wave/hop/sleep/celebrate).
const POSEN: Array[Dictionary] = [
	{"id": "frei", "clip": "", "label_key": "foto.pose.frei"},
	{"id": "sitzen", "clip": "sit", "label_key": "foto.pose.sitzen"},
	{"id": "winken", "clip": "wave", "label_key": "foto.pose.winken"},
	{"id": "huepfen", "clip": "hop", "label_key": "foto.pose.huepfen"},
	{"id": "schlafen", "clip": "sleep", "label_key": "foto.pose.schlafen"},
	{"id": "jubeln", "clip": "celebrate", "label_key": "foto.pose.jubeln"},
]
const POSE_FREI := "frei"
const EMOTION_KEINE := "keine"
## Fehlt ein Wunsch-Clip in der Rig-Liste, winkt Gooby ersatzweise —
## dasselbe Fallback wie BoardEmotes.throw_clip (Tomate → wave).
const POSE_FALLBACK_CLIP := "wave"
## Selfie (C §3.9): Gooby hebt das Handy — phone_up, wave-Fallback.
const SELFIE_CLIP := "phone_up"

var pose_id := POSE_FREI
var emotion_id := EMOTION_KEINE
var rahmen_id := "kein"


static func pose_ids() -> Array[String]:
	var out: Array[String] = []
	for pose in POSEN:
		out.append(str(pose["id"]))
	return out


static func pose_def(id: String) -> Dictionary:
	for pose in POSEN:
		if str(pose["id"]) == id:
			return pose
	return {}


static func pose_label_key(id: String) -> String:
	return str(pose_def(id).get("label_key", ""))


## Wunsch-Clip gegen die tatsächliche Clip-Liste des Rigs auflösen:
## "frei" → "" (kein Eingriff), fehlender Clip → POSE_FALLBACK_CLIP.
static func pose_clip(id: String, verfuegbare_clips: Array) -> String:
	var clip := str(pose_def(id).get("clip", ""))
	if clip.is_empty():
		return ""
	if verfuegbare_clips.has(clip):
		return clip
	return POSE_FALLBACK_CLIP


## Selfie-Clip gegen die Rig-Liste auflösen (phone_up → wave-Fallback).
static func selfie_clip(verfuegbare_clips: Array) -> String:
	if verfuegbare_clips.has(SELFIE_CLIP):
		return SELFIE_CLIP
	return POSE_FALLBACK_CLIP


## "keine" + die 12 inszenierten W12-Emotionen (FeelEmotions ist die Quelle).
static func emotion_ids() -> Array[String]:
	var out: Array[String] = [EMOTION_KEINE]
	out.append_array(FeelEmotions.EMOTIONEN)
	return out


static func emotion_label_key(id: String) -> String:
	return "foto.emotion.%s" % id


func waehle_pose(id: String) -> void:
	if pose_ids().has(id):
		pose_id = id


func waehle_emotion(id: String) -> void:
	if emotion_ids().has(id):
		emotion_id = id


func waehle_rahmen(id: String) -> void:
	if FotoRahmen.ist_gueltig(id):
		rahmen_id = id


## Rotation (Werkzeug-Reihen durchtippen) — gibt die neue Auswahl zurück.
func naechste_pose() -> String:
	var liste := pose_ids()
	pose_id = liste[(liste.find(pose_id) + 1) % liste.size()]
	return pose_id


func naechste_emotion() -> String:
	var liste := emotion_ids()
	emotion_id = liste[(liste.find(emotion_id) + 1) % liste.size()]
	return emotion_id


func naechster_rahmen() -> String:
	rahmen_id = FotoRahmen.naechster(rahmen_id)
	return rahmen_id


func zuruecksetzen() -> void:
	pose_id = POSE_FREI
	emotion_id = EMOTION_KEINE
	rahmen_id = "kein"


## Metadaten fürs Album (nur Nicht-Defaults — Bestandsfotos bleiben schlank).
func als_meta() -> Dictionary:
	var meta: Dictionary = {}
	if pose_id != POSE_FREI:
		meta["pose"] = pose_id
	if emotion_id != EMOTION_KEINE:
		meta["emotion"] = emotion_id
	if rahmen_id != "kein":
		meta["rahmen"] = rahmen_id
	return meta
