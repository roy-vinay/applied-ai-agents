import Foundation

/// Decides whether a finished utterance is a question or a direct prompt worth answering.
public enum QuestionDetector {
    static let openers: [String] = [
        "what", "why", "how", "when", "where", "who", "which", "whose",
        "can you", "could you", "would you", "will you", "do you", "did you", "have you", "has your",
        "are you", "were you", "is there", "is it", "was there", "should", "if you",
        "tell me", "tell us", "walk me", "walk us", "describe", "give me", "give us", "talk about",
        "talk me", "talk us", "share", "explain", "help me understand", "take me through", "say more",
        "i'd love to hear", "i would love to hear", "i'm curious", "i am curious", "let's talk about",
    ]
    static let inner: [String] = ["tell me about", "walk me through", "walk us through", "how would you",
                                  "what would you", "what was", "how did you", "why did you", "can you give"]

    public static func isQuestion(_ utterance: String) -> Bool {
        let s = utterance.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Lexicon.words(s).count >= 3 else { return false }
        if s.hasSuffix("?") { return true }
        // Speech recognizers often drop the question mark; look at how the last sentence opens.
        let last = Lexicon.sentences(s).last ?? s
        if openers.contains(where: { last.hasPrefix($0 + " ") }) { return true }
        return inner.contains(where: { last.contains($0) })
    }
}

/// How a session may listen. There are three modes and only three; there is no hidden capture.
public enum CaptureMode: String, Codable, CaseIterable, Sendable {
    /// You say the disclosure sentence aloud, confirm there was no objection, then capture starts.
    case announced
    /// Only your own voice, only while you're dictating a question. No one else is captured.
    case myVoiceOnly
    /// Nothing is captured. The hotkey and query box still work.
    case off

    public var title: String {
        switch self {
        case .announced: return "Announced"
        case .myVoiceOnly: return "My Voice Only"
        case .off: return "Off"
        }
    }
}

/// Where the session happens, which decides what the microphone hears.
public enum SessionKind: String, Codable, CaseIterable, Sendable {
    /// A call on Zoom, Meet or Teams: You on the microphone, Them on the system audio.
    case remote
    /// Same room: both voices reach the microphone.
    case inPerson
    /// Just you, practicing. Questions are detected in your own speech.
    case rehearsal

    public var title: String {
        switch self {
        case .remote: return "Remote interview"
        case .inPerson: return "In person"
        case .rehearsal: return "Rehearsal (just me)"
        }
    }
}

/// The consent gate. It lives for one session only and is never saved, so attestation can't carry over.
public struct ConsentGate: Sendable {
    public static let disclosure = "Before we start: I'm using a local assistant that transcribes on my own laptop to help me refer to my notes. Nothing leaves my machine. Is that okay with you?"

    public private(set) var kind: SessionKind
    public private(set) var mode: CaptureMode
    public private(set) var attested = false

    public init(kind: SessionKind, mode: CaptureMode) {
        self.kind = kind
        // Rehearsal records no one else, so it never needs the announcement.
        self.mode = kind == .rehearsal && mode == .announced ? .myVoiceOnly : mode
    }

    /// Announced needs the sentence said and no objection, every session.
    public var needsAttestation: Bool { mode == .announced && !attested }

    /// You confirm you said the sentence. An objection drops the session to My Voice Only.
    public mutating func attest(saidIt: Bool, objection: Bool) {
        guard mode == .announced else { return }
        if objection || !saidIt {
            mode = .myVoiceOnly
            attested = false
        } else {
            attested = true
        }
    }

    /// The other side of a call, through ScreenCaptureKit.
    public var mayCaptureSystemAudio: Bool { kind == .remote && mode == .announced && attested }

    /// The microphone, listening continuously. In person it hears the other person too, so it needs consent.
    public var mayListenContinuously: Bool {
        switch kind {
        case .rehearsal: return mode != .off
        case .remote, .inPerson: return mode == .announced && attested
        }
    }

    /// The microphone, only while you hold dictation on, to say your own paraphrase of the question.
    public var mayDictate: Bool { mode != .off }

    /// Which channel's finished utterances are checked for questions. Your own microphone always counts while
    /// it's on: it's your voice, and saying the question aloud (or practising alone) should get an answer.
    public func answersQuestions(on channel: Channel) -> Bool {
        channel == .you ? (mode != .off) : detectsQuestions(on: .them)
    }

    /// Which channel's finished utterances are checked for questions.
    public func detectsQuestions(on channel: Channel) -> Bool {
        switch (kind, channel) {
        case (.remote, .them): return mayCaptureSystemAudio
        case (.inPerson, .you), (.rehearsal, .you): return mayListenContinuously
        default: return false
        }
    }
}

public enum Channel: String, Codable, Sendable {
    case you = "You"
    case them = "Them"
}

public struct Utterance: Codable, Sendable {
    public var channel: Channel
    public var text: String
    public var at: Date
    public init(channel: Channel, text: String, at: Date = Date()) {
        self.channel = channel
        self.text = text
        self.at = at
    }
}

/// One question the tool handled, for the review after the session.
public struct ReviewItem: Codable, Sendable {
    public var question: String
    public var label: AnswerLabel
    public var source: String?
    public var answer: String?
    public var withheld: String?
    public var sourceLatency: TimeInterval
    public var missed = false
    public var note = ""

    public init(card: AnswerCard) {
        question = card.question
        label = card.label
        source = card.passages.first?.chunk.sourceLine
        answer = card.answer
        withheld = card.withheld
        sourceLatency = card.sourceLatency
    }
}

/// The session's working memory. The transcript is a buffer: it's dropped at the end unless you save it.
public final class SessionLog: @unchecked Sendable {
    public private(set) var transcript: [Utterance] = []
    public var review: [ReviewItem] = []
    private let lock = NSLock()

    public init() {}

    public func add(_ u: Utterance) {
        lock.lock(); defer { lock.unlock() }
        transcript.append(u)
    }

    /// Removes an utterance that turned out to be an echo.
    public func remove(_ u: Utterance) {
        lock.lock(); defer { lock.unlock() }
        if let i = transcript.lastIndex(where: { $0.channel == u.channel && $0.text == u.text && $0.at == u.at }) {
            transcript.remove(at: i)
        }
    }

    /// Recent questions, oldest first, for follow-up context.
    public func recentQuestions(_ n: Int = 2) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return review.suffix(n).map(\.question)
    }

    /// The last exchange, for the manual trigger: the last thing they said, or failing that the last thing anyone said.
    public var lastExchange: String? {
        lock.lock(); defer { lock.unlock() }
        return transcript.last(where: { $0.channel == .them })?.text ?? transcript.last?.text
    }

    public func discardTranscript() {
        lock.lock(); defer { lock.unlock() }
        transcript.removeAll()
    }

    public func transcriptMarkdown(title: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return "# \(title)\n\n" + transcript.map { "**\($0.channel.rawValue)** \(f.string(from: $0.at)): \($0.text)" }
            .joined(separator: "\n\n") + "\n"
    }

    /// The misses as a to-do list for the prep pack.
    public func missesMarkdown(title: String) -> String {
        let misses = review.filter(\.missed)
        guard !misses.isEmpty else { return "" }
        var out = "# Second Chair misses: \(title)\n\nFix the prep pack, not the tool.\n\n"
        for m in misses {
            out += "- [ ] **\(m.question)** (showed \(m.label.rawValue)\(m.source.map { ", from \($0)" } ?? ""))"
            out += m.note.isEmpty ? "\n" : "\n  - \(m.note)\n"
        }
        return out
    }
}

/// Speakers leak the other side of a call into your microphone, so the same words arrive on both
/// channels a moment apart. The "You" copy of anything "Them" also said is an echo.
public enum Echo {
    public static func isEcho(_ a: String, _ b: String) -> Bool {
        let x = Set(Lexicon.terms(a)), y = Set(Lexicon.terms(b))
        guard !x.isEmpty, !y.isEmpty else { return false }
        return Double(x.intersection(y).count) / Double(x.union(y).count) >= 0.6
    }
}
