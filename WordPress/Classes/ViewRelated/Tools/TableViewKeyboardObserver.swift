import UIKit

class TableViewKeyboardObserver: NSObject {
    @objc weak var tableView: UITableView? {
        didSet {
            originalInset = tableView?.contentInset ?? .zero
        }
    }

    @objc var originalInset: UIEdgeInsets = .zero

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(TableViewKeyboardObserver.keyboardWillShow(_:)), name: .UIKeyboardWillShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TableViewKeyboardObserver.keyboardWillHide(_:)), name: .UIKeyboardWillHide, object: nil)
    }

    @objc func keyboardWillShow(_ notification: Foundation.Notification) {
        guard let keyboardFrame = (notification.userInfo?[UIKeyboardFrameBeginUserInfoKey] as? NSValue)?.cgRectValue else {
            return
        }

        var inset = originalInset
        if UIInterfaceOrientationIsPortrait(UIApplication.shared.statusBarOrientation) {
            inset.bottom += keyboardFrame.height
        } else {
            inset.bottom += keyboardFrame.width
        }
        tableView?.contentInset = inset
    }

    @objc func keyboardWillHide(_ notification: Notification) {
        tableView?.contentInset = originalInset
    }
}
