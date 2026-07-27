package dev.projecteclipse.eclipse.woah.resonance.client;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.woah.resonance.ResonanceTones;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.client.resources.sounds.AbstractTickableSoundInstance;
import net.minecraft.client.resources.sounds.SoundInstance;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * WOAH-04 §4.2 — the distance-volume choir: one positional loop per NEAR crystal,
 * pitched from the shared {@link ResonanceTones} table, volume driven per tick by a
 * manual distance curve. Derived from the verified {@code client/sound/SanctumHum}
 * pattern with the three planned deltas:
 *
 * <ul>
 *   <li><b>Attenuation NONE + manual curve</b> — vanilla rolloff would end a ≤1.0
 *       volume at ~16 blocks; instead {@code vol = 0.65 × clamp(1 − (dist − 4)/44,
 *       0, 1)^1.5} runs in {@code tick()} with the SanctumHum 0.05 per-tick lerp.
 *       3D panning stays (relative = false).</li>
 *   <li><b>Voice budget + hysteresis</b> — engage &lt; {@value #ENGAGE_DISTANCE},
 *       release &gt; {@value #RELEASE_DISTANCE}, max {@value #MAX_VOICES} concurrent
 *       voices (nearest first; the quietest is faded and stopped when a closer
 *       crystal needs the slot). Valley center = 4 voices = the chord bed, wanted.</li>
 *   <li><b>Sound event</b> — resolves the ledger id {@code eclipse:ambient.crystal_voice}
 *       (sounds.json ask in {@code docs/plans_v3/wiring/woah_resonance_sounds.json});
 *       until the .ogg ships it falls back to the shipped
 *       {@code EclipseSounds.AMBIENT_LIMBO_LOOP} re-pitched by the SAME tone table —
 *       the documented {@code SanctumHum.resolveHum()} self-healing pattern.</li>
 * </ul>
 *
 * <p>{@code SoundSource.AMBIENT} keeps the choir off {@code MusicManager}'s MUSIC
 * channel; every instance self-stops after {@value Voice#SILENT_STOP_TICKS} silent
 * ticks and the {@code LoggingOut} teardown kills the set (risk #2 mitigations).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class ResonanceChoir {
    /** Ledger id of the authored glass-bow drone (§6.5 — asset ask pending). */
    private static final ResourceLocation VOICE_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ambient.crystal_voice");

    /** §8: sing-LOD is hard — beyond this nothing sings, the far silhouette carries. */
    private static final double ENGAGE_DISTANCE = 44.0D;
    private static final double RELEASE_DISTANCE = 52.0D;
    public static final int MAX_VOICES = 4;
    /** §4.2 volume curve: {@code 0.65 × clamp(1 − (dist − 4)/44, 0, 1)^1.5}. */
    private static final float PEAK_VOLUME = 0.65F;
    private static final double CURVE_NEAR = 4.0D;
    private static final double CURVE_SPAN = 44.0D;

    /** Live voices by crystal index (client main thread only). */
    private static final Map<Integer, Voice> VOICES = new HashMap<>();

    private ResonanceChoir() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        LocalPlayer player = minecraft.player;
        ResonanceFieldClient.Snapshot field = ResonanceFieldClient.get();
        if (level == null || player == null || field == null
                || level.dimension() != Level.OVERWORLD) {
            fadeAll();
            return;
        }

        // Distance-sorted candidates inside the engage window.
        record Candidate(int index, double distance) {}
        List<Candidate> near = new ArrayList<>(MAX_VOICES + 2);
        Vec3 eye = player.getEyePosition();
        for (int i = 0; i < field.crystals().size(); i++) {
            double distance = eye.distanceTo(field.voicePos(i));
            boolean live = VOICES.containsKey(i);
            if (distance < ENGAGE_DISTANCE || (live && distance <= RELEASE_DISTANCE)) {
                near.add(new Candidate(i, distance));
            }
        }
        near.sort(Comparator.comparingDouble(Candidate::distance));

        // Release: voices out of the hysteresis window or beyond the budget cut.
        for (Map.Entry<Integer, Voice> entry : VOICES.entrySet()) {
            int index = entry.getKey();
            boolean keep = false;
            for (int rank = 0; rank < Math.min(near.size(), MAX_VOICES); rank++) {
                if (near.get(rank).index() == index) {
                    keep = true;
                    break;
                }
            }
            if (!keep) {
                entry.getValue().targetVolume = 0.0F; // fade; self-stops when silent
            }
        }
        VOICES.values().removeIf(Voice::isStopped);

        // Engage / drive the top-4 nearest.
        for (int rank = 0; rank < Math.min(near.size(), MAX_VOICES); rank++) {
            Candidate candidate = near.get(rank);
            Voice voice = VOICES.get(candidate.index());
            if (voice == null || voice.isStopped()) {
                voice = new Voice(field.crystals().get(candidate.index()).toneIndex(),
                        field.voicePos(candidate.index()));
                VOICES.put(candidate.index(), voice);
                minecraft.getSoundManager().play(voice);
            }
            double linear = Mth.clamp(
                    1.0D - (candidate.distance() - CURVE_NEAR) / CURVE_SPAN, 0.0D, 1.0D);
            voice.targetVolume = PEAK_VOLUME * (float) Math.pow(linear, 1.5D);
        }
    }

    private static void fadeAll() {
        for (Voice voice : VOICES.values()) {
            voice.targetVolume = 0.0F;
        }
        VOICES.values().removeIf(Voice::isStopped);
    }

    /** Disconnect teardown (SanctumHum {@code onLoggingOut} mirror) — no leaked loops. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        for (Voice voice : VOICES.values()) {
            voice.forceStop();
        }
        VOICES.clear();
    }

    /** Registered {@code ambient.crystal_voice} or the pitched limbo-loop fallback. */
    private static SoundEvent resolveVoice() {
        return BuiltInRegistries.SOUND_EVENT.getOptional(VOICE_ID)
                .orElseGet(EclipseSounds.AMBIENT_LIMBO_LOOP);
    }

    /**
     * One crystal's singing loop: Attenuation NONE (the manual curve IS the rolloff),
     * volume chases the ticker's target with the SanctumHum 0.05 step, self-stop after
     * {@value #SILENT_STOP_TICKS} silent ticks.
     */
    private static final class Voice extends AbstractTickableSoundInstance {
        private static final float VOLUME_STEP = 0.05F;
        private static final int SILENT_STOP_TICKS = 60;

        volatile float targetVolume;
        private int silentTicks;

        private Voice(int toneIndex, Vec3 pos) {
            super(resolveVoice(), SoundSource.AMBIENT, SoundInstance.createUnseededRandom());
            this.looping = true;
            this.delay = 0;
            this.volume = 0.0F;
            this.relative = false;
            this.attenuation = SoundInstance.Attenuation.NONE;
            this.pitch = ResonanceTones.pitch(toneIndex);
            this.x = pos.x;
            this.y = pos.y;
            this.z = pos.z;
        }

        @Override
        public void tick() {
            float target = this.targetVolume;
            if (this.volume < target) {
                this.volume = Math.min(target, this.volume + VOLUME_STEP);
            } else if (this.volume > target) {
                this.volume = Math.max(target, this.volume - VOLUME_STEP);
            }
            if (this.volume <= 0.005F) {
                if (++this.silentTicks >= SILENT_STOP_TICKS) {
                    this.stop();
                }
            } else {
                this.silentTicks = 0;
            }
        }

        void forceStop() {
            this.stop();
        }
    }
}
