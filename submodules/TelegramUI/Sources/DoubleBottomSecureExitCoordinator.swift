import UIKit
import Display
import SwiftSignalKit
import TelegramUIPreferences

private final class DoubleBottomSecureExitCoveringView: WindowCoveringView {
    private let contentView = UIStackView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let passwordField = UITextField()
    private let errorLabel = UILabel()
    private let unlockButton = UIButton(type: .system)

    var unlock: ((String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.backgroundColor = .systemBackground
        self.isOpaque = true
        self.accessibilityViewIsModal = true

        self.contentView.axis = .vertical
        self.contentView.spacing = 12.0
        self.contentView.alignment = .fill
        self.contentView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.contentView)

        self.titleLabel.font = .systemFont(ofSize: 28.0, weight: .semibold)
        self.titleLabel.textColor = .label
        self.titleLabel.textAlignment = .center
        self.titleLabel.text = "Telegram"
        self.contentView.addArrangedSubview(self.titleLabel)

        self.subtitleLabel.font = .systemFont(ofSize: 15.0)
        self.subtitleLabel.textColor = .secondaryLabel
        self.subtitleLabel.textAlignment = .center
        self.subtitleLabel.text = "Enter your password"
        self.contentView.addArrangedSubview(self.subtitleLabel)
        self.contentView.setCustomSpacing(24.0, after: self.subtitleLabel)

        self.passwordField.borderStyle = .roundedRect
        self.passwordField.backgroundColor = .secondarySystemBackground
        self.passwordField.textColor = .label
        self.passwordField.placeholder = "Password"
        self.passwordField.isSecureTextEntry = true
        self.passwordField.autocapitalizationType = .none
        self.passwordField.autocorrectionType = .no
        self.passwordField.spellCheckingType = .no
        self.passwordField.textContentType = .password
        self.passwordField.returnKeyType = .go
        self.passwordField.delegate = self
        self.passwordField.heightAnchor.constraint(equalToConstant: 44.0).isActive = true
        self.contentView.addArrangedSubview(self.passwordField)

        self.errorLabel.font = .systemFont(ofSize: 13.0)
        self.errorLabel.textColor = .systemRed
        self.errorLabel.textAlignment = .center
        self.errorLabel.text = "Incorrect password"
        self.errorLabel.isHidden = true
        self.contentView.addArrangedSubview(self.errorLabel)

        self.unlockButton.setTitle("Continue", for: .normal)
        self.unlockButton.setTitleColor(.white, for: .normal)
        self.unlockButton.titleLabel?.font = .systemFont(ofSize: 17.0, weight: .semibold)
        self.unlockButton.backgroundColor = .systemBlue
        self.unlockButton.layer.cornerRadius = 10.0
        self.unlockButton.heightAnchor.constraint(equalToConstant: 48.0).isActive = true
        self.unlockButton.addTarget(self, action: #selector(self.unlockPressed), for: .touchUpInside)
        self.contentView.addArrangedSubview(self.unlockButton)

        let preferredWidth = self.contentView.widthAnchor.constraint(equalToConstant: 320.0)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            self.contentView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.contentView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.contentView.leadingAnchor.constraint(greaterThanOrEqualTo: self.leadingAnchor, constant: 32.0),
            self.contentView.trailingAnchor.constraint(lessThanOrEqualTo: self.trailingAnchor, constant: -32.0),
            self.contentView.widthAnchor.constraint(lessThanOrEqualToConstant: 320.0),
            preferredWidth
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        if self.window != nil {
            self.passwordField.becomeFirstResponder()
        }
    }

    func setVerifying(_ value: Bool) {
        self.passwordField.isEnabled = !value
        self.unlockButton.isEnabled = !value
        self.unlockButton.alpha = value ? 0.6 : 1.0
        self.unlockButton.setTitle(value ? "Checking…" : "Continue", for: .normal)
        if value {
            self.errorLabel.isHidden = true
        }
    }

    func showIncorrectPassword() {
        self.passwordField.text = nil
        self.setVerifying(false)
        self.errorLabel.isHidden = false
        self.passwordField.becomeFirstResponder()
    }

    func reset() {
        self.passwordField.text = nil
        self.errorLabel.isHidden = true
        self.setVerifying(false)
    }

    @objc private func unlockPressed() {
        guard let password = self.passwordField.text, !password.isEmpty else {
            self.showIncorrectPassword()
            return
        }
        self.passwordField.text = nil
        self.setVerifying(true)
        self.unlock?(password)
    }
}

extension DoubleBottomSecureExitCoveringView: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.unlockPressed()
        return false
    }
}

final class DoubleBottomSecureExitCoordinator {
    private weak var window: Window1?
    private let coveringView = DoubleBottomSecureExitCoveringView(frame: .zero)
    private let context: DoubleBottomContext
    private let credentialStore: DoubleBottomCredentialStore
    private let privateStore: DoubleBottomPrivateStore
    private let policy: DoubleBottomPolicy
    private let profileUIState: DoubleBottomProfileUIStateContextImpl
    private var accessStateDisposable: Disposable?
    private let verificationDisposable = MetaDisposable()
    private let applyProfileDisposable = MetaDisposable()

    init(window: Window1?, context: DoubleBottomContext, credentialStore: DoubleBottomCredentialStore, privateStore: DoubleBottomPrivateStore, policy: DoubleBottomPolicy, profileUIState: DoubleBottomProfileUIStateContextImpl) {
        self.window = window
        self.context = context
        self.credentialStore = credentialStore
        self.privateStore = privateStore
        self.policy = policy
        self.profileUIState = profileUIState
        self.coveringView.unlock = { [weak self] password in
            self?.verify(password: password)
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
            case .invalid, .notConfigured, .unavailable:
                self.coveringView.showIncorrectPassword()
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
}
