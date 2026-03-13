/**
 * 2048: 无限闭环 - 极致渲染引擎 (v4.3 FINAL)
 */
export class UI {
    constructor() {
        this.viewport = document.getElementById('game-viewport');
        this.app = document.getElementById('app');
        this.gridBg = document.getElementById('grid-bg');
        this.tileContainer = document.getElementById('tile-container');
        this.effectsContainer = document.getElementById('effects-container');
        this.progressBar = document.getElementById('phase-progress');
        this.phaseLabel = document.getElementById('phase-label');
        this.phaseTag = document.getElementById('phase-tag');
        this.scoreElement = document.getElementById('score');
        this.bestScoreElement = document.getElementById('best-score');
        this.comboDisplay = document.getElementById('combo-display');
        this.itemBar = document.getElementById('item-bar');

        this.successModal = document.getElementById('modal-phase-success');
        this.successTitle = document.getElementById('success-title');
        this.successMsg = document.getElementById('success-msg');
        this.nextPhaseInfo = document.getElementById('next-phase-info');

        this.currentMode = null;
    }

    render(game, mergedTiles = []) {
        if (!this.tileContainer) return;

        // 状态同步
        this.app.className = (game.mode === 'loop') ? 'mode-loop' : 'mode-standard';
        if (this.currentMode !== game.mode) {
            this.renderGridBg(game.size);
            this.currentMode = game.mode;
            if (this.itemBar) this.itemBar.classList.toggle('hidden', game.mode !== 'loop');
        }

        // 磁贴同步
        const currentIds = new Set();
        game.board.forEach((row, r) => {
            row.forEach((tile, c) => {
                if (tile) {
                    currentIds.add(tile.id);
                    this.updateTileDOM(tile, r, c, game.size, mergedTiles.find(m => m.r === r && m.c === c));
                }
            });
        });

        // 移除多余磁贴
        Array.from(this.tileContainer.children).forEach(el => {
            const id = parseInt(el.id.replace('tile-', ''));
            if (!currentIds.has(id)) el.remove();
        });

        // 合并反馈
        if (mergedTiles.length > 0) {
            mergedTiles.forEach(m => this.createSplash(m, game.size));
            this.showCombo(game.combo);
        } else {
            this.hideCombo();
        }

        // 数据更新 (保护 NaN)
        this.scoreElement.innerText = game.score || 0;
        const b = (game.bestScore && !isNaN(game.bestScore)) ? game.bestScore : 0;
        this.bestScoreElement.innerText = Math.max(game.score || 0, b);
        this.updateProgress(game);

        // 胜利与阶段拦截
        if (game.phaseJustCleared) {
            this.showPhaseSuccess(game);
        } else if (game.won) {
            this.showFinalWin();
        }
    }

    renderGridBg(size) {
        if (!this.gridBg) return;
        this.gridBg.innerHTML = '';
        const n = size * size;
        for (let i = 0; i < n; i++) {
            const cell = document.createElement('div');
            cell.className = 'grid-cell';
            this.gridBg.appendChild(cell);
        }
    }

    updateTileDOM(tile, r, c, size, mergedInfo) {
        let el = document.getElementById(`tile-${tile.id}`);
        if (!el) {
            el = document.createElement('div');
            el.id = `tile-${tile.id}`;
            this.tileContainer.appendChild(el);
        }
        el.className = `tile tile-${tile.value} ${tile.isAnchor ? 'tile-anchor' : ''} ${mergedInfo ? 'tile-merged' : ''}`;
        el.innerText = tile.isAnchor ? "2048" : tile.value;
        const offset = 100 / size;
        el.style.top = `${r * offset}%`;
        el.style.left = `${c * offset}%`;
        el.style.width = `calc(${offset}% - 10px)`;
        el.style.height = `calc(${offset}% - 10px)`;
    }

    createSplash({ r, c, value }, size) {
        const offset = 100 / size;
        // Particle count scales with tile value: 4→6, 8→8, 64→12, 512→18, 2048→24
        const logVal = Math.log2(value || 2);
        const count = Math.min(24, Math.max(6, Math.floor(logVal * 2)));
        // Color hue mapped to value: low=cyan(180), mid=gold(45), high=pink(330)
        const hue = value <= 8 ? 180 : value <= 64 ? 45 : value <= 256 ? 280 : 330;

        for (let i = 0; i < count; i++) {
            const p = document.createElement('div');
            const isLarge = value >= 256 && Math.random() > 0.5;
            const isGlow = value >= 128;
            p.className = `particle${isLarge ? ' large' : ''}${isGlow ? ' glow' : ''}`;
            p.style.top = `${(r + 0.5) * offset}%`;
            p.style.left = `${(c + 0.5) * offset}%`;
            const spread = 80 + logVal * 10;
            const tx = (Math.random() - 0.5) * spread;
            const ty = (Math.random() - 0.5) * spread;
            p.style.setProperty('--target-transform', `translate(${tx}px, ${ty}px)`);
            const h = hue + (Math.random() - 0.5) * 40;
            p.style.background = `hsl(${h}, 80%, ${60 + Math.random() * 20}%)`;
            p.style.color = `hsl(${h}, 80%, 70%)`; // for box-shadow currentColor
            this.effectsContainer.appendChild(p);
            setTimeout(() => p.remove(), isLarge ? 800 : 600);
        }
    }

    shake() {
        this.viewport.classList.add('shake');
        setTimeout(() => this.viewport.classList.remove('shake'), 400);
    }

    showCombo(count) {
        if (count < 2 || !this.comboDisplay) return;
        this.comboDisplay.innerText = `COMBO x${count}`;
        this.comboDisplay.style.opacity = '1';
        this.comboDisplay.style.transform = `scale(${1 + Math.min(count, 5) * 0.1})`;
    }

    hideCombo() { if (this.comboDisplay) this.comboDisplay.style.opacity = '0'; }

    updateProgress(game) {
        let p = 0;
        if (game.mode === 'loop') {
            if (game.phase === 'disassemble') {
                this.phaseTag.innerText = "DISASSEMBLE";
                this.phaseLabel.innerText = "第一阶段：熵减拆解";
                let t = 0, c = 0;
                game.board.forEach(row => row.forEach(tile => { if (tile && !tile.isAnchor) { t++; if (tile.value === 2) c++; } }));
                p = t ? (c / t) * 100 : 0;
            } else {
                this.phaseTag.innerText = "REASSEMBLE";
                this.phaseLabel.innerText = "第二阶段：物质重构";
                const ns = [{ r: 1, c: 2 }, { r: 3, c: 2 }, { r: 2, c: 1 }, { r: 2, c: 3 }];
                let found = 0;
                ns.forEach(pos => { if (game.board[pos.r][pos.c]?.value >= 512) found++; });
                p = (found / 4) * 100;
            }
        } else {
            this.phaseTag.innerText = "CLASSIC";
            this.phaseLabel.innerText = "初始维度：冲击 2048";
            p = Math.max(0, (Math.log2(game.getMaxTileValue()) - 1) / 10) * 100;
        }
        this.progressBar.style.width = `${Math.min(100, p)}%`;
        this.setPhaseBackground(game);
    }

    /** Phase-aware background orb color control */
    setPhaseBackground(game) {
        const root = document.documentElement;
        if (game.mode === 'loop') {
            if (game.phase === 'disassemble') {
                // Stage 2: Dark crimson + deep purple
                root.style.setProperty('--orb-a', 'rgba(180, 30, 60, 0.25)');
                root.style.setProperty('--orb-b', 'rgba(100, 20, 140, 0.25)');
            } else {
                // Stage 3: Golden + emerald
                root.style.setProperty('--orb-a', 'rgba(251, 191, 36, 0.25)');
                root.style.setProperty('--orb-b', 'rgba(34, 197, 94, 0.25)');
            }
        } else {
            // Stage 1 (Classic): Blue-purple (default)
            root.style.setProperty('--orb-a', 'rgba(139, 92, 246, 0.25)');
            root.style.setProperty('--orb-b', 'rgba(236, 72, 153, 0.25)');
        }
    }

    /** Full-screen Canvas transition animation */
    playTransition(type = 'victory') {
        return new Promise(resolve => {
            let canvas = document.getElementById('transition-canvas');
            if (!canvas) {
                canvas = document.createElement('canvas');
                canvas.id = 'transition-canvas';
                document.body.appendChild(canvas);
            }
            canvas.width = window.innerWidth;
            canvas.height = window.innerHeight;
            canvas.classList.add('active');
            const ctx = canvas.getContext('2d');

            const particles = [];
            const cx = canvas.width / 2, cy = canvas.height / 2;

            if (type === 'victory') {
                // Burst outward: tiles explode then reassemble
                for (let i = 0; i < 60; i++) {
                    const angle = (Math.PI * 2 / 60) * i;
                    const speed = 3 + Math.random() * 5;
                    particles.push({
                        x: cx, y: cy,
                        vx: Math.cos(angle) * speed,
                        vy: Math.sin(angle) * speed,
                        size: 8 + Math.random() * 16,
                        hue: Math.random() * 60 + 280, // purple-pink
                        life: 1,
                        decay: 0.008 + Math.random() * 0.008
                    });
                }
            } else {
                // Defeat: dark vortex swallows inward
                for (let i = 0; i < 50; i++) {
                    const angle = Math.random() * Math.PI * 2;
                    const dist = 200 + Math.random() * 300;
                    particles.push({
                        x: cx + Math.cos(angle) * dist,
                        y: cy + Math.sin(angle) * dist,
                        vx: -Math.cos(angle) * (1 + Math.random() * 2),
                        vy: -Math.sin(angle) * (1 + Math.random() * 2),
                        size: 6 + Math.random() * 12,
                        hue: 0,
                        life: 1,
                        decay: 0.01 + Math.random() * 0.01
                    });
                }
            }

            let frame = 0;
            const maxFrames = 90; // ~1.5s at 60fps
            const animate = () => {
                frame++;
                ctx.clearRect(0, 0, canvas.width, canvas.height);

                if (type === 'defeat') {
                    const alpha = Math.min(0.6, frame / maxFrames);
                    ctx.fillStyle = `rgba(0, 0, 0, ${alpha})`;
                    ctx.fillRect(0, 0, canvas.width, canvas.height);
                }

                particles.forEach(p => {
                    p.x += p.vx;
                    p.y += p.vy;
                    p.life -= p.decay;
                    if (type === 'victory') {
                        p.vx *= 0.97;
                        p.vy *= 0.97;
                    }
                    if (p.life > 0) {
                        ctx.globalAlpha = p.life;
                        ctx.fillStyle = type === 'defeat'
                            ? `rgba(20, 0, 30, ${p.life})`
                            : `hsla(${p.hue}, 80%, 65%, ${p.life})`;
                        ctx.shadowBlur = type === 'victory' ? 15 : 0;
                        ctx.shadowColor = `hsla(${p.hue}, 80%, 65%, 0.5)`;
                        ctx.beginPath();
                        ctx.arc(p.x, p.y, p.size * p.life, 0, Math.PI * 2);
                        ctx.fill();
                    }
                });
                ctx.globalAlpha = 1;
                ctx.shadowBlur = 0;

                if (frame < maxFrames) {
                    requestAnimationFrame(animate);
                } else {
                    canvas.classList.remove('active');
                    ctx.clearRect(0, 0, canvas.width, canvas.height);
                    resolve();
                }
            };
            requestAnimationFrame(animate);
        });
    }

    async showPhaseSuccess(game) {
        // Play victory transition before showing modal
        await this.playTransition('victory');
        if (!this.successModal) return;
        this.successModal.classList.remove('hidden');
        if (game.mode === 'classic') {
            this.successTitle.innerText = "抵达 2048 点位！";
            this.successMsg.innerText = "你已触碰初始维度的极限。";
            this.nextPhaseInfo.innerText = "即将进入：【拆解阶段】\n目标：将所有物质归 2（熵减）。";
            window._nextStageCallback = () => game.jumpToStage('loop_1');
        } else {
            this.successTitle.innerText = "阶段任务完成！";
            this.successMsg.innerText = "逻辑屏障已瓦解。";
            this.nextPhaseInfo.innerText = "即将进入：【重构阶段】\n目标：在中心周围合成 4 个 512。";
            window._nextStageCallback = () => game.jumpToStage('loop_2');
        }
    }

    async showFinalWin() {
        await this.playTransition('victory');
        if (!this.successModal) return;
        this.successModal.classList.remove('hidden');
        this.successTitle.innerText = "维度大一统！";
        this.successMsg.innerText = "你成功在虚无中建立了永恒秩序。";
        this.nextPhaseInfo.innerText = "恭喜通关！你可以继续留在此维度探索。";
        window._nextStageCallback = () => this.successModal.classList.add('hidden');
    }
}
