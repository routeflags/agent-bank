/**
 * useChatSession — Formerly a React hook.
 *
 * Session management logic has been integrated directly into the
 * ChatPanel class component for React 16.1.1 compatibility (no hooks).
 *
 * This file now serves as a utility module exporting CSRF helpers.
 */

/**
 * Read CSRF token from <meta name="csrf-token">.
 * Follows the same pattern used in ManageAvailabilityActions.js.
 */
export function csrfToken() {
  var metaTag = document.querySelector('meta[name=csrf-token]');
  return metaTag ? metaTag.getAttribute('content') : '';
}

/** Default headers for all state-changing fetch requests. */
export function jsonHeaders() {
  return {
    'Content-Type': 'application/json',
    'X-CSRF-Token': csrfToken(),
  };
}
