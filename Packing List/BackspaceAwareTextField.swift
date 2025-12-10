import ObjectiveC.runtime
import SwiftData
import SwiftUI
import UIKit

struct BackspaceAwareTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFirstResponder: Bool
    var isEditable: Bool
    var isStrikethrough: Bool
    var opacity: Double
    var onSubmitNewline: () -> Void
    var onDeleteWhenEmpty: () -> Void

    func makeUIView(context: Context) -> BackspaceAwareUITextField {
        let tf = BackspaceAwareUITextField()
        tf.delegate = context.coordinator
        tf.borderStyle = .none
        tf.backgroundColor = .clear
        tf.autocorrectionType = .yes
        tf.returnKeyType = .default
        tf.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        return tf
    }

    func updateUIView(_ uiView: BackspaceAwareUITextField, context _: Context) {
        uiView.isUserInteractionEnabled = self.isEditable
        uiView.alpha = self.opacity
        uiView.onDeleteWhenEmpty = self.onDeleteWhenEmpty
        uiView.onSubmitNewline = self.onSubmitNewline

        // Only update text if it's different to avoid cursor jumping
        if uiView.text != self.text {
            uiView.text = self.text
        }

        // Apply strikethrough styling via typing attributes to avoid resetting text/selection.
        var attrs = uiView.defaultTextAttributes
        attrs[.strikethroughStyle] = self.isStrikethrough ? NSUnderlineStyle.single.rawValue : 0
        uiView.defaultTextAttributes = attrs
        uiView.typingAttributes = attrs
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: BackspaceAwareTextField

        init(parent: BackspaceAwareTextField) {
            self.parent = parent
        }

        @objc func editingChanged(_ textField: UITextField) {
            self.parent.text = textField.text ?? ""
        }

        func textFieldDidBeginEditing(_: UITextField) {
            self.parent.isFirstResponder = true
        }

        func textFieldDidEndEditing(_: UITextField) {
            self.parent.isFirstResponder = false
        }

        // Keep delegate permissive; newline handled in insertText override.
        func textField(_: UITextField, shouldChangeCharactersIn _: NSRange, replacementString string: String) -> Bool {
            if string == "\n" {
                self.parent.onSubmitNewline()
                return false
            }
            return true
        }

        func textFieldShouldReturn(_: UITextField) -> Bool {
            self.parent.onSubmitNewline()
            return false
        }
    }
}

final class BackspaceAwareUITextField: UITextField {
    var onDeleteWhenEmpty: (() -> Void)?
    var onSubmitNewline: (() -> Void)?

    override func deleteBackward() {
        if (text ?? "").isEmpty {
            self.onDeleteWhenEmpty?()
        }
        super.deleteBackward()
    }

    override func insertText(_ text: String) {
        if text == "\n" {
            self.onSubmitNewline?()
        } else {
            super.insertText(text)
        }
    }
}
