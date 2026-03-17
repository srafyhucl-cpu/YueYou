// ======================================
// 声音引擎管理器 (AudioManager.js)
// 职责：处理 Web Audio API 全息混响、TTS 有声书预加载与播报、环境白噪音、以及交互音效
// ======================================
import { LocalDB } from './LocalDB.js';

export class AudioManager {
    constructor(settings) {
        this.settings = settings;
        this.u = null;
        this.ttsInput = null;
        this.currentTTSNodes = [];
        this.m = { oscs: [], grains: [], masterGain: null, intervals: [] };
        this.M = null;

        this.lines = [];
        this.chapters = [];
        this.novelID = parseInt(localStorage.getItem("current_novel_id") || "1");
        this.novelTitle = localStorage.getItem("current_novel_title") || "三国演义";
        this.cursor = parseInt(localStorage.getItem("novel_index") || "0");
        this.fetchCursor = this.cursor;
        this.audioBufferArray = [];
        this.isSpeaking = false;

        this.ttsURL = (typeof AppConfig !== "undefined" ? AppConfig.ttsURL : "http://8.218.177.149:3000/api/v1/tts/createStream");
        this.enabled = this.settings.storyTTS;
        this.loopSession = 1;

        this._playLoopActive = false;
        this._prefetchLoopActive = false;
        this.isBuffering = false;

        this.playbackRate = parseFloat(localStorage.getItem("setting_tts_rate") || "1.0");
        
        // --- 常亮引擎初始化 ---
        this.wakeLockObj = null;
        this.initMediaSession(); // 保留 MediaSession 支持
        document.addEventListener('visibilitychange', () => {
            if (document.visibilityState === 'visible' && this.enabled) {
                this.manageWakeLock(true);
            }
        });

        this.initLibrary();
    }

    unlockAudio() {
        this.initContext();
        if (this.u && this.u.state === "suspended") this.u.resume().catch(() => { });
    }

    // ======================================
    // 系统级硬件 API：屏幕常亮与锁屏播控
    // ======================================
    async manageWakeLock(enable) {
        try {
            if (enable && 'wakeLock' in navigator) {
                if (!this.wakeLockObj) this.wakeLockObj = await navigator.wakeLock.request('screen');
            } else {
                if (this.wakeLockObj) {
                    await this.wakeLockObj.release();
                    this.wakeLockObj = null;
                }
            }
        } catch (err) {
            console.warn('Wake Lock 申请被系统拒绝或不支持:', err);
        }
    }

    initMediaSession() {
        if ('mediaSession' in navigator) {
            navigator.mediaSession.setActionHandler('play', () => { if(window.toggleTTS) window.toggleTTS(new Event('click')); });
            navigator.mediaSession.setActionHandler('pause', () => { if(window.toggleTTS) window.toggleTTS(new Event('click')); });
            navigator.mediaSession.setActionHandler('nexttrack', () => {
                let next = Math.min(this.cursor + 10, this.lines.length - 1);
                this.jumpToChapter(next);
            });
            navigator.mediaSession.setActionHandler('previoustrack', () => {
                let prev = Math.max(this.cursor - 10, 0);
                this.jumpToChapter(prev);
            });
        }
    }

    updateMediaSessionMetadata(chapterTitle) {
        if ('mediaSession' in navigator) {
            navigator.mediaSession.playbackState = this.enabled ? (this.isBuffering ? 'none' : 'playing') : 'paused';
            navigator.mediaSession.metadata = new MediaMetadata({
                title: `${this.novelTitle}`,
                artist: `当前: ${chapterTitle}`,
                album: '阅游 Cyber-Zen',
                artwork: [{ src: 'icon.png', sizes: '512x512', type: 'image/png' }]
            });
        }
    }

    initContext() {
        if (!this.u) {
            this.u = new (window.AudioContext || window.webkitAudioContext)();
            this.masterCompressor = this.u.createDynamicsCompressor();
            this.masterCompressor.connect(this.u.destination);
            this.ttsInput = this.u.createGain();
            window.analyser = this.u.createAnalyser();
            window.analyser.fftSize = 64;
            this.ttsInput.connect(window.analyser);
            this.updateTTSFilter();
        }
        if (this.u && this.u.state === "suspended") this.u.resume().catch(() => { });
    }

    updateTTSFilter() {
        if (!this.u || !this.ttsInput) return;
        this.ttsInput.disconnect();
        if (window.analyser) this.ttsInput.connect(window.analyser);
        this.currentTTSNodes.forEach(node => node.disconnect());
        this.currentTTSNodes = [];
        
        // 实时更新环境音量
        if (this.m.masterGain) {
            this.m.masterGain.gain.setTargetAtTime(this.settings.ambientVol, this.u.currentTime, 0.1);
        }
        if (this.settings.ambientTheme === "wuxia") {
            let convolver = this.u.createConvolver();
            convolver.buffer = this.createReverbIR(this.u, 2.0, 3.0);
            let dry = this.u.createGain(), wet = this.u.createGain();
            dry.gain.value = 0.8; wet.gain.value = 0.4;
            this.ttsInput.connect(dry); dry.connect(this.masterCompressor);
            this.ttsInput.connect(convolver); convolver.connect(wet); wet.connect(this.masterCompressor);
            this.currentTTSNodes.push(convolver, dry, wet);
        } else {
            this.ttsInput.connect(this.masterCompressor);
        }
    }

    createReverbIR(audioCtx, duration, decay) {
        let sampleRate = audioCtx.sampleRate;
        let length = sampleRate * duration;
        let impulse = audioCtx.createBuffer(2, length, sampleRate);
        let left = impulse.getChannelData(0), right = impulse.getChannelData(1);
        for (let i = 0; i < length; i++) {
            left[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / length, decay);
            right[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / length, decay);
        }
        return impulse;
    }

    stopAmbient() {
        if (this.m.intervals) this.m.intervals.forEach(clearInterval);
        this.m.oscs.forEach(osc => { try { osc.stop(); } catch { } });
        this.m.oscs = []; this.m.intervals = [];
        this.M = null;
    }

    playAmbient(phase) {
        let sig = phase + '_' + (this.settings.ambientTheme || 'wuxia');
        if (!this.settings.ambientEnabled || !this.u || this.M === sig) return;
        this.stopAmbient();
        this.M = sig;
        let masterGain = this.u.createGain();
        this.m.masterGain = masterGain;
        masterGain.gain.value = this.settings.ambientVol;
        masterGain.connect(this.u.destination);
        if (this.settings.ambientTheme === "wuxia") {
            const fluteFreqs = [329.63, 392.00, 440.00, 523.25, 587.33];
            const playFlute = () => {
                if (this.M !== sig || !this.settings.ambientEnabled) return;
                let osc = this.u.createOscillator(); let g = this.u.createGain();
                osc.type = "sine"; osc.frequency.value = fluteFreqs[Math.floor(Math.random() * fluteFreqs.length)];
                g.gain.setValueAtTime(0, this.u.currentTime);
                g.gain.linearRampToValueAtTime(0.05, this.u.currentTime + 1.0);
                g.gain.exponentialRampToValueAtTime(0.001, this.u.currentTime + 4.0);
                osc.connect(g); g.connect(this.u.destination);
                osc.start(); osc.stop(this.u.currentTime + 4.1);
            };
            this.m.intervals.push(setInterval(playFlute, 6000));
        }
    }

    playEffect(type) {
        if (!this.settings.sound || !this.u) return;
        this.unlockAudio();
        const g = this.u.createGain();
        const o = this.u.createOscillator();
        if (type === 'merge') {
            o.type = 'sine';
            o.frequency.setValueAtTime(440, this.u.currentTime);
            o.frequency.exponentialRampToValueAtTime(880, this.u.currentTime + 0.1);
            g.gain.setValueAtTime(0.12, this.u.currentTime);
            g.gain.exponentialRampToValueAtTime(0.001, this.u.currentTime + 0.3);
            o.connect(g); g.connect(this.u.destination);
            o.start(); o.stop(this.u.currentTime + 0.3);
        }
    }

    syncGameState(gameEngine) {
        this.initContext();
        let phase = gameEngine.mode === "loop" ? gameEngine.phase : "classic";
        this.playAmbient(phase);
        this.updateTTSFilter();
        this.heartbeat();
    }

    checkHeadphonesAndStart() {
        if (!this.enabled) {
            this.enabled = true;
            this.settings.storyTTS = true;
            localStorage.setItem("setting_story_tts", "true");
        }
        this.heartbeat();
    }

    async initLibrary() {
        await this.loadNovel(this.novelID, this.novelTitle, this.cursor);
        
        // 核心修复 3：初始化完成后强制同步 UI 状态，消灭占位图
        if (typeof window._syncIdleState === 'function') window._syncIdleState();

        if (this.enabled) {
            this.startPrefetchLoop();
            this.startPlayLoop();
        }
    }

    async loadNovel(id, title, newCursor = null) {
        try {
            const currentSession = ++this.loopSession;
            this.stopAllAudio();
            this.audioBufferArray.forEach(x => { 
                // 核心修复：在释放内存前，强行切断底层 Audio 的网络流，防止 ERR_FILE_NOT_FOUND
                if (x.obj && typeof x.obj.pause === 'function') {
                    x.obj.removeAttribute('src');
                    if (typeof x.obj.load === 'function') x.obj.load();
                }
                if (x.url && x.url !== 'speech_synthesis') URL.revokeObjectURL(x.url); 
            });
            this.audioBufferArray = [];
            
            // 强制将当前小说 ID 锁定为字符串，供高维引擎精准对接
            this.novelID = String(id);
            this.novelTitle = title;

            let data = await LocalDB.loadBook(id);
            if (!data) return;
            if (this.loopSession !== currentSession) return;

            // 兼容旧版本纯数组数据，并动态解析章节
                // 核心修复：纯文本与对象的兼容反向映射
                if (Array.isArray(data)) {
                    this.lines = data.map(item => typeof item === 'string' ? { t: item } : item);
                    this.chapters = [];
                } else {
                    this.lines = (data.lines || []).map(item => typeof item === 'string' ? { t: item } : item);
                    this.chapters = data.chapters || [];
                }

            // 引擎加固：读取精准进度
            let savedRecord = window.ProgressManager ? window.ProgressManager.getRecord(this.novelID) : { cursor: 0 };
            
            // 如果外部明确传入了大于 0 的游标（如跳章），使用外部游标；否则优先使用本地档
            if (newCursor !== null && newCursor !== undefined && newCursor > 0) {
                this.cursor = newCursor;
            } else {
                this.cursor = savedRecord.cursor || 0;
            }

            if (this.lines && this.cursor >= this.lines.length) this.cursor = 0;
            this.fetchCursor = this.cursor;

            localStorage.setItem("current_novel_id", this.novelID);
            localStorage.setItem("current_novel_title", title);
            localStorage.setItem("novel_index", this.cursor.toString());
            // 同步一次进度
            if (window.ProgressManager && this.lines.length > 0) {
                window.ProgressManager.updateRecord(this.novelID, this.cursor, this.lines.length);
            }
            this.updateUI();
            if (typeof window._syncIdleState === 'function') window._syncIdleState();
        } catch (e) { console.error("LoadNovel error:", e); }
    }

    stopAllAudio() {
        if (this.currentAudio) {
            try {
                // 核心修复：物理消噪（淡出 0.1s 再停止，防止吱啦声）
                if (this.currentAudio.volume !== undefined) {
                    this.currentAudio.volume = 0; 
                }
                this.currentAudio.pause();
                // 🚨 核心修复：删除 currentTime = 0，以便恢复时在原断点继续发声
                if (this.currentAudio.isSpeech && window.speechSynthesis) window.speechSynthesis.cancel();
            } catch (e) { }
        }
        if (window.speechSynthesis) window.speechSynthesis.cancel();
    }

    heartbeat() {
        this.unlockAudio();
        this.startPlayLoop();
        this.startPrefetchLoop();
    }

    async manageWakeLock(enable) {
        try {
            if (enable && 'wakeLock' in navigator) {
                if (!this.wakeLockObj) this.wakeLockObj = await navigator.wakeLock.request('screen');
            } else {
                if (this.wakeLockObj) {
                    await this.wakeLockObj.release();
                    this.wakeLockObj = null;
                }
            }
        } catch (err) {
            console.warn('Wake Lock 申请失败:', err);
        }
    }

    setEnabled(enable) {
        this.enabled = enable;
        localStorage.setItem("setting_story_tts", enable ? "true" : "false");
        
        // 核心挂载：同步触发常亮引擎
        this.manageWakeLock(enable);

        if (enable) {
            // 开启播放：若缓冲区为空，立即同步亮起缓冲态，无需等待循环的下一个 tick
            if (this.audioBufferArray.length === 0) {
                this.isBuffering = true;
                this.isSpeaking = false;
                this.updateUI();
            }
            this.heartbeat();
        } else {
            // 关闭播放：原子性地清除所有播放与缓冲态
            this.stopAllAudio();
            this.isSpeaking = false;
            this.isBuffering = false;
            this.updateUI();
        }
    }

    refreshSession() {
        this.loopSession++;
        this.stopAllAudio();
        this.audioBufferArray.forEach(x => { 
            // 核心修复：强行切断底层 Audio 的网络流
            if (x.obj && typeof x.obj.pause === 'function') {
                x.obj.removeAttribute('src');
                if (typeof x.obj.load === 'function') x.obj.load();
            }
            if (x.url && x.url !== "speech_synthesis") URL.revokeObjectURL(x.url); 
        });
        this.audioBufferArray = [];
        this.isSpeaking = false;
        this.isBuffering = false; // 核心修复：会话刷新时重置缓冲状态，让新会话重新亮灯
        this.fetchCursor = this.cursor; // 从当前行重新开始抓取
        this.heartbeat();
    }

    jumpToChapter(lineIndex) {
        this.loopSession++;
        this.stopAllAudio();
        this.audioBufferArray.forEach(x => { 
            // 核心修复：强行切断底层 Audio 的网络流
            if (x.obj && typeof x.obj.pause === 'function') {
                x.obj.removeAttribute('src');
                if (typeof x.obj.load === 'function') x.obj.load();
            }
            if (x.url && x.url !== "speech_synthesis") URL.revokeObjectURL(x.url); 
        });
        this.audioBufferArray = [];
        this.isSpeaking = false;
        this.isBuffering = false; // 核心修复：跳章时重置缓冲，让底层 loop 重新触发 UI 刷新
        this.cursor = lineIndex; this.fetchCursor = lineIndex;
        if (window.ProgressManager && this.lines) {
            window.ProgressManager.updateRecord(this.novelID, this.cursor, this.lines.length);
        }
        localStorage.setItem("novel_index", this.cursor.toString());
        this.updateUI();
        this.heartbeat();
    }

    async fetchTTS(text, voice) {
        if (!text || text.trim().length === 0) return null;
        let safeText = text.trim();
        if (safeText.length < 5) safeText = safeText.padEnd(5, '。');
        const session = this.loopSession;
        for (let attempt = 0; attempt <= 2; attempt++) {
            if (this.loopSession !== session) return null;
            const controller = new AbortController();
            const tid = setTimeout(() => controller.abort(), 8000);
            try {
                let res = await fetch(this.ttsURL, {
                    method: "POST", headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({ 
                        text: safeText, 
                        voice: voice || (this.settings && this.settings.voice) || "zh-CN-XiaoxiaoNeural" 
                    }),
                    signal: controller.signal
                });
                clearTimeout(tid);
                if (!res.ok) throw new Error("HTTP " + res.status);
                let blob = await res.blob();
                if (blob.size === 0) throw new Error("Empty");
                return URL.createObjectURL(blob);
            } catch (e) {
                clearTimeout(tid);
                if (attempt === 2) return "speech_synthesis";
                await new Promise(r => setTimeout(r, 800));
            }
        }
        return "speech_synthesis";
    }

    updateUI() {
        let title = "序章";
        if (this.chapters && this.chapters.length > 0) {
            for (let i = this.chapters.length - 1; i >= 0; i--) {
                if (this.cursor >= this.chapters[i].lineIndex) { title = this.chapters[i].title; break; }
            }
        }
        // 核心挂载：实时投射小说进度到手机系统状态栏
        this.updateMediaSessionMetadata(title);
        // 灵动岛胶囊智能滚动文本同步与性能优化
        let scroller = document.getElementById("capsule-scroller");
        let container = document.querySelector(".capsule-text-container");
        if (scroller && container) {
            let targetText = this.lines && this.lines.length > 0 ? "轻触继续听" : "▶ 点击任意处唤醒神经接入";
            if (this.enabled && this.lines && this.lines.length > 0) {
                targetText = this.isBuffering ? "⏳ 神经数据连接中..." : `${this.novelTitle} - ${title}`;
            }

            // 性能优化：仅当文本真正变化时才触发 DOM 变更和重绘计算
            if (scroller._lastText !== targetText) {
                scroller.innerText = targetText;
                scroller._lastText = targetText;

                if (this.isBuffering) {
                    scroller.classList.remove("scrolling");
                    scroller.style.setProperty('--scroll-dist', `0px`);
                } else {
                    requestAnimationFrame(() => {
                        if (scroller.scrollWidth > container.clientWidth) {
                            scroller.classList.add("scrolling");
                            scroller.style.setProperty('--scroll-dist', `-${scroller.scrollWidth - container.clientWidth}px`);
                        } else {
                            scroller.classList.remove("scrolling");
                            scroller.style.setProperty('--scroll-dist', `0px`);
                        }
                    });
                }
            }
        }

        // 更新播放控制图标（开启状态下，说话或缓冲均显示暂停键，允许用户随时中断）
        let capsuleIcon = document.getElementById("play-pause-icon");
        if (capsuleIcon) {
            const playSVG = `<svg viewBox="0 0 24 24" width="14" height="14" fill="white"><path d="M8 5v14l11-7z"/></svg>`;
            const pauseSVG = `<svg viewBox="0 0 24 24" width="14" height="14" fill="white"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>`;
            capsuleIcon.innerHTML = (this.enabled && (this.isSpeaking || this.isBuffering)) ? pauseSVG : playSVG;
        }

        // 更新进度环 (Perimeter ~ 668.5)
        const aura = document.getElementById("capsule-aura-bar");
        if (aura) {
            const progress = this.getChapterProgress();
            const dash = 668.5;
            aura.style.strokeDashoffset = dash * (1 - progress);
        }

        if (typeof window._syncIdleState === 'function') window._syncIdleState();
    }

    getChapterProgress() {
        if (!this.lines.length || !this.chapters.length) return 0;
        let start = 0, end = this.lines.length;
        for (let i = 0; i < this.chapters.length; i++) {
            if (this.cursor >= this.chapters[i].lineIndex) {
                start = this.chapters[i].lineIndex;
                if (i < this.chapters.length - 1) end = this.chapters[i + 1].lineIndex;
                else end = this.lines.length;
            }
        }
        let totalChars = 0, readChars = 0;
        for (let j = start; j < end; j++) {
            let len = (this.lines[j] && this.lines[j].t) ? this.lines[j].t.length : 0;
            totalChars += len;
            if (j < this.cursor) readChars += len;
        }
        return totalChars > 0 ? (readChars / totalChars) : 0;
    }

    async startPrefetchLoop() {
        if (this._prefetchLoopActive) return;
        this._prefetchLoopActive = true;
        while (true) {
            const currentSession = this.loopSession; // 归一化名词：当前会话快照
            // 提升预取深度到 6，应对不稳定的网络
            if (!this.enabled || !this.lines.length || this.audioBufferArray.length >= 6) {
                await new Promise(r => setTimeout(r, 500));
                continue;
            }
            let line = this.lines[this.fetchCursor];
            if (!line) {
                await new Promise(r => setTimeout(r, 1000));
                continue;
            }

            // 核心修复：极其安全的文本提取
            let textToRead = typeof line === 'string' ? line : (line.t || "");
            let voiceToUse = typeof line === 'string' ? null : line.v;

            if (!textToRead || String(textToRead).trim() === "") {
                this.fetchCursor = (this.fetchCursor + 1) % this.lines.length;
                continue;
            }

            let url = await this.fetchTTS(textToRead, voiceToUse);

            if (this.loopSession !== currentSession) {
                if (url && url !== "speech_synthesis") URL.revokeObjectURL(url);
                continue;
            }

            if (url) {
                let item = { url, session: currentSession };
                if (url === "speech_synthesis") {
                    item.obj = {
                        isSpeech: true, text: textToRead, paused: true, ended: false,
                        play: async function() {
                            this.paused = false; this.ended = false;
                            if (window.speechSynthesis) window.speechSynthesis.cancel(); 
                            return new Promise((resolve) => {
                                let u = new SpeechSynthesisUtterance(this.text);
                                u.lang = "zh-CN";
                                u.rate = window.AudioManager ? window.AudioManager.playbackRate || 1.0 : 1.0;
                                u.onend = () => { this.ended = true; this.paused = true; if(this.onended) this.onended(); resolve(); };
                                u.onerror = () => { this.ended = true; this.paused = true; if(this.onerror) this.onerror(); resolve(); };
                                if (window.speechSynthesis) {
                                    window.speechSynthesis.speak(u);
                                } else {
                                    this.ended = true; resolve();
                                }
                            });
                        },
                        pause: function() { this.paused = true; if (window.speechSynthesis) window.speechSynthesis.cancel(); }
                    };
                } else { 
                    item.obj = new Audio(url); 
                }
                this.audioBufferArray.push(item);
                this.fetchCursor = (this.fetchCursor + 1) % this.lines.length;
                this.updateUI();
            }
        }
    }

    async startPlayLoop() {
        if (this._playLoopActive) return;
        this._playLoopActive = true;
        while (true) {
            // 暂停状态：交出 CPU，仅在状态发生变化时触发一次 UI 刷新，防止每 100ms 狂刷 DOM
            if (!this.enabled) {
                if (this.isSpeaking || this.isBuffering) {
                    this.isSpeaking = false;
                    this.isBuffering = false;
                    this.updateUI();
                }
                await new Promise(r => setTimeout(r, 100));
                continue;
            }
            const sessionAtStep = this.loopSession;
            // 缓冲中：当前会话已启用，但预取队列尚未准备好
            if (this.audioBufferArray.length === 0) {
                if (!this.isBuffering) {
                    this.isBuffering = true;
                    this.updateUI();
                }
                if (this.isSpeaking) {
                    this.isSpeaking = false;
                    this.updateUI();
                }
                await new Promise(r => setTimeout(r, 200));
                continue;
            }

            // 当有音频可以播放时，解除缓冲状态
            if (this.isBuffering) {
                this.isBuffering = false;
                this.updateUI();
            }
            const item = this.audioBufferArray.shift();
            if (!item || item.session !== this.loopSession) {
                if (item && item.url && item.url !== "speech_synthesis") {
                    if (item.obj && typeof item.obj.pause === 'function') {
                        item.obj.removeAttribute('src');
                        if (typeof item.obj.load === 'function') item.obj.load();
                    }
                    URL.revokeObjectURL(item.url);
                }
                continue;
            }

            // 确保播放前杀死一切之前的声音残留
            this.stopAllAudio();

            this.isSpeaking = true; this.updateUI();
            const audio = item.obj;
            this.currentAudio = audio;
            
            // 🚨 核心修复：在这里必须恢复 1.0 音量！否则上一句会被“静默播放”，导致漫长等待+跳句！
            if (this.currentAudio.volume !== undefined) {
                this.currentAudio.volume = 1.0;
            }

            if (!audio.isSpeech) {
                audio.playbackRate = this.playbackRate || 1.0;
            }

            let finished = false;
            // 高灵敏哨兵机制
            await Promise.race([
                new Promise(async (resolve) => {
                    this.currentAudio.onended = () => { finished = true; resolve(); };
                    this.currentAudio.onerror = resolve;
                    if (!this.currentAudio.isSpeech && !this.currentAudio._c && this.u && this.ttsInput) {
                        try { this.u.createMediaElementSource(this.currentAudio).connect(this.ttsInput); this.currentAudio._c = true; } catch (e) { }
                    }
                    await this.currentAudio.play().catch(resolve);
                }),
                new Promise(async (resolve) => {
                    while (this.loopSession === sessionAtStep && this.enabled) {
                        await new Promise(r => setTimeout(r, 100));
                    }
                    resolve();
                }),
                new Promise(r => setTimeout(r, 40000))
            ]);

            // 核心修复：如果没有完成播放（可能因为暂停），回收该 item
            if (!finished && this.enabled === false && this.loopSession === sessionAtStep) {
                this.audioBufferArray.unshift(item);
                continue;
            }

            if (item.url && item.url !== "speech_synthesis") {
                if (item.obj && typeof item.obj.pause === 'function') {
                    item.obj.removeAttribute('src');
                    if (typeof item.obj.load === 'function') item.obj.load();
                }
                URL.revokeObjectURL(item.url);
            }
            if (this.loopSession === sessionAtStep && finished) {
                this.cursor = (this.cursor + 1) % this.lines.length;
                // 将最新进度同步至高维引擎
                if (window.ProgressManager) {
                    window.ProgressManager.updateRecord(this.novelID, this.cursor, this.lines.length);
                }
                localStorage.setItem("novel_index", this.cursor.toString());
            }
        }
    }
}
