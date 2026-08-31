import Display
import SwiftSignalKit
import TelegramPresentationData
import UIKit

private final class DoubleBottomAuthorizationPrivacyCover: WindowCoveringView {
    init(presentationData: PresentationData) {
        super.init(frame: .zero)
        self.backgroundColor = presentationData.theme.list.plainBackgroundColor
        self.isOpaque = true
        self.accessibilityViewIsModal = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class DoubleBottomSecureExitCoordinator {
    private weak var window: Window1?
    private let coveringView: DoubleBottomAuthorizationPrivacyCover
    private let context: DoubleBottomContext
    private let privateStore: DoubleBottomPrivateStore
    private let policy: DoubleBottomPolicy
    private let profileUIState: DoubleBottomProfileUIStateContextImpl
    private var accessStateDisposable: Disposable?
    private var authorizationRequested = false

    var beginAuthorization: (() -> Void)? {
        didSet {
            self.requestAuthorizationIfNeeded()
        }
    }

    init(window: Window1?, presentationData: PresentationData, context: DoubleBottomContext, privateStore: DoubleBottomPrivateStore, policy: DoubleBottomPolicy, profileUIState: DoubleBottomProfileUIStateContextImpl, initialAccessState: DoubleBottomAccessState) {
        self.window = window
        self.coveringView = DoubleBottomAuthorizationPrivacyCover(presentationData: presentationData)
        self.context = context
        self.privateStore = privateStore
        self.policy = policy
        self.profileUIState = profileUIState
        if initialAccessState == .secureExited {
            self.authorizationRequested = true
            if let window {
                window.privacyCoveringView = self.coveringView
            }
        }
        self.accessStateDisposable = policy.activeMode.startStrict(next: { [weak self] mode in
            guard let self, let window = self.window else {
                return
            }

            switch mode {
            case .ordinary:
                break
            case .primary, .decoy:
                if window.privacyCoveringView === self.coveringView {
                    window.privacyCoveringView = nil
                }
            case .secureExited:
                window.hostView.eventView.endEditing(true)
                if window.privacyCoveringView !== self.coveringView {
                    window.privacyCoveringView = self.coveringView
                }
                (window.viewController as? TelegramRootController)?.sanitizeForDoubleBottomPolicy()
                self.privateStore.clearDecryptedState()
                self.profileUIState.clearSensitiveState()
                self.authorizationRequested = true
                self.requestAuthorizationIfNeeded()
            }
        })
    }

    deinit {
        self.accessStateDisposable?.dispose()
    }

    func secureExit() {
        assert(Queue.mainQueue().isCurrent())
        let didPersistSecureExit = self.privateStore.setRequiresLocalUnlockSynchronously(true)
        self.context.secureExit()

        guard let window = self.window else {
            return
        }

        window.hostView.eventView.endEditing(true)
        if window.privacyCoveringView !== self.coveringView {
            window.privacyCoveringView = self.coveringView
        }

        (window.viewController as? TelegramRootController)?.sanitizeForDoubleBottomPolicy()
        window.forEachViewController { controller in
            controller.view.endEditing(true)
            return true
        }
        self.privateStore.clearDecryptedState()
        self.profileUIState.clearSensitiveState()

        if didPersistSecureExit {
            self.authorizationRequested = true
            self.requestAuthorizationIfNeeded()
        }
    }

    func authorizationDidPresent() {
        assert(Queue.mainQueue().isCurrent())
        guard let window = self.window, window.privacyCoveringView === self.coveringView else {
            return
        }
        window.privacyCoveringView = nil
    }

    private func requestAuthorizationIfNeeded() {
        guard self.authorizationRequested, let beginAuthorization = self.beginAuthorization else {
            return
        }
        self.authorizationRequested = false
        beginAuthorization()
    }
}
