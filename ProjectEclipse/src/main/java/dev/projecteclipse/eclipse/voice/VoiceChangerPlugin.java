package dev.projecteclipse.eclipse.voice;

import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

import de.maxhenkel.voicechat.api.ForgeVoicechatPlugin;
import de.maxhenkel.voicechat.api.VoicechatApi;
import de.maxhenkel.voicechat.api.VoicechatConnection;
import de.maxhenkel.voicechat.api.VoicechatPlugin;
import de.maxhenkel.voicechat.api.events.EventRegistration;
import de.maxhenkel.voicechat.api.events.MicrophonePacketEvent;
import de.maxhenkel.voicechat.api.events.PlayerDisconnectedEvent;
import de.maxhenkel.voicechat.api.events.VoicechatServerStoppedEvent;
import de.maxhenkel.voicechat.api.opus.OpusDecoder;
import de.maxhenkel.voicechat.api.opus.OpusEncoder;
import dev.projecteclipse.eclipse.EclipseMod;

/**
 * W4-TOGGLES voice changer: server-side per-player voice effects applied in the
 * {@code MicrophonePacketEvent} path — decode opus → {@link VoiceDsp} pitch/tremolo →
 * re-encode → {@code MicrophonePacket.setOpusEncodedData} (the packet impl mutates the
 * underlying {@code MicPacket}, so ALL receivers — locational, group and whisper — hear the
 * transformed voice; the sender's own client never plays back its own mic, so the speaker is
 * unaffected).
 *
 * <p>Follows the {@code EclipseVoicePlugin} isolation contract: this is the ONLY voice-changer
 * class importing the optional {@code de.maxhenkel.voicechat.api} ({@code compileOnly} dep) and
 * nothing in Eclipse's init path references it — Simple Voice Chat discovers it via the
 * annotation only when installed. A separate plugin (id {@code eclipse_voice_changer}) rather
 * than an edit to {@code EclipseVoicePlugin}: the mic handler registers at priority
 * {@value #MIC_EVENT_PRIORITY} so the mute plugin's default-priority cancel runs first
 * (Simple Voice Chat stops dispatch on cancel — muted packets never reach the DSP; if the
 * sort order ever inverts, the only cost is DSP work on a packet that is then dropped).</p>
 *
 * <p><b>Threading &amp; codec state</b>: mic events fire on the voice packet thread. Opus
 * codecs are stateful per stream, so each speaking player gets a lazily-created decoder +
 * encoder pair ({@link Pipeline}), closed on voice disconnect and at voice-server stop. An
 * empty opus payload is Simple Voice Chat's end-of-transmission marker — passed through
 * untouched with a codec/effect state reset.</p>
 *
 * <p><b>Perf</b>: with the effective preset OFF the handler costs one map read; when active,
 * the full decode→DSP→encode time is measured with {@code System.nanoTime} and reported to
 * {@link VoiceChangerService#reportFrameNanos} (budget default 2 ms/frame, auto-disable with
 * a WARN log after consecutive over-budget frames). Any DSP failure logs (throttled) and
 * passes the original packet through — the changer can break itself, never voice chat.</p>
 */
@ForgeVoicechatPlugin
public final class VoiceChangerPlugin implements VoicechatPlugin {
    /** Below the mute plugin's default 0 → runs after the mute cancel. */
    private static final int MIC_EVENT_PRIORITY = -100;
    /** Error log throttle (ms) so a broken codec can't spam 50 lines/sec. */
    private static final long ERROR_LOG_THROTTLE_MILLIS = 10_000L;

    private static final ConcurrentHashMap<UUID, Pipeline> PIPELINES = new ConcurrentHashMap<>();
    private static final AtomicLong LAST_ERROR_LOG = new AtomicLong();

    @Override
    public String getPluginId() {
        return "eclipse_voice_changer";
    }

    @Override
    public void registerEvents(EventRegistration registration) {
        registration.registerEvent(MicrophonePacketEvent.class,
                VoiceChangerPlugin::onMicrophonePacket, MIC_EVENT_PRIORITY);
        registration.registerEvent(PlayerDisconnectedEvent.class,
                VoiceChangerPlugin::onPlayerDisconnected);
        registration.registerEvent(VoicechatServerStoppedEvent.class,
                VoiceChangerPlugin::onVoiceServerStopped);
    }

    private static void onMicrophonePacket(MicrophonePacketEvent event) {
        if (event.isCancelled()) {
            return;
        }
        VoicechatConnection sender = event.getSenderConnection();
        if (sender == null) {
            return;
        }
        UUID speaker = sender.getPlayer().getUuid();
        VoicePreset preset = VoiceChangerService.effectivePreset(speaker);
        if (preset == VoicePreset.OFF) {
            return;
        }
        Pipeline pipeline = PIPELINES.computeIfAbsent(speaker,
                uuid -> new Pipeline(event.getVoicechat()));
        byte[] data = event.getPacket().getOpusEncodedData();
        if (data == null || data.length == 0) {
            // End-of-transmission marker: forward untouched, start the next utterance clean.
            pipeline.reset();
            return;
        }
        try {
            long start = System.nanoTime();
            short[] pcm = pipeline.decoder.decode(data);
            if (pcm == null || pcm.length == 0) {
                return;
            }
            short[] shaped = VoiceDsp.apply(pcm, preset, pipeline.fx);
            byte[] encoded = pipeline.encoder.encode(shaped);
            long elapsed = System.nanoTime() - start;
            event.getPacket().setOpusEncodedData(encoded);
            VoiceChangerService.reportFrameNanos(elapsed);
        } catch (Throwable t) {
            long now = System.currentTimeMillis();
            long last = LAST_ERROR_LOG.get();
            if (now - last > ERROR_LOG_THROTTLE_MILLIS && LAST_ERROR_LOG.compareAndSet(last, now)) {
                EclipseMod.LOGGER.error("VoiceChanger: DSP failed for {} — passing voice through", speaker, t);
            }
        }
    }

    private static void onPlayerDisconnected(PlayerDisconnectedEvent event) {
        Pipeline pipeline = PIPELINES.remove(event.getPlayerUuid());
        if (pipeline != null) {
            pipeline.close();
        }
    }

    private static void onVoiceServerStopped(VoicechatServerStoppedEvent event) {
        PIPELINES.values().forEach(Pipeline::close);
        PIPELINES.clear();
    }

    /** Per-speaker stateful opus codec pair + DSP carry-over (voice thread only). */
    private static final class Pipeline {
        final OpusDecoder decoder;
        final OpusEncoder encoder;
        final VoiceDsp.FxState fx = new VoiceDsp.FxState();

        Pipeline(VoicechatApi api) {
            this.decoder = api.createDecoder();
            this.encoder = api.createEncoder();
        }

        void reset() {
            if (!decoder.isClosed()) {
                decoder.resetState();
            }
            if (!encoder.isClosed()) {
                encoder.resetState();
            }
            fx.reset();
        }

        void close() {
            if (!decoder.isClosed()) {
                decoder.close();
            }
            if (!encoder.isClosed()) {
                encoder.close();
            }
        }
    }
}
