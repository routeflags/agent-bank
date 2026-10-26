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

// モーダルを開いたときの初期フォーカス。優先要素があればそこへ、
// なければダイアログ内の最初のフォーカス可能要素へ移動する。
export function focusInitial(container, preferred) {
  if (typeof document === 'undefined') return;
  var target = preferred || getFocusableElements(container)[0];
  if (!target || !target.focus) return;
  try { target.focus(); } catch (e) {}
  // setState 直後の ref 未確定に備え、フォーカスが当たらなければ再試行する。
  if (document.activeElement !== target) {
    setTimeout(function () { try { target.focus(); } catch (err) {} }, 0);
  }
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
