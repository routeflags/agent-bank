import React from 'react';
import '../components/ChatPanel/chatPanel.css';
import '../components/ChatPanel/wallet-topup.css';

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

// ─── HTML sanitization ────────────────────────────────────

/**
 * Escape HTML entities to prevent XSS from AI-generated content.
 * This must run BEFORE any markdown-to-HTML conversion so that
 * user/agent-supplied tags like <script> are neutralized.
 */
function sanitizeHTML(text) {
  if (!text) return '';
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// ─── Simple Markdown renderer (no external deps) ──────────

function renderMarkdown(text) {
  if (!text) return '';

  // Sanitize first: escape any HTML that could be injected
  var sanitized = sanitizeHTML(text);

  var html = sanitized
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

// ─── i18n ─────────────────────────────────────────────────────
// Server-provided strings (props.i18n from lamprey.chat.*) with
// Japanese defaults so the panel never renders blank keys.
var DEFAULT_I18N = {
  wallet_topup_title: 'クレジットを追加',
  wallet_topup_close: '閉じる',
  wallet_current_balance: '現在の残高: ¥',
  wallet_custom_label: 'カスタム:',
  wallet_amount_placeholder: '金額を入力（円）',
  wallet_invalid_amount: '金額は100円〜10,000円の間で指定してください。',
  wallet_pay_failed: '決済に失敗しました。',
  wallet_success: '✅ 追加が完了しました！',
  wallet_processing: '処理中...',
  wallet_submit: '追加する',
  wallet_add_credits: 'クレジットを追加する',
  wallet_buy: '購入する',
  wallet_add_preparing: '追加する（準備中）',
  wallet_add_preparing_body: 'ウォレットへの追加機能は現在準備中です。正式リリースまでお待ちください。',
  purchase_preparing_body: 'このペルソナの購入ページは現在準備中です。正式リリースまでお待ちください。',
  new_chat_title: '新しいチャット',
  insufficient_tokens: 'トークンが不足しています。',
  purchase_required: 'このペルソナを利用するには購入が必要です。',
  error_generic: 'エラーが発生しました。',
  wallet_insufficient: 'ウォレットの残高が不足しています。',
  connect_failed: 'チャットに接続できませんでした。しばらくしてからもう一度お試しください。',
  session_create_failed: 'セッションの作成に失敗しました。',
  history_title: '履歴',
  history_new: '＋ 新規',
  history_today: '今日',
  history_past_week: '過去7日',
  history_earlier: 'それ以前',
  history_empty: 'まだチャット履歴がありません。',
  loading: '接続中...',
  empty_state: '%{name} にメッセージを送信してください。',
  input_placeholder: 'メッセージを入力してください...',
  disclaimer: '⚠️ AIの回答は必ずしも正確とは限りません。重要な判断はご自身で確認してください。',
  balance_label: '残高',
  settings_title: '⚙️ 実行設定',
  settings_model: 'モデル',
  settings_token_limit: 'トークン上限',
  settings_tokens_unit: '%{count} トークン',
  settings_output_length: '出力の長さ',
  output_short: '短め',
  output_standard: '標準',
  output_long: '長め',
  settings_tone: 'トーン',
  tone_polite: '丁寧に',
  tone_casual: 'カジュアル',
  tone_professional: 'ビジネス',
  tone_friendly: 'フレンドリー',
  message_tokens: '%{count} トークン',
  result_panel_heading: '最新の成果',
  result_panel_jump: '会話へ移動',
  result_badge: 'RESULT',
  result_title: 'Best Answer',
  attach_button: '画像を添付',
  attach_remove: '添付を取り消す',
  attach_upload_failed: '画像のアップロードに失敗しました。',
  attach_invalid_type: '画像ファイル（JPG/PNG/GIF/WebP）を選択してください。',
  attach_too_large: '画像は5MB以下にしてください。',
  a11y_dialog: 'AIチャット',
  a11y_open: 'AIチャットを開く',
  a11y_close: 'チャットを閉じる',
  a11y_input: 'チャットメッセージ入力',
  a11y_send: 'メッセージを送信'
};
var I18N = Object.assign({}, DEFAULT_I18N);
function t(key) { return I18N[key] != null ? I18N[key] : (DEFAULT_I18N[key] || key); }
function setI18n(obj) { I18N = Object.assign({}, DEFAULT_I18N, obj || {}); }
function tFormat(key, vars) {
  var s = t(key);
  Object.keys(vars || {}).forEach(function (k) {
    s = s.split('%{' + k + '}').join(String(vars[k]));
  });
  return s;
}

// ─── Wallet Top-up Modal ──────────────────────────────────

var TOPUP_AMOUNTS = [
  { cents: 1000, label: '¥1,000' },
  { cents: 3000, label: '¥3,000' },
  { cents: 5000, label: '¥5,000' },
];

class WalletTopupModal extends React.Component {
  constructor(props) {
    super(props);
    this.state = {
      selectedCents: 3000,
      customAmount: '',
      isProcessing: false,
      error: null,
      success: false,
    };
    this.handleSelectAmount = this.handleSelectAmount.bind(this);
    this.handleCustomChange = this.handleCustomChange.bind(this);
    this.handleSubmit = this.handleSubmit.bind(this);
    this.handleOverlayClick = this.handleOverlayClick.bind(this);
  }

  handleSelectAmount(cents) {
    this.setState({ selectedCents: cents, customAmount: '', error: null });
  }

  handleCustomChange(e) {
    var raw = e.target.value.replace(/[^0-9]/g, '');
    this.setState({ customAmount: raw, selectedCents: null, error: null });
  }

  getAmountCents() {
    if (this.state.selectedCents) return this.state.selectedCents;
    var parsed = parseInt(this.state.customAmount, 10);
    return isNaN(parsed) ? 0 : parsed;
  }

  handleSubmit() {
    var self = this;
    var amountCents = this.getAmountCents();

    if (amountCents < 100 || amountCents > 10000) {
      self.setState({ error: t('wallet_invalid_amount') });
      return;
    }

    self.setState({ isProcessing: true, error: null });

    // Step 1: Create a PaymentIntent
    fetch('/api/v1/wallet_topup', {
      method: 'POST',
      headers: jsonHeaders(),
      body: JSON.stringify({ amount_cents: amountCents }),
    })
      .then(function (response) {
        if (!response.ok) {
          return response.json().catch(function () { return {}; }).then(function (body) {
            throw new Error(body.error || 'PaymentIntent creation failed');
          });
        }
        return response.json();
      })
      .then(function (data) {
        // Step 2: Confirm the payment (simplified — in production this
        // would use Stripe.js to collect card details and confirm)
        return fetch('/api/v1/wallet_topup/confirm', {
          method: 'POST',
          headers: jsonHeaders(),
          body: JSON.stringify({ payment_intent_id: data.payment_intent_id }),
        });
      })
      .then(function (response) {
        if (!response.ok) {
          return response.json().catch(function () { return {}; }).then(function (body) {
            throw new Error(body.error || 'Payment confirmation failed');
          });
        }
        return response.json();
      })
      .then(function (data) {
        self.setState({ isProcessing: false, success: true });
        if (self.props.onSuccess) self.props.onSuccess(data.balance_cents);
        setTimeout(function () { self.props.onClose(); }, 1200);
      })
      .catch(function (err) {
        self.setState({ isProcessing: false, error: err.message || t('wallet_pay_failed') });
      });
  }

  handleOverlayClick(e) {
    if (e.target === e.currentTarget) this.props.onClose();
  }

  render() {
    var state = this.state;
    var self = this;

    return React.createElement('div', {
      className: 'wallet-topup-modal__overlay',
      onClick: this.handleOverlayClick,
    },
      React.createElement('div', { className: 'wallet-topup-modal', role: 'dialog', 'aria-label': t('wallet_topup_title') },
        // Header
        React.createElement('div', { className: 'wallet-topup-modal__header' },
          React.createElement('h3', { className: 'wallet-topup-modal__title' }, '💰 ' + t('wallet_topup_title')),
          React.createElement('button', {
            className: 'wallet-topup-modal__closeBtn',
            onClick: this.props.onClose,
            'aria-label': t('wallet_topup_close'),
            type: 'button',
          },
            React.createElement('svg', { width: '18', height: '18', viewBox: '0 0 20 20', fill: 'none' },
              React.createElement('path', {
                d: 'M15 5L5 15M5 5l10 10',
                stroke: 'currentColor', strokeWidth: '2',
                strokeLinecap: 'round', strokeLinejoin: 'round',
              })
            )
          )
        ),

        // Current balance
        React.createElement('div', {
          style: { fontSize: '13px', color: '#999', marginBottom: '16px' }
        }, t('wallet_current_balance') + (this.props.balance || 0).toLocaleString()),

        // Amount grid
        React.createElement('div', { className: 'wallet-topup-modal__amounts' },
          TOPUP_AMOUNTS.map(function (opt) {
            return React.createElement('button', {
              key: opt.cents,
              className: 'wallet-topup-modal__amountBtn' + (state.selectedCents === opt.cents ? ' is-selected' : ''),
              onClick: function () { self.handleSelectAmount(opt.cents); },
              type: 'button',
            }, opt.label);
          })
        ),

        // Custom amount
        React.createElement('div', { className: 'wallet-topup-modal__customAmount' },
          React.createElement('span', { className: 'wallet-topup-modal__customLabel' }, t('wallet_custom_label')),
          React.createElement('input', {
            className: 'wallet-topup-modal__customInput',
            type: 'text',
            inputMode: 'numeric',
            placeholder: t('wallet_amount_placeholder'),
            value: state.customAmount,
            onChange: this.handleCustomChange,
          })
        ),

        // Status messages
        state.error && React.createElement('div', { className: 'wallet-topup-modal__error' }, state.error),
        state.success && React.createElement('div', { className: 'wallet-topup-modal__success' }, t('wallet_success')),

        // Submit
        React.createElement('button', {
          className: 'wallet-topup-modal__submitBtn',
          onClick: this.handleSubmit,
          disabled: state.isProcessing || state.success || this.getAmountCents() < 100,
          type: 'button',
        },
          state.isProcessing
            ? React.createElement('span', null,
                React.createElement('span', { className: 'wallet-topup-modal__spinner' }),
                t('wallet_processing')
              )
            : t('wallet_submit')
        )
      )
    );
  }
}

// ─── Message Bubble ──────────────────────────────────────

function MessageBubble(props) {
  var role = props.role;
  var content = props.content;
  var isStreaming = props.isStreaming;
  var totalTokens = props.total_tokens;
  var createdAt = props.created_at;
  var showTopupButton = props.showTopupButton;
  var onTopupClick = props.onTopupClick;
  var showPurchaseButton = props.showPurchaseButton;
  var onPurchaseClick = props.onPurchaseClick;
  var attachment = props.attachment;
  // 特別な成果表示（DESIGN.md §13）は明示フラグが付いた回答にのみ適用する
  var isResult = props.is_result === true;

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
    background: isUser ? 'var(--chat-surface-user)' : isSystem ? 'rgba(255,255,255,0.05)' : '#242424',
    color: isUser ? '#fff' : isSystem ? '#999' : '#e0e0e0',
    border: isUser ? '1px solid var(--chat-border-user)' : isAssistant ? '1px solid #333' : isSystem ? '1px solid #333' : 'none',
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

  return React.createElement('div', { className: 'chatMessage chatMessage--' + (role || 'user') + (isAssistant && !isStreaming && displayContent ? ' chatMessage--assistant-done' : '') },
    React.createElement('div', { className: 'chatMessage__bubble' },
      // RESULT Best Answer card header (designs/chat-sp.png §7-3)
      // DESIGN.md §13: 特別な成果表示であり通常の回答すべてには出さない
      isAssistant && !isStreaming && displayContent && isResult && React.createElement('div', { className: 'chatMessage__result' },
        React.createElement('span', { className: 'chatMessage__result-badge' }, t('result_badge')),
        React.createElement('span', { className: 'chatMessage__result-title' }, t('result_title'))
      ),
      renderedContent,
      attachment && attachment.url && React.createElement('img', {
        className: 'chatMessage__attachment',
        src: attachment.url,
        alt: '',
      }),
      isStreaming && React.createElement('span', { className: 'chatMessage__streaming' })
    ),
    // Show topup button for insufficient balance errors
    showTopupButton && onTopupClick && React.createElement('div', { className: 'wallet-topup-prompt' },
      React.createElement('button', {
        className: 'wallet-topup-prompt__btn',
        onClick: onTopupClick,
        type: 'button',
      }, t('wallet_add_credits'))
    ),
    // Show purchase button for purchase_required errors
    showPurchaseButton && onPurchaseClick && React.createElement('div', { className: 'wallet-topup-prompt' },
      React.createElement('button', {
        className: 'wallet-topup-prompt__btn',
        onClick: onPurchaseClick,
        type: 'button',
      }, t('wallet_buy'))
    ),
    role === 'assistant' && totalTokens > 0 && (
      React.createElement('span', { className: 'chatMessage__tokens' }, tFormat('message_tokens', { count: totalTokens }))
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
    setI18n(props.i18n);
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
      // Wallet
      walletBalance: 0,
      walletLoading: false,
      showTopupModal: false,
      // Attachment (composer 📎)
      pendingAttachment: null,
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
    this.handleAttachClick = this.handleAttachClick.bind(this);
    this.handleFileSelected = this.handleFileSelected.bind(this);
    this.handleRemoveAttachment = this.handleRemoveAttachment.bind(this);
    this.handleOpenTopup = this.handleOpenTopup.bind(this);
    this.handleCloseTopup = this.handleCloseTopup.bind(this);
    this.handleTopupSuccess = this.handleTopupSuccess.bind(this);
    this.handlePurchase = this.handlePurchase.bind(this);
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
            // エラータイプを保持して、呼び出し元で適切なメッセージを表示できるようにする
            var err = new Error(body.error || t('session_create_failed'));
            err.error_type = body.error_type || null;
            throw err;
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
              title: t('new_chat_title'),
              timestamp: new Date().toISOString(),
            }]),
          };
        });
        self.subscribeToChannel(session.id);
        self.fetchWalletBalance();
        self.loadSessionMessages(session.id);
        return { id: session.id, error_type: null };
      })
      .catch(function (err) {
        self.setState({ error: err.message, isLoading: false });
        return { id: null, error_type: err.error_type || null };
      });
  }

  // 履歴読み込み: 既存セッション（POST が冪等で返したもの）のメッセージを取得
  loadSessionMessages(sessionId) {
    var self = this;
    return fetch('/api/v1/chat_sessions/' + sessionId, {
      headers: jsonHeaders(),
    })
      .then(function (response) {
        if (!response.ok) return null;
        return response.json();
      })
      .then(function (data) {
        if (!data || !data.chat_session) return;
        var messages = (data.chat_session.messages || []).map(function (m) {
          return {
            id: m.id,
            role: m.role,
            content: m.content,
            isStreaming: false,
            is_result: m.is_result === true,
            created_at: m.created_at,
            total_tokens: (m.input_tokens || 0) + (m.output_tokens || 0),
            attachment: m.attachment || null,
          };
        });
        self.setState({ messages: messages });
      })
      .catch(function () {});
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

  sendMessage(content, attachment) {
    if (!this.subscription) return;
    var payload = {
      chat_session_id: this.state.sessionId,
      content: content,
    };
    if (attachment && attachment.id) payload.attachment_id = attachment.id;
    this.subscription.perform('receive', payload);
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
      this.finalizeMessage(this.streamingId, data.message_id || this.streamingId, data.is_result === true);
      this.streamingId = null;
    }
  }

  handleError(data) {
    this.streamingId = null;

    if (data.error_type === 'insufficient_balance') {
      // Update wallet balance if server sent current_balance
      if (typeof data.current_balance === 'number') {
        this.setState({ walletBalance: data.current_balance });
      }
      // Show error message with inline topup button
      this.setState(function (prev) {
        return {
          messages: prev.messages.concat([{
            id: 'sys-err-' + Date.now(),
            role: 'system',
            content: data.error || t('insufficient_tokens'),
            isStreaming: false,
            created_at: new Date().toISOString(),
            showTopupButton: true,
          }]),
        };
      });
    } else if (data.error_type === 'purchase_required') {
      this.setState(function (prev) {
        return {
          messages: prev.messages.concat([{
            id: 'sys-err-' + Date.now(),
            role: 'system',
            content: data.error || t('purchase_required'),
            isStreaming: false,
            created_at: new Date().toISOString(),
            showPurchaseButton: true,
          }]),
        };
      });
    } else {
      this.addMessage('sys-err-' + Date.now(), 'system', data.error || t('error_generic'), false);
    }
  }

  // ─── Message helpers ──────────────────────────────────

  addMessage(id, role, content, isStreaming, attachment) {
    this.setState(function (prev) {
      return {
        messages: prev.messages.concat([{
          id: id, role: role, content: content,
          isStreaming: isStreaming, created_at: new Date().toISOString(),
          attachment: attachment || null,
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

  finalizeMessage(tempId, finalId, isResult) {
    this.setState(function (prev) {
      return {
        messages: prev.messages.map(function (m) {
          if (m.id === tempId) {
            return Object.assign({}, m, {
              id: finalId,
              isStreaming: false,
              is_result: isResult === true,
            });
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
    var pending = this.state.pendingAttachment;
    if ((!text && !(pending && pending.status === 'ready')) || this.sending) return;
    if (pending && pending.status === 'uploading') return;
    this.sending = true;

    var attachment = pending && pending.status === 'ready'
      ? { id: pending.id, url: pending.url }
      : null;
    this.addMessage('user-' + Date.now(), 'user', text, false, attachment);
    this.setState({ inputText: '', pendingAttachment: null });

    if (this.state.sessionId) {
      this.sendMessage(text, attachment);
      this.sending = false;
    } else {
      this.createSession().then(function (result) {
        if (result && result.id) {
          self.sendMessage(text, attachment);
        } else {
          // エラータイプに応じて適切なメッセージを表示
          var errorType = result ? result.error_type : null;
          if (errorType === 'purchase_required') {
            // 購入が必要な場合は購入導線のみ表示（接続エラーメッセージは出さない）
            self.setState(function (prev) {
              return {
                error: null,
                messages: prev.messages.concat([{
                  id: 'sys-purchase-' + Date.now(),
                  role: 'system',
                  content: 'このペルソナを利用するには購入が必要です。',
                  isStreaming: false,
                  created_at: new Date().toISOString(),
                  showPurchaseButton: true,
                }]),
              };
            });
          } else if (errorType === 'insufficient_balance') {
            self.setState(function (prev) {
              return {
                error: null,
                messages: prev.messages.concat([{
                  id: 'sys-balance-' + Date.now(),
                  role: 'system',
                  content: t('wallet_insufficient'),
                  isStreaming: false,
                  created_at: new Date().toISOString(),
                  showTopupButton: true,
                }]),
              };
            });
          } else {
            // その他の接続エラー
            self.addMessage('sys-err-' + Date.now(), 'system', t('connect_failed'), false);
          }
        }
        self.sending = false;
      });
    }
  }

  handleAttachClick() {
    if (this.fileInputRef) this.fileInputRef.click();
  }

  handleRemoveAttachment() {
    this.setState({ pendingAttachment: null });
    if (this.fileInputRef) this.fileInputRef.value = '';
  }

  handleFileSelected(e) {
    var self = this;
    var file = e.target.files && e.target.files[0];
    if (!file) return;

    var allowed = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];
    if (allowed.indexOf(file.type) === -1) {
      this.addMessage('sys-attach-' + Date.now(), 'system', t('attach_invalid_type'), false);
      return;
    }
    if (file.size > 5 * 1024 * 1024) {
      this.addMessage('sys-attach-' + Date.now(), 'system', t('attach_too_large'), false);
      return;
    }

    this.setState({ pendingAttachment: { status: 'uploading', name: file.name } });

    var upload = this.state.sessionId
      ? Promise.resolve(this.state.sessionId)
      : this.createSession().then(function (result) { return result && result.id; });

    upload.then(function (sessionId) {
      if (!sessionId) {
        self.setState({ pendingAttachment: null });
        self.addMessage('sys-attach-' + Date.now(), 'system', t('attach_upload_failed'), false);
        return;
      }
      var formData = new FormData();
      formData.append('image', file);
      return fetch('/api/v1/chat_sessions/' + sessionId + '/attachments', {
        method: 'POST',
        headers: { 'X-CSRF-Token': csrfToken() },
        credentials: 'same-origin',
        body: formData,
      }).then(function (res) {
        if (!res.ok) throw new Error('upload failed');
        return res.json();
      }).then(function (data) {
        self.setState({
          sessionId: sessionId,
          pendingAttachment: { status: 'ready', id: data.id, url: data.url, name: file.name },
        });
      });
    }).catch(function () {
      self.setState({ pendingAttachment: null });
      self.addMessage('sys-attach-' + Date.now(), 'system', t('attach_upload_failed'), false);
    });
  }

  handleNewChat() {
    this.disconnect();
    this.closeSession();
    this.setState({ messages: [], sessionId: null, error: null });
    this.createSession();
  }

  handleOpen() {
    this.setState({ isOpen: true });
    this.fetchWalletBalance();
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

  // ─── Wallet handlers ─────────────────────────────────────

  fetchWalletBalance() {
    var self = this;
    self.setState({ walletLoading: true });

    fetch('/api/v1/wallet_topup/balance', {
      method: 'GET',
      headers: jsonHeaders(),
    })
      .then(function (response) {
        if (!response.ok) return null;
        return response.json();
      })
      .then(function (data) {
        if (data) {
          self.setState({ walletBalance: data.balance_cents || 0, walletLoading: false });
        } else {
          self.setState({ walletLoading: false });
        }
      })
      .catch(function () {
        self.setState({ walletLoading: false });
      });
  }

  handleOpenTopup() {
    // トップアップ機能は準備中（Stripe.js 統合前）
    // モーダルの代わりに準備中メッセージを表示
    this.setState(function (prev) {
      return {
        messages: prev.messages.concat([{
          id: 'sys-topup-' + Date.now(),
          role: 'system',
          content: t('wallet_add_preparing_body'),
          isStreaming: false,
          created_at: new Date().toISOString(),
        }]),
      };
    });
  }

  handleCloseTopup() {
    this.setState({ showTopupModal: false });
  }

  handleTopupSuccess(newBalance) {
    this.setState({ walletBalance: newBalance });
  }

  handlePurchase() {
    // ペルソナ購入ページへ遷移（現在は準備中メッセージを表示）
    this.setState(function (prev) {
      return {
        messages: prev.messages.concat([{
          id: 'sys-purchase-' + Date.now(),
          role: 'system',
          content: t('purchase_preparing_body'),
          isStreaming: false,
          created_at: new Date().toISOString(),
        }]),
      };
    });
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

    // §13 Result/Artifact preview — latest completed assistant answer
    var latestResult = null;
    for (var i = state.messages.length - 1; i >= 0; i--) {
      var m = state.messages[i];
      if (m.role === 'assistant' && !m.isStreaming && m.content) {
        latestResult = m;
        break;
      }
    }

    // ── Trigger button ────────────────────────────────
    if (!state.isOpen) {
      return React.createElement('button', {
        onClick: this.handleOpen,
        className: 'chatPanel__trigger',
        'aria-label': t('a11y_open'),
        type: 'button',
        style: {
          position: 'fixed', bottom: '24px', right: '24px',
          width: '56px', height: '56px', borderRadius: '50%',
          background: 'var(--chat-brand-gold)', color: '#070707', border: 'none',
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
        'aria-label': t('a11y_dialog'),
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
            React.createElement('h4', { className: 'chatPanel__historyTitle' }, t('history_title')),
            React.createElement('button', {
              className: 'chatPanel__newChatBtn',
              onClick: this.handleNewChat,
              type: 'button',
            }, t('history_new'))
          ),
          React.createElement('div', { className: 'chatPanel__historyList' },
            today.length > 0 && React.createElement('div', { className: 'chatPanel__historyGroup' },
              React.createElement('div', { className: 'chatPanel__historyGroupLabel' }, t('history_today')),
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
              React.createElement('div', { className: 'chatPanel__historyGroupLabel' }, t('history_past_week')),
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
              React.createElement('div', { className: 'chatPanel__historyGroupLabel' }, t('history_earlier')),
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
            }, t('history_empty'))
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
              'aria-label': t('a11y_close'),
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
          state.isLoading && React.createElement('div', { className: 'chatPanel__loading' }, t('loading')),

          // Messages
          React.createElement('div', { className: 'chatPanel__messages' },
            state.messages.length === 0 && !state.isLoading
              ? React.createElement('div', { className: 'chatPanel__emptyState' },
                  React.createElement('div', { className: 'chatPanel__emptyStateIcon' }, '🤖'),
                  tFormat('empty_state', { name: personaName || '' })
                )
              : state.messages.map(function (msg) {
                  return React.createElement(MessageBubble, {
                    key: msg.id, role: msg.role, content: msg.content,
                    isStreaming: msg.isStreaming,
                    is_result: msg.is_result,
                    total_tokens: msg.total_tokens,
                    created_at: msg.created_at,
                    showTopupButton: msg.showTopupButton,
                    onTopupClick: msg.showTopupButton ? self.handleOpenTopup : null,
                    showPurchaseButton: msg.showPurchaseButton,
                    onPurchaseClick: msg.showPurchaseButton ? self.handlePurchase : null,
                    attachment: msg.attachment,
                  });
                }),
            React.createElement('div', { ref: function (el) { self.messagesEndRef = el; } })
          ),

          // Attachment preview chip
          state.pendingAttachment && state.pendingAttachment.status !== 'uploading'
            ? React.createElement('div', { className: 'chatPanel__attachPreview' },
                state.pendingAttachment.url && React.createElement('img', {
                  src: state.pendingAttachment.url, alt: '',
                }),
                React.createElement('span', { className: 'chatPanel__attachName' }, state.pendingAttachment.name || ''),
                React.createElement('button', {
                  className: 'chatPanel__attachRemove',
                  onClick: this.handleRemoveAttachment,
                  'aria-label': t('attach_remove'),
                  type: 'button',
                }, '✕')
              )
            : null,

          // Input
          React.createElement('div', { className: 'chatPanel__inputArea' },
            React.createElement('input', {
              type: 'file',
              accept: 'image/jpeg,image/png,image/gif,image/webp',
              ref: function (el) { self.fileInputRef = el; },
              className: 'chatPanel__attachInput',
              onChange: this.handleFileSelected,
              'aria-label': t('attach_button'),
            }),
            React.createElement('button', {
              className: 'chatPanel__attachBtn',
              onClick: this.handleAttachClick,
              disabled: state.isLoading || (state.pendingAttachment && state.pendingAttachment.status === 'uploading'),
              'aria-label': t('attach_button'),
              type: 'button',
            }, '📎'),
            React.createElement('textarea', {
              className: 'chatPanel__input',
              value: state.inputText,
              onChange: this.handleInputChange,
              onKeyDown: this.handleKeyDown,
              placeholder: t('input_placeholder'),
              rows: 1,
              disabled: state.isLoading,
              'aria-label': t('a11y_input'),
            }),
            React.createElement('button', {
              className: 'chatPanel__sendBtn',
              onClick: this.handleSend,
              disabled: state.isLoading || (!state.inputText.trim() && !(state.pendingAttachment && state.pendingAttachment.status === 'ready')) || (state.pendingAttachment && state.pendingAttachment.status === 'uploading'),
              'aria-label': t('a11y_send'),
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
          React.createElement('div', { className: 'chatPanel__disclaimer' }, t('disclaimer'))
        ),

        // ═══ RIGHT: Settings panel ═══
        React.createElement('div', { className: 'chatPanel__settings', style: { width: '220px', background: '#1e1e1e', borderLeft: '1px solid #333', display: 'flex', flexDirection: 'column', flexShrink: 0, padding: '16px', overflowY: 'auto' } },
          // ── Result / Artifact preview (DESIGN.md §13) ──────
          latestResult && React.createElement('div', { className: 'chatPanel__resultPanel' },
            React.createElement('div', { className: 'chatPanel__resultBadgeRow' },
              React.createElement('span', { className: 'chatPanel__resultBadge' }, t('result_badge')),
              React.createElement('span', { className: 'chatPanel__resultTitle' }, t('result_title'))
            ),
            React.createElement('div', { className: 'chatPanel__resultHeading' }, t('result_panel_heading')),
            React.createElement('div', {
              className: 'chatPanel__resultBody chatMessage__markdown',
              dangerouslySetInnerHTML: { __html: renderMarkdown(latestResult.content || '') },
            }),
            latestResult.total_tokens > 0 && React.createElement('div', { className: 'chatPanel__resultMeta' },
              tFormat('message_tokens', { count: latestResult.total_tokens })),
            React.createElement('button', {
              className: 'chatPanel__resultJump',
              onClick: function () {
                if (self.messagesEndRef && self.messagesEndRef.scrollIntoView) {
                  self.messagesEndRef.scrollIntoView({ behavior: 'smooth' });
                }
              },
              type: 'button',
            }, t('result_panel_jump'))
          ),

          // ── Wallet balance ──────────────────────────────
          React.createElement('div', {
            className: 'wallet-balance' + (state.walletLoading ? ' wallet-balance--loading' : ''),
          },
            React.createElement('div', { className: 'wallet-balance__info' },
              React.createElement('span', { className: 'wallet-balance__label' }, t('balance_label')),
              state.walletLoading
                ? React.createElement('div', { className: 'wallet-balance__skeleton' })
                : React.createElement('span', { className: 'wallet-balance__amount' },
                    '¥', state.walletBalance.toLocaleString(),
                    React.createElement('span', { className: 'wallet-balance__currency' }, ' ')
                  )
            ),
            React.createElement('button', {
              className: 'wallet-balance__topupBtn',
              onClick: this.handleOpenTopup,
              type: 'button',
            }, t('wallet_add_preparing'))
          ),

          React.createElement('h4', { className: 'chatPanel__settingsTitle' }, t('settings_title')),

          // Model selection
          React.createElement('div', { className: 'chatPanel__settingsGroup' },
            React.createElement('label', { className: 'chatPanel__settingsLabel' }, t('settings_model')),
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
            React.createElement('label', { className: 'chatPanel__settingsLabel' }, t('settings_token_limit')),
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
              tFormat('settings_tokens_unit', { count: state.tokenLimit.toLocaleString() })
            )
          ),

          // Output length
          React.createElement('div', { className: 'chatPanel__settingsGroup' },
            React.createElement('label', { className: 'chatPanel__settingsLabel' }, t('settings_output_length')),
            React.createElement('div', { className: 'chatPanel__toneButtons' },
              ['short', 'standard', 'long'].map(function (length) {
                var labels = { short: t('output_short'), standard: t('output_standard'), long: t('output_long') };
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
            React.createElement('label', { className: 'chatPanel__settingsLabel' }, t('settings_tone')),
            React.createElement('select', {
              className: 'chatPanel__settingsSelect',
              value: state.tone,
              onChange: function (e) { self.handleToneChange(e.target.value); },
            },
              React.createElement('option', { value: 'polite' }, t('tone_polite')),
              React.createElement('option', { value: 'casual' }, t('tone_casual')),
              React.createElement('option', { value: 'professional' }, t('tone_professional')),
              React.createElement('option', { value: 'friendly' }, t('tone_friendly'))
            )
          )
        )
      ),

      // ── Wallet Top-up Modal ────────────────────────
      state.showTopupModal && React.createElement(WalletTopupModal, {
        balance: state.walletBalance,
        onSuccess: this.handleTopupSuccess,
        onClose: this.handleCloseTopup,
      })
    );
  }
}

export default ChatPanelApp;
