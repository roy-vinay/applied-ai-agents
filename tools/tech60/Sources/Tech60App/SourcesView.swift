import SwiftUI
import Tech60Core

struct SourcesView: View {
    @ObservedObject var model: AppModel
    @State private var newName = ""
    @State private var newURL = ""
    @State private var isOfficial = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sources").font(.title3.weight(.semibold))
            Text("Official sources get short summaries, checked against the source. Publishers and Hacker News show headline and link only.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List {
                ForEach($model.sources) { $source in
                    HStack {
                        Toggle(isOn: $source.isEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name)
                                Text(detail(for: source)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 260)
            GroupBox("Add an RSS or Atom feed") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Name", text: $newName)
                    TextField("https://example.com/feed.xml", text: $newURL)
                    Toggle("Official source from the company itself (summarize it)", isOn: $isOfficial)
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    Button("Add feed", action: add)
                }
                .padding(6)
            }
            Toggle("Short summaries with Apple's on-device model", isOn: $model.summariesEnabled)
            if let problem = model.summaryProblem {
                Text(problem).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(width: 460)
    }

    private func detail(for source: Source) -> String {
        var parts = [source.isPrimary ? "Official, summarized" : "Headline and link"]
        if let s = model.status(for: source) {
            if let e = s.lastError { parts.append("Last check failed: \(e)") }
            else if let ok = s.lastSuccess { parts.append("Updated \(StoryRow.relative(ok))") }
        }
        return parts.joined(separator: " · ")
    }

    private func add() {
        let trimmed = newURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https", url.host != nil else {
            error = "Enter a full https address for the feed."
            return
        }
        let name = newName.trimmingCharacters(in: .whitespaces)
        model.addFeed(name: name.isEmpty ? (url.host ?? "Feed") : name, url: url, isOfficial: isOfficial)
        newName = ""; newURL = ""; isOfficial = false; error = nil
    }
}
