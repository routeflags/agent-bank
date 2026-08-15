/**
 * useActionCable — Manages Action Cable WebSocket connection for chat.
 *
 * Responsibilities:
 *   - Connect to PersonaChatChannel with a chat_session_id
 *   - Receive streaming events: stream_chunk, stream_done, stream_error
 *   - Send user messages via the channel's `perform('receive', ...)` method
 *   - Clean up on unmount or session change
 *
 * Depends on the global `ActionCable` object injected by actioncable npm package.
 */
import { useState, useEffect, useRef, useCallback } from 'react';

/**
 * Singleton Action Cable consumer.
 * Multiple hooks/subscriptions share the same underlying WebSocket connection.
 */
let sharedConsumer = null;

const getConsumer = () => {
  if (!sharedConsumer) {
    const cable = window.ActionCable || window.actionCable;
    if (cable && cable.createConsumer) {
      sharedConsumer = cable.createConsumer('/api/cable');
    }
  }
  return sharedConsumer;
};

/**
 * @param {Object} options
 * @param {number|null} options.chatSessionId - The session to subscribe to
 * @param {Object} options.handlers - Callback map: { onChunk, onDone, onError, onDisconnect }
 * @returns {Object} { sendMessage, disconnect, isConnected }
 */
export default function useActionCable({ chatSessionId, handlers }) {
  const [isConnected, setIsConnected] = useState(false);
  const subscriptionRef = useRef(null);
  const handlersRef = useRef(handlers);
  handlersRef.current = handlers;

  /**
   * Subscribe to PersonaChatChannel for the given session.
   */
  useEffect(() => {
    if (!chatSessionId) return;

    const consumer = getConsumer();
    if (!consumer) {
      console.warn('[ActionCable] ActionCable consumer not available on window');
      return;
    }

    const subscription = consumer.subscriptions.create(
      { channel: 'PersonaChatChannel', chat_session_id: chatSessionId },
      {
        connected() {
          setIsConnected(true);
        },

        disconnected() {
          setIsConnected(false);
          // Notify handler so the UI can surface reconnection status
          if (handlersRef.current.onDisconnect) {
            handlersRef.current.onDisconnect();
          }
        },

        received(data) {
          const { type } = data;
          const h = handlersRef.current;

          switch (type) {
            case 'stream_chunk':
              if (h.onChunk) h.onChunk(data);
              break;
            case 'stream_done':
              if (h.onDone) h.onDone(data);
              break;
            case 'stream_error':
              if (h.onError) h.onError(data);
              break;
            default:
              // Unknown message type — ignore gracefully
              break;
          }
        },
      }
    );

    subscriptionRef.current = subscription;

    return () => {
      subscription.unsubscribe();
      subscriptionRef.current = null;
      setIsConnected(false);
    };
  }, [chatSessionId]);

  /**
   * Send a user message through the channel.
   */
  const sendMessage = useCallback((content) => {
    if (!subscriptionRef.current) {
      console.warn('[ActionCable] Cannot send: no active subscription');
      return;
    }

    subscriptionRef.current.perform('receive', {
      chat_session_id: chatSessionId,
      content,
    });
  }, [chatSessionId]);

  /**
   * Explicitly disconnect (called on panel close).
   */
  const disconnect = useCallback(() => {
    if (subscriptionRef.current) {
      subscriptionRef.current.unsubscribe();
      subscriptionRef.current = null;
      setIsConnected(false);
    }
  }, []);

  return {
    sendMessage,
    disconnect,
    isConnected,
  };
}
