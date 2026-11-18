import UIKit

final class PhotoViewController: UIViewController, UIScrollViewDelegate {
    var onSelect: ((String, Int) -> Void)?
    private let refs: [String]
    private let photos: [UIImageView]
    private let initialIndex: Int
    private let scroller = UIScrollView()
    private let pages = UIStackView()
    private var currentIndex: Int
    private var didPosition = false

    init(refs: [String], images: [UIImage?], index: Int) {
        self.refs = refs
        photos = images.map { image in
            let view = UIImageView(image: image)
            view.contentMode = .scaleAspectFit
            return view
        }
        initialIndex = index
        currentIndex = index
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateTitle()
        view.backgroundColor = .black
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(close)
        )
        scroller.translatesAutoresizingMaskIntoConstraints = false
        scroller.isPagingEnabled = true
        scroller.showsHorizontalScrollIndicator = false
        scroller.delegate = self
        pages.translatesAutoresizingMaskIntoConstraints = false
        pages.axis = .horizontal
        for photo in photos { pages.addArrangedSubview(photo) }
        view.addSubview(scroller)
        scroller.addSubview(pages)
        NSLayoutConstraint.activate([
            scroller.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroller.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroller.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroller.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pages.topAnchor.constraint(equalTo: scroller.contentLayoutGuide.topAnchor),
            pages.bottomAnchor.constraint(equalTo: scroller.contentLayoutGuide.bottomAnchor),
            pages.leadingAnchor.constraint(equalTo: scroller.contentLayoutGuide.leadingAnchor),
            pages.trailingAnchor.constraint(equalTo: scroller.contentLayoutGuide.trailingAnchor),
            pages.heightAnchor.constraint(equalTo: scroller.frameLayoutGuide.heightAnchor),
        ])
        for photo in photos {
            photo.widthAnchor.constraint(equalTo: scroller.frameLayoutGuide.widthAnchor).isActive = true
        }
        scroller.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(close)))
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !didPosition, scroller.bounds.width > 0 else { return }
        didPosition = true
        scroller.contentOffset.x = CGFloat(initialIndex) * scroller.bounds.width
        select(initialIndex)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView.bounds.width > 0 else { return }
        select(Int((scrollView.contentOffset.x / scrollView.bounds.width).rounded()))
    }

    private func select(_ index: Int) {
        guard refs.indices.contains(index) else { return }
        currentIndex = index
        updateTitle()
        onSelect?(refs[index], index)
    }

    private func updateTitle() {
        title = refs.count > 1 ? "\(currentIndex + 1) / \(refs.count)" : NativeLanguage.text("Photo")
    }

    func show(_ image: UIImage, at index: Int) {
        guard photos.indices.contains(index) else { return }
        photos[index].image = image
    }
    @objc private func close() { dismiss(animated: true) }
}
