package dev.projecteclipse.eclipse.gametest.admin;

import java.util.LinkedHashMap;
import java.util.Map;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.admin.AntiCheatCheck;
import dev.projecteclipse.eclipse.admin.ModVersionCheck;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * Regression tests for the pack version pins.
 *
 * <p>The bug these lock down: EMI resolves from {@code dev.emi:emi-neoforge:1.1.24+1.21.1} but
 * REPORTS {@code 1.1.24+1.21.1+neoforge}, so the exact-string pin flagged the mod the pack
 * bundles itself as "wrong version" on every client start.</p>
 */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class ModVersionCheckTests {
    /**
     * The versions the pack mods actually report, read off a dev client's loader mod list.
     * Client-only extras (sodium/iris) and ids that ride inside another jar are included
     * where the shipped allowlist pins them.
     */
    private static Map<String, String> reportedPackVersions() {
        Map<String, String> reported = new LinkedHashMap<>();
        reported.put("minecraft", "1.21.1");
        reported.put("neoforge", "21.1.238");
        reported.put("eclipse", "2.1.0");
        reported.put("veil", "4.3.0");
        reported.put("geckolib", "4.9.2");
        reported.put("emi", "1.1.24+1.21.1+neoforge");
        reported.put("mousetweaks", "2.26.1");
        reported.put("create", "6.0.10");
        reported.put("aeronautics", "1.3.0");
        reported.put("aeronautics_bundled", "1.3.0");
        reported.put("simulated", "1.3.0");
        reported.put("offroad", "1.3.0");
        reported.put("sable", "2.0.3");
        reported.put("sablecompanion", "1.6.0");
        reported.put("voicechat", "1.21.1-2.6.16");
        reported.put("voicechat_api", "2.6.13");
        reported.put("farmersdelight", "1.3.2");
        reported.put("supplementaries", "1.21.1-3.8.3");
        reported.put("moonlight", "1.21.1-3.1.1");
        reported.put("sophisticatedbackpacks", "3.25.71");
        reported.put("sophisticatedcore", "1.4.77");
        reported.put("createaddition", "1.6.0");
        reported.put("flywheel", "1.0.6");
        reported.put("ponder", "1.0.82+mc1.21.1");
        reported.put("codecui", "1.21.1-1.1.5");
        reported.put("photon", "2.1.5");
        reported.put("ldlib2", "2.2.29");
        reported.put("sodium", "0.8.12+mc1.21.1");
        reported.put("iris", "1.8.14-beta.1+mc1.21.1");
        return reported;
    }

    private ModVersionCheckTests() {}

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void shippedPinsAcceptTheRealPack(GameTestHelper helper) {
        Map<String, String> allowed = AntiCheatCheck.defaults().allowedMods();
        reportedPackVersions().forEach((modId, reported) -> {
            String pin = allowed.get(modId);
            helper.assertTrue(pin != null, "no allowlist pin for pack mod " + modId);
            helper.assertTrue(ModVersionCheck.matches(reported, pin),
                    "pack mod " + modId + " reports " + reported + " but is pinned to " + pin);
        });
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void buildMetadataIsToleratedOnlyOnAnExactPrefix(GameTestHelper helper) {
        helper.assertTrue(ModVersionCheck.matches("1.1.24+1.21.1+neoforge", "1.1.24+1.21.1"),
                "an added +build suffix must be tolerated");
        helper.assertTrue(ModVersionCheck.matches("1.1.24+1.21.1", "1.1.24+1.21.1+neoforge"),
                "a missing +build suffix must be tolerated");
        helper.assertTrue(ModVersionCheck.matches("1.1.24", "1.1.24+1.21.1"),
                "a build reporting no metadata at all satisfies a metadata pin");
        helper.assertTrue(!ModVersionCheck.matches("1.1.24+1.20.1", "1.1.24+1.21.1"),
                "the part before the extra +suffix must still match exactly");
        helper.assertTrue(!ModVersionCheck.matches("1.1.240", "1.1.24"),
                "a plain string prefix is not a match");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void rangeGlobAndWildcardPinsBehave(GameTestHelper helper) {
        helper.assertTrue(ModVersionCheck.matches("4.3.1", "[4.3.0,)"),
                "an open Maven range accepts a newer build");
        helper.assertTrue(!ModVersionCheck.matches("4.2.9", "[4.3.0,)"),
                "an open Maven range rejects an older build");
        helper.assertTrue(ModVersionCheck.matches("1.21.1-3.25.71.1997", "*3.25.71*"),
                "a glob pin still works");
        helper.assertTrue(ModVersionCheck.matches("anything", ModVersionCheck.ANY),
                "'*' accepts every version");
        helper.assertTrue(ModVersionCheck.matches("anything", ""),
                "an empty pin accepts every version");
        helper.assertTrue(ModVersionCheck.matches("2.26.1.0", "2.26.1"),
                "Maven-normalized padding compares equal");
        helper.assertTrue(!ModVersionCheck.matches("6.0.9", "6.0.10"),
                "a genuinely different version is still a mismatch");
        helper.assertTrue(!ModVersionCheck.matches("", "6.0.10"),
                "an unknown installed version never satisfies a pin");
        helper.succeed();
    }
}
