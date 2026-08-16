package de.sonic0810.goobymod.gametest;

import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.compat.CreateCompat;
import de.sonic0810.goobymod.compat.CreateRetryPolicy;
import de.sonic0810.goobymod.registry.ModItems;
import java.util.concurrent.atomic.AtomicInteger;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * Create-runtime-only suite. Its separate namespace prevents Create from
 * sending negotiated payloads to vanilla GameTest mock players used elsewhere.
 */
@GameTestHolder("goobymod_create")
@PrefixGameTestTemplate(false)
public final class CreateGameTests {
    private static final String ARENA = "arena";

    /** Initial call plus three delayed retries recovers from transient integration exceptions. */
    @GameTest(template = ARENA)
    public static void transient_degrade_recovers(GameTestHelper helper) {
        CreateRetryPolicy policy = new CreateRetryPolicy();
        AtomicInteger calls = new AtomicInteger();
        CreateRetryPolicy.Operation flaky = () -> {
            if (calls.getAndIncrement() < 3) {
                throw new IllegalStateException("simulated transient Create tick");
            }
            return true;
        };

        helper.assertFalse(policy.execute(0, flaky), "Erster transienter Fehler wurde nicht abgefangen");
        helper.assertFalse(policy.execute(0, flaky), "Backoff liess sofortigen Retry durch");
        helper.assertTrue(calls.get() == 1 && policy.retryAtTick() == 1,
                "Erster Backoff oder Aufrufzaehler ist falsch");
        helper.assertFalse(policy.execute(1, flaky), "Erster Retry sollte simuliert scheitern");
        helper.assertFalse(policy.execute(3, flaky), "Zweiter Retry sollte simuliert scheitern");
        helper.assertTrue(policy.execute(7, flaky), "Dritter Retry erholte sich nicht");
        helper.assertTrue(policy.state() == CreateRetryPolicy.State.ACTIVE
                        && policy.attempts() == 0 && calls.get() == 4,
                "Erfolgreicher Retry setzte den Zustand nicht vollstaendig zurueck");
        helper.succeed();
    }

    /** Conditional processing recipe is registered by Create and produces the Gooby jar. */
    @GameTest(template = ARENA)
    public static void mixer_nutella_recipe(GameTestHelper helper) {
        helper.assertTrue(CreateCompat.isCreateLoaded(), "Create-Suite startete ohne Create");
        ResourceLocation mixingId =
                ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, "create/mixing_nutella");
        var recipe = helper.getLevel().getRecipeManager().byKey(mixingId);
        helper.assertTrue(recipe.isPresent(), "Create-Mixer-Rezept wurde nicht registriert");
        helper.assertTrue(recipe.get().value().getResultItem(helper.getLevel().registryAccess())
                        .is(ModItems.NUTELLA.get()),
                "Create-Mixer-Rezept erzeugt kein Nutella-Glas");
        helper.assertTrue("create:mixing".equals(BuiltInRegistries.RECIPE_SERIALIZER
                        .getKey(recipe.get().value().getSerializer()).toString()),
                "Create-Mixer-Rezept verwendet den falschen Serializer");
        helper.succeed();
    }

    /** Create's GameTestServer lacks the seat networking lifecycle, so it must fail closed. */
    @GameTest(template = ARENA)
    public static void contraption_seat_headless_gate(GameTestHelper helper) {
        helper.assertTrue(CreateCompat.isCreateLoaded(), "Create-Suite startete ohne Create");
        helper.assertFalse(CreateCompat.isSeatIntegrationAvailable(),
                "Create-Sitzintegration war auf dem headless GameTestServer aktiv");
        helper.succeed();
    }

    private CreateGameTests() {
    }
}
