import SwiftUI
import Tech60Core

struct SourcesView: View {
    @ObservedObject var model: AppModel
    @State private var newName = ""
    @State private var newURL = ""
    @State private var isOfficial = false
    @State private var error: String?

    var body: some View {
        TabView {
            sourcesTab.tabItem { Text("Sources") }
            TopicsView(model: model).tabItem { Text("Topics") }
            BriefSettingsView(model: model).tabItem { Text("Daily brief") }
        }
        .padding(12)
        .frame(width: 480, height: 600)
    }

    private var sourcesTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Techmeme anchors the feed: its editors pick what matters. Deals, reviews, how-tos, gaming, and small Hacker News posts are filtered out, and an on-device editor drops minor stories from Top.")
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
        .padding(14)
    }

    private func detail(for source: Source) -> String {
        var parts = [source.isPrimary ? "Official, summarized" : "Headline and link"]
        if let s = model.status(for: source) {
            if let e = s.lastError { parts.append("Last check failed: \(e)") }
            else if let ok = s.lastSuccess { parts.append("Updated \(When.relative(ok))") }
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

struct TopicsView: View {
    @ObservedObject var model: AppModel
    @State private var name = ""
    @State private var keywords = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stories on topics you follow move to the top of the card and go first in your brief. Everything else is dimmed.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List {
                ForEach(model.allTopics) { topic in
                    HStack {
                        Toggle(isOn: binding(for: topic)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(topic.name)
                                Text(topic.keywords.prefix(8).joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        if topic.id.hasPrefix("custom-") {
                            Spacer()
                            Button { model.removeTopic(topic) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .help("Remove this topic")
                        }
                    }
                }
            }
            .frame(minHeight: 280)
            HStack {
                Text(model.taste.isEmpty && model.hiddenIDs.isEmpty
                     ? "Right-click any story for More like this or Less like this."
                     : "Tech60 is tuning your feed from \(model.taste.terms.count) words you liked or disliked.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reset") { model.resetTaste() }
                    .disabled(model.taste.isEmpty && model.hiddenIDs.isEmpty)
            }
            GroupBox("Add your own topic") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Name, like Robotics", text: $name)
                    TextField("Words to look for, separated by commas", text: $keywords)
                    Button("Add topic") {
                        if model.addTopic(name: name, keywords: keywords) { name = ""; keywords = "" }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(6)
            }
        }
        .padding(14)
    }

    private func binding(for topic: Topic) -> Binding<Bool> {
        Binding(
            get: { model.followedTopicIDs.contains(topic.id) },
            set: { on in if on { model.followedTopicIDs.insert(topic.id) } else { model.followedTopicIDs.remove(topic.id) } }
        )
    }
}

struct BriefSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Once a day, Tech60 sends one notification with the five stories that matter most since your last brief: the ones covered by several sources, on topics you follow, or from the company itself.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Picker("Send my brief at", selection: $model.briefHour) {
                Text("Off").tag(Int?.none)
                ForEach(5..<13) { hour in Text(Self.label(hour)).tag(Int?.some(hour)) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 260)
            Text("If your Mac is asleep at that time, the brief comes when it wakes. Click the notification to see the stories on the card.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Send a brief now") { Task { await model.sendBrief() } }
            Spacer()
        }
        .padding(14)
    }

    static func label(_ hour: Int) -> String {
        var c = DateComponents(); c.hour = hour; c.minute = 0
        let date = Calendar.current.date(from: c) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}
