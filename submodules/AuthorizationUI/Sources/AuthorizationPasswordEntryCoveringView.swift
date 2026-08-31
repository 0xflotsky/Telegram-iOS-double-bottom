import Foundation
import UIKit
import Display
import TelegramPresentationData

public final class AuthorizationPasswordEntryCoveringView: WindowCoveringView {
    private let passwordNode: AuthorizationSequencePasswordEntryControllerNode
    private var currentSize: CGSize = .zero
    private var keyboardHeight: CGFloat = 0.0
    private var keyboardObservers: [NSObjectProtocol] = []

    public var submitPassword: ((String) -> Void)?
    public var forgotPassword: (() -> Void)?

    public init(presentationData: PresentationData) {
        self.passwordNode = AuthorizationSequencePasswordEntryControllerNode(strings: presentationData.strings, theme: presentationData.theme)

        super.init(frame: .zero)

        self.backgroundColor = presentationData.theme.list.plainBackgroundColor
        self.isOpaque = true
        self.accessibilityViewIsModal = true

        self.addSubview(self.passwordNode.view)
        self.passwordNode.updateData(
            hint: presentationData.strings.TwoStepAuth_EnterPasswordPassword,
            didForgotWithNoRecovery: false,
            suggestReset: false
        )
        self.passwordNode.loginWithCode = { [weak self] password in
            self?.submitPassword?(password)
        }
        self.passwordNode.forgot = { [weak self] in
            self?.forgotPassword?()
        }

        self.keyboardObservers.append(NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            queue: .main,
            using: { [weak self] notification in
                self?.updateKeyboard(notification: notification)
            }
        ))
        self.keyboardObservers.append(NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main,
            using: { [weak self] _ in
                guard let self else {
                    return
                }
                self.keyboardHeight = 0.0
                self.updatePasswordLayout(transition: .immediate)
            }
        ))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        for observer in self.keyboardObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()

        if self.window != nil {
            self.passwordNode.activateInput()
        }
    }

    public override func updateLayout(_ size: CGSize) {
        self.currentSize = size
        self.passwordNode.frame = CGRect(origin: .zero, size: size)
        self.updatePasswordLayout(transition: .immediate)
    }

    public func setInProgress(_ value: Bool) {
        self.passwordNode.inProgress = value
    }

    public func displayInvalidPassword() {
        self.passwordNode.inProgress = false
        self.passwordNode.passwordIsInvalid()
    }

    public func displayUnavailable() {
        self.passwordNode.inProgress = false
        self.passwordNode.passwordIsInvalid()
    }

    public func reset() {
        self.passwordNode.inProgress = false
        self.passwordNode.resetPasswordInput()
    }

    public func activateInput() {
        self.passwordNode.activateInput()
    }

    private func updateKeyboard(notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }
        let localFrame = self.convert(frame, from: nil)
        self.keyboardHeight = max(0.0, self.bounds.maxY - localFrame.minY)
        self.updatePasswordLayout(transition: .immediate)
    }

    private func updatePasswordLayout(transition: ContainedViewLayoutTransition) {
        guard !self.currentSize.width.isZero, !self.currentSize.height.isZero else {
            return
        }

        let orientation: UIInterfaceOrientation? = self.currentSize.width > self.currentSize.height ? .landscapeRight : .portrait
        let metrics: LayoutMetrics
        if self.currentSize.width > 690.0 && self.currentSize.height > 650.0 {
            metrics = LayoutMetrics(widthClass: .regular, heightClass: .regular, orientation: orientation)
        } else {
            metrics = LayoutMetrics(widthClass: .compact, heightClass: .compact, orientation: orientation)
        }

        let safeInsets = self.safeAreaInsets
        let onScreenNavigationHeight: CGFloat? = safeInsets.bottom > 0.0 ? safeInsets.bottom : nil
        let deviceMetrics = DeviceMetrics(
            screenSize: UIScreen.main.bounds.size,
            scale: UIScreen.main.scale,
            statusBarHeight: safeInsets.top,
            onScreenNavigationHeight: onScreenNavigationHeight
        )
        let layout = ContainerViewLayout(
            size: self.currentSize,
            metrics: metrics,
            deviceMetrics: deviceMetrics,
            intrinsicInsets: UIEdgeInsets(top: 0.0, left: 0.0, bottom: safeInsets.bottom, right: 0.0),
            safeInsets: safeInsets,
            additionalInsets: .zero,
            statusBarHeight: safeInsets.top,
            inputHeight: self.keyboardHeight,
            inputHeightIsInteractivellyChanging: false,
            inVoiceOver: UIAccessibility.isVoiceOverRunning
        )
        self.passwordNode.containerLayoutUpdated(layout, navigationBarHeight: safeInsets.top, transition: transition)
    }
}
