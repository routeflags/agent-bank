/* eslint-env browser */
// Shared modal dialog keyboard support (Issue #78).
//
// ChatPanelApp と WalletTopupModal で共用するフォーカス管理。React 16.1
// （フック非対応）のため、クラスコンポーネントから呼ぶプレーンな関数群。
// コピペで2箇所に書かず、この1ファイルにまとめる。
//
// 使い方（各モーダル共通）:
//   - 開く直前: this.previouslyFocused = saveActiveElement();
//   - 開いた直後: focusInitial(this.dialogRef, this.initialFocusRef);
//   - ダイアログの onKeyDown: Esc → 閉じる、Tab → trapTabKey(e, dialogRef)
//   - 閉じた後: restoreFocus(this.previouslyFocused);

var FOCUSABLE_SELECTOR =
  'a[href], button:not([disabled]), textarea:not([disabled]), ' +
  'input:not([disabled]), select:not([disabled]), [tabindex]:not([tabindex="-1"])';

// ダイアログ内のフォーカス可能な要素をタブ順で返す。非表示・無効は除く。
export function getFocusableElements(container) {
  if (typeof document === 'undefined') return [];
  if (!container || !container.querySelectorAll) return [];
  var nodes = container.querySelectorAll(FOCUSABLE_SELECTOR);
  var els = [];
  for (var i = 0; i < nodes.length; i++) {
    var el = nodes[i];
    if (el.disabled) continue;
    if (el.getAttribute && el.getAttribute('aria-hidden') === 'true') continue;
    // offsetParent は fixed 配置でも null になるため、rect で可視判定する。
    if (el.getBoundingClientRect) {
      var rect = el.getBoundingClientRect();
      if (rect.width === 0 && rect.height === 0) continue;
    }
    els.push(el);
  }
  return els;
}

// Tab / Shift+Tab をダイアログ内で循環させる。フォーカスを移動したら true。
export function trapTabKey(event, container) {
  if (!event || event.key !== 'Tab' || !container) return false;
  var focusables = getFocusableElements(container);
  if (focusables.length === 0) {
    event.preventDefault();
    return true;
  }
  var first = focusables[0];
  var last = focusables[focusables.length - 1];
  var active = typeof document === 'undefined' ? null : document.activeElement;
  if (event.shiftKey) {
    if (active === first || !container.contains(active)) {
      event.preventDefault();
      last.focus();
      return true;
    }
  } else if (active === last || !container.contains(active)) {
    event.preventDefault();
    first.focus();
    return true;
  }
  return false;
}

// 優先要素がフォーカス可能かを判定する（Issue #78 R5）。
// disabled・aria-hidden・非表示の要素を初期フォーカス先にすると
// フォーカスが body に逃げるため、該当時はフォールバックへ譲る。
function isFocusablePreferred(el) {
  if (!el || !el.focus || el.disabled) return false;
  if (el.getAttribute && el.getAttribute('aria-hidden') === 'true') return false;
  if (el.getBoundingClientRect) {
    var rect = el.getBoundingClientRect();
    if (rect.width === 0 && rect.height === 0) return false;
  }
  return true;
}

// モーダルを開いたときの初期フォーカス。優先要素があればそこへ、
// なければダイアログ内の最初のフォーカス可能要素へ移動する。
// 優先要素が disabled 等で受け付けない場合は先頭要素へフォールバックし、
// どちらも無ければダイアログ自体（tabIndex="-1" 付与が前提）に置く。
export function focusInitial(container, preferred) {
  if (typeof document === 'undefined') return;
  var target = isFocusablePreferred(preferred)
    ? preferred
    : getFocusableElements(container)[0] || null;
  if (!target && container && container.focus && container.hasAttribute &&
      container.hasAttribute('tabindex')) {
    target = container;
  }
  if (!target || !target.focus) return;
  try { target.focus(); } catch (e) {}
  // setState 直後の ref 未確定に備え、フォーカスが当たらなければ再試行する。
  if (document.activeElement !== target) {
    setTimeout(function () { try { target.focus(); } catch (err) {} }, 0);
  }
}

// フォーカスがモーダル外に逃げた場合の復帰用（Issue #78 R6）。
// document レベルの keydown から呼び出す。ダイアログ内の Tab は各ダイアログの
// onKeyDown が循環させるため、ここでは「外にいる場合だけ」先頭へ戻す。
// 背景はオーバーレイがポインタを塞ぎ aria-modal が SR から隠すため、
// inert 属性を付けずともキーボード・SR の到達をこの復帰で抑止する。
// root 内に Wallet 決済モーダルがあれば、最前面のそちらを優先する。
export function pullFocusInside(event, root) {
  if (!event || event.key !== 'Tab' || !root) return false;
  if (typeof document === 'undefined') return false;
  var active = document.activeElement;
  if (active && root.contains && root.contains(active)) return false;
  var top = root;
  if (root.querySelector) {
    var nested = root.querySelector('.wallet-topup-modal');
    if (nested) top = nested;
  }
  var focusables = getFocusableElements(top);
  var target = focusables[0] || null;
  if (!target && top.focus && top.hasAttribute && top.hasAttribute('tabindex')) {
    target = top;
  }
  if (!target) return false;
  event.preventDefault();
  try { target.focus(); } catch (e) {}
  return true;
}

// モーダルを開く直前のフォーカス位置を保存する（閉じたら戻すため）。
export function saveActiveElement() {
  if (typeof document === 'undefined') return null;
  return document.activeElement;
}

// 保存した要素へフォーカスを戻す。要素が無くなっていても例外にしない。
export function restoreFocus(element) {
  if (!element || !element.focus) return;
  try { element.focus(); } catch (e) {}
}
