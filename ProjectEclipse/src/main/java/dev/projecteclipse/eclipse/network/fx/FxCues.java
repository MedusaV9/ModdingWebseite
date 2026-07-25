package dev.projecteclipse.eclipse.network.fx;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.resources.ResourceLocation;

/**
 * Frozen logical FX cue ids for the {@code PhotonFxRegistry} lane (INTEGRATION.md §3):
 * plain server-referenceable constants so server code never touches client classes (repo
 * rule). A cue travels over the EXISTING {@code S2CFxEventPayload}
 * ({@link FxPayloads#sendFxEvent}) — no new payload type, no registrar bump, identical
 * bytes whether or not the client has Photon. On the client,
 * {@code veilfx/PhotonFxRegistry} resolves the cue to a Photon effect and/or a Quasar
 * fallback via its registered row.
 *
 * <p>Namespace law: cue ids reuse the {@code eclipse:fx/} prefix (collision-free with the
 * v1 payload ids) with an extra {@code cue/} segment so they are visually distinct from
 * the handler-dispatched {@code fx/*} ids in {@link FxPayloads}.</p>
 *
 * <p>Content workers: add one {@code CUE_*} constant here per new cue (server side) and
 * register the matching row in your own {@code *PhotonFxRows} client registrar class
 * (see {@code veilfx/PhotonFxRows} for the reference pattern).</p>
 */
public final class FxCues {
    /** PH-CORE smoke test: one-shot spark burst ({@code eclipse:template_burst}). */
    public static final ResourceLocation CUE_TEMPLATE_BURST = cue("template_burst");
    /** PH-CORE smoke test: looping aura ring ({@code eclipse:template_loop}, WINDOWED-only). */
    public static final ResourceLocation CUE_TEMPLATE_LOOP = cue("template_loop");

    private FxCues() {}

    /** {@code eclipse:fx/cue/<name>} — use for every new registry cue id. */
    public static ResourceLocation cue(String name) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/cue/" + name);
    }
}
