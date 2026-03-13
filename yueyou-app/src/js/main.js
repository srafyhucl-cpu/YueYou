const API_BASE = "http://8.218.177.149:3000";
(() => {
  var U = class {
    constructor() {
      ((this.MODES = { CLASSIC: "classic", LOOP: "loop" }),
        (this.PHASES = {
          NORMAL: "normal",
          DISASSEMBLE: "disassemble",
          REASSEMBLE: "reassemble",
        }));
      let e = localStorage.getItem("bestScore_premium");
      ((this.bestScore = e && !isNaN(e) ? parseInt(e) : 0), this.reset());
    }
    reset() {
      ((this.mode = this.MODES.CLASSIC),
        (this.phase = this.PHASES.NORMAL),
        (this.size = 4),
        (this.score = 0),
        (this.combo = 0),
        (this.nextId = Date.now()),
        (this.over = !1),
        (this.won = !1),
        (this.phaseJustCleared = !1),
        this.initBoard(),
        this.addRandomTile(),
        this.addRandomTile());
    }
    initBoard() {
      ((this.board = Array(this.size)
        .fill()
        .map(() => Array(this.size).fill(null))),
        this.mode === this.MODES.LOOP &&
          (this.board[2][2] = { id: 0, value: 2048, isAnchor: !0 }));
    }
    jumpToStage(e) {
      ((this.won = !1),
        (this.over = !1),
        (this.phaseJustCleared = !1),
        (this.combo = 0),
        e === "classic"
          ? ((this.mode = this.MODES.CLASSIC),
            (this.size = 4),
            (this.phase = this.PHASES.NORMAL),
            this.initBoard(),
            this.addRandomTile(),
            this.addRandomTile())
          : e === "loop_1"
            ? ((this.mode = this.MODES.LOOP),
              (this.size = 5),
              (this.phase = this.PHASES.DISASSEMBLE),
              this.initBoard(),
              this.seedDisassembleTiles())
            : e === "loop_2"
              ? ((this.mode = this.MODES.LOOP),
                (this.size = 5),
                (this.phase = this.PHASES.REASSEMBLE),
                this.initBoard(),
                this.addLoopTile())
              : e === "fast_win" &&
                (this.jumpToStage("loop_2"),
                [
                  { r: 1, c: 2 },
                  { r: 3, c: 2 },
                  { r: 2, c: 1 },
                  { r: 2, c: 3 },
                ].forEach(
                  (t) =>
                    (this.board[t.r][t.c] = { id: this.nextId++, value: 512 }),
                ),
                this.checkPhaseTransition()));
    }
    seedDisassembleTiles() {
      let e = [512, 256, 128, 64];
      for (let s = 0; s < 4; s++) {
        let t = [];
        for (let r = 0; r < 5; r++)
          for (let l = 0; l < 5; l++)
            !this.board[r][l] &&
              (r === 0 || r === 4 || l === 0 || l === 4) &&
              t.push({ r, c: l });
        if (t.length) {
          let r = t[Math.floor(Math.random() * t.length)];
          this.board[r.r][r.c] = { id: this.nextId++, value: e[s] };
        }
      }
    }
    move(e) {
      if (this.over || this.won || this.phaseJustCleared)
        return { moved: !1, mergedTiles: [] };
      let s = !1,
        t = [],
        r = this.getVector(e),
        { rows: l, cols: y } = this.getTraversalOrder(r),
        v = Array(this.size)
          .fill()
          .map(() => Array(this.size).fill(null));
      this.board.forEach((u, w) =>
        u.forEach((h, E) => {
          h && (v[w][E] = { ...h });
        }),
      );
      let A = Array(this.size)
        .fill()
        .map(() => Array(this.size).fill(!1));
      return (
        l.forEach((u) => {
          y.forEach((w) => {
            let h = v[u][w];
            if (!h || h.isAnchor) return;
            let E = { r: u, c: w },
              m = { r: u + r.y, c: w + r.x };
            for (; this.inBounds(m.r, m.c) && !v[m.r][m.c]; )
              ((v[m.r][m.c] = h),
                (v[E.r][E.c] = null),
                (E = { r: m.r, c: m.c }),
                (m = { r: m.r + r.y, c: m.c + r.x }),
                (s = !0));
            if (this.inBounds(m.r, m.c)) {
              let M = v[m.r][m.c];
              if (M && !M.isAnchor && M.value === h.value && !A[m.r][m.c]) {
                let $ =
                  this.mode === this.MODES.LOOP &&
                  this.phase === this.PHASES.DISASSEMBLE;
                ((M.value = $ ? Math.max(2, M.value / 2) : M.value * 2),
                  (v[E.r][E.c] = null),
                  (A[m.r][m.c] = !0),
                  (s = !0),
                  this.combo++,
                  (this.score += M.value),
                  this.score > this.bestScore &&
                    ((this.bestScore = this.score),
                    localStorage.setItem("bestScore_premium", this.bestScore)),
                  t.push({
                    r: m.r,
                    c: m.c,
                    value: M.value,
                    combo: this.combo,
                  }));
              }
            }
          });
        }),
        s &&
          (t.length === 0 && (this.combo = 0),
          (this.board = v),
          this.mode === this.MODES.LOOP
            ? (this.addLoopTile(), this.checkPhaseTransition())
            : (this.addRandomTile(),
              this.getMaxTileValue() >= 2048 && (this.phaseJustCleared = !0)),
          this.movesAvailable() || (this.over = !0)),
        { moved: s, mergedTiles: t, combo: this.combo }
      );
    }
    addLoopTile() {
      let e = [];
      for (let s = 0; s < 5; s++)
        for (let t = 0; t < 5; t++)
          (s === 0 || s === 4 || t === 0 || t === 4) &&
            !this.board[s][t] &&
            e.push({ r: s, c: t });
      if (e.length) {
        let s = e[Math.floor(Math.random() * e.length)],
          t =
            this.phase === this.PHASES.REASSEMBLE
              ? Math.random() < 0.9
                ? 2
                : 4
              : this.getMaxTileValue();
        this.board[s.r][s.c] = { id: this.nextId++, value: t };
      }
    }
    checkPhaseTransition() {
      if (this.phase === this.PHASES.DISASSEMBLE) {
        let e = !1,
          s = 0;
        (this.board.forEach((t) =>
          t.forEach((r) => {
            r && !r.isAnchor && (s++, r.value > 2 && (e = !0));
          }),
        ),
          s > 0 && !e && (this.phaseJustCleared = !0));
      } else if (this.phase === this.PHASES.REASSEMBLE) {
        let e = [
            { r: 1, c: 2 },
            { r: 3, c: 2 },
            { r: 2, c: 1 },
            { r: 2, c: 3 },
          ],
          s = !0;
        (e.forEach((t) => {
          (!this.board[t.r][t.c] || this.board[t.r][t.c].value < 512) &&
            (s = !1);
        }),
          s && (this.won = !0));
      }
    }
    clearTile(e, s) {
      return this.board[e][s] && !this.board[e][s].isAnchor
        ? ((this.board[e][s] = null), !0)
        : !1;
    }
    getMaxTileValue() {
      let e = 2;
      return (
        this.board.forEach((s) =>
          s.forEach((t) => {
            t && !t.isAnchor && (e = Math.max(e, t.value));
          }),
        ),
        e
      );
    }
    inBounds(e, s) {
      return e >= 0 && e < this.size && s >= 0 && s < this.size;
    }
    getVector(e) {
      return {
        up: { x: 0, y: -1 },
        down: { x: 0, y: 1 },
        left: { x: -1, y: 0 },
        right: { x: 1, y: 0 },
      }[e];
    }
    getTraversalOrder(e) {
      let s = [...Array(this.size).keys()],
        t = [...Array(this.size).keys()];
      return (
        e.y === 1 && s.reverse(),
        e.x === 1 && t.reverse(),
        { rows: s, cols: t }
      );
    }
    movesAvailable() {
      for (let e = 0; e < this.size; e++)
        for (let s = 0; s < this.size; s++) {
          if (!this.board[e][s]) return !0;
          for (let t of ["up", "down", "left", "right"]) {
            let r = this.getVector(t),
              l = e + r.y,
              y = s + r.x;
            if (this.inBounds(l, y)) {
              let v = this.board[l][y];
              if (!v || (!v.isAnchor && v.value === this.board[e][s].value))
                return !0;
            }
          }
        }
      return !1;
    }
    addRandomTile() {
      let e = [];
      for (let s = 0; s < this.size; s++)
        for (let t = 0; t < this.size; t++)
          this.board[s][t] || e.push({ r: s, c: t });
      if (e.length) {
        let { r: s, c: t } = e[Math.floor(Math.random() * e.length)];
        this.board[s][t] = {
          id: this.nextId++,
          value: Math.random() < 0.9 ? 2 : 4,
        };
      }
    }
  };
  var Y = class {
    constructor() {
      ((this.viewport = document.getElementById("game-viewport")),
        (this.app = document.getElementById("app")),
        (this.gridBg = document.getElementById("grid-bg")),
        (this.tileContainer = document.getElementById("tile-container")),
        (this.effectsContainer = document.getElementById("effects-container")),
        (this.progressBar = document.getElementById("phase-progress")),
        (this.phaseLabel = document.getElementById("phase-label")),
        (this.phaseTag = document.getElementById("phase-tag")),
        (this.scoreElement = document.getElementById("score")),
        (this.bestScoreElement = document.getElementById("best-score")),
        (this.comboDisplay = document.getElementById("combo-display")),
        (this.itemBar = document.getElementById("item-bar")),
        (this.successModal = document.getElementById("modal-phase-success")),
        (this.successTitle = document.getElementById("success-title")),
        (this.successMsg = document.getElementById("success-msg")),
        (this.nextPhaseInfo = document.getElementById("next-phase-info")),
        (this.currentMode = null));
    }
    render(e, s = []) {
      if (!this.tileContainer) return;
      ((this.app.className = e.mode === "loop" ? "mode-loop" : "mode-standard"),
        this.currentMode !== e.mode &&
          (this.renderGridBg(e.size),
          (this.currentMode = e.mode),
          this.itemBar &&
            this.itemBar.classList.toggle("hidden", e.mode !== "loop")));
      let t = new Set();
      (e.board.forEach((l, y) => {
        l.forEach((v, A) => {
          v &&
            (t.add(v.id),
            this.updateTileDOM(
              v,
              y,
              A,
              e.size,
              s.find((u) => u.r === y && u.c === A),
            ));
        });
      }),
        Array.from(this.tileContainer.children).forEach((l) => {
          let y = parseInt(l.id.replace("tile-", ""));
          t.has(y) || l.remove();
        }),
        s.length > 0
          ? (s.forEach((l) => this.createSplash(l, e.size)),
            this.showCombo(e.combo))
          : this.hideCombo(),
        (this.scoreElement.innerText = e.score || 0));
      let r = e.bestScore && !isNaN(e.bestScore) ? e.bestScore : 0;
      ((this.bestScoreElement.innerText = Math.max(e.score || 0, r)),
        this.updateProgress(e),
        e.phaseJustCleared
          ? this.showPhaseSuccess(e)
          : e.won && this.showFinalWin());
    }
    renderGridBg(e) {
      if (!this.gridBg) return;
      this.gridBg.innerHTML = "";
      let s = e * e;
      for (let t = 0; t < s; t++) {
        let r = document.createElement("div");
        ((r.className = "grid-cell"), this.gridBg.appendChild(r));
      }
    }
    updateTileDOM(e, s, t, r, l) {
      let y = document.getElementById(`tile-${e.id}`);
      (y ||
        ((y = document.createElement("div")),
        (y.id = `tile-${e.id}`),
        this.tileContainer.appendChild(y)),
        (y.className = `tile tile-${e.value} ${e.isAnchor ? "tile-anchor" : ""} ${l ? "tile-merged" : ""}`),
        (y.innerText = e.isAnchor ? "2048" : e.value));
      let v = 100 / r;
      ((y.style.top = `${s * v}%`),
        (y.style.left = `${t * v}%`),
        (y.style.width = `calc(${v}% - 10px)`),
        (y.style.height = `calc(${v}% - 10px)`));
    }
    createSplash({ r: e, c: s, value: t }, r) {
      let l = 100 / r,
        y = Math.log2(t || 2),
        v = Math.min(24, Math.max(6, Math.floor(y * 2))),
        A = t <= 8 ? 180 : t <= 64 ? 45 : t <= 256 ? 280 : 330;
      for (let u = 0; u < v; u++) {
        let w = document.createElement("div"),
          h = t >= 256 && Math.random() > 0.5,
          E = t >= 128;
        ((w.className = `particle${h ? " large" : ""}${E ? " glow" : ""}`),
          (w.style.top = `${(e + 0.5) * l}%`),
          (w.style.left = `${(s + 0.5) * l}%`));
        let m = 80 + y * 10,
          M = (Math.random() - 0.5) * m,
          $ = (Math.random() - 0.5) * m;
        w.style.setProperty("--target-transform", `translate(${M}px, ${$}px)`);
        let j = A + (Math.random() - 0.5) * 40;
        ((w.style.background = `hsl(${j}, 80%, ${60 + Math.random() * 20}%)`),
          (w.style.color = `hsl(${j}, 80%, 70%)`),
          this.effectsContainer.appendChild(w),
          setTimeout(() => w.remove(), h ? 800 : 600));
      }
    }
    shake() {
      (this.viewport.classList.add("shake"),
        setTimeout(() => this.viewport.classList.remove("shake"), 400));
    }
    showCombo(e) {
      e < 2 ||
        !this.comboDisplay ||
        ((this.comboDisplay.innerText = `COMBO x${e}`),
        (this.comboDisplay.style.opacity = "1"),
        (this.comboDisplay.style.transform = `scale(${1 + Math.min(e, 5) * 0.1})`));
    }
    hideCombo() {
      this.comboDisplay && (this.comboDisplay.style.opacity = "0");
    }
    updateProgress(e) {
      let s = 0;
      if (e.mode === "loop")
        if (e.phase === "disassemble") {
          ((this.phaseTag.innerText = "DISASSEMBLE"),
            (this.phaseLabel.innerText =
              "\u7B2C\u4E00\u9636\u6BB5\uFF1A\u71B5\u51CF\u62C6\u89E3"));
          let t = 0,
            r = 0;
          (e.board.forEach((l) =>
            l.forEach((y) => {
              y && !y.isAnchor && (t++, y.value === 2 && r++);
            }),
          ),
            (s = t ? (r / t) * 100 : 0));
        } else {
          ((this.phaseTag.innerText = "REASSEMBLE"),
            (this.phaseLabel.innerText =
              "\u7B2C\u4E8C\u9636\u6BB5\uFF1A\u7269\u8D28\u91CD\u6784"));
          let t = [
              { r: 1, c: 2 },
              { r: 3, c: 2 },
              { r: 2, c: 1 },
              { r: 2, c: 3 },
            ],
            r = 0;
          (t.forEach((l) => {
            e.board[l.r][l.c]?.value >= 512 && r++;
          }),
            (s = (r / 4) * 100));
        }
      else
        ((this.phaseTag.innerText = "CLASSIC"),
          (this.phaseLabel.innerText =
            "\u521D\u59CB\u7EF4\u5EA6\uFF1A\u51B2\u51FB 2048"),
          (s = Math.max(0, (Math.log2(e.getMaxTileValue()) - 1) / 10) * 100));
      ((this.progressBar.style.width = `${Math.min(100, s)}%`),
        this.setPhaseBackground(e));
    }
    setPhaseBackground(e) {
      let s = document.documentElement;
      e.mode === "loop"
        ? e.phase === "disassemble"
          ? (s.style.setProperty("--orb-a", "rgba(180, 30, 60, 0.25)"),
            s.style.setProperty("--orb-b", "rgba(100, 20, 140, 0.25)"))
          : (s.style.setProperty("--orb-a", "rgba(251, 191, 36, 0.25)"),
            s.style.setProperty("--orb-b", "rgba(34, 197, 94, 0.25)"))
        : (s.style.setProperty("--orb-a", "rgba(139, 92, 246, 0.25)"),
          s.style.setProperty("--orb-b", "rgba(236, 72, 153, 0.25)"));
    }
    playTransition(e = "victory") {
      return new Promise((s) => {
        let t = document.getElementById("transition-canvas");
        (t ||
          ((t = document.createElement("canvas")),
          (t.id = "transition-canvas"),
          document.body.appendChild(t)),
          (t.width = window.innerWidth),
          (t.height = window.innerHeight),
          t.classList.add("active"));
        let r = t.getContext("2d"),
          l = [],
          y = t.width / 2,
          v = t.height / 2;
        if (e === "victory")
          for (let h = 0; h < 60; h++) {
            let E = ((Math.PI * 2) / 60) * h,
              m = 3 + Math.random() * 5;
            l.push({
              x: y,
              y: v,
              vx: Math.cos(E) * m,
              vy: Math.sin(E) * m,
              size: 8 + Math.random() * 16,
              hue: Math.random() * 60 + 280,
              life: 1,
              decay: 0.008 + Math.random() * 0.008,
            });
          }
        else
          for (let h = 0; h < 50; h++) {
            let E = Math.random() * Math.PI * 2,
              m = 200 + Math.random() * 300;
            l.push({
              x: y + Math.cos(E) * m,
              y: v + Math.sin(E) * m,
              vx: -Math.cos(E) * (1 + Math.random() * 2),
              vy: -Math.sin(E) * (1 + Math.random() * 2),
              size: 6 + Math.random() * 12,
              hue: 0,
              life: 1,
              decay: 0.01 + Math.random() * 0.01,
            });
          }
        let A = 0,
          u = 90,
          w = () => {
            if ((A++, r.clearRect(0, 0, t.width, t.height), e === "defeat")) {
              let h = Math.min(0.6, A / u);
              ((r.fillStyle = `rgba(0, 0, 0, ${h})`),
                r.fillRect(0, 0, t.width, t.height));
            }
            (l.forEach((h) => {
              ((h.x += h.vx),
                (h.y += h.vy),
                (h.life -= h.decay),
                e === "victory" && ((h.vx *= 0.97), (h.vy *= 0.97)),
                h.life > 0 &&
                  ((r.globalAlpha = h.life),
                  (r.fillStyle =
                    e === "defeat"
                      ? `rgba(20, 0, 30, ${h.life})`
                      : `hsla(${h.hue}, 80%, 65%, ${h.life})`),
                  (r.shadowBlur = e === "victory" ? 15 : 0),
                  (r.shadowColor = `hsla(${h.hue}, 80%, 65%, 0.5)`),
                  r.beginPath(),
                  r.arc(h.x, h.y, h.size * h.life, 0, Math.PI * 2),
                  r.fill()));
            }),
              (r.globalAlpha = 1),
              (r.shadowBlur = 0),
              A < u
                ? requestAnimationFrame(w)
                : (t.classList.remove("active"),
                  r.clearRect(0, 0, t.width, t.height),
                  s()));
          };
        requestAnimationFrame(w);
      });
    }
    async showPhaseSuccess(e) {
      (await this.playTransition("victory"),
        this.successModal &&
          (this.successModal.classList.remove("hidden"),
          e.mode === "classic"
            ? ((this.successTitle.innerText =
                "\u62B5\u8FBE 2048 \u70B9\u4F4D\uFF01"),
              (this.successMsg.innerText =
                "\u4F60\u5DF2\u89E6\u78B0\u521D\u59CB\u7EF4\u5EA6\u7684\u6781\u9650\u3002"),
              (this.nextPhaseInfo.innerText = `\u5373\u5C06\u8FDB\u5165\uFF1A\u3010\u62C6\u89E3\u9636\u6BB5\u3011
\u76EE\u6807\uFF1A\u5C06\u6240\u6709\u7269\u8D28\u5F52 2\uFF08\u71B5\u51CF\uFF09\u3002`),
              (window._nextStageCallback = () => e.jumpToStage("loop_1")))
            : ((this.successTitle.innerText =
                "\u9636\u6BB5\u4EFB\u52A1\u5B8C\u6210\uFF01"),
              (this.successMsg.innerText =
                "\u903B\u8F91\u5C4F\u969C\u5DF2\u74E6\u89E3\u3002"),
              (this.nextPhaseInfo.innerText = `\u5373\u5C06\u8FDB\u5165\uFF1A\u3010\u91CD\u6784\u9636\u6BB5\u3011
\u76EE\u6807\uFF1A\u5728\u4E2D\u5FC3\u5468\u56F4\u5408\u6210 4 \u4E2A 512\u3002`),
              (window._nextStageCallback = () => e.jumpToStage("loop_2")))));
    }
    async showFinalWin() {
      (await this.playTransition("victory"),
        this.successModal &&
          (this.successModal.classList.remove("hidden"),
          (this.successTitle.innerText =
            "\u7EF4\u5EA6\u5927\u4E00\u7EDF\uFF01"),
          (this.successMsg.innerText =
            "\u4F60\u6210\u529F\u5728\u865A\u65E0\u4E2D\u5EFA\u7ACB\u4E86\u6C38\u6052\u79E9\u5E8F\u3002"),
          (this.nextPhaseInfo.innerText =
            "\u606D\u559C\u901A\u5173\uFF01\u4F60\u53EF\u4EE5\u7EE7\u7EED\u7559\u5728\u6B64\u7EF4\u5EA6\u63A2\u7D22\u3002"),
          (window._nextStageCallback = () =>
            this.successModal.classList.add("hidden"))));
    }
  };
  document.addEventListener("DOMContentLoaded", () => {
    let p = new U(),
      e = new Y(),
      s = {
        async saveScore(f, i) {
          if (!(typeof AV > "u" || !f || f === "\u70B9\u51FB\u767B\u5F55"))
            try {
              let c = AV.Object.extend("PlayerScore");
              await new c().save({ username: f, score: i });
            } catch {}
        },
        async loadLeaderboard() {
          let f = document.getElementById("leaderboard-content");
          if (!f) return;
          let i = localStorage.getItem("player_name") || "\u533F\u540D",
            c = parseInt(document.getElementById("score").innerText) || 0,
            a = () => {
              let n = [
                  { name: "AntigravityUser", score: 17098 },
                  { name: "Admin", score: 12054 },
                  { name: "TestUser", score: 8092 },
                  { name: "Observer_01", score: 4096 },
                  { name: "Player2048", score: 2048 },
                ],
                g = n.findIndex((T) => T.name === i) + 1,
                x = n
                  .map((T, _) => {
                    let N = T.name === i;
                    return `
                    <div style="display:flex; justify-content:space-between; padding:12px; margin-bottom:8px; border-radius:12px; border: 1px solid transparent; ${N ? "background:rgba(236,72,153,0.15); border-color:var(--accent-pink);" : "background:rgba(255,255,255,0.05); border-color:var(--glass-border);"}">
                        <span style="color:#fff; font-weight: 800;">${_ + 1}. ${T.name} ${N ? "(\u4F60)" : ""}</span>
                        <span style="color:var(--accent-pink); font-weight:800;">${T.score}</span>
                    </div>
                `;
                  })
                  .join("");
              (g === 0 &&
                i !== "\u533F\u540D" &&
                i !== "\u70B9\u51FB\u767B\u5F55" &&
                (x += `<div style="text-align:center; padding:5px; color:#aaa;">...</div>
                              <div style="display:flex; justify-content:space-between; padding:12px; background:rgba(236,72,153,0.15); border: 1px solid var(--accent-pink); margin-bottom:8px; border-radius:12px;">
                                <span style="color:#fff; font-weight: 800;">??. ${i} (\u4F60)</span>
                                <span style="color:var(--accent-pink); font-weight:800;">${c}</span>
                              </div>`),
                (x +=
                  '<p style="text-align:center; color:rgba(255,255,255,0.4); font-size:10px; margin-top:15px; letter-spacing:1px;">(\u79BB\u7EBF\u7EF4\u5EA6\u6863\u6848)</p>'),
                (f.innerHTML = x));
            };
          if (typeof AV > "u") {
            a();
            return;
          }
          try {
            let g = await new AV.Query("PlayerScore")
              .descending("score")
              .limit(10)
              .find();
            if (g.length === 0) throw new Error("empty");
            let x = await new AV.Query("PlayerScore")
                .equalTo("username", i)
                .descending("score")
                .limit(1)
                .find(),
              T = x.length > 0 ? x[0].get("score") : c,
              _ =
                (await new AV.Query("PlayerScore")
                  .greaterThan("score", T)
                  .count()) + 1,
              N = g
                .map((C, D) => {
                  let z = C.get("username") === i;
                  return `
                    <div style="display:flex; justify-content:space-between; padding:12px; margin-bottom:8px; border-radius:12px; border: 1px solid transparent; ${z ? "background:rgba(236,72,153,0.15); border-color:var(--accent-pink);" : "background:rgba(255,255,255,0.05); border-color:var(--glass-border);"}">
                        <span style="color:#fff; font-weight: 800;">${D + 1}. ${C.get("username") || "\u533F\u540D"} ${z ? "(\u4F60)" : ""}</span>
                        <span style="color:var(--accent-pink); font-weight:800;">${C.get("score")}</span>
                    </div>
                `;
                })
                .join("");
            (!g.some((C) => C.get("username") === i) &&
              i !== "\u533F\u540D" &&
              i !== "\u70B9\u51FB\u767B\u5F55" &&
              (N += `<div style="text-align:center; padding:5px; color:#aaa;">...</div>
                              <div style="display:flex; justify-content:space-between; padding:12px; background:rgba(236,72,153,0.15); border: 1px solid var(--accent-pink); margin-bottom:8px; border-radius:12px;">
                                <span style="color:#fff; font-weight: 800;">${_}. ${i} (\u4F60)</span>
                                <span style="color:var(--accent-pink); font-weight:800;">${T}</span>
                              </div>`),
              (f.innerHTML = N));
          } catch {
            a();
          }
        },
      },
      t = {
        sound: localStorage.getItem("setting_sound") !== "false",
        vibration: localStorage.getItem("setting_vibration") !== "false",
        ambientVol: parseFloat(
          localStorage.getItem("setting_ambient_vol") || "0",
        ),
        storyTTS: localStorage.getItem("setting_story_tts") === "true",
      };
    class r {
      constructor() {
        ((this.lines = [
          {
            v: "zh-CN-YunyangNeural",
            t: "\u4E1C\u6C49\u672B\u5E74\uFF0C\u5929\u4E0B\u5927\u4E71\u3002\u9EC4\u5DFE\u8D3C\u5BC7\u56DB\u8D77\uFF0C\u767E\u59D3\u6D41\u79BB\u5931\u6240\u3002\u671D\u5EF7\u5F20\u699C\u62DB\u52DF\u4E49\u5175\uFF0C\u6709\u5FD7\u4E4B\u58EB\u7EB7\u7EB7\u54CD\u5E94\u3002",
          },
          {
            v: "zh-CN-YunxiNeural",
            t: "\u6211\u4E43\u4E2D\u5C71\u9756\u738B\u4E4B\u540E\uFF0C\u6C49\u666F\u5E1D\u9601\u4E0B\u7384\u5B59\uFF0C\u59D3\u5218\u540D\u5907\uFF0C\u5B57\u7384\u5FB7\u3002\u89C1\u5929\u4E0B\u82CD\u751F\u53D7\u82E6\uFF0C\u5E38\u6000\u5321\u6276\u6C49\u5BA4\u4E4B\u5FD7\uFF0C\u5948\u4F55\u529B\u5355\u52BF\u8584\uFF0C\u65E0\u4ECE\u65BD\u5C55\u554A\u3002",
          },
          {
            v: "zh-CN-YunyangNeural",
            t: "\u5218\u5907\u5728\u699C\u6587\u524D\u957F\u53F9\u4E00\u58F0\u3002\u5FFD\u95FB\u8EAB\u540E\u4E00\u4EBA\u5389\u58F0\u9AD8\u559D\u3002",
          },
          {
            v: "zh-CN-YunxiaNeural",
            t: "\u5927\u4E08\u592B\u4E0D\u4E0E\u56FD\u5BB6\u51FA\u529B\uFF0C\u5728\u8FD9\u91CC\u957F\u5401\u77ED\u53F9\uFF0C\u6709\u4EC0\u4E48\u7528\uFF01\u6211\u4E43\u71D5\u4EBA\u5F20\u98DE\uFF0C\u5B57\u7FFC\u5FB7\uFF0C\u4E16\u5C45\u6DBF\u90E1\uFF0C\u9887\u6709\u5E84\u7530\u3002\u4ECA\u613F\u4E0E\u4F60\u5171\u56FE\u5927\u4E8B\uFF01",
          },
          {
            v: "zh-CN-YunxiNeural",
            t: "\u6211\u867D\u6709\u6B64\u5FC3\uFF0C\u5948\u4F55\u6EE1\u8154\u70ED\u8840\uFF0C\u65E0\u5904\u6325\u6D12\u3002\u4ECA\u5F97\u58EE\u58EB\u76F8\u52A9\uFF0C\u5B9E\u4E43\u5929\u610F\uFF01",
          },
          {
            v: "zh-CN-YunyangNeural",
            t: "\u4E8C\u4EBA\u76F8\u8C08\u751A\u6B22\uFF0C\u9042\u5165\u6751\u4E2D\u9152\u9986\u996E\u9152\u3002\u6B63\u996E\u95F4\uFF0C\u4E00\u5927\u6C49\u63A8\u95E8\u800C\u5165\uFF0C\u8EAB\u9AD8\u4E5D\u5C3A\uFF0C\u987B\u957F\u4E8C\u5C3A\uFF0C\u9762\u5982\u91CD\u67A3\uFF0C\u5507\u82E5\u6D82\u8102\uFF0C\u76F8\u8C8C\u5802\u5802\uFF0C\u5A01\u98CE\u51DB\u51DB\u3002",
          },
          {
            v: "zh-CN-YunjianNeural",
            t: "\u5C0F\u4E8C\uFF0C\u5FEB\u659F\u9152\u6765\uFF01\u6211\u8981\u8D76\u53BB\u6295\u519B\uFF0C\u5148\u996E\u4E00\u7897\u58EE\u884C\u9152\u3002",
          },
          {
            v: "zh-CN-YunxiNeural",
            t: "\u58EE\u58EB\u8BF7\u8FC7\u6765\u540C\u5750\u3002\u6562\u95EE\u5C0A\u59D3\u5927\u540D\uFF1F",
          },
          {
            v: "zh-CN-YunjianNeural",
            t: "\u67D0\u59D3\u5173\u540D\u7FBD\uFF0C\u5B57\u4E91\u957F\uFF0C\u6CB3\u4E1C\u89E3\u826F\u4EBA\u6C0F\u3002\u56E0\u672C\u5904\u52BF\u8C6A\u501A\u52BF\u51CC\u4EBA\uFF0C\u88AB\u543E\u6740\u4E86\u3002\u9003\u96BE\u6C5F\u6E56\uFF0C\u4E94\u516D\u5E74\u77E3\u3002\u4ECA\u95FB\u6B64\u5904\u62DB\u519B\u7834\u8D3C\uFF0C\u7279\u6765\u5E94\u52DF\u3002",
          },
          {
            v: "zh-CN-YunxiaNeural",
            t: "\u597D\uFF01\u6B63\u5408\u6211\u610F\uFF01\u6211\u5E84\u540E\u6709\u4E00\u5EA7\u6843\u56ED\uFF0C\u82B1\u5F00\u6B63\u76DB\u3002\u660E\u65E5\u6211\u4E09\u4EBA\u4F55\u4E0D\u5C31\u5728\u56ED\u4E2D\u7ED3\u4E3A\u5144\u5F1F\uFF0C\u540C\u5FC3\u534F\u529B\uFF0C\u5171\u56FE\u5927\u4E8B\uFF1F",
          },
          {
            v: "zh-CN-YunyangNeural",
            t: "\u6B21\u65E5\uFF0C\u4E09\u4EBA\u6765\u5230\u5F20\u98DE\u5E84\u540E\u6843\u56ED\u3002\u4F46\u89C1\u6843\u82B1\u707F\u70C2\u5982\u9526\uFF0C\u843D\u82F1\u7F24\u7EB7\u3002\u5907\u4E0B\u4E4C\u725B\u767D\u9A6C\u796D\u793C\uFF0C\u711A\u9999\u518D\u62DC\uFF0C\u5BF9\u5929\u76DF\u8A93\u3002",
          },
          {
            v: "zh-CN-YunxiNeural",
            t: "\u5FF5\u5218\u5907\u3001\u5173\u7FBD\u3001\u5F20\u98DE\uFF0C\u867D\u7136\u5F02\u59D3\uFF0C\u65E2\u7ED3\u4E3A\u5144\u5F1F\uFF0C\u5219\u540C\u5FC3\u534F\u529B\uFF0C\u6551\u56F0\u6276\u5371\uFF0C\u4E0A\u62A5\u56FD\u5BB6\uFF0C\u4E0B\u5B89\u9ECE\u5EB6\u3002",
          },
          {
            v: "zh-CN-YunjianNeural",
            t: "\u4E0D\u6C42\u540C\u5E74\u540C\u6708\u540C\u65E5\u751F\u3002",
          },
          {
            v: "zh-CN-YunxiaNeural",
            t: "\u4F46\u613F\u540C\u5E74\u540C\u6708\u540C\u65E5\u6B7B\uFF01",
          },
          {
            v: "zh-CN-YunxiNeural",
            t: "\u7687\u5929\u540E\u571F\uFF0C\u5B9E\u9274\u6B64\u5FC3\u3002\u80CC\u4E49\u5FD8\u6069\uFF0C\u5929\u4EBA\u5171\u622E\uFF01",
          },
          {
            v: "zh-CN-YunyangNeural",
            t: "\u8A93\u6BD5\uFF0C\u62DC\u5218\u5907\u4E3A\u5144\uFF0C\u5173\u7FBD\u6B21\u4E4B\uFF0C\u5F20\u98DE\u4E3A\u5F1F\u3002\u6843\u56ED\u6625\u98CE\u6D69\u8361\uFF0C\u4E09\u4EBA\u4ECE\u6B64\u809D\u80C6\u76F8\u7167\uFF0C\u5171\u8D74\u5929\u4E0B\u3002",
          },
          {
            v: "zh-CN-YunxiaNeural",
            t: "\u5927\u54E5\u4E8C\u54E5\uFF01\u6211\u5F20\u98DE\u6563\u5C3D\u5BB6\u8D22\uFF0C\u62DB\u5F97\u4E61\u52C7\u4E09\u767E\u4F59\u4EBA\u3002\u5200\u67AA\u5251\u621F\uFF0C\u6837\u6837\u9F50\u5168\u3002\u968F\u65F6\u53EF\u4EE5\u51FA\u53D1\uFF01",
          },
          {
            v: "zh-CN-YunjianNeural",
            t: "\u5144\u957F\u653E\u5FC3\u3002\u5173\u67D0\u867D\u4E00\u4ECB\u6B66\u592B\uFF0C\u4F46\u65E2\u5DF2\u7ED3\u4E49\uFF0C\u4FBF\u5F53\u4EE5\u6027\u547D\u76F8\u62A5\u3002\u5200\u5C71\u706B\u6D77\uFF0C\u5728\u6240\u4E0D\u8F9E\u3002",
          },
          {
            v: "zh-CN-YunxiNeural",
            t: "\u6709\u4E8C\u4F4D\u8D24\u5F1F\u76F8\u52A9\uFF0C\u4F55\u6101\u5927\u4E8B\u4E0D\u6210\uFF1F\u4ECA\u65E5\u51FA\u53D1\uFF0C\u7834\u9EC4\u5DFE\uFF0C\u5B89\u793E\u7A37\uFF0C\u8FD8\u5929\u4E0B\u4E00\u4E2A\u592A\u5E73\uFF01",
          },
          {
            v: "zh-CN-YunyangNeural",
            t: "\u6843\u82B1\u7EB7\u98DE\u4E4B\u4E2D\uFF0C\u4E09\u9A91\u7EDD\u5C18\u800C\u53BB\u3002\u81EA\u6B64\uFF0C\u5218\u5173\u5F20\u4E09\u5144\u5F1F\u7684\u4F20\u5947\uFF0C\u6B63\u5F0F\u62C9\u5F00\u4E86\u6CE2\u6F9C\u58EE\u9614\u7684\u5E8F\u5E55\u3002\u540E\u4EBA\u6709\u8BD7\u8D5E\u66F0\uFF1A\u82F1\u96C4\u9732\u9896\u5728\u4ECA\u671D\uFF0C\u4E00\u8BD5\u77DB\u516E\u4E00\u8BD5\u5200\u3002\u521D\u51FA\u4FBF\u5C06\u5A01\u529B\u5C55\uFF0C\u4E09\u5206\u597D\u628A\u59D3\u540D\u6807\u3002",
          },
        ]),
          (this.novelID = parseInt(
            localStorage.getItem("current_novel_id") || "1",
          )),
          (this.novelTitle =
            localStorage.getItem("current_novel_title") ||
            "\u4E09\u56FD\u6F14\u4E49\xB7\u6843\u56ED\u7ED3\u4E49\u7247\u6BB5"),
          (this.cursor = parseInt(localStorage.getItem("novel_index") || "0")),
          (this.fetchCursor = this.cursor),
          (this.audioBufferArray = []),
          (this.isPlaying = !1),
          (this.prefetching = !1),
          (this.lastActive = Date.now()));
        let i = parseInt(localStorage.getItem("setting_idle_timeout") || "1");
        ((this.idleTimeout = i * 6e4),
          (this.ttsURL = "${API_BASE}/api/v1/tts/createStream"),
          (this.enabled = t.storyTTS),
          (this.loopSession = 1),
          this.initLibrary().then(() => {
            this.enabled && (this.startPrefetchLoop(), this.startPlayLoop());
          }),
          setInterval(() => {
            this.enabled &&
              this.isPlaying &&
              this.idleTimeout > 0 &&
              Date.now() - this.lastActive > this.idleTimeout &&
              this.currentAudio &&
              !this.currentAudio.paused &&
              (this.currentAudio.pause(),
              (this.isSpeaking = !1),
              this.updateUI(),
              window._showToast(
                "\u5DF2\u6682\u505C\u64AD\u62A5 (\u957F\u65F6\u95F4\u65E0\u64CD\u4F5C)",
              ));
          }, 5e3));
      }
      async initLibrary() {
        (!this.lines || this.lines.length === 0) &&
          (await this.loadNovel(this.novelID, this.novelTitle, this.cursor));
      }
      async loadNovel(i, c, a = null) {
        try {
          this.loopSession = (this.loopSession || 1) + 1;
          let n = this.loopSession;
          (this.currentAudio &&
            (this.currentAudio.pause(),
            this.currentAudio.removeAttribute("src"),
            (this.currentAudio = null)),
            this.audioBufferArray.forEach((x) => {
              x.url && URL.revokeObjectURL(x.url);
            }),
            (this.audioBufferArray = []),
            (this.isSpeaking = !1),
            (this.prefetching = !1),
            (this.isPlaying = !1),
            (this.novelID = i),
            (this.novelTitle = c),
            (this.cursor = a !== null ? a : 0),
            (this.fetchCursor = this.cursor),
            this.updateUI(),
            console.log(
              `[loadNovel] Session ${n} starting for Novel ${i} at cursor ${a}`,
            ));
          let g = await fetch(`${API_BASE}/api/novel/${i}`);
          if (g.ok) {
            let x = await g.json();
            if (this.loopSession !== n) return;
            ((this.lines = x),
              (this.cursor = (a !== null && a < x.length) ? a : 0),
              (this.fetchCursor = this.cursor),
              localStorage.setItem("current_novel_id", i),
              localStorage.setItem("current_novel_title", c),
              localStorage.setItem("novel_index",this.cursor.toString()), (()=>{let tok = localStorage.getItem("auth_token"); if(tok) { fetch(`${API_BASE}/api/state/save`, {method: "POST", headers: {"Content-Type":"application/json", "Authorization": `Bearer ${tok}`}, body: JSON.stringify({current_novel_id: this.novelID, novel_index: this.cursor, board_data: "null", score: 0})}).catch(()=>{}); }})(), void(0),
              this.updateUI(),
              this.enabled && (this.startPrefetchLoop(), this.startPlayLoop()));
          }
        } catch (n) {
          console.error("Failed to load novel:", n);
        }
      }
      heartbeat() {
        ((this.lastActive = Date.now()),
          this.enabled &&
            (this.isPlaying
              ? this.idleTimeout > 0 &&
                this.currentAudio &&
                this.currentAudio.paused &&
                !this.currentAudio.ended &&
                this.currentAudio
                  .play()
                  .then(() => {
                    ((this.isSpeaking = !0),
                      this.updateUI(),
                      window._showToast("\u5DF2\u6062\u590D\u64AD\u62A5"));
                  })
                  .catch((i) => console.warn(i))
              : this.startPlayLoop()));
      }
      toggle(i) {
        ((this.enabled = i),
          (t.storyTTS = i),
          localStorage.setItem("setting_story_tts", i),
          i
            ? (this.heartbeat(),
              this.currentAudio &&
              this.currentAudio.paused &&
              !this.currentAudio.ended
                ? ((this.isSpeaking = !0),
                  this.currentAudio
                    .play()
                    .catch((c) => console.warn("Failed to resume audio:", c)),
                  this.updateUI())
                : (this.startPrefetchLoop(), this.startPlayLoop()))
            : (this.currentAudio && this.currentAudio.pause(),
              (this.isSpeaking = !1),
              this.updateUI()));
      }
      async fetchTTS(i, c) {
        try {
          let a = await fetch(this.ttsURL, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ text: i, voice: c }),
          });
          if (!a.ok)
            return (
              console.error(
                `[TTS Error] Remote server returned HTTP ${a.status} for text:`,
                i.substring(0, 10) + "...",
              ),
              null
            );
          let n = await a.blob();
          return URL.createObjectURL(n);
        } catch (a) {
          return (console.error("[TTS Error] Network/Fetch failed:", a), null);
        }
      }
      updateUI() {
        let i = document.getElementById("player-title");
        i && (i.innerText = `${this.novelTitle}`);
        let c = document.getElementById("player-chapter");
        c &&
          (c.innerText = `\u7B2C ${this.cursor + 1} \u53E5 / \u5171 ${this.lines ? this.lines.length : "..."} \u53E5`);
        let a = document.getElementById("player-status-icon");
        a && (a.innerText = this.isSpeaking ? "\u23F8" : "\u25B6");
      }
      async startPrefetchLoop() {
        if (this.prefetching) return;
        this.prefetching = !0;
        let i = this.loopSession;
        for (; this.enabled && this.loopSession === i; ) {
          if (
            this.idleTimeout > 0 &&
            Date.now() - this.lastActive > this.idleTimeout
          ) {
            await new Promise((n) => setTimeout(n, 1e3));
            continue;
          }
          if (this.audioBufferArray.length >= 2) {
            await new Promise((n) => setTimeout(n, 200));
            continue;
          }
          let c = this.lines[this.fetchCursor];
          if (!c) {
            await new Promise((n) => setTimeout(n, 1e3));
            continue;
          }
          let a = await this.fetchTTS(c.t, c.v);
          if (this.loopSession !== i) break;
          if (a) {
            let n = Math.random().toString(36).substr(2, 9),
              g = new Audio(a);
            ((g.preload = "auto"),
              this.audioBufferArray.push({ url: a, id: n, obj: g }),
              (this.fetchCursor = (this.fetchCursor + 1) % this.lines.length));
          } else
            (console.error("Skipping failed sentence generation..."),
              this.audioBufferArray.push({ url: null, id: "fail", obj: null }),
              (this.fetchCursor = (this.fetchCursor + 1) % this.lines.length),
              await new Promise((n) => setTimeout(n, 1e3)));
        }
        this.loopSession === i && (this.prefetching = !1);
      }
      async startPlayLoop() {
        if (this.isPlaying) return;
        this.isPlaying = !0;
        let i = this.loopSession;
        for (; this.enabled && this.loopSession === i; ) {
          if (this.audioBufferArray.length === 0) {
            (this.isSpeaking && ((this.isSpeaking = !1), this.updateUI()),
              await new Promise((a) => setTimeout(a, 100)));
            continue;
          }
          let c = this.audioBufferArray.shift();
          if (!c.obj) {
            (this.lines &&
              this.lines.length > 0 &&
              ((this.cursor = (this.cursor + 1) % this.lines.length),
              localStorage.setItem("novel_index",this.cursor.toString()), (()=>{let tok = localStorage.getItem("auth_token"); if(tok) { fetch(`${API_BASE}/api/state/save`, {method: "POST", headers: {"Content-Type":"application/json", "Authorization": `Bearer ${tok}`}, body: JSON.stringify({current_novel_id: this.novelID, novel_index: this.cursor, board_data: "null", score: 0})}).catch(()=>{}); }})(), void(0)),
              this.updateUI());
            continue;
          }
          if (
            ((this.isSpeaking = !0),
            this.updateUI(),
            await new Promise((a) => {
              let n = c.obj;
              ((this.currentAudio = n),
                (n.onended = () => a()),
                (n.onerror = () => a()));
              let g = n.play();
              g !== void 0 &&
                g.catch((x) => {
                  if (x.name === "NotAllowedError") {
                    let T = document.getElementById("autoplay-mask");
                    T && T.classList.remove("hidden");
                    let _ = document.getElementById("btn-unblock-audio");
                    _ &&
                      (_.onclick = () => {
                        (T.classList.add("hidden"),
                          n
                            .play()
                            .then(() => a())
                            .catch(() => a()));
                      });
                  } else x.name !== "AbortError" && a();
                });
            }),
            this.loopSession !== i)
          )
            break;
          ((this.currentAudio = null),
            c.url && URL.revokeObjectURL(c.url),
            this.lines &&
              this.lines.length > 0 &&
              ((this.cursor = (this.cursor + 1) % this.lines.length),
              localStorage.setItem("novel_index",this.cursor.toString()), (()=>{let tok = localStorage.getItem("auth_token"); if(tok) { fetch(`${API_BASE}/api/state/save`, {method: "POST", headers: {"Content-Type":"application/json", "Authorization": `Bearer ${tok}`}, body: JSON.stringify({current_novel_id: this.novelID, novel_index: this.cursor, board_data: "null", score: 0})}).catch(()=>{}); }})(), void(0)));
        }
        this.loopSession === i && ((this.isPlaying = !1), this.updateUI());
      }
    }
    let l = new r(),
      y = null,
      v = () => {
        let f = localStorage.getItem("auth_token");
        if (!f) return;
        let i = {
          board_data: JSON.stringify(p.board),
          score: p.score,
          novel_index: l.cursor,
          current_novel_id: l.novelID,
        };
        fetch("${API_BASE}/api/state/save", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${f}`,
          },
          body: JSON.stringify(i),
          keepalive: !0,
        }).catch(() => {});
      },
      A = () => {
        (y && clearTimeout(y), (y = setTimeout(v, 1e3)));
      };
    (document.addEventListener("visibilitychange", () => {
      document.hidden && v();
    }),
      localStorage.getItem("score_version_v2") ||
        (localStorage.removeItem("bestScore_premium"),
        localStorage.setItem("score_version_v2", "1"),
        (p.bestScore = 0)));
    let u = null,
      w = () => {
        (u || (u = new (window.AudioContext || window.webkitAudioContext)()),
          u.state === "suspended" && u.resume());
      };
    (w(),
      (window._showToast = (f) => {
        let i = document.getElementById("sys-toast");
        (i ||
          ((i = document.createElement("div")),
          (i.id = "sys-toast"),
          (i.style.cssText =
            "position:fixed; bottom:120px; left:50%; transform:translateX(-50%); background:rgba(0,0,0,0.8); color:#auto; padding:12px 24px; border-radius:30px; font-size:14px; color:#fff; word-break:keep-all; z-index:9999; opacity:0; transition:opacity 0.3s; pointer-events:none;"),
          document.body.appendChild(i)),
          (i.innerText = f),
          (i.style.opacity = "1"),
          clearTimeout(i._to),
          (i._to = setTimeout(() => (i.style.opacity = "0"), 3e3)));
      }));
    let h = (f, i = "sine", c = 0.1) => {
        if (t.sound) {
          w();
          try {
            let a = u.createOscillator(),
              n = u.createGain();
            ((a.type = i),
              (a.frequency.value = f),
              n.gain.setValueAtTime(0.1, u.currentTime),
              n.gain.exponentialRampToValueAtTime(1e-4, u.currentTime + c),
              a.connect(n),
              n.connect(u.destination),
              a.start(),
              a.stop(u.currentTime + c));
          } catch {}
        }
      },
      E = (f) => {
        if (!t.sound) return;
        w();
        let i = [
            0, 0, 261.63, 293.66, 329.63, 392, 440, 523.25, 587.33, 659.25,
            783.99, 880, 1046.5, 1174.66, 1318.51,
          ],
          c = Math.min(Math.floor(Math.log2(f)), i.length - 1),
          a = i[c] || 300;
        try {
          let n = u.createOscillator(),
            g = u.createGain();
          ((n.type = "sine"),
            n.frequency.setValueAtTime(a, u.currentTime),
            n.frequency.exponentialRampToValueAtTime(
              a * 2.5,
              u.currentTime + 0.15,
            ),
            g.gain.setValueAtTime(0, u.currentTime),
            g.gain.linearRampToValueAtTime(0.3, u.currentTime + 0.02),
            g.gain.exponentialRampToValueAtTime(0.001, u.currentTime + 0.2),
            n.connect(g),
            g.connect(u.destination),
            n.start(),
            n.stop(u.currentTime + 0.25));
        } catch {}
      },
      m = { oscs: [], gains: [], masterGain: null },
      M = null,
      $ = () => {
        (m.oscs.forEach((f) => {
          try {
            f.stop();
          } catch {}
        }),
          (m.oscs = []),
          (m.gains = []),
          (M = null));
      },
      j = (f) => {
        if (!t.sound || !u || M === f) return;
        ($(), (M = f));
        let i = u.createGain();
        ((i.gain.value = t.ambientVol),
          i.connect(u.destination),
          (m.masterGain = i));
        let c = (a, n = "sine", g = 0.5) => {
          let x = u.createOscillator(),
            T = u.createGain();
          return (
            (x.type = n),
            (x.frequency.value = a),
            (T.gain.value = g),
            x.connect(T),
            T.connect(i),
            x.start(),
            m.oscs.push(x),
            m.gains.push(T),
            x
          );
        };
        f === "classic" || f === "normal"
          ? (c(220, "sine", 0.3),
            c(330.5, "sine", 0.15),
            c(440.2, "sine", 0.08))
          : f === "disassemble"
            ? (c(55, "sine", 0.4),
              c(82.5, "triangle", 0.2),
              c(110, "sine", 0.1))
            : f === "reassemble" &&
              (c(293.66, "sine", 0.25),
              c(392, "sine", 0.15),
              c(523.25, "sine", 0.1));
      },
      q = (f) => {
        if (!t.sound || t.ambientVol <= 0) {
          $();
          return;
        }
        w();
        let i = f.mode === "loop" ? f.phase : "classic";
        (j(i), m.masterGain && (m.masterGain.gain.value = t.ambientVol));
      },
      W = async () => {
        try {
          (await navigator.mediaDevices.enumerateDevices())
            .filter((a) => a.kind === "audiooutput")
            .some((a) => {
              let n = a.label.toLowerCase();
              return (
                n.includes("headphone") ||
                n.includes("earbud") ||
                n.includes("bluetooth") ||
                n.includes("\u8033\u673A")
              );
            })
            ? (console.log("Headphones detected, silent TTS trigger."),
              l.toggle(!0))
            : (console.log(
                "No headphones detected. Proceeding anyway, will be blocked by mask if needed.",
              ),
              l.toggle(!0));
        } catch (f) {
          (console.warn("enumerateDevices rejected:", f), l.toggle(!0));
        }
      },
      G = async (f) => {
        let i = document.getElementById("tile-container");
        if (p.phaseJustCleared || i.classList.contains("targeting")) return;
        let { moved: c, mergedTiles: a, combo: n } = p.move(f);
        if (c) {
          if ((l.heartbeat(), A(), e.render(p, a), a.length > 0)) {
            let g = Math.max(...a.map((x) => x.value));
            (E(g),
              t.vibration &&
                navigator.vibrate &&
                (g >= 512
                  ? (e.shake(), navigator.vibrate([80, 30, 40]))
                  : g >= 128
                    ? (e.shake(), navigator.vibrate([50, 20, 30]))
                    : g >= 64
                      ? navigator.vibrate(30)
                      : navigator.vibrate(10)),
              [512, 1024, 2048].includes(g) &&
                [g * 2, g * 4, g * 8, g * 16].forEach((x, T) =>
                  setTimeout(() => E(x), T * 150),
                ));
          }
          ((p.won || p.phaseJustCleared) &&
            s.saveScore(localStorage.getItem("player_name"), p.score),
            p.over &&
              (await e.playTransition("defeat"),
              alert(
                "\u7EF4\u5EA6\u5D29\u584C\uFF01\u91CD\u65B0\u542F\u52A8...",
              ),
              p.reset(),
              e.render(p)));
        }
      };
    ((() => {
      let f = (o) => {
          let d = document.getElementById("btn-admin");
          d &&
            ([
              "admin",
              "Admin",
              "Root",
              "AntigravityUser",
              "TestUser",
              "Admin2048",
              "developer",
            ].includes(o)
              ? d.classList.remove("hidden")
              : d.classList.add("hidden"));
        },
        i = localStorage.getItem("player_name");
      i &&
        ((document.getElementById("display-name").innerText = i),
        (document.getElementById("user-title").innerText =
          "\u7EF4\u5EA6\u65C5\u884C\u4E2D..."),
        f(i));
      let c = document.getElementById("login-trigger"),
        a = document.getElementById("modal-login"),
        n = document.getElementById("tab-login"),
        g = document.getElementById("tab-register"),
        x = document.getElementById("form-login"),
        T = document.getElementById("form-register"),
        _ = (o) => {
          o
            ? ((n.style.color = "var(--accent-pink)"),
              (n.style.borderBottom = "2px solid var(--accent-pink)"),
              (g.style.color = "rgba(255,255,255,0.5)"),
              (g.style.borderBottom = "2px solid transparent"),
              x.classList.remove("hidden"),
              T.classList.add("hidden"))
            : ((g.style.color = "var(--accent-pink)"),
              (g.style.borderBottom = "2px solid var(--accent-pink)"),
              (n.style.color = "rgba(255,255,255,0.5)"),
              (n.style.borderBottom = "2px solid transparent"),
              T.classList.remove("hidden"),
              x.classList.add("hidden"));
        };
      (n && (n.onclick = () => _(!0)),
        g && (g.onclick = () => _(!1)),
        c &&
          (c.onclick = () => {
            a.classList.remove("hidden");
            let o = localStorage.getItem("player_phone") || "";
            ((document.getElementById("login-phone").value = o),
              (document.getElementById("reg-phone").value = o),
              _(!0));
          }),
        (document.getElementById("btn-login-cancel").onclick = () =>
          a.classList.add("hidden")));
      let N = async (o, d) => {
        (localStorage.setItem("auth_token", o),
          localStorage.setItem("player_phone", d));
        let S = d.substring(0, 3) + "****" + d.substring(7);
        ((document.getElementById("display-name").innerText = "\u{1F4F1} " + S),
          (document.getElementById("user-title").innerText =
            "\u591A\u7AEF\u540C\u6B65\u5DF2\u5F00\u542F"),
          a.classList.add("hidden"),
          h(880, "sine", 0.2));
        try {
          let I = await (
            await fetch("${API_BASE}/api/state/load", {
              headers: { Authorization: `Bearer ${o}` },
            })
          ).json();
          if (I.found) {
            ((p.board = JSON.parse(I.board_data)),
              (p.score = I.score),
              e.render(p));
            let k = I.current_novel_id || 1,
              P = I.novel_index || 0,
              L =
                I.novel_title ||
                "\u4E09\u56FD\u6F14\u4E49\xB7\u8FDE\u8F7D\u4E2D";
            (await l.loadNovel(k, L, P),
              console.log(
                `Remote state loaded successfully. Novel: ${L} (ID: ${k}) at index ${P}`,
              ));
          }
        } catch (b) {
          console.warn("Could not load state cleanly", b);
        }
      };
      ((document.getElementById("btn-login-submit").onclick = async () => {
        let o = document.getElementById("login-phone").value.trim(),
          d = document.getElementById("login-password").value;
        if (!o || o.length < 11)
          return alert(
            "\u8BF7\u8F93\u5165\u6709\u6548\u7684 11 \u4F4D\u624B\u673A\u53F7\u7801\u3002",
          );
        if (!d) return alert("\u8BF7\u8F93\u5165\u5BC6\u7801");
        try {
          let S = await fetch("${API_BASE}/api/auth/login", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ phone: o, password: d }),
            }),
            b = await S.json();
          S.ok && b.token
            ? await N(b.token, o)
            : alert(b.error || "\u767B\u5F55\u9A8C\u8BC1\u5931\u8D25");
        } catch (S) {
          alert(
            "\u7F51\u7EDC\u6216 API \u8C03\u7528\u5931\u8D25: " + S.message,
          );
        }
      }),
        (document.getElementById("btn-register-submit").onclick = async () => {
          let o = document.getElementById("reg-phone").value.trim(),
            d = document.getElementById("reg-password").value,
            S = document.getElementById("reg-password-confirm").value;
          if (!o || o.length < 11)
            return alert(
              "\u8BF7\u8F93\u5165\u6709\u6548\u7684 11 \u4F4D\u624B\u673A\u53F7\u7801\u3002",
            );
          if (d.length < 6)
            return alert(
              "\u4E3A\u4E86\u7EF4\u5EA6\u5B89\u5168\uFF0C\u8BF7\u8BBE\u7F6E\u81F3\u5C11 6 \u4F4D\u7684\u5BC6\u7801\u3002",
            );
          if (d !== S)
            return alert(
              "\u4E24\u6B21\u8F93\u5165\u7684\u5BC6\u7801\u4E0D\u4E00\u81F4\uFF01",
            );
          try {
            let b = await fetch("${API_BASE}/api/auth/register", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ phone: o, password: d }),
              }),
              I = await b.json();
            b.ok && I.token
              ? (alert(
                  "\u6CE8\u518C\u6210\u529F\uFF01\u5373\u5C06\u540C\u6B65\u8FDB\u5EA6...",
                ),
                await N(I.token, o),
                A())
              : alert(I.error || "\u6CE8\u518C\u5931\u8D25");
          } catch (b) {
            alert(
              "\u7F51\u7EDC\u6216 API \u8C03\u7528\u5931\u8D25: " + b.message,
            );
          }
        }));
      let B = (o, d) => {
        let S = document.getElementById(o);
        S && (S.onclick = d);
      };
      B("player-mute-btn", () => {
        let o = !l.enabled;
        (l.toggle(o),
          (document.getElementById("toggle-story").checked = o),
          (document.getElementById("player-mute-btn").innerText = o
            ? "\u{1F50A}"
            : "\u{1F507}"));
      });
      let C = document.getElementById("toggle-sound"),
        D = document.getElementById("toggle-vibration"),
        z = document.getElementById("toggle-story"),
        R = document.getElementById("idle-timeout");
      if (
        (C && (C.checked = t.sound),
        D && (D.checked = t.vibration),
        z && (z.checked = t.storyTTS),
        R)
      ) {
        let o = parseInt(localStorage.getItem("setting_idle_timeout") || "1");
        ((R.value = o),
          (document.getElementById("idle-timeout-label").innerText =
            o == 0 ? "\u6C38\u4E0D\u505C\u6B62" : o + " \u5206\u949F"));
      }
      (B("btn-settings", () =>
        document.getElementById("modal-settings").classList.remove("hidden"),
      ),
        B("close-settings", () => {
          (C && (t.sound = C.checked),
            D && (t.vibration = D.checked),
            z && l.toggle(z.checked));
          let o = document.getElementById("ambient-volume");
          if ((o && (t.ambientVol = parseFloat(o.value)), R)) {
            let d = parseInt(R.value);
            (localStorage.setItem("setting_idle_timeout", d),
              (l.idleTimeout = d * 6e4));
          }
          (localStorage.setItem("setting_sound", t.sound),
            localStorage.setItem("setting_vibration", t.vibration),
            localStorage.setItem("setting_ambient_vol", t.ambientVol),
            document.getElementById("modal-settings").classList.add("hidden"),
            t.sound ? q(p) : $());
        }),
        B("btn-admin", () =>
          document.getElementById("admin-panel").classList.toggle("hidden"),
        ),
        B("btn-leaderboard", () => {
          (document
            .getElementById("modal-leaderboard")
            .classList.remove("hidden"),
            s.loadLeaderboard());
        }),
        B("close-leaderboard", () =>
          document.getElementById("modal-leaderboard").classList.add("hidden"),
        ),
        B("restart-btn", () => {
          confirm("\u91CD\u7F6E\u65F6\u95F4\u7EBF\uFF1F") &&
            (p.reset(), e.render(p));
        }),
        B("btn-next-phase", () => {
          window._nextStageCallback &&
            (window._nextStageCallback(),
            document
              .getElementById("modal-phase-success")
              .classList.add("hidden"),
            e.render(p));
        }),
        B("item-clear", () => {
          let o = document.getElementById("tile-container");
          if (o.classList.contains("targeting")) {
            o.classList.remove("targeting");
            return;
          }
          let d = document.querySelector("#item-clear .count"),
            S = parseInt(d.innerText);
          if (S > 0) {
            o.classList.add("targeting");
            let b = (I) => {
              I.stopPropagation();
              let k = I.target.closest(".tile");
              if (k && !k.classList.contains("tile-anchor")) {
                let P = parseInt(k.id.replace("tile-", ""));
                for (let L = 0; L < p.size; L++)
                  for (let O = 0; O < p.size; O++)
                    p.board[L][O]?.id === P &&
                      p.clearTile(L, O) &&
                      ((d.innerText = S - 1),
                      h(100, "sawtooth", 0.1),
                      e.render(p));
              }
              (o.classList.remove("targeting"),
                o.removeEventListener("click", b, !0));
            };
            o.addEventListener("click", b, !0);
          }
        }),
        B("item-reverse", () => {
          let o = document.querySelector("#item-reverse .count"),
            d = parseInt(o.innerText);
          d > 0 &&
            ((p.phase =
              p.phase === "disassemble" ? "reassemble" : "disassemble"),
            (o.innerText = d - 1),
            e.render(p),
            h(600, "sine", 0.2));
        }));
      let V = document.getElementById("modal-library"),
        H = document.getElementById("library-content"),
        J = async () => {
          try {
            H.innerHTML =
              '<p style="text-align:center;">\u540C\u6B65\u4E66\u5E93\u4E2D...</p>';
            let o = localStorage.getItem("auth_token") || "",
              d = await fetch("${API_BASE}/api/novels", {
                headers: o ? { Authorization: `Bearer ${o}` } : {},
              });
            if (!d.ok) {
              let b = await d.text();
              throw (
                console.error("fetch /api/novels failed:", d.status, b),
                new Error(`HTTP ${d.status}: ${b}`)
              );
            }
            let S = await d.json();
            if (!S || S.length === 0) {
              H.innerHTML =
                '<p style="text-align:center;">\u6682\u65E0\u516C\u5F00\u5C0F\u8BF4\u4E66\u7C4D</p>';
              return;
            }
            H.innerHTML = S.map((b, I) => {
              let k = b.id === l.novelID,
                P = k
                  ? "background:rgba(236,72,153,0.15); border: 2px solid var(--accent-pink);"
                  : "background:rgba(255,255,255,0.05); border: 2px solid transparent;",
                L =
                  b.total_paragraphs > 0
                    ? Math.floor(
                        ((b.history_index || 0) / b.total_paragraphs) * 100,
                      )
                    : 0,
                O = (I * 45) % 360;
              return `
                    <div style="display:flex; flex-direction:column; padding:0; align-items: stretch; border-radius:12px; overflow:hidden; cursor:pointer; transition: all 0.2s; ${P}"
                         onclick="window._readBook(${b.id}, '${b.title}', ${b.history_index || 0})"
                         onmouseover="this.style.transform='translateY(-5px)'; this.style.boxShadow='0 10px 20px rgba(0,0,0,0.5)';"
                         onmouseout="this.style.transform='translateY(0)'; this.style.boxShadow='none';">
                        
                        <!-- Book Cover Placehoder -->
                        <div style="height: 120px; background: linear-gradient(135deg, hsl(${O}, 60%, 40%), hsl(${O + 40}, 60%, 20%)); position: relative; display: flex; align-items: center; justify-content: center;">
                             <div style="position: absolute; top: 8px; right: 8px; background: rgba(0,0,0,0.6); border-radius: 4px; padding: 2px 6px; font-size: 10px;">ID ${b.id}</div>
                             <span style="font-size: 32px; filter: drop-shadow(0 2px 4px rgba(0,0,0,0.5));">\u{1F4DA}</span>
                        </div>

                        <!-- Book Info -->
                        <div style="padding: 10px; display: flex; flex-direction: column; flex: 1; justify-content: space-between;">
                            <div>
                                <div style="color:#fff; font-weight: 800; font-size: 14px; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; text-overflow: ellipsis; line-height: 1.3; margin-bottom: 5px;">${b.title}</div>
                                <div style="color:rgba(255,255,255,0.5); font-size:11px; margin-bottom: 8px;">\u63D0\u501F: ${b.uploader}</div>
                            </div>
                            
                            <!-- Progress Bar -->
                            <div style="width: 100%; height: 4px; background: rgba(255,255,255,0.1); border-radius: 2px; overflow: hidden; margin-bottom: 4px;">
                                <div style="width: ${L}%; height: 100%; background: var(--accent-pink);"></div>
                            </div>
                            <div style="display:flex; justify-content: space-between; font-size: 10px; color: ${k ? "var(--accent-pink)" : "rgba(255,255,255,0.5)"}; font-weight: bold;">
                                <span>${k ? "\u25B6 \u6B63\u5728\u9605\u8BFB" : ""}</span>
                                <span>\u8FDB\u5EA6 ${L}%</span>
                            </div>
                        </div>
                    </div>
                    `;
            }).join("");
          } catch (o) {
            (console.error("fetchLibrary error", o),
              (H.innerHTML = `<p style="text-align:center; color: #ff4757;">\u8FDE\u63A5\u516C\u5171\u4E66\u5E93\u5931\u8D25<br><span style="font-size:10px; opacity:0.7">${o.message}</span></p>`));
          }
        };
      ((window._readBook = async (o, d, S = null) => {
        if ((await l.loadNovel(o, d, S), !l.enabled)) {
          l.toggle(!0);
          let b = document.getElementById("toggle-story");
          b && (b.checked = !0);
          let I = document.getElementById("player-mute-btn");
          I && (I.innerText = "\u{1F50A}");
        }
        (l.heartbeat(), A(), V.classList.add("hidden"));
      }),
        B("btn-library", () => {
          (V.classList.remove("hidden"), J());
        }),
        B("player-info", () => {
          (V.classList.remove("hidden"), J());
        }),
        B("close-library", () => V.classList.add("hidden")),
        B("btn-upload-novel", async () => {
          let o = localStorage.getItem("auth_token");
          if (!o)
            return alert(
              "\u8BF7\u5148\u9A8C\u8BC1\u60A8\u7684\u624B\u673A\u8EAB\u4EFD\u540E\u65B9\u53EF\u8FDB\u884C\u957F\u7BC7\u4E0A\u4F20\u8D21\u732E\u3002",
            );
          let d = document.getElementById("upload-novel-title").value.trim(),
            S = document.getElementById("upload-novel-file");
          if (!d) return alert("\u8BF7\u8F93\u5165\u4E66\u540D");
          if (S.files.length === 0)
            return alert(
              "\u8BF7\u9009\u62E9\u8981\u4E0A\u4F20\u7684 TXT \u6587\u4EF6",
            );
          let b = S.files[0];
          if (b.size > 5 * 1024 * 1024)
            return alert("TXT \u6587\u4EF6\u4E0D\u53EF\u8D85\u8FC7 5MB");
          let I = new FormData();
          (I.append("title", d), I.append("file", b));
          let k = document.getElementById("btn-upload-novel");
          ((k.innerText = "\u4E0A\u4F20\u89E3\u6790\u4E2D..."),
            (k.disabled = !0));
          try {
            let P = await fetch("${API_BASE}/api/novel/upload", {
                method: "POST",
                headers: { Authorization: `Bearer ${o}` },
                body: I,
              }),
              L = await P.json();
            P.ok
              ? (alert(
                  "\u4E0A\u4F20\u6210\u529F\uFF0C\u5DF2\u5F55\u5165\u516C\u5171\u7EF4\u5EA6\u4E66\u5E93\uFF01",
                ),
                (document.getElementById("upload-novel-title").value = ""),
                (S.value = ""),
                J())
              : alert(
                  "\u4E0A\u4F20\u53D7\u963B\uFF1A" +
                    (L.error || "\u672A\u77E5\u5F02\u5E38"),
                );
          } catch (P) {
            alert(
              "\u7F51\u7EDC\u6216 API \u8C03\u7528\u5931\u8D25: " + P.message,
            );
          } finally {
            ((k.innerText = "\u4E0A\u4F20\u8D21\u732E"), (k.disabled = !1));
          }
        }),
        (window.admin = {
          jump: (o) => {
            (p.jumpToStage(o),
              e.render(p),
              document.getElementById("admin-panel").classList.add("hidden"));
          },
          addItems: () =>
            document
              .querySelectorAll(".item-slot .count")
              .forEach((o) => (o.innerText = "99")),
          clearBoard: () => {
            (p.initBoard(), e.render(p));
          },
        }),
        (window.onkeydown = (o) => {
          let d = {
            ArrowUp: "up",
            ArrowDown: "down",
            ArrowLeft: "left",
            ArrowRight: "right",
          }[o.key];
          d && (o.preventDefault(), G(d));
        }));
      let F, X;
      ((window.ontouchstart = (o) => {
        ((F = o.touches[0].clientX), (X = o.touches[0].clientY));
      }),
        (window.ontouchend = (o) => {
          let d = o.changedTouches[0].clientX - F,
            S = o.changedTouches[0].clientY - X;
          Math.max(Math.abs(d), Math.abs(S)) > 30 &&
            G(
              Math.abs(d) > Math.abs(S)
                ? d > 0
                  ? "right"
                  : "left"
                : S > 0
                  ? "down"
                  : "up",
            );
        }),
        typeof AV < "u" &&
          AV.init({
            appId: "hV9NfHh3Xv6R3P7yH3v9",
            appKey: "X3H8v9NfHh3Xv6R3",
            serverURL: "https://hv9nfhh3.api.lncldglobal.com",
          }));
    })(),
      e.render(p),
      q(p),
      t.sound || $(),
      W());
  });
})();
