import AppKit
import SwiftUI
import Tech60Core

// Design: a translucent card that sits on the desktop like a Mac widget. Headlines are set in Apple's
// serif (New York) so the card reads as news; everything else is SF Pro. The one bold element is the
// "60" dial in the wordmark. Each source has its own color badge, so you can tell sources apart at a glance.
enum Palette {
    static let accent = Color(red: 0.18, green: 0.36, blue: 0.92)
    static let checked = Color(red: 0.13, green: 0.60, blue: 0.40)
    static let sourceColors: [Color] = [
        Color(red: 0.18, green: 0.36, blue: 0.92), Color(red: 0.55, green: 0.33, blue: 0.86),
        Color(red: 0.90, green: 0.42, blue: 0.20), Color(red: 0.10, green: 0.60, blue: 0.62),
        Color(red: 0.86, green: 0.26, blue: 0.45), Color(red: 0.36, green: 0.55, blue: 0.20),
        Color(red: 0.75, green: 0.55, blue: 0.10), Color(red: 0.40, green: 0.45, blue: 0.55),
    ]

    static func color(for source: String) -> Color {
        let sum = source.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return sourceColors[sum % sourceColors.count]
    }
}

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
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if model.visibleStories.isEmpty { empty }
                        ForEach(Array(model.visibleStories.enumerated()), id: \.element.id) { offset, story in
                            StoryRow(story: story, isNew: model.isNew(story), isLead: offset == 0) { model.open(story) }
                                .id(story.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .onReceive(tick) { _ in advance(proxy) }
            }
            footer
        }
        .frame(minWidth: 320, minHeight: 300)
        .background(.regularMaterial)
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
        HStack(alignment: .center, spacing: 10) {
            Wordmark()
            Spacer(minLength: 8)
            if model.newCount > 0 {
                Text("\(model.newCount) new")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Palette.accent))
                    .help("\(model.newCount) new since you last looked")
            }
            Button { model.isPaused.toggle() } label: {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(model.isPaused ? "Resume scrolling" : "Pause scrolling")
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if model.isRefreshing {
                ProgressView().controlSize(.mini)
                Text("Checking sources")
            } else {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.checked)
                Text("Summaries are checked against their source")
            }
            Spacer()
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.03))
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.isRefreshing ? "Fetching the latest stories" : "No stories yet")
                .font(.system(size: 15, weight: .semibold, design: .serif))
            Text("Choose sources from the newspaper icon in the menu bar.")
                .font(.system(size: 12.5)).foregroundStyle(.secondary)
        }
        .padding(14)
    }

    private func advance(_ proxy: ScrollViewProxy) {
        let stories = model.visibleStories
        guard !isHovering, !model.isPaused, !reduceMotion, stories.count > 2 else { return }
        index = (index + 1) % stories.count
        withAnimation(.easeInOut(duration: 0.9)) { proxy.scrollTo(stories[index].id, anchor: .top) }
    }
}

/// "Tech" in rounded bold, "60" inside a dial: sixty words, at a glance.
struct Wordmark: View {
    var body: some View {
        HStack(spacing: 5) {
            Text("Tech")
                .font(.system(size: 19, weight: .heavy, design: .rounded))
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.82)
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("60")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.accent)
            }
            .frame(width: 27, height: 27)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tech60")
    }
}

struct SourceBadge: View {
    let name: String
    var body: some View {
        let color = Palette.color(for: name)
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color))
            .accessibilityHidden(true)
    }
}

struct StoryRow: View {
    let story: Story
    let isNew: Bool
    let isLead: Bool
    let open: () -> Void
    @State private var showEvidence = false
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            SourceBadge(name: story.sourceName).padding(.top, 1)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(story.sourceName)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Palette.color(for: story.sourceName))
                    Text(Self.relative(story.displayDate))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                    if isNew {
                        Circle().fill(Palette.accent).frame(width: 6, height: 6)
                            .accessibilityLabel("New")
                    }
                }
                Text(story.title)
                    .font(.system(size: isLead ? 17.5 : 14.5, weight: .semibold, design: .serif))
                    .foregroundStyle(.primary)
                    .lineSpacing(1.5)
                    .lineLimit(isLead ? 4 : 3)
                    .fixedSize(horizontal: false, vertical: true)
                if case .checked(let text, let evidence) = story.summary {
                    Text(text)
                        .font(.system(size: 12.5))
                        .lineSpacing(2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 1)
                    Button { showEvidence.toggle() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                            Text("Checked")
                            Text("See sources").foregroundStyle(Palette.accent)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.checked)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Palette.checked.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .help("See the source text behind each sentence")
                    .popover(isPresented: $showEvidence, arrowEdge: .trailing) { EvidenceView(evidence: evidence) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, isLead ? 12 : 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.06 : (isLead ? 0.035 : 0)))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Where each sentence comes from")
                .font(.system(size: 13, weight: .semibold, design: .serif))
            ForEach(evidence, id: \.self) { e in
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.sentence).font(.system(size: 12))
                    HStack(alignment: .top, spacing: 6) {
                        Rectangle().fill(Palette.checked).frame(width: 2)
                        Text(e.support).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}
