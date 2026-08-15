/**
 * useChatSession — Manages the lifecycle of a chat session.
 *
 * Responsibilities:
 *   - Create a new session (POST /api/v1/chat_sessions)
 *   - Fetch message history (GET /api/v1/chat_sessions/:id)
 *   - Close a session (PATCH /api/v1/chat_sessions/:id)
 *   - Append messages received via Action Cable to local state
 */
import { useState, useCallback, useRef, useEffect } from 'react';

/**
 * Read CSRF token from <meta name="csrf-token">.
 * Follows the same pattern used in ManageAvailabilityActions.js.
 */
const csrfToken = () => {
  const metaTag = document.querySelector('meta[name=csrf-token]');
  return metaTag ? metaTag.getAttribute('content') : '';
};

/** Default headers for all state-changing fetch requests. */
const jsonHeaders = () => ({
  'Content-Type': 'application/json',
  'X-CSRF-Token': csrfToken(),
});

/**
 * @param {Object} options
 * @param {number} options.listingId - The listing (persona) to chat with
 * @returns {Object} Chat session state and actions
 */
export default function useChatSession({ listingId }) {
  const [sessionId, setSessionId] = useState(null);
  const [messages, setMessages] = useState([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState(null);

  // Keep a stable ref to the latest messages array for streaming appends.
  const messagesRef = useRef(messages);
  messagesRef.current = messages;

  // Abort controller ref — allows cancelling in-flight fetches on unmount.
  const abortRef = useRef(null);

  /**
   * Fetch message history for an existing session.
   */
  const fetchMessages = useCallback(async (id) => {
    try {
      const controller = new AbortController();
      abortRef.current = controller;
      const response = await fetch(`/api/v1/chat_sessions/${id}`, {
        signal: controller.signal,
      });
      if (!response.ok) {
        throw new Error(`Failed to load messages (HTTP ${response.status})`);
      }
      const data = await response.json();
      setMessages(data.chat_session.messages || []);
      return data.chat_session.messages || [];
    } catch (err) {
      // Ignore abort — user navigated away
      if (err.name === 'AbortError') return [];
      setError(err.message);
      return [];
    }
  }, []);

  /**
   * Create a new chat session for the given listing.
   * If an active session already exists, load its messages instead.
   */
  const createSession = useCallback(async () => {
    setIsLoading(true);
    setError(null);

    try {
      // Check for an existing active session via index
      const controller = new AbortController();
      abortRef.current = controller;
      const indexResponse = await fetch('/api/v1/chat_sessions', {
        signal: controller.signal,
      });
      if (indexResponse.ok) {
        const indexData = await indexResponse.json();
        const existing = (indexData.chat_sessions || []).find(
          (s) => s.listing_id === listingId && s.status === 'active'
        );
        if (existing) {
          setSessionId(existing.id);
          await fetchMessages(existing.id);
          setIsLoading(false);
          return existing.id;
        }
      }

      // Create a new session
      const response = await fetch('/api/v1/chat_sessions', {
        method: 'POST',
        headers: jsonHeaders(),
        body: JSON.stringify({ listing_id: listingId }),
        signal: controller.signal,
      });

      if (!response.ok) {
        const body = await response.json().catch(() => ({}));
        throw new Error(body.error || `Failed to create session (HTTP ${response.status})`);
      }

      const data = await response.json();
      const newSession = data.chat_session;
      setSessionId(newSession.id);
      setMessages([]);
      setIsLoading(false);
      return newSession.id;
    } catch (err) {
      // Ignore abort — cleanup on unmount
      if (err.name === 'AbortError') return null;
      setError(err.message);
      setIsLoading(false);
      return null;
    }
  }, [listingId, fetchMessages]);

  /**
   * Close the current session.
   */
  const closeSession = useCallback(async () => {
    if (!sessionId) return;

    try {
      await fetch(`/api/v1/chat_sessions/${sessionId}`, {
        method: 'PATCH',
        headers: jsonHeaders(),
        body: JSON.stringify({ status: 'closed' }),
      });
    } catch (err) {
      // Non-critical: session close is best-effort
      console.warn('[ChatSession] Failed to close session:', err.message);
    }

    setSessionId(null);
    setMessages([]);
    setError(null);
  }, [sessionId]);

  /**
   * Append a user-sent message to local state (optimistic UI).
   */
  const addUserMessage = useCallback((content) => {
    const optimistic = {
      id: `temp-${Date.now()}`,
      role: 'user',
      content,
      seq: (messagesRef.current.length || 0) + 1,
      created_at: new Date().toISOString(),
    };
    setMessages((prev) => [...prev, optimistic]);
  }, []);

  /**
   * Append or update an assistant message during streaming.
   * If a message with the given tempId exists, append content; otherwise insert new.
   */
  const upsertAssistantMessage = useCallback((tempId, content) => {
    setMessages((prev) => {
      const idx = prev.findIndex((m) => m.id === tempId);
      if (idx >= 0) {
        const updated = [...prev];
        updated[idx] = { ...updated[idx], content: (updated[idx].content || '') + content };
        return updated;
      }
      return [
        ...prev,
        {
          id: tempId,
          role: 'assistant',
          content,
          seq: prev.length + 1,
          created_at: new Date().toISOString(),
        },
      ];
    });
  }, []);

  /**
   * Finalize a streaming assistant message with server-assigned id and token info.
   */
  const finalizeAssistantMessage = useCallback((tempId, finalId, totalTokens) => {
    setMessages((prev) =>
      prev.map((m) =>
        m.id === tempId
          ? { ...m, id: finalId, total_tokens: totalTokens, isStreaming: false }
          : m
      )
    );
  }, []);

  /**
   * Mark a message as streaming (for animation).
   */
  const markStreaming = useCallback((tempId) => {
    setMessages((prev) =>
      prev.map((m) => (m.id === tempId ? { ...m, isStreaming: true } : m))
    );
  }, []);

  /**
   * Add a system message (error notifications, etc.)
   */
  const addSystemMessage = useCallback((content) => {
    setMessages((prev) => [
      ...prev,
      {
        id: `sys-${Date.now()}`,
        role: 'system',
        content,
        seq: prev.length + 1,
        created_at: new Date().toISOString(),
      },
    ]);
  }, []);

  // Abort in-flight requests on unmount
  useEffect(() => {
    return () => {
      abortRef.current?.abort();
    };
  }, []);

  return {
    sessionId,
    messages,
    isLoading,
    error,
    createSession,
    fetchMessages,
    closeSession,
    addUserMessage,
    upsertAssistantMessage,
    finalizeAssistantMessage,
    markStreaming,
    addSystemMessage,
  };
}
