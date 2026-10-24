/* eslint-env browser */
import React from 'react';
import WalletTopupModal from '../components/WalletTopup/WalletTopupModal';
import { fetchTopupStatus } from '../components/WalletTopup/walletTopupApi';

/**
 * MypageWalletApp — マイページのウォレット残高枠に置く「チャージする」
 * ボタン（Issue #58）。残高の金額自体は SSR（HAML）で出す。
 *
 * 額面選択モーダルは ChatPanel と共通の WalletTopupModal を使う。
 * チャージは既存 API（GET status → POST /api/v1/wallet_topup → checkout_url）
 * に一本化し、新しい決済経路は作らない。
 *
 * @param {Object} props
 * @param {Object} props.i18n lamprey.chat.* + lamprey.mypage.wallet_charge
 * @param {number} props.balance_cents SSR 残高（モーダル内の表示専用）
 */
class MypageWalletApp extends React.Component {
  constructor(props) {
    super(props);
    this.state = {
      showTopupModal: false,
      // Top-up availability: fetched from GET /api/v1/wallet_topup/status.
      // Defaults to enabled so the button never flashes "preparing" when
      // the status request fails; the server remains the source of truth.
      topupEnabled: true,
      topupDevMode: false,
      topupDenominations: [],
    };

    this.handleOpenTopup = this.handleOpenTopup.bind(this);
    this.handleCloseTopup = this.handleCloseTopup.bind(this);
    this.handleTopupSuccess = this.handleTopupSuccess.bind(this);
  }

  t(key) {
    var dict = this.props.i18n || {};
    return dict[key] != null ? dict[key] : key;
  }

  componentDidMount() {
    var self = this;
    fetchTopupStatus().then(function (status) {
      if (status) {
        self.setState({
          topupEnabled: status.topupEnabled,
          topupDevMode: status.devMode,
          topupDenominations: status.denominations,
        });
      }
    });
  }

  handleOpenTopup() {
    this.setState({ showTopupModal: true });
  }

  handleCloseTopup() {
    this.setState({ showTopupModal: false });
  }

  handleTopupSuccess() {
    // 残高の金額は SSR のため、dev 擬似決済の確定後は再読み込みで反映する。
    // hosted checkout 経路は決済ページへ遷移済みのためここには来ない。
    window.location.reload();
  }

  render() {
    var state = this.state;

    return React.createElement('div', { className: 'mypage-wallet' },
      React.createElement('button', {
        className: 'mypage-wallet-charge',
        onClick: this.handleOpenTopup,
        type: 'button',
        disabled: !state.topupEnabled,
        title: state.topupEnabled ? null : this.t('wallet_topup_unavailable_reason'),
      }, '💰 ' + this.t('wallet_charge')),

      // Top-up unavailable reason: visible only when the server reports
      // that no payment method is configured.
      !state.topupEnabled && React.createElement('div', {
        className: 'mypage-wallet-unavailable',
      }, this.t('wallet_topup_unavailable_reason')),

      state.showTopupModal && React.createElement(WalletTopupModal, {
        i18n: this.props.i18n,
        balance: this.props.balance_cents || 0,
        denominations: state.topupDenominations,
        devMode: state.topupDevMode,
        onSuccess: this.handleTopupSuccess,
        onClose: this.handleCloseTopup,
      })
    );
  }
}

export default MypageWalletApp;
