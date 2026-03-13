// ======================================
// 渲染管理器 (Renderer.js)
// 职责：处理游戏所有的 UI 渲染、粒子动画、界面提示框
// ======================================

export class Renderer {
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
          (()=>{
    let maxTile = e.getMaxTileValue();
    let scoreProgress = (e.score / 20000) * 100;
    let tileProgress = (Math.log2(maxTile) / 11) * 100; 
    s = Math.max(scoreProgress, tileProgress);
})());
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
              (this.nextPhaseInfo.innerText = `\u5373\u5C06\u8FDB\u5165\uFF1A\u3010\u62C6\u89E3\u9636\u6BB5\u3011\n\u76EE\u6807\uFF1A\u5C06\u6240\u6709\u7269\u8D28\u5F52 2\uFF08\u71B5\u51CF\uFF09\u3002`),
              (window._nextStageCallback = () => e.jumpToStage("loop_1")))
            : ((this.successTitle.innerText =
                "\u9636\u6BB5\u4EFB\u52A1\u5B8C\u6210\uFF01"),
              (this.successMsg.innerText =
                "\u903B\u8F91\u5C4F\u969C\u5DF2\u74E6\u89E3\u3002"),
              (this.nextPhaseInfo.innerText = `\u5373\u5C06\u8FDB\u5165\uFF1A\u3010\u91CD\u6784\u9636\u6BB5\u3011\n\u76EE\u6807\uFF1A\u5728\u4E2D\u5FC3\u5468\u56F4\u5408\u6210 4 \u4E2A 512\u3002`),
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
  }
