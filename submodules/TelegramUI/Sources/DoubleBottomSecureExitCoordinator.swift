import UIKit
import Display
import SwiftSignalKit

private final class DoubleBottomSecureExitCoveringView: WindowCoveringView {
    override init(frame: CGRect) {
        super.init(frame: frame)

        self.backgroundColor = .black
        self.isOpaque = true
        self.accessibilityViewIsModal = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class DoubleBottomSecureExitCoordinator {
    private weak var window: Window1?
    private let coveringView = DoubleBottomSecureExitCoveringView(frame: .zero)
    private var accessStateDisposable: Disposable?

    init(window: Window1?, context: DoubleBottomContext) {
        self.window = window
        self.accessStateDisposable = context.accessState.startStrict(next: { [weak self] state in
            guard let self, let window = self.window else {
                return
            }

            switch state {
            case .unlocked:
                if window.privacyCoveringView === self.coveringView {
                    window.privacyCoveringView = nil
                }
            case .secureExited:
                window.hostView.eventView.endEditing(true)
                if window.privacyCoveringView !== self.coveringView {
                    window.privacyCoveringView = self.coveringView
                }
            }
        })
    }

    deinit {
        self.accessStateDisposable?.dispose()
    }
}
