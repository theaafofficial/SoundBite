import Foundation
import WebKit
import CryptoKit
import os

// MARK: - API Models

struct InnertubeSearchResponse: Decodable {
    // We will parse manually due to complex nested JSON
}

struct InnertubeLibraryResponse: Decodable {
    // We will parse manually
}

// MARK: - Innertube Service
actor InnertubeService {
    private let logger = Logger(subsystem: "com.soundbite", category: "InnertubeService")
    private let session: URLSession
    private let dataStore: WKWebsiteDataStore
    
    // Constants
    private static let baseURL = "https://music.youtube.com/youtubei/v1"
    private static let clientVersion = "1.20231204.01.00" // Trusted version
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    @MainActor
    init(dataStore: WKWebsiteDataStore) {
        self.dataStore = dataStore
        
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
            "Accept-Encoding": "gzip, deflate, br",
            "Origin": "https://music.youtube.com",
            "Referer": "https://music.youtube.com/"
        ]
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Public API
    func search(query: String) async throws -> [SearchResult] {
        logger.info("Searching for: \(query)")
        let body: [String: Any] = ["query": query]
        let json = try await request("search", body: body)
        return parseSearchResults(from: json)
    }
    
    func getLibraryPlaylists() async throws -> [PlaylistItem] {
        logger.info("Fetching library playlists")
        let body: [String: Any] = ["browseId": "FEmusic_liked_playlists"]
        let json = try await request("browse", body: body)
        return parseLibraryPlaylists(from: json)
    }
    
    func getPlaylist(id: String) async throws -> [SearchResult] {
        logger.info("Fetching playlist: \(id)")
        // Browse ID for playlists usually starts with VL if strictly browsing, but often we can just pass the ID if we use the right context.
        // However, standard browseId for a playlist is VL<id>.
        let browseId = id.hasPrefix("VL") ? id : "VL\(id)"
        let body: [String: Any] = ["browseId": browseId]
        let json = try await request("browse", body: body)
        return parsePlaylistTracks(from: json)
    }
    
    func getQueue(videoId: String?, playlistId: String?) async throws -> [QueueItem] {
        logger.info("Fetching queue for v:\(videoId ?? "nil") p:\(playlistId ?? "nil")")
        var body: [String: Any] = [:]
        if let v = videoId { body["videoId"] = v }
        if let p = playlistId { body["playlistId"] = p }
        
        let json = try await request("next", body: body)
        return parseQueue(from: json)
    }
    
    // MARK: - Request Logic
    private func request(_ endpoint: String, body: [String: Any]) async throws -> [String: Any] {
        // 1. Get Cookies
        let cookies = await dataStore.httpCookieStore.allCookies()
        let youtubeCookies = cookies.filter { $0.domain.contains("youtube.com") }
        
        guard let sapisid = youtubeCookies.first(where: { $0.name == "SAPISID" || $0.name == "__Secure-3PAPISID" })?.value else {
            logger.error("No SAPISID cookie found. User not authenticated?")
            throw URLError(.userAuthenticationRequired)
        }
        
        // 2. Build Auth Header (SAPISIDHASH)
        let timestamp = Int(Date().timeIntervalSince1970)
        let origin = "https://music.youtube.com"
        let hashInput = "\(timestamp) \(sapisid) \(origin)"
        let digest = Insecure.SHA1.hash(data: Data(hashInput.utf8))
        let hashHex = digest.map { String(format: "%02x", $0) }.joined()
        let sapisidHash = "\(timestamp)_\(hashHex)"
        
        // 3. Build Request
        let apiKey = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30"
        
        guard let url = URL(string: "\(Self.baseURL)/\(endpoint)?key=\(apiKey)&prettyPrint=false") else {
            throw URLError(.badURL)
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("SAPISIDHASH \(sapisidHash)", forHTTPHeaderField: "Authorization")
        
        let cookieHeaderValue = youtubeCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        req.setValue(cookieHeaderValue, forHTTPHeaderField: "Cookie")
        
        var fullBody = body
        fullBody["context"] = [
            "client": [
                "clientName": "WEB_REMIX",
                "clientVersion": Self.clientVersion,
                "hl": "en",
                "gl": "US",
                "userAgent": userAgent,
                "osName": "Macintosh",
                "osVersion": "10_15_7",
                "platform": "DESKTOP"
            ]
        ]
        
        req.httpBody = try JSONSerialization.data(withJSONObject: fullBody)
        let (data, response) = try await session.data(for: req)
        
        guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
            logger.error("API Error: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            throw URLError(.badServerResponse)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return json
    }
    
    // MARK: - Parsing Helpers
    private func parseSearchResults(from json: [String: Any]) -> [SearchResult] {
        var results: [SearchResult] = []
        
        guard let contents = json["contents"] as? [String: Any],
              let tabbedRenderer = contents["tabbedSearchResultsRenderer"] as? [String: Any],
              let tabs = tabbedRenderer["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
              let tabContent = tabRenderer["content"] as? [String: Any],
              let sectionList = tabContent["sectionListRenderer"] as? [String: Any],
              let sections = sectionList["contents"] as? [[String: Any]] else {
            return []
        }
        
        for section in sections {
            guard let shelf = section["musicShelfRenderer"] as? [String: Any],
                  let shelfContents = shelf["contents"] as? [[String: Any]] else { continue }
            
            for item in shelfContents {
                if let song = item["musicResponsiveListItemRenderer"] as? [String: Any] {
                    // Title
                    guard let flexCols = song["flexColumns"] as? [[String: Any]],
                          let titleCol = flexCols.first?["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
                          let titleTextDict = titleCol["text"] as? [String: Any],
                          let titleRuns = titleTextDict["runs"] as? [[String: Any]],
                          let title = titleRuns.first?["text"] as? String else { continue }
                    
                    // ID
                    var id: String?
                    if let overlay = song["overlay"] as? [String: Any],
                       let thumbOverlay = overlay["musicItemThumbnailOverlayRenderer"] as? [String: Any],
                       let content = thumbOverlay["content"] as? [String: Any],
                       let playButton = content["musicPlayButtonRenderer"] as? [String: Any],
                       let navEndpoint = playButton["playNavigationEndpoint"] as? [String: Any],
                       let watchEndpoint = navEndpoint["watchEndpoint"] as? [String: Any] {
                        id = watchEndpoint["videoId"] as? String
                    }
                    guard let finalId = id else { continue }
                    
                    // Artist
                    var artist = ""
                    if flexCols.count > 1,
                       let subCol = flexCols[1]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
                       let subTextDict = subCol["text"] as? [String: Any],
                       let subRuns = subTextDict["runs"] as? [[String: Any]] {
                        artist = subRuns.compactMap { $0["text"] as? String }.joined()
                    }
                    
                    // Artwork
                    var artwork: URL?
                    if let thumbnailDict = song["thumbnail"] as? [String: Any],
                       let thumbRenderer = thumbnailDict["musicThumbnailRenderer"] as? [String: Any],
                       let thumbInfo = thumbRenderer["thumbnail"] as? [String: Any],
                       let thumbnails = thumbInfo["thumbnails"] as? [[String: Any]],
                       let lastThumb = thumbnails.last,
                       let urlStr = lastThumb["url"] as? String {
                        artwork = URL(string: urlStr)
                    }
                    
                    results.append(SearchResult(id: finalId, title: title, artist: artist, artworkURL: artwork))
                }
            }
        }
        return results
    }
    
    private func parseLibraryPlaylists(from json: [String: Any]) -> [PlaylistItem] {
        var items: [PlaylistItem] = []
        
        guard let contents = json["contents"] as? [String: Any],
              let singleCol = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
              let tabs = singleCol["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
              let tabContent = tabRenderer["content"] as? [String: Any],
              let sectionList = tabContent["sectionListRenderer"] as? [String: Any],
              let sections = sectionList["contents"] as? [[String: Any]],
              let firstSection = sections.first,
              let gridRenderer = firstSection["gridRenderer"] as? [String: Any],
              let gridItems = gridRenderer["items"] as? [[String: Any]] else {
            return []
        }
        
        for item in gridItems {
            if let ptr = item["musicTwoRowItemRenderer"] as? [String: Any] {
                // Title
                guard let titleDict = ptr["title"] as? [String: Any],
                      let titleRuns = titleDict["runs"] as? [[String: Any]],
                      let title = titleRuns.first?["text"] as? String else { continue }
                
                // ID
                guard let navEndpoint = ptr["navigationEndpoint"] as? [String: Any],
                      let browseEndpoint = navEndpoint["browseEndpoint"] as? [String: Any],
                      let browseId = browseEndpoint["browseId"] as? String else { continue }
                
                let id = browseId.replacingOccurrences(of: "VL", with: "")
                
                // Subtitle
                var subtitle = ""
                if let subtitleDict = ptr["subtitle"] as? [String: Any],
                   let subRuns = subtitleDict["runs"] as? [[String: Any]] {
                    subtitle = subRuns.compactMap { $0["text"] as? String }.joined()
                }
                
                // Artwork
                var artwork: URL?
                if let thumbRendererDict = ptr["thumbnailRenderer"] as? [String: Any],
                   let musicThumbRenderer = thumbRendererDict["musicThumbnailRenderer"] as? [String: Any],
                   let thumbInfo = musicThumbRenderer["thumbnail"] as? [String: Any],
                   let thumbnails = thumbInfo["thumbnails"] as? [[String: Any]],
                   let lastThumb = thumbnails.last,
                   let urlStr = lastThumb["url"] as? String {
                    artwork = URL(string: urlStr)
                }
                
                items.append(PlaylistItem(id: id, title: title, subtitle: subtitle, artworkURL: artwork))
            }
        }
        return items
    }
    
    private func parsePlaylistTracks(from json: [String: Any]) -> [SearchResult] {
        var results: [SearchResult] = []
        
        guard let contents = json["contents"] as? [String: Any] else { return [] }
        
        var shelfContents: [[String: Any]]?
        
        if let twoCol = contents["twoColumnBrowseResultsRenderer"] as? [String: Any],
           let secContents = twoCol["secondaryContents"] as? [String: Any],
           let secSectionList = secContents["sectionListRenderer"] as? [String: Any],
           let secSections = secSectionList["contents"] as? [[String: Any]],
           let firstSec = secSections.first,
           let playlistShelf = firstSec["musicPlaylistShelfRenderer"] as? [String: Any] {
            shelfContents = playlistShelf["contents"] as? [[String: Any]]
        } else if let singleCol = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
                  let tabs = singleCol["tabs"] as? [[String: Any]],
                  let firstTab = tabs.first,
                  let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
                  let content = tabRenderer["content"] as? [String: Any],
                  let sectionList = content["sectionListRenderer"] as? [String: Any],
                  let sections = sectionList["contents"] as? [[String: Any]],
                  let firstSec = sections.first,
                  let playlistShelf = firstSec["musicPlaylistShelfRenderer"] as? [String: Any] {
            shelfContents = playlistShelf["contents"] as? [[String: Any]]
        }
        
        guard let items = shelfContents else { return [] }
        
        for item in items {
            if let row = item["musicResponsiveListItemRenderer"] as? [String: Any] {
                guard let flexCols = row["flexColumns"] as? [[String: Any]],
                      let titleCol = flexCols.first?["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
                      let textDict = titleCol["text"] as? [String: Any],
                      let titleRuns = textDict["runs"] as? [[String: Any]],
                      let title = titleRuns.first?["text"] as? String else { continue }
                
                // ID
                 var id: String?
                if let overlay = row["overlay"] as? [String: Any],
                   let thumbOverlay = overlay["musicItemThumbnailOverlayRenderer"] as? [String: Any],
                   let content = thumbOverlay["content"] as? [String: Any],
                   let playButton = content["musicPlayButtonRenderer"] as? [String: Any],
                   let navEndpoint = playButton["playNavigationEndpoint"] as? [String: Any],
                   let watchEndpoint = navEndpoint["watchEndpoint"] as? [String: Any] {
                    id = watchEndpoint["videoId"] as? String
                } else if let itemConfig = row["playlistItemData"] as? [String: Any] {
                     id = itemConfig["videoId"] as? String
                }
                
                guard let finalId = id else { continue }
                
                // Artist
                var artist = ""
                if flexCols.count > 1,
                   let subCol = flexCols[1]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
                   let subText = subCol["text"] as? [String: Any],
                   let subRuns = subText["runs"] as? [[String: Any]] {
                     artist = subRuns.compactMap { $0["text"] as? String }.joined()
                }
                
                // Artwork
                var artwork: URL?
                if let thumbDict = row["thumbnail"] as? [String: Any],
                   let musicThumb = thumbDict["musicThumbnailRenderer"] as? [String: Any],
                   let thumbInfo = musicThumb["thumbnail"] as? [String: Any],
                   let thumbnails = thumbInfo["thumbnails"] as? [[String: Any]],
                   let lastThumb = thumbnails.last,
                   let urlStr = lastThumb["url"] as? String {
                    artwork = URL(string: urlStr)
                }
                
                results.append(SearchResult(id: finalId, title: title, artist: artist, artworkURL: artwork))
            }
        }
        
        return results
    }
    
    private func parseQueue(from json: [String: Any]) -> [QueueItem] {
        // contents -> singleColumnMusicWatchNextResultsRenderer -> tabbedRenderer -> watchNextTabbedResultsRenderer -> tabs[0] -> tabRenderer -> content -> musicQueueRenderer -> content -> playlistPanelRenderer -> contents
        
        guard let contents = json["contents"] as? [String: Any] else { return [] }
        
        var tabbed: [String: Any]?
        
        if let single = contents["singleColumnMusicWatchNextResultsRenderer"] as? [String: Any],
           let t = single["tabbedRenderer"] as? [String: Any] {
            tabbed = t
        } else if let two = contents["twoColumnWatchNextResultsRenderer"] as? [String: Any],
                  let secondary = two["secondaryContents"] as? [String: Any] {
             
             // Check 'contents' array in secondary (Standard Desktop)
             if let secContents = secondary["contents"] as? [[String: Any]] {
                 for item in secContents {
                     if let queueRenderer = item["musicQueueRenderer"] as? [String: Any],
                        let qContent = queueRenderer["content"] as? [String: Any],
                        let panelRenderer = qContent["playlistPanelRenderer"] as? [String: Any],
                        let items = panelRenderer["contents"] as? [[String: Any]] {
                         return parseQueueItems(items)
                     }
                 }
             }
             
             // Check 'secondaryResults' (Alternate)
             if let secResults = secondary["secondaryResults"] as? [String: Any],
                let queueRenderer = secResults["musicQueueRenderer"] as? [String: Any],
                let qContent = queueRenderer["content"] as? [String: Any],
                let panelRenderer = qContent["playlistPanelRenderer"] as? [String: Any],
                let items = panelRenderer["contents"] as? [[String: Any]] {
                  return parseQueueItems(items)
             }
        }
        
        // Fallback for Tabbed (Single Column)
        guard let validTabbed = tabbed,
              let watchTabbed = validTabbed["watchNextTabbedResultsRenderer"] as? [String: Any],
              let tabs = watchTabbed["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
              let content = tabRenderer["content"] as? [String: Any],
              let queueRenderer = content["musicQueueRenderer"] as? [String: Any],
              let qContent = queueRenderer["content"] as? [String: Any],
              let panelRenderer = qContent["playlistPanelRenderer"] as? [String: Any],
              let items = panelRenderer["contents"] as? [[String: Any]] else {
            return []
        }
        
        return parseQueueItems(items)
    }
    
    private func parseQueueItems(_ items: [[String: Any]]) -> [QueueItem] {
        var results: [QueueItem] = []
        
        for item in items {
            if let panelItem = item["playlistPanelVideoRenderer"] as? [String: Any] {
                guard let videoId = panelItem["videoId"] as? String,
                      let titleDict = panelItem["title"] as? [String: Any],
                      let titleRuns = titleDict["runs"] as? [[String: Any]],
                      let title = titleRuns.first?["text"] as? String else { continue }
                
                var artist = ""
                if let shortByline = panelItem["shortBylineText"] as? [String: Any],
                   let artistRuns = shortByline["runs"] as? [[String: Any]] {
                    artist = artistRuns.compactMap { $0["text"] as? String }.joined()
                }
                
                var artwork: URL?
                if let thumbnailDict = panelItem["thumbnail"] as? [String: Any],
                   let thumbnails = thumbnailDict["thumbnails"] as? [[String: Any]],
                   let lastThumb = thumbnails.last,
                   var urlStr = lastThumb["url"] as? String {
                    
                    // Upgrade resolution if low quality
                    if urlStr.contains("w60-h60") {
                        urlStr = urlStr.replacingOccurrences(of: "w60-h60", with: "w544-h544")
                    } else if urlStr.contains("s60") {
                         // Regex replace might be cleaner but string replace is safer for simple cases
                         urlStr = urlStr.replacingOccurrences(of: "s60", with: "s544")
                    }
                    
                    artwork = URL(string: urlStr)
                }
                
                results.append(QueueItem(id: videoId, title: title, artist: artist, artworkURL: artwork))
            }
        }
        return results
    }
}
