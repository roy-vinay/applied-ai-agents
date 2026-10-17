import AppKit
import SwiftUI
import Tech60Core

struct CardView: View {
    @ObservedObject var model: AppModel
    @State private var isHovering = false
    @State private var index = 0
    @State private var hoverStart: Date?
    private let tick = Timer.publish(every: 8, on: .main, in: .common).autoconnect()
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.6)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if model.visibleStories.isEmpty { empty }
                        ForEach(model.visibleStories) { story in
                            StoryRow(story: story, isNew: model.isNew(story)) { model.open(story) }
                                .id(story.id)
                            Divider().opacity(0.5)
                        }
                    }
                }
                .onReceive(tick) { _ in advance(proxy) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .frame(minWidth: 320, minHeight: 300)
        .onHover { hovering in
            isHovering = hovering
            hoverStart = hovering ? Date() : nil
        }
        .onReceive(tick) { _ in
            // Looking at the card for a moment clears "new since you looked".
            if let start = hoverStart, Date().timeIntervalSince(start) > 2, model.newCount > 0 { model.markViewed() }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Tech60").font(.system(size: 15, weight: .semibold))
            if model.isRefreshing { ProgressView().controlSize(.small) }
            Spacer()
            if model.newCount > 0 {
                Text("\(model.newCount) new since you looked")
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
            }
            Button { model.isPaused.toggle() } label: {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill").font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .help(model.isPaused ? "Resume scrolling" : "Pause scrolling")
        }
        .padding(.bottom, 10)
    }

    private var empty: some View {
        Text(model.isRefreshing ? "Fetching the latest stories…" : "No stories yet. Check your sources from the menu bar.")
            .font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 20)
    }

    private func advance(_ proxy: ScrollViewProxy) {
        let stories = model.visibleStories
        guard !isHovering, !model.isPaused, !reduceMotion, stories.count > 2 else { return }
        index = (index + 1) % stories.count
        withAnimation(.easeInOut(duration: 0.9)) { proxy.scrollTo(stories[index].id, anchor: .top) }
    }
}

struct StoryRow: View {
    let story: Story
    let isNew: Bool
    let open: () -> Void
    @State private var showEvidence = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(isNew ? Color.accentColor : Color.clear).frame(width: 7, height: 7).padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(story.sourceName) · \(Self.relative(story.displayDate))")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                Text(story.title)
                    .font(.system(size: 14, weight: isNew ? .semibold : .medium))
                    .foregroundStyle(isNew ? Color.primary : Color.primary.opacity(0.8))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if case .checked(let text, let evidence) = story.summary {
                    Text(text)
                        .font(.system(size: 12.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Label("AI summary, checked against the source", systemImage: "checkmark.seal")
                            .font(.system(size: 10.5)).foregroundStyle(.secondary)
                        Button("Why?") { showEvidence.toggle() }
                            .buttonStyle(.link).font(.system(size: 10.5))
                            .popover(isPresented: $showEvidence, arrowEdge: .trailing) { EvidenceView(evidence: evidence) }
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
        .help(story.url.absoluteString)
    }

    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}

struct EvidenceView: View {
    let evidence: [SummaryEvidence]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Each sentence and the source text behind it").font(.system(size: 12, weight: .semibold))
            ForEach(evidence, id: \.self) { e in
                VStack(alignment: .leading, spacing: 3) {
                    Text(e.sentence).font(.system(size: 12))
                    Text("Source: \u{201C}\(e.support)\u{201D}").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(width: 340)
    }
}
