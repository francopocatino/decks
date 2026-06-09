import SwiftUI

struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(Self.parse(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case let .heading(level, content):
            inline(content).font(headingFont(level))
        case let .bullet(content):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                inline(content)
            }
        case let .ordered(number, content):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(number).").monospacedDigit()
                inline(content)
            }
        case let .code(content):
            Text(content)
                .font(.system(.callout, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        case let .paragraph(content):
            inline(content)
        case .blank:
            Spacer().frame(height: 2)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title2.bold()
        case 2: .title3.bold()
        default: .headline
        }
    }

    private func inline(_ string: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: string, options: options) {
            return Text(attributed)
        }
        return Text(string)
    }

    private enum Block {
        case heading(Int, String)
        case bullet(String)
        case ordered(String, String)
        case code(String)
        case paragraph(String)
        case blank
    }

    private static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var codeLines: [String] = []
        var inCode = false

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines = []
                }
                inCode.toggle()
                continue
            }
            if inCode {
                codeLines.append(line)
                continue
            }
            if trimmed.isEmpty {
                blocks.append(.blank)
                continue
            }
            if let heading = heading(trimmed) {
                blocks.append(.heading(heading.0, heading.1))
                continue
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                blocks.append(.bullet(String(trimmed.dropFirst(2))))
                continue
            }
            if let ordered = ordered(trimmed) {
                blocks.append(.ordered(ordered.0, ordered.1))
                continue
            }
            blocks.append(.paragraph(trimmed))
        }
        if inCode {
            blocks.append(.code(codeLines.joined(separator: "\n")))
        }
        return blocks
    }

    private static func heading(_ line: String) -> (Int, String)? {
        for level in 1 ... 4 {
            let prefix = String(repeating: "#", count: level) + " "
            if line.hasPrefix(prefix) {
                return (min(level, 3), String(line.dropFirst(prefix.count)))
            }
        }
        return nil
    }

    private static func ordered(_ line: String) -> (String, String)? {
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let number = line[..<dot]
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
        let afterDot = line.index(after: dot)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        return (String(number), String(line[line.index(after: afterDot)...]))
    }
}

struct MarkdownToggle: View {
    @Binding var preview: Bool

    var body: some View {
        HStack {
            Spacer()
            Picker("", selection: $preview) {
                Image(systemName: "pencil").tag(false)
                Image(systemName: "eye").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}
