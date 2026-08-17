# 6.0.0 final coherence rubric

| Dimension | Score | Evidence |
|---|---:|---|
| R1 visual consistency | 9 | Migration uses existing glass cards, type scale, buttons, palette, and settings navigation. |
| R2 motion | 9 | No blocking animation; progress is state-driven and honors the 5.4 motion budget. |
| R3 haptics & sound | 9 | Success/warning feedback only at export, unlock, import, and rejection boundaries. |
| R4 state completeness | 10 | Export, share, destination guidance, file read, locked/review, confirmation, success, and failure states. |
| R5 DE+EN | 10 | All assistant, warning, What’s New, patch-note, and manual text ships in paired localization. |
| R6 accessibility | 9 | Labeled system icons, semantic controls, selectable code, no color-only status. |
| R7 performance | 9 | Logical JSON bounded to 16 MB; media stays out of the mobile envelope. |
| R8 resilience | 10 | Digest/schema/freshness gates, no token migration, re-pair flow, two-server E2E test. |
| R9 honesty | 10 | Media admin-copy, unsigned IPA, entitlement, and device-test limits are explicit. |
| R10 coherence | 10 | API, server, app, Settings, What’s New, DE/EN manuals, and 15-version archive align. |

Gate: PASS — no category below 8; average 9.5.
