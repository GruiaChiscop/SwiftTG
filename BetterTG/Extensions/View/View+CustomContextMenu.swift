// View+CustomContextMenu.swift

import SwiftUI

// MARK: - ContextMenuAction

enum ContextMenuAction {
    case divider
    case button(title: String, systemImage: String, attributes: UIMenuElement.Attributes = [], action: () -> Void)
    case menu(title: String, systemImage: String? = nil, children: [ContextMenuAction])
}

extension [ContextMenuAction] {
    func flattened() -> [(title: String, action: () -> Void)] {
        flatMap { action -> [(title: String, action: () -> Void)] in
            switch action {
            case .divider:
                []
            case .button(let title, _, _, let handler):
                [(title, handler)]
            case .menu(_, _, let children):
                children.flattened()
            }
        }
    }

    func uiMenu(title: String = "", systemImage: String? = nil) -> UIMenu {
        var elements = [UIMenuElement]()
        for action in self {
            switch action {
            case .divider:
                let children = elements
                elements.removeAll()
                elements.append(UIMenu(options: .displayInline, children: children))
            case .button(let title, let systemImage, let attributes, let action):
                elements.append(
                    UIAction(
                        title: title,
                        image: UIImage(systemName: systemImage),
                        attributes: attributes,
                        handler: { _ in action() },
                    ),
                )
            case .menu(let title, let systemImage, let children):
                elements.append(children.uiMenu(title: title, systemImage: systemImage))
            }
        }
        if let systemImage {
            return UIMenu(title: title, image: UIImage(systemName: systemImage), children: elements)
        } else {
            return UIMenu(title: title, children: elements)
        }
    }
}

// MARK: - ContextMenuActionsView

private struct ContextMenuActionsView: View {
    let actions: [ContextMenuAction]
    
    var body: some View {
        ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
            ContextMenuActionItemView(action: action)
        }
    }
}

// MARK: - ContextMenuActionItemView

private struct ContextMenuActionItemView: View {
    let action: ContextMenuAction
    
    var body: some View {
        switch action {
        case .divider:
            Divider()
        case .button(let title, let systemImage, let attributes, let action):
            if !attributes.contains(.hidden) {
                if attributes.contains(.destructive) {
                    Button(role: .destructive, action: action) {
                        Label(title, systemImage: systemImage)
                    }
                    .disabled(attributes.contains(.disabled))
                } else {
                    Button(action: action) {
                        Label(title, systemImage: systemImage)
                    }
                    .disabled(attributes.contains(.disabled))
                }
            }
        case .menu(let title, let systemImage, let children):
            if let systemImage {
                Menu {
                    children.contextMenuContent()
                } label: {
                    Label(title, systemImage: systemImage)
                }
            } else {
                Menu(title) {
                    children.contextMenuContent()
                }
            }
        }
    }
}

extension [ContextMenuAction] {
    func contextMenuContent() -> some View {
        ContextMenuActionsView(actions: self)
    }
}

extension View {
    func customContextMenu(
        cornerRadius: CGFloat = 0,
        _ actions: [ContextMenuAction] = [],
        didTapPreview: (() -> Void)? = nil,
        onAppear: @escaping () -> Void = {},
        onDisappear: @escaping () -> Void = {},
    ) -> some View {
        hidden()
            .overlay {
                CustomContextMenuView(
                    cornerRadius: cornerRadius,
                    menu: actions.uiMenu(),
                    content: self,
                    preview: self,
                    didTapPreview: didTapPreview,
                    onAppear: onAppear,
                    onDisappear: onDisappear,
                )
            }
    }
    
    func customContextMenu(
        cornerRadius: CGFloat = 0,
        _ actions: [ContextMenuAction] = [],
        @ViewBuilder _ preview: () -> some View,
        didTapPreview: (() -> Void)? = nil,
        onAppear: @escaping () -> Void = {},
        onDisappear: @escaping () -> Void = {},
    ) -> some View {
        hidden()
            .overlay {
                CustomContextMenuView(
                    cornerRadius: cornerRadius,
                    menu: actions.uiMenu(),
                    content: self,
                    preview: preview(),
                    didTapPreview: didTapPreview,
                    onAppear: onAppear,
                    onDisappear: onDisappear,
                )
            }
    }
}

// MARK: - CustomContextMenuView

private struct CustomContextMenuView<Content: View, Preview: View>: UIViewRepresentable {
    final class Coordinator: NSObject, UIContextMenuInteractionDelegate {
        // MARK: Lifecycle

        init(
            cornerRadius: CGFloat,
            menu: UIMenu,
            content: Content,
            preview: Preview,
            didTapPreview: (() -> Void)?,
            onAppear: @escaping () -> Void,
            onDisappear: @escaping () -> Void,
        ) {
            self.cornerRadius = cornerRadius
            self.menu = menu
            self.content = content
            self.preview = preview
            self.didTapPreview = didTapPreview
            self.onAppear = onAppear
            self.onDisappear = onDisappear
        }

        // MARK: Internal

        var cornerRadius: CGFloat
        var menu: UIMenu
        var content: Content
        var preview: Preview
        var didTapPreview: (() -> Void)?
        var onAppear: () -> Void
        var onDisappear: () -> Void
        weak var hostingController: UIHostingController<Content>?
        
        func contextMenuInteraction(
            _: UIContextMenuInteraction,
            configurationForMenuAtLocation _: CGPoint,
        ) -> UIContextMenuConfiguration? {
            UIContextMenuConfiguration(
                identifier: nil,
                previewProvider: { [weak self] () -> UIViewController? in
                    guard let self else { return nil }
                    return PreviewHostingController(
                        rootView: preview,
                        cornerRadius: cornerRadius,
                        onAppear: onAppear,
                        onDisappear: onDisappear,
                    )
                },
                actionProvider: { [weak self] _ in
                    self?.menu ?? nil
                },
            )
        }
        
        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            previewForHighlightingMenuWithConfiguration _: UIContextMenuConfiguration,
        ) -> UITargetedPreview? {
            guard let view = interaction.view else { return nil }
            return UITargetedPreview(view: view, parameters: UIPreviewParameters(backgroundColor: .clear))
        }
        
        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            previewForDismissingMenuWithConfiguration _: UIContextMenuConfiguration,
        ) -> UITargetedPreview? {
            guard let view = interaction.view else { return nil }
            return UITargetedPreview(view: view, parameters: UIPreviewParameters(backgroundColor: .clear))
        }
        
        func contextMenuInteraction(
            _: UIContextMenuInteraction,
            willPerformPreviewActionForMenuWith _: UIContextMenuConfiguration,
            animator: UIContextMenuInteractionCommitAnimating,
        ) {
            if let didTapPreview {
                animator.addCompletion(didTapPreview)
            }
        }
    }

    let cornerRadius: CGFloat
    let menu: UIMenu
    let content: Content
    let preview: Preview
    let didTapPreview: (() -> Void)?
    let onAppear: () -> Void
    let onDisappear: () -> Void
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.layer.cornerRadius = cornerRadius
        let host = UIHostingController(rootView: content)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.layer.cornerRadius = cornerRadius
        host.view.backgroundColor = .clear
        let constraints = [
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            host.view.widthAnchor.constraint(equalTo: view.widthAnchor),
            host.view.heightAnchor.constraint(equalTo: view.heightAnchor),
        ]
        view.addSubview(host.view)
        view.addConstraints(constraints)
        view.addInteraction(UIContextMenuInteraction(delegate: context.coordinator))
        context.coordinator.hostingController = host
        return view
    }

    // makeUIView only runs once per cell instance; every subsequent SwiftUI update (new message
    // state, downloaded voice note, playback progress, etc.) has to be pushed in here or the
    // UIKit-hosted content and the context menu's actions/preview go stale.
    func updateUIView(_: UIView, context: Context) {
        context.coordinator.cornerRadius = cornerRadius
        context.coordinator.menu = menu
        context.coordinator.content = content
        context.coordinator.preview = preview
        context.coordinator.didTapPreview = didTapPreview
        context.coordinator.onAppear = onAppear
        context.coordinator.onDisappear = onDisappear
        context.coordinator.hostingController?.rootView = content
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(
            cornerRadius: cornerRadius,
            menu: menu,
            content: content,
            preview: preview,
            didTapPreview: didTapPreview,
            onAppear: onAppear,
            onDisappear: onDisappear,
        )
    }
}

// MARK: - PreviewHostingController

private final class PreviewHostingController<Content: View>: UIHostingController<Content> {
    // MARK: Lifecycle

    init(rootView: Content, cornerRadius: CGFloat, onAppear: @escaping () -> Void, onDisappear: @escaping () -> Void) {
        self.onAppear = onAppear
        self.onDisappear = onDisappear
        super.init(rootView: rootView)
        view.backgroundColor = .clear
        view.layer.cornerRadius = cornerRadius
    }
    
    @available(*, unavailable) dynamic required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: Internal

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        preferredContentSize = view.intrinsicContentSize
        onAppear()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        onDisappear()
    }

    // MARK: Private

    private let onAppear: () -> Void
    private let onDisappear: () -> Void
}

private extension UIPreviewParameters {
    convenience init(backgroundColor: UIColor) {
        self.init()
        self.backgroundColor = backgroundColor
    }
}
