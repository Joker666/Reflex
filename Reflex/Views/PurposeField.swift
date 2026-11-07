import AppKit
import SwiftUI

/// A persistent text view avoids the display-to-field-editor switch that moves
/// clipped text when a standard text field receives focus.
struct StablePurposeField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        _text = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> PurposeTextFieldView {
        let textField = PurposeTextFieldView()
        context.coordinator.fieldView = textField
        textField.textView.delegate = context.coordinator
        return textField
    }

    func updateNSView(_ textField: PurposeTextFieldView, context: Context) {
        context.coordinator.text = $text
        textField.placeholder = placeholder
        textField.setText(text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var fieldView: PurposeTextFieldView?

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            fieldView?.updatePlaceholder()
            fieldView?.updateDocumentSize()
        }
    }
}

final class PurposeTextFieldView: NSView {
    let textView = SingleLineTextView()
    private let scrollView = NSScrollView()
    private let placeholderLabel = NSTextField(labelWithString: "")

    var placeholder = "" {
        didSet {
            placeholderLabel.stringValue = placeholder
            textView.setAccessibilityLabel(placeholder)
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 22)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true

        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = false
        textView.autoresizingMask = [.height]
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.focusChanged = { [weak self] focused in
            self?.setFocused(focused)
        }
        scrollView.documentView = textView

        placeholderLabel.font = textView.font
        placeholderLabel.textColor = .placeholderTextColor
        placeholderLabel.lineBreakMode = .byClipping
        placeholderLabel.isHidden = true

        addSubview(placeholderLabel)
        addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let contentFrame = bounds.insetBy(dx: 5, dy: 3)
        scrollView.frame = contentFrame
        placeholderLabel.frame = contentFrame
        updateDocumentSize()
    }

    func setText(_ text: String) {
        if textView.string != text {
            textView.string = text
        }
        updatePlaceholder()
        updateDocumentSize()
    }

    func setFocused(_ focused: Bool) {
        if !focused {
            scrollToStart()
        }
    }

    func updatePlaceholder() {
        placeholderLabel.isHidden = !textView.string.isEmpty
    }

    func updateDocumentSize() {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        layoutManager.ensureLayout(for: textContainer)
        let textWidth = ceil(layoutManager.usedRect(for: textContainer).width) + 1
        let visibleSize = scrollView.contentSize
        textView.frame = NSRect(
            origin: textView.frame.origin,
            size: NSSize(width: max(textWidth, visibleSize.width), height: visibleSize.height)
        )
    }

    private func scrollToStart() {
        let clipView = scrollView.contentView
        clipView.scroll(to: NSPoint(x: 0, y: clipView.bounds.origin.y))
        scrollView.reflectScrolledClipView(clipView)
    }

}

final class SingleLineTextView: NSTextView {
    var focusChanged: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder {
            focusChanged?(true)
        }
        return becameFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let resignedFirstResponder = super.resignFirstResponder()
        if resignedFirstResponder {
            focusChanged?(false)
        }
        return resignedFirstResponder
    }

    /// AppKit gives a drop to the deepest registered view, so a registered field would
    /// stop a dragged target from reaching its row.
    override func updateDragTypeRegistration() {
        unregisterDraggedTypes()
    }

    override func insertNewline(_ sender: Any?) {
        window?.makeFirstResponder(nil)
    }

    override func insertTab(_ sender: Any?) {
        window?.selectNextKeyView(nil)
    }

    override func insertBacktab(_ sender: Any?) {
        window?.selectPreviousKeyView(nil)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let string: String
        if let attributedString = insertString as? NSAttributedString {
            string = attributedString.string
        } else {
            string = String(describing: insertString)
        }
        let singleLine = string
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        super.insertText(singleLine, replacementRange: replacementRange)
    }
}
