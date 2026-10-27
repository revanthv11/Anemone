import QuartzCore

/// The layer libmpv draws in. MoltenVK briefly sets the drawable size to 1×1 to finish a
/// presentation, which can leave the video flickering or stuck at that size, so such sizes are
/// ignored. From MPVKit's demo (`MetalLayer`, LGPL-3.0), after mpv-player/mpv#13651.
final class MPVMetalLayer: CAMetalLayer {
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            if Int(newValue.width) > 1, Int(newValue.height) > 1 {
                super.drawableSize = newValue
            }
        }
    }
}
