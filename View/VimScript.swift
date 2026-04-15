import Foundation

enum VimScript {
    static let template: String = #"""
        (function () {
          'use strict';

          const ENABLED = __VIM_ENABLED__;
          const WHITELIST = __VIM_WHITELIST_JSON__;

          if (!ENABLED) return;

          function hostMatches(host) {
            for (const entry of WHITELIST) {
              if (host === entry) return true;
              if (host.endsWith('.' + entry)) return true;
            }
            return false;
          }

          const WHITELISTED = hostMatches(location.hostname);

          function isEditable(target) {
            if (!target) return false;
            const tag = target.tagName;
            if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return true;
            if (target.isContentEditable) return true;
            return false;
          }

          const SCROLL_STEP = 60;

          let prefix = null;
          let prefixTimer = null;

          function clearPrefix() {
            prefix = null;
            if (prefixTimer) {
              clearTimeout(prefixTimer);
              prefixTimer = null;
            }
          }

          function armPrefix(ch) {
            prefix = ch;
            if (prefixTimer) clearTimeout(prefixTimer);
            prefixTimer = setTimeout(clearPrefix, 1000);
          }

          function halfViewport() {
            return Math.max(100, Math.floor(window.innerHeight / 2));
          }

          function postScroll(where_) {
            try {
              webkit.messageHandlers.viewScroll.postMessage(where_);
            } catch (e) {}
          }

          function dispatch(key, event) {
            // Two-char sequences beginning with 'g'.
            if (prefix === 'g') {
              clearPrefix();
              if (key === 'g') {
                postScroll('top');
                return true;
              }
              return false;
            }

            switch (key) {
              case 'j':
                window.scrollBy(0, SCROLL_STEP);
                return true;
              case 'k':
                window.scrollBy(0, -SCROLL_STEP);
                return true;
              case 'd':
                window.scrollBy(0, halfViewport());
                return true;
              case 'u':
                window.scrollBy(0, -halfViewport());
                return true;
              case 'g':
                armPrefix('g');
                return true;
              case 'G':
                postScroll('bottom');
                return true;
              case 'H':
                history.back();
                return true;
              case 'L':
                history.forward();
                return true;
              case 'r':
                location.reload();
                return true;
              default:
                return false;
            }
          }

          window.addEventListener('keydown', function (event) {
            if (event.ctrlKey || event.metaKey || event.altKey) return;
            if (isEditable(event.target)) return;

            if (event.key.length !== 1 && event.key !== 'g') return;
            if (WHITELISTED && event.key !== 'g' && event.key !== 'G') {
              clearPrefix();
              return;
            }

            const handled = dispatch(event.key, event);
            if (handled) {
              event.preventDefault();
              event.stopPropagation();
            } else {
              clearPrefix();
            }
          }, true);
        })();
        """#
}
