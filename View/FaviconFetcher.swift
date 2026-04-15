import AppKit
import WebKit

final class FaviconFetcher {
    static let shared = FaviconFetcher()

    private var cache: [String: NSImage] = [:]
    private var inflight: [String: [(NSImage?) -> Void]] = [:]
    private let session = URLSession.shared

    func fetch(for webView: WKWebView, completion: @escaping (NSImage?) -> Void) {
        guard let pageURL = webView.url, let host = pageURL.host else {
            completion(nil)
            return
        }

        if let cached = cache[host] {
            completion(cached)
            return
        }

        let js = """
            (function () {
              var links = document.querySelectorAll('link[rel~="icon"]');
              var best = null;
              var bestSize = -1;
              for (var i = 0; i < links.length; i++) {
                var href = links[i].getAttribute('href');
                if (!href) continue;
                var sizes = links[i].getAttribute('sizes') || '';
                var m = sizes.match(/(\\d+)/);
                var size = m ? parseInt(m[1], 10) : 0;
                if (size >= bestSize) {
                  bestSize = size;
                  best = href;
                }
              }
              return best;
            })();
            """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self else { return }
            let href = result as? String
            let candidate: URL
            if let href, let resolved = URL(string: href, relativeTo: pageURL) {
                candidate = resolved.absoluteURL
            } else if let fallback = URL(string: "/favicon.ico", relativeTo: pageURL) {
                candidate = fallback.absoluteURL
            } else {
                completion(nil)
                return
            }
            self.download(candidate, cacheKey: host, completion: completion)
        }
    }

    private func download(
        _ url: URL, cacheKey: String, completion: @escaping (NSImage?) -> Void
    ) {
        if let cached = cache[cacheKey] {
            completion(cached)
            return
        }
        if inflight[cacheKey] != nil {
            inflight[cacheKey]?.append(completion)
            return
        }
        inflight[cacheKey] = [completion]

        let task = session.dataTask(with: url) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let image = data.flatMap { NSImage(data: $0) }
                if let image {
                    self.cache[cacheKey] = image
                }
                let handlers = self.inflight.removeValue(forKey: cacheKey) ?? []
                for handler in handlers {
                    handler(image)
                }
            }
        }
        task.resume()
    }
}
