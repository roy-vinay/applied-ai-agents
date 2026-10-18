import Foundation

public enum DefaultSources {
    private static func feed(_ id: String, _ name: String, _ url: String, primary: Bool, on: Bool = true) -> Source {
        Source(id: id, name: name, kind: .feed, url: URL(string: url), isPrimary: primary, isEnabled: on)
    }

    /// Bumped when the default list changes, so existing installs pick up new sources once.
    public static let version = 4
    /// Sources turned off by default since version 2: frequent, minor updates.
    public static let offByDefault: Set<String> = ["github-changelog", "apple-developer"]
    /// Default sources whose address changed: id to (old address, new address). A saved source still on the
    /// old address moves to the new one; one the reader edited is left alone.
    public static let movedURLs: [String: (old: String, new: String)] = [
        "arxiv": ("https://rss.arxiv.org/rss/cs.AI+cs.CL", "https://export.arxiv.org/api/query?search_query=cat:cs.AI+OR+cat:cs.CL&sortBy=submittedDate&sortOrder=descending&max_results=150"),
    ]

    /// Official sources (summarized) and publishers (headline and link only). Every feed here is one the
    /// site publishes itself; Tech60 never scrapes a site that has no feed.
    public static let all: [Source] = [
        feed("openai", "OpenAI", "https://openai.com/news/rss.xml", primary: true),
        feed("deepmind", "Google DeepMind", "https://deepmind.google/blog/rss.xml", primary: true),
        feed("google-ai", "Google AI", "https://blog.google/technology/ai/rss/", primary: true),
        feed("github-changelog", "GitHub Changelog", "https://github.blog/changelog/feed/", primary: true, on: false),
        feed("apple-developer", "Apple Developer", "https://developer.apple.com/news/rss/news.rss", primary: true, on: false),
        feed("huggingface", "Hugging Face", "https://huggingface.co/blog/feed.xml", primary: true),
        Source(id: "hn", name: "Hacker News", kind: .hackerNews, url: URL(string: "https://news.ycombinator.com"), isPrimary: false),
        feed("techmeme", "Techmeme", "https://www.techmeme.com/feed.xml", primary: false),
        feed("techcrunch", "TechCrunch", "https://techcrunch.com/feed/", primary: false),
        feed("mit-tr", "MIT Technology Review", "https://www.technologyreview.com/feed/", primary: false),
        feed("platformer", "Platformer", "https://www.platformer.news/rss/", primary: false),
        feed("verge", "The Verge", "https://www.theverge.com/rss/index.xml", primary: false),
        feed("ars", "Ars Technica", "https://feeds.arstechnica.com/arstechnica/index", primary: false),
        // The newest AI and language papers, from arXiv's search API. (Its RSS feed is empty on weekends.)
        // Titles and abstracts are public domain (CC0); arXiv asks for no more than one request every three
        // seconds, and Tech60 asks once every six hours.
        Source(id: "arxiv", name: "arXiv", kind: .research, url: URL(string: "https://export.arxiv.org/api/query?search_query=cat:cs.AI+OR+cat:cs.CL&sortBy=submittedDate&sortOrder=descending&max_results=150"), isPrimary: false),
    ]
}
