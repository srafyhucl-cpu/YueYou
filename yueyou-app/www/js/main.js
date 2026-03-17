import { AudioManager } from './modules/AudioManager.js';
import { GameEngine } from './modules/GameEngine.js';
import { Renderer } from './modules/Renderer.js';
import { LocalDB } from './modules/LocalDB.js';

// 全局高维阅读进度引擎 (加固版)
window.ProgressManager = {
    getRecord(bookId) {
        if (!bookId) return { cursor: 0, total: 1, percent: 0 };
        let records = JSON.parse(localStorage.getItem('reading_records') || '{}');
        return records[String(bookId)] || { cursor: 0, total: 1, percent: 0 };
    },
    updateRecord(bookId, cursor, total) {
        if (!bookId || total <= 0) return;
        let records = JSON.parse(localStorage.getItem('reading_records') || '{}');
        let percent = Math.min(100, (cursor / total) * 100);
        records[String(bookId)] = { cursor, total, percent: parseFloat(percent.toFixed(2)) };
        localStorage.setItem('reading_records', JSON.stringify(records));
    },
    deleteRecord(bookId) {
        if (!bookId) return;
        let records = JSON.parse(localStorage.getItem('reading_records') || '{}');
        delete records[String(bookId)];
        localStorage.setItem('reading_records', JSON.stringify(records));
    }
};

// 全局赛博数字翻页器 (Odometer Engine)
window.animateValue = (elementId, start, end, duration) => {
    const obj = document.getElementById(elementId);
    if (!obj) return;
    if (end - start === 0) {
        obj.innerText = end;
        return;
    }
    let startTimestamp = null;
    const step = (timestamp) => {
        if (!startTimestamp) startTimestamp = timestamp;
        const progress = Math.min((timestamp - startTimestamp) / duration, 1);
        const easeOutProgress = 1 - Math.pow(1 - progress, 3);
        obj.innerText = Math.floor(easeOutProgress * (end - start) + start);
        if (progress < 1) {
            window.requestAnimationFrame(step);
        } else {
            obj.innerText = end;
        }
    };
    window.requestAnimationFrame(step);
};

window.generateCoverGradient = (title) => {
    let hash = 0;
    for (let i = 0; i < title.length; i++) hash = title.charCodeAt(i) + ((hash << 5) - hash);
    const h1 = Math.abs(hash % 360);
    const h2 = (h1 + 40) % 360; // 取相邻色相产生高级流体感
    return `linear-gradient(135deg, hsl(${h1}, 80%, 60%), hsl(${h2}, 80%, 40%))`;
};

// ==========================================
// 赛博 HUD 状态栏引擎 (系统时间与硬件电量感知)
// ==========================================
window.initCyberHUD = () => {
    const timeEl = document.getElementById('sys-time');
    const batEl = document.getElementById('sys-battery');
    const batIcon = document.getElementById('sys-battery-icon');
    
    // 1. 时钟引擎
    const updateTime = () => {
        if (!timeEl) return;
        const now = new Date();
        timeEl.innerText = now.getHours().toString().padStart(2, '0') + ':' + now.getMinutes().toString().padStart(2, '0');
    };
    updateTime();
    setInterval(updateTime, 1000);

    // 2. 硬件电量感知 (Web Battery API)
    if ('getBattery' in navigator) {
        navigator.getBattery().then(battery => {
            const updateBattery = () => {
                if (!batEl || !batIcon) return;
                let level = Math.floor(battery.level * 100);
                batEl.innerText = `PWR ${level}%`;
                
                batEl.className = ''; batIcon.className = '';
                if (battery.charging) {
                    batIcon.innerText = '⚡';
                    batEl.classList.add('sys-charging');
                    batIcon.classList.add('sys-charging');
                } else if (level <= 20) {
                    batIcon.innerText = '⚠️';
                    batEl.classList.add('sys-low');
                    batIcon.classList.add('sys-low');
                } else {
                    batIcon.innerText = '🔋';
                }
            };
            updateBattery();
            battery.addEventListener('levelchange', updateBattery);
            battery.addEventListener('chargingchange', updateBattery);
        });
    } else {
        if (batEl) batEl.innerText = "SYS OK";
        if (batIcon) batIcon.innerText = "🌐";
    }
};

let analyser = null;
let visualizerCtx = null;

// ======================================
// 归一化 UI 组件库：自定义确认弹窗
// ======================================
window._isModalActive = false;
window._showConfirm = (title, msg, isAlert = false) => {
    // 强制清理旧的弹窗残留（如果由于异常未关闭）
    if (window._isModalActive) {
        const existing = document.querySelector('.custom-confirm-overlay');
        if (!existing) window._isModalActive = false;
        else return Promise.resolve(false); 
    }
    
    return new Promise((resolve) => {
        window._isModalActive = true;
        document.body.classList.add('modal-open');
        const overlay = document.createElement('div');
        overlay.className = 'custom-confirm-overlay';
        overlay.innerHTML = `
        <div class="custom-confirm-modal">
            <div class="custom-confirm-title">${title}</div>
            <div class="custom-confirm-msg">${msg}</div>
            <div class="custom-confirm-btns">
                ${!isAlert ? '<button class="custom-confirm-btn cancel" id="confirm-cancel">取消</button>' : ''}
                <button class="custom-confirm-btn confirm" id="confirm-ok">确定</button>
            </div>
        </div>`;
        document.body.appendChild(overlay);
        const close = (res) => {
            overlay.style.opacity = '0';
            document.body.classList.remove('modal-open');
            window._isModalActive = false; // 释放锁
            setTimeout(() => { if(overlay.parentNode) document.body.removeChild(overlay); resolve(res); }, 200);
        };
        const cancelBtn = overlay.querySelector('#confirm-cancel');
        if (cancelBtn) cancelBtn.onclick = () => close(false);
        overlay.querySelector('#confirm-ok').onclick = () => close(true);
        overlay.onclick = (e) => { if (e.target === overlay) close(false); };
    });
};

window._showAlert = (title, msg) => window._showConfirm(title, msg, true);

window._showToast = (e, text) => {
    if (e && e.stopPropagation) e.stopPropagation();
    const old = document.querySelector('.floating-tooltip');
    if (old) old.remove();

    const tooltip = document.createElement('div');
    tooltip.className = 'floating-tooltip';
    tooltip.innerText = text;
    document.body.appendChild(tooltip);

    // 自动移除逻辑已通过 CSS 动画 forwards 实现，此处仅需清理 DOM
    setTimeout(() => { if(tooltip.parentNode) tooltip.remove(); }, 3500);
};

(() => {
    document.addEventListener("DOMContentLoaded", () => {
        let p = new GameEngine(),
            e = new Renderer(),
            s = {
                async saveScore(f, i) { },
                async loadLeaderboard() {
                    let lb = document.getElementById("leaderboard-content");
                    if (lb) lb.innerHTML = "<p style=\"text-align:center;color:gray\">离线单机模式不支持排行榜</p>";
                },
                saveLocalState() {
                    let st = {
                        board_data: JSON.stringify(p.board),
                        score: p.score,
                        combo: p.combo,
                        bestScore: p.bestScore,
                        maxCombo: p.maxCombo,
                        novel_index: l.cursor,
                        current_novel_id: l.novelID
                    };
                    localStorage.setItem("local_save_data", JSON.stringify(st));
                }
            },
            t = {
                sound: localStorage.getItem("setting_sound") !== "false",
                ambientVol: parseFloat(localStorage.getItem("setting_ambient_vol") || "0.5"),
                ambientEnabled: localStorage.getItem("setting_ambient_enabled") !== "false", // 默认开启
                ambientTheme: localStorage.getItem("setting_ambient_theme") || "wuxia",
                storyTTS: localStorage.getItem("setting_story_tts") !== "false",
                voice: localStorage.getItem("setting_voice") || "zh-CN-XiaoxiaoNeural",
                idleTimeout: parseInt(localStorage.getItem("setting_idle_timeout") || "1"),
            };

        const l = new AudioManager(t);
        window.AudioManager = l;
        Object.defineProperty(window, 'u', { get: () => l.u });

        function B(i, f) { let el = document.getElementById(i); if (el) el.addEventListener("click", f); }
        let V = document.getElementById("modal-library");
        let S = document.getElementById("modal-settings");
        let L = document.getElementById("modal-leaderboard");
        let C = document.getElementById("modal-chapters");
        let H = document.getElementById("library-content");

        let lastInteractionTime = Date.now();
        const updateInteraction = () => { lastInteractionTime = Date.now(); };
        ['mousedown', 'touchstart', 'keydown'].forEach(evt => document.addEventListener(evt, updateInteraction));

        setInterval(() => {
            if (!l.enabled || t.idleTimeout === 0) return;
            const idleTime = (Date.now() - lastInteractionTime) / 1000 / 60;
            if (idleTime > t.idleTimeout && l.isSpeaking) {
                l.setEnabled(false);
                window._showToast({ clientX: window.innerWidth / 2, clientY: 100 }, "由于长时间未操作，播报已自动暂停");
            }
        }, 10000);

        const syncSettingsUI = () => {
            const ts = document.getElementById("toggle-sound");
            const tst = document.getElementById("toggle-story");
            const tv = document.getElementById("tts-voice-select");
            const ta = document.getElementById("toggle-ambient");
            const it = document.getElementById("idle-timeout");
            const itl = document.getElementById("idle-timeout-label");

            if (ts) ts.checked = t.sound;
            if (tst) tst.checked = t.storyTTS;
            if (tv) tv.value = t.voice;
            if (ta) ta.checked = t.ambientEnabled;
            if (it) it.value = t.idleTimeout;
            if (itl) itl.innerText = t.idleTimeout === 0 ? '永不停止' : t.idleTimeout + ' 分钟';


            // 初始化灵动岛的倍速显示
            let savedRate = parseFloat(localStorage.getItem("setting_tts_rate") || "1.0").toFixed(1);
            let speedBtn = document.getElementById("capsule-speed-btn");
            if (speedBtn) speedBtn.innerText = savedRate + "x";
        };

        const updateSetting = async (key, value) => {
            t[key] = value;
            const storageKey = `setting_${key === 'storyTTS' ? 'story_tts' : (key === 'ambientEnabled' ? 'ambient_enabled' : (key === 'idleTimeout' ? 'idle_timeout' : key))}`;
            localStorage.setItem(storageKey, value);
            l.settings = { ...t };

            if (key === 'voice') {
                if (t.storyTTS) l.refreshSession();
                window._showToast(null, "发声人已切换");
            }
            if (key === 'storyTTS') {
                if (value) l.refreshSession();
                else l.setEnabled(false);
            }
            if (key === 'ambientEnabled') {
                if (value) l.playAmbient('game');
                else l.stopAmbient();
            }
            if (key === 'idleTimeout') {
                const itl = document.getElementById("idle-timeout-label");
                if (itl) itl.innerText = value === 0 ? '永不停止' : value + ' 分钟';
            }
        };

        const initSettingsListeners = () => {
            const ts = document.getElementById("toggle-sound");
            if (ts) ts.onchange = (e) => updateSetting('sound', e.target.checked);
            const tst = document.getElementById("toggle-story");
            if (tst) tst.onchange = (e) => updateSetting('storyTTS', e.target.checked);
            const tv = document.getElementById("tts-voice-select");
            if (tv) tv.onchange = (e) => updateSetting('voice', e.target.value);
            const ta = document.getElementById("toggle-ambient");
            if (ta) ta.onchange = (e) => updateSetting('ambientEnabled', e.target.checked);
            const it = document.getElementById("idle-timeout");
            if (it) it.oninput = (e) => updateSetting('idleTimeout', parseInt(e.target.value));
        };
        initSettingsListeners();
        
        // 唤醒 HUD 状态栏
        window.initCyberHUD();

        B("btn-settings", () => { syncSettingsUI(); if (S) S.classList.remove("hidden"); });
        B("close-settings", () => { 
            if (S) S.classList.add("hidden"); 
        });

        const loadSavedState = () => {
            const saved = localStorage.getItem("local_save_data");
            if (saved) {
                try {
                    const st = JSON.parse(saved);
                    if (st.board_data) {
                        p.board = JSON.parse(st.board_data);
                        p.score = st.score || 0;
                        p.combo = st.combo || 0;
                        p.bestScore = st.bestScore || p.bestScore;
                        p.maxCombo = st.maxCombo || p.maxCombo;
                        let maxId = 0;
                        p.board.forEach(row => row.forEach(tile => {
                            if (tile && tile.id) maxId = Math.max(maxId, tile.id);
                        }));
                        p.nextId = maxId + 1;
                    }
                } catch (err) { console.error("Failed to load game state", err); }
            }
        };

        const renderLibrary = () => {
                if (!H) return;
                let shelfText = localStorage.getItem("local_bookshelf");
                let shelf = shelfText ? JSON.parse(shelfText) : [];
                if (shelf.length === 0) {
                    H.innerHTML = '<p style="text-align:center;color:rgba(255,255,255,0.5);margin-top:20px;">当前书架为空，请导入 TXT 本地小说</p>';
                    return;
                }

                let htmlContent = '<ul id="novel-list">';

                shelf.forEach(b => {
                    let cleanTitle = (b.title || "未知").replace(/\.txt$/i, '');
                    let coverChar = cleanTitle.charAt(0);
                    let coverBg = window.generateCoverGradient(cleanTitle);

                    // 从独立高维进度引擎读取百分比（防止丢进度）
                    let records = JSON.parse(localStorage.getItem('reading_records') || '{}');
                    let bookRecord = records[String(b.id)] || { percent: 0 };
                    let progressValue = bookRecord.percent || 0;
                    let displayWidth = Math.max(1, progressValue); // 至少显示 1%

                    htmlContent += `
              <li class="bento-card" onclick="window.loadBookFromShelf(${b.id}, '${b.title.replace(/'/g, "\\'")}', 0)">
                  <div class="bento-full-cover" style="background: ${coverBg};">
                      <span class="bento-watermark">${coverChar}</span>
                      <div class="bento-info-overlay">
                          <div class="bento-title">${cleanTitle}</div>
                          <div class="bento-meta">
                              <div class="bento-progress-container">
                                  <div class="bento-progress-text">已读 ${progressValue}%</div>
                                  <div class="bento-progress-track">
                                      <div class="bento-progress-fill" style="width: ${displayWidth}%;"></div>
                                  </div>
                              </div>
                              <button class="btn-bento-delete" onclick="window.deleteBook(${b.id}, event)">删</button>
                          </div>
                      </div>
                  </div>
              </li>`;
                });

                htmlContent += '</ul>';
                H.innerHTML = htmlContent;
            };

            window.loadBookFromShelf = async (id, title, cursor) => {
                await l.loadNovel(id, title, cursor);
                if (V) V.classList.add("hidden");
                
                // 唤醒音频上下文并开启模式
                if (window.u && window.u.state === 'suspended') window.u.resume();
                l.setEnabled(true);
                l.refreshSession();
                window._syncIdleState();
            };

            window.deleteBook = async (id, event) => {
                if (event) event.stopPropagation(); // 禁止触发书籍加载
                if (await window._showConfirm("初始化抹除？", "此操作将永久移除该档案及其所有阅读进度，确认执行？")) {
                   if (window.ProgressManager) window.ProgressManager.deleteRecord(id);
                   let shelf = JSON.parse(localStorage.getItem("local_bookshelf") || "[]");
                   shelf = shelf.filter(x => x.id !== id);
                   localStorage.setItem("local_bookshelf", JSON.stringify(shelf));
                   LocalDB.deleteBook(id);
                   renderLibrary();
                }
            };

            window._chapterReversed = false;
            const renderChapterList = () => {
                let container = document.getElementById("chapter-list");
                if (!container) return;
                if (!l.chapters || l.chapters.length === 0) {
                    container.innerHTML = `<div style="text-align:center;padding:20px;color:gray;">暂无目录数据</div>`;
                    const stats = document.getElementById("chapter-stats");
                    if (stats) stats.innerText = "共 0 章 | 阅读进度 0%";
                    return;
                }

                const total = l.chapters.length;
                const readPercent = Math.floor((l.cursor / l.lines.length) * 100);
                const stats = document.getElementById("chapter-stats");
                if (stats) stats.innerText = `共 ${total} 章 | 阅读进度 ${readPercent}%`;

                let activeIdx = -1;
                for (let i = l.chapters.length - 1; i >= 0; i--) {
                    if (l.cursor >= l.chapters[i].lineIndex) {
                        activeIdx = i;
                        break;
                    }
                }

                let displayChapters = window._chapterReversed ? [...l.chapters].reverse() : l.chapters;
                let html = "";
                for (let i = 0; i < displayChapters.length; i++) {
                    const c = displayChapters[i];
                    const originalIdx = window._chapterReversed ? (total - 1 - i) : i;
                    let cls = "";
                    if (originalIdx === activeIdx) cls = "active";
                    else if (originalIdx < activeIdx) cls = "read";
                    html += `
                <div id="chapter-item-${originalIdx}" class="chapter-item ${cls}" onclick="jumpTo(${c.lineIndex})">
                    <span class="chapter-status-dot"></span>
                    ${c.title}
                </div>
            `;
                }
                container.innerHTML = html;

                if (activeIdx !== -1) {
                    setTimeout(() => {
                        const activeEl = document.getElementById(`chapter-item-${activeIdx}`);
                        if (activeEl) activeEl.scrollIntoView({ behavior: 'smooth', block: 'center' });
                    }, 100);
                }
            };

            window.jumpTo = (idx) => {
                l.jumpToChapter(idx);
                if (C) C.classList.add("hidden");
            };

            const fileInput = document.getElementById("upload-novel-file");
            if (fileInput) {
                fileInput.addEventListener("change", async (e) => {
                    let file = e.target.files[0];
                    if (!file) return;
                    let reader = new FileReader();
                    reader.onload = async (ev) => {
                        let mask = document.createElement("div");
                        mask.style.cssText = "position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.6); backdrop-filter:blur(10px); z-index:10000; display:flex; align-items:center; justify-content:center; color:#fff;";
                        mask.innerHTML = "<div style='text-align:center;'><div style='font-size:40px; margin-bottom:20px;'>📚</div>正在构建本地库...</div>";
                        document.body.appendChild(mask);
                        try {
                            const buffer = ev.target.result;
                            let text = "";
                            try {
                                const utf8Decoder = new TextDecoder('utf-8', { fatal: true });
                                text = utf8Decoder.decode(buffer);
                            } catch (e) {
                                const gbkDecoder = new TextDecoder('gb18030');
                                text = gbkDecoder.decode(buffer);
                            }
                            let rawLines = text.split(/\r?\n/).map(line => line.trim()).filter(line => line.length > 0);
                            let title = file.name.replace(".txt", "");

                            // 归一化章节识别算法：适配《斗破苍穹》(正文 第X章)、校对版(卷一 第X章)、以及多种复杂前缀
                            let chapters = [];
                            const chapterRegex = /^\s*(?:(?:正文|卷[0-9零一二三四五六七八九十百千两\s]+|.{0,4})\s*第?\s*[0-9零一二三四五六七八九十百千两]+\s*[章回节卷集部篇]|Chapter\s*[0-9]+|引子|序言|楔子|前言|内容简介|致读者)/i;
                            rawLines.forEach((line, index) => {
                                if (chapterRegex.test(line) && line.length < 50) { // 长度限制防止误报
                                    chapters.push({ title: line.trim(), lineIndex: index });
                                }
                            });

                            let bookId = Date.now();
                            
                            // 🚨 核心修复：绝对不能加 window. 前缀！直接使用当前模块引用的 LocalDB
                            await LocalDB.saveBook(bookId, { lines: rawLines, chapters: chapters });
                            
                            let shelfText = localStorage.getItem("local_bookshelf");
                            let shelf = shelfText ? JSON.parse(shelfText) : [];
                            
                            // 增强体验：查重逻辑，防止重复导入同一本小说导致书架冗余
                            let existingIndex = shelf.findIndex(b => b.title === title);
                            if (existingIndex !== -1) {
                                shelf.splice(existingIndex, 1);
                            }
                            
                            // 将新书插入书架最前面
                            shelf.unshift({ id: bookId, title: title, total: rawLines.length, cursor: 0 });
                            localStorage.setItem("local_bookshelf", JSON.stringify(shelf));

                             // 核心变更：不再自动切换加载，不再关闭图书馆
                             window._showToast(null, "档案注入成功");
                             renderLibrary();
                             // window._syncIdleState(); // 暂不需要，书架保持开启状态
                        } catch (err) { console.error(err); } finally { mask.remove(); e.target.value = ""; }
                    };
                    reader.readAsArrayBuffer(file);
                });
            }

            // 归一化重启引擎：确保重置动作是原子性的，同步刷新 UI 与持久化存储
            window._forceRestartGame = () => {
                p.reset(); 
                e.render(p); 
                s.saveLocalState();
            };

            B("btn-library", () => { renderLibrary(); if (V) V.classList.remove("hidden"); });
            B("close-library", () => { if (V) V.classList.add("hidden"); });
            B("btn-leaderboard", () => { s.loadLeaderboard(); if (L) L.classList.remove("hidden"); });
            B("close-leaderboard", () => { if (L) L.classList.add("hidden"); });
            B("btn-chapter-list", () => { if (C) { renderChapterList(); C.classList.remove("hidden"); } });
            B("btn-sort-chapters", () => { window._chapterReversed = !window._chapterReversed; renderChapterList(); });
            B("play-pause-icon", (e) => { window.toggleTTS(e); updateInteraction(); });
            B("player-progress-text", () => { if (C) { renderChapterList(); C.classList.remove("hidden"); } });
            B("player-capsule", (e) => { if (e.target.id === "play-pause-icon") return; if (C) { renderChapterList(); C.classList.remove("hidden"); } });
            B("btn-close-chapters", () => { if (C) C.classList.add("hidden"); });
            B("btn-idle-import", () => { renderLibrary(); if (V) V.classList.remove("hidden"); });
            B("restart-btn", async () => { 
                if (await window._showConfirm("重组系统架构？", "当前游戏进度将重置，所有合并记录将归零，是否继续？")) { 
                    window._forceRestartGame();
                } 
            });
            document.querySelectorAll('.modal-overlay').forEach(overlay => { overlay.addEventListener('click', (e) => { if (e.target === overlay) overlay.classList.add('hidden'); }); });

            const handleMove = (dir) => {
                // 状态机同步判定
                if (p.over) {
                    // 若已结束且未在显示弹窗，则唤起重开确认
                    if (!window._isModalActive) {
                        window._showConfirm("演化终止", "当前熵值已达极限。是否重启系统演化进程？").then(ok => {
                            if (ok) window._forceRestartGame();
                        });
                    }
                    return;
                }

                const result = p.move(dir);
                if (result.moved) {
                    e.render(p, Array.isArray(result.mergedTiles) ? result.mergedTiles : []);
                    if (result.mergedTiles && result.mergedTiles.length > 0 && t.sound) l.playEffect('merge');
                    l.unlockAudio();
                    s.saveLocalState();
                    updateInteraction();
                    
                    // 核心：若此次移动导致游戏结束，立即触发弹窗
                    if (p.over) {
                        window._showConfirm("演化终止", "熵増无法逆转。是否重启系统演化进程？").then(ok => {
                            if (ok) window._forceRestartGame();
                        });
                    }
                }
            };
            document.addEventListener("keydown", (e) => {
                const map = { ArrowUp: "up", ArrowDown: "down", ArrowLeft: "left", ArrowRight: "right", w: "up", s: "down", a: "left", d: "right", W: "up", S: "down", A: "left", D: "right" };
                if (map[e.key]) { e.preventDefault(); handleMove(map[e.key]); }
            });
            let tsX, tsY;
            document.addEventListener("touchstart", (e) => { tsX = e.touches[0].clientX; tsY = e.touches[0].clientY; }, { passive: false });
            document.addEventListener("touchend", (e) => { if (!tsX || !tsY) return; let teX = e.changedTouches[0].clientX, teY = e.changedTouches[0].clientY; let dx = teX - tsX, dy = teY - tsY; if (Math.abs(dx) > 30 || Math.abs(dy) > 30) { if (Math.abs(dx) > Math.abs(dy)) handleMove(dx > 0 ? "right" : "left"); else handleMove(dy > 0 ? "down" : "up"); } tsX = null; tsY = null; }, { passive: false });

            // 核心修复 1：精准指向 player-capsule，实现主页状态互斥
            // 归一化 UI 同步引擎
            window._syncIdleState = () => {
                requestAnimationFrame(() => {
                    let idle = document.getElementById("player-idle-state");
                    let player = document.getElementById("player-capsule"); 
                    if (!idle) return;

                    // 优先级判定：1. 内存存在数据 2. 存储存在 ID
                    const hasActiveBook = (l.lines && l.lines.length > 0) || localStorage.getItem("current_novel_id");

                    if (hasActiveBook) {
                        idle.style.display = "none";
                        if (player) player.style.display = "flex";
                    } else {
                        idle.style.display = "flex";
                        if (player) player.style.display = "none";
                    }
                });
            };
            // 确保启动时执行一次同步
            window._syncIdleState();

            const startApp = () => { loadSavedState(); e.render(p); l.syncGameState(p); l.checkHeadphonesAndStart(); };
            let pm = document.getElementById('privacy-modal');
            if (!pm || localStorage.getItem('privacy_agreed') === 'true') { if (pm) pm.classList.add('hidden'); startApp(); }
            else { pm.classList.remove('hidden'); B('btn-privacy-agree', () => { localStorage.setItem('privacy_agreed', 'true'); pm.classList.add('hidden'); startApp(); }); }

            const drawVisualizer = () => {
                requestAnimationFrame(drawVisualizer);
                if (!analyser && window.analyser) analyser = window.analyser;
                let canvas = document.getElementById('audio-visualizer');
                if (!canvas) return;
                if (!visualizerCtx) visualizerCtx = canvas.getContext('2d');
                visualizerCtx.clearRect(0, 0, canvas.width, canvas.height);
                const barCount = 4; const barWidth = 3; const gap = 3;
                const totalWidth = barCount * barWidth + (barCount - 1) * gap;
                const startX = (canvas.width - totalWidth) / 2;
                let dataArray = new Uint8Array(32);
                if (analyser) analyser.getByteFrequencyData(dataArray);
                for (let i = 0; i < barCount; i++) {
                    let value = dataArray[[1, 3, 5, 8][i]] || 0;
                    if (l.isSpeaking) { if (value < 10) value = 50 + Math.random() * 150; }
                    else if (l.enabled) { value = 40 + Math.sin(Date.now() / 200 + i) * 30; }
                    else { value = 5; }
                    let percent = Math.pow(value / 255, 0.85);
                    let barHeight = Math.max(2, percent * canvas.height * 1.2);
                    if (barHeight > canvas.height) barHeight = canvas.height;
                    // 核心视觉升级：Apple Music 级紫粉色流体渐变
                    let gradient = visualizerCtx.createLinearGradient(0, 0, 0, canvas.height);
                    gradient.addColorStop(0, '#ec4899'); // 顶部：亮粉色 (accent-pink)
                    gradient.addColorStop(1, '#8b5cf6'); // 底部：深紫色 (accent-purple)
                    visualizerCtx.fillStyle = gradient;
                    const x = startX + i * (barWidth + gap);
                    const y = (canvas.height - barHeight) / 2;
                    visualizerCtx.beginPath();
                    visualizerCtx.roundRect(x, y, barWidth, barHeight, 2);
                    visualizerCtx.fill();
                }
            };
            drawVisualizer();
        });
})();

// ==========================================
// 控播逻辑：全局 TTS 启停接管
// ==========================================
window.toggleTTS = (e) => {
    e.stopPropagation(); // 绝对阻断冒泡
    if (!window.AudioManager) return;

    const am = window.AudioManager;

    // 核心修复：直接利用引擎底层开关，完美覆盖说话、缓冲、待机等所有状态
    if (am.enabled) {
        am.setEnabled(false); // 触发全局暂停并终止拉取
    } else {
        if (window.u && window.u.state === 'suspended') window.u.resume();
        am.setEnabled(true);  // 触发全局恢复并重启队列
    }

    // 同步设置面板的开关状态 UI
    let autoTts = document.getElementById("toggle-story");
    if (autoTts) autoTts.checked = am.enabled;
};

// ==========================================
// 控播逻辑：一键倍速循环引擎
// ==========================================
window.cycleTTSpeed = (e) => {
    e.stopPropagation(); // 绝对阻断冒泡，防止触发打开目录
    const speeds = [1.0, 1.2, 1.5, 2.0, 2.5, 0.7]; // 主流听书倍速档位
    let currentRate = parseFloat(localStorage.getItem("setting_tts_rate") || "1.0");
    
    // 循环切换到下一档位
    let nextIndex = (speeds.indexOf(currentRate) + 1) % speeds.length;
    if (speeds.indexOf(currentRate) === -1) nextIndex = 1; // 容错
    let newRate = speeds[nextIndex];

    // 1. 持久化存储
    localStorage.setItem("setting_tts_rate", newRate.toString());
    
    // 2. 核心：动态同步到底层音频引擎
    if (window.AudioManager) {
        window.AudioManager.playbackRate = newRate;
        if (window.AudioManager.currentAudio && !window.AudioManager.currentAudio.isSpeech) {
            window.AudioManager.currentAudio.playbackRate = newRate;
        }
    }

    // 3. UI 更新：更新灵动岛按钮文字
    let btn = document.getElementById("capsule-speed-btn");
    if (btn) btn.innerText = newRate.toFixed(1) + "x";

    // 4. UI 更新：同步设置页的滑块（如果存在）
    let ttsRateInput = document.getElementById("tts-rate");
    if (ttsRateInput) ttsRateInput.value = newRate;
    let ttsRateLabel = document.getElementById("tts-rate-label");
    if (ttsRateLabel) ttsRateLabel.innerText = newRate.toFixed(1) + "x";
};
