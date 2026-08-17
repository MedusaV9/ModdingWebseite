class_name RQuestWarte
extends RefCounted
## Warte-Quest-Helfer (RW-3, C4): Restzeit-Rechnung/-Format (PURE) plus die
## Notification-/Live-Activity-Verdrahtung eines wartenden Quest-Laufs.
## Grundregeln: Warten ist NIE blockierend (nur der eine Lauf steht),
## jede Warte-Quest zeigt eine Alternativbeschäftigung (I18n-Key
## `rquest.warte.alternative_<n>`), und die Benachrichtigung ist IMMER
## positiv formuliert (H6 — kein Schuld-FOMO).

const NOTIFY_PREFIX := "rquest_"
const ALTERNATIVEN := 4


## Restzeit eines wartenden Laufs in ms (0 = fällig/kein Warten).
static func restzeit_ms(lauf: Dictionary, now_ms: int) -> int:
	if str(lauf.get("status", "")) != RQuestSlices.STATUS_WARTEND:
		return 0
	return maxi(0, int(lauf.get("bereitAt", 0)) - now_ms)


## Restzeit menschenfreundlich: "2 Std 05 Min" / "12 Min" / "gleich!".
static func restzeit_text(rest_ms: int) -> String:
	var minuten := int(ceilf(float(rest_ms) / 60000.0))
	if minuten <= 0:
		return I18nService.t("rquest.warte.gleich")
	if minuten < 60:
		return I18nService.t("rquest.warte.minuten", {"m": minuten})
	return I18nService.t("rquest.warte.stunden", {"h": minuten / 60, "m": "%02d" % (minuten % 60)})


## Deterministische Alternativbeschäftigung zu einer Quest (aus der Id
## geseedet, damit die Karte im Quest-Log stabil bleibt).
static func alternative_text(quest_id: String) -> String:
	var slot := absi(quest_id.hash()) % ALTERNATIVEN + 1
	return I18nService.t("rquest.warte.alternative_%d" % slot)


## Beim Start eines Warte-Ziels: lokale Notification (Fertig-Zeitpunkt)
## planen und — wenn das Ziel `liveActivity` trägt — die Live Activity
## starten. `titel` = lokalisierter Quest-Titel.
static func warte_gestartet(
	quest_id: String, ziel: Dictionary, lauf: Dictionary, titel: String
) -> void:
	var bereit_at := int(lauf.get("bereitAt", 0))
	if bereit_at <= 0:
		return
	NotifyStub.schedule_local(
		NOTIFY_PREFIX + quest_id,
		titel,
		I18nService.t("rquest.warte.notify_fertig", {"quest": titel}),
		bereit_at
	)
	if bool(ziel.get("liveActivity", false)):
		RanchLiveActivity.start(
			quest_id, titel, I18nService.t("rquest.warte.activity_laeuft"), bereit_at
		)


## Beim Auflösen des Warte-Ziels (tick meldet die Quest in `fertig`):
## Live Activity beenden; die Notification feuert von selbst.
static func warte_fertig(quest_id: String) -> void:
	RanchLiveActivity.beende(quest_id)


## Beim Abbrechen/Abgeben einer Quest: alles aufräumen.
static func aufraeumen(quest_id: String) -> void:
	NotifyStub.cancel_local(NOTIFY_PREFIX + quest_id)
	RanchLiveActivity.beende(quest_id)
