import SwiftUI
import UIKit

/// Spike variant B: UIKit. A vertical scroll view holding one horizontal collection view per
/// row, each with `remembersLastFocusedIndexPath`, the pattern Apple's TV app uses.
struct UIKitHomeSpike: UIViewControllerRepresentable {
    func makeUIViewController(context _: Context) -> UINavigationController {
        let navigation = UINavigationController(rootViewController: UIKitHomeViewController())
        navigation.setNavigationBarHidden(true, animated: false)
        return navigation
    }

    func updateUIViewController(_: UINavigationController, context _: Context) {}
}

final class UIKitHomeViewController: UIViewController {
    private let header = UIHostingController(rootView: SpikeHeader(item: nil))
    private var headerTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()

        addChild(header)
        header.view.translatesAutoresizingMaskIntoConstraints = false
        header.view.backgroundColor = .clear
        view.addSubview(header.view)
        header.didMove(toParent: self)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = SpikeLayout.rowSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        for row in SpikeData.rows {
            let title = UILabel()
            title.text = row.title
            title.font = .preferredFont(forTextStyle: .headline)
            stack.addArrangedSubview(title)
            stack.setCustomSpacing(8, after: title)
            stack.addArrangedSubview(
                UIKitSpikeRowView(
                    row: row,
                    onFocus: { [weak self] item in self?.didFocus(item) },
                    onSelect: { [weak self] item in self?.open(item) },
                ),
            )
        }

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.clipsToBounds = false
        scrollView.addSubview(stack)
        view.addSubview(scrollView)

        let inset = SpikeLayout.horizontalInset
        NSLayoutConstraint.activate([
            header.view.topAnchor.constraint(equalTo: view.topAnchor),
            header.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: header.view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),
        ])
    }

    private func didFocus(_ item: SpikeItem) {
        headerTask?.cancel()
        headerTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.header.rootView = SpikeHeader(item: item)
        }
    }

    private func open(_ item: SpikeItem) {
        navigationController?.pushViewController(UIHostingController(rootView: SpikeDetail(item: item)), animated: true)
    }
}

private final class UIKitSpikeRowView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    private let row: SpikeRow
    private let onFocus: (SpikeItem) -> Void
    private let onSelect: (SpikeItem) -> Void

    init(row: SpikeRow, onFocus: @escaping (SpikeItem) -> Void, onSelect: @escaping (SpikeItem) -> Void) {
        self.row = row
        self.onFocus = onFocus
        self.onSelect = onSelect
        super.init(frame: .zero)

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = SpikeLayout.posterSize
        layout.minimumLineSpacing = SpikeLayout.posterSpacing
        layout.sectionInset = UIEdgeInsets(
            top: SpikeLayout.focusPadding,
            left: 0,
            bottom: SpikeLayout.focusPadding,
            right: SpikeLayout.horizontalInset,
        )

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.clipsToBounds = false
        collectionView.remembersLastFocusedIndexPath = true
        collectionView.register(UIKitPosterCell.self, forCellWithReuseIdentifier: UIKitPosterCell.reuseID)
        collectionView.dataSource = self
        collectionView.delegate = self
        addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightAnchor.constraint(equalToConstant: SpikeLayout.posterSize.height + SpikeLayout.focusPadding * 2),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        row.items.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath,
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: UIKitPosterCell.reuseID, for: indexPath)
        (cell as? UIKitPosterCell)?.configure(with: row.items[indexPath.item])
        return cell
    }

    func collectionView(
        _: UICollectionView,
        didUpdateFocusIn context: UICollectionViewFocusUpdateContext,
        with _: UIFocusAnimationCoordinator,
    ) {
        if let indexPath = context.nextFocusedIndexPath {
            onFocus(row.items[indexPath.item])
        }
    }

    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect(row.items[indexPath.item])
    }
}

private final class UIKitPosterCell: UICollectionViewCell {
    static let reuseID = "poster"

    private let imageView = UIImageView()
    private var loadTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.frame = contentView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.backgroundColor = UIColor(white: 1, alpha: 0.1)
        imageView.adjustsImageWhenAncestorFocused = true
        contentView.addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with item: SpikeItem) {
        accessibilityIdentifier = item.id
        loadTask?.cancel()
        imageView.image = PosterImageCache.shared.cachedImage(for: item)
        guard imageView.image == nil else { return }
        loadTask = Task { [weak self] in
            let image = await PosterImageCache.shared.image(for: item)
            guard !Task.isCancelled else { return }
            self?.imageView.image = image
        }
    }
}
