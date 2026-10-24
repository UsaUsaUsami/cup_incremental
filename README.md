# カップ × ゲート × ミニガン（仮題）

カップから玉を注ぎ、盤面に置いたゲートで玉の値を増やし、溜めた弾をミニガンで撃って敵を倒す、デッキ構築ローグライトの試作です。
Godot 4.7（GDScript）で作っています。発売先は Steam・DLsite（PC）を先に考え、スマホは後回しです。

- 遊びの元になったのは、Voodoo の『Cup Heroes』などの「カップの玉をゲートで増やす」ハイパーカジュアルです。それを土台にしたゲームは、調べた範囲では見当たりませんでした（`research/` 参照）。
- 決めたことと理由は [docs/design.md](docs/design.md) にまとめています。

## 遊び方（いまの試作）

1. タイトルで「はじめる」→ 11層を一本道で進む（地図はない）。戦闘・強敵・ショップ・休憩・宝箱の順番はランごとにランダムで、画面上部に「ショップまで2　宝箱まで4 …」と出る。11層目のボスを倒すとクリア。
2. 戦闘は「ノルマレース」。敵ごとに決まった**制限ターン**のうちに、**ノルマ**（合計ダメージ）へ届けば勝ち。届かなければランが終わる（HP はない）。
   - 敵は攻撃してこない代わりに、どの敵も盤面に値を減らす**デメリットゲート**（÷2、−5、√）を置いている。一部の敵は、さらに固有のハンデ（カップが速い、注ぐ玉 −2 など）を持つ。どちらも戦ってみるまで分からない。
3. 毎ターン手札を5枚引く。エネルギー（4）を払ってカードを出す。
   - ゲートのカードは、光った候補マス（各列に1つずつ＋ランダムに2つ）のどれかをクリックして置く。右クリックで選択の取り消し。盤面は 4列×5行。
   - すぐ効くカード（玉 +5、延長、引く、など）は出した時点で効く。
4. 「玉を注ぐ」かスペースでターン終了。カップが左右に往復するので、クリックかスペースで止めると、そこから玉が落ちる。
5. 下に落ちた玉の値の合計が弾倉に溜まり、ミニガンが撃って残りノルマを減らす。

## 起動

Godot は winget で入れています（`winget install GodotEngine.GodotEngine`）。

- ゲームを遊ぶ: `play.cmd` をダブルクリック
- エディターで開く: `play.cmd -e`
- PowerShell から直接:

```powershell
& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe" --path game
```

## フォルダの構成

| 場所 | 中身 |
|---|---|
| `game/` | **本番の Godot プロジェクト**。PC 向け 1920×1080 |
| `game/main.gd` | ランの流れ（タイトル・一本道の11層・戦闘・ショップ・休憩・宝箱・クリア・敗北）、戦闘の進行、画面（UI）、敵・銃・弾の描画、確認用の自動操作 |
| `game/board.gd` | 盤面（カップ・ゲート・ペグ・玉の物理と描画）。ゲートの種類の定義（`GATE_DEFS`） |
| `game/data.gd` | カード・敵・レリックの定義と、強化後の値の引き方 |
| `game/card.gd` | カード1枚の表示（手札・報酬・ショップ・一覧で共通） |
| `game/fx.gd` | 演出（粒子・飛び出す文字・一瞬の光・効果音） |
| `game/assets/` | フォント・UI 部品・粒子・効果音。ライセンスは `game/assets/licenses/` |
| `web/` | スマホで手ざわりを試すための HTML 版の試作（本番ではない）。`web/src/` の部品を `tools/build_web.py` で1枚の HTML にまとめる |
| `tools/snapshot.py` | Godot のデモを数秒動かして `snapshots/latest.gif` を作る（スマホで進み具合を見る用） |
| `research/` | 市場調査の地図（`map.md`）・経過（`log.md`）・照合済みの抜き書き（`extracts.json`）。原文の写しは git に入れていない |
| `snapshots/` | 確認用の GIF・PNG |

## 確認のしかた

Godot のコンソール版（`Godot_v4.7.2-stable_win64_console.exe`）を使う。`--` のあとがゲームへの引数。

```bash
G="$(ls -d ~/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_*/)Godot_v4.7.2-stable_win64_console.exe"
"$G" --headless --path game --import                         # 素材の取り込み（新しい素材を足したとき）
"$G" --headless --path game --check-only --script main.gd     # 文法の確認
"$G" --headless --path game -- --demo-auto                    # 自動プレイでランを最後まで通し、層ごとの状況を表示
"$G" --path game -- --demo-tour --shots=<フォルダ>            # 全画面をめぐって 0.1 秒ごとに PNG を保存
python tools/snapshot.py                                      # 戦闘デモの GIF を snapshots/latest.gif に作る
```

デモの種類: `--demo`（戦闘）、`--demo-bounce`（跳ね返し）、`--demo-tour`（画面めぐり）、`--demo-auto`（自動プレイ）。

## いまの状態（2026-10-24）

- 1章（11層）を最初から最後まで遊べる。戦闘はノルマレース、盤面は 4列×5行。自動プレイで、クリアとノルマ未達の両方まで通ることを確かめている。
- **数値のつり合いは未調整**（後回しと決めている）。ノルマ・制限ターン・反転の係数などは仮置きの定数。
- 絵は図形と無料素材の仮のもの。セーブとチュートリアルはまだない。
