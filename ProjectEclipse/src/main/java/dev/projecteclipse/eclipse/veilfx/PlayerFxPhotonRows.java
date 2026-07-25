package dev.projecteclipse.eclipse.veilfx;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * PH-SOCIAL's player-state Photon effects (IDEAS-player.md #3/#7/#8/#9/#10): the
 * heart-theft soul arc plus the shared fx-id constants for the four windowed entity
 * loops. Assets are authored programmatically — {@code tools/photon/gen_ph_social.py}
 * (fxlib) is the committed source for the nine {@code assets/eclipse/fx/*.fx} blobs.
 *
 * <p><b>Only the heart-theft cue registers a {@link PhotonFxRegistry} row.</b> The four
 * loops are entity-attached and per-entity (a ghost wisp per ghost, a mark per target…),
 * which the registry's position-anchored {@code ensureLoop} lane cannot express — they
 * are driven straight through {@link PhotonBridge#ensureAttachedFx} /
 * {@link PhotonBridge#stopAttachedFx} by their client-tick window controllers
 * (WINDOWED-only law, INTEGRATION.md §4):</p>
 * <ul>
 *   <li>{@link #REBIRTH_AURA_TIERS} — {@code client/skills/RebirthAuraFxClient}
 *       (Mode.LAYER in spirit: the server-side WITCH ring keeps running for everyone);</li>
 *   <li>{@link #CONTRACT_MARK} — {@code client/contracts/HunterMarkFxClient}
 *       (REPLACE with null Quasar leg: no pre-existing fallback, hunter-client-only);</li>
 *   <li>{@link #GHOST_WISP} — {@code client/GhostWispFxClient} (REPLACE, null leg: the
 *       vanilla glowing outline stays the guaranteed ghost signal);</li>
 *   <li>{@link #GLIDE_TRAIL_FX} — {@link GlideTrailFx} (REPLACE over the existing
 *       {@code eclipse:glide_trail} Quasar loop, which re-enters on Photon failure).</li>
 * </ul>
 *
 * <p>The heart-theft row is special-cased like the warden eye laser: its cue carries the
 * killer/victim entity ids in the payload's free {@code (a, b)} floats and needs
 * per-executor rotation + delays, so {@code FxPayloads.handleFxEvent} routes the cue to
 * {@link #heartTheftArc}, which resolves the SAME registered row (single source of truth
 * for the Photon leg's asset id). The row has a null Quasar leg by design: the
 * {@code HEART_BURST} drift payload {@code HeartTheftService.celebrate} already sends is
 * the unchanged photon-less baseline (Mode.LAYER — both play on Photon clients).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class PlayerFxPhotonRows {
    // ------------------------------------------------------------------ heart theft (#3)
    /** Victim leg 2: aimed comet + fat ara ribbon departing toward the killer. */
    public static final ResourceLocation THEFT_SOUL_LAUNCH = fx("theft_soul_launch");
    /** Killer leg: 16-wisp in-suck → HDR heart bloom + soft ring. */
    public static final ResourceLocation THEFT_SOUL_ARRIVE = fx("theft_soul_arrive");

    // ------------------------------------------------------------------ windowed loops
    /**
     * Prestige ribbon orbits, one file per tier (IDEAS-player #7: scale can't add
     * ribbons) — index = {@code min(rebirthCount, 3) - 1}. Ids differ per tier so
     * Photon's per-entity dedup never blocks a tier upgrade.
     */
    public static final ResourceLocation[] REBIRTH_AURA_TIERS = {
            fx("rebirth_aura_1"), fx("rebirth_aura_2"), fx("rebirth_aura_3")};
    /** Hunter's target-locked sonar pulse ring + head chevrons (IDEAS-player #8). */
    public static final ResourceLocation CONTRACT_MARK = fx("contract_mark");
    /** Cold spectral wisp loop on Limbo ghosts (IDEAS-player #9). */
    public static final ResourceLocation GHOST_WISP = fx("ghost_wisp");
    /** Wingtip ara-ribbon pair for the edge-glide (IDEAS-player #10, FORWARD AutoRotate). */
    public static final ResourceLocation GLIDE_TRAIL_FX = fx("glide_trail");

    /** Rise duration before the launch leg fires (baked into {@code theft_soul_rise}). */
    private static final int THEFT_RISE_TICKS = 20;
    /** Comet speed in blocks/tick ({@code theft_soul_launch}: startSpeed 1.5 along +Z). */
    private static final double THEFT_COMET_SPEED = 1.5D;
    /** Corpse chest height above the payload's feet position. */
    private static final double THEFT_CHEST_Y = 1.2D;
    /** Killer nearest-player fallback range when the entity id is not client-tracked. */
    private static final double KILLER_MATCH_RANGE_SQ = 24.0D * 24.0D;

    private PlayerFxPhotonRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // IDEAS-player #3 — the arc's row holds the RISE asset (the always-plays leg);
        // launch/arrive are the choreography's fixed companions. Null Quasar leg: the
        // ceremony's HEART_BURST payload is the baseline and keeps firing regardless.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_HEART_THEFT,
                fx("theft_soul_rise"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false));
    }

    /**
     * {@code FxPayloads.handleFxEvent} branch for {@code FxCues.CUE_HEART_THEFT} (client
     * main thread): the three-part soul-arc choreography.
     *
     * <p><b>Anchoring:</b> the victim died this very tick, and BOTH Photon and the bridge
     * sweep destroy executors on dead entities — so the two victim legs anchor at the
     * corpse position (exact-anchor block executors) instead of the victim entity; only
     * the killer leg is a true {@code EntityEffectExecutor} (it rides the killer if they
     * move during the ~1.5 s handoff, and the in-suck re-anchors the illusion).</p>
     *
     * <p><b>Handoff:</b> launch fires at +{@value #THEFT_RISE_TICKS}t rotated so its
     * local +Z axis points at the killer's chest; arrive is delayed by the rise plus the
     * comet's distance-scaled flight time (dist / {@value #THEFT_COMET_SPEED} blocks per
     * tick, clamped 4–12t per the doc) so the bloom lands as the ribbon does. Default
     * {@code allowMulti=false} everywhere = free double-send guard (one-shots; the 45 min
     * killer cooldown makes real stacking impossible).</p>
     *
     * @param pos the victim's corpse feet position (payload pos)
     * @param a   killer entity network id (payload {@code a})
     * @param b   victim entity network id (payload {@code b}, used only to exclude the
     *            corpse from the killer's nearest-player fallback)
     */
    public static void heartTheftArc(Vec3 pos, float a, float b) {
        PhotonFxRegistry.Row row = PhotonFxRegistry.row(FxCues.CUE_HEART_THEFT);
        ClientLevel level = Minecraft.getInstance().level;
        if (row == null || level == null) {
            return;
        }
        Vec3 chest = pos.add(0.0D, THEFT_CHEST_Y, 0.0D);
        // Leg 1 — the rise always plays (readable even when the killer is unresolvable).
        PhotonBridge.spawn(row.photonFx(), chest, PhotonBridge.SpawnOptions.DEFAULT);

        Entity killer = resolveKiller(level, (int) a, (int) b, pos);
        if (killer == null) {
            return; // no aim target: the mote rises and fades, the Quasar drift carries on
        }
        Vec3 aim = killer.getEyePosition().subtract(chest);
        double dist = aim.length();
        if (dist < 1.0E-3D) {
            return; // degenerate point-blank overlap: rise + drift already read
        }
        // Leg 2 — comet aimed by rotating the executor's local +Z onto `aim`. SpawnOptions
        // rotations go through JOML rotationXYZ (Rx·Ry·Rz), which maps +Z to
        // (sin ay, −sin ax·cos ay, cos ax·cos ay) — solve for the X/Y Euler pair:
        Vec3 dir = aim.scale(1.0D / dist);
        double xDeg = Math.toDegrees(Math.atan2(-dir.y, dir.z));
        double yDeg = Math.toDegrees(Math.atan2(dir.x, Math.sqrt(dir.y * dir.y + dir.z * dir.z)));
        PhotonBridge.spawn(THEFT_SOUL_LAUNCH, chest, PhotonBridge.SpawnOptions.DEFAULT
                .withRotationDeg(xDeg, yDeg, 0.0D)
                .withDelay(THEFT_RISE_TICKS));
        // Leg 3 — arrive on the killer, synced to the comet's flight time.
        int flightTicks = (int) Math.max(4L, Math.min(12L, Math.round(dist / THEFT_COMET_SPEED)));
        PhotonBridge.spawnOnEntity(THEFT_SOUL_ARRIVE, killer, PhotonBridge.AUTO_ROTATE_NONE,
                PhotonBridge.SpawnOptions.DEFAULT
                        .withOffset(0.0D, -0.4D, 0.0D)
                        .withDelay(THEFT_RISE_TICKS + flightTicks));
    }

    /**
     * The killer entity: by network id when client-tracked, else the nearest living
     * player to the corpse that is not the victim (the doc's fallback), else null.
     */
    @Nullable
    private static Entity resolveKiller(ClientLevel level, int killerId, int victimId, Vec3 pos) {
        Entity byId = level.getEntity(killerId);
        if (byId != null && byId.isAlive()) {
            return byId;
        }
        Player best = null;
        double bestDistSq = KILLER_MATCH_RANGE_SQ;
        for (Player player : level.players()) {
            if (player.getId() == victimId || !player.isAlive()) {
                continue;
            }
            double distSq = player.distanceToSqr(pos);
            if (distSq < bestDistSq) {
                bestDistSq = distSq;
                best = player;
            }
        }
        return best;
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
