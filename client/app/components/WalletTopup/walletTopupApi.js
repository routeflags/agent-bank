/* eslint-env browser */
// Shared wallet top-up API helpers (Issue #58).
//
// ChatPanelApp と MypageWalletApp の共通基盤。チャージ可否・額面の取得は
// GET /api/v1/wallet_topup/status に一本化する。
// React 16.1 のためクラスコンポーネント側と同様に ES5 形式で書く。

export function csrfToken() {
  var metaTag = document.querySelector('meta[name=csrf-token]');
  return metaTag ? metaTag.getAttribute('content') : '';
}

export function jsonHeaders() {
  return {
    'Content-Type': 'application/json',
    'X-CSRF-Token': csrfToken(),
  };
}

// Top-up availability (Issue #34, #46): keeps button labels in sync with
// the server payment configuration.
//
// Resolves to { topupEnabled, devMode, denominations, fixedAvailable },
// or null when the status cannot be determined (callers keep their
// optimistic defaults; the server remains the source of truth on submit).
//
// Fixed prepaid denominations (plan_id / USD / JPY) come from
// FreemiusTopupPlans; dev_mode pseudo-payment is development only.
export function fetchTopupStatus() {
  return fetch('/api/v1/wallet_topup/status', {
    method: 'GET',
    headers: jsonHeaders(),
  })
    .then(function (response) {
      if (!response.ok) return null;
      return response.json();
    })
    .then(function (data) {
      if (!data || typeof data.topup_enabled === 'undefined') return null;
      return {
        topupEnabled: !!data.topup_enabled,
        devMode: !!data.dev_mode,
        denominations: data.denominations || [],
        fixedAvailable: !!(data.fixed_prepaid_available || (data.denominations && data.denominations.length > 0)),
      };
    })
    .catch(function () {
      return null;
    });
}
