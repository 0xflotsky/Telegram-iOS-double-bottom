import AuthorizationUI
import Display
import SwiftSignalKit
import TelegramPresentationData
import TelegramUIPreferences
import UIKit

final class DoubleBottomSecureExitCoordinator {
    private weak var window: Window1?
    private let coveringView: AuthorizationPasswordEntryCoveringView
    private let presentationData: PresentationData
    private let context: DoubleBottomContext
    private let credentialStore: DoubleBottomCredentialStore
    private let privateStore: DoubleBottomPrivateStore
    private let policy: DoubleBottomPolicy
    private let profileUIState: DoubleBottomProfileUIStateContextImpl
    private var accessStateDisposable: Disposable?
    private let verificationDisposable = MetaDisposable()
    private let applyProfileDisposable = MetaDisposable()

    init(window: Window1?, presentationData: PresentationData, context: DoubleBottomContext, credentialStore: DoubleBottomCredentialStore, privateStore: DoubleBottomPrivateStore, policy: DoubleBottomPolicy, profileUIState: DoubleBottomProfileUIStateContextImpl) {
        self.window = window
        self.presentationData = presentationData
        self.coveringView = AuthorizationPasswordEntryCoveringView(presentationData: presentationData)
        self.context = context
        self.credentialStore = credentialStore
        self.privateStore = privateStore
        self.policy = policy
        self.profileUIState = profileUIState
        if (privateStore.hasPersistedState || credentialStore.hasPersistedCredentials), let window {
            window.privacyCoveringView = self.coveringView
        }
        self.coveringView.submitPassword = { [weak self] password in
            self?.verify(password: password)
        }
        self.coveringView.forgotPassword = { [weak self] in
            self?.presentPasswordAlert(text: presentationData.strings.TwoStepAuth_RecoveryUnavailable)
        }
        self.accessStateDisposable = policy.activeMode.startStrict(next: { [weak self] mode in
            guard let self, let window = self.window else {
                return
            }

            switch mode {
            case .ordinary, .primary, .decoy:
                if window.privacyCoveringView === self.coveringView {
                    window.privacyCoveringView = nil
                }
                self.coveringView.reset()
            case .secureExited:
                window.hostView.eventView.endEditing(true)
                if window.privacyCoveringView !== self.coveringView {
                    window.privacyCoveringView = self.coveringView
                }
                (window.viewController as? TelegramRootController)?.sanitizeForDoubleBottomPolicy()
                self.privateStore.clearDecryptedState()
                self.profileUIState.clearSensitiveState()
            }
        })
    }

    deinit {
        self.accessStateDisposable?.dispose()
        self.verificationDisposable.dispose()
        self.applyProfileDisposable.dispose()
    }

    func secureExit() {
        assert(Queue.mainQueue().isCurrent())
        guard let window = self.window else {
            self.context.secureExit()
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
        self.verificationDisposable.set(nil)
        self.applyProfileDisposable.set(nil)
        self.privateStore.clearDecryptedState()
        self.profileUIState.clearSensitiveState()
        self.context.secureExit()
    }

    private func verify(password: String) {
        self.coveringView.setInProgress(true)
        guard self.policy.canUnlockActiveOwner else {
            self.coveringView.displayUnavailable()
            self.presentPasswordAlert(text: self.presentationData.strings.Login_UnknownError)
            return
        }
        self.verificationDisposable.set((self.credentialStore.verify(password: password)
        |> deliverOnMainQueue).startStrict(next: { [weak self] result in
            guard let self else {
                return
            }

            let profile: DoubleBottomProfile
            switch result {
            case .primary:
                profile = .primary
            case .decoy:
                profile = .decoy
            case .invalid:
                self.coveringView.displayInvalidPassword()
                self.presentPasswordAlert(text: self.presentationData.strings.LoginPassword_InvalidPasswordError)
                return
            case .notConfigured, .unavailable:
                self.coveringView.displayUnavailable()
                self.presentPasswordAlert(text: self.presentationData.strings.Login_UnknownError)
                return
            }

            let applyProfile = (self.context.setCurrentProfile(profile)
            |> ignoreValues)
            |> then(
                self.context.currentProfile
                |> filter { $0 == profile }
                |> take(1)
                |> ignoreValues
            )
            |> then(
                self.policy.currentProfile
                |> filter { $0 == profile }
                |> take(1)
                |> ignoreValues
            )
            |> deliverOnMainQueue

            self.applyProfileDisposable.set(applyProfile.startStrict(completed: { [weak self] in
                guard let self else {
                    return
                }
                if profile == .decoy {
                    (self.window?.viewController as? TelegramRootController)?.sanitizeForDoubleBottomPolicy()
                }
                self.context.completeLocalUnlock()
            }))
        }))
    }

    private func presentPasswordAlert(text: String) {
        guard let window = self.window else {
            return
        }
        let controller = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: self.presentationData.strings.Common_OK, style: .default, handler: { [weak self] _ in
            self?.coveringView.activateInput()
        }))
        window.presentNative(controller)
    }
}
