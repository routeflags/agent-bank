/**
 * ChatPanel — Main container for the AI persona chat UI.
 *
 * Composes:
 *   - ChatHeader    (persona name + close button)
 *   - Message list  (scrollable area)
 *   - ChatInput     (message input + send button)
 *
 * Manages:
 *   - Session lifecycle (create / fetch / close)
 *   - WebSocket connection via Action Cable
 *   - Streaming message assembly from Action Cable chunks
 *
 * @param {Object} props
 * @param {number} props.listingId - The listing (persona) to chat with
 * @param {string} [props.personaName] - Display name of the persona
 * @param {Function} props.onClose - Called when the panel should close
 */
import React from 'react';
import ChatHeader from './ChatHeader';
import ChatMessage from './ChatMessage';
import ChatInput from './ChatInput';
// import css from './chatPanel.css';

/**
 * Singleton Action Cable consumer.
 * Multiple subscriptions share the same underlying WebSocket connection.
 */
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

/**
 * Read CSRF token from <meta name="csrf-token">.
 */
function csrfToken() {
  var metaTag = document.querySelector('meta[name=csrf-token]');
  return metaTag ? metaTag.getAttribute('content') : '';
}

/**
 * Default headers for all state-changing fetch requests.
 */
function jsonHeaders() {
  return {
    'Content-Type': 'application/json',
    'X-CSRF-Token': csrfToken(),
  };
}

class ChatPanel extends React.Component {
  constructor(props) {
    super(props);

    this.state = {
      sessionId: null,
      messages: [],
      isLoading: false,
      error: null,
      isConnected: false,
    };

    // Refs (plain instance properties — no React.createRef needed for these)
    this.streamingId = null;
    this.sending = false;
    this.messagesEndRef = null;
    this.subscription = null;
    this.abortController = null;

    // Bind all methods
    this.createSession = this.createSession.bind(this);
    this.closeSession = this.closeSession.bind(this);
    this.fetchMessages = this.fetchMessages.bind(this);
    this.addUserMessage = this.addUserMessage.bind(this);
    this.upsertAssistantMessage = this.upsertAssistantMessage.bind(this);
    this.finalizeAssistantMessage = this.finalizeAssistantMessage.bind(this);
    this.markStreaming = this.markStreaming.bind(this);
    this.addSystemMessage = this.addSystemMessage.bind(this);

    this.handleChunk = this.handleChunk.bind(this);
    this.handleDone = this.handleDone.bind(this);
    this.handleError = this.handleError.bind(this);

    this.subscribeToChannel = this.subscribeToChannel.bind(this);
    this.unsubscribeFromChannel = this.unsubscribeFromChannel.bind(this);
    this.sendMessage = this.sendMessage.bind(this);
    this.disconnect = this.disconnect.bind(this);

    this.handleSend = this.handleSend.bind(this);
    this.handleClose = this.handleClose.bind(this);
    this.handleOverlayClick = this.handleOverlayClick.bind(this);
    this.handlePanelClick = this.handlePanelClick.bind(this);
  }

  // ─── Lifecycle ──────────────────────────────────────────────

  componentDidMount() {
    // Create session on mount
    this.createSession();
  }

  componentDidUpdate(prevProps, prevState) {
    // Re-subscribe to Action Cable when sessionId changes
    if (prevState.sessionId !== this.state.sessionId) {
      if (prevState.sessionId) {
        this.unsubscribeFromChannel();
      }
      if (this.state.sessionId) {
        this.subscribeToChannel(this.state.sessionId);
      }
    }

    // Auto-scroll to bottom when messages change
    if (prevState.messages !== this.state.messages) {
      if (this.messagesEndRef) {
        this.messagesEndRef.scrollIntoView({ behavior: 'smooth' });
      }
    }
  }

  componentWillUnmount() {
    // Abort in-flight fetch requests
    if (this.abortController) {
      this.abortController.abort();
    }
    // Disconnect WebSocket
    this.disconnect();
    // Close session (best-effort, fire-and-forget)
    this.closeSession();
  }

  // ─── Session management (formerly useChatSession) ───────────

  fetchMessages(id) {
    var self = this;
    var controller = new AbortController();
    this.abortController = controller;

    return fetch('/api/v1/chat_sessions/' + id, {
      signal: controller.signal,
    })
      .then(function (response) {
        if (!response.ok) {
          throw new Error('Failed to load messages (HTTP ' + response.status + ')');
        }
        return response.json();
      })
      .then(function (data) {
        var messages = (data.chat_session && data.chat_session.messages) || [];
        self.setState({ messages: messages });
        return messages;
      })
      .catch(function (err) {
        if (err.name === 'AbortError') return [];
        self.setState({ error: err.message });
        return [];
      });
  }

  createSession() {
    var self = this;
    self.setState({ isLoading: true, error: null });

    var controller = new AbortController();
    self.abortController = controller;

    // Check for an existing active session via index
    return fetch('/api/v1/chat_sessions', {
      signal: controller.signal,
    })
      .then(function (indexResponse) {
        if (!indexResponse.ok) return null;
        return indexResponse.json();
      })
      .then(function (indexData) {
        if (!indexData) return self._createNewSession(controller);

        var existing = (indexData.chat_sessions || []).find(function (s) {
          return s.listing_id === self.props.listingId && s.status === 'active';
        });

        if (existing) {
          self.setState({ sessionId: existing.id });
          return self.fetchMessages(existing.id).then(function () {
            self.setState({ isLoading: false });
            return existing.id;
          });
        }

        return self._createNewSession(controller);
      })
      .catch(function (err) {
        if (err.name === 'AbortError') return null;
        self.setState({ error: err.message, isLoading: false });
        return null;
      });
  }

  _createNewSession(controller) {
    var self = this;

    return fetch('/api/v1/chat_sessions', {
      method: 'POST',
      headers: jsonHeaders(),
      body: JSON.stringify({ listing_id: self.props.listingId }),
      signal: controller.signal,
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
        var newSession = data.chat_session;
        self.setState({
          sessionId: newSession.id,
          messages: [],
          isLoading: false,
        });
        return newSession.id;
      })
      .catch(function (err) {
        if (err.name === 'AbortError') return null;
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
    })
      .catch(function (err) {
        console.warn('[ChatSession] Failed to close session:', err.message);
      })
      .then(function () {
        self.setState({ sessionId: null, messages: [], error: null });
      });
  }

  // ─── Message state mutations ────────────────────────────────

  addUserMessage(content) {
    this.setState(function (prevState) {
      return {
        messages: prevState.messages.concat([{
          id: 'temp-' + Date.now(),
          role: 'user',
          content: content,
          seq: (prevState.messages.length || 0) + 1,
          created_at: new Date().toISOString(),
        }]),
      };
    });
  }

  upsertAssistantMessage(tempId, content) {
    this.setState(function (prevState) {
      var idx = prevState.messages.findIndex(function (m) { return m.id === tempId; });
      if (idx >= 0) {
        var updated = prevState.messages.slice();
        updated[idx] = Object.assign({}, updated[idx], {
          content: (updated[idx].content || '') + content,
        });
        return { messages: updated };
      }
      return {
        messages: prevState.messages.concat([{
          id: tempId,
          role: 'assistant',
          content: content,
          seq: prevState.messages.length + 1,
          created_at: new Date().toISOString(),
        }]),
      };
    });
  }

  finalizeAssistantMessage(tempId, finalId, totalTokens) {
    this.setState(function (prevState) {
      return {
        messages: prevState.messages.map(function (m) {
          if (m.id === tempId) {
            return Object.assign({}, m, {
              id: finalId,
              total_tokens: totalTokens,
              isStreaming: false,
            });
          }
          return m;
        }),
      };
    });
  }

  markStreaming(tempId) {
    this.setState(function (prevState) {
      return {
        messages: prevState.messages.map(function (m) {
          if (m.id === tempId) {
            return Object.assign({}, m, { isStreaming: true });
          }
          return m;
        }),
      };
    });
  }

  addSystemMessage(content) {
    this.setState(function (prevState) {
      return {
        messages: prevState.messages.concat([{
          id: 'sys-' + Date.now(),
          role: 'system',
          content: content,
          seq: prevState.messages.length + 1,
          created_at: new Date().toISOString(),
        }]),
      };
    });
  }

  // ─── Action Cable (formerly useActionCable) ─────────────────

  subscribeToChannel(sessionId) {
    var self = this;
    var consumer = getConsumer();
    if (!consumer) {
      console.warn('[ActionCable] ActionCable consumer not available on window');
      return;
    }

    var subscription = consumer.subscriptions.create(
      { channel: 'PersonaChatChannel', chat_session_id: sessionId },
      {
        connected: function () {
          self.setState({ isConnected: true });
        },
        disconnected: function () {
          self.setState({ isConnected: false });
        },
        received: function (data) {
          var type = data.type;
          switch (type) {
            case 'stream_chunk':
              self.handleChunk(data);
              break;
            case 'stream_done':
              self.handleDone(data);
              break;
            case 'stream_error':
              self.handleError(data);
              break;
            default:
              break;
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
      this.setState({ isConnected: false });
    }
  }

  sendMessage(content) {
    if (!this.subscription) {
      console.warn('[ActionCable] Cannot send: no active subscription');
      return;
    }
    this.subscription.perform('receive', {
      chat_session_id: this.state.sessionId,
      content: content,
    });
  }

  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe();
      this.subscription = null;
      this.setState({ isConnected: false });
    }
  }

  // ─── Action Cable event handlers ────────────────────────────

  handleChunk(data) {
    var content = data.content || '';

    if (!this.streamingId) {
      // First chunk of a new assistant response — create a temp message
      var tempId = 'stream-' + Date.now();
      this.streamingId = tempId;
      this.upsertAssistantMessage(tempId, content);
      this.markStreaming(tempId);
    } else {
      // Subsequent chunk — append content
      this.upsertAssistantMessage(this.streamingId, content);
    }
  }

  handleDone(data) {
    if (this.streamingId) {
      this.finalizeAssistantMessage(
        this.streamingId,
        data.message_id || this.streamingId,
        data.total_tokens || 0
      );
      this.streamingId = null;
    }
  }

  handleError(data) {
    this.streamingId = null;
    var errorMsg = data.error || 'An error occurred while generating a response.';
    this.addSystemMessage(errorMsg);
  }

  // ─── User interaction handlers ──────────────────────────────

  handleSend(content) {
    var self = this;
    if (this.sending) return;
    this.sending = true;

    this.addUserMessage(content);

    var activeSessionId = this.state.sessionId;

    if (activeSessionId) {
      this.sendMessage(content);
      this.sending = false;
    } else {
      this.createSession().then(function (newId) {
        if (newId) {
          self.sendMessage(content);
        } else {
          self.addSystemMessage('Could not connect to chat. Please try again.');
        }
        self.sending = false;
      });
    }
  }

  handleClose() {
    this.disconnect();
    this.closeSession();
    this.props.onClose();
  }

  handleOverlayClick() {
    // On mobile, tap on overlay should not close (same as original)
    var isMobile = typeof window !== 'undefined' && window.innerWidth < 768;
    if (!isMobile) {
      this.handleClose();
    }
  }

  handlePanelClick(e) {
    e.stopPropagation();
  }

  // ─── Render ─────────────────────────────────────────────────

  render() {
    var state = this.state;
    var personaName = this.props.personaName;
    var isMobile = typeof window !== 'undefined' && window.innerWidth < 768;

    return (
      React.createElement('div', {
          className: 'chatPanel__overlay',
          onClick: isMobile ? undefined : this.handleOverlayClick,
        },
        React.createElement('div', {
          className: 'chatPanel',
          onClick: this.handlePanelClick,
          role: 'dialog',
          'aria-label': 'AI Chat',
        },
          React.createElement(ChatHeader, {
            personaName: personaName,
            onClose: this.handleClose,
          }),

          // Error banner
          state.error && (
            React.createElement('div', { className: 'chatPanel__error' }, state.error)
          ),

          // Messages
          React.createElement('div', { className: 'chatPanel__messages' },
            state.messages.length === 0 && !state.isLoading ? (
              React.createElement('div', { className: 'chatPanel__emptyState' },
                'Start a conversation with ' + (personaName || 'the AI assistant') + '.'
              )
            ) : (
              state.messages.map(function (msg) {
                return React.createElement(ChatMessage, {
                  key: msg.id,
                  role: msg.role,
                  content: msg.content,
                  isStreaming: msg.isStreaming,
                  total_tokens: msg.total_tokens,
                  created_at: msg.created_at,
                });
              })
            ),
            React.createElement('div', { ref: (el) => { this.messagesEndRef = el; } })
          ),

          React.createElement(ChatInput, {
            onSend: this.handleSend,
            disabled: state.isLoading,
          })
        )
      )
    );
  }
}

export default ChatPanel;
