import Foundation
import WordPressKit


@objc
class WPAccount: NSObject {
    var username: String! = ""
    var displayName = ""
    var email = ""
    var userID = NSNumber(integerLiteral: 1)

    var wordPressComRestApi: WordPressComRestApi!
}