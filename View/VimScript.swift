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

          function fullViewport() {
            return Math.max(200, window.innerHeight);
          }

          function dispatchCtrl(key) {
            switch (key) {
              case 'f':
                window.scrollBy(0, fullViewport());
                return true;
              case 'b':
                window.scrollBy(0, -fullViewport());
                return true;
              default:
                return false;
            }
          }

          function dispatch(key, event) {
            // Two-char sequences beginning with 'g'.
            if (prefix === 'g') {
              clearPrefix();
              if (key === 'g') {
                window.scrollTo({ top: 0, behavior: 'auto' });
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
                window.scrollTo({ top: document.documentElement.scrollHeight, behavior: 'auto' });
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
            if (event.metaKey || event.altKey) return;
            if (isEditable(event.target)) return;

            if (event.ctrlKey) {
              if (event.shiftKey) return;
              if (dispatchCtrl(event.key)) {
                event.preventDefault();
                event.stopPropagation();
              }
              return;
            }

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
