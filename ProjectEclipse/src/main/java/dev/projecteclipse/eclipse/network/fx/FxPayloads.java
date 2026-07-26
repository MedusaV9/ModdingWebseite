package dev.projecteclipse.eclipse.network.fx;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.veilfx.EclipseFxState;
import dev.projecteclipse.eclipse.veilfx.FxAnchors;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.network.PacketDistributor;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.network.handling.IPayloadContext;
import net.neoforged.neoforge.network.registration.PayloadRegistrar;

/**
 * Self-registering registrar for the P2 FX payloads (P2 §3.2). Registers on its own MOD-bus
 * {@link RegisterPayloadHandlersEvent} subscriber under version group {@value #VERSION} —
 * {@code EclipsePayloads.register(...)} and {@code EclipseMod} stay untouched (NeoForge
 * allows any number of payload registrars). All payload ids are prefixed {@code eclipse:fx/}
 * so they can never collide with the v1 ids.
 *
 * <p>Handlers are thin: they dispatch to the frozen client entry points (§3.2 table). Client
 * classes are referenced fully-qualified inside the handler bodies so they are resolved
 * lazily and never load on a dedicated server (repo pattern from {@code EclipsePayloads}).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
public final class FxPayloads {
    private static final String VERSION = "fx1";

    // Frozen S2CFxEventPayload ids (P2 §3.2).
    /** pos = impact, a = intensity 0..1, b = 0 normal / 1 giant. */
    public static final ResourceLocation FX_LIGHTNING_STRIKE = fx("lightning_strike");
    /** pos = origin, a = strength, b = durationTicks. */
    public static final ResourceLocation FX_SHOCKWAVE = fx("shockwave");
    /** pos = center, a = width blocks, b = style 0 structure / 1 portal. */
    public static final ResourceLocation FX_RIFT_OPEN = fx("rift_open");
    public static final ResourceLocation FX_RIFT_CLOSE = fx("rift_close");
    /** pos = the gliding player. */
    public static final ResourceLocation FX_GLIDE_START = fx("glide_start");
    public static final ResourceLocation FX_GLIDE_STOP = fx("glide_stop");
    /** a = 0 off / 1 on. */
    public static final ResourceLocation FX_DOOR_GLOW = fx("door_glow");
    /** W4-FEEL: ore proc sparkle at a mined block (a = ore tint index, b = bonus count). */
    public static final ResourceLocation FX_ORE_PROC = fx("ore_proc");
    /** W4-ATMOS: post-expansion new-land band glow (a = innerR, b = outerR). */
    public static final ResourceLocation FX_NEW_LAND_GLOW = fx("new_land_glow");
    /**
     * W-P-ALTAR: altar level-up ceremony (pos = altar, a = freshly reached level,
     * b = crowd size — players within {@code AltarBlockEntity.CROWD_RANGE} of the altar;
     * VEIL-REPASS-2: widens the ceremony burst. 0 from pre-crowd servers = base look).
     */
    public static final ResourceLocation FX_ALTAR_LEVELUP = fx("altar_levelup");

    /** How far the glide event position may be from a player to attach the trail to them. */
    private static final double GLIDE_MATCH_RANGE_SQ = 8.0D * 8.0D;
    /** Distance the reconstructed lightning source sits toward the sun (R10: center + dir·180). */
    private static final double LIGHTNING_SOURCE_BLOCKS = 180.0D;

    private FxPayloads() {}

    private static ResourceLocation fx(String name) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/" + name);
    }

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CEclipsePhasePayload.TYPE, S2CEclipsePhasePayload.STREAM_CODEC, FxPayloads::handleEclipsePhase);
        registrar.playToClient(S2CFxEventPayload.TYPE, S2CFxEventPayload.STREAM_CODEC, FxPayloads::handleFxEvent);
        registrar.playToClient(S2CFxEntityEventPayload.TYPE, S2CFxEntityEventPayload.STREAM_CODEC, FxPayloads::handleFxEntityEvent);
        registrar.playToClient(S2CStormStatePayload.TYPE, S2CStormStatePayload.STREAM_CODEC, FxPayloads::handleStormState);
        registrar.playToClient(S2CStormSiegePayload.TYPE, S2CStormSiegePayload.STREAM_CODEC, FxPayloads::handleStormSiege);
        registrar.playToClient(S2CSupplyMarkerPayload.TYPE, S2CSupplyMarkerPayload.STREAM_CODEC, FxPayloads::handleSupplyMarker);
        registrar.playToClient(S2CViewDistancePayload.TYPE, S2CViewDistancePayload.STREAM_CODEC, FxPayloads::handleViewDistance);
        registrar.playToClient(S2CScreenFadePayload.TYPE, S2CScreenFadePayload.STREAM_CODEC, FxPayloads::handleScreenFade);
        registrar.playToClient(S2CCaptionPayload.TYPE, S2CCaptionPayload.STREAM_CODEC, FxPayloads::handleCaption);
        registrar.playToClient(S2CGhostStatePayload.TYPE, S2CGhostStatePayload.STREAM_CODEC, FxPayloads::handleGhostState);
        registrar.playToClient(S2CAnchorPayload.TYPE, S2CAnchorPayload.STREAM_CODEC, FxPayloads::handleAnchor);
        registrar.playToClient(S2CGlitchZonePayload.TYPE, S2CGlitchZonePayload.STREAM_CODEC, FxPayloads::handleGlitchZone);
    }

    // ------------------------------------------------------------------ server send helpers

    /** Broadcasts an eclipse phase change to every player (W6/W7 sequences, P4 login re-send). */
    public static void sendEclipsePhase(MinecraftServer server, int phase, float intensity,
            int rampTicks, boolean permanentRim) {
        PacketDistributor.sendToAllPlayers(new S2CEclipsePhasePayload(phase, intensity, rampTicks, permanentRim));
    }

    /**
     * Sends an FX event to players near {@code pos} ({@code range <= 0} → whole dimension).
     * Use the frozen {@code FX_*} ids.
     */
    public static void sendFxEvent(ServerLevel level, ResourceLocation id, Vec3 pos,
            float a, float b, double range) {
        S2CFxEventPayload payload = new S2CFxEventPayload(id, pos, a, b);
        if (range <= 0.0D) {
            PacketDistributor.sendToPlayersInDimension(level, payload);
        } else {
            PacketDistributor.sendToPlayersNear(level, null, pos.x, pos.y, pos.z, range, payload);
        }
    }

    /**
     * NEWFX-C2: sends one position-lane FX event to exactly ONE player (the
     * {@code PacketDistributor.sendToPlayer} half of the {@code CUE_DAWN_TOLL} personal-
     * ceremony law, on the position lane). Use for per-player cues anchored at that
     * player's own position — a range broadcast would stack N×N copies on clustered
     * players and leak that the cue is per-recipient.
     */
    public static void sendFxEventTo(ServerPlayer player, ResourceLocation id, Vec3 pos,
            float a, float b) {
        PacketDistributor.sendToPlayer(player, new S2CFxEventPayload(id, pos, a, b));
    }

    /**
     * PH-PLAYER / PH-MOBS entity-cue lane ({@link S2CFxEntityEventPayload}): like
     * {@link #sendFxEvent} but the cue rides {@code target}'s entity id so the client can
     * attach the Photon leg to the (possibly moving) entity; {@code target.position()} is
     * carried as the degrade anchor for clients that no longer track it ({@code range <= 0}
     * → whole dimension). Use {@code FxCues.CUE_*} ids whose registry row expects the
     * entity lane ({@code PhotonFxRegistry.dispatchEntity}).
     */
    public static void sendFxEntityEvent(ServerLevel level, ResourceLocation id,
            net.minecraft.world.entity.Entity target, float a, float b, double range) {
        Vec3 pos = target.position();
        S2CFxEntityEventPayload payload =
                new S2CFxEntityEventPayload(id, target.getId(), pos, a, b);
        if (range <= 0.0D) {
            PacketDistributor.sendToPlayersInDimension(level, payload);
        } else {
            PacketDistributor.sendToPlayersNear(level, null, pos.x, pos.y, pos.z, range, payload);
        }
    }

    /** Ghost-grade toggle for one player (P3 death/respawn flow, §6.2). */
    public static void sendGhostState(ServerPlayer player, boolean active) {
        PacketDistributor.sendToPlayer(player, new S2CGhostStatePayload(active));
    }

    // ------------------------------------------------------------------ client dispatch

    private static void handleEclipsePhase(S2CEclipsePhasePayload payload, IPayloadContext context) {
        EclipseFxState.setEclipse(payload.phase(), payload.intensity(), payload.rampTicks());
        EclipseFxState.setPermanentSunRim(payload.permanentRim());
    }

    /** Runs on the client main thread only; sibling client classes are resolved lazily. */
    private static void handleFxEvent(S2CFxEventPayload payload, IPayloadContext context) {
        ResourceLocation id = payload.id();
        if (FX_SHOCKWAVE.equals(id)) {
            EclipseFxState.startShockwave(payload.pos(), payload.a(), Math.max(1, (int) payload.b()));
            if (payload.a() >= 1.0F && payload.b() >= 50.0F) {
                // PH-EVENTS (IDEAS-events #1): the (1.0, 50) giant signature is sent only
                // by the intro/credits BURST beats (live + FX-only replays) — layer the
                // HDR white-out ring so the flash sandwich gets a physical source. LAYER
                // law: the Quasar shockwave above already ran; no timing changes.
                dev.projecteclipse.eclipse.veilfx.PhotonBridge.spawn(
                        dev.projecteclipse.eclipse.veilfx.PhotonBridge.INTRO_BURST_RING, payload.pos());
            }
        } else if (FX_LIGHTNING_STRIKE.equals(id)) {
            // Strikes come FROM the eclipse: reconstruct the source along the sun direction
            // (R10: center + sunDir · 180) so every client agrees with the sky; the source is
            // kept at least 60 blocks up so night-time strikes never originate underground.
            org.joml.Vector3f dir = dev.projecteclipse.eclipse.veilfx.SunTracker.sunDirWorld(1.0F);
            Vec3 from = payload.pos().add(dir.x() * LIGHTNING_SOURCE_BLOCKS,
                    Math.max(dir.y() * LIGHTNING_SOURCE_BLOCKS, 60.0D), dir.z() * LIGHTNING_SOURCE_BLOCKS);
            dev.projecteclipse.eclipse.stormfx.StormFxClient.strikeLightning(from, payload.pos(), payload.a());
        } else if (FX_RIFT_OPEN.equals(id)) {
            dev.projecteclipse.eclipse.veilfx.rift.RiftFx.openRift(
                    payload.pos(), new Vec3(0.0D, 1.0D, 0.0D), payload.a(), 0, (int) payload.b());
        } else if (FX_RIFT_CLOSE.equals(id)) {
            dev.projecteclipse.eclipse.veilfx.rift.RiftFx.closeRift(payload.pos());
        } else if (FX_GLIDE_START.equals(id)) {
            // PH-SOCIAL (IDEAS-player #10): the controller elects the trail leg — Photon
            // wingtip ara ribbons (FORWARD AutoRotate) REPLACING the Quasar loop, which
            // re-enters automatically whenever the Photon leg is unavailable.
            Player glider = nearestPlayer(payload.pos());
            if (glider != null) {
                dev.projecteclipse.eclipse.veilfx.GlideTrailFx.attach(glider);
            }
        } else if (FX_GLIDE_STOP.equals(id)) {
            Player glider = nearestPlayer(payload.pos());
            if (glider != null) {
                dev.projecteclipse.eclipse.veilfx.GlideTrailFx.detach(glider);
            }
        } else if (FX_DOOR_GLOW.equals(id)) {
            dev.projecteclipse.eclipse.client.ShipDoorGlow.handleDoorGlow(payload.a() > 0.5F);
        } else if (FX_ORE_PROC.equals(id)) {
            dev.projecteclipse.eclipse.client.drama.OreProcFxClient.handle(
                    payload.pos(), payload.a(), payload.b());
        } else if (FX_NEW_LAND_GLOW.equals(id)) {
            dev.projecteclipse.eclipse.sequence.ExpansionSequence.ClientHooks
                    .handleNewLandGlow(payload.a(), payload.b());
        } else if (FX_ALTAR_LEVELUP.equals(id)) {
            // W-P-ALTAR: per-level escalating level-up ceremony (a = the new level;
            // VEIL-REPASS-2: b = crowd size at the altar — widens the burst).
            dev.projecteclipse.eclipse.client.drama.AltarCeremonyFx.start(
                    payload.pos(), (int) payload.a(), (int) payload.b());
        } else if (dev.projecteclipse.eclipse.drama.GestureGlyphService.FX_GLYPH.equals(id)) {
            // W4-CEREMONY IDEA-10 #2: pos = gesturing player, a = glyph 0 greet/1 danger/2 follow.
            dev.projecteclipse.eclipse.client.drama.GestureGlyphFx.show(payload.pos(), (int) payload.a());
        } else if (FxCues.CUE_WARDEN_VOLLEY_TELEGRAPH.equals(id)) {
            // PH-BOSS-B (IDEAS-boss #3): pos = warden eye, a = yaw deg. Needs an executor
            // rotation, which the generic PhotonFxRegistry.dispatch(id, pos) tail cannot
            // carry — the helper resolves the same registered row and adds the aim.
            dev.projecteclipse.eclipse.veilfx.BossPhotonFxRows.wardenEyeLaser(payload.pos(), payload.a());
        } else if (FxCues.CUE_GROWTH_RIDER.equals(id)) {
            // PH-RIFT (IDEAS-events #4): entity-anchored cue — a = rider entity id,
            // b = 1 attach / 0 release. Dedicated branch (not a registry row: rows are
            // position-anchored; INTEGRATION.md §3.5 law 5 pre-authorizes this shape).
            dev.projecteclipse.eclipse.sequence.ExpansionSequence.ClientHooks
                    .handleGrowthRider((int) payload.a(), payload.b() > 0.5F);
        } else if (FxCues.CUE_HEART_THEFT.equals(id)) {
            // PH-SOCIAL (IDEAS-player #3): pos = corpse, a/b = killer/victim entity ids.
            // Needs aimed rotation + distance-scaled delays across three executors — the
            // warden pattern: an explicit branch over the registered row.
            dev.projecteclipse.eclipse.veilfx.PlayerFxPhotonRows.heartTheftArc(
                    payload.pos(), payload.a(), payload.b());
        } else if (dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry.dispatch(
                id, payload.pos(), payload.a(), payload.b())) {
            // PH-CORE tail branch: table-driven FxCues cue rows (Photon layer + Quasar
            // fallback per row mode) — consumed when a row is registered for the id.
            // The payload's a/b thread through so rows with a PhotonLeg can consume them
            // (CUE_STERN_KOMET telegraph delay, CUE_CREDITS_STRIKE intensity → scale,
            // CUE_STRUCTURE_SLAM footprint → scale).
        } else {
            EclipseMod.LOGGER.debug("Unknown FX event id {} (pos {}, a {}, b {})", id, payload.pos(), payload.a(), payload.b());
        }
    }

    /**
     * PH-PLAYER / PH-MOBS entity-cue lane (client main thread): resolves the entity id
     * against the client level and hands the cue to the registry's entity dispatch. A
     * missing/gone entity degrades to the payload's position anchor inside
     * {@code PhotonFxRegistry.dispatchEntity} — never a drop below the Quasar baseline.
     */
    private static void handleFxEntityEvent(S2CFxEntityEventPayload payload, IPayloadContext context) {
        ClientLevel level = Minecraft.getInstance().level;
        net.minecraft.world.entity.Entity target =
                level == null ? null : level.getEntity(payload.entityId());
        if (!dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry.dispatchEntity(
                payload.id(), target, payload.pos(), payload.a(), payload.b())) {
            EclipseMod.LOGGER.debug("Unknown FX entity event id {} (entity {}, pos {})",
                    payload.id(), payload.entityId(), payload.pos());
        }
    }

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleStormState(S2CStormStatePayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.stormfx.StormFxClient.handle(payload);
    }

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleStormSiege(S2CStormSiegePayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.stormfx.StormFxClient.handleSiege(payload);
    }

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleSupplyMarker(S2CSupplyMarkerPayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.veilfx.SupplyBeamClient.handle(payload);
    }

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleViewDistance(S2CViewDistancePayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.cutscene.client.ViewDistanceClient.handle(payload);
    }

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleScreenFade(S2CScreenFadePayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.cutscene.client.CaptionRenderer.fade(
                payload.inTicks(), payload.holdTicks(), payload.outTicks(), payload.argb(),
                payload.sustained());
    }

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleCaption(S2CCaptionPayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.cutscene.client.CaptionRenderer.enqueue(
                payload.langKey(), payload.durationTicks(), payload.style());
    }

    private static void handleGhostState(S2CGhostStatePayload payload, IPayloadContext context) {
        EclipseFxState.setGhost(payload.active());
    }

    private static void handleAnchor(S2CAnchorPayload payload, IPayloadContext context) {
        FxAnchors.handleClient(payload.id(), payload.set(), payload.pos());
    }

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleGlitchZone(S2CGlitchZonePayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.client.GlitchZoneFx.handle(payload.effect(), payload.strength(),
                payload.colour(), payload.originValid(), payload.origin());
    }

    /** Nearest client-level player to an FX event position (glide events carry no entity id). */
    @javax.annotation.Nullable
    private static Player nearestPlayer(Vec3 pos) {
        ClientLevel level = Minecraft.getInstance().level;
        if (level == null) {
            return null;
        }
        Player best = null;
        double bestDistSq = GLIDE_MATCH_RANGE_SQ;
        for (Player player : level.players()) {
            double distSq = player.distanceToSqr(pos);
            if (distSq < bestDistSq) {
                bestDistSq = distSq;
                best = player;
            }
        }
        return best;
    }
}
