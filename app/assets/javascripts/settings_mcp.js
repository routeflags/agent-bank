window.ST = window.ST || {};

// Issue #146: MCP 接続画面のコピーボタン。
//
// 平文トークンと claude_desktop_config.json の雛形は発行直後の 1 回しか
// 表示されない。手で写すと失敗しやすいのでワンクリックでクリップボードへ
// 入れる。React にはしない（この画面は Haml で描画する）。
//
// マークアップ（app/views/settings/mcp.haml）が持つ属性:
//   data-mcp-copy                  … コピー元要素のセレクタ
//   data-mcp-copied-message        … 成功時に aria-live 領域へ流す文言
//   data-mcp-copy-failed-message   … 失敗時の文言
// 読み上げ先は #mcp-copy-status（aria-live="polite"）。
(function(module) {
  var STATUS_SELECTOR = "#mcp-copy-status";
  var RESET_DELAY_MS = 2000;

  // コピーできる環境か。secure context でない（http の LAN アクセス等）と
  // navigator.clipboard は使えないため、その場合は execCommand に戻す。
  // 権限不足で writeText が拒否されたときも同じ経路に落とす。
  function copyText(text, done) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(
        function() { done(true); },
        function() { done(legacyCopy(text)); }
      );
      return;
    }

    done(legacyCopy(text));
  }

  function legacyCopy(text) {
    var area = document.createElement("textarea");
    area.value = text;
    area.setAttribute("readonly", "readonly");
    area.style.position = "fixed";
    area.style.top = "-1000px";
    document.body.appendChild(area);
    area.select();

    var copied = false;
    try {
      copied = document.execCommand("copy");
    } catch (error) {
      copied = false;
    }
    document.body.removeChild(area);
    return copied;
  }

  function announce(message) {
    var status = document.querySelector(STATUS_SELECTOR);
    if (status) {
      status.textContent = message || "";
    }
  }

  function bind(button) {
    button.addEventListener("click", function() {
      var source = document.querySelector(button.getAttribute("data-mcp-copy"));
      if (!source) {
        return;
      }

      // input なら value、code / pre なら textContent。
      var text = source.value !== undefined ? source.value : source.textContent;

      copyText(text, function(copied) {
        announce(
          button.getAttribute(
            copied ? "data-mcp-copied-message" : "data-mcp-copy-failed-message"
          )
        );

        if (!copied) {
          return;
        }

        // 見た目でも成功がわかるように、一時的にラベルを差し替える。
        var original = button.getAttribute("data-mcp-original-label");
        if (!original) {
          original = button.textContent;
          button.setAttribute("data-mcp-original-label", original);
        }
        button.textContent = button.getAttribute("data-mcp-copied-message");
        window.setTimeout(function() {
          button.textContent = button.getAttribute("data-mcp-original-label");
        }, RESET_DELAY_MS);
      });
    });
  }

  module.initializeMcpConnect = function initializeMcpConnect() {
    function setup() {
      var buttons = document.querySelectorAll("button[data-mcp-copy]");

      for (var i = 0; i < buttons.length; i++) {
        bind(buttons[i]);
      }
    }

    // レイアウトは head で初期化関数を呼ぶため、DOM 前なら待ってから束縛する。
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", setup);
    } else {
      setup();
    }
  };
})(window.ST);
