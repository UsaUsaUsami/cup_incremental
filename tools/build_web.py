"""web/src の共通エンジンと各試作のスクリプトを、1枚の HTML（アーティファクト用）に組み立てる。

使い方: python tools/build_web.py
出力:   web/proto-a-cards.html ほか（PROTOS の各行）と、ブラウザ確認用の web/_preview-*.html
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB = os.path.join(ROOT, "web")
SRC = os.path.join(WEB, "src")

# (出力名, タイトル, 説明, 試作のスクリプト)
PROTOS = [
    ("proto-a-cards", "Cup Gate Cards", "カードを引いてゲートを置き、ペグで散る玉を注いで撃つデッキ構築型の試作", "proto_a.js"),
    ("proto-b-idle", "Cup Gate Idle", "注ぎ続けて敵の壁を越え、転生で強くなるインクリ特化の試作", "proto_b.js"),
    ("proto-c-pegs", "Cup Gate Pegs", "置いたら固定のゲートとペグで玉を散らすラウンド制の試作", "proto_c.js"),
]

HEAD = """<title>{title}</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Chakra+Petch:wght@500;700&display=swap">
<style>
  /* 単一の暗いテーマ（ゲーム画面）。720x1280 の仮想画面を画面に収まるよう拡大縮小する */
  :root {{
    --bg: #11131a;
    --frame: #0b0c11;
    --ink: #eef0f6;
    color-scheme: dark;
  }}
  html, body {{ height: 100%; }}
  body {{
    background: var(--frame);
    color: var(--ink);
    overflow: hidden;
    padding-left: max(16px, env(safe-area-inset-left, 0px));
    padding-right: max(16px, env(safe-area-inset-right, 0px));
    padding-block: 0;
    box-sizing: border-box;
  }}
  .stage {{
    width: 100%;
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    min-width: 0;
  }}
  canvas {{
    display: block;
    background: var(--bg);
    touch-action: none;
    border-radius: 10px;
    max-width: 100%;
  }}
</style>
<div class="stage" id="stage"><canvas id="game" aria-label="{desc}"></canvas></div>
<script>
(() => {{
{engine}
{proto}
}})();
</script>
"""

# アーティファクトの公開時に付く骨組みを、手元の確認用に再現する
PREVIEW_WRAP = ('<!doctype html><html><head><meta charset="utf-8">'
                '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">'
                '<style>:root{{padding-top:env(safe-area-inset-top);padding-bottom:env(safe-area-inset-bottom)}}'
                'body{{margin:0;font:14px system-ui}}</style></head><body>\n{body}\n</body></html>\n')


def main() -> None:
    with open(os.path.join(SRC, "engine.js"), encoding="utf-8") as f:
        engine = f.read()
    for name, title, desc, script in PROTOS:
        with open(os.path.join(SRC, script), encoding="utf-8") as f:
            proto = f.read()
        html = HEAD.format(title=title, desc=desc, engine=engine, proto=proto)
        with open(os.path.join(WEB, f"{name}.html"), "w", encoding="utf-8", newline="\n") as f:
            f.write(html)
        with open(os.path.join(WEB, f"_preview-{name}.html"), "w", encoding="utf-8", newline="\n") as f:
            f.write(PREVIEW_WRAP.format(body=html))
        print(f"web/{name}.html")


if __name__ == "__main__":
    main()
