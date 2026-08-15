import React from 'react';
import '../components/ChatPanel/chatPanel.css';

/**
 * ChatPanelApp — AI persona chat panel with 3-column layout.
 *
 * Features:
 *   - Left: Chat session history sidebar
 *   - Center: Chat messages + input
 *   - Right: Execution settings (model, tokens, tone)
 *   - Markdown rendering for AI responses
 *   - Disclaimer at the bottom
 *
 * @param {Object} props
 * @param {number} props.listing_id
 * @param {string} props.persona_name
 */

// ─── Utility functions ───────────────────────────────────

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

// ─── Simple Markdown renderer (no external deps) ──────────

function renderMarkdown(text) {
  if (!text) return '';

  var html = text
    // Code blocks (triple backtick)
    .replace(/```(\w*)\n([\s\S]*?)```/g, '<pre><code>$2</code></pre>')
    // Inline code
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    // Bold
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    // Italic
    .replace(/\*([^*]+)\*/g, '<em>$1</em>')
    // Headers
    .replace(/^### (.+)$/gm, '<h3>$1</h3>')
    .replace(/^## (.+)$/gm, '<h2>$1</h2>')
    .replace(/^# (.+)$/gm, '<h1>$1</h1>')
    // Unordered lists
    .replace(/^[*-] (.+)$/gm, '<li>$1</li>')
    // Ordered lists
    .replace(/^\d+\. (.+)$/gm, '<li>$1</li>')
    // Blockquotes
    .replace(/^> (.+)$/gm, '<blockquote>$1</blockquote>')
    // Horizontal rule
    .replace(/^---$/gm, '<hr/>')
    // Line breaks to paragraphs
    .replace(/\n\n/g, '</p><p>')
    .replace(/\n/g, '<br/>');

  // Wrap adjacent <li> in <ul>
  html = html.replace(/(<li>[\s\S]*?<\/li>)/g, function(match) {
    if (!match.startsWith('<ul>') && !match.startsWith('<ol>')) {
      return '<ul>' + match + '</ul>';
    }
    return match;
  });

  return '<p>' + html + '</p>';
}

// ─── Message Bubble ──────────────────────────────────────

function MessageBubble(props) {
  var role = props.role;
  var content = props.content;
  var isStreaming = props.isStreaming;
  var totalTokens = props.total_tokens;
  var createdAt = props.created_at;

  var isUser = role === 'user';
  var isSystem = role === 'system';
  var isAssistant = role === 'assistant';

  var bubbleStyle = {
    padding: '12px 16px',
    borderRadius: '16px',
    maxWidth: '85%',
    wordBreak: 'break-word',
    lineHeight: '1.6',
    marginBottom: '8px',
    alignSelf: isUser ? 'flex-end' : isSystem ? 'center' : 'flex-start',
    background: isUser ? '#c41e3a' : isSystem ? 'rgba(255,255,255,0.05)' : '#242424',
    color: isUser ? '#fff' : isSystem ? '#999' : '#e0e0e0',
    border: isAssistant ? '1px solid #333' : isSystem ? '1px solid #333' : 'none',
    fontStyle: isSystem ? 'italic' : 'normal',
    fontSize: isSystem ? '12px' : '14px',
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
  };

  var displayContent = content;
  if (isStreaming && content) {
    displayContent = content;
  }

  var timeStr = createdAt
    ? new Date(createdAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
    : null;

  var renderedContent;
  if (isAssistant) {
    renderedContent = React.createElement('div', {
      className: 'chatMessage__markdown',
      dangerouslySetInnerHTML: { __html: renderMarkdown(displayContent || '') }
    });
  } else {
    renderedContent = displayContent || '';
  }

  return React.createElement('div', { className: 'chatMessage chatMessage--' + (role || 'user') },
    React.createElement('div', { className: 'chatMessage__bubble' },
      renderedContent,
      isStreaming && React.createElement('span', { className: 'chatMessage__streaming' })
    ),
    role === 'assistant' && totalTokens > 0 && (
      React.createElement('span', { className: 'chatMessage__tokens' }, totalTokens + ' tokens')
    ),
    timeStr && role !== 'system' && (
      React.createElement('span', { className: 'chatMessage__meta' }, timeStr)
    )
  );
}

// ─── ChatPanelApp (main class component) ─────────────────

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
      // Settings
      selectedModel: 'gpt-4o',
      tokenLimit: 4000,
      outputLength: 'standard',
      tone: 'polite',
      // History
      sessionHistory: [],
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
    this.handleNewChat = this.handleNewChat.bind(this);
    this.handleModelChange = this.handleModelChange.bind(this);
    this.handleTokenChange = this.handleTokenChange.bind(this);
    this.handleOutputLength = this.handleOutputLength.bind(this);
    this.handleToneChange = this.handleToneChange.bind(this);
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
        self.setState(function (prev) {
          return {
            sessionId: session.id,
            messages: [],
            isLoading: false,
            sessionHistory: prev.sessionHistory.concat([{
              id: session.id,
              title: '新しいチャット',
              timestamp: new Date().toISOString(),
            }]),
          };
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

  handleNewChat() {
    this.disconnect();
    this.closeSession();
    this.setState({ messages: [], sessionId: null, error: null });
    this.createSession();
  }

  handleOpen() {
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

  // ─── Settings handlers ────────────────────────────────

  handleModelChange(e) {
    this.setState({ selectedModel: e.target.value });
  }

  handleTokenChange(e) {
    this.setState({ tokenLimit: parseInt(e.target.value, 10) });
  }

  handleOutputLength(length) {
    this.setState({ outputLength: length });
  }

  handleToneChange(tone) {
    this.setState({ tone: tone });
  }

  // ─── Lifecycle ────────────────────────────────────────

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
    var self = this;
    var personaName = this.props.persona_name || 'AI Assistant';

    // ── Trigger button ────────────────────────────────
    if (!state.isOpen) {
      return React.createElement('button', {
        onClick: this.handleOpen,
        className: 'chatPanel__trigger',
        'aria-label': 'Open AI chat',
        type: 'button',
        style: {
          position: 'fixed', bottom: '24px', right: '24px',
          width: '56px', height: '56px', borderRadius: '50%',
          background: '#c41e3a', color: '#fff', border: 'none',
          cursor: 'pointer', boxShadow: '0 4px 12px rgba(0,0,0,0.3)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          zIndex: 999, fontSize: '24px',
        }
      }, '💬');
    }

    // ── Group history items ────────────────────────────
    var today = [];
    var thisWeek = [];
    var older = [];
    var now = new Date();
    state.sessionHistory.forEach(function (item) {
      var diff = (now - new Date(item.timestamp)) / (1000 * 60 * 60 * 24);
      if (diff < 1) today.push(item);
      else if (diff < 7) thisWeek.push(item);
      else older.push(item);
    });

    // ── Main 3-column layout ──────────────────────────
    return React.createElement('div', {
      className: 'chatPanel__overlay',
      onClick: this.handleClose,
    },
      React.createElement('div', {
        className: 'chatPanel',
        onClick: function (e) { e.stopPropagation(); },
        role: 'dialog',
        'aria-label': 'AI Chat',
        style: {
          display: 'flex',
          flexDirection: 'row',
          width: '900px',
          maxWidth: '100%',
          height: '100%',
          background: '#1a1a1a',
          boxShadow: '-4px 0 24px rgba(0,0,0,0.5)',
          position: 'relative',
          color: '#ffffff',
          fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
          overflow: 'hidden',
        },
      },

        // ═══ LEFT: History sidebar ═══
        React.createElement('div', { className: 'chatPanel__history', style: { width: '240px', background: '#1e1e1e', borderRight: '1px solid #333', display: 'flex', flexDirection: 'column', flexShrink: 0, overflow: 'hidden' } },
          React.createElement('div', { className: 'chatPanel__historyHeader' },
            React.createElement('h4', { className: 'chatPanel__historyTitle' }, '履歴'),
            React.createElement('button', {
              className: 'chatPanel__newChatBtn',
              onClick: this.handleNewChat,
              type: 'button',
            }, '＋ 新規')
          ),
          React.createElement('div', { className: 'chatPanel__historyList' },
            today.length > 0 && React.createElement('div', { className: 'chatPanel__historyGroup' },
              React.createElement('div', { className: 'chatPanel__historyGroupLabel' }, '今日'),
              today.map(function (item) {
                return React.createElement('div', {
                  key: item.id,
                  className: 'chatPanel__historyItem' + (item.id === state.sessionId ? ' is-active' : ''),
                },
                  React.createElement('span', { className: 'chatPanel__historyItemIcon' }, '💬'),
                  React.createElement('span', { className: 'chatPanel__historyItemText' }, item.title)
                );
              })
            ),
            thisWeek.length > 0 && React.createElement('div', { className: 'chatPanel__historyGroup' },
              React.createElement('div', { className: 'chatPanel__historyGroupLabel' }, '過去7日'),
              thisWeek.map(function (item) {
                return React.createElement('div', {
                  key: item.id,
                  className: 'chatPanel__historyItem' + (item.id === state.sessionId ? ' is-active' : ''),
                },
                  React.createElement('span', { className: 'chatPanel__historyItemIcon' }, '💬'),
                  React.createElement('span', { className: 'chatPanel__historyItemText' }, item.title)
                );
              })
            ),
            older.length > 0 && React.createElement('div', { className: 'chatPanel__historyGroup' },
              React.createElement('div', { className: 'chatPanel__historyGroupLabel' }, 'それ以前'),
              older.map(function (item) {
                return React.createElement('div', {
                  key: item.id,
                  className: 'chatPanel__historyItem' + (item.id === state.sessionId ? ' is-active' : ''),
                },
                  React.createElement('span', { className: 'chatPanel__historyItemIcon' }, '💬'),
                  React.createElement('span', { className: 'chatPanel__historyItemText' }, item.title)
                );
              })
            ),
            state.sessionHistory.length === 0 && React.createElement('div', {
              style: { color: '#666', fontSize: '13px', textAlign: 'center', padding: '24px 12px' }
            }, 'まだチャット履歴がありません。')
          )
        ),

        // ═══ CENTER: Chat area ═══
        React.createElement('div', { className: 'chatPanel__chat', style: { flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0 } },
          // Header
          React.createElement('div', { className: 'chatPanel__header' },
            React.createElement('div', { style: { display: 'flex', alignItems: 'center' } },
              React.createElement('h3', { className: 'chatPanel__personaName' }, personaName),
              React.createElement('span', {
                className: 'chatPanel__connectionDot' + (state.isConnected ? '' : ' chatPanel__connectionDot--disconnected')
              })
            ),
            React.createElement('button', {
              onClick: this.handleClose,
              className: 'chatPanel__closeBtn',
              'aria-label': 'Close chat',
              type: 'button',
            },
              React.createElement('svg', { width: '20', height: '20', viewBox: '0 0 20 20', fill: 'none' },
                React.createElement('path', {
                  d: 'M15 5L5 15M5 5l10 10',
                  stroke: 'currentColor', strokeWidth: '2',
                  strokeLinecap: 'round', strokeLinejoin: 'round',
                })
              )
            )
          ),

          // Error
          state.error && React.createElement('div', { className: 'chatPanel__error' }, state.error),

          // Loading
          state.isLoading && React.createElement('div', { className: 'chatPanel__loading' }, '接続中...'),

          // Messages
          React.createElement('div', { className: 'chatPanel__messages' },
            state.messages.length === 0 && !state.isLoading
              ? React.createElement('div', { className: 'chatPanel__emptyState' },
                  React.createElement('div', { className: 'chatPanel__emptyStateIcon' }, '🤖'),
                  personaName + ' にメッセージを送信してください。'
                )
              : state.messages.map(function (msg) {
                  return React.createElement(MessageBubble, {
                    key: msg.id, role: msg.role, content: msg.content,
                    isStreaming: msg.isStreaming,
                    total_tokens: msg.total_tokens,
                    created_at: msg.created_at,
                  });
                }),
            React.createElement('div', { ref: function (el) { self.messagesEndRef = el; } })
          ),

          // Input
          React.createElement('div', { className: 'chatPanel__inputArea' },
            React.createElement('textarea', {
              className: 'chatPanel__input',
              value: state.inputText,
              onChange: this.handleInputChange,
              onKeyDown: this.handleKeyDown,
              placeholder: 'メッセージを入力...',
              rows: 1,
              disabled: state.isLoading,
              'aria-label': 'Chat message input',
            }),
            React.createElement('button', {
              className: 'chatPanel__sendBtn',
              onClick: this.handleSend,
              disabled: state.isLoading || !state.inputText.trim(),
              'aria-label': 'Send message',
              type: 'button',
            },
              React.createElement('svg', { width: '18', height: '18', viewBox: '0 0 18 18', fill: 'none' },
                React.createElement('path', {
                  d: 'M3 15L15 9L3 3V7.5L11 9L3 10.5V15Z',
                  fill: 'currentColor',
                })
              )
            )
          ),

          // Disclaimer
          React.createElement('div', { className: 'chatPanel__disclaimer' },
            '⚠️ AIの回答は必ずしも正確とは限りません。重要な判断はご自身で確認してください。'
          )
        ),

        // ═══ RIGHT: Settings panel ═══
        React.createElement('div', { className: 'chatPanel__settings', style: { width: '220px', background: '#1e1e1e', borderLeft: '1px solid #333', display: 'flex', flexDirection: 'column', flexShrink: 0, padding: '16px', overflowY: 'auto' } },
          React.createElement('h4', { className: 'chatPanel__settingsTitle' }, '⚙️ 実行設定'),

          // Model selection
          React.createElement('div', { className: 'chatPanel__settingsGroup' },
            React.createElement('label', { className: 'chatPanel__settingsLabel' }, 'モデル'),
            React.createElement('select', {
              className: 'chatPanel__settingsSelect',
              value: state.selectedModel,
              onChange: this.handleModelChange,
            },
              React.createElement('option', { value: 'gpt-4o' }, 'GPT-4o'),
              React.createElement('option', { value: 'gpt-4o-mini' }, 'GPT-4o Mini'),
              React.createElement('option', { value: 'claude-sonnet' }, 'Claude Sonnet'),
              React.createElement('option', { value: 'claude-haiku' }, 'Claude Haiku')
            )
          ),

          // Token limit
          React.createElement('div', { className: 'chatPanel__settingsGroup' },
            React.createElement('label', { className: 'chatPanel__settingsLabel' }, 'トークン上限'),
            React.createElement('input', {
              type: 'range',
              className: 'chatPanel__settingsSlider',
              min: '1000',
              max: '8000',
              step: '500',
              value: state.tokenLimit,
              onChange: this.handleTokenChange,
            }),
            React.createElement('div', { className: 'chatPanel__settingsValue' },
              state.tokenLimit.toLocaleString() + ' トークン'
            )
          ),

          // Output length
          React.createElement('div', { className: 'chatPanel__settingsGroup' },
            React.createElement('label', { className: 'chatPanel__settingsLabel' }, '出力の長さ'),
            React.createElement('div', { className: 'chatPanel__toneButtons' },
              ['short', 'standard', 'long'].map(function (length) {
                var labels = { short: '短め', standard: '標準', long: '長め' };
                return React.createElement('button', {
                  key: length,
                  className: 'chatPanel__toneBtn' + (state.outputLength === length ? ' is-active' : ''),
                  onClick: function () { self.handleOutputLength(length); },
                  type: 'button',
                }, labels[length]);
              })
            )
          ),

          // Tone
          React.createElement('div', { className: 'chatPanel__settingsGroup' },
            React.createElement('label', { className: 'chatPanel__settingsLabel' }, 'トーン'),
            React.createElement('select', {
              className: 'chatPanel__settingsSelect',
              value: state.tone,
              onChange: function (e) { self.handleToneChange(e.target.value); },
            },
              React.createElement('option', { value: 'polite' }, '丁寧に'),
              React.createElement('option', { value: 'casual' }, 'カジュアル'),
              React.createElement('option', { value: 'professional' }, 'ビジネス'),
              React.createElement('option', { value: 'friendly' }, 'フレンドリー')
            )
          )
        )
      )
    );
  }
}

export default ChatPanelApp;
