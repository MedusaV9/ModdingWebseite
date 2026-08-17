# 4.1.0 polish rubric — About / Settings

Touched surface: About sheet reached from Settings.

| Dimension | Score | Evidence |
|---|---:|---|
| R1 Visual consistency | 9 | Existing Theme colors, rounded typography, `LayoutMetrics`, and `glassCard` only. |
| R2 Motion | 9 | No new blocking motion; existing sheet transition honors system settings. |
| R3 Haptics & sound | 8 | Informational surface intentionally introduces no feedback noise. |
| R4 State completeness | 9 | Server version resolves to a localized unavailable state without a spinner. |
| R5 Localization | 10 | Every new label uses `L10n`; all six DE/EN tables pass parity checks. |
| R6 Accessibility | 9 | Credit is a header; logo is hidden; rows combine into coherent VoiceOver elements. |
| R7 Performance | 9 | One bounded health request; no per-frame allocation or unbounded list. |
| R8 Resilience | 9 | Missing server/API and failed health requests degrade to an honest label. |
| R9 Honesty | 10 | App/build/server versions and unsigned/sideload limits are stated precisely. |
| R10 Coherence | 9 | Credit appears in-app, README, patchnotes, manual, and release archive. |

Gate: PASS — every score is at least 8; R5 and R9 are 10.
