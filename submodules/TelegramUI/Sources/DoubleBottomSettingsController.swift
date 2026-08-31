import Foundation
import UIKit
import AsyncDisplayKit
import Display
import AccountContext
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences

private final class DoubleBottomSettingsControllerNode: ASDisplayNode {
    let tableView: UITableView

    override init() {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        self.tableView = tableView
        super.init()
        self.setViewBlock {
            return tableView
        }
    }
}

final class DoubleBottomSettingsController: ViewController, UITableViewDataSource, UITableViewDelegate {
    private enum Row: Equatable {
        case setup
        case changePrimaryPassword
        case changeDecoyPassword
        case allowlist
        case localFolder
        case showAllChats
        case clearFolders
        case sortOrder
        case secureExit
    }

    private let context: AccountContext
    private unowned let sharedContext: SharedAccountContextImpl
    private var credentialStatus: DoubleBottomCredentialStoreStatus = .notConfigured
    private var rows: [Row] = []
    private let actionDisposable = MetaDisposable()
    private let pickerDisposable = MetaDisposable()
    private var stateDisposable: Disposable?

    private var controllerNode: DoubleBottomSettingsControllerNode {
        return self.displayNode as! DoubleBottomSettingsControllerNode
    }

    init(context: AccountContext, sharedContext: SharedAccountContextImpl) {
        self.context = context
        self.sharedContext = sharedContext
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationTheme: presentationData.theme, presentationStrings: presentationData.strings))
        self.title = "Double Bottom"

        self.actionDisposable.set((sharedContext.doubleBottomCredentialStore.status()
        |> deliverOnMainQueue).startStrict(next: { [weak self] status in
            self?.credentialStatus = status
            self?.reloadRows()
        }))
        self.stateDisposable = (sharedContext.doubleBottomProfileUIState.updates
        |> deliverOnMainQueue).startStrict(next: { [weak self] _ in
            self?.reloadRows()
        })
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.actionDisposable.dispose()
        self.pickerDisposable.dispose()
        self.stateDisposable?.dispose()
    }

    override func loadDisplayNode() {
        let node = DoubleBottomSettingsControllerNode()
        node.tableView.dataSource = self
        node.tableView.delegate = self
        node.tableView.keyboardDismissMode = .interactive
        self.displayNode = node
        self.displayNodeDidLoad()
        self.reloadRows()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        transition.updateFrame(node: self.displayNode, frame: CGRect(origin: .zero, size: layout.size))
        let navigationHeight = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.controllerNode.tableView.contentInset.top = navigationHeight
        self.controllerNode.tableView.verticalScrollIndicatorInsets.top = navigationHeight
    }

    private func reloadRows() {
        guard self.isNodeLoaded else {
            return
        }
        switch self.credentialStatus {
        case .notConfigured:
            self.rows = [.setup]
        case .configured:
            self.rows = [.changePrimaryPassword, .changeDecoyPassword, .allowlist, .localFolder, .showAllChats, .clearFolders, .sortOrder, .secureExit]
        case .unavailable:
            self.rows = []
        }
        self.controllerNode.tableView.reloadData()
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return self.credentialStatus == .unavailable ? 1 : 2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return self.rows.filter { $0 != .secureExit }.count
        } else {
            return self.rows.contains(.secureExit) ? 1 : 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if self.credentialStatus == .unavailable {
            return "Double Bottom"
        }
        return section == 0 ? "Local Profiles" : nil
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if self.credentialStatus == .unavailable {
            return "Local credential storage is unavailable. No profile data was changed."
        }
        if section == 0 {
            return "Both passwords are local to this iPhone and are never sent to Telegram. Decoy folders and sorting do not modify Telegram cloud folders."
        }
        return nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        let row = self.row(at: indexPath)
        cell.accessoryType = .disclosureIndicator
        switch row {
        case .setup:
            cell.textLabel?.text = "Set Up Double Bottom"
        case .changePrimaryPassword:
            cell.textLabel?.text = "Change Primary Password"
        case .changeDecoyPassword:
            cell.textLabel?.text = "Change Decoy Password"
        case .allowlist:
            cell.textLabel?.text = "Decoy Chats"
        case .localFolder:
            cell.textLabel?.text = "Create Local Folder"
        case .showAllChats:
            cell.textLabel?.text = "Show All Decoy Chats"
            cell.accessoryType = .none
        case .clearFolders:
            cell.textLabel?.text = "Clear Local Folders"
            cell.accessoryType = .none
        case .sortOrder:
            cell.textLabel?.text = "Decoy Sort Order"
            cell.detailTextLabel?.text = self.sharedContext.doubleBottomProfileUIState.currentDecoyState.sortOrder == .title ? "Title" : "Activity"
        case .secureExit:
            cell.textLabel?.text = "Secure Exit"
            cell.textLabel?.textColor = .systemRed
            cell.accessoryType = .none
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch self.row(at: indexPath) {
        case .setup:
            self.presentCredentialSetup()
        case .changePrimaryPassword:
            self.presentPasswordChange(profile: .primary)
        case .changeDecoyPassword:
            self.presentPasswordChange(profile: .decoy)
        case .allowlist:
            self.openAllowlistPicker()
        case .localFolder:
            self.presentFolderName()
        case .showAllChats:
            let _ = self.sharedContext.doubleBottomProfileUIState.setSelectedFolderId(nil).startStandalone()
        case .clearFolders:
            let _ = self.sharedContext.doubleBottomProfileUIState.setFolders([]).startStandalone()
        case .sortOrder:
            let current = self.sharedContext.doubleBottomProfileUIState.currentDecoyState.sortOrder
            let _ = self.sharedContext.doubleBottomProfileUIState.setSortOrder(current == .activity ? .title : .activity).startStandalone()
        case .secureExit:
            let _ = self.sharedContext.performDoubleBottomSecureExitIfOwner(accountPeerId: self.context.account.peerId)
        }
    }

    private func row(at indexPath: IndexPath) -> Row {
        if indexPath.section == 1 {
            return .secureExit
        }
        return self.rows.filter { $0 != .secureExit }[indexPath.row]
    }

    private func presentCredentialSetup() {
        let alert = UIAlertController(title: "Set Up Double Bottom", message: "Choose two different local passwords.", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Primary password"
            field.isSecureTextEntry = true
            field.textContentType = UITextContentType.newPassword
        }
        alert.addTextField { field in
            field.placeholder = "Decoy password"
            field.isSecureTextEntry = true
            field.textContentType = UITextContentType.newPassword
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default, handler: { [weak self, weak alert] _ in
            guard let self, let fields = alert?.textFields, fields.count == 2 else {
                return
            }
            let primary = fields[0].text ?? ""
            let decoy = fields[1].text ?? ""
            self.actionDisposable.set((self.sharedContext.doubleBottomCredentialStore.setCredentials(primaryPassword: primary, decoyPassword: decoy)
            |> deliverOnMainQueue).startStandalone(next: { [weak self] _ in
                guard let self else {
                    return
                }
                self.pickerDisposable.set((self.sharedContext.doubleBottomPolicy.claimOwner(accountPeerId: self.context.account.peerId)
                |> deliverOnMainQueue).startStandalone(next: { [weak self] claimed in
                    guard let self, claimed else {
                        self?.presentError("Double Bottom already belongs to another Telegram account.")
                        return
                    }
                    self.credentialStatus = .configured
                    self.reloadRows()
                }, error: { [weak self] _ in
                    self?.presentError("Could not bind Double Bottom to this Telegram account.")
                }))
            }, error: { [weak self] error in
                self?.presentError(self?.credentialErrorText(error) ?? "Could not save the local passwords.")
            }))
        }))
        self.present(alert, animated: true)
    }

    private func presentPasswordChange(profile: DoubleBottomProfile) {
        let title = profile == .primary ? "Change Primary Password" : "Change Decoy Password"
        let alert = UIAlertController(title: title, message: "This changes only the local Double Bottom password.", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "New password"
            field.isSecureTextEntry = true
            field.textContentType = UITextContentType.newPassword
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default, handler: { [weak self, weak alert] _ in
            guard let self, let password = alert?.textFields?.first?.text else {
                return
            }
            self.actionDisposable.set((self.sharedContext.doubleBottomCredentialStore.setPassword(password, for: profile)
            |> deliverOnMainQueue).startStandalone(error: { [weak self] error in
                self?.presentError(self?.credentialErrorText(error) ?? "Could not change the local password.")
            }))
        }))
        self.present(alert, animated: true)
    }

    private func openAllowlistPicker() {
        self.actionDisposable.set((self.sharedContext.doubleBottomPrivateStore.load()
        |> deliverOnMainQueue).startStandalone(next: { [weak self] state in
            guard let self, state.ownerPeerId == self.context.account.peerId.toInt64() else {
                return
            }
            self.openPeerPicker(title: "Decoy Chats", selectedPeerIds: Set(state.decoyAllowedPeerIds.map(PeerId.init))) { [weak self] peerIds in
                guard let self else {
                    return
                }
                let _ = self.sharedContext.doubleBottomPolicy.setDecoyAllowedPeerIds(Set(peerIds), accountPeerId: self.context.account.peerId).startStandalone()
            }
        }, error: { [weak self] _ in
            self?.presentError("Could not open the encrypted Double Bottom configuration.")
        }))
    }

    private func presentFolderName() {
        let alert = UIAlertController(title: "Local Decoy Folder", message: "This folder exists only inside the Decoy profile.", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Folder name"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Next", style: .default, handler: { [weak self, weak alert] _ in
            guard let self, let title = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                return
            }
            self.actionDisposable.set((self.sharedContext.doubleBottomPrivateStore.load()
            |> deliverOnMainQueue).startStandalone(next: { [weak self] state in
                guard let self, state.ownerPeerId == self.context.account.peerId.toInt64() else {
                    return
                }
                self.openPeerPicker(title: title, selectedPeerIds: []) { [weak self] peerIds in
                    guard let self else {
                        return
                    }
                    var folders = self.sharedContext.doubleBottomProfileUIState.currentDecoyState.folders
                    let folder = DoubleBottomLocalChatFolder(id: UUID().uuidString, title: title, peerIds: Set(peerIds))
                    folders.append(folder)
                    let _ = (self.sharedContext.doubleBottomProfileUIState.setFolders(folders)
                    |> then(self.sharedContext.doubleBottomProfileUIState.setSelectedFolderId(folder.id))).startStandalone()
                }
            }))
        }))
        self.present(alert, animated: true)
    }

    private func openPeerPicker(title: String, selectedPeerIds: Set<PeerId>, completion: @escaping ([PeerId]) -> Void) {
        let controller = self.context.sharedContext.makeContactMultiselectionController(ContactMultiselectionControllerParams(
            context: self.context,
            mode: .chatSelection(ContactMultiselectionControllerMode.ChatSelection(
                title: title,
                searchPlaceholder: "Search Chats",
                selectedChats: selectedPeerIds,
                additionalCategories: nil,
                chatListFilters: nil
            )),
            filters: [],
            alwaysEnabled: true
        ))
        self.pickerDisposable.set((controller.result
        |> take(1)
        |> deliverOnMainQueue).startStrict(next: { [weak controller] result in
            guard case let .result(rawPeerIds, _) = result else {
                return
            }
            let peerIds = rawPeerIds.compactMap { value -> PeerId? in
                if case let .peer(peerId) = value {
                    return peerId
                }
                return nil
            }
            completion(peerIds)
            controller?.dismiss()
        }))
        self.push(controller)
    }

    private func credentialErrorText(_ error: Error) -> String {
        if let error = error as? DoubleBottomCredentialStoreError {
            switch error {
            case .invalidPassword:
                return "Enter both local passwords."
            case .passwordsMustDiffer:
                return "Primary and Decoy passwords must be different."
            default:
                return "The local credential store is unavailable."
            }
        }
        return "Could not update Double Bottom."
    }

    private func presentError(_ text: String) {
        let alert = UIAlertController(title: "Double Bottom", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        self.present(alert, animated: true)
    }
}

final class DoubleBottomDecoyPasswordController: ViewController, UITableViewDataSource, UITableViewDelegate {
    private let context: AccountContext
    private let credentialStore: DoubleBottomCredentialStore
    private let actionDisposable = MetaDisposable()

    private var controllerNode: DoubleBottomSettingsControllerNode {
        return self.displayNode as! DoubleBottomSettingsControllerNode
    }

    init(context: AccountContext, credentialStore: DoubleBottomCredentialStore) {
        self.context = context
        self.credentialStore = credentialStore
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationTheme: presentationData.theme, presentationStrings: presentationData.strings))
        self.title = presentationData.strings.PrivacySettings_TwoStepAuth
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.actionDisposable.dispose()
    }

    override func loadDisplayNode() {
        let node = DoubleBottomSettingsControllerNode()
        node.tableView.dataSource = self
        node.tableView.delegate = self
        self.displayNode = node
        self.displayNodeDidLoad()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        transition.updateFrame(node: self.displayNode, frame: CGRect(origin: .zero, size: layout.size))
        let navigationHeight = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.controllerNode.tableView.contentInset.top = navigationHeight
        self.controllerNode.tableView.verticalScrollIndicatorInsets.top = navigationHeight
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return "This password protects the local profile on this iPhone. It does not change your Telegram cloud password."
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = "Change Password"
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let alert = UIAlertController(title: "Change Password", message: "Enter a new local password.", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "New password"
            field.isSecureTextEntry = true
            field.textContentType = UITextContentType.newPassword
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default, handler: { [weak self, weak alert] _ in
            guard let self, let password = alert?.textFields?.first?.text else {
                return
            }
            self.actionDisposable.set((self.credentialStore.setPassword(password, for: .decoy)
            |> deliverOnMainQueue).startStandalone(error: { [weak self] error in
                let message: String
                if error == .passwordsMustDiffer {
                    message = "Primary and Decoy passwords must be different."
                } else {
                    message = "Could not change the local password."
                }
                let errorAlert = UIAlertController(title: "Password", message: message, preferredStyle: .alert)
                errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(errorAlert, animated: true)
            }))
        }))
        self.present(alert, animated: true)
    }
}
