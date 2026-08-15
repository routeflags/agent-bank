/**
 * ChatInput — Message input field with send button.
 *
 * Features:
 *   - Auto-resizing textarea (up to 120px)
 *   - Send on Enter key (Shift+Enter for newline)
 *   - Send button disabled when input is empty or while sending
 *
 * @param {Object} props
 * @param {Function} props.onSend - Called with the message text when submitted
 * @param {boolean} [props.disabled] - Disables input (e.g., during loading)
 */
import React, { useState, useRef, useCallback } from 'react';

const ChatInput = ({ onSend, disabled }) => {
  const [text, setText] = useState('');
  const textareaRef = useRef(null);

  const canSend = text.trim().length > 0 && !disabled;

  const handleSend = useCallback(() => {
    if (!canSend) return;

    const message = text.trim();
    setText('');
    onSend(message);

    // Reset textarea height
    if (textareaRef.current) {
      textareaRef.current.style.height = 'auto';
    }
  }, [canSend, text, onSend]);

  const handleKeyDown = useCallback(
    (e) => {
      // Enter sends; Shift+Enter inserts a newline
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        handleSend();
      }
    },
    [handleSend]
  );

  // Auto-resize textarea as content grows
  const handleChange = useCallback((e) => {
    setText(e.target.value);
    const el = e.target;
    el.style.height = 'auto';
    el.style.height = `${Math.min(el.scrollHeight, 120)}px`;
  }, []);

  return (
    <div className="chatPanel__inputArea">
      <textarea
        ref={textareaRef}
        className="chatPanel__input"
        value={text}
        onChange={handleChange}
        onKeyDown={handleKeyDown}
        placeholder="Type a message..."
        rows={1}
        disabled={disabled}
        aria-label="Chat message input"
      />
      <button
        className="chatPanel__sendBtn"
        onClick={handleSend}
        disabled={!canSend}
        aria-label="Send message"
        type="button"
      >
        {/* Arrow-up send icon */}
        <svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path
            d="M3 15L15 9L3 3V7.5L11 9L3 10.5V15Z"
            fill="currentColor"
          />
        </svg>
      </button>
    </div>
  );
};

export default ChatInput;
