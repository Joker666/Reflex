import AppKit
import SwiftUI

/// A persistent text view avoids the display-to-field-editor switch of a standard text
/// field. The text wraps and the field grows, so a long purpose stays fully visible.
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
            fieldView?.updateContentHeight()
        }
    }
}

final class PurposeTextFieldView: NSView {
    let textView = SingleParagraphTextView()
    private let placeholderLabel = NSTextField(labelWithString: "")
    private let horizontalInset: CGFloat = 5
    private let verticalInset: CGFloat = 3
    private var contentHeight: CGFloat = 16

    var placeholder = "" {
        didSet {
            placeholderLabel.stringValue = placeholder
            textView.setAccessibilityLabel(placeholder)
        }
    }

    /// The height follows the wrapped text, so SwiftUI gives the row the room it needs.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: contentHeight + verticalInset * 2)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true

        placeholderLabel.font = textView.font
        placeholderLabel.textColor = .placeholderTextColor
        placeholderLabel.lineBreakMode = .byClipping
        placeholderLabel.isHidden = true

        addSubview(placeholderLabel)
        addSubview(textView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let contentFrame = bounds.insetBy(dx: horizontalInset, dy: verticalInset)
        textView.frame = contentFrame
        placeholderLabel.frame = NSRect(
            x: contentFrame.minX,
            y: contentFrame.maxY - contentHeight,
            width: contentFrame.width,
            height: contentHeight
        )
        updateContentHeight()
    }

    func setText(_ text: String) {
        if textView.string != text {
            textView.string = text
        }
        updatePlaceholder()
        updateContentHeight()
    }

    func updatePlaceholder() {
        placeholderLabel.isHidden = !textView.string.isEmpty
    }

    /// Measure the wrapped text and ask SwiftUI for a new height when it changes.
    func updateContentHeight() {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let font = textView.font else { return }

        layoutManager.ensureLayout(for: textContainer)
        let lineHeight = ceil(layoutManager.defaultLineHeight(for: font))
        let height = max(ceil(layoutManager.usedRect(for: textContainer).height), lineHeight)
        guard height != contentHeight else { return }
        contentHeight = height
        invalidateIntrinsicContentSize()
    }
}

/// One paragraph of text that wraps. Return ends editing, and pasted line breaks become spaces.
final class SingleParagraphTextView: NSTextView {
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
