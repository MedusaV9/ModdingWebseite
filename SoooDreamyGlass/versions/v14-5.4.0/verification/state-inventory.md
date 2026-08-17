# 5.4.0 full-app state inventory

Each row is covered by the executable `PolishAudit` five-state contract. “Offline” may retain stale content with an honest banner; “failure” always offers one-tap retry.

| Surface | Loading | Empty | Content | Offline | Failure |
|---|---|---|---|---|---|
| Dashboard | skeleton cards | new-couple guidance | priority groups | cached cards + badge | explanation + retry |
| Chat | initial history load | first-message prompt | paged bubbles | queued outbox | retained history + retry |
| Play hub | session load | discovery cards | grouped games | cached sessions | retry card |
| Memories | collection load | creation prompt | filterable content | cached timeline | retry card |
| Settings | server probe | unavailable labels | controls | local settings remain | inline error |
| Replay | move load | honest no-record label | reducer state | retained moves | retry card |
| Tournament | season load | no-finished-games copy | complete table | retained table | retry card |
| Repair conversation | session load | start guidance | turn structure | reconnecting notice | safe exit/retry |
| Season calendar | door load | author template | locked/open doors | retained calendar | retry card |
| Personalization | profile load | defaults | palette/effects | local palette | validation error |
| Widgets | placeholder | no snapshot | fresh snapshot | stale indicator | honest unavailable |
| Handbook | markdown load | bundled fallback | anchored chapters | bundled copy | retry/close |

Motion audit: 0.18–0.45 seconds for intentional interactions; Reduce Motion keeps static state changes. Localization audit: all newly found hard-coded language branches removed. Device-only states remain explicitly unverified.
