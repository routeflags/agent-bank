import React from 'react';
import '../components/ChatPanel/chatPanel.css';
import WalletTopupModal from '../components/WalletTopup/WalletTopupModal';
import { csrfToken, jsonHeaders, fetchTopupStatus as fetchTopupStatusFromServer } from '../components/WalletTopup/walletTopupApi';
import { saveActiveElement, restoreFocus, focusInitial, trapTabKey } from '../utils/modalDialog';

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

// ─── HTML sanitization ────────────────────────────────────
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
  wallet_redirecting: '決済ページへ移動しています…',
  wallet_add_credits: 'クレジットを追加する',
  wallet_add_preparing: '追加する（準備中）',
  wallet_add_preparing_body: 'ウォレットへの追加機能は現在準備中です。正式リリースまでお待ちください。',
  wallet_topup_unavailable_reason: '決済が未設定のため、現在チャージできません。',
  topup_fixed_title: '固定額チャージ',
  topup_select_plan: '金額を選択',
  topup_fx_note: '円表示は目安です。レート変動で表示額が変わります。実際の請求はUSD建てで決済画面に表示されます。',
  topup_usd_estimate: '約 $%{usd}（USD請求）',
  topup_credit_label: 'チャージ額: ¥%{jpy}',
  topup_invalid_plan: '指定されたプランは利用できません。金額を選択し直してください。',
  new_chat_title: '新しいチャット',
  insufficient_tokens: 'トークンが不足しています。',
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
  a11y_send: 'メッセージを送信',
  a11y_connected: '接続済み',
  a11y_disconnected: '未接続',
  truncated_notice: '回答がトークン上限に達したため、途中で切れています。続きが必要な場合は「続きを生成」を押してください。',
  truncated_continue: '続きを生成',
  truncated_continue_prompt: '続きを生成してください。前回の回答の続きからお願いします。',
  copy: 'コピー',
  copied: 'コピー済み'
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
// ─── Wallet Top-up Modal (Issue #58: 共通化) ───────────────
// WalletTopupModal / TOPUP_AMOUNTS / formatJpy / formatUsd は
// client/app/components/WalletTopup/ に移動。ChatPanel とマイページで共用。

// ─── Message Bubble ──────────────────────────────────────

// アシスタント回答のコピーボタン（Issue #66）。
// React 16.1.1 はフック非対応のためクラスコンポーネントで実装する。
class CopyButton extends React.Component {
  constructor(props) {
    super(props);
    this.state = { copied: false };
    this.mounted = false;
    this.resetTimer = null;
    this.handleClick = this.handleClick.bind(this);
  }

  componentDidMount() {
    this.mounted = true;
  }

  componentWillUnmount() {
    this.mounted = false;
    if (this.resetTimer) {
      clearTimeout(this.resetTimer);
      this.resetTimer = null;
    }
  }

  legacyCopy(text) {
    var ta = document.createElement('textarea');
    ta.value = text;
    ta.setAttribute('readonly', '');
    ta.style.position = 'fixed';
    ta.style.top = '-1000px';
    document.body.appendChild(ta);
    ta.select();
    document.execCommand('copy');
    document.body.removeChild(ta);
  }

  handleClick() {
    var self = this;
    var text = this.props.text || '';
    var done = function() {
      if (!self.mounted) return;
      self.setState({ copied: true });
      if (self.resetTimer) clearTimeout(self.resetTimer);
      self.resetTimer = setTimeout(function() {
        if (self.mounted) self.setState({ copied: false });
      }, 1500);
    };
    // クリップボード API は secure context のみ。使えない環境では
    // textarea + execCommand にフォールバックする。
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done, function() {
          try { self.legacyCopy(text); done(); } catch (e) {
            console.warn('[ChatPanel] copy failed', e);
          }
        });
      } else {
        this.legacyCopy(text);
        done();
      }
    } catch (e) {
      console.warn('[ChatPanel] copy failed', e);
    }
  }

  render() {
    var label = this.state.copied ? t('copied') : t('copy');
    return React.createElement('button', {
      type: 'button',
      className: 'chatMessage__copyBtn' + (this.state.copied ? ' is-copied' : ''),
      onClick: this.handleClick,
      title: label,
      'aria-label': label,
    }, this.state.copied ? '✓ ' + label : label);
  }
}

function MessageBubble(props) {
  var role = props.role;
  var content = props.content;
  var isStreaming = props.isStreaming;
  var totalTokens = props.total_tokens;
  var createdAt = props.created_at;
  var showTopupButton = props.showTopupButton;
  var onTopupClick = props.onTopupClick;
  var attachment = props.attachment;
  // 会話へ移動（Issue #64）のスクロール先特定用。key は props 経由で
  // 取得できないため、メッセージ ID を data-message-id として描画する。
  var messageId = props.message_id;
  // 特別な成果表示（DESIGN.md §13）は明示フラグが付いた回答にのみ適用する
  var isResult = props.is_result === true;
  // トークン上限による打ち切り（Issue #63）。正常完結時は表示しない。
  var truncated = props.truncated === true;
  var onContinueClick = props.onContinueClick;

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

  return React.createElement('div', {
    className: 'chatMessage chatMessage--' + (role || 'user') + (isAssistant && !isStreaming && displayContent && isResult ? ' chatMessage--assistant-done' : ''),
    'data-message-id': messageId,
  },
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
    // 打ち切り明示（Issue #63）: length 打ち切り時のみ注意書き＋継続導線を出す。
    // 正常完結（stop）時は何も出さない。
    isAssistant && !isStreaming && truncated && React.createElement('div', { className: 'chatMessage__truncated' },
      React.createElement('div', { className: 'chatMessage__truncatedNotice' }, t('truncated_notice')),
      onContinueClick && React.createElement('button', {
        className: 'chatMessage__continueBtn',
        onClick: onContinueClick,
        type: 'button',
      }, t('truncated_continue'))
    ),
    // Inline导线: 残高不足時はチャージ導線のみを出す（Issue #51。購入導線は持たない）。
    showTopupButton && onTopupClick && React.createElement('div', { className: 'wallet-topup-prompt' },
      React.createElement('button', {
        className: 'wallet-topup-prompt__btn',
        onClick: onTopupClick,
        type: 'button',
      }, t('wallet_add_credits'))
    ),
    role === 'assistant' && totalTokens > 0 && (
      React.createElement('span', { className: 'chatMessage__tokens' }, tFormat('message_tokens', { count: totalTokens }))
    ),
    // コピーボタン（Issue #66）: 完了したアシスタント回答のプレーンテキストを
    // コピーする（Markdown 変換前の本文）。
    isAssistant && !isStreaming && displayContent && (
      React.createElement(CopyButton, { text: content })
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
      renamingId: null,
      renameValue: '',
      // Wallet
      walletBalance: 0,
      walletLoading: false,
      showTopupModal: false,
      // Top-up availability (Issue #34): fetched from GET /api/v1/wallet_topup/status.
      // Defaults to enabled so the button never flashes "preparing" when
      // the status request fails; the server remains the source of truth.
      topupEnabled: true,
      topupDevMode: false,
      topupDenominations: [],
      // Attachment (composer 📎)
      pendingAttachment: null,
    };

    this.streamingId = null;
    this.sending = false;
    this.subscription = null;
    // 接続確立前に送信されたメッセージの待機列（#32 再発防止）。
    // connected 確認後に順次 perform し、取りこぼしを無くす。
    this.pendingMessages = [];
    this.abortController = null;
    this.messagesEndRef = null;
    // アンマウント後の setState を避けるためのフラグ。
    // 購読解除は componentWillUnmount からも呼ばれるため必要。
    this.mounted = false;

    this.handleOpen = this.handleOpen.bind(this);
    this.handleClose = this.handleClose.bind(this);
    this.handleInputChange = this.handleInputChange.bind(this);
    this.handleSend = this.handleSend.bind(this);
    this.handleKeyDown = this.handleKeyDown.bind(this);
    this.handleNewChat = this.handleNewChat.bind(this);
    this.handleSelectSession = this.handleSelectSession.bind(this);
    this.handleRenameSession = this.handleRenameSession.bind(this);
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
    this.handleContinue = this.handleContinue.bind(this);
    this.handleJumpToResult = this.handleJumpToResult.bind(this);
    this.handleDialogKeyDown = this.handleDialogKeyDown.bind(this);
    // モーダルのフォーカス管理（Issue #78）。開く直前の要素を覚え、
    // ダイアログ内で Tab を循環・Esc で閉じる・閉じたら元へ戻す。
    this.dialogRef = null;
    this.inputRef = null;
    this.previouslyFocused = null;
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
              title: session.title || t('new_chat_title'),
              timestamp: session.created_at || new Date().toISOString(),
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
          var meta = m.metadata || {};
          return {
            id: m.id,
            role: m.role,
            content: m.content,
            isStreaming: false,
            is_result: m.is_result === true,
            // 打ち切り記録（Issue #63）: API の算出値を優先し、metadata を後方互換で読む。
            truncated: m.truncated === true || meta.truncated === true,
            finish_reason: m.finish_reason || meta.finish_reason || null,
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
    // 古い購読が残っていると this.subscription が上書きされ、
    // 送信と購読のペアがずれる（#32）。先に明示的に解除する。
    // ただし購読確立前に送信された同一セッション宛の待機分は引き継ぐ。
    var carried = this.pendingMessages.filter(function (payload) {
      return payload.chat_session_id === sessionId;
    });
    this.unsubscribeFromChannel();
    this.pendingMessages = carried;
    var consumer = getConsumer();
    if (!consumer) {
      console.warn('[ActionCable] consumer not available');
      return;
    }

    var subscription = consumer.subscriptions.create(
      { channel: 'PersonaChatChannel', chat_session_id: sessionId },
      {
        connected: function () {
          self.setState({ isConnected: true });
          self.flushPendingMessages();
        },
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
      try {
        this.subscription.unsubscribe();
      } catch (e) {
        console.warn('[ActionCable] unsubscribe failed', e);
      }
      this.subscription = null;
    }
    // アンマウント後は setState しない（React 16 の警告を避ける）。
    if (this.mounted) this.setState({ isConnected: false });
    // セッション切替時の取り違えを防ぐため、旧セッション向け待機列は破棄する。
    this.pendingMessages = [];
  }

  // 接続確立前の送信は破棄せず待機列に入れ、connected 時に flush する。
  // perform が false（WebSocket 未接続）を返した場合も同様に待機させる。
  queuePendingMessage(payload) {
    this.pendingMessages.push(payload);
  }

  flushPendingMessages() {
    if (!this.subscription || this.pendingMessages.length === 0) return;
    var queued = this.pendingMessages;
    this.pendingMessages = [];
    for (var i = 0; i < queued.length; i++) {
      var sent = false;
      try {
        sent = this.subscription.perform('receive', queued[i]);
      } catch (e) {
        console.warn('[ActionCable] perform failed, re-queueing', e);
      }
      if (sent === false) {
        // 接続がまだ開いていない — 先頭に戻して次回 connected 時に再送する。
        this.pendingMessages = queued.slice(i);
        console.warn('[ActionCable] connection not ready, message queued');
        return;
      }
    }
  }

  // 戻り値: 送信した（または待機列に入れた）payload。セッション ID 未確定時は false。
  sendMessage(content, attachment, sessionIdOverride) {
    // setState は非同期のため、作成直後の送信では引数の ID を優先する（#32）。
    var sessionId = sessionIdOverride || this.state.sessionId;
    if (!sessionId) {
      console.warn('[ActionCable] no session id, message not sent');
      return false;
    }
    var payload = {
      chat_session_id: sessionId,
      content: content,
      settings: {
        token_limit: this.state.tokenLimit,
        output_length: this.state.outputLength,
        tone: this.state.tone
      }
    };
    if (attachment && attachment.id) payload.attachment_id = attachment.id;
    if (!this.subscription) {
      // 購読確立前の送信も破棄せず待機列へ（connected 時に flush される）。
      this.queuePendingMessage(payload);
      console.warn('[ActionCable] no subscription, message queued');
      return payload;
    }
    var result = false;
    try {
      result = this.subscription.perform('receive', payload);
    } catch (e) {
      console.warn('[ActionCable] perform threw', e);
      result = false;
    }
    if (result === false) {
      // WebSocket 未接続時は破棄せず待機列へ（connected 時に flush）。
      this.queuePendingMessage(payload);
      console.warn('[ActionCable] perform deferred until connected');
    }
    return payload;
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
    // Issue #82: 課金後の残高が数値で届いたら表示を更新（追加リクエストなし）。
    // null/欠落時は何もしない（後方互換）。
    if (data && typeof data.current_balance === 'number') {
      this.setState({ walletBalance: data.current_balance });
    }
    if (this.streamingId) {
      // サーバーは messageId（camelCase）で送る。旧形式 message_id も受ける（#32）。
      var finalId = data.message_id || data.messageId || this.streamingId;
      this.finalizeMessage(this.streamingId, finalId, {
        isResult: data.is_result === true,
        truncated: data.truncated === true,
        finishReason: data.finish_reason || null,
      });
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
      // 課金は残高一本（Issue #51）。残高不足時はチャージ導線のみを出す。
      this.setState(function (prev) {
        return {
          messages: prev.messages.concat([{
            id: 'sys-err-' + Date.now(),
            role: 'system',
            content: t('wallet_insufficient'),
            isStreaming: false,
            created_at: new Date().toISOString(),
            showTopupButton: true,
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

  finalizeMessage(tempId, finalId, flags) {
    var isResult = flags && flags.isResult === true;
    var truncated = flags && flags.truncated === true;
    var finishReason = flags && flags.finishReason ? flags.finishReason : null;
    this.setState(function (prev) {
      return {
        messages: prev.messages.map(function (m) {
          if (m.id === tempId) {
            return Object.assign({}, m, {
              id: finalId,
              isStreaming: false,
              is_result: isResult,
              truncated: truncated,
              finish_reason: finishReason,
            });
          }
          return m;
        }),
      };
    });
  }

  // 打ち切り時の継続導線（Issue #63）: 前回回答の続きを同じセッションで要求する。
  handleContinue() {
    if (!this.state.sessionId || this.sending) return;
    var text = t('truncated_continue_prompt');
    this.sending = true;
    this.addMessage('user-' + Date.now(), 'user', text, false);
    this.sendMessage(text, null, this.state.sessionId);
    this.sending = false;
  }

  // 成果プレビュー「会話へ移動」（Issue #64）: 該当の assistant 回答までスクロールする。
  // 要素が見つからない場合は何もしない（例外を出さない）。
  handleJumpToResult(result) {
    if (!result || result.id === undefined || result.id === null) return;
    var el = null;
    try {
      el = document.querySelector('[data-message-id="' + result.id + '"]');
    } catch (e) {
      return;
    }
    if (!el || !el.scrollIntoView) return;
    el.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }

  // ─── User interaction ─────────────────────────────────

  handleInputChange(e) {
    this.setState({ inputText: e.target.value });
  }

  handleKeyDown(e) {
    // IME変換確定のEnterでは送信しない（isComposing / keyCode 229）
    if (e.nativeEvent.isComposing || e.keyCode === 229) return;
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
      this.sendMessage(text, attachment, this.state.sessionId);
      this.sending = false;
    } else {
      this.createSession().then(function (result) {
        if (result && result.id) {
          // setState の反映待ちによる取り違えを避けるため、作成結果の ID を直接渡す（#32）。
          self.sendMessage(text, attachment, result.id);
        } else {
          // 課金は残高一本（Issue #51）。残高不足時はチャージ導線のみを出す。
          var errorType = result ? result.error_type : null;
          if (errorType === 'insufficient_balance') {
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
    var self = this;
    this.disconnect();
    // Wait for the old session to close before creating a new one —
    // otherwise the backend may still see the old session as active.
    this.closeSession().then(function () {
      self.createSession();
    });
  }

  // Loads the session list from the backend for this listing so the
  // history sidebar survives page reloads (not just client-side state).
  fetchSessionHistory() {
    var self = this;
    return fetch('/api/v1/chat_sessions?listing_id=' + this.props.listing_id, {
      headers: jsonHeaders(),
    })
      .then(function (r) { return r.ok ? r.json() : { chat_sessions: [] }; })
      .then(function (data) {
        var sessions = (data.chat_sessions || []).map(function (s) {
          return { id: s.id, title: s.title || t('new_chat_title'), timestamp: s.updated_at };
        });
        self.setState({ sessionHistory: sessions });
      })
      .catch(function () {});
  }

  // Switches to a previously-created session and loads its messages.
  handleSelectSession(sessionId) {
    var self = this;
    if (sessionId === this.state.sessionId) return;
    this.disconnect();
    this.setState({ isLoading: true, messages: [], sessionId: sessionId, error: null });
    this.subscribeToChannel(sessionId);
    this.loadSessionMessages(sessionId).then(function () {
      self.setState({ isLoading: false });
    });
  }

  // Renames a session. Called with the new title (or null to keep current).
  handleRenameSession(sessionId, title) {
    var self = this;
    var trimmed = (title || '').trim();
    this.setState({ renamingId: null, renameValue: '' });
    if (!trimmed) return;

    fetch('/api/v1/chat_sessions/' + sessionId, {
      method: 'PATCH',
      headers: jsonHeaders(),
      body: JSON.stringify({ title: trimmed }),
    })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (data) {
        if (!data || !data.chat_session) return;
        var updated = data.chat_session;
        self.setState(function (prev) {
          return {
            sessionHistory: prev.sessionHistory.map(function (item) {
              return item.id === updated.id
                ? { id: updated.id, title: updated.title || item.title, timestamp: updated.updated_at }
                : item;
            }),
          };
        });
      })
      .catch(function () {});
  }

  handleOpen() {
    this.previouslyFocused = saveActiveElement();
    this.setState({ isOpen: true });
    this.fetchWalletBalance();
    this.fetchTopupStatus();
    this.fetchSessionHistory();
    if (!this.state.sessionId) {
      this.createSession();
    }
  }

  handleClose() {
    this.disconnect();
    this.closeSession();
    this.setState({ isOpen: false });
    restoreFocus(this.previouslyFocused);
    this.previouslyFocused = null;
  }

  // ダイアログ内のキーボード操作（Issue #78）: Esc で閉じる、Tab は循環。
  handleDialogKeyDown(e) {
    if (!this.state.isOpen) return;
    if (e.key === 'Escape') {
      e.stopPropagation();
      this.handleClose();
      return;
    }
    if (e.key === 'Tab') {
      trapTabKey(e, this.dialogRef);
    }
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
    this.fetchWalletBalance();
    this.setState({ showTopupModal: true });
  }

  // Top-up availability (Issue #34, #46): keeps the settings button label in
  // sync with the server payment configuration. Called when the panel opens.
  // Fixed prepaid denominations (plan_id / USD / JPY) are stored for the modal.
  // Shared helper (Issue #58) — same status object as MypageWalletApp.
  fetchTopupStatus() {
    var self = this;

    fetchTopupStatusFromServer().then(function (status) {
      if (status) {
        self.setState({
          topupEnabled: status.topupEnabled,
          topupDevMode: status.devMode,
          topupDenominations: status.denominations,
        });
      }
      // null: keep the optimistic default (enabled); the server validates on submit.
    });
  }

  handleCloseTopup() {
    this.setState({ showTopupModal: false });
  }

  handleTopupSuccess(newBalance) {
    this.setState({ walletBalance: newBalance });
  }

  // ─── Lifecycle ────────────────────────────────────────

  componentDidUpdate(prevProps, prevState) {
    if (prevState.messages !== this.state.messages && this.messagesEndRef) {
      this.messagesEndRef.scrollIntoView({ behavior: 'smooth' });
    }
    // 開いた直後に入力欄へフォーカスを移す（Issue #78）。
    if (!prevState.isOpen && this.state.isOpen) {
      focusInitial(this.dialogRef, this.inputRef);
    }
  }

  componentDidMount() {
    this.mounted = true;
    // Expose a global hook so server-rendered CTAs (e.g. the
    // "このスキルを利用する" button) can open this chat panel.
    var self = this;
    window.LampreyChat = {
      open: function () { self.handleOpen(); }
    };
  }

  componentWillUnmount() {
    this.mounted = false;
    this.disconnect();
    if (window.LampreyChat) delete window.LampreyChat;
  }

  // ─── Render ───────────────────────────────────────────

  renderHistoryItem(item) {
    var self = this;
    var state = this.state;
    var isRenaming = state.renamingId === item.id;

    if (isRenaming) {
      return React.createElement('div', {
        key: item.id,
        className: 'chatPanel__historyItem is-active',
      },
        React.createElement('input', {
          className: 'chatPanel__renameInput',
          value: state.renameValue,
          autoFocus: true,
          onChange: function (e) { self.setState({ renameValue: e.target.value }); },
          onBlur: function () { self.handleRenameSession(item.id, state.renameValue); },
          onKeyDown: function (e) {
            if (e.key === 'Enter') {
              e.preventDefault();
              self.handleRenameSession(item.id, state.renameValue);
            } else if (e.key === 'Escape') {
              self.setState({ renamingId: null, renameValue: '' });
            }
          },
        })
      );
    }

    return React.createElement('div', {
      key: item.id,
      className: 'chatPanel__historyItem' + (item.id === state.sessionId ? ' is-active' : ''),
      role: 'button',
      tabIndex: 0,
      'aria-label': item.title,
      // ダブルクリックのリネームは既存の ✎ ボタンに一本化し、行自体は
      // クリック / Enter / Space の選択操作にする（Issue #78）。
      onClick: function () { self.handleSelectSession(item.id); },
      onKeyDown: function (e) {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          self.handleSelectSession(item.id);
        }
      },
      title: item.title,
    },
      React.createElement('span', { className: 'chatPanel__historyItemIcon' }, '💬'),
      React.createElement('span', { className: 'chatPanel__historyItemText' }, item.title),
      React.createElement('button', {
        className: 'chatPanel__historyRenameBtn',
        type: 'button',
        title: '名前を変更',
        onClick: function (e) {
          e.stopPropagation();
          self.setState({ renamingId: item.id, renameValue: item.title });
        },
      }, '✎')
    );
  }

  render() {
    var state = this.state;
    var self = this;
    var personaName = this.props.persona_name || 'AI Assistant';

    // §13 Result/Artifact preview — latest completed assistant answer with is_result === true (Issue #65)
    var latestResult = null;
    for (var i = state.messages.length - 1; i >= 0; i--) {
      var m = state.messages[i];
      if (m.role === 'assistant' && !m.isStreaming && m.content && m.is_result === true) {
        latestResult = m;
        break;
      }
    }

    // ── Closed state ──────────────────────────────────
    // チャットの入口は「このスキルを利用する」CTA（window.LampreyChat.open）に一本化する。
    // フローティング 💬 アイコンは誤解・重複のため描画しない（Issue #31）。
    if (!state.isOpen) {
      return null;
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
        onKeyDown: this.handleDialogKeyDown,
        ref: function (el) { self.dialogRef = el; },
        role: 'dialog',
        'aria-modal': 'true',
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
              today.map(function (item) { return self.renderHistoryItem(item); })
            ),
            thisWeek.length > 0 && React.createElement('div', { className: 'chatPanel__historyGroup' },
              React.createElement('div', { className: 'chatPanel__historyGroupLabel' }, t('history_past_week')),
              thisWeek.map(function (item) { return self.renderHistoryItem(item); })
            ),
            older.length > 0 && React.createElement('div', { className: 'chatPanel__historyGroup' },
              React.createElement('div', { className: 'chatPanel__historyGroupLabel' }, t('history_earlier')),
              older.map(function (item) { return self.renderHistoryItem(item); })
            ),
            state.sessionHistory.length === 0 && React.createElement('div', {
              style: { color: 'var(--text-secondary, #999)', fontSize: '13px', textAlign: 'center', padding: '24px 12px' }
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
                className: 'chatPanel__connectionDot' + (state.isConnected ? '' : ' chatPanel__connectionDot--disconnected'),
                role: 'img',
                'aria-label': state.isConnected ? t('a11y_connected') : t('a11y_disconnected'),
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
          state.error && React.createElement('div', { className: 'chatPanel__error', role: 'alert' }, state.error),

          // Loading
          state.isLoading && React.createElement('div', { className: 'chatPanel__loading' }, t('loading')),

          // Messages
          React.createElement('div', {
            className: 'chatPanel__messages',
            'aria-live': 'polite',
            'aria-relevant': 'additions text',
          },
            state.messages.length === 0 && !state.isLoading
              ? React.createElement('div', { className: 'chatPanel__emptyState' },
                  React.createElement('div', { className: 'chatPanel__emptyStateIcon' }, '🤖'),
                  tFormat('empty_state', { name: personaName || '' })
                )
              : state.messages.map(function (msg) {
                  return React.createElement(MessageBubble, {
                    key: msg.id, message_id: msg.id, role: msg.role, content: msg.content,
                    isStreaming: msg.isStreaming,
                    is_result: msg.is_result,
                    truncated: msg.truncated,
                    onContinueClick: msg.truncated ? self.handleContinue : null,
                    total_tokens: msg.total_tokens,
                    created_at: msg.created_at,
                    showTopupButton: msg.showTopupButton,
                    onTopupClick: msg.showTopupButton ? self.handleOpenTopup : null,
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
              ref: function (el) { self.inputRef = el; },
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
              onClick: function () { self.handleJumpToResult(latestResult); },
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
              disabled: !state.topupEnabled,
              title: state.topupEnabled ? null : t('wallet_topup_unavailable_reason'),
            }, state.topupEnabled ? t('wallet_submit') : t('wallet_add_preparing'))
          ),

          // Top-up unavailable reason (Issue #34): visible only when the
          // server reports that no payment method is configured.
          !state.topupEnabled && React.createElement('div', {
            className: 'wallet-topup-unavailable',
          }, t('wallet_topup_unavailable_reason')),

          React.createElement('h4', { className: 'chatPanel__settingsTitle' }, t('settings_title')),

          // Model selection
          React.createElement('div', { className: 'chatPanel__settingsGroup' },
            React.createElement('label', { className: 'chatPanel__settingsLabel', htmlFor: 'chatPanel-modelSelect' }, t('settings_model')),
            React.createElement('select', {
              className: 'chatPanel__settingsSelect',
              id: 'chatPanel-modelSelect',
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
            React.createElement('label', { className: 'chatPanel__settingsLabel', htmlFor: 'chatPanel-tokenLimit' }, t('settings_token_limit')),
            React.createElement('input', {
              type: 'range',
              className: 'chatPanel__settingsSlider',
              id: 'chatPanel-tokenLimit',
              min: '1000',
              max: '8000',
              step: '500',
              value: state.tokenLimit,
              onChange: this.handleTokenChange,
              'aria-valuetext': tFormat('settings_tokens_unit', { count: state.tokenLimit.toLocaleString() }),
            }),
            React.createElement('div', { className: 'chatPanel__settingsValue' },
              tFormat('settings_tokens_unit', { count: state.tokenLimit.toLocaleString() })
            )
          ),

          // Output length
          React.createElement('div', { className: 'chatPanel__settingsGroup' },
            React.createElement('span', { className: 'chatPanel__settingsLabel', id: 'chatPanel-outputLengthLabel' }, t('settings_output_length')),
            React.createElement('div', { className: 'chatPanel__toneButtons', role: 'group', 'aria-labelledby': 'chatPanel-outputLengthLabel' },
              ['short', 'standard', 'long'].map(function (length) {
                var labels = { short: t('output_short'), standard: t('output_standard'), long: t('output_long') };
                return React.createElement('button', {
                  key: length,
                  className: 'chatPanel__toneBtn' + (state.outputLength === length ? ' is-active' : ''),
                  'aria-pressed': state.outputLength === length,
                  onClick: function () { self.handleOutputLength(length); },
                  type: 'button',
                }, labels[length]);
              })
            )
          ),

          // Tone
          React.createElement('div', { className: 'chatPanel__settingsGroup' },
            React.createElement('label', { className: 'chatPanel__settingsLabel', htmlFor: 'chatPanel-toneSelect' }, t('settings_tone')),
            React.createElement('select', {
              className: 'chatPanel__settingsSelect',
              id: 'chatPanel-toneSelect',
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

      // ── Wallet Top-up Modal (Issue #46 fixed prepaid; Issue #58 共通化) ──
      state.showTopupModal && React.createElement(WalletTopupModal, {
        i18n: this.props.i18n,
        balance: state.walletBalance,
        denominations: state.topupDenominations,
        devMode: state.topupDevMode,
        onSuccess: this.handleTopupSuccess,
        onClose: this.handleCloseTopup,
      })
    );
  }
}

export default ChatPanelApp;
