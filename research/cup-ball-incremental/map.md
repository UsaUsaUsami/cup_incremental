# map: cup-ball-incremental

問い: 「カップに入ったボールをゲートに通して増やす」ゲームをインクリメンタル（放置・強化・プレステージ）系として作るとき、いまの市場に何があり、どこに余地と落とし穴があるか。
最初の検索語: "multiply ball cup game", "ball gate multiplier hypercasual", "ボール 増やす ゲート カップ ゲーム", "incremental game design"

## 要る主張
- [x] 1. この界隈（ボール増殖系ハイパーカジュアル／インクリメンタル・放置ゲーム）の知見はどこに集まっているか（場） — automaton-2026-incremental-definition.md:25「疑問がRedditに投じられている」、lawn-guide-to-incrementals.md:14「comprehensive guide」、bhg-2025-plinkidle-design-discussion.md:27「open this discussion up to our players」
- [~] 2. 「カップのボールをゲートに通して増やす」仕組みの元になった作品（原典）はどれで、界隈で何と呼ばれているか — 一部だけ。gizmodo-2008-keisan-no-niwa.md:9「+5」「x7」ゲート、note-detamaka-bounce-and-collect.md:15,45「Bounce and collect」2021-02、supersonic-2021-hypercasual-trends.md:57「multiplier gates」、insightrackr-cup-heroes-intelligence.md:33「2023-10-25」、thexboxhub-2025-cup-heroes-review.md:39「pour out ping-pong balls from your cup」、4gamer-2026-maaaaath-keisan-gate.md:1「計算ゲート」
- [x] 3. その仕組みをインクリメンタル（強化・放置・プレステージ）と組み合わせた作品はすでにあるか、どれくらい遊ばれた・売れたか — steam-ballatory.md:125「88 user reviews」、steam-pegfinity.md:133「374」、steam-idle-gumball-machine.md:133「271」、steam-plinkidle.md:125「2 Nov, 2026」、insightrackr-cup-heroes-intelligence.md:13「1.4 million monthly downloads」
- [x] 4. 既存のカップ・ボール増殖系でプレイヤーが不満に思う点（どこで飽きるか・何が足りないか） — thexboxhub-2025-cup-heroes-review.md:57「fourth hour」, :63「precious few interesting ingredients」, :49「abundantly obvious」、applestore-cup-heroes.md:84「abusive use of ads」、applestore-money-rush.md:128「levels are too short」
- [x] 5. インクリメンタルゲームの設計がどこで失敗するか（数値の伸び・プレステージ・中盤の停滞）についての開発者の知見 — lawn-guide-balancing.md:46「Inflation is the term」、bhg-2025-plinkidle-design-discussion.md:87「cap how many balls」, :166「reset layers」、pecorella-2017-math-idle-3.md:258「4 times」、furtado-2018-lessons-first-incremental.md:316「automatize balancing」
- [x] 6. 物理ボール×増殖×インクリメンタル系が Steam／モバイルでどれくらい売れているか（数字） — steampageanalyzer-2026-idler.md:9,11,13「940 games」「5.6%」「$10 to $14.99」、pcgamer-2026-54-idle-games.md:56「AI disclosure」、unity-hyper-to-hybrid.md:23,33、voodoo-2025-2024-results.md:60

## 用語
- Idler（Steam のタグ名）— https://www.steampageanalyzer.com/niches/idler
- incremental game / idle game / clicker（インクリメンタル・放置・クリッカー。日本語記事でも併用）— https://automaton-media.com/articles/newsjp/20260130-414641/ （未確認）
- prestige（転生。リセットして永続倍率を得る）— https://www.gamedeveloper.com/design/the-math-of-idle-games-part-iii
- tier boost — Pecorella Part II（未確認）
- node buster（量産されたインクリの定型の俗称）— https://gamedev.net/news/3928-incremental-games-have-a-creativity-problem/ （未確認）
- multiplier gate / x2 gate — https://www.thexboxhub.com/cup-heroes-review/
- 計算ゲート（4Gamer の呼び方）— https://www.4gamer.net/games/013/G101328/20261006016/
- ボール増殖（app-liv が Bump Pop に使う）— https://app-liv.jp/5344050/
- 計算の庭（佐藤雅彦 2008。「+5」「x7」ゲートの先例）— https://www.gizmodo.jp/article/73/
- hypercasual / hybrid-casual / playable ad — https://unity.com/blog/the-shift-from-hyper-to-hybrid-games-and-why-it-matters-for-everyone （未確認）
- Plinko idle / pachinko idle / Peggle-like — itch・Steam の作品名から（未確認）

## 人
- Anthony Pecorella（Kongregate → Level Up Labs）— The Math of Idle Games I〜III、GDC 2015/GDC Europe 2016 講演
- Pedro Furtado（個人開発）— Lessons of my first incremental game（2018）（未確認）
- Eric Guan — Idle Game Design Principles（2025 Substack）（未確認）
- Payne Robinson — Incremental games have a creativity problem（gamedev.net）（未確認）
- Chris Zukowski（How To Market A Game）— Steam 市場の分析（未確認）
- thepaperpilot — Incremental Social（未確認）
- Orteil / Julien Thiennot（Cookie Clicker）、Frank Lantz（Universal Paperclips）（未確認）

## 場
- r/incremental_games — https://www.reddit.com/r/incremental_games/ （英語の検索役。プレイヤーと開発者の本拠）
- r/incremental_gamedev — https://www.reddit.com/r/incremental_gamedev/ （英）
- r/incremental_games の Discord（英・未確認）
- Incremental Social（fediverse）（英・未確認）
- itch.io の idle / incremental タグ — https://itch.io/games/tag-idle/tag-increment （英）
- Game Developer（旧 Gamasutra）／Kongregate blog — Pecorella 連載の原載（英・日 両方）
- GDC Vault — https://gdcvault.com/play/1022066/Idle-Games-The-Mechanics-and （英・会員限定の可能性）
- Steam Page Analyzer の Niche Index — https://www.steampageanalyzer.com/niches/idler （英・日 両方）
- How To Market A Game — https://howtomarketagame.com/ （英）
- App Store のレビュー（Rollic・Voodoo のゲート系）（日）
- Automaton／4Gamer／電撃オンライン／MSY（日本語のゲームメディア）（日）
- Substack・dev.to の個人の事後分析（英・日）

## 原文（sources/）
| 論文・資料 | ファイル | 元の URL | どこから来たか（周・動き） |
|---|---|---|---|
| 〔本人〕Pecorella: The Math of Idle Games I | pecorella-2016-math-idle-1.md | https://www.gamedeveloper.com/design/the-math-of-idle-games-part-i | 1周・0周目の手がかり |
| 〔本人〕Pecorella: The Math of Idle Games II（未読） | pecorella-2016-math-idle-2.md | https://www.gamedeveloper.com/game-platforms/the-math-of-idle-games-part-ii | 1周・0周目 |
| 〔本人〕Pecorella: The Math of Idle Games III | pecorella-2017-math-idle-3.md | https://www.gamedeveloper.com/design/the-math-of-idle-games-part-iii | 1周・0周目 |
| 〔本人〕Pecorella: Quest for Progress スライド（本文ほぼ無し） | pecorella-2016-quest-for-progress-slides.md | https://www.slideshare.net/AnthonyPecorella/quest-for-progress-gdc-europe-2016 | 1周・Part I から後ろへ |
| 〔まとめ〕測定あり Steam Page Analyzer: Idler | steampageanalyzer-2026-idler.md | https://www.steampageanalyzer.com/niches/idler | 1周・0周目 |
| 〔観察〕TheXboxHub: Cup Heroes Review | thexboxhub-2025-cup-heroes-review.md | https://www.thexboxhub.com/cup-heroes-review/ | 1周・0周目 |
| 〔本人〕Furtado: Lessons of my first incremental game | furtado-2018-lessons-first-incremental.md | https://www.gamedeveloper.com/design/lessons-of-my-first-incremental-game | 1周・0周目 |
| 〔本人〕Guan: Idle Game Design Principles | guan-2025-idle-design-principles.md | https://ericguan.substack.com/p/idle-game-design-principles | 1周・0周目 |
| 〔まとめ〕宣伝あり gamedev.net: Robinson の動画の紹介 | robinson-gamedevnet-creativity-problem.md | https://gamedev.net/news/3928-incremental-games-have-a-creativity-problem/ | 1周・0周目 |
| 〔観察〕PC Gamer: 54 idle games | pcgamer-2026-54-idle-games.md | https://pcgamer.com/gaming-industry/steam-week-in-review-54-idle-games-released-on-steam-last-week-and-many-look-eerily-similar | 1周・0周目 |
| 〔まとめ〕Automaton: インクリメンタルの定義論争 | automaton-2026-incremental-definition.md | https://automaton-media.com/articles/newsjp/20260130-414641/ | 1周・0周目 |
| 〔観察〕4Gamer: 計算ゲートと MAaaaaTH! | 4gamer-2026-maaaaath-keisan-gate.md | https://www.4gamer.net/games/013/G101328/20261006016/ | 1周・0周目 |
| 〔公式〕App Store: Money Rush（レビュー含む） | applestore-money-rush.md | https://apps.apple.com/us/app/-/id1580099513 | 1周・0周目 |
| 〔観察〕アプリブ: Bump Pop | appliv-2026-bump-pop.md | https://app-liv.jp/5344050/ | 1周・0周目 |
| 〔公式〕Unity: hyper から hybrid へ | unity-hyper-to-hybrid.md | https://unity.com/blog/the-shift-from-hyper-to-hybrid-games-and-why-it-matters-for-everyone | 1周・0周目 |
| 〔公式〕App Store: Cup Heroes（Voodoo） | applestore-cup-heroes.md | https://apps.apple.com/us/app/cup-heroes/id6469621221 | 1周・親の検索 |
| 〔公式〕CrazyGames: Cup Heroes（未読） | crazygames-cup-heroes.md | https://www.crazygames.com/game/cup-heroes | 1周・親の検索 |
| 〔公式〕Nintendo: Multi Maze 3D（未読） | nintendo-multi-maze-3d.md | https://nintendo.co.uk/Games/Nintendo-Switch-download-software/Multi-Maze-3D-2545988.html | 1周・親の検索 |
| 〔公式〕Steam: Ballatory | steam-ballatory.md / itch-ballatory.md（未読） | https://store.steampowered.com/app/3957050/ | 1周・0周目 |
| 〔公式〕Steam: PlinkIdle | steam-plinkidle.md | https://store.steampowered.com/app/3684530/ | 1周・0周目 |
| 〔公式〕Steam: Pegfinity | steam-pegfinity.md | https://store.steampowered.com/app/3947040/ | 1周・0周目 |
| 〔公式〕Steam: Idle Gumball Machine | steam-idle-gumball-machine.md | https://store.steampowered.com/app/3724490/ | 1周・0周目 |
| 〔公式〕Steam: BALL x PIT | steam-ball-x-pit.md | https://store.steampowered.com/app/2062430/ | 1周・0周目 |
| 〔公式〕App Store: Balls go High（未読） | applestore-balls-go-high.md | https://apps.apple.com/us/app/id1604861021 | 1周・0周目 |
| 〔公式〕itch: Plinkonomics（未読） | itch-plinkonomics.md | https://boygamedev.itch.io/plinkonomics | 1周・0周目 |
| 〔まとめ〕Insightrackr: Cup Heroes（推定値） | insightrackr-cup-heroes-intelligence.md | https://blog.insightrackr.com/en/docs/Cup-Heroes-Intelligence | 1周・親の検索 |
| 〔公式〕Voodoo: 2024 年の業績 | voodoo-2025-2024-results.md | https://voodoo.io/news/voodoo-reports-20-growth-and-strong-profitability-in-2024 | 1周・親の検索 |
| 〔本人〕Black Heart Games: PlinkIdle Game Design Discussion | bhg-2025-plinkidle-design-discussion.md | https://black-heart-games-studio.itch.io/plinkidle/devlog/949621/plinkidle-game-design-discussion | 1周・親の検索 |
| 〔本人〕Black Heart Games: Major Upgrade Overhaul | bhg-2026-plinkidle-upgrade-overhaul.md | https://black-heart-games-studio.itch.io/plinkidle/devlog/1521814/plinkidle-major-upgrade-overhaul | 1周・著者で追う |
| 〔本人〕Black Heart Games: Homestretch | bhg-2026-plinkidle-homestretch.md | https://black-heart-games-studio.itch.io/plinkidle/devlog/1668002/homestretch | 1周・著者で追う |
| 〔観察〕VaporLens: Smashing Bottles（未読） | vaporlens-smashing-bottles.md | https://vaporlens.app/app/4637870/smashing_bottles | 1周・親の検索 |
| 〔本人〕Lawn (The Paper Pilot): Guide to Incrementals | lawn-guide-to-incrementals.md | https://paperpilot.dev/garden/guide-to-incrementals | 1周・Automaton から後ろへ |
| 〔本人〕Lawn: Balancing | lawn-guide-balancing.md | https://paperpilot.dev/garden/guide-to-incrementals/balancing | 1周・後ろへ |
| 〔本人〕Lawn: Navigating Criticism | lawn-guide-navigating-criticism.md | https://paperpilot.dev/garden/guide-to-incrementals/navigating-criticism | 1周・後ろへ |
| 〔本人〕Lawn: Appeal to Players（未読） | lawn-guide-appeal-to-players.md | https://paperpilot.dev/garden/guide-to-incrementals/appeal-to-players | 1周・後ろへ |
| 〔本人〕Lawn: What is Content?（未読） | lawn-guide-what-is-content.md | https://paperpilot.dev/garden/guide-to-incrementals/what-is-content | 1周・後ろへ |
| 〔観察〕note 浮雲: Bounce and collect | note-detamaka-bounce-and-collect.md | https://note.com/deta_maka/n/nf77e202823f6 | 1周・親の検索（深い検索） |
| 〔公式〕Supersonic: 2021 年のハイパーカジュアルの傾向 | supersonic-2021-hypercasual-trends.md | https://supersonic.com/learn/blog/breaking-down-hyper-casual-trends-in-2021 | 1周・親の検索 |
| 〔まとめ〕Naavik: The Evolution of Hybridcasual | naavik-evolution-of-hybridcasual.md | https://naavik.co/deep-dives/evolution-of-hybridcasual-deepdive/ | 1周・親の検索 |
| 〔観察〕Gizmodo: 計算の庭（2008） | gizmodo-2008-keisan-no-niwa.md | https://www.gizmodo.jp/article/73/ | 1周・0周目の手がかり |

## 次の手がかり
- Cup Heroes より前のカップ型の作品 — 広告アーカイブ（Meta Ad Library など）、AppMagic・Sensor Tower（有料）
- r/incremental_games の Automaton が引いたスレッド本文（vkaike2 の投稿）
- Lawn「Appeal to Players」「What is Content?」— 保存したが未読
- Payne Robinson の元動画（YouTube）— yt-dlp を入れれば字幕を取れる
- 「カップ＋ボール＋倍率ゲート」の元祖ハイパーカジュアルの特定 — 2本とも特定できず。候補: Cup Heroes、Multi Maze 3D、Balls go High（Voodoo）、Balls to Cup、Money Rush（Rollic・ゲート式）
- Cup Heroes（Studio 501?/Voodoo?）— アイデアにいちばん近い既存作。ストアの数字とレビューを取る
- Steam のボール物理×インクリ作品（Ballatory、PlinkIdle、Pegfinity、Idle Gumball Machine、Ball x Pit）— レビュー数・評価を取る
- Pecorella Part I〜III — 数値設計の定番。後ろへ（引いている作品・資料）
- Steam Page Analyzer の idler — 市場の数字
- PC Gamer「54 idle games released last week」、gamedev.net の creativity problem — 飽和と量産の論調
- r/incremental_games — プレイヤーの不満（両方とも探していない）
- 日本語の個人開発者の放置ゲーム設計記事（note・個人ブログ・X）— 日本語の検索役は見つけられず
