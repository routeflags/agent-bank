import React from 'react';

/**
 * ChatPanelApp — AI persona chat panel with full API/Action Cable integration.
 *
 * Features:
 *   - Session lifecycle (create / fetch / close)
 *   - Action Cable streaming via PersonaChatChannel
 *   - Real-time message assembly from streaming chunks
 *   - CSRF-protected REST API calls
 *
 * @param {Object} props
 * @param {number} props.listing_id
 * @param {string} props.persona_name
 */

// ─── Utility functions (inlined for Webpack bundle reliability) ───

function csrfToken() {
  var metaTag = document.querySelector('meta[name=csrf-token]');
  return metaTag ? metaTag.getAttribute('content') : '';
}

function jsonHeaders() {
  return {
    'Content-Type': 'application/json',
    'X-CSRF-Token': csrfToken(),
  };
}

var sharedConsumer = null;
function getConsumer() {
  if (!sharedConsumer) {
    var cable = window.ActionCable || window.actionCable;
    if (cable && cable.createConsumer) {
      sharedConsumer = cable.createConsumer('/api/cable');
    }
  }
  return sharedConsumer;
}

// ─── Message Bubble ───

function MessageBubble(props) {
  var role = props.role;
  var content = props.content;
  var isStreaming = props.isStreaming;

  var isUser = role === 'user';
  var isSystem = role === 'system';

  var bubbleStyle = {
    padding: '10px 14px',
    borderRadius: '16px',
    maxWidth: '85%',
    wordBreak: 'break-word',
    lineHeight: '1.5',
    fontSize: '14px',
    marginBottom: '8px',
    alignSelf: isUser ? 'flex-end' : 'flex-start',
    background: isUser ? '#59b3a2' : isSystem ? '#f0f0f0' : '#f5f5f5',
    color: isUser ? '#fff' : '#333',
    border: isSystem ? '1px solid #ddd' : 'none',
    fontStyle: isSystem ? 'italic' : 'normal',
    fontSize: isSystem ? '12px' : '14px',
  };

  var displayContent = content;
  if (isStreaming && content) {
    displayContent = content + '▌';
  }

  return React.createElement('div', { style: bubbleStyle }, displayContent || '');
}

// ─── ChatPanelApp (main class component) ───

class ChatPanelApp extends React.Component {
  constructor(props) {
    super(props);
    this.state = {
      isOpen: false,
      sessionId: null,
      messages: [],
      isLoading: false,
      error: null,
      isConnected: false,
      inputText: '',
    };

    this.streamingId = null;
    this.sending = false;
    this.subscription = null;
    this.abortController = null;
    this.messagesEndRef = null;

    this.handleOpen = this.handleOpen.bind(this);
    this.handleClose = this.handleClose.bind(this);
    this.handleInputChange = this.handleInputChange.bind(this);
    this.handleSend = this.handleSend.bind(this);
    this.handleKeyDown = this.handleKeyDown.bind(this);
  }

  // ─── Session management ───────────────────────────────

  createSession() {
    var self = this;
    self.setState({ isLoading: true, error: null });

    return fetch('/api/v1/chat_sessions', {
      method: 'POST',
      headers: jsonHeaders(),
      body: JSON.stringify({ listing_id: self.props.listing_id }),
    })
      .then(function (response) {
        if (!response.ok) {
          return response.json().catch(function () { return {}; }).then(function (body) {
            throw new Error(body.error || 'Failed to create session (HTTP ' + response.status + ')');
          });
        }
        return response.json();
      })
      .then(function (data) {
        var session = data.chat_session;
        self.setState({
          sessionId: session.id,
          messages: [],
          isLoading: false,
        });
        self.subscribeToChannel(session.id);
        return session.id;
      })
      .catch(function (err) {
        self.setState({ error: err.message, isLoading: false });
        return null;
      });
  }

  closeSession() {
    var self = this;
    if (!this.state.sessionId) return Promise.resolve();

    return fetch('/api/v1/chat_sessions/' + this.state.sessionId, {
      method: 'PATCH',
      headers: jsonHeaders(),
      body: JSON.stringify({ status: 'closed' }),
    }).catch(function () {})
      .then(function () {
        self.setState({ sessionId: null, messages: [], error: null });
      });
  }

  // ─── Action Cable ─────────────────────────────────────

  subscribeToChannel(sessionId) {
    var self = this;
    var consumer = getConsumer();
    if (!consumer) {
      console.warn('[ActionCable] consumer not available');
      return;
    }

    var subscription = consumer.subscriptions.create(
      { channel: 'PersonaChatChannel', chat_session_id: sessionId },
      {
        connected: function () { self.setState({ isConnected: true }); },
        disconnected: function () { self.setState({ isConnected: false }); },
        received: function (data) {
          switch (data.type) {
            case 'stream_chunk': self.handleChunk(data); break;
            case 'stream_done': self.handleDone(data); break;
            case 'stream_error': self.handleError(data); break;
          }
        },
      }
    );
    this.subscription = subscription;
  }

  unsubscribeFromChannel() {
    if (this.subscription) {
      this.subscription.unsubscribe();
      this.subscription = null;
    }
  }

  sendMessage(content) {
    if (!this.subscription) return;
    this.subscription.perform('receive', {
      chat_session_id: this.state.sessionId,
      content: content,
    });
  }

  disconnect() {
    this.unsubscribeFromChannel();
  }

  // ─── Streaming handlers ───────────────────────────────

  handleChunk(data) {
    var content = data.content || '';
    if (!this.streamingId) {
      var tempId = 'stream-' + Date.now();
      this.streamingId = tempId;
      this.addMessage(tempId, 'assistant', content, true);
    } else {
      this.appendToMessage(this.streamingId, content);
    }
  }

  handleDone(data) {
    if (this.streamingId) {
      this.finalizeMessage(this.streamingId, data.message_id || this.streamingId);
      this.streamingId = null;
    }
  }

  handleError(data) {
    this.streamingId = null;
    this.addMessage('sys-err-' + Date.now(), 'system', data.error || 'An error occurred.', false);
  }

  // ─── Message helpers ──────────────────────────────────

  addMessage(id, role, content, isStreaming) {
    this.setState(function (prev) {
      return {
        messages: prev.messages.concat([{
          id: id, role: role, content: content,
          isStreaming: isStreaming, created_at: new Date().toISOString(),
        }]),
      };
    });
  }

  appendToMessage(tempId, content) {
    this.setState(function (prev) {
      var updated = prev.messages.map(function (m) {
        if (m.id === tempId) {
          return Object.assign({}, m, { content: (m.content || '') + content });
        }
        return m;
      });
      return { messages: updated };
    });
  }

  finalizeMessage(tempId, finalId) {
    this.setState(function (prev) {
      return {
        messages: prev.messages.map(function (m) {
          if (m.id === tempId) {
            return Object.assign({}, m, { id: finalId, isStreaming: false });
          }
          return m;
        }),
      };
    });
  }

  // ─── User interaction ─────────────────────────────────

  handleInputChange(e) {
    this.setState({ inputText: e.target.value });
  }

  handleKeyDown(e) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      this.handleSend();
    }
  }

  handleSend() {
    var self = this;
    var text = this.state.inputText.trim();
    if (!text || this.sending) return;
    this.sending = true;

    this.addMessage('user-' + Date.now(), 'user', text, false);
    this.setState({ inputText: '' });

    if (this.state.sessionId) {
      this.sendMessage(text);
      this.sending = false;
    } else {
      this.createSession().then(function (id) {
        if (id) {
          self.sendMessage(text);
        } else {
          self.addMessage('sys-err-' + Date.now(), 'system', 'Could not connect to chat.', false);
        }
        self.sending = false;
      });
    }
  }

  handleOpen() {
    var self = this;
    this.setState({ isOpen: true });
    if (!this.state.sessionId) {
      this.createSession();
    }
  }

  handleClose() {
    this.disconnect();
    this.closeSession();
    this.setState({ isOpen: false });
  }

  // ─── Auto-scroll ──────────────────────────────────────

  componentDidUpdate(prevProps, prevState) {
    if (prevState.messages !== this.state.messages && this.messagesEndRef) {
      this.messagesEndRef.scrollIntoView({ behavior: 'smooth' });
    }
  }

  componentWillUnmount() {
    this.disconnect();
  }

  // ─── Render ───────────────────────────────────────────

  render() {
    var state = this.state;
    var personaName = this.props.persona_name || 'AI Assistant';

    // Trigger button
    if (!state.isOpen) {
      return React.createElement('button', {
        onClick: this.handleOpen,
        className: 'chatPanel__trigger',
        'aria-label': 'Open AI chat',
        type: 'button',
        style: {
          position: 'fixed', bottom: '24px', right: '24px',
          width: '56px', height: '56px', borderRadius: '50%',
          background: '#59b3a2', color: '#fff', border: 'none',
          cursor: 'pointer', boxShadow: '0 4px 12px rgba(0,0,0,0.2)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          zIndex: 999,
        }
      }, '💬');
    }

    // Chat panel
    var panelStyle = {
      position: 'fixed', top: 0, right: 0, width: '400px', height: '100%',
      background: '#fff', boxShadow: '-2px 0 12px rgba(0,0,0,0.15)',
      zIndex: 1000, display: 'flex', flexDirection: 'column',
    };

    var headerStyle = {
      padding: '16px', borderBottom: '1px solid #eee',
      display: 'flex', justifyContent: 'space-between', alignItems: 'center',
      background: '#fafafa',
    };

    var messagesStyle = {
      flex: 1, overflowY: 'auto', padding: '16px',
      display: 'flex', flexDirection: 'column',
    };

    var inputAreaStyle = {
      padding: '12px 16px', borderTop: '1px solid #eee',
      display: 'flex', gap: '8px', background: '#fafafa',
    };

    var inputStyle = {
      flex: 1, padding: '10px 14px', border: '1px solid #ddd',
      borderRadius: '20px', fontSize: '14px', outline: 'none',
    };

    var sendBtnStyle = {
      padding: '10px 20px', borderRadius: '20px', border: 'none',
      background: '#59b3a2', color: '#fff', cursor: 'pointer',
      fontSize: '14px', fontWeight: 'bold',
    };

    return React.createElement('div', { style: panelStyle },
      // Header
      React.createElement('div', { style: headerStyle },
        React.createElement('h3', { style: { margin: 0, fontSize: '16px' } }, personaName),
        React.createElement('button', {
          onClick: this.handleClose,
          style: { border: 'none', background: 'none', cursor: 'pointer', fontSize: '20px', padding: '4px' },
        }, '✕')
      ),

      // Error banner
      state.error ? React.createElement('div', {
        style: { padding: '8px 16px', background: '#fff3cd', color: '#856404', fontSize: '13px' },
      }, state.error) : null,

      // Loading indicator
      state.isLoading ? React.createElement('div', {
        style: { padding: '8px 16px', color: '#999', fontSize: '13px', textAlign: 'center' },
      }, '接続中...') : null,

      // Messages
      React.createElement('div', { style: messagesStyle },
        state.messages.length === 0 && !state.isLoading
          ? React.createElement('div', {
              style: { color: '#999', textAlign: 'center', paddingTop: '40px', fontSize: '14px' },
            }, personaName + ' にメッセージを送信してください。')
          : state.messages.map(function (msg) {
              return React.createElement(MessageBubble, {
                key: msg.id, role: msg.role, content: msg.content,
                isStreaming: msg.isStreaming,
              });
            }),
        React.createElement('div', { ref: function (el) { this.messagesEndRef = el; }.bind(this) })
      ),

      // Input area
      React.createElement('div', { style: inputAreaStyle },
        React.createElement('input', {
          type: 'text', placeholder: 'メッセージを入力...',
          style: inputStyle, value: state.inputText,
          onChange: this.handleInputChange, onKeyDown: this.handleKeyDown,
          disabled: state.isLoading,
        }),
        React.createElement('button', {
          style: sendBtnStyle, onClick: this.handleSend,
          disabled: state.isLoading || !state.inputText.trim(),
        }, '送信')
      )
    );
  }
}

export default ChatPanelApp;
