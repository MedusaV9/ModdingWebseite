class_name NetErrorText
extends RefCounted
## Einheitliche deutsche Fehlertexte für Netz-Fehlercodes (W4-P4 POLISH,
## Strings-Domain `sys.err.*`): bekannte Codes bekommen einen knuffigen
## Klartext, unbekannte fallen auf den domänenspezifischen
## „… fehlgeschlagen: {code}“-String zurück.

const CODE_KEYS := {
	"OFFLINE": "sys.err.offline",
	"TIMEOUT": "sys.err.timeout",
	"RATE_LIMIT": "sys.err.rate_limit",
}


## Text zu einem Fehlercode. `fallback_key` MUSS ein {code}-Platzhalter-String
## sein (z. B. "social.visit.request_failed").
static func for_code(code: String, fallback_key: String) -> String:
	if CODE_KEYS.has(code):
		return I18nService.t(str(CODE_KEYS[code]))
	return I18nService.t(fallback_key, {"code": code})
