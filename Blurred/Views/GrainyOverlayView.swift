//
//  GrainyOverlayView.swift
//  Blurred
//
//  Composites three layers for the grainy blur effect:
//  1. NSVisualEffectView — behind-window blur (handled by WindowServer)
//  2. Dim layer — semi-transparent black (existing dimming behaviour)
//  3. Grain layer — tiled noise texture with overlay blend mode
//
//  Ongoing GPU cost: just Core Animation compositing (~2-5% on Apple Silicon).
//  Metal is only used for the one-time texture generation.
//

import Cocoa

/// NSView subclass that guarantees its layer background color is set
/// after AppKit creates the backing layer (not before, as layer? would be nil).
private final class DimLayerView: NSView {
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = NSColor.black.cgColor
    }
}

final class GrainyOverlayView: NSView {

    private let visualEffectView = NSVisualEffectView()
    private let dimView = DimLayerView()
    private var grainLayer: CALayer?
    private var grainLayerInstalled = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }

    // MARK: - Public API

    func updateDimAlpha(_ alpha: CGFloat) {
        dimView.alphaValue = alpha
    }

    func updateGrainIntensity(_ intensity: CGFloat) {
        let hasGrain = intensity > 0
        grainLayer?.opacity = Float(intensity)
        visualEffectView.isHidden = !hasGrain
    }

    // MARK: - Setup

    private func setupLayers() {
        wantsLayer = true

        // 1. Behind-window blur (compositor-managed, not our GPU budget)
        visualEffectView.material = .fullScreenUI
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.appearance = NSAppearance(named: .darkAqua)
        visualEffectView.isHidden = true  // shown when grain > 0
        visualEffectView.frame = bounds
        visualEffectView.autoresizingMask = [.width, .height]
        addSubview(visualEffectView)

        // 2. Dim overlay (replaces the old backgroundColor approach)
        dimView.wantsLayer = true
        dimView.frame = bounds
        dimView.autoresizingMask = [.width, .height]
        addSubview(dimView)
    }

    // Install grain sublayer once the backing layer exists.
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if !grainLayerInstalled, superview != nil {
            setupGrainLayer()
            grainLayerInstalled = true
        }
    }

    private func setupGrainLayer() {
        guard let grainImage = GrainTextureGenerator.grainImage() else { return }

        let tileSize = NSSize(width: CGFloat(grainImage.width), height: CGFloat(grainImage.height))
        let nsImage = NSImage(cgImage: grainImage, size: tileSize)
        let patternColor = NSColor(patternImage: nsImage)

        let grain = CALayer()
        grain.frame = bounds
        grain.backgroundColor = patternColor.cgColor
        grain.compositingFilter = "overlayBlendMode"
        grain.opacity = 0
        grain.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        // Add on top of all subviews
        layer?.addSublayer(grain)
        grainLayer = grain
    }

    override func layout() {
        super.layout()
        grainLayer?.frame = bounds
    }
}
