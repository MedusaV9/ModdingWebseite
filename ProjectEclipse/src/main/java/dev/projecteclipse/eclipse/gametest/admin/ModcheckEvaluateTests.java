package dev.projecteclipse.eclipse.gametest.admin;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.admin.AntiCheatCheck;
import dev.projecteclipse.eclipse.admin.AntiCheatCheck.Config;
import dev.projecteclipse.eclipse.admin.AntiCheatCheck.Evaluation;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.server.MinecraftServer;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * D7 regression tests: the shipped allowlist accepts the Forgified-Fabric-API sub-module ids
 * nested inside the Sodium/Iris NeoForge jars (plus MixinSquared nested in Supplementaries),
 * unknown ids still fail, and the UUID-pinned dev bypass matches exactly its listed identities.
 */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class ModcheckEvaluateTests {
    /** The nested jar-in-jar ids verified by unpacking the dev pack (see docs/BUNDLING.md). */
    private static final List<String> NESTED_IDS = List.of(
            "fabric_api_base", "fabric_block_view_api_v2",
            "fabric_renderer_api_v1", "fabric_rendering_data_attachment_v1",
            "mixinsquared");

    private ModcheckEvaluateTests() {}

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void nestedFabricSubmoduleIdsPassAllowlist(GameTestHelper helper) {
        Config config = AntiCheatCheck.defaults();
        List<String> report = new ArrayList<>(config.requiredMods());
        report.addAll(List.of("sodium", "iris"));
        report.addAll(NESTED_IDS);

        Evaluation result = AntiCheatCheck.evaluate(config, report);
        helper.assertTrue(result.accepted(),
                "nested Forgified-Fabric-API/MixinSquared ids must pass in allowlist mode: "
                        + result.summary());
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void unknownIdStillFailsAllowlist(GameTestHelper helper) {
        Config config = AntiCheatCheck.defaults();
        List<String> report = new ArrayList<>(config.requiredMods());
        report.add("definitely_not_in_the_pack");

        Evaluation result = AntiCheatCheck.evaluate(config, report);
        helper.assertTrue(!result.accepted(), "an unknown id must still fail the allowlist");
        helper.assertTrue(result.extra().contains("definitely_not_in_the_pack"),
                "the unknown id is itemized as extra");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void devBypassMatchesOnlyListedUuids(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        UUID dev = UUID.fromString("11111111-2222-3333-4444-555555555555");
        Config base = AntiCheatCheck.defaults();
        // Deliberately no "name:…" pin here: name resolution may consult the profile
        // repository (network) on a cache miss, which would make this test non-hermetic.
        Config config = new Config(base.mode(), base.blockedModIdSubstrings(), base.allowedMods(),
                base.requiredMods(), base.optionalMods(), base.downloadHintUrl(),
                base.allowContinueOnMismatch(),
                List.of(dev.toString(), "not-a-uuid-and-not-a-name-pin"));

        helper.assertTrue(AntiCheatCheck.isDevBypass(config, server, dev),
                "a UUID-pinned dev identity is bypassed");
        helper.assertTrue(!AntiCheatCheck.isDevBypass(config, server, UUID.randomUUID()),
                "an unlisted identity is never bypassed");
        helper.assertTrue(!AntiCheatCheck.isDevBypass(config, server, null),
                "a null identity is never bypassed");
        // The malformed second entry must be skipped without throwing (exercised above).
        Config empty = new Config(base.mode(), base.blockedModIdSubstrings(), base.allowedMods(),
                base.requiredMods(), base.optionalMods(), base.downloadHintUrl(),
                base.allowContinueOnMismatch(), List.of());
        helper.assertTrue(!AntiCheatCheck.isDevBypass(empty, server, dev),
                "an empty bypass list bypasses nobody");
        helper.succeed();
    }
}
