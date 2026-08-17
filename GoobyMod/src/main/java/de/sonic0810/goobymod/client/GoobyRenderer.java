package de.sonic0810.goobymod.client;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;
import com.mojang.math.Axis;
import de.sonic0810.goobymod.GoobyClientConfig;
import de.sonic0810.goobymod.GoobyConfig;
import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.entity.GoobySpeech;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.RenderType;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.minecraft.client.renderer.texture.OverlayTexture;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.FormattedCharSequence;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.item.ItemDisplayContext;
import net.minecraft.world.item.ItemStack;
import org.joml.Matrix4f;
import software.bernie.geckolib.cache.object.BakedGeoModel;
import software.bernie.geckolib.cache.object.GeoBone;
import software.bernie.geckolib.renderer.GeoEntityRenderer;
import software.bernie.geckolib.renderer.layer.BlockAndItemGeoLayer;

public class GoobyRenderer extends GeoEntityRenderer<GoobyEntity> {
    private static final ResourceLocation BUBBLE_TEXTURE =
            ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, "textures/misc/speech_bubble.png");
    private static final ResourceLocation ICON_FONT =
            ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, "icons");
    private static final int TEXT_COLOR = 0xFF5C3A21;
    private static final int MAX_TEXT_WIDTH = 110;
    private static final String HAT_ANCHOR_BONE = "hat_anchor";
    private static final String NECK_ANCHOR_BONE = "neck_anchor";
    private static final String BACK_ANCHOR_BONE = "back_anchor";
    private static final String MOUTH_ANCHOR_BONE = "mouth_anchor";
    private final Map<Integer, BubbleVisual> bubbleVisuals = new HashMap<>();

    private static final class BubbleVisual {
        private String key = "";
        private String argument = "";
        private float firstSeen;
        private float lastSeen;
    }

    public GoobyRenderer(EntityRendererProvider.Context context) {
        super(context, new GoobyModel());
        this.shadowRadius = 0.65F;
        addRenderLayer(new WardrobeLayer(this));
    }

    /** Three-slot wardrobe layer; accessory item models are true 3D shapes. */
    private static final class WardrobeLayer extends BlockAndItemGeoLayer<GoobyEntity> {
        private WardrobeLayer(GoobyRenderer renderer) {
            super(renderer);
        }

        @Override
        protected ItemStack getStackForBone(GeoBone bone, GoobyEntity gooby) {
            // Der Apportier-Ball haengt am Maul-Anker beider Geos — auch beim
            // Baby (das Feature startet fuer Babys nie, aber ein per Save
            // hereingetragener Ball darf niemals unsichtbar verschwinden).
            if (MOUTH_ANCHOR_BONE.equals(bone.getName())) {
                return gooby.getCarriedFetchItem();
            }
            if (gooby.isBaby()) {
                return ItemStack.EMPTY;
            }
            return switch (bone.getName()) {
                case HAT_ANCHOR_BONE -> gooby.getHatStack();
                case NECK_ANCHOR_BONE -> gooby.getNeckStack();
                case BACK_ANCHOR_BONE -> gooby.getBackStack();
                default -> ItemStack.EMPTY;
            };
        }

        @Override
        protected ItemDisplayContext getTransformTypeForStack(GeoBone bone, ItemStack stack, GoobyEntity gooby) {
            return ItemDisplayContext.GROUND;
        }

        @Override
        protected void renderStackForBone(PoseStack poseStack, GeoBone bone, ItemStack stack, GoobyEntity gooby,
                MultiBufferSource bufferSource, float partialTick, int packedLight, int packedOverlay) {
            poseStack.pushPose();
            if (HAT_ANCHOR_BONE.equals(bone.getName())) {
                poseStack.scale(1.2F, 1.2F, 1.2F);
            } else if (NECK_ANCHOR_BONE.equals(bone.getName())) {
                poseStack.mulPose(Axis.XP.rotationDegrees(90.0F));
                poseStack.scale(0.72F, 0.72F, 0.72F);
            } else if (BACK_ANCHOR_BONE.equals(bone.getName())) {
                poseStack.mulPose(Axis.XP.rotationDegrees(90.0F));
                poseStack.scale(0.82F, 0.82F, 0.82F);
            } else if (MOUTH_ANCHOR_BONE.equals(bone.getName())) {
                poseStack.scale(0.62F, 0.62F, 0.62F);
            }
            super.renderStackForBone(poseStack, bone, stack, gooby, bufferSource, partialTick, packedLight,
                    packedOverlay);
            poseStack.popPose();
        }
    }

    @Override
    public void preRender(PoseStack poseStack, GoobyEntity entity, BakedGeoModel model,
            MultiBufferSource bufferSource, VertexConsumer buffer, boolean isReRender,
            float partialTick, int packedLight, int packedOverlay, int renderColor) {
        if (entity.isBaby()) {
            poseStack.scale(0.55F, 0.55F, 0.55F);
        }
        super.preRender(poseStack, entity, model, bufferSource, buffer, isReRender,
                partialTick, packedLight, packedOverlay, renderColor);
    }

    @Override
    public void render(GoobyEntity entity, float entityYaw, float partialTick, PoseStack poseStack,
            MultiBufferSource bufferSource, int packedLight) {
        entity.markClientRendered();
        if (entity.tickCount % 200 == 0 && this.bubbleVisuals.size() > 64) {
            this.bubbleVisuals.keySet().removeIf(id -> entity.level().getEntity(id) == null);
        }
        super.render(entity, entityYaw, partialTick, poseStack, bufferSource, packedLight);
        renderSpeechBubble(entity, partialTick, poseStack, bufferSource, packedLight);
    }

    /**
     * Sprechblase ueber Goobys Kopf: Billboard, mehrzeilig, gut lesbar.
     * Blasen-Textur (mit Schwaenzchen) + Text in Nutella-Braun.
     */
    private void renderSpeechBubble(GoobyEntity entity, float partialTick, PoseStack poseStack,
            MultiBufferSource bufferSource, int packedLight) {
        float now = entity.tickCount + partialTick;
        String liveKey = entity.getBubbleKey();
        BubbleVisual visual = this.bubbleVisuals.get(entity.getId());
        if (!liveKey.isEmpty()) {
            if (visual == null) {
                visual = new BubbleVisual();
                this.bubbleVisuals.put(entity.getId(), visual);
            }
            if (!liveKey.equals(visual.key)) {
                visual.key = liveKey;
                visual.argument = entity.getBubbleArgument();
                visual.firstSeen = now;
            }
            visual.lastSeen = now;
        } else if (visual == null || now - visual.lastSeen > 5.0F) {
            this.bubbleVisuals.remove(entity.getId());
            return;
        }
        String key = visual.key;
        float bubbleDistance = GoobyConfig.bubbleDistance();
        if (entity.isInvisible()
                || this.entityRenderDispatcher.distanceToSqr(entity) > bubbleDistance * bubbleDistance) {
            return;
        }
        if (Minecraft.getInstance().getCameraEntity() instanceof LivingEntity viewer
                && !viewer.hasLineOfSight(entity)) {
            return;
        }
        // Special-Lines sind eine rein LOKALE kosmetische Blase: sie erscheinen nur
        // auf dem Bildschirm des Besitzer-Spielers selbst, nie bei Umstehenden
        // (eingebauter Sophie-Default und Datapack-Pools gleichermassen).
        String specialOwner = GoobySpeech.specialLineOwner(key);
        if (specialOwner != null) {
            LocalPlayer localPlayer = Minecraft.getInstance().player;
            if (localPlayer == null
                    || !specialOwner.equalsIgnoreCase(localPlayer.getGameProfile().getName())) {
                return;
            }
        }
        Font font = Minecraft.getInstance().font;
        Component text = (visual.argument.isEmpty()
                ? Component.translatable(key) : Component.translatable(key, visual.argument))
                .withStyle(style -> style.withFont(ICON_FONT));
        List<FormattedCharSequence> lines = font.split(text, MAX_TEXT_WIDTH);
        if (lines.isEmpty()) {
            return;
        }
        int textWidth = 0;
        for (FormattedCharSequence line : lines) {
            textWidth = Math.max(textWidth, font.width(line));
        }
        int lineHeight = 10;
        int padding = 5;
        int panelWidth = textWidth + padding * 2;
        int panelHeight = lines.size() * lineHeight + padding * 2 - 2;
        int tailHeight = 7;
        boolean reducedMotion = GoobyClientConfig.reducedMotion();
        boolean highContrast = GoobyClientConfig.highContrastBubbles();
        float popScale = reducedMotion ? 1.0F : liveKey.isEmpty()
                ? Mth.clamp(1.0F - (now - visual.lastSeen) / 5.0F, 0.0F, 1.0F)
                : Mth.clamp((now - visual.firstSeen) / 5.0F, 0.05F, 1.0F);

        poseStack.pushPose();
        float bubbleBottom = entity.getBbHeight() + 0.42F + Math.floorMod(entity.getId(), 3) * 0.11F;
        poseStack.translate(0.0F, bubbleBottom, 0.0F);
        poseStack.mulPose(this.entityRenderDispatcher.cameraOrientation());
        poseStack.scale(0.025F * popScale, -0.025F * popScale, 0.025F * popScale);

        // Im Billboard-Raum zeigt -Y nach oben (Y ist gespiegelt); Panel oberhalb des Ankers
        float left = -panelWidth / 2.0F;
        float top = -(tailHeight + panelHeight);
        LivingEntity addressed = entity.level().getNearestPlayer(entity, 12.0);
        float tailOffset = reducedMotion || addressed == null ? 0.0F
                : Mth.clamp((float) (addressed.getX() - entity.getX()) * 2.0F,
                        -panelWidth * 0.28F, panelWidth * 0.28F);

        Matrix4f pose = poseStack.last().pose();
        VertexConsumer buffer = bufferSource.getBuffer(RenderType.entityTranslucent(BUBBLE_TEXTURE));
        // Blasen-Koerper (Textur-Bereich 0..64 x 0..47, gestreckt)
        drawQuad(buffer, pose, left, top, left + panelWidth, top + panelHeight,
                0.0F, 0.0F, 1.0F, 47.0F / 64.0F, packedLight, highContrast);
        // Schwaenzchen (Textur-Bereich 24..40 x 48..62, fixe Groesse, mittig unten)
        drawQuad(buffer, pose, tailOffset - 8.0F, top + panelHeight - 0.5F,
                tailOffset + 8.0F, top + panelHeight + tailHeight,
                24.0F / 64.0F, 48.0F / 64.0F, 40.0F / 64.0F, 62.0F / 64.0F,
                packedLight, highContrast);

        // Text VOR die Blase ruecken: im Billboard-Raum (nach cameraOrientation +
        // Y-Spiegelung) zeigt +Z ZUR Kamera — der alte -0.03-Offset schob den Text
        // HINTER die Blase, wo ihn der Depth-Test verschluckte (leere Blasen!).
        poseStack.translate(0.0F, 0.0F, 0.5F);
        Matrix4f textPose = poseStack.last().pose();
        float textY = top + padding - 1;
        for (FormattedCharSequence line : lines) {
            float textX = -font.width(line) / 2.0F;
            font.drawInBatch(line, textX, textY, highContrast ? 0xFF160D08 : TEXT_COLOR,
                    false, textPose, bufferSource,
                    Font.DisplayMode.NORMAL, 0, packedLight);
            textY += lineHeight;
        }
        poseStack.popPose();
    }

    private static void drawQuad(VertexConsumer buffer, Matrix4f pose, float x0, float y0, float x1, float y1,
            float u0, float v0, float u1, float v1, int packedLight, boolean highContrast) {
        int red = highContrast ? 255 : 255;
        int green = highContrast ? 244 : 255;
        int blue = highContrast ? 204 : 255;
        int alpha = highContrast ? 255 : 250;
        buffer.addVertex(pose, x0, y1, 0.0F).setColor(red, green, blue, alpha).setUv(u0, v1)
                .setOverlay(OverlayTexture.NO_OVERLAY).setLight(packedLight).setNormal(0.0F, 0.0F, -1.0F);
        buffer.addVertex(pose, x1, y1, 0.0F).setColor(red, green, blue, alpha).setUv(u1, v1)
                .setOverlay(OverlayTexture.NO_OVERLAY).setLight(packedLight).setNormal(0.0F, 0.0F, -1.0F);
        buffer.addVertex(pose, x1, y0, 0.0F).setColor(red, green, blue, alpha).setUv(u1, v0)
                .setOverlay(OverlayTexture.NO_OVERLAY).setLight(packedLight).setNormal(0.0F, 0.0F, -1.0F);
        buffer.addVertex(pose, x0, y0, 0.0F).setColor(red, green, blue, alpha).setUv(u0, v0)
                .setOverlay(OverlayTexture.NO_OVERLAY).setLight(packedLight).setNormal(0.0F, 0.0F, -1.0F);
    }
}
