package de.sonic0810.goobymod.client;

import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.entity.GoobyEntity;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import software.bernie.geckolib.animation.AnimationState;
import software.bernie.geckolib.cache.object.GeoBone;
import software.bernie.geckolib.constant.DataTickets;
import software.bernie.geckolib.model.GeoModel;
import software.bernie.geckolib.model.data.EntityModelData;

public class GoobyModel extends GeoModel<GoobyEntity> {
    private static final ResourceLocation MODEL =
            ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, "geo/gooby.geo.json");
    private static final ResourceLocation BABY_MODEL =
            ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, "geo/gooby_baby.geo.json");
    private static final ResourceLocation BABY_TEXTURE =
            ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, "textures/entity/gooby_baby.png");
    private static final ResourceLocation ANIMATIONS =
            ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, "animations/gooby.animation.json");

    @Override
    public ResourceLocation getModelResource(GoobyEntity animatable) {
        return animatable.isBaby() ? BABY_MODEL : MODEL;
    }

    @Override
    public ResourceLocation getTextureResource(GoobyEntity animatable) {
        return animatable.isBaby() ? BABY_TEXTURE : animatable.getCoatVariant().texture();
    }

    @Override
    public ResourceLocation getAnimationResource(GoobyEntity animatable) {
        return ANIMATIONS;
    }

    @Override
    public void setCustomAnimations(GoobyEntity animatable, long instanceId,
            AnimationState<GoobyEntity> animationState) {
        // Kopf folgt dem Blick — ausser Gooby schlaeft oder buddelt gerade
        if (animatable.isGoobySleeping() || animatable.isDigging()) {
            animatable.resetClientHeadLook();
            return;
        }
        GeoBone head = getAnimationProcessor().getBone("head");
        if (head != null) {
            EntityModelData entityData = animationState.getData(DataTickets.ENTITY_MODEL_DATA);
            animatable.updateClientHeadLook(
                    entityData.headPitch() * Mth.DEG_TO_RAD * 0.6F,
                    entityData.netHeadYaw() * Mth.DEG_TO_RAD * 0.7F);
            head.setRotX(head.getRotX() + animatable.getClientSmoothedHeadPitch());
            head.setRotY(head.getRotY() + animatable.getClientSmoothedHeadYaw());
        }

        // Ruhigeres Wabbeln macht Text in einer aktiven Sprechblase leichter lesbar.
        if (!animatable.getBubbleKey().isEmpty() && !animationState.isMoving()) {
            GeoBone body = getAnimationProcessor().getBone("body");
            if (body != null) {
                body.setScaleX(1.0F + (body.getScaleX() - 1.0F) * 0.85F);
                body.setScaleY(1.0F + (body.getScaleY() - 1.0F) * 0.85F);
                body.setScaleZ(1.0F + (body.getScaleZ() - 1.0F) * 0.85F);
            }
        }
    }
}
