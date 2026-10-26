/* eslint-env browser */
import React from 'react';
import { jsonHeaders } from './walletTopupApi';
import { saveActiveElement, restoreFocus, focusInitial, trapTabKey } from '../../utils/modalDialog';
import './wallet-topup.css';

// Shared wallet top-up modal (Issue #58).
//
// ChatPanelApp から切り出した共通クラスコンポーネント（React 16.1 のため
// クラスコンポーネント）。ChatPanel とマイページの両方から使う。
// 文言は props.i18n（lamprey.chat.*）で受け取り、不足分は下記の日本語
// デフォルトで補う。
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
  wallet_topup_unavailable_reason: '決済が未設定のため、現在チャージできません。',
  topup_fixed_title: '固定額チャージ',
  topup_select_plan: '金額を選択',
  topup_fx_note: '円表示は目安です。レート変動で表示額が変わります。実際の請求はUSD建てで決済画面に表示されます。',
  topup_usd_estimate: '約 $%{usd}（USD請求）',
  topup_credit_label: 'チャージ額: ¥%{jpy}',
  topup_invalid_plan: '指定されたプランは利用できません。金額を選択し直してください。',
};

function formatJpy(amount) {
  var n = parseInt(amount, 10);
  if (isNaN(n)) n = 0;
  return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

function formatUsd(usdCents) {
  var n = parseInt(usdCents, 10);
  if (isNaN(n)) n = 0;
  return (n / 100).toFixed(2);
}

var TOPUP_AMOUNTS = [
  { cents: 1000, label: '¥1,000' },
  { cents: 3000, label: '¥3,000' },
  { cents: 5000, label: '¥5,000' },
];

// Props:
//   i18n: {Object} lamprey.chat.* の文言辞書（不足分は DEFAULT_I18N で補完）
//   balance: {number} 現在残高（cents。モーダル内の表示専用）
//   denominations: {Array} 固定額プラン一覧（plan_id / credit_jpy / estimated_usd_cents）
//   devMode: {boolean} 開発環境の擬似決済を表示するか
//   onSuccess: {Function} dev 擬似決済の確定後に呼ばれる（balance_cents 付き）
//   onClose: {Function} モーダルを閉じる
class WalletTopupModal extends React.Component {
  constructor(props) {
    super(props);
    var denoms = props.denominations || [];
    this.state = {
      selectedCents: 3000,
      customAmount: '',
      selectedPlanId: denoms.length > 0 ? denoms[0].plan_id : null,
      isProcessing: false,
      error: null,
      success: false,
    };
    this.handleSelectAmount = this.handleSelectAmount.bind(this);
    this.handleSelectPlan = this.handleSelectPlan.bind(this);
    this.handleCustomChange = this.handleCustomChange.bind(this);
    this.handleSubmit = this.handleSubmit.bind(this);
    this.handleOverlayClick = this.handleOverlayClick.bind(this);
    this.handleDialogKeyDown = this.handleDialogKeyDown.bind(this);
    // モーダルのフォーカス管理（Issue #78。ChatPanelApp と共用）。
    this.dialogRef = null;
    this.closeBtnRef = null;
    this.previouslyFocused = null;
  }

  componentDidMount() {
    // 開く直前のフォーカスを覚え、閉じるボタンへ初期フォーカスする。
    this.previouslyFocused = saveActiveElement();
    focusInitial(this.dialogRef, this.closeBtnRef);
  }

  componentWillUnmount() {
    restoreFocus(this.previouslyFocused);
    this.previouslyFocused = null;
  }

  // Esc で閉じる、Tab はダイアログ内で循環させる。親の ChatPanel
  // ダイアログへ伝搬させない（Esc で両方が閉じないようにする）。
  handleDialogKeyDown(e) {
    if (e.key === 'Escape') {
      e.stopPropagation();
      this.props.onClose();
      return;
    }
    if (e.key === 'Tab') {
      e.stopPropagation();
      trapTabKey(e, this.dialogRef);
    }
  }

  t(key) {
    var dict = this.props.i18n || {};
    if (dict[key] != null) return dict[key];
    return DEFAULT_I18N[key] || key;
  }

  tFormat(key, vars) {
    var s = this.t(key);
    Object.keys(vars || {}).forEach(function (k) {
      s = s.split('%{' + k + '}').join(String(vars[k]));
    });
    return s;
  }

  handleSelectAmount(cents) {
    this.setState({ selectedCents: cents, customAmount: '', selectedPlanId: null, error: null });
  }

  handleSelectPlan(planId) {
    this.setState({ selectedPlanId: planId, selectedCents: null, customAmount: '', error: null });
  }

  handleCustomChange(e) {
    var raw = e.target.value.replace(/[^0-9]/g, '');
    this.setState({ customAmount: raw, selectedCents: null, selectedPlanId: null, error: null });
  }

  getAmountCents() {
    if (this.state.selectedCents) return this.state.selectedCents;
    var parsed = parseInt(this.state.customAmount, 10);
    return isNaN(parsed) ? 0 : parsed;
  }

  isFixedMode() {
    var denoms = this.props.denominations || [];
    return denoms.length > 0;
  }

  handleSubmit() {
    var self = this;
    // Fixed prepaid (Issue #46): plan_id -> hosted checkout URL.
    // Completion arrives via webhook; poll the balance on return.
    if (this.isFixedMode() && this.state.selectedPlanId) {
      self.setState({ isProcessing: true, error: null });
      fetch('/api/v1/wallet_topup', {
        method: 'POST',
        headers: jsonHeaders(),
        body: JSON.stringify({ plan_id: this.state.selectedPlanId }),
      })
        .then(function (response) {
          return response.json().catch(function () { return {}; }).then(function (body) {
            if (!response.ok) {
              var err = new Error(body.error || self.t('wallet_pay_failed'));
              err.body = body;
              throw err;
            }
            return body;
          });
        })
        .then(function (data) {
          if (data.checkout_url) {
            self.setState({ isProcessing: false, redirecting: true });
            window.location.href = data.checkout_url;
            return;
          }
          throw new Error(self.t('wallet_pay_failed'));
        })
        .catch(function (err) {
          var msg = err.message || self.t('wallet_pay_failed');
          if (err.body && err.body.error_type === 'invalid_plan') msg = self.t('topup_invalid_plan');
          if (err.body && err.body.error_type === 'payment_unconfigured') msg = self.t('wallet_topup_unavailable_reason');
          self.setState({ isProcessing: false, error: msg });
        });
      return;
    }

    var amountCents = this.getAmountCents();

    if (amountCents < 100 || amountCents > 10000) {
      self.setState({ error: self.t('wallet_invalid_amount') });
      return;
    }

    self.setState({ isProcessing: true, error: null });

    // Step 1: Create a top-up intent (dev pseudo-payment; Freemius/Stripe not used per Issue #43)
    fetch('/api/v1/wallet_topup', {
      method: 'POST',
      headers: jsonHeaders(),
      body: JSON.stringify({ amount_cents: amountCents }),
    })
      .then(function (response) {
        if (!response.ok) {
          return response.json().catch(function () { return {}; }).then(function (body) {
            throw new Error(body.error || 'Checkout creation failed');
          });
        }
        return response.json();
      })
      .then(function (data) {
        // Hosted checkout redirect (fixed prepaid plans, Issue #46).
        // Completion arrives via webhook; poll the balance on return.
        if (data.provider === 'freemius' && data.checkout_url) {
          self.setState({ isProcessing: false, redirecting: true });
          window.location.href = data.checkout_url;
          return null;
        }
        // Dev mode: confirm the pseudo payment directly.
        return fetch('/api/v1/wallet_topup/confirm', {
          method: 'POST',
          headers: jsonHeaders(),
          body: JSON.stringify({ payment_intent_id: data.payment_intent_id }),
        });
      })
      .then(function (response) {
        // Hosted redirect path returns null above; skip confirm in that case.
        if (!response) return null;
        if (!response.ok) {
          return response.json().catch(function () { return {}; }).then(function (body) {
            throw new Error(body.error || 'Payment confirmation failed');
          });
        }
        return response.json();
      })
      .then(function (data) {
        // Null means the hosted redirect already happened; nothing more to do.
        if (!data) return;
        self.setState({ isProcessing: false, success: true });
        if (self.props.onSuccess) self.props.onSuccess(data.balance_cents);
        setTimeout(function () { self.props.onClose(); }, 1200);
      })
      .catch(function (err) {
        self.setState({ isProcessing: false, error: err.message || self.t('wallet_pay_failed') });
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
      React.createElement('div', {
        className: 'wallet-topup-modal',
        ref: function (el) { self.dialogRef = el; },
        onKeyDown: this.handleDialogKeyDown,
        role: 'dialog',
        'aria-modal': 'true',
        'aria-label': self.t('wallet_topup_title'),
      },
        // Header
        React.createElement('div', { className: 'wallet-topup-modal__header' },
          React.createElement('h3', { className: 'wallet-topup-modal__title' }, '💰 ' + self.t('wallet_topup_title')),
          React.createElement('button', {
            className: 'wallet-topup-modal__closeBtn',
            ref: function (el) { self.closeBtnRef = el; },
            onClick: this.props.onClose,
            'aria-label': self.t('wallet_topup_close'),
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
        }, self.t('wallet_current_balance') + (this.props.balance || 0).toLocaleString()),

        // Fixed prepaid plans (Issue #46): plan_id list with JPY + USD estimate.
        // Currency note: JPY display is an estimate; the true charge is USD.
        (function () {
          var denoms = self.props.denominations || [];
          if (denoms.length === 0) return null;
          return React.createElement('div', null,
            React.createElement('div', {
              style: { fontSize: '13px', color: '#ccc', marginBottom: '8px' }
            }, self.t('topup_select_plan')),
            React.createElement('div', { className: 'wallet-topup-modal__amounts' },
              denoms.map(function (d) {
                var label = '¥' + formatJpy(d.credit_jpy);
                var sub = d.estimated_usd_cents != null ? self.tFormat('topup_usd_estimate', { usd: formatUsd(d.estimated_usd_cents) }) : null;
                return React.createElement('button', {
                  key: d.plan_id,
                  className: 'wallet-topup-modal__amountBtn' + (state.selectedPlanId === d.plan_id ? ' is-selected' : ''),
                  onClick: function () { self.handleSelectPlan(d.plan_id); },
                  type: 'button',
                  title: sub || label,
                }, label + (sub ? '\n' + sub : ''));
              })
            ),
            React.createElement('div', {
              style: { fontSize: '11px', color: '#888', marginBottom: '12px' }
            }, self.t('topup_fx_note'))
          );
        })(),

        // Legacy dev amounts (shown only when no fixed plans are available).
        // Dev pseudo top-up is kept for local verification (Issue #46).
        (function () {
          var denoms = self.props.denominations || [];
          if (denoms.length > 0 && !self.props.devMode) return null;
          if (denoms.length > 0 && self.props.devMode) {
            return React.createElement('div', {
              style: { fontSize: '11px', color: '#666', margin: '8px 0' }
            }, '--- dev: ' + self.t('wallet_custom_label') + ' ---');
          }
          return React.createElement('div', null,
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
            React.createElement('div', { className: 'wallet-topup-modal__customAmount' },
              React.createElement('span', { className: 'wallet-topup-modal__customLabel' }, self.t('wallet_custom_label')),
              React.createElement('input', {
                className: 'wallet-topup-modal__customInput',
                type: 'text',
                inputMode: 'numeric',
                placeholder: self.t('wallet_amount_placeholder'),
                value: state.customAmount,
                onChange: self.handleCustomChange,
              })
            )
          );
        })(),

        // Status messages
        state.error && React.createElement('div', { className: 'wallet-topup-modal__error', role: 'alert' }, state.error),
        state.success && React.createElement('div', { className: 'wallet-topup-modal__success' }, self.t('wallet_success')),
        state.redirecting && React.createElement('div', { className: 'wallet-topup-modal__success' }, self.t('wallet_redirecting')),

        // Submit
        React.createElement('button', {
          className: 'wallet-topup-modal__submitBtn',
          onClick: this.handleSubmit,
          disabled: state.isProcessing || state.success || (this.isFixedMode() ? !state.selectedPlanId : this.getAmountCents() < 100),
          type: 'button',
        },
          state.isProcessing
            ? React.createElement('span', null,
                React.createElement('span', { className: 'wallet-topup-modal__spinner' }),
                self.t('wallet_processing')
              )
            : self.t('wallet_submit')
        )
      )
    );
  }
}

export default WalletTopupModal;
