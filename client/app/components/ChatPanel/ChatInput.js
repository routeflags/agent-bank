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
import React from 'react';

class ChatInput extends React.Component {
  constructor(props) {
    super(props);
    this.state = {
      text: '',
    };

    this.textareaRef = null;

    this.handleSend = this.handleSend.bind(this);
    this.handleKeyDown = this.handleKeyDown.bind(this);
    this.handleChange = this.handleChange.bind(this);
  }

  get canSend() {
    return this.state.text.trim().length > 0 && !this.props.disabled;
  }

  handleSend() {
    if (!this.canSend) return;

    var message = this.state.text.trim();
    this.setState({ text: '' });
    this.props.onSend(message);

    // Reset textarea height
    if (this.textareaRef) {
      this.textareaRef.style.height = 'auto';
    }
  }

  handleKeyDown(e) {
    // Enter sends; Shift+Enter inserts a newline
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      this.handleSend();
    }
  }

  handleChange(e) {
    this.setState({ text: e.target.value });
    // Auto-resize textarea as content grows
    var el = e.target;
    el.style.height = 'auto';
    el.style.height = Math.min(el.scrollHeight, 120) + 'px';
  }

  render() {
    var text = this.state.text;
    var disabled = this.props.disabled;

    return (
      React.createElement('div', { className: 'chatPanel__inputArea' },
        React.createElement('textarea', {
          ref: (el) => { this.textareaRef = el; },
          className: 'chatPanel__input',
          value: text,
          onChange: this.handleChange,
          onKeyDown: this.handleKeyDown,
          placeholder: 'Type a message...',
          rows: 1,
          disabled: disabled,
          'aria-label': 'Chat message input',
        }),
        React.createElement('button', {
          className: 'chatPanel__sendBtn',
          onClick: this.handleSend,
          disabled: !this.canSend,
          'aria-label': 'Send message',
          type: 'button',
        },
          // Arrow-up send icon
          React.createElement('svg', { width: '18', height: '18', viewBox: '0 0 18 18', fill: 'none', xmlns: 'http://www.w3.org/2000/svg' },
            React.createElement('path', {
              d: 'M3 15L15 9L3 3V7.5L11 9L3 10.5V15Z',
              fill: 'currentColor',
            })
          )
        )
      )
    );
  }
}

export default ChatInput;
