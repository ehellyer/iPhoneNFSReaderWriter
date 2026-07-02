import SwiftUI

extension View {
    /// Resigns the first responder, dismissing the keyboard from anywhere.
    /// Avoids threading a @FocusState binding through every write form.
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
