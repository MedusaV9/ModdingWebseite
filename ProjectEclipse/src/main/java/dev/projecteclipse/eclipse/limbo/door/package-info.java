/**
 * The limbo ghost ship's Respawn Door (P6-W3, plans_v3 §2.5) — the imposing 3×5 double
 * door in the sterncastle bulkhead that the death/respawn flow walks revived players
 * through, plus the ship's own version stamp.
 *
 * <ul>
 *   <li>{@link dev.projecteclipse.eclipse.limbo.door.DoorRegistry} — self-contained
 *       DeferredRegisters (2 blocks, 1 BE type, 1 admin BlockItem). Needs the single
 *       wiring line {@code DoorRegistry.register(modEventBus)} in {@code EclipseMod}
 *       (see {@code docs/plans_v3/wiring/P6-W3_wiring.md}); everything else in the
 *       package is {@code @EventBusSubscriber}-annotated or guarded by
 *       {@code DoorRegistry.isBound()} so the mod boots green either way.</li>
 *   <li>{@link dev.projecteclipse.eclipse.limbo.door.RespawnDoorBlock} (controller, at
 *       the multiblock's bottom-center cell) +
 *       {@link dev.projecteclipse.eclipse.limbo.door.RespawnDoorFillerBlock} (the other
 *       14 cells) — both invisible/unbreakable; the GeckoLib model on
 *       {@link dev.projecteclipse.eclipse.limbo.door.RespawnDoorBlockEntity} draws
 *       everything.</li>
 *   <li>{@link dev.projecteclipse.eclipse.limbo.door.RespawnDoorApi} — the frozen P3/P4
 *       server API (global {@link dev.projecteclipse.eclipse.limbo.door.DoorState},
 *       per-player open cues, respawn/cinematic positions) and the idempotent multiblock
 *       placement + FX-anchor publishing driven from
 *       {@code GhostShipBuilder.onServerStarted}.</li>
 *   <li>{@link dev.projecteclipse.eclipse.limbo.door.S2CDoorCuePayload} /
 *       {@link dev.projecteclipse.eclipse.limbo.door.DoorPayloads} — the tiny
 *       {@code p6w3} payload group for per-player door pose cues (the global state syncs
 *       via plain BE data, no payload needed).</li>
 *   <li>{@link dev.projecteclipse.eclipse.limbo.door.ShipVersionData} — the ghost ship's
 *       build-version SavedData ({@code GhostShipBuilder} migration guard, sanctum
 *       pattern).</li>
 * </ul>
 */
package dev.projecteclipse.eclipse.limbo.door;
