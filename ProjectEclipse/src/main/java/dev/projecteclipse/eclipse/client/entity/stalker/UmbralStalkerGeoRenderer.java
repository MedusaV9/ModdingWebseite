package dev.projecteclipse.eclipse.client.entity.stalker;

import dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer;
import dev.projecteclipse.eclipse.entity.UmbralStalkerEntity;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Umbral Stalker GeckoLib renderer (MC2 conversion): defaulted asset triple for
 * {@code umbral_stalker} (64x64 canvas), head tracking ON and the {@code _glowmask.png}
 * layer.
 *
 * <p>The glowmask is what makes this mob readable at all — it hunts at light 0, where the
 * near-black hide is invisible. It burns the three {@code glow_spine} shards, the bone
 * keel that traces the SHOULDER HUMP, the shoulder-blade crests, the umbral flank cracks,
 * the two eye pinpricks, the inner mouth and the charged whip-tail tip. The two bone
 * tusks are deliberately left dark so the bite still reads against the shard light.</p>
 *
 * <p>{@code withUprightDeath()} pairs with the entity's scripted
 * {@link UmbralStalkerEntity#DEATH_ANIM_TICKS}t collapse — the held {@code death} anim
 * folds the stalker forward onto its chest itself, and the vanilla sideways flip would
 * double-rotate the corpse.</p>
 */
@OnlyIn(Dist.CLIENT)
public class UmbralStalkerGeoRenderer extends EclipseGeoRenderer<UmbralStalkerEntity> {
    public UmbralStalkerGeoRenderer(EntityRendererProvider.Context context) {
        super(context, UmbralStalkerEntity.GEO_ID, true);
        withGlowmask();
        withUprightDeath();
        this.shadowRadius = 0.6F; // Parity with the old MobRenderer registration.
    }
}
