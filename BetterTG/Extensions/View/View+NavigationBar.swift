// View+NavigationBar.swift

import SwiftUI

extension View {
    func navigationBarHeight(_ height: Binding<CGFloat>) -> some View {
        background {
            NavigationBarAccessor { navigationBar in
                height.wrappedValue = navigationBar.bounds.height
            }
        }
    }

    /// Sets the title UIKit uses for the actual Back item on the next pushed screen. Because this
    /// configures the source navigation item, the native pop action and edge-swipe remain intact.
    func nativeNavigationBackButtonTitle(_ title: String) -> some View {
        background {
            NativeNavigationBackButtonTitleAccessor(title: title)
        }
    }
}

// MARK: - NativeNavigationBackButtonTitleAccessor

private struct NativeNavigationBackButtonTitleAccessor: UIViewControllerRepresentable {
    @MainActor final class ProxyViewController: UIViewController {
        // MARK: Lifecycle

        init(title: String) {
            self.titleForBackButton = title
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable) required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // MARK: Internal

        var titleForBackButton: String

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            applyTitle()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            applyTitle()
        }

        func applyTitle() {
            guard let owner = parent else { return }
            owner.navigationItem.backButtonTitle = titleForBackButton
            owner.navigationItem.backButtonDisplayMode = .default
        }
    }

    let title: String

    func makeUIViewController(context _: Context) -> ProxyViewController {
        ProxyViewController(title: title)
    }

    func updateUIViewController(_ proxyViewController: ProxyViewController, context _: Context) {
        proxyViewController.titleForBackButton = title
        proxyViewController.applyTitle()
    }
}

// MARK: - NavigationBarAccessor

struct NavigationBarAccessor: UIViewControllerRepresentable {
    // MARK: Internal

    var callback: (UINavigationBar) -> Void

    func makeUIViewController(context _: Context) -> UIViewController {
        let proxyViewController = ProxyViewController()
        proxyViewController.callback = callback
        proxyViewController.startObservingNavigationBarIfNeeded()
        return proxyViewController
    }
    
    func updateUIViewController(_: UIViewController, context _: Context) {}
    
    // MARK: Private

    private final class ProxyViewController: UIViewController {
        // MARK: Lifecycle

        isolated deinit {
            stopObservingNavigationBar()
        }
        
        // MARK: Internal

        var callback: ((UINavigationBar) -> Void)?

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            startObservingNavigationBarIfNeeded()
            refreshNavigationBarHeight()
        }
        
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            startObservingNavigationBarIfNeeded()
            refreshNavigationBarHeight()
        }
        
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            refreshNavigationBarHeight()
        }
        
        override func willMove(toParent parent: UIViewController?) {
            super.willMove(toParent: parent)
            if parent == nil {
                stopObservingNavigationBar()
            }
        }
        
        func startObservingNavigationBarIfNeeded() {
            guard let navigationBar = navigationController?.navigationBar else { return }
            guard observedNavigationBar !== navigationBar else { return }
            stopObservingNavigationBar()
            observedNavigationBar = navigationBar
            
            boundsObservation = navigationBar.observe(\.bounds, options: [
                .initial,
                .new,
            ]) { [weak self] navigationBar, _ in
                MainActor.assumeIsolated {
                    self?.reportHeightIfNeeded(for: navigationBar)
                }
            }
        }
        
        func refreshNavigationBarHeight() {
            guard let navigationBar = navigationController?.navigationBar else { return }
            reportHeightIfNeeded(for: navigationBar)
        }
        
        // MARK: Private

        private weak var observedNavigationBar: UINavigationBar?
        private var boundsObservation: NSKeyValueObservation?
        private var lastReportedHeight = CGFloat.zero
        
        private func stopObservingNavigationBar() {
            boundsObservation?.invalidate()
            boundsObservation = nil
            observedNavigationBar = nil
        }
        
        private func reportHeightIfNeeded(for navigationBar: UINavigationBar) {
            let height = navigationBar.bounds.height
            guard height.isFinite else { return }
            guard abs(height - lastReportedHeight) > 0.5 else { return }
            lastReportedHeight = height
            callback?(navigationBar)
        }
    }
}
