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

class ChatMessage extends React.Component {
  render() {
    var role = this.props.role;
    var content = this.props.content;
    var isStreaming = this.props.isStreaming;
    var totalTokens = this.props.total_tokens;
    var createdAt = this.props.created_at;

    var roleClass = 'chatMessage--' + (role || 'user');
    var timeStr = createdAt
      ? new Date(createdAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
      : null;

    return (
      React.createElement('div', { className: 'chatMessage ' + roleClass },
        React.createElement('div', { className: 'chatMessage__bubble' },
          content || '',
          isStreaming && React.createElement('span', { className: 'chatMessage__streaming' })
        ),

        // Show token usage for completed assistant messages
        role === 'assistant' && totalTokens > 0 && (
          React.createElement('span', { className: 'chatMessage__tokens' },
            totalTokens + ' tokens'
          )
        ),

        // Timestamp
        timeStr && role !== 'system' && (
          React.createElement('span', { className: 'chatMessage__meta' }, timeStr)
        )
      )
    );
  }
}

export default ChatMessage;
