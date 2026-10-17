import AppKit
import SwiftUI
import Tech60Core

// Design: a translucent card that sits on the desktop like a Mac widget. Headlines are set in Apple's
// serif (New York) so the card reads as news; everything else is SF Pro. The one bold element is the
// "60" dial in the wordmark. Each source has its own color badge, so you can tell sources apart at a glance.
enum Palette {
    static let accent = Color(red: 0.18, green: 0.36, blue: 0.92)
    static let checked = Color(red: 0.13, green: 0.60, blue: 0.40)
    static let brief = Color(red: 0.93, green: 0.55, blue: 0.13)
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
    @State private var expandedID: String?
    private let tick = Timer.publish(every: 8, on: .main, in: .common).autoconnect()
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)
            if model.briefIDs != nil { briefBanner }
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if model.visibleClusters.isEmpty { empty }
                        ForEach(Array(model.visibleClusters.enumerated()), id: \.element.id) { offset, cluster in
                            StoryRow(cluster: cluster, isNew: model.isNew(cluster), isLead: offset == 0,
                                     isExpanded: expandedID == cluster.id,
                                     isFaded: model.isFaded(cluster),
                                     topics: model.topicNames(for: cluster),
                                     modelProblem: model.summaryProblem,
                                     toggle: { toggle(cluster) },
                                     open: { model.open($0) })
                                .id(cluster.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .onReceive(tick) { _ in advance(proxy) }
                .onChange(of: model.briefIDs) { _ in
                    if let first = model.visibleClusters.first { proxy.scrollTo(first.id, anchor: .top) }
                }
            }
            // Fade the last row into the footer instead of cutting it off.
            .mask(VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 28)
            })
            footer
        }
        .frame(minWidth: 320, minHeight: 300)
        .onAppear {
            guard model.isDemo else { return }
            if ProcessInfo.processInfo.arguments.contains("--brief") { model.showBrief() }
            expandedID = model.visibleClusters.first?.id
        }
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
            Button { model.refreshNow() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(model.isRefreshing ? 360 : 0))
                    .animation(model.isRefreshing && !reduceMotion
                               ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                               value: model.isRefreshing)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(model.isRefreshing)
            .keyboardShortcut("r", modifiers: .command)
            .help("Check sources for new stories")
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

    private var briefBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "sunrise.fill").foregroundStyle(Palette.brief)
            Text("Your brief").font(.system(size: 13, weight: .semibold, design: .serif))
            Text(model.visibleClusters.count == 1 ? "1 story" : "\(model.visibleClusters.count) stories")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Button("Show all") { withAnimation { model.closeBrief() } }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.accent)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.brief.opacity(0.13)))
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if model.isRefreshing {
                ProgressView().controlSize(.mini)
                Text("Checking sources")
            } else {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.checked)
                Text("Tap a story for its summary")
                Spacer()
                if let updated = model.lastUpdated {
                    Text("Updated \(StoryRow.relative(updated))")
                }
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

    private func toggle(_ cluster: StoryCluster) {
        let opening = expandedID != cluster.id
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) {
            expandedID = opening ? cluster.id : nil
        }
        if opening { model.summarize(cluster.summaryStory) }
    }

    private func advance(_ proxy: ScrollViewProxy) {
        let stories = model.visibleClusters
        guard !isHovering, expandedID == nil, model.briefIDs == nil, !model.isPaused, !reduceMotion, stories.count > 2 else { return }
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
    var size: CGFloat = 22
    var body: some View {
        let color = Palette.color(for: name)
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(color))
            .accessibilityHidden(true)
    }
}

struct StoryRow: View {
    let cluster: StoryCluster
    let isNew: Bool
    let isLead: Bool
    let isExpanded: Bool
    let isFaded: Bool
    let topics: [String]
    let modelProblem: String?
    let toggle: () -> Void
    let open: (Story) -> Void
    private var story: Story { cluster.lead }
    /// The story whose summary this row shows (may be another source's copy of the same news).
    private var summarized: Story { cluster.summaryStory }
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
                    if let topic = topics.first {
                        Text(topic)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                            .padding(.horizontal, 6).padding(.vertical, 1.5)
                            .background(Capsule().fill(Palette.accent.opacity(0.11)))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .opacity(isHovered || isExpanded ? 1 : 0)
                }
                Text(story.title)
                    .font(.system(size: isLead ? 17.5 : 14.5, weight: .semibold, design: .serif))
                    .foregroundStyle(.primary)
                    .lineSpacing(1.5)
                    .lineLimit(isExpanded ? nil : (isLead ? 4 : 3))
                    .fixedSize(horizontal: false, vertical: true)
                if !cluster.others.isEmpty && !isExpanded { alsoCovered }
                if isExpanded {
                    summary
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    HStack(spacing: 8) {
                        Button { open(story) } label: {
                            HStack(spacing: 4) {
                                Text("Read article")
                                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold))
                            }
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Palette.accent))
                        }
                        .buttonStyle(.plain)
                        .help(story.url.absoluteString)
                        if case .checked(_, let evidence) = summarized.summary {
                            Button { showEvidence.toggle() } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.seal.fill")
                                    Text("Checked")
                                }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Palette.checked)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(Palette.checked.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                            .help("See the source text behind each sentence")
                            .popover(isPresented: $showEvidence, arrowEdge: .trailing) { EvidenceView(evidence: evidence) }
                        }
                    }
                    .padding(.top, 4)
                    if !cluster.others.isEmpty { otherSources }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, isLead ? 12 : 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(isExpanded ? 0.055 : (isHovered ? 0.045 : (isLead ? 0.03 : 0))))
        )
        .opacity(isFaded && !isHovered && !isExpanded ? 0.5 : 1)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: toggle)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isExpanded ? "Hides the summary" : "Shows a summary")
    }

    /// Collapsed: the other sources on the same news, as a row of badges.
    private var alsoCovered: some View {
        HStack(spacing: 6) {
            HStack(spacing: -5) {
                ForEach(cluster.others.prefix(4), id: \.id) { other in
                    SourceBadge(name: other.sourceName, size: 16)
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(.background, lineWidth: 1.5))
                }
            }
            Text(cluster.others.count == 1 ? "Also in \(cluster.others[0].sourceName)"
                 : "Also in \(cluster.others.count) more sources")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 1)
    }

    /// Expanded: every other source's headline, each opening its own article.
    private var otherSources: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Also covered by")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
            ForEach(cluster.others, id: \.id) { other in
                Button { open(other) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        SourceBadge(name: other.sourceName, size: 16)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(other.sourceName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Palette.color(for: other.sourceName))
                            Text(other.title)
                                .font(.system(size: 12))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(other.url.absoluteString)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder private var summary: some View {
        switch summarized.summary {
        case .checked(let text, _):
            Text(text)
                .font(.system(size: 12.5))
                .lineSpacing(2.5)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.top, 2)
        case .pending:
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("Summarizing on your Mac")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
        case .withheld(let reason):
            fallback(note: reason)
        case .none:
            fallback(note: modelProblem)
        }
    }

    /// No checked summary: show what the feed itself says, labeled as such, plus why there's no summary.
    @ViewBuilder private func fallback(note: String?) -> some View {
        let excerpt = Self.excerpt(summarized.sourceText.isEmpty ? story.sourceText : summarized.sourceText)
        VStack(alignment: .leading, spacing: 6) {
            if !excerpt.isEmpty {
                Text(excerpt)
                    .font(.system(size: 12.5))
                    .lineSpacing(2.5)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Text("From the feed, not an AI summary.")
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
            if let note {
                Label(note, systemImage: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }

    static func excerpt(_ text: String) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > 280 else { return clean }
        let cut = clean.prefix(280)
        if let end = cut.lastIndex(where: { ".!?".contains($0) }), cut.distance(from: cut.startIndex, to: end) > 120 {
            return String(cut[...end])
        }
        return cut.trimmingCharacters(in: .whitespaces) + "…"
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
