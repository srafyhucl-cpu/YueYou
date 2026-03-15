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
        this.isPlaying = false;
        this.prefetching = false;

        this.ttsURL = (typeof AppConfig !== "undefined" ? AppConfig.ttsURL : "http://8.218.177.149:3000/api/v1/tts/createStream");
        this.enabled = this.settings.storyTTS;
        this.loopSession = 1;

        this._playLoopActive = false;
        this._prefetchLoopActive = false;

        this.playbackRate = parseFloat(localStorage.getItem("setting_tts_rate") || "1.0");
        this.initLibrary();
    }

    unlockAudio() {
        this.initContext();
        if (this.u && this.u.state === "suspended") this.u.resume().catch(() => { });
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
        this.heartbeat();
    }

    async loadNovel(id, title, newCursor = null) {
        try {
            const currentSession = ++this.loopSession;
            this.stopAllAudio();
            this.audioBufferArray.forEach(x => { if (x.url && x.url !== 'speech_synthesis') URL.revokeObjectURL(x.url); });
            this.audioBufferArray = [];
            
            // 强制将当前小说 ID 锁定为字符串，供高维引擎精准对接
            this.novelID = String(id);
            this.novelTitle = title;

            let data = await LocalDB.loadBook(id);
            if (!data) return;
            if (this.loopSession !== currentSession) return;

            // 兼容旧版本纯数组数据，并动态解析章节
            if (Array.isArray(data)) {
                this.lines = data.map(item => typeof item === 'string' ? { t: item } : item);
                this.chapters = [];
                const chapterRegex = /^\s*(?:\d{1,5}\s+.*|\d{1,5}\s*第[0-9零一二三四五六七八九十百千两]+[章回节卷集部篇].*|第[0-9零一二三四五六七八九十百千两]+[章回节卷集部篇].*)$/;
                this.lines.forEach((line, index) => {
                    if (chapterRegex.test(line.t)) {
                        this.chapters.push({ title: line.t.trim(), lineIndex: index });
                    }
                });
            } else {
                this.lines = data.lines || [];
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
        } catch (e) { console.error("LoadNovel error:", e); }
    }

    stopAllAudio() {
        if (this.currentAudio) {
            try {
                this.currentAudio.pause();
                this.currentAudio.currentTime = 0;
                if (this.currentAudio.isSpeech) window.speechSynthesis.cancel();
            } catch (e) { }
        }
        window.speechSynthesis.cancel();
    }

    heartbeat() {
        this.unlockAudio();
        this.startPlayLoop();
        this.startPrefetchLoop();
    }

    setEnabled(enable) {
        this.enabled = enable;
        localStorage.setItem("setting_story_tts", enable ? "true" : "false");

        if (enable) {
            this.heartbeat();
        } else {
            this.stopAllAudio();
            this.isSpeaking = false;
            this.updateUI();
        }
    }

    refreshSession() {
        this.loopSession++;
        this.stopAllAudio();
        this.audioBufferArray.forEach(x => { if (x.url && x.url !== "speech_synthesis") URL.revokeObjectURL(x.url); });
        this.audioBufferArray = [];
        this.fetchCursor = this.cursor; // 从当前行重新开始抓取
        this.heartbeat();
    }

    jumpToChapter(lineIndex) {
        this.loopSession++;
        this.stopAllAudio();
        this.audioBufferArray.forEach(x => { if (x.url && x.url !== "speech_synthesis") URL.revokeObjectURL(x.url); });
        this.audioBufferArray = [];
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
                    body: JSON.stringify({ text: safeText, voice: voice || "zh-CN-XiaoxiaoNeural" }),
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
        // 灵动岛胶囊智能滚动文本同步
        let scroller = document.getElementById("capsule-scroller");
        let container = document.querySelector(".capsule-text-container");
        if (scroller && container) {
            let currentChapterTitle = title;
            scroller.innerText = (this.enabled && this.lines.length > 0) ? `${this.novelTitle} - ${currentChapterTitle}` : "▶ 点击任意处唤醒神经接入";
            
            // 下一帧计算超长文本，赋予 CSS 变量进行乒乓滚动
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
        let statusEl = document.getElementById("player-status-icon");
        if (statusEl) statusEl.innerText = this.isSpeaking ? "⏸" : "▶";
        let capsuleIcon = document.getElementById("play-pause-icon");
        if (capsuleIcon) capsuleIcon.innerText = this.enabled ? "⏸" : "▶";

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
            if (!this.enabled || !this.lines.length || this.audioBufferArray.length >= 3) {
                await new Promise(r => setTimeout(r, 500));
                continue;
            }
            const session = this.loopSession;
            const line = this.lines[this.fetchCursor];

            // --- 核心修复区：安全提取文本，向下兼容旧数据 ---
            let textToRead = typeof line === 'string' ? line : line.t;
            let voiceToUse = (typeof line === 'object' && line.v) ? line.v : (this.settings.voice || "zh-CN-XiaoxiaoNeural");

            // 拦截空字符串或 undefined，防止报错或错误朗读
            if (!textToRead || textToRead.trim() === "" || String(textToRead) === "undefined") {
                this.fetchCursor = (this.fetchCursor + 1) % this.lines.length;
                continue;
            }
            // ------------------------------------------------

            const url = await this.fetchTTS(textToRead, voiceToUse); // 使用安全文本

            if (this.loopSession !== session) {
                if (url && url !== "speech_synthesis") URL.revokeObjectURL(url);
                continue;
            }

            if (url) {
                let item = { url, session };
                if (url === "speech_synthesis") {
                    item.obj = {
                        isSpeech: true, text: textToRead, // 使用安全文本
                        play: function () {
                            return new Promise(resolve => {
                                window.speechSynthesis.cancel();
                                let u = new SpeechSynthesisUtterance(this.text);
                                u.lang = "zh-CN";
                                u.rate = window.AudioManager.playbackRate || 1.0;
                                u.onend = () => resolve(); u.onerror = () => resolve();
                                window.speechSynthesis.speak(u);
                            });
                        },
                        pause: () => window.speechSynthesis.cancel()
                    };
                } else { item.obj = new Audio(url); }
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
            if (!this.enabled) {
                this.isSpeaking = false; this.updateUI();
                await new Promise(r => setTimeout(r, 100));
                continue;
            }
            const sessionAtStep = this.loopSession;
            if (this.audioBufferArray.length === 0) {
                this.isSpeaking = false; this.updateUI();
                await new Promise(r => setTimeout(r, 100));
                continue;
            }
            const item = this.audioBufferArray.shift();
            if (!item || item.session !== this.loopSession) {
                if (item && item.url && item.url !== "speech_synthesis") URL.revokeObjectURL(item.url);
                continue;
            }

            // 确保播放前杀死一切之前的声音残留
            this.stopAllAudio();

            this.isSpeaking = true; this.updateUI();
            const audio = item.obj;
            this.currentAudio = audio;
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

            // 核心修复：如果不是正常播完（比如因为暂停而被哨兵中断），将 item 放回队列首部
            if (!finished && this.enabled === false && this.loopSession === sessionAtStep) {
                this.audioBufferArray.unshift(item);
                continue;
            }

            if (item.url && item.url !== "speech_synthesis") URL.revokeObjectURL(item.url);
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
