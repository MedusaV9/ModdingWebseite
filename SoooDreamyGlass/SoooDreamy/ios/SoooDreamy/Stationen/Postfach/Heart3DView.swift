import SwiftUI
import SceneKit

/// The 3D beating heart — SceneKit, fully procedural (geometry, materials,
/// particles are all generated in code).
///
/// Reduce Motion (commandment 13): the endless lub-dub pulse, the sway and
/// the ambient particle drizzle are ornamental choreography — under the
/// system switch the heart holds still as a lit sculpture (and the SCNView
/// stops its render loop entirely), exactly like the aurora freezes in
/// `DreamyBackground`. The tap burst is muted too: a particle shower is
/// the opposite of "reduce motion".
///
/// The same gate also honors Low Power Mode (a battery saver must not run
/// a SceneKit loop) and the caller's scroll-visibility flag (the dashboard
/// coda sits below the fold — no rendering before it was ever seen, and
/// none while it is scrolled away; re-entry restarts the choreography).
struct Heart3DView: UIViewRepresentable {
    /// Increment to trigger a celebratory burst (e.g. on tap).
    var burstTrigger: Int = 0
    /// Scroll-visibility gate, driven by the host (`onScrollVisibilityChange`).
    var isVisible: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        // An ornament never needs 60/120 Hz — half rate is invisible on a
        // slow lub-dub pulse and halves the GPU wake-ups.
        view.preferredFramesPerSecond = 30
        view.isPlaying = true
        view.allowsCameraControl = false

        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        view.scene = scene

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 7.5)
        scene.rootNode.addChildNode(cameraNode)

        // Lights
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 420
        ambient.light?.color = UIColor(red: 1.0, green: 0.85, blue: 0.95, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.intensity = 950
        key.light?.color = UIColor(red: 1.0, green: 0.9, blue: 1.0, alpha: 1)
        key.position = SCNVector3(4, 6, 9)
        scene.rootNode.addChildNode(key)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .omni
        rim.light?.intensity = 450
        rim.light?.color = UIColor(red: 0.7, green: 0.4, blue: 1.0, alpha: 1)
        rim.position = SCNVector3(-5, -3, 6)
        scene.rootNode.addChildNode(rim)

        // Heart
        let heartNode = SCNNode(geometry: Self.heartGeometry())
        heartNode.scale = SCNVector3(1, 1, 1)
        scene.rootNode.addChildNode(heartNode)

        // Ambient floating hearts (birth rate driven by the motion gate).
        let ambientParticles = Self.particles(birthRate: 2.2, size: 0.16)
        let emitterNode = SCNNode()
        emitterNode.position = SCNVector3(0, -2.4, 0)
        emitterNode.addParticleSystem(ambientParticles)
        scene.rootNode.addChildNode(emitterNode)

        context.coordinator.view = view
        context.coordinator.scene = scene
        context.coordinator.heartNode = heartNode
        context.coordinator.ambientParticles = ambientParticles
        context.coordinator.lastBurst = burstTrigger
        context.coordinator.reduceMotion = reduceMotion
        context.coordinator.visible = isVisible
        context.coordinator.refreshAmbientMotion()
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // React to the system switches live — neither toggle must need an
        // app restart to calm the dashboard.
        context.coordinator.reduceMotion = reduceMotion
        context.coordinator.visible = isVisible
        context.coordinator.refreshAmbientMotion()
        if context.coordinator.lastBurst != burstTrigger {
            context.coordinator.lastBurst = burstTrigger
            context.coordinator.burst()
        }
    }

    final class Coordinator {
        weak var view: SCNView?
        var scene: SCNScene?
        var heartNode: SCNNode?
        var ambientParticles: SCNParticleSystem?
        var lastBurst = 0
        var reduceMotion = false
        var visible = true
        private var motionEnabled: Bool?
        /// Mirrors `ProcessInfo.processInfo.isLowPowerModeEnabled`; refreshed
        /// via notification because power state is not observable directly
        /// (same pattern as `DreamyBackground` in UI/Theme.swift).
        private var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        private var powerObserver: NSObjectProtocol?

        private static let heartbeatKey = "heartbeat"
        private static let swayKey = "sway"

        init() {
            powerObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name.NSProcessInfoPowerStateDidChange,
                object: nil, queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
                self.refreshAmbientMotion()
            }
        }

        deinit {
            if let powerObserver {
                NotificationCenter.default.removeObserver(powerObserver)
            }
        }

        /// One gate for all three calm reasons: Reduce Motion, Low Power
        /// Mode, and "the coda is not on screen".
        func refreshAmbientMotion() {
            setAmbientMotion(!reduceMotion && !lowPowerMode && visible)
        }

        /// Starts/stops the ornamental choreography (pulse, sway, ambient
        /// drizzle) — idempotent, so `updateUIView` may call it every pass.
        private func setAmbientMotion(_ enabled: Bool) {
            guard motionEnabled != enabled else { return }
            motionEnabled = enabled
            ambientParticles?.birthRate = enabled ? 2.2 : 0
            // No choreography → no reason to keep the render loop awake.
            view?.isPlaying = enabled
            guard let heartNode else { return }
            guard enabled else {
                heartNode.removeAction(forKey: Self.heartbeatKey)
                heartNode.removeAction(forKey: Self.swayKey)
                // Settle facing forward — rotateBy is relative, so a
                // mid-sway stop would freeze the heart askew.
                heartNode.scale = SCNVector3(1, 1, 1)
                heartNode.eulerAngles = SCNVector3(0, 0, 0)
                return
            }

            // Heartbeat: lub-dub pulse
            let lub = SCNAction.scale(to: 1.09, duration: 0.14)
            lub.timingMode = .easeOut
            let back1 = SCNAction.scale(to: 1.0, duration: 0.16)
            let dub = SCNAction.scale(to: 1.05, duration: 0.12)
            dub.timingMode = .easeOut
            let back2 = SCNAction.scale(to: 1.0, duration: 0.2)
            let rest = SCNAction.wait(duration: 0.75)
            heartNode.runAction(.repeatForever(.sequence([lub, back1, dub, back2, rest])),
                                forKey: Self.heartbeatKey)

            // Gentle sway
            let swayRight = SCNAction.rotateBy(x: 0, y: 0.5, z: 0, duration: 2.6)
            swayRight.timingMode = .easeInEaseOut
            let swayLeft = SCNAction.rotateBy(x: 0, y: -1.0, z: 0, duration: 5.2)
            swayLeft.timingMode = .easeInEaseOut
            let swayBack = SCNAction.rotateBy(x: 0, y: 0.5, z: 0, duration: 2.6)
            swayBack.timingMode = .easeInEaseOut
            heartNode.runAction(.repeatForever(.sequence([swayRight, swayLeft, swayBack])),
                                forKey: Self.swayKey)
        }

        func burst() {
            // Reduce Motion: the tap still lands (haptic/state elsewhere),
            // but a scale pop + particle shower is exactly the choreography
            // the switch asks us to skip.
            guard motionEnabled == true else { return }
            guard let scene, let heartNode else { return }
            let pop = SCNAction.sequence([
                SCNAction.scale(to: 1.24, duration: 0.12),
                SCNAction.scale(to: 1.0, duration: 0.3)
            ])
            pop.timingMode = .easeInEaseOut
            heartNode.runAction(pop)

            let burstNode = SCNNode()
            burstNode.position = SCNVector3(0, -0.5, 0.5)
            let system = Heart3DView.particles(birthRate: 90, size: 0.22)
            system.emissionDuration = 0.35
            system.loops = false
            burstNode.addParticleSystem(system)
            scene.rootNode.addChildNode(burstNode)
            burstNode.runAction(.sequence([.wait(duration: 4), .removeFromParentNode()]))
        }
    }

    // MARK: Geometry

    private static func heartGeometry() -> SCNGeometry {
        let path = UIBezierPath()
        let steps = 160
        let scale: CGFloat = 0.115
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
            let x = 16 * pow(sin(t), 3) * scale
            let y = (13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)) * scale
            let pt = CGPoint(x: x, y: y)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.close()
        path.flatness = 0.05

        let shape = SCNShape(path: path, extrusionDepth: 0.85)
        shape.chamferRadius = 0.12

        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(red: 1.0, green: 0.32, blue: 0.52, alpha: 1)
        material.emission.contents = UIColor(red: 0.55, green: 0.05, blue: 0.25, alpha: 1)
        material.metalness.contents = 0.15
        material.roughness.contents = 0.28
        shape.materials = [material]
        return shape
    }

    // MARK: Particles

    static func particles(birthRate: CGFloat, size: CGFloat) -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.birthRate = birthRate
        system.particleLifeSpan = 3.6
        system.particleLifeSpanVariation = 1.0
        system.particleVelocity = 1.4
        system.particleVelocityVariation = 0.7
        system.emittingDirection = SCNVector3(0, 1, 0)
        system.spreadingAngle = 55
        system.particleSize = size
        system.particleSizeVariation = size * 0.4
        system.particleImage = heartSpriteImage()
        system.particleColor = UIColor(red: 1.0, green: 0.5, blue: 0.7, alpha: 0.9)
        system.particleColorVariation = SCNVector4(0.12, 0.1, 0.15, 0.1)
        system.blendMode = .additive
        system.particleAngularVelocity = 40
        system.particleAngularVelocityVariation = 60
        system.acceleration = SCNVector3(0, 0.35, 0)
        system.emitterShape = SCNSphere(radius: 1.4)
        return system
    }

    /// Draws a tiny heart sprite in code (no bundled image assets).
    private static func heartSpriteImage() -> UIImage {
        let side: CGFloat = 64
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { ctx in
            let path = UIBezierPath()
            let steps = 80
            let scale: CGFloat = 1.7
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
                let x = 16 * pow(sin(t), 3) * scale + side / 2
                let y = -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)) * scale + side / 2
                let pt = CGPoint(x: x, y: y)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            path.close()
            UIColor.white.setFill()
            path.fill()
            _ = ctx // silence unused warning paranoia
        }
    }
}
