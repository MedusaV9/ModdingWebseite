# scripts/dev — Dev-Werkzeuge (Owner: W4-P5 INFRA)

Nichts hier ist Spiel-Content; alles ist debug-only bzw. Werkzeug.

## perf_overlay.gd — Performance-Overlay (Plan §2.4-14)

Kapsel oben links mit FPS, Frame-Zeit, Draw Calls + Primitiven
(`RenderingServer.get_rendering_info`), Node-Anzahl und VRAM.

- **Einschalten:** 3-Finger-Tap irgendwo auf den Screen ODER das
  AppSettings-Debug-Setting `dev.perf_overlay` (der Tap schreibt das
  Setting zurück, der Zustand überlebt also Neustarts).
- **Release:** In Nicht-Debug-Builds (`OS.is_debug_build() == false`)
  entfernt sich der Node in `_ready()` selbst — unsichtbar, null Kosten.
- **Autoload:** Request `PerfOverlay` liegt in
  `handoffs/project-godot-requests.md` (Orchestrator trägt ein). Bis dahin
  funktioniert das Skript auch manuell instanziert.
- **Tests:** `tests/unit/test_perf_overlay.gd`.

## perf_probe.gd — Messfahrt Stadt/Räume

Lädt `city_scene` + alle 5 Raum-Szenen, wartet auf `ready_for_reveal` und
misst über 60 Frames via `perf_overlay.snapshot()`. Braucht einen echten
Renderer:

```bash
xvfb-run -a godot --path . --rendering-method gl_compatibility \
  --rendering-driver opengl3 --script res://scripts/dev/perf_probe.gd
```

### Messwerte-Baseline (W4, 2026-07-25, Godot 4.4.1, xvfb/llvmpipe, 1280×720)

| Szene | Draw Calls | Primitive (Tris) | Nodes | VRAM MB |
|---|---|---|---|---|
| Stadt (city_scene, freie Fahrt) | 39 | 11 390 | 414 | 42,2 |
| Raum bathroom | 45 | 11 076 | 128 | 34,2 |
| Raum bedroom | 35 | 20 152 | 144 | 42,5 |
| Raum garden | 32 | 10 240 | 146 | 34,1 |
| Raum kitchen | 65 | 12 218 | 152 | 34,2 |
| Raum living | 57 | 19 710 | 170 | 34,4 |

Einordnung (Doc A §7-Budgets: ≤ ~120 Draw Calls, ≤ ~150k Tris mobil):
alle Szenen liegen komfortabel im Budget. FPS/Frame-Zeit aus diesem Lauf
sind NICHT aussagekräftig (Software-Rasterizer llvmpipe, ~5–8 FPS) — auf
echter Hardware zählen nur die Draw-Call-/Tris-/VRAM-Spalten; FPS bitte
auf dem Gerät mit dem Overlay selbst ablesen.
