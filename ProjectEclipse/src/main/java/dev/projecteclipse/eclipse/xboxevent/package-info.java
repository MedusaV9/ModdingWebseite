/**
 * Xbox-360 tutorial world event (P5-W9, plan §2.13): three bundled, pre-baked tutorial
 * worlds ({@code tu1}, {@code tu12}, {@code tu14}) installed lazily into datapack
 * dimensions, a dev-triggered 30-minute nostalgia event with a rift portal near spawn,
 * protected deaths (no item/life loss), voluntary exit via {@code /xboxleave} with
 * per-instance lockouts, a server-authoritative timer (bossbar fallback until P3-W11's
 * overlay), and a participation reward through P4's {@code TimedBuffApi}.
 *
 * <p>Ownership: this package, the {@code data/eclipse/dimension(_type)/xbox_*} JSONs, the
 * bundled world zips under {@code assets/eclipse/xboxworlds/}, and
 * {@code devtools/dev/DevXboxCommands} are P5-W9's; wiring for other planners is in
 * {@code docs/plans_v3/wiring/P5-W9.md}.</p>
 */
package dev.projecteclipse.eclipse.xboxevent;
