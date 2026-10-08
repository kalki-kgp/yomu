// One page the reader can pinch into. UIKit, because nothing in SwiftUI zooms and pans inside a
// paging scroll view as well as a nested UIScrollView does.

import SwiftUI
import UIKit

struct ZoomablePage: UIViewRepresentable {
    let image: CGImage
    var scale: ScaleType = .fitScreen
    /// Which side a page wider than the screen opens on. Never `.automatic` by the time it gets here.
    var start: ZoomStart = .center
    /// A single tap, in unit coordinates of the screen area the page fills.
    let onTap: (CGPoint) -> Void
    var onLongPress: (() -> Void)? = nil

    func makeUIView(context: Context) -> ZoomView {
        let view = ZoomView()
        update(view)
        return view
    }

    func updateUIView(_ view: ZoomView, context: Context) {
        update(view)
    }

    private func update(_ view: ZoomView) {
        view.onTap = onTap
        view.onLongPress = onLongPress
        view.show(image, scale: scale, start: start)
    }
}

final class ZoomView: UIScrollView, UIScrollViewDelegate {
    var onTap: ((CGPoint) -> Void)?
    var onLongPress: (() -> Void)?

    private let imageView = UIImageView()
    private var shown: CGImage?
    private var scale = ScaleType.fitScreen
    private var start = ZoomStart.center
    private var laidOut = CGSize.zero

    init() {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        imageView.contentMode = .scaleToFill
        addSubview(imageView)

        let double = UITapGestureRecognizer(target: self, action: #selector(doubleTapped))
        double.numberOfTapsRequired = 2
        let single = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
        single.require(toFail: double)
        addGestureRecognizer(double)
        addGestureRecognizer(single)
        addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(longPressed)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func show(_ image: CGImage, scale: ScaleType, start: ZoomStart) {
        guard image !== shown || scale != self.scale || start != self.start else { return }
        if image !== shown { imageView.image = UIImage(cgImage: image) }
        shown = image
        self.scale = scale
        self.start = start
        place()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOut else { return }
        place()
    }

    /// Sizes the page for the scale type and puts the view at its starting corner.
    private func place() {
        guard let image = shown, bounds.width > 0, bounds.height > 0, image.width > 0, image.height > 0 else { return }
        laidOut = bounds.size
        zoomScale = 1

        let aspect = CGFloat(image.width) / CGFloat(image.height)
        let byWidth = CGSize(width: bounds.width, height: bounds.width / aspect)
        let byHeight = CGSize(width: bounds.height * aspect, height: bounds.height)
        let size: CGSize
        switch scale {
        case .fitScreen: size = byWidth.height <= bounds.height ? byWidth : byHeight
        case .stretch: size = bounds.size
        case .fitWidth: size = byWidth
        case .fitHeight: size = byHeight
        case .original:
            let density = max(traitCollection.displayScale, 1)
            size = CGSize(width: CGFloat(image.width) / density, height: CGFloat(image.height) / density)
        case .smart:
            // A spread wider than the screen fills the height and pans; anything else fills the width.
            size = aspect > bounds.width / bounds.height ? byHeight : byWidth
        }

        imageView.frame = CGRect(origin: .zero, size: size)
        contentSize = size
        centre()

        let spare = max(size.width - bounds.width, 0)
        let x: CGFloat
        switch start {
        case .left, .automatic: x = 0
        case .right: x = spare
        case .center: x = spare / 2
        }
        contentOffset = CGPoint(x: spare > 0 ? x : -contentInset.left, y: -contentInset.top)
    }

    /// Keeps a page smaller than the screen in the middle of it.
    private func centre() {
        let x = max((bounds.width - contentSize.width) / 2, 0)
        let y = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centre()
    }

    @objc private func singleTapped(_ gesture: UITapGestureRecognizer) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let point = gesture.location(in: self)
        onTap?(CGPoint(x: (point.x - contentOffset.x) / bounds.width, y: (point.y - contentOffset.y) / bounds.height))
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        if zoomScale > 1 {
            setZoomScale(1, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let size = CGSize(width: bounds.width / 2.5, height: bounds.height / 2.5)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }

    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { onLongPress?() }
    }
}
