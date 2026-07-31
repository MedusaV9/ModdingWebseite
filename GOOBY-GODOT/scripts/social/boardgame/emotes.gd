class_name BoardEmotes
extends RefCounted
## Emote-Rad + Tomaten-Regel fürs Brettspiel (W3c VISIT) — PURE.
##
## 4 Emotes (Auftrag: tanzen/wütend/lachen/schlafen). dance nutzt seit W13C
## den ECHTEN dance-Clip (P1, F §1.4); angry/laugh bleiben auf vorhandene
## Clips + Emotionen gemappt — kommen weitere P-Clips, nur DIESE Tabelle
## anpassen. Der Tomaten-Tracker spiegelt die Server-Regel aus
## boardgames.js: max 1 Wurf pro Spieler pro Runde (Runde = abgeschlossene
## SHOT/SHOT_RESULT-Paare beider Spieler, exchanges/2).

const EMOTES: Array[Dictionary] = [
	{"id": "dance", "clip": "dance", "emotion": "ecstatic", "label_key": "board.emote.dance"},
	{"id": "angry", "clip": "hop", "emotion": "angry", "label_key": "board.emote.angry"},
	{"id": "laugh", "clip": "wave", "emotion": "happy", "label_key": "board.emote.laugh"},
	{"id": "sleep", "clip": "sleep", "emotion": "sleepy", "label_key": "board.emote.sleep"},
]

## Zusatz-Vokabular AUSSERHALB des 4er-Rads (W13C, FOTOWERK-Request):
## gültig für Relay/Validierung (RemoteGooby.play_emote), bekommt aber
## keinen Rad-Knopf — ids() bleibt bei den 4 Auftrags-Emotes. Das
## Besuchs-Selfie (SnapAGooby.RELAY_EMOTE) posiert damit den Peer.
## Clip wird phone_up, sobald CLIPS ihn ins Rig legt (heute wave).
const EXTRA_EMOTES: Array[Dictionary] = [
	{"id": "selfie", "clip": "wave", "emotion": "happy", "label_key": "board.emote.selfie"},
]

## Tomaten-Wurf: `tomato_throw` liegt seit W13C im GLB und wird von
## throw_clip() automatisch gewählt; wave bleibt Fallback für Alt-Rigs.
const TOMATO_THROW_CLIP := "tomato_throw"
const TOMATO_FALLBACK_CLIP := "wave"

## Splat rutscht 3–5 s langsam ab (Auftrag) — der Wert liegt in der Mitte.
const SPLAT_SLIDE_SEC := 4.0


static func ids() -> Array[String]:
	var out: Array[String] = []
	for emote in EMOTES:
		out.append(str(emote["id"]))
	return out


static func def(emote_id: String) -> Dictionary:
	for emote in EMOTES:
		if str(emote["id"]) == emote_id:
			return emote
	for emote in EXTRA_EMOTES:
		if str(emote["id"]) == emote_id:
			return emote
	return {}


static func is_valid(emote_id: String) -> bool:
	return not def(emote_id).is_empty()


static func clip_for(emote_id: String) -> String:
	return str(def(emote_id).get("clip", ""))


static func emotion_for(emote_id: String) -> String:
	return str(def(emote_id).get("emotion", "neutral"))


## Wurf-Clip gegen die tatsächliche Clip-Liste des Rigs auflösen.
static func throw_clip(available_clips: Array) -> String:
	if available_clips.has(TOMATO_THROW_CLIP):
		return TOMATO_THROW_CLIP
	return TOMATO_FALLBACK_CLIP


## Rad-Layout: Position von Emote `index` auf einem Kreis (oben beginnend,
## im Uhrzeigersinn) — pur, damit die UI-Geometrie testbar ist.
static func wheel_position(index: int, count: int, radius: float) -> Vector2:
	if count <= 0:
		return Vector2.ZERO
	var angle := -PI / 2.0 + TAU * float(index) / float(count)
	return Vector2(cos(angle), sin(angle)) * radius


## Client-Spiegel der Server-Tomaten-Regel (1×/Spieler/Runde). Der Server
## bleibt die Autorität (ERROR TOMATO_LIMIT) — der Tracker verhindert nur,
## dass die UI überhaupt einen aussichtslosen Wurf abschickt.
class TomatoTracker:
	extends RefCounted

	var _last_round := -1

	func can_throw(round_index: int) -> bool:
		return round_index != _last_round

	func mark_thrown(round_index: int) -> void:
		_last_round = round_index

	func reset() -> void:
		_last_round = -1
