package de.sonic0810.goobymod.registry;

import de.sonic0810.goobymod.GoobyMod;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvent;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.registries.DeferredHolder;
import net.neoforged.neoforge.registries.DeferredRegister;

public final class ModSounds {
    public static final DeferredRegister<SoundEvent> SOUND_EVENTS =
            DeferredRegister.create(Registries.SOUND_EVENT, GoobyMod.MODID);

    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_SQUEAK = register("entity.gooby.squeak");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_PURR = register("entity.gooby.purr");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_BOING = register("entity.gooby.boing");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_PLOP = register("entity.gooby.plop");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_MUNCH = register("entity.gooby.munch");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_SNORE = register("entity.gooby.snore");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_AMBIENT = register("entity.gooby.ambient");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_SAD_WHIMPER =
            register("entity.gooby.sad_whimper");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_YAWN = register("entity.gooby.yawn");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_SNIFF = register("entity.gooby.sniff");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_PURR_LOOP =
            register("entity.gooby.purr_loop");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_AMBIENT_NEUTRAL =
            register("entity.gooby.ambient_neutral");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_AMBIENT_HAPPY =
            register("entity.gooby.ambient_happy");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_AMBIENT_SLEEPY =
            register("entity.gooby.ambient_sleepy");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_WHISTLE_WANDER =
            register("entity.gooby.whistle_wander");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_WHISTLE_FOLLOW =
            register("entity.gooby.whistle_follow");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_WHISTLE_STAY =
            register("entity.gooby.whistle_stay");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_BRUSH =
            register("entity.gooby.brush");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_WHINE_HUNGRY =
            register("entity.gooby.whine_hungry");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_LONELY_SIGH =
            register("entity.gooby.lonely_sigh");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_ALARM_SQUEAK =
            register("entity.gooby.alarm_squeak");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_SHAKE =
            register("entity.gooby.shake");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_TIER_UP_JINGLE =
            register("entity.gooby.tier_up_jingle");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_SNUGGLE_PURR_LONG =
            register("entity.gooby.snuggle_purr_long");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_TRICK_CHIME =
            register("entity.gooby.trick_chime");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_FLOP_THUD =
            register("entity.gooby.flop_thud");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_WHISTLE_DENIED =
            register("entity.gooby.whistle_denied");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_HUTCH_RUSTLE =
            register("entity.gooby.hutch_rustle");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_HUTCH_CREAK =
            register("entity.gooby.hutch_creak");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_BABY_SQUEAK =
            register("entity.gooby.baby_squeak");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_NUZZLE =
            register("entity.gooby.nuzzle");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_DRESS_UP =
            register("entity.gooby.dress_up");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_WILD_CALL =
            register("entity.gooby.wild_call");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_CHIRP_SOCIAL =
            register("entity.gooby.chirp_social");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_SNIFF_LONG =
            register("entity.gooby.sniff_long");
    public static final DeferredHolder<SoundEvent, SoundEvent> GOOBY_MAP_RUSTLE =
            register("entity.gooby.map_rustle");

    private static DeferredHolder<SoundEvent, SoundEvent> register(String name) {
        return SOUND_EVENTS.register(name, () -> SoundEvent.createVariableRangeEvent(
                ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, name)));
    }

    public static void register(IEventBus bus) {
        SOUND_EVENTS.register(bus);
    }

    private ModSounds() {
    }
}
