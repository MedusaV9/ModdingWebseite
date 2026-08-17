extends TestCase
## PURE-Tests fürs Emote-Rad + Tomaten-Regel (W3c VISIT): 4 Emotes, Mapping
## auf existierende W1b-Clips/-Emotionen, Rad-Geometrie und der Client-
## Spiegel des Server-Tomaten-Limits (1×/Spieler/Runde).

## W1b-M1-Clipliste (Handoff W1b-rig-api.md) + die 8 W13C-P1-Clips + die 2
## W15-Selfie-Clips — Emotes dürfen NUR auf diese Clips zeigen, sonst spielt
## das Rig nichts ab (test_w13c_clips pinnt die echte GLB-Liste auf exakt 21).
const RIG_CLIPS: Array[String] = [
	"idle",
	"idle_lookaround",
	"walk",
	"hop",
	"sit",
	"sleep",
	"wave",
	"squeeze_door",
	"brush_teeth",
	"build_hammer",
	"celebrate",
	"dance",
	"refuse",
	"ragdoll_flail",
	"grip_floor",
	"tomato_throw",
	"ceiling_cling",
	"idle_ear_flick",
	"idle_stretch",
	"phone_up",
	"phone_tap",
]
const RIG_EMOTIONS: Array[String] = [
	"neutral", "happy", "sad", "sleepy", "ecstatic", "angry", "scared", "dizzy"
]


func test_vier_emotes_mit_gueltigen_clips() -> void:
	var ids := BoardEmotes.ids()
	assert_eq(ids.size(), 4, "Auftrag: genau 4 Emotes")
	assert_eq(ids, ["dance", "angry", "laugh", "sleep"] as Array[String])
	for emote_id in ids:
		assert_true(BoardEmotes.is_valid(emote_id))
		assert_true(
			RIG_CLIPS.has(BoardEmotes.clip_for(emote_id)),
			"Clip %s existiert nicht im W1b-Rig" % BoardEmotes.clip_for(emote_id)
		)
		assert_true(
			RIG_EMOTIONS.has(BoardEmotes.emotion_for(emote_id)),
			"Emotion %s existiert nicht" % BoardEmotes.emotion_for(emote_id)
		)
		assert_true(
			str(BoardEmotes.def(emote_id).get("label_key", "")).begins_with("board.emote."),
			"Label-Key gehört in die board.*-Domain"
		)
	assert_false(BoardEmotes.is_valid("quatsch"))
	assert_eq(BoardEmotes.clip_for("quatsch"), "")
	assert_eq(BoardEmotes.emotion_for("quatsch"), "neutral")


func test_selfie_extra_emote_gueltig_aber_nicht_im_rad() -> void:
	# W13C FOTOWERK-Request: selfie ist Relay-Vokabular (SnapAGooby),
	# bekommt aber KEINEN Knopf im 4er-Rad.
	assert_false(BoardEmotes.ids().has("selfie"), "selfie bleibt aus dem Rad")
	assert_true(BoardEmotes.is_valid("selfie"), "selfie ist Relay-gültig")
	assert_true(
		RIG_CLIPS.has(BoardEmotes.clip_for("selfie")),
		"Selfie-Clip %s existiert nicht im Rig" % BoardEmotes.clip_for("selfie")
	)
	# W15/VOICE2: der W13C-Request ist eingelöst — selfie posiert mit phone_up.
	assert_eq(BoardEmotes.clip_for("selfie"), "phone_up", "selfie nutzt den echten Clip")
	assert_eq(BoardEmotes.emotion_for("selfie"), "happy")
	assert_eq(str(BoardEmotes.def("selfie").get("label_key", "")), "board.emote.selfie")


func test_tomaten_wurf_clip_fallback() -> void:
	assert_eq(
		BoardEmotes.throw_clip(RIG_CLIPS),
		"tomato_throw",
		"tomato_throw liegt seit W13C im Rig und gewinnt"
	)
	var alt_rig := RIG_CLIPS.duplicate()
	alt_rig.erase("tomato_throw")
	assert_eq(
		BoardEmotes.throw_clip(alt_rig),
		BoardEmotes.TOMATO_FALLBACK_CLIP,
		"Alt-Rig ohne tomato_throw → wave-Fallback"
	)


func test_splat_dauer_im_auftrag_fenster() -> void:
	assert_true(
		BoardEmotes.SPLAT_SLIDE_SEC >= 3.0 and BoardEmotes.SPLAT_SLIDE_SEC <= 5.0,
		"Splat rutscht 3–5 s ab"
	)


func test_rad_geometrie() -> void:
	assert_eq(BoardEmotes.wheel_position(0, 0, 100.0), Vector2.ZERO)
	var top := BoardEmotes.wheel_position(0, 4, 100.0)
	assert_almost(top.x, 0.0, 1e-4)
	assert_almost(top.y, -100.0, 1e-4, "Emote 0 sitzt OBEN")
	var right := BoardEmotes.wheel_position(1, 4, 100.0)
	assert_almost(right.x, 100.0, 1e-4, "im Uhrzeigersinn: Emote 1 rechts")
	assert_almost(right.y, 0.0, 1e-4)
	for index in 4:
		assert_almost(
			BoardEmotes.wheel_position(index, 4, 64.0).length(), 64.0, 1e-4, "alle auf dem Radius"
		)


func test_tomaten_tracker_eine_pro_runde() -> void:
	var tracker := BoardEmotes.TomatoTracker.new()
	assert_true(tracker.can_throw(0))
	tracker.mark_thrown(0)
	assert_false(tracker.can_throw(0), "2. Tomate in Runde 0 verboten")
	assert_true(tracker.can_throw(1), "neue Runde = neue Tomate")
	tracker.mark_thrown(1)
	assert_false(tracker.can_throw(1))
	tracker.reset()
	assert_true(tracker.can_throw(1), "reset (Server-Ablehnung) gibt den Wurf frei")
