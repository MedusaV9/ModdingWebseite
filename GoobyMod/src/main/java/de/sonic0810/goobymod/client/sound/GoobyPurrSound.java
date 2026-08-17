package de.sonic0810.goobymod.client.sound;

import de.sonic0810.goobymod.GoobyConfig;
import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.registry.ModSounds;
import java.util.HashSet;
import java.util.Set;
import net.minecraft.client.Minecraft;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.client.resources.sounds.AbstractTickableSoundInstance;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;

/** Client-local, position-bound purr that fades with the pet animation. */
public final class GoobyPurrSound extends AbstractTickableSoundInstance {
    private static final Set<Integer> ACTIVE_ENTITIES = new HashSet<>();
    private static final int DURATION_TICKS = 34;

    private final GoobyEntity gooby;
    private int age;

    private GoobyPurrSound(GoobyEntity gooby) {
        super(ModSounds.GOOBY_PURR_LOOP.get(), SoundSource.NEUTRAL, RandomSource.create());
        this.gooby = gooby;
        this.looping = true;
        this.delay = 0;
        this.pitch = 1.0F;
        this.volume = 0.0F;
        this.attenuation = Attenuation.LINEAR;
        updatePosition();
    }

    public static void playForLocalPetter(GoobyEntity gooby) {
        Minecraft minecraft = Minecraft.getInstance();
        LocalPlayer player = minecraft.player;
        if (player == null || !gooby.isBeingPettedBy(player.getUUID())
                || !ACTIVE_ENTITIES.add(gooby.getId())) {
            return;
        }
        minecraft.getSoundManager().play(new GoobyPurrSound(gooby));
    }

    @Override
    public void tick() {
        if (this.gooby.isRemoved() || ++this.age >= DURATION_TICKS) {
            ACTIVE_ENTITIES.remove(this.gooby.getId());
            stop();
            return;
        }
        updatePosition();
        float fadeIn = Mth.clamp(this.age / 5.0F, 0.0F, 1.0F);
        float fadeOut = Mth.clamp((DURATION_TICKS - this.age) / 8.0F, 0.0F, 1.0F);
        this.volume = 0.42F * Math.min(fadeIn, fadeOut) * GoobyConfig.goobyVolumeScale();
    }

    private void updatePosition() {
        this.x = this.gooby.getX();
        this.y = this.gooby.getY() + 0.8;
        this.z = this.gooby.getZ();
    }
}
