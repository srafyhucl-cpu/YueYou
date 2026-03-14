// ======================================
// 渲染管理器 (Renderer.js)
// 职责：处理游戏所有的 UI 渲染、粒子动画
// （已精简：移除高维模式动画和阶段通关弹窗）
// ======================================

export class Renderer {
    constructor() {
        // 绑定 DOM 元素引用
        this.viewport = document.getElementById("game-viewport");
        this.app = document.getElementById("app");
        this.gridBg = document.getElementById("grid-bg");
        this.tileContainer = document.getElementById("tile-container");
        this.effectsContainer = document.getElementById("effects-container");
        this.scoreElement = document.getElementById("score");
        this.bestScoreElement = document.getElementById("best-score");
        this.maxComboElement = document.getElementById("max-combo");
        this.comboDisplay = document.getElementById("combo-display");
        
        // 由于阶段相关的进度条和标签已经不再需要，但在 HTML 里还没删，所以这里加上宽容处理
        this.progressBar = document.getElementById("phase-progress");
        this.phaseLabel = document.getElementById("phase-label");
        this.phaseTag = document.getElementById("phase-tag");
    }
    
    render(e, s = []) {
        if (!this.tileContainer) return;
        
        // 渲染一次背景格子
        if(this.gridBg && this.gridBg.children.length === 0) {
            this.renderGridBg(e.size);
        }
        
        let t = new Set();
        e.board.forEach((l, y) => {
            l.forEach((v, A) => {
                if(v) {
                    t.add(v.id);
                    this.updateTileDOM(
                        v,
                        y,
                        A,
                        e.size,
                        s.find((u) => u.r === y && u.c === A)
                    );
                }
            });
        });
        
        Array.from(this.tileContainer.children).forEach((l) => {
            let y = parseInt(l.id.replace("tile-", ""));
            if(!t.has(y)) l.remove();
        });
        
        if(s.length > 0) {
            s.forEach((l) => this.createSplash(l, e.size));
            this.showCombo(e.combo);
        } else {
            this.hideCombo();
        }
        
        if(this.scoreElement) this.scoreElement.innerText = e.score || 0;
        let r = e.bestScore && !isNaN(e.bestScore) ? e.bestScore : 0;
        if(this.bestScoreElement) this.bestScoreElement.innerText = Math.max(e.score || 0, r);
        if(this.maxComboElement) this.maxComboElement.innerText = e.maxCombo || 0;
        
        this.updateProgress(e);
    }
    
    renderGridBg(e) {
        if (!this.gridBg) return;
        this.gridBg.innerHTML = "";
        let s = e * e;
        for (let t = 0; t < s; t++) {
            let r = document.createElement("div");
            r.className = "grid-cell";
            this.gridBg.appendChild(r);
        }
    }
    
    updateTileDOM(e, s, t, r, l) {
        let y = document.getElementById(`tile-${e.id}`);
        if(!y) {
            y = document.createElement("div");
            y.id = `tile-${e.id}`;
            this.tileContainer.appendChild(y);
        }
        y.className = `tile tile-${e.value} ${l ? "tile-merged" : ""}`;
        y.innerText = e.value;
        let v = 100 / r;
        y.style.top = `${s * v}%`;
        y.style.left = `${t * v}%`;
        y.style.width = `calc(${v}% - 10px)`;
        y.style.height = `calc(${v}% - 10px)`;
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
            w.className = `particle${h ? " large" : ""}${E ? " glow" : ""}`;
            w.style.top = `${(e + 0.5) * l}%`;
            w.style.left = `${(s + 0.5) * l}%`;
            let m = 80 + y * 10,
                M = (Math.random() - 0.5) * m,
                $ = (Math.random() - 0.5) * m;
            w.style.setProperty("--target-transform", `translate(${M}px, ${$}px)`);
            let j = A + (Math.random() - 0.5) * 40;
            w.style.background = `hsl(${j}, 80%, ${60 + Math.random() * 20}%)`;
            w.style.color = `hsl(${j}, 80%, 70%)`;
            this.effectsContainer.appendChild(w);
            setTimeout(() => w.remove(), h ? 800 : 600);
        }
    }
    
    shake() {
        if(this.viewport) {
            this.viewport.classList.add("shake");
            setTimeout(() => this.viewport.classList.remove("shake"), 400);
        }
    }
    
    showCombo(e) {
        if(e < 2 || !this.comboDisplay) return;
        this.comboDisplay.innerText = `连击 x${e}`;
        this.comboDisplay.style.opacity = "1";
        this.comboDisplay.style.transform = `translate(-50%, -50%) scale(${1 + Math.min(e, 5) * 0.1})`;
    }
    
    hideCombo() {
        if(this.comboDisplay) this.comboDisplay.style.opacity = "0";
    }
    
    updateProgress(e) {
        if(this.phaseTag) this.phaseTag.innerText = "无尽推演";
        if(this.phaseLabel) this.phaseLabel.innerText = "挑战进展";
        let s = 0;
        if (e.score > 0 || e.combo > 0 || e.getMaxTileValue() > 4) {
            let maxTile = e.getMaxTileValue();
            let scoreProgress = (e.score / 20000) * 100;
            let tileProgress = (Math.log2(maxTile) / 11) * 100; 
            s = Math.max(scoreProgress, tileProgress);
        }
        if(this.progressBar) this.progressBar.style.width = `${Math.min(100, Math.max(0, s))}%`;
        
        let root = document.documentElement;
        root.style.setProperty("--orb-a", "rgba(139, 92, 246, 0.25)");
        root.style.setProperty("--orb-b", "rgba(236, 72, 153, 0.25)");
    }
}
