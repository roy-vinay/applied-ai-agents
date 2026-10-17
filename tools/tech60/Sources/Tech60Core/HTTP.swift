import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fetches public sources over https, with a timeout and a size limit.
public struct HTTPClient: Sendable {
    public var session: URLSession
    public var userAgent = "Tech60/0.1 (Mac news card; +https://github.com/roy-vinay/applied-ai-agents/tree/main/tools/tech60)"

    public init(session: URLSession = .shared) { self.session = session }

    public func get(_ url: URL, maxBytes: Int = 5_000_000) async throws -> Data {
        guard url.scheme?.lowercased() == "https" else { throw Tech60Error.insecureURL }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = false
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Tech60Error.badStatus(http.statusCode)
        }
        guard data.count <= maxBytes else { throw Tech60Error.tooLarge }
        return data
    }
}

/// Hacker News through its official public API.
public enum HackerNews {
    struct Item: Decodable {
        let id: Int
        let title: String?
        let url: String?
        let time: Int?
        let dead: Bool?
        let deleted: Bool?
    }

    public static func topStories(count: Int = 20, client: HTTPClient) async throws -> [FeedItem] {
        let base = URL(string: "https://hacker-news.firebaseio.com/v0/")!
        let data = try await client.get(base.appendingPathComponent("topstories.json"))
        let ids = Array(try JSONDecoder().decode([Int].self, from: data).prefix(count))
        var items: [FeedItem] = []
        // Four requests at a time.
        for chunk in stride(from: 0, to: ids.count, by: 4).map({ Array(ids[$0..<min($0 + 4, ids.count)]) }) {
            let found = await withTaskGroup(of: (Int, FeedItem?).self) { group -> [(Int, FeedItem)] in
                for id in chunk {
                    group.addTask {
                        guard let d = try? await client.get(base.appendingPathComponent("item/\(id).json")),
                              let item = try? JSONDecoder().decode(Item.self, from: d),
                              item.dead != true, item.deleted != true, let title = item.title else { return (id, nil) }
                        let link = item.url.flatMap(URL.init(string:)) ?? URL(string: "https://news.ycombinator.com/item?id=\(id)")
                        let date = item.time.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                        return (id, FeedItem(id: String(id), title: title, link: link, published: date, text: ""))
                    }
                }
                var out: [(Int, FeedItem)] = []
                for await (id, item) in group { if let item { out.append((id, item)) } }
                return out
            }
            for id in chunk { if let hit = found.first(where: { $0.0 == id }) { items.append(hit.1) } }
        }
        return items
    }
}
