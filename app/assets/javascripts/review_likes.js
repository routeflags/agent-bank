window.ST = window.ST || {};

// Issue #151: レビューへの「いいね」トグル。
//
// follow/unfollow（follow.js）は jquery-ujs の remote で HTML を差し替えるが、
// ここは件数と aria-pressed だけを差し替えたいので fetch + JSON にする。
// React にはしない（React 16.1.1 はフック非対応で、この画面は Haml で描画する）。
//
// マークアップ（app/views/listings/_review_list.haml）が持つ属性:
//   aria-pressed  … 現在の状態（サーバーが描画し、JS が切り替える）
//   data-like-url   … いいねする（POST）
//   data-unlike-url … 取り消す（DELETE）
//   data-label-template … aria-label のテンプレート（%{count} を件数で置換）
(function(module) {
  var COUNT_SELECTOR = ".raku-review-like__count";
  var BUSY_ATTRIBUTE = "data-busy";

  function csrfToken() {
    var meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.getAttribute("content") : null;
  }

  function render(button, liked, count) {
    button.setAttribute("aria-pressed", liked ? "true" : "false");
    button.classList.toggle("is-liked", liked);

    var countNode = button.querySelector(COUNT_SELECTOR);
    if (countNode) {
      countNode.textContent = String(count);
    }

    // aria-label はボタン内の「♥ 3」を読み上げ対象から外すので、件数も含めて
    // 付け直す（テンプレートの %{count} を置換）。
    var template = button.getAttribute("data-label-template");
    if (template) {
      button.setAttribute("aria-label", template.replace("%{count}", String(count)));
    }
  }

  function toggle(button) {
    if (button.getAttribute(BUSY_ATTRIBUTE) === "true") {
      return;
    }

    var liked = button.getAttribute("aria-pressed") === "true";
    var url = button.getAttribute(liked ? "data-unlike-url" : "data-like-url");
    if (!url) {
      return;
    }

    button.setAttribute(BUSY_ATTRIBUTE, "true");

    fetch(url, {
      method: liked ? "DELETE" : "POST",
      credentials: "same-origin",
      headers: {
        "Accept": "application/json",
        "X-CSRF-Token": csrfToken()
      }
    }).then(function(response) {
      if (response.status === 401) {
        // セッション切れ。サーバーは HTML のリダイレクトではなく JSON を返す。
        return response.json().then(function(data) {
          window.location.href = (data && data.login_url) || "/login";
        });
      }
      if (!response.ok) {
        // 403（自分のレビュー・権限なし）や 404（削除済み）。状態は変えない。
        return null;
      }
      return response.json();
    }).then(function(data) {
      if (data && typeof data.likes_count === "number") {
        render(button, data.liked === true, data.likes_count);
      }
    }).catch(function() {
      // 通信失敗時も状態を変えない（押し直せば再試行になる）。
    }).then(function() {
      button.removeAttribute(BUSY_ATTRIBUTE);
    });
  }

  module.initializeReviewLikes = function initializeReviewLikes() {
    function bind() {
      var buttons = document.querySelectorAll("button[data-like-url]");

      for (var i = 0; i < buttons.length; i++) {
        buttons[i].addEventListener("click", function() {
          toggle(this);
        });
      }
    }

    // レイアウトは head で初期化関数を呼ぶため、DOM 前なら待ってから束縛する。
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", bind);
    } else {
      bind();
    }
  };
})(window.ST);
