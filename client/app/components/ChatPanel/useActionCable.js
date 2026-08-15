/**
 * useActionCable — Formerly a React hook.
 *
 * Action Cable subscription logic has been integrated directly into the
 * ChatPanel class component for React 16.1.1 compatibility (no hooks).
 *
 * This file now serves as a utility module exporting the singleton consumer getter.
 */

/**
 * Singleton Action Cable consumer.
 * Multiple subscriptions share the same underlying WebSocket connection.
 */
var sharedConsumer = null;

export function getConsumer() {
  if (!sharedConsumer) {
    var cable = window.ActionCable || window.actionCable;
    if (cable && cable.createConsumer) {
      sharedConsumer = cable.createConsumer('/api/cable');
    }
  }
  return sharedConsumer;
}
