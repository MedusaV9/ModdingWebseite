package dev.projecteclipse.eclipse.drama;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import dev.projecteclipse.eclipse.network.S2CAnnouncePayload;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.timeline.AnnouncementService;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.level.saveddata.SavedData;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingDeathEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * "First Blood" (FIX-5, IDEAS-A #2): the very first player death of the event makes the
 * whole world flinch once — every online player gets a light 0.8&nbsp;s camera shake
 * ({@link S2CShakePayload}), one deep bell toll, and the anonymous typewriter announcement
 * "Someone has fallen." (no name: anonymity holds, which is exactly what makes voice chat
 * erupt). One-shot: the latch persists in its own tiny {@link SavedData}
 * ({@code data/eclipse_first_blood.dat}) so a server restart can never replay the beat.
 *
 * <p>Runs at {@link EventPriority#LOW} on {@code LivingDeathEvent} — after
 * {@code lives.LifecycleEvents} (NORMAL) has processed the death economy, alongside
 * {@code lives.DeathFlowHooks}; this class only observes that a player died and adds the
 * theater. Deliberately does NOT touch {@code EclipseWorldState} — the latch lives in its
 * own adjacent SavedData file.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class FirstBloodService {
    /** Light global flinch — well under the Ferryman gunwale-slam strengths (horror-calm). */
    private static final float SHAKE_STRENGTH = 0.35F;
    /** 0.8 s decay (IDEAS-A #2). */
    private static final int SHAKE_TICKS = 16;
    /** Deep bell: pitch floor 0.5 reads as a funeral toll rather than a village bell. */
    private static final float BELL_VOLUME = 0.8F;
    private static final float BELL_PITCH = 0.5F;

    private FirstBloodService() {}

    /** LOW: after the death economy (NORMAL) — this beat only observes that a player died. */
    @SubscribeEvent(priority = EventPriority.LOW)
    static void onLivingDeath(LivingDeathEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer victim)) {
            return;
        }
        MinecraftServer server = victim.server;
        FirstBloodState state = FirstBloodState.get(server);
        if (state.isFired()) {
            return;
        }
        state.markFired();

        // Anonymous typewriter line + bossbar sweep; empty subtitle = "type the title".
        AnnouncementService.announce(server, "announce.eclipse.first_blood.title", "",
                S2CAnnouncePayload.STYLE_BOSS);
        PacketDistributor.sendToAllPlayers(S2CShakePayload.shake(SHAKE_STRENGTH, SHAKE_TICKS));
        for (ServerPlayer online : server.getPlayerList().getPlayers()) {
            // One toll at each player's own position (the LifecycleEvents death-cue pattern);
            // it layers under the existing global thunder rather than replacing it.
            online.playNotifySound(SoundEvents.BELL_RESONATE, SoundSource.AMBIENT,
                    BELL_VOLUME, BELL_PITCH);
        }
        EclipseMod.LOGGER.info("First Blood fired: the world flinched for {}'s death (anonymous)",
                victim.getScoreboardName());
    }

    /**
     * One boolean of persistent state, stored next to {@code EclipseWorldState} in overworld
     * data storage (its own file — the frozen world-state schema stays untouched).
     */
    static final class FirstBloodState extends SavedData {
        static final String DATA_ID = "eclipse_first_blood";
        private static final String TAG_FIRED = "fired";

        private boolean fired;

        FirstBloodState() {}

        static FirstBloodState get(MinecraftServer server) {
            return EclipseSavedData.getOverworld(server, DATA_ID,
                    new SavedData.Factory<>(FirstBloodState::new, FirstBloodState::load));
        }

        static FirstBloodState load(CompoundTag tag, HolderLookup.Provider registries) {
            FirstBloodState state = new FirstBloodState();
            state.fired = tag.getBoolean(TAG_FIRED);
            return state;
        }

        @Override
        public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
            tag.putBoolean(TAG_FIRED, fired);
            return tag;
        }

        boolean isFired() {
            return fired;
        }

        void markFired() {
            fired = true;
            setDirty();
        }
    }
}
