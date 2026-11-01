import Foundation
import SwiftSoup

private final class SameOriginRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url?.host == StudIPClient.origin.host && request.url?.scheme == "https" ? request : nil)
    }
}

private struct Reference: Decodable, Sendable { var id: String }
private struct Relation: Decodable, Sendable { var data: Reference? }
private struct Relations: Decodable, Sendable {
    var parent: Relation?
    var startSemester: Relation?
    enum CodingKeys: String, CodingKey { case parent; case startSemester = "start-semester" }
}
private struct Resource<A: Decodable & Sendable>: Decodable, Sendable {
    var id: String
    var attributes: A
    var relationships: Relations?
}
private struct Page<A: Decodable & Sendable>: Decodable, Sendable {
    var data: [Resource<A>]
    var links: Links?
    struct Links: Decodable, Sendable { var next: String? }
}
private struct CourseAttributes: Decodable, Sendable { var title: String }
private struct SemesterAttributes: Decodable, Sendable {
    var current: Bool
    enum CodingKeys: String, CodingKey { case current = "is-current" }
}
private struct FolderAttributes: Decodable, Sendable { var name: String }
private struct FileAttributes: Decodable, Sendable {
    var name: String
    var filesize: Int64?
    var chdate: String
    var downloadable: Bool
    enum CodingKeys: String, CodingKey {
        case name, filesize, chdate
        case downloadable = "is-downloadable"
    }
}

public actor StudIPClient {
    public static let origin = URL(string: "https://studip.uni-goettingen.de")!
    private let session: URLSession
    private var credentials: (String, String)?

    public init(session: URLSession? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 1800
        config.httpMaximumConnectionsPerHost = 2
        self.session = session ?? URLSession(configuration: config, delegate: SameOriginRedirects(), delegateQueue: nil)
    }

    public static func loginFields(html: String, username: String, password: String) throws -> (URL, [String: String]) {
        let document = try SwiftSoup.parse(html)
        guard let form = try document.select("form").first(where: {
            try !$0.select("input[name=loginname]").isEmpty() && !$0.select("input[name=password]").isEmpty()
        }), let action = URL(string: try form.attr("action"), relativeTo: origin)?.absoluteURL,
              action.scheme == "https", action.host == origin.host,
              action.port == nil || action.port == 443
        else { throw StudSyncError.authentication }
        var fields = ["loginname": username, "password": password, "Login": "1"]
        for input in try form.select("input[type=hidden]") {
            let name = try input.attr("name")
            if !name.isEmpty && fields[name] == nil { fields[name] = try input.attr("value") }
        }
        return (action, fields)
    }

    public static func formBody(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return Data(fields.sorted(by: { $0.key < $1.key }).map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").utf8)
    }

    public func signIn(username: String, password: String) async throws {
        credentials = nil
        let (data, response) = try await session.data(from: Self.origin)
        try check(response)
        let (action, fields) = try Self.loginFields(html: String(decoding: data, as: UTF8.self), username: username, password: password)
        var request = URLRequest(url: action)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(fields)
        let (_, posted) = try await session.data(for: request)
        try check(posted)
        _ = try await apiData("users/me", retry: false)
        credentials = (username, password)
    }

    public func adopt(cookies: [HTTPCookie]) async throws {
        for cookie in cookies where cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")) == Self.origin.host {
            session.configuration.httpCookieStorage?.setCookie(cookie)
        }
        _ = try await apiData("users/me", retry: false)
    }

    public func signOut() {
        credentials = nil
        session.configuration.httpCookieStorage?.cookies?.forEach { session.configuration.httpCookieStorage?.deleteCookie($0) }
    }

    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw StudSyncError.invalidResponse }
        guard http.url?.host == Self.origin.host, http.url?.scheme == "https" else { throw StudSyncError.authentication }
        if http.statusCode == 401 { throw StudSyncError.authentication }
        guard (200..<300).contains(http.statusCode) else { throw StudSyncError.http(http.statusCode) }
    }

    private func apiData(_ path: String, retry: Bool = true) async throws -> Data {
        let url = URL(string: "/jsonapi.php/v1/" + path, relativeTo: Self.origin)!.absoluteURL
        return try await apiData(url: url, retry: retry)
    }

    private func apiData(url: URL, retry: Bool = true) async throws -> Data {
        guard url.host == Self.origin.host, url.scheme == "https", url.port == nil || url.port == 443 else { throw StudSyncError.unsafePath }
        let (data, response) = try await session.data(from: url)
        let http = response as? HTTPURLResponse
        let expired = http?.statusCode == 401 || http?.mimeType == "text/html"
        if expired {
            if retry, let (username, password) = credentials {
                try await signIn(username: username, password: password)
                return try await apiData(url: url, retry: false)
            }
            throw StudSyncError.authentication
        }
        try check(response)
        return data
    }

    private func list<A: Decodable & Sendable>(_ path: String, as: A.Type) async throws -> [Resource<A>] {
        var url: URL? = URL(string: "/jsonapi.php/v1/" + path, relativeTo: Self.origin)!.absoluteURL
        var seen: Set<URL> = []
        var items: [Resource<A>] = []
        while let current = url {
            guard seen.insert(current).inserted else { throw StudSyncError.invalidResponse }
            let page = try JSONDecoder().decode(Page<A>.self, from: await apiData(url: current))
            items += page.data
            url = page.links?.next.flatMap { URL(string: $0, relativeTo: current)?.absoluteURL }
        }
        return items
    }

    public func courses() async throws -> [Course] {
        struct Me: Decodable { var data: Reference }
        let me = try JSONDecoder().decode(Me.self, from: await apiData("users/me"))
        let semesters = try await list("semesters", as: SemesterAttributes.self)
        let filter = semesters.first(where: { $0.attributes.current }).map { "?filter[semester]=\($0.id)" } ?? ""
        let courses = try await list("users/\(me.data.id)/courses" + filter, as: CourseAttributes.self)
        return courses.map { Course(id: $0.id, title: $0.attributes.title) }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public func files(course: Course) async throws -> [RemoteFile] {
        let folders = try await list("courses/\(course.id)/folders", as: FolderAttributes.self)
        let byID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        let files = try await list("courses/\(course.id)/file-refs", as: FileAttributes.self)
        return try files.filter { $0.attributes.downloadable && $0.attributes.filesize != nil }.map { file in
            var components = [file.attributes.name]
            var parent = file.relationships?.parent?.data?.id
            var seen: Set<String> = []
            while let id = parent {
                guard seen.insert(id).inserted, let folder = byID[id] else { throw StudSyncError.unsafePath }
                parent = folder.relationships?.parent?.data?.id
                if parent != nil { components.insert(folder.attributes.name, at: 0) }
            }
            components.insert(course.title, at: 0)
            return RemoteFile(id: file.id, components: components, size: file.attributes.filesize!, revision: file.attributes.chdate)
        }
    }

    public func download(id: String) async throws -> URL {
        guard id.allSatisfy({ $0.isHexDigit }), !id.isEmpty else { throw StudSyncError.unsafePath }
        let url = Self.origin.appendingPathComponent("jsonapi.php/v1/file-refs/\(id)/content")
        var (file, response) = try await session.download(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 || http.mimeType == "text/html" {
            try? FileManager.default.removeItem(at: file)
            guard let (username, password) = credentials else { throw StudSyncError.authentication }
            try await signIn(username: username, password: password)
            (file, response) = try await session.download(from: url)
        }
        do {
            try check(response)
            guard (response as? HTTPURLResponse)?.mimeType != "text/html" else { throw StudSyncError.authentication }
            return file
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
    }
}
