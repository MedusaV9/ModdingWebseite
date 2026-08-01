package dev.projecteclipse.eclipse.client.entity.fog;

import java.util.HashSet;
import java.util.Iterator;
import java.util.Set;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer;
import dev.projecteclipse.eclipse.entity.fog.StormHoundEntity;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import dev.projecteclipse.eclipse.veilfx.Wave4CombatFxRows;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.Entity;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import software.bernie.geckolib.cache.object.BakedGeoModel;

/**
 * Storm Hound renderer — defaulted asset triple for {@code storm_hound}, head tracking
 * ON ({@code head} bone), glowmask layer (the three {@code glow_spine} shards +
 * {@code glow_horn} antenna, the charge flank veins, the {@code mane_*} strand streaks,
 * eye dots and the charged whip-tail tips — the windup anim scales the spine bones and
 * flares the mane, so the glow visibly ramps before a lunge).
 * {@code withUprightDeath()} is deliberate even though the hound dies sideways:
 * the 30 t {@code death} anim rolls the root itself, and the vanilla tip-over would
 * double-rotate the corpse.
 *
 * <p><b>W4 A6 stagger tell:</b> while the hound's synced lunge-stagger flag is up (the
 * 40 t whiffed-lunge punish window), {@code preRender} keeps an {@code eclipse:rift_spark}
 * Quasar loop attached ({@code ensureAttached} — budget-refused frames retry free) and
 * fires the {@code wave4_stagger_arc} Photon one-shot ONCE on the rising edge (the
 * asset's 40 t timeline matches the window, and the entity attach lets Photon auto-clean
 * a mid-stagger death). Detach runs on the falling edge in {@code preRender}, with the
 * {@link #onClientTick} sweep as the off-screen/despawn backstop — a culled hound must
 * not keep sparking (the {@code HurtSparks} owner-manages-loop law).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
@OnlyIn(Dist.CLIENT)
public class StormHoundRenderer extends EclipseGeoRenderer<StormHoundEntity> {
    /** The shipped loop-crackle emitter (IDEA-02: the hound "stands sparking"). */
    private static final ResourceLocation RIFT_SPARK_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "rift_spark");
    /** Hound ids whose stagger FX are currently attached (render/main thread only). */
    private static final Set<Integer> STAGGER_ATTACHED = new HashSet<>();

    public StormHoundRenderer(EntityRendererProvider.Context context) {
        super(context, StormHoundEntity.GEO_ID, true);
        // WAVE5 (F-105 B) B4: the glowmask breathes with the storm interior — a 1:1
        // replacement of the stock withGlowmask() layer. EMISSIVE PASS ONLY: the W4 A6
        // stagger tell (preRender/tickStaggerTell below) is untouched.
        addRenderLayer(new FogGlowBreathLayer<>(this));
        withUprightDeath();
        this.shadowRadius = 0.5F;
    }

    @Override
    public void preRender(PoseStack poseStack, StormHoundEntity entity, BakedGeoModel model,
            MultiBufferSource bufferSource, VertexConsumer buffer, boolean isReRender, float partialTick,
            int packedLight, int packedOverlay, int colour) {
        super.preRender(poseStack, entity, model, bufferSource, buffer, isReRender, partialTick,
                packedLight, packedOverlay, colour);
        if (!isReRender) {
            tickStaggerTell(entity);
        }
    }

    /** Per-frame window keeper: edge-dispatch + loop ensure while staggered. */
    private static void tickStaggerTell(StormHoundEntity hound) {
        if (hound.isLungeStaggered() && hound.isAlive()) {
            if (STAGGER_ATTACHED.add(hound.getId())) {
                // Rising edge: the 40t Photon arc, once — through the registry gate
                // (reducedFx/WorldStage/budget law lives in the row leg, not here).
                PhotonFxRegistry.dispatchEntity(Wave4CombatFxRows.CUE_STAGGER_ARC, hound,
                        hound.getEyePosition(), 0.0F, 0.0F);
            }
            // Loop leg: keeping a live loop alive is free; a budget-refused spawn
            // simply retries next frame (the ensureAttached contract).
            QuasarSpawner.ensureAttached(RIFT_SPARK_EMITTER, hound, FxBudget.Channel.BURST);
        } else if (STAGGER_ATTACHED.remove(hound.getId())) {
            QuasarSpawner.removeAttached(RIFT_SPARK_EMITTER, hound);
        }
    }

    /** Backstop sweep: a hound that left the screen (or the world) mid-stagger still
     *  gets its loop detached — {@code preRender} only runs for visible entities. */
    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        if (STAGGER_ATTACHED.isEmpty()) {
            return;
        }
        ClientLevel level = Minecraft.getInstance().level;
        if (level == null) {
            STAGGER_ATTACHED.clear(); // QuasarSpawner prunes its own handles on unload.
            return;
        }
        Iterator<Integer> ids = STAGGER_ATTACHED.iterator();
        while (ids.hasNext()) {
            Entity entity = level.getEntity(ids.next());
            if (entity instanceof StormHoundEntity hound && hound.isAlive()
                    && hound.isLungeStaggered()) {
                continue;
            }
            if (entity != null) {
                QuasarSpawner.removeAttached(RIFT_SPARK_EMITTER, entity);
            }
            ids.remove();
        }
    }
}
