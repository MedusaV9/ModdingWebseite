# 4.4.0 state audit

| Flow | Loading | Content | Empty | Offline | Failure / retry |
|---|---:|---:|---:|---:|---:|
| Replay | yes | yes | yes | yes | yes |
| Tournament | yes | yes | yes | yes | yes |
| Chat outbox | persisted | optimistic | no drafts | FIFO held | reconnect retry |
| App Lock | auth task | unlocked app | n/a | local | retry + Settings |

All new copy has DE/EN parity. Existing content wins over transient errors, then
loading, explicit failure, offline, and finally true empty. No state uses a
silent spinner or destructive automatic recovery.
