import AppKit
import SwiftUI

// One always-editable surface: the buffer stays plain markdown (the on-disk
// contract is untouched) and gets styled in place on every change — no
// edit/preview mode. NSTextView also brings Writing Tools, find bar and
// cmd-clickable links for free.
@MainActor
final class MarkdownEditorController {
    weak var textView: NSTextView?

    func bold() { wrap("**", placeholder: "bold") }
    func italic() { wrap("*", placeholder: "italic") }
    func code() { wrap("`", placeholder: "code") }
    func heading() { prefixLines("## ") }
    func list() { prefixLines("- ") }

    func link() {
        guard let textView else { return }
        let range = textView.selectedRange()
        let selected = (textView.string as NSString).substring(with: range)
        let label = selected.isEmpty ? "label" : selected
        textView.insertText("[\(label)](url)", replacementRange: range)
        textView.setSelectedRange(NSRange(location: range.location + (label as NSString).length + 3, length: 3))
        focus()
    }

    private func wrap(_ marker: String, placeholder: String) {
        guard let textView else { return }
        let range = textView.selectedRange()
        let selected = (textView.string as NSString).substring(with: range)
        let body = selected.isEmpty ? placeholder : selected
        textView.insertText(marker + body + marker, replacementRange: range)
        textView.setSelectedRange(NSRange(location: range.location + (marker as NSString).length, length: (body as NSString).length))
        focus()
    }

    private func prefixLines(_ marker: String) {
        guard let textView else { return }
        let string = textView.string as NSString
        let lines = string.lineRange(for: textView.selectedRange())
        let block = string.substring(with: lines)
        let prefixed = block
            .components(separatedBy: "\n")
            .map { $0.isEmpty ? $0 : marker + $0 }
            .joined(separator: "\n")
        textView.insertText(prefixed, replacementRange: lines)
        focus()
    }

    private func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }
}

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let controller: MarkdownEditorController
    var accent: NSColor = .controlAccentColor

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let textView = scroll.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 14)
        scroll.drawsBackground = false
        textView.string = text
        controller.textView = textView
        MarkdownStyler.style(textView, accent: accent)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? NSTextView else { return }
        controller.textView = textView
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            let length = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
            MarkdownStyler.style(textView, accent: accent)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor

        init(_ parent: MarkdownEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            MarkdownStyler.style(textView, accent: parent.accent)
        }

        // Concealed syntax reveals on the caret's line, so restyle as the
        // selection moves between lines.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            MarkdownStyler.style(textView, accent: parent.accent)
        }
    }
}

enum MarkdownStyler {
    @MainActor
    static func style(_ textView: NSTextView, accent: NSColor = .controlAccentColor) {
        // Restyling during dead-key/IME composition (´ + e) breaks it.
        guard !textView.hasMarkedText(), let storage = textView.textStorage else { return }
        let string = storage.string as NSString
        let full = NSRange(location: 0, length: string.length)
        // Syntax markers conceal everywhere except the line being edited.
        let active = string.lineRange(for: textView.selectedRange())
        let base = NSFont.systemFont(ofSize: 13.5)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2.5
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: base,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraph,
        ]

        func conceal(_ range: NSRange, near match: NSRange) {
            if NSIntersectionRange(match, active).length > 0 {
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
            } else {
                storage.addAttributes([
                    .foregroundColor: NSColor.clear,
                    .font: NSFont.systemFont(ofSize: 0.1),
                ], range: range)
            }
        }

        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: full)

        apply(#"^(#{1,3}\s)(.*)$"#, to: storage) { match in
            let level = match.range(at: 1).length - 1
            let size: CGFloat = level == 1 ? 20 : level == 2 ? 17 : 15
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: size, weight: .bold), range: match.range)
            conceal(match.range(at: 1), near: match.range)
        }
        apply(#"\*\*([^*\n]+)\*\*"#, to: storage) { match in
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 13.5, weight: .bold), range: match.range(at: 1))
            conceal(NSRange(location: match.range.location, length: 2), near: match.range)
            conceal(NSRange(location: match.range.location + match.range.length - 2, length: 2), near: match.range)
        }
        apply(#"(?<![\*\w])\*([^*\n]+)\*(?!\*)"#, to: storage) { match in
            let italic = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
            storage.addAttribute(.font, value: italic, range: match.range(at: 1))
            conceal(NSRange(location: match.range.location, length: 1), near: match.range)
            conceal(NSRange(location: match.range.location + match.range.length - 1, length: 1), near: match.range)
        }
        apply(#"`([^`\n]+)`"#, to: storage) { match in
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular), range: match.range(at: 1))
            storage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor.withAlphaComponent(0.16), range: match.range(at: 1))
            conceal(NSRange(location: match.range.location, length: 1), near: match.range)
            conceal(NSRange(location: match.range.location + match.range.length - 1, length: 1), near: match.range)
        }
        apply(#"^([-*])\s"#, to: storage) { match in
            storage.addAttribute(.foregroundColor, value: accent, range: match.range(at: 1))
        }
        apply(#"^>\s.*$"#, to: storage) { match in
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range)
        }
        apply(#"(\[)([^\]\n]+)(\]\(([^)\n\s]+)\))"#, to: storage) { match in
            storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: match.range(at: 2))
            let target = string.substring(with: match.range(at: 4))
            if let url = URL(string: target) {
                storage.addAttribute(.link, value: url, range: match.range(at: 2))
            }
            conceal(match.range(at: 1), near: match.range)
            conceal(match.range(at: 3), near: match.range)
        }
        apply(#"(?<![\(\w])https?://[^\s)\]]+"#, to: storage) { match in
            let target = string.substring(with: match.range)
            if let url = URL(string: target) {
                storage.addAttribute(.link, value: url, range: match.range)
            }
        }
        storage.endEditing()
        textView.typingAttributes = baseAttributes
    }

    private static func apply(_ pattern: String, to storage: NSTextStorage, _ handler: (NSTextCheckingResult) -> Void) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
        let full = NSRange(location: 0, length: (storage.string as NSString).length)
        regex.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            if let match { handler(match) }
        }
    }
}

// Inline cluster, embedded in each section's header row.
struct MarkdownFormatButtons: View {
    let controller: MarkdownEditorController

    var body: some View {
        HStack(spacing: 2) {
            button("bold", "Bold (⌘B)", shortcut: "b") { controller.bold() }
            button("italic", "Italic (⌘I)", shortcut: "i") { controller.italic() }
            button("chevron.left.forwardslash.chevron.right", "Code") { controller.code() }
            button("textformat.size", "Heading") { controller.heading() }
            button("list.bullet", "List") { controller.list() }
            button("link", "Link (⌘K)", shortcut: "k") { controller.link() }
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func button(_ symbol: String, _ help: String, shortcut: Character? = nil, action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 22, height: 18)
        }
        .buttonStyle(.borderless)
        .help(help)
        if let shortcut {
            button.keyboardShortcut(KeyEquivalent(shortcut), modifiers: .command)
        } else {
            button
        }
    }
}
