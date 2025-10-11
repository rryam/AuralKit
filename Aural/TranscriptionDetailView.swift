import SwiftUI
import AuralKit

// MARK: - Sub-views

struct MetadataRowView: View {
    let label: String
    let icon: String
    let value: String

    var body: some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body)
        }
    }
}

struct MetadataSectionView: View {
    let record: TranscriptionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MetadataRowView(
                label: "Language",
                icon: "globe",
                value: record.locale.localizedString(
                    forIdentifier: record.locale.identifier
                ) ?? record.locale.identifier
            )

            MetadataRowView(
                label: "Date",
                icon: "calendar",
                value: record.timestamp.formatted(date: .abbreviated, time: .omitted)
            )

            MetadataRowView(
                label: "Time",
                icon: "clock",
                value: record.timestamp.formatted(date: .omitted, time: .shortened)
            )

            MetadataRowView(
                label: "Word Count",
                icon: "textformat.size",
                value: "\(record.text.split(separator: " ").count) words"
            )

            if !record.timeRange.isEmpty {
                MetadataRowView(
                    label: "Duration",
                    icon: "timer",
                    value: record.timeRange
                )
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

struct TranscriptSectionView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcript")
                .font(.headline)

            Text(text)
                .font(.body)
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
        }
    }
}

struct AlternativesSectionView: View {
    let alternatives: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Alternative Interpretations")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(alternatives.prefix(5).enumerated()), id: \.offset) { index, alternative in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .trailing)

                        Text(alternative)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
            .background(Color.indigo.opacity(0.05))
            .cornerRadius(12)
        }
    }
}

struct ActionButtonsView: View {
    let text: String
    @Binding var isCopied: Bool

    var body: some View {
        HStack(spacing: 12) {
            ShareLink(item: text) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.indigo)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }

            Button {
                copyToClipboard(text)
            } label: {
                Label(isCopied ? "Copied!" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isCopied ? Color.green : Color.gray.opacity(0.2))
                    .foregroundStyle(isCopied ? .white : .primary)
                    .cornerRadius(12)
            }
        }
    }

    private func copyToClipboard(_ text: String) {
#if os(iOS)
        UIPasteboard.general.string = text
#elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#endif

        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCopied = false
        }
    }
}

// MARK: - Main View

struct TranscriptionDetailView: View {
    let record: TranscriptionRecord
    @State private var isCopied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MetadataSectionView(record: record)

                TranscriptSectionView(text: record.text)

                ActionButtonsView(text: record.text, isCopied: $isCopied)
            }
            .padding()
        }
        .navigationTitle("Transcription Details")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}
