# 4.6.0 backup / restore matrix

| Domain | Export | Restore | Notes |
|---|---:|---:|---|
| Device language/sound/haptics | optional | optional | Local only |
| App Group widgets/Live Activities | optional | optional | Entitlement-safe JSON |
| Server profiles | optional | optional | Never includes Keychain bearer tokens |
| Couple snapshot | optional | no | Evidence only; server remains source of truth |

Contract tests cover manifest JSON round-trip, legacy migration with/without
snapshot, empty/future schema rejection, restore-domain selection, successful
commit, and injected-failure rollback. Wrong-password/corrupt-envelope behavior
continues to fail closed in `BackupService.decodeEncrypted`.
