import AppKit
import SwiftUI
import Tech60Core

// Design ("Edition"): the card reads like a small newspaper. A serif masthead with today's date and edition,
// section tabs, a lead story with its picture, and a ranked list with thumbnails. Heat is a small ring that
// fills as more outlets and readers pick a story up; there are no rank numbers. Opening a story shows its
// checked summary and who covered it, earliest first. Light and dark follow macOS.
enum Palette {
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }

    static let paper = dynamic(0xFFFFFF, 0x151A23)
    static let ink = dynamic(0x17181C, 0xECEEF2)
    static let body = dynamic(0x45474E, 0xC3C8D1)
    static let secondary = dynamic(0x666A73, 0x9AA1AD)
    static let rule = dynamic(0xE5E2DE, 0x2A313D)
    static let chip = dynamic(0xF2F0ED, 0x232A35)
    static let photo = dynamic(0xDCE3EE, 0x2B3446)
    static let accent = dynamic(0xC2410C, 0xFF8A3D)
    static let live = dynamic(0xD92D20, 0xFF6B5E)
    static let checked = dynamic(0x2F7A4A, 0x5ED3A7)
    static let brief = dynamic(0xB45309, 0xF2A93B)

    static let sourceColors: [Color] = [
        Color(red: 0.18, green: 0.36, blue: 0.92), Color(red: 0.48, green: 0.25, blue: 0.76),
        Color(red: 0.85, green: 0.28, blue: 0.06), Color(red: 0.05, green: 0.49, blue: 0.53),
        Color(red: 0.80, green: 0.20, blue: 0.40), Color(red: 0.30, green: 0.50, blue: 0.16),
        Color(red: 0.65, green: 0.45, blue: 0.05), Color(red: 0.36, green: 0.42, blue: 0.52),
    ]

    static func color(for source: String) -> Color {
        let sum = source.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return sourceColors[sum % sourceColors.count]
    }
}

enum When {
    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    /// "8:30 AM" today, "Oct 16" before that.
    static func clock(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func edition(_ date: Date = Date()) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case ..<12: return "Morning edition"
        case ..<17: return "Afternoon edition"
        default: return "Evening edition"
        }
    }
}

struct CardView: View {
    @ObservedObject var model: AppModel
    @State private var openID: String?
    @State private var hoverStart: Date?
    private let tick = Timer.publish(every: 4, on: .main, in: .common).autoconnect()
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private var openCluster: StoryCluster? {
        guard let id = openID else { return nil }
        return model.clusters.first { $0.id == id || $0.stories.contains { $0.id == id } }
    }

    var body: some View {
        ZStack {
            if let cluster = openCluster {
                StoryDetail(cluster: cluster, model: model, backTitle: backTitle) { show(nil) }
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            } else {
                front.transition(.opacity)
            }
        }
        .frame(minWidth: 340, minHeight: 360)
        .background(Palette.paper)
        .foregroundStyle(Palette.ink)
        .onAppear {
            if model.isDemo, ProcessInfo.processInfo.arguments.contains("--open") { openID = model.visibleClusters.first?.id }
        }
        .onHover { hoverStart = $0 ? Date() : nil }
        .onReceive(tick) { _ in
            // Looking at the card for a moment clears "new since you looked".
            if let start = hoverStart, Date().timeIntervalSince(start) > 2, model.newCount > 0 { model.markViewed() }
        }
    }

    private var backTitle: String {
        if model.briefIDs != nil { return "Your brief" }
        if let tab = model.topicTab, let t = model.allTopics.first(where: { $0.id == tab }) { return Topics.shortName(t) }
        return model.sortMode == .hot ? "Top stories" : "Latest"
    }

    private func show(_ cluster: StoryCluster?) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { openID = cluster?.id }
        if let cluster { model.summarize(cluster.summaryStory) }
    }

    // MARK: Front page

    private var front: some View {
        VStack(alignment: .leading, spacing: 0) {
            masthead
            if model.briefIDs != nil { briefBanner }
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let rows = model.visibleClusters
                    if rows.isEmpty { empty }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { offset, cluster in
                        if offset == 0 {
                            LeadStory(cluster: cluster, model: model) { show(cluster) }
                        } else {
                            StoryLine(cluster: cluster, model: model, isLast: offset == rows.count - 1) { show(cluster) }
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .mask(VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 24)
            })
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Wordmark()
                Spacer(minLength: 8)
                if model.newCount > 0 {
                    Text("\(model.newCount) new")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .fixedSize()
                        .help("\(model.newCount) new since you last looked")
                }
                RoundButton(symbol: "arrow.clockwise", label: "Refresh", spinning: model.isRefreshing) { model.refreshNow() }
                    .keyboardShortcut("r", modifiers: .command)
                RoundButton(symbol: "slider.horizontal.3", label: "Sources, topics, and brief") { model.openSettings() }
            }
            HStack {
                Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                Spacer()
                Text(model.isRefreshing ? "Checking sources" : When.edition())
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.secondary)
            .padding(.top, 9)
            .padding(.bottom, 7)
            Rectangle().fill(Palette.ink).frame(height: 1)
            Rectangle().fill(Palette.ink).frame(height: 1).padding(.top, 2)
            tabs
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                tab("Top", selected: model.topicTab == nil && model.sortMode == .hot) {
                    model.topicTab = nil; model.sortMode = .hot; model.closeBrief()
                }
                tab("Latest", selected: model.topicTab == nil && model.sortMode == .latest) {
                    model.topicTab = nil; model.sortMode = .latest; model.closeBrief()
                }
                ForEach(model.tabTopics) { topic in
                    tab(Topics.shortName(topic), selected: model.topicTab == topic.id) {
                        model.topicTab = topic.id; model.closeBrief(); model.loadImages()
                    }
                }
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.rule).frame(height: 1) }
    }

    private func tab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? Palette.ink : Palette.secondary)
                .padding(.top, 9)
                .padding(.bottom, 8)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(selected ? Palette.accent : .clear).frame(height: 2.5)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var briefBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "sunrise.fill").foregroundStyle(Palette.brief)
            Text("Your brief").font(.system(size: 13, weight: .semibold, design: .serif))
            Text(model.visibleClusters.count == 1 ? "1 story" : "\(model.visibleClusters.count) stories")
                .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            Spacer()
            Button("Show all") { withAnimation { model.closeBrief() } }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.accent)
        }
        .padding(.horizontal, 18).padding(.vertical, 9)
        .background(Palette.chip)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.briefIDs != nil ? "Nothing new since your last brief"
                 : model.isRefreshing ? "Fetching the latest stories" : "No stories here yet")
                .font(.system(size: 17, weight: .semibold, design: .serif))
            Text(model.topicTab != nil ? "Nothing on this topic in the last two days." : "Choose sources with the settings button above.")
                .font(.system(size: 12.5)).foregroundStyle(Palette.secondary)
        }
        .padding(18)
    }
}

/// "Tech" in the serif masthead face, with "60" inside a ring.
struct Wordmark: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("Tech")
                .font(.system(size: 28, weight: .heavy, design: .serif))
                .kerning(-0.6)
            ZStack {
                Circle().stroke(Palette.rule, lineWidth: 2.6)
                Circle()
                    .trim(from: 0, to: 0.82)
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("60")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Palette.accent)
            }
            .frame(width: 25, height: 25)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tech60")
    }
}

struct RoundButton: View {
    let symbol: String
    let label: String
    var spinning = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(spinning ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: spinning)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Palette.chip))
                .foregroundStyle(Palette.body)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// How hot a story is: a ring that fills as more outlets and readers pick it up. No numbers.
struct HeatRing: View {
    let fraction: Double
    var size: CGFloat = 13
    var body: some View {
        ZStack {
            Circle().stroke(Palette.rule, lineWidth: size * 0.19)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: size * 0.19, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityLabel(fraction > 0.66 ? "Very hot" : fraction > 0.33 ? "Warm" : "Quiet")
    }
}

struct DevelopingBadge: View {
    var onPhoto = false
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(onPhoto ? Color.white : Palette.live).frame(width: 6, height: 6)
            Text("Developing")
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(onPhoto ? Color.white : Palette.live)
        .padding(.horizontal, onPhoto ? 8 : 0).padding(.vertical, onPhoto ? 3 : 0)
        .background(Capsule().fill(onPhoto ? Palette.live : .clear))
        .help("Three or more outlets in the last few hours")
    }
}

/// A story's picture. Hidden when there isn't one, except in sample mode, where a tinted block stands in.
struct StoryPhoto: View {
    let url: URL?
    let placeholder: Bool
    let height: CGFloat
    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Palette.photo
                }
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
        } else if placeholder {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.photo)
                .frame(height: height)
                .accessibilityHidden(true)
        }
    }
}

/// The lead story: picture, kicker, big serif headline, and its checked summary as the deck.
struct LeadStory: View {
    let cluster: StoryCluster
    @ObservedObject var model: AppModel
    let open: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 7) {
                if cluster.imageURL != nil || model.isDemo {
                    StoryPhoto(url: cluster.imageURL, placeholder: model.isDemo, height: 150)
                        .overlay(alignment: .topLeading) {
                            if cluster.isDeveloping() { DevelopingBadge(onPhoto: true).padding(8) }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if cluster.sourceCount > 1 {
                                Text("\(cluster.sourceCount) outlets")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Palette.ink)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(Palette.paper))
                                    .padding(8)
                            }
                        }
                        .padding(.bottom, 2)
                }
                Kicker(cluster: cluster, model: model, long: true)
                Text(cluster.lead.title)
                    .font(.system(size: 21, weight: .bold, design: .serif))
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                if case .checked(let text, _) = cluster.summaryStory.summary {
                    Text(text)
                        .font(.system(size: 13.5, design: .serif))
                        .foregroundStyle(Palette.body)
                        .lineSpacing(2)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovered ? Palette.chip.opacity(0.6) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.rule).frame(height: 1).padding(.horizontal, 18) }
        .help(cluster.lead.url.absoluteString)
    }
}

/// The line above a headline: heat ring, section, and when it first came out.
struct Kicker: View {
    let cluster: StoryCluster
    @ObservedObject var model: AppModel
    let long: Bool

    var body: some View {
        let first = cluster.firstReport
        HStack(spacing: 6) {
            HeatRing(fraction: model.heatFraction(cluster))
            if let kicker = model.kicker(for: cluster) {
                Text(kicker).font(.system(size: 11.5, weight: .bold)).foregroundStyle(Palette.accent)
            }
            Text(long ? "First reported \(When.clock(first.displayDate)) by \(first.sourceName)"
                      : cluster.sourceCount > 1 ? "\(cluster.sourceCount) outlets, first \(When.clock(first.displayDate))"
                      : "\(first.sourceName), \(When.clock(first.displayDate))")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
            if !long, cluster.isDeveloping() { DevelopingBadge() }
            if model.isNew(cluster) {
                Circle().fill(Palette.accent).frame(width: 6, height: 6).accessibilityLabel("New")
            }
        }
    }
}

/// Every story after the lead: serif headline, kicker, and a thumbnail when the source has a picture.
struct StoryLine: View {
    let cluster: StoryCluster
    @ObservedObject var model: AppModel
    let isLast: Bool
    let open: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(cluster.lead.title)
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .lineSpacing(1)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Kicker(cluster: cluster, model: model, long: false)
                }
                Spacer(minLength: 0)
                if cluster.imageURL != nil || model.isDemo {
                    StoryPhoto(url: cluster.imageURL, placeholder: model.isDemo, height: 58)
                        .frame(width: 58)
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovered ? Palette.chip.opacity(0.6) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .overlay(alignment: .bottom) {
            if !isLast { Rectangle().fill(Palette.rule).frame(height: 1).padding(.horizontal, 18) }
        }
        .help(cluster.lead.url.absoluteString)
    }
}

// MARK: An opened story

struct StoryDetail: View {
    let cluster: StoryCluster
    @ObservedObject var model: AppModel
    let backTitle: String
    let back: () -> Void
    @State private var showEvidence = false

    private var summarized: Story { cluster.summaryStory }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: back) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                        Text(backTitle)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Wordmark().scaleEffect(0.7, anchor: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.rule).frame(height: 1) }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 9) {
                    if cluster.imageURL != nil || model.isDemo {
                        StoryPhoto(url: cluster.imageURL, placeholder: model.isDemo, height: 160)
                    }
                    Kicker(cluster: cluster, model: model, long: true)
                    Text(cluster.lead.title)
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    summary
                    coverage.padding(.top, 8)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }

            Button { model.open(cluster.lead) } label: {
                Text("Read on \(cluster.lead.sourceName)")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Palette.paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.ink))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
            .help(cluster.lead.url.absoluteString)
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
            .padding(.top, 8)
        }
    }

    @ViewBuilder private var summary: some View {
        switch summarized.summary {
        case .checked(let text, let evidence):
            Text(text)
                .font(.system(size: 15, design: .serif))
                .lineSpacing(3.5)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack(spacing: 5) {
                Image(systemName: "checkmark").font(.system(size: 10.5, weight: .heavy))
                Text("Checked against \(summarized.sourceName)'s text")
                Button("See how") { showEvidence.toggle() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.secondary)
                    .underline()
                    .popover(isPresented: $showEvidence, arrowEdge: .bottom) { EvidenceView(evidence: evidence) }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Palette.checked)
        case .pending:
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("Summarizing on your Mac")
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Palette.secondary)
            .padding(.vertical, 6)
        case .withheld(let reason):
            fallback(note: reason)
        case .none:
            fallback(note: model.summaryProblem)
        }
    }

    /// No checked summary: what the feed itself says, labeled, and why there's no summary.
    @ViewBuilder private func fallback(note: String?) -> some View {
        let excerpt = Self.excerpt(summarized.sourceText.isEmpty ? cluster.lead.sourceText : summarized.sourceText)
        if !excerpt.isEmpty {
            Text(excerpt)
                .font(.system(size: 14.5, design: .serif))
                .lineSpacing(3)
                .foregroundStyle(Palette.body)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Text("From the feed, not an AI summary.")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary)
        }
        if let note {
            Label(note, systemImage: "info.circle")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Who covered it, earliest first, each opening its own article.
    private var coverage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Coverage")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Palette.secondary)
                .padding(.bottom, 4)
            let stories = cluster.stories.sorted { $0.displayDate < $1.displayDate }
            ForEach(Array(stories.enumerated()), id: \.element.id) { i, story in
                Button { model.open(story) } label: {
                    HStack(alignment: .top, spacing: 9) {
                        SourceBadge(name: story.sourceName, size: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(story.sourceName).font(.system(size: 12.5, weight: .bold))
                            Text(Self.coverageLine(story))
                                .font(.system(size: 12.5))
                                .foregroundStyle(Palette.body)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 6)
                        Text(When.clock(story.displayDate))
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.secondary)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(story.url.absoluteString)
                .overlay(alignment: .bottom) {
                    if i < stories.count - 1 { Rectangle().fill(Palette.rule).frame(height: 1) }
                }
            }
        }
    }

    static func coverageLine(_ story: Story) -> String {
        if let points = story.points {
            let comments = story.comments.map { ", \($0) comments" } ?? ""
            return "\(points) points\(comments)"
        }
        return story.title
    }

    static func excerpt(_ text: String) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > 320 else { return clean }
        let cut = clean.prefix(320)
        if let end = cut.lastIndex(where: { ".!?".contains($0) }), cut.distance(from: cut.startIndex, to: end) > 120 {
            return String(cut[...end])
        }
        return cut.trimmingCharacters(in: .whitespaces) + "…"
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
