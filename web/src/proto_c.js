// 試作 C: いまのラウンド制の改良版。
// ゲートは一度置いたら動かせない（撤去はショップで有料）。盤面のペグで玉が左右に散る。
// 勝つとゲート3つから1つを選んで、すぐ置く（取らなければコイン）。3ラウンドごとにショップが開く。

const GATE_USES_BASE = 8, FIRE_TIME = 2.5, POUR = 6;

const game = {
  board: makeBoard({ pegs: true, useDisplay: "count" }),
  S: null,
  fireT: 0, fireHpStart: 0, msg: "",

  newRun() {
    return { phase: "place", round: 1, coins: 0, ballLv: 0, useLv: 0, holding: ["add", "mul"], removing: false,
      enemyHp: this.hpFor(1), enemyMax: this.hpFor(1), ballsLeft: 0, ammo: 0, rewards: [], lastReward: 0 };
  },

  hpFor: r => Math.round(25 * Math.pow(1.5, r - 1)),
  ballsPerRound() { return 20 + this.S.ballLv * 5; },
  gateUses() { return GATE_USES_BASE + this.S.useLv * 2; },
  ballCost() { return Math.round(10 * Math.pow(1.6, this.S.ballLv)); },
  useCost() { return Math.round(8 * Math.pow(1.6, this.S.useLv)); },
  removeCost() { return 6 + this.S.round; },
  shopOpen() { return this.S.round > 1 && (this.S.round - 1) % 3 === 0; },

  litEmpty() {
    this.board.highlight = new Set(this.board.slots.map((g, k) => g ? -1 : k).filter(k => k >= 0));
  },

  onSlot(i) {
    const S = this.S, B = this.board;
    if (S.phase === "place" && !B.slots[i]) {
      B.slots[i] = newGate(S.holding.shift(), this.gateUses());
      if (S.holding.length === 0 || B.slots.every(g => g)) {
        S.holding = [];
        B.highlight.clear();
        S.phase = "ready";
      } else {
        this.litEmpty();
      }
    } else if (S.phase === "ready" && S.removing && B.slots[i] && S.coins >= this.removeCost()) {
      S.coins -= this.removeCost();
      B.slots[i] = null;
      S.removing = false;
    }
  },

  startRound() {
    const S = this.S;
    S.phase = "play";
    S.removing = false;
    S.enemyMax = this.hpFor(S.round);
    S.enemyHp = S.enemyMax;
    S.ammo = 0;
    for (const g of this.board.slots) if (g) { g.uses = this.gateUses(); g.max = g.uses; }
    this.board.toPour = this.ballsPerRound();
    this.board.pourRate = POUR;
  },

  update(dt) {
    const S = this.S, B = this.board;
    B.ammoShown = S.phase === "fire" ? Math.max(S.ammo * (1 - this.fireT / FIRE_TIME), 0) : S.ammo;
    S.ballsLeft = B.toPour;
    if (S.phase === "play" && B.toPour === 0 && B.balls.length === 0) {
      S.phase = "fire";
      this.fireT = 0;
      this.fireHpStart = S.enemyHp;
      B.firing = S.ammo > 0;
    } else if (S.phase === "fire") {
      this.fireT += dt;
      S.enemyHp = this.fireHpStart - S.ammo * Math.min(this.fireT / FIRE_TIME, 1);
      if (S.enemyHp <= 0 || this.fireT >= FIRE_TIME) {
        B.firing = false;
        S.ammo = 0;
        if (S.enemyHp <= 0) {
          S.lastReward = 5 + 2 * S.round;
          S.coins += S.lastReward;
          S.round += 1;
          S.enemyMax = this.hpFor(S.round);
          S.enemyHp = S.enemyMax;
          S.rewards = shuffle(["add", "add", "mul", "mul", "sq"]).slice(0, 3);
          S.phase = "reward";
        } else {
          S.phase = "over";
        }
      }
    }
    this.msg = {
      place: `${S.holding.length ? GATE_DEFS[S.holding[0]].label : ""} を置くマスを選ぶ（置いたら動かせない）` +
        (S.holding.length > 1 ? `  あと ${S.holding.length - 1} 個` : ""),
      ready: S.removing ? `撤去するゲートをタップ（${this.removeCost()} コイン）` :
        this.shopOpen() ? `ショップが開いている（コイン ${fmt(S.coins)}）` : "準備ができたら開始",
      play: "注いでいる…（上の帯でカップを動かせる）",
      fire: `発射！ 残弾 ${fmt(B.ammoShown)}`,
      reward: `勝利！ +${S.lastReward} コイン。ゲートを1つ選ぶ（取らなければ +5 コイン）`,
      over: `敗北… ラウンド ${S.round} で HP が ${fmt(S.enemyHp)} 残った`,
    }[S.phase];
  },

  takeReward(t) {
    const S = this.S;
    if (t && this.board.slots.some(g => !g)) {
      S.holding = [t];
      S.phase = "place";
      this.litEmpty();
    } else {
      if (!t) S.coins += 5;
      S.phase = "ready";
    }
  },

  drawTop() {
    const S = this.S;
    text(`ラウンド ${S.round}   敵 HP ${fmt(Math.max(S.enemyHp, 0))} / ${fmt(S.enemyMax)}`, 20, 40, 28, "#eef0f6", "left", 700);
    drawBar(20, 52, W - 40, 16, S.enemyHp / S.enemyMax, "#e5504d", this.board.hitShake);
    const shown = S.phase === "play" ? S.ballsLeft : this.ballsPerRound();
    text(`コイン ${fmt(S.coins)}   残りの玉 ${shown} / ${this.ballsPerRound()}   ゲート回数 ${this.gateUses()}`,
      20, 100, 20, "rgba(238,240,246,0.75)");
  },

  drawPanel() {
    drawLines(this.msg, 16, 938, 22, "#eef0f6", W - 32, 2);
    if (this.S.phase === "ready" && !this.shopOpen()) {
      text(`次のショップ: ラウンド ${this.S.round + (3 - (this.S.round - 1) % 3)} の前`, 16, 1050, 20, "rgba(238,240,246,0.6)");
    }
  },

  buttons() {
    const S = this.S;
    const list = [];
    const bw = 228, bh = 72, x0 = 12, gap = 8;
    if (S.phase === "reward") {
      S.rewards.forEach((t, i) => list.push({ x: x0 + i * (bw + gap), y: 990, w: bw, h: 120, gate: t, text: "これを取る",
        enabled: true, act: () => this.takeReward(t) }));
      list.push({ x: 12, y: 1150, w: 696, h: 84, big: true, enabled: true, text: "取らない（+5 コイン）", act: () => this.takeReward(null) });
    } else if (S.phase === "ready") {
      if (this.shopOpen()) {
        const bc = this.ballCost(), uc = this.useCost(), rc = this.removeCost();
        list.push({ x: x0, y: 1000, w: bw, h: bh, text: "玉 +5", sub: fmt(bc), enabled: S.coins >= bc,
          act: () => { S.coins -= bc; S.ballLv += 1; } });
        list.push({ x: x0 + bw + gap, y: 1000, w: bw, h: bh, text: "ゲート回数 +2", sub: fmt(uc), enabled: S.coins >= uc,
          act: () => { S.coins -= uc; S.useLv += 1; } });
        list.push({ x: x0 + 2 * (bw + gap), y: 1000, w: bw, h: bh, text: S.removing ? "撤去をやめる" : "ゲート撤去",
          sub: fmt(rc), enabled: S.coins >= rc || S.removing, selected: S.removing,
          act: () => { S.removing = !S.removing; } });
      }
      list.push({ x: 12, y: 1150, w: 696, h: 84, big: true, enabled: true,
        text: `ラウンド ${S.round} 開始（敵 HP ${fmt(S.enemyMax)}）`, act: () => this.startRound() });
    } else if (S.phase === "over") {
      list.push({ x: 12, y: 1150, w: 696, h: 84, big: true, enabled: true, text: "最初から", act: () => this.reset() });
    } else {
      list.push({ x: 12, y: 1150, w: 696, h: 84, big: true, enabled: false, text: S.phase === "place" ? "マスを選んで置く" : "…",
        act: () => {} });
    }
    return list;
  },

  reset() {
    this.S = this.newRun();
    this.board.slots.fill(null);
    this.litEmpty();
  },

  snapshot() { return { S: this.S, slots: this.board.slots }; },

  restore(data) {
    if (data.S && data.S.phase !== "over") {
      this.S = data.S;
      this.board.slots = data.slots || this.board.slots;
      if (this.S.phase === "play" || this.S.phase === "fire") { this.S.phase = "ready"; this.S.enemyHp = this.S.enemyMax; }
      if (this.S.phase === "place") this.litEmpty();
    } else {
      this.reset();
    }
    this.board.onCollect = v => { this.S.ammo += v; };
  },
};

run(game);
