/**
 * ChatMessage — Renders a single chat message bubble.
 *
 * Layout varies by role:
 *   - user:      right-aligned, green bubble
 *   - assistant: left-aligned, grey bubble, streaming animation support
 *   - system:    centered, subtle grey bubble
 *
 * @param {Object} props
 * @param {string} props.role - 'user' | 'assistant' | 'system'
 * @param {string} props.content - The message text
 * @param {boolean} [props.isStreaming] - Whether the message is still being streamed
 * @param {number} [props.total_tokens] - Token usage to display
 * @param {string} [props.created_at] - ISO timestamp
 */
import React from 'react';

const ChatMessage = ({ role, content, isStreaming, total_tokens, created_at }) => {
  const roleClass = `chatMessage--${role || 'user'}`;
  const timeStr = created_at
    ? new Date(created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
    : null;

  return (
    <div className={`chatMessage ${roleClass}`}>
      <div className="chatMessage__bubble">
        {content || ''}
        {isStreaming && <span className="chatMessage__streaming" />}
      </div>

      {/* Show token usage for completed assistant messages */}
      {role === 'assistant' && total_tokens > 0 && (
        <span className="chatMessage__tokens">
          {total_tokens} tokens
        </span>
      )}

      {/* Timestamp */}
      {timeStr && role !== 'system' && (
        <span className="chatMessage__meta">{timeStr}</span>
      )}
    </div>
  );
};

export default ChatMessage;
