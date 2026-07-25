package dev.projecteclipse.eclipse.veilfx;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * PH-MOBS' {@link PhotonFxRegistry} row registrar ({@link PhotonFxRows} reference
 * pattern) — the cue-driven one-shots of the {@code IDEAS-mobs.md} batch (#1, #4 hound
 * half, #5 pop). All rows are {@code Mode.LAYER} garnish with a {@code null} Quasar leg:
 * every trigger point already ships a complete vanilla/Quasar visual (intro card,
 * REVERSE_PORTAL blink pairs, glow-spine + sonic-charge windup tell) that stays
 * bit-identical on photon-less clients.
 *
 * <p>The entity-attached LOOPS of the batch (#6 bolt ribbon, #7 petal orbit, #8 dread
 * aura, #9 gaze beam, #10 wanderer shroud) are deliberately NOT rows here — they carry
 * no wire traffic at all and live in {@link PhotonMobFx}'s attach table instead
 * (IDEAS-mobs §0.2 loop tier).</p>
 *
 * <p>Custom {@code PhotonLeg}s (INTEGRATION §3.5 — grows only when a cue needs it):</p>
 * <ul>
 *   <li><b>shockwave</b> — parks the spawn behind {@code setDelay(
 *       BossIntroOverlay.pendingLockDelayTicks())} so the ground ring erupts on the intro
 *       card's DANGER→TEXT lock flash (deterministic decode formula; delay 0 without a
 *       card). {@code allowMulti} stays false: one ring per intro per arena pos.</li>
 *   <li><b>glitch pop</b> — forces {@code allowMulti=true}: origin + exit of a short
 *       blink can land in the SAME BlockPos and packs blink on independent clocks.</li>
 *   <li><b>hound windup/dash</b> — entity-lane cues; when the hound is tracked the FX
 *       attaches ({@code NONE} at the paws for the collapsing spiral, {@code FORWARD}
 *       so the dash ara ribbon lays along the locked line), else the payload pos anchors
 *       it. Default {@code allowMulti=false} per entity: the 160t cooldown guarantees no
 *       overlap and dedup absorbs duplicate cues.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class MobPhotonFxRows {
    /** Anchor drop from the hound's eye to its paws (0.9×1.1 hitbox — spiral base). */
    private static final Vec3 HOUND_FEET_OFFSET = new Vec3(0.0D, -0.9D, 0.0D);
    /** Anchor drop from the hound's eye to mid-body (dash ribbon height). */
    private static final Vec3 HOUND_BODY_OFFSET = new Vec3(0.0D, -0.4D, 0.0D);

    private MobPhotonFxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // IDEAS-mobs #1 — boss-intro name-lock ground shockwave (delay-synced leg).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_BOSS_INTRO_SHOCKWAVE,
                fx("boss_intro_shockwave"),
                null,
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> PhotonBridge.spawn(photonFx, pos,
                        PhotonBridge.SpawnOptions.DEFAULT.withDelay(
                                dev.projecteclipse.eclipse.client.hud.BossIntroOverlay
                                        .pendingLockDelayTicks()))));
        // IDEAS-mobs #5 — glitch_pop datamosh burst (allowMulti leg).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_GLITCH_POP,
                fx("glitch_pop"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> PhotonBridge.spawn(photonFx, pos,
                        PhotonBridge.SpawnOptions.DEFAULT.withAllowMulti(true))));
        // IDEAS-mobs #4 — hound charge spiral (entity lane, rides the rooted hound).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_HOUND_WINDUP,
                fx("hound_lunge_windup"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> entity != null
                        ? PhotonBridge.spawnOnEntity(photonFx, entity,
                                PhotonBridge.AUTO_ROTATE_NONE, HOUND_FEET_OFFSET)
                        : PhotonBridge.spawn(photonFx, pos)));
        // IDEAS-mobs #4 — hound dash ribbon (entity lane, FORWARD along the dash line).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_HOUND_DASH,
                fx("hound_dash_trail"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> entity != null
                        ? PhotonBridge.spawnOnEntity(photonFx, entity,
                                PhotonBridge.AUTO_ROTATE_FORWARD, HOUND_BODY_OFFSET)
                        : PhotonBridge.spawn(photonFx, pos)));
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
