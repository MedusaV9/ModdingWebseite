/**
 * Client half of the KILL CONTRACTS system (IDEA-20): the hunter's roulette→real-face→red-X
 * reveal ceremony, the target's "DU WIRST GEJAGT" warning, the window mini-marker + subtle
 * vignette, and the client window flag that gates the armor blackout mixin
 * ({@code client/mixin/HumanoidArmorLayerMixin}).
 *
 * <p><b>The one deliberate anonymity breach:</b> {@code AbstractClientPlayerMixin} only
 * intercepts entity-render skins ({@code AbstractClientPlayer#getSkin}); this package
 * resolves the target UUID → {@code GameProfile} → {@code SkinManager} directly, which
 * bypasses the uniform-skin mixin — face only, name never, hunters only.</p>
 */
package dev.projecteclipse.eclipse.client.contracts;
