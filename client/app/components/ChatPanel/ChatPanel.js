/**
 * ChatPanel — Main container for the AI persona chat UI.
 *
 * Composes:
 *   - ChatHeader    (persona name + close button)
 *   - Message list  (scrollable area)
 *   - ChatInput     (message input + send button)
 *
 * Manages:
 *   - Session lifecycle via useChatSession
 *   - WebSocket connection via useActionCable
 *   - Streaming message assembly from Action Cable chunks
 *
 * @param {Object} props
 * @param {number} props.listingId - The listing (persona) to chat with
 * @param {string} [props.personaName] - Display name of the persona
 * @param {Function} props.onClose - Called when the panel should close
 */
import React, { useEffect, useCallback, useRef } from 'react';
import ChatHeader from './ChatHeader';
import ChatMessage from './ChatMessage';
import ChatInput from './ChatInput';
import useChatSession from './useChatSession';
import useActionCable from './useActionCable';
import css from './chatPanel.css';

const ChatPanel = ({ listingId, personaName, onClose }) => {
  const {
    sessionId,
    messages,
    isLoading,
    error,
    createSession,
    closeSession,
    addUserMessage,
    upsertAssistantMessage,
    finalizeAssistantMessage,
    markStreaming,
    addSystemMessage,
  } = useChatSession({ listingId });

  // Track the current streaming assistant message temp id
  const streamingIdRef = useRef(null);

  // Guard against duplicate sends while a previous send is in flight
  const sendingRef = useRef(false);

  // Detect mobile viewport for overlay click behavior
  const isMobile = typeof window !== 'undefined' && window.innerWidth < 768;

  // Action Cable handlers — refs to avoid stale closures
  const handleChunk = useCallback(
    (data) => {
      const { content, message_id } = data;

      if (!streamingIdRef.current) {
        // First chunk of a new assistant response — create a temp message
        const tempId = `stream-${Date.now()}`;
        streamingIdRef.current = tempId;
        upsertAssistantMessage(tempId, content || '');
        markStreaming(tempId);
      } else {
        // Subsequent chunk — append content
        upsertAssistantMessage(streamingIdRef.current, content || '');
      }
    },
    [upsertAssistantMessage, markStreaming]
  );

  const handleDone = useCallback(
    (data) => {
      const { message_id, total_tokens } = data;

      if (streamingIdRef.current) {
        finalizeAssistantMessage(
          streamingIdRef.current,
          message_id || streamingIdRef.current,
          total_tokens || 0
        );
        streamingIdRef.current = null;
      }
    },
    [finalizeAssistantMessage]
  );

  const handleError = useCallback(
    (data) => {
      streamingIdRef.current = null;
      const errorMsg = data.error || 'An error occurred while generating a response.';
      addSystemMessage(errorMsg);
    },
    [addSystemMessage]
  );

  const { sendMessage, disconnect } = useActionCable({
    chatSessionId: sessionId,
    handlers: { onChunk: handleChunk, onDone: handleDone, onError: handleError },
  });

  // Auto-scroll to bottom when messages change
  const messagesEndRef = useRef(null);
  useEffect(() => {
    if (messagesEndRef.current) {
      messagesEndRef.current.scrollIntoView({ behavior: 'smooth' });
    }
  }, [messages]);

  // Create session on mount
  useEffect(() => {
    createSession();
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // Cleanup: disconnect WebSocket and close session on unmount
  useEffect(() => {
    return () => {
      disconnect();
      closeSession();
    };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  /**
   * Handle user sending a message.
   * Creates the session if needed, then sends via Action Cable.
   * Guarded by sendingRef to prevent race conditions on rapid clicks.
   */
  const handleSend = useCallback(
    async (content) => {
      if (sendingRef.current) return;
      sendingRef.current = true;
      try {
        addUserMessage(content);

        // Ensure we have a session (and thus a channel subscription)
        let activeSessionId = sessionId;
        if (!activeSessionId) {
          activeSessionId = await createSession();
        }

        if (activeSessionId) {
          sendMessage(content);
        } else {
          addSystemMessage('Could not connect to chat. Please try again.');
        }
      } finally {
        sendingRef.current = false;
      }
    },
    [sessionId, addUserMessage, createSession, sendMessage, addSystemMessage]
  );

  const handleClose = useCallback(() => {
    disconnect();
    closeSession();
    onClose();
  }, [disconnect, closeSession, onClose]);

  return (
    <div
      className="chatPanel__overlay"
      onClick={isMobile ? undefined : handleClose}
    >
      <div
        className="chatPanel"
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-label="AI Chat"
      >
        <ChatHeader personaName={personaName} onClose={handleClose} />

        {/* Error banner */}
        {error && (
          <div className="chatPanel__error">{error}</div>
        )}

        {/* Messages */}
        <div className="chatPanel__messages">
          {messages.length === 0 && !isLoading ? (
            <div className="chatPanel__emptyState">
              Start a conversation with {personaName || 'the AI assistant'}.
            </div>
          ) : (
            messages.map((msg) => (
              <ChatMessage
                key={msg.id}
                role={msg.role}
                content={msg.content}
                isStreaming={msg.isStreaming}
                total_tokens={msg.total_tokens}
                created_at={msg.created_at}
              />
            ))
          )}
          <div ref={messagesEndRef} />
        </div>

        <ChatInput onSend={handleSend} disabled={isLoading} />
      </div>
    </div>
  );
};

export default ChatPanel;
