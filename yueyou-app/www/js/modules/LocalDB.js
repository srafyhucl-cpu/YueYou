// ======================================
// 本地 IndexedDB 管理器 (LocalDB.js)
// ======================================

const DB_NAME = "LocalBookDB";
const STORE_NAME = "books";

export const LocalDB = {
    async open() {
        // 打开 IndexedDB 数据库：用于存储超大体积的 TXT 小说内容
        return new Promise((resolve) => {
            let req = window.indexedDB.open(DB_NAME, 2);
            req.onupgradeneeded = e => {
                if (!e.target.result.objectStoreNames.contains(STORE_NAME)) {
                    // 创建名为 books 的对象仓库
                    e.target.result.createObjectStore(STORE_NAME);
                }
            };
            req.onsuccess = e => resolve(e.target.result);
            req.onerror = () => resolve(null);
        });
    },

    async saveBook(id, rawData) {
        let db = await this.open();
        if (!db) return;

        // 核心修复：在此处拦截数据，强制格式化并提取章节
        let formattedLines = [];
        let chapters = [];
        const chapterRegex = /^\s*(?:第\s*[0-9零一二三四五六七八九十百千两]+[章节回卷集部篇]|正文\s+第\s*[0-9零一二三四五六七八九十百千两]+[章节回卷集部篇]|[序前引楔][言子]|[Cc]hapter\s*\d+|\d{1,5}\s+).*/;

        if (Array.isArray(rawData)) {
            for (let i = 0; i < rawData.length; i++) {
                let item = rawData[i];
                let textStr = typeof item === 'string' ? item : (item.t || "");
                if (!textStr.trim()) continue;

                // 强制转换为标准对象格式
                formattedLines.push(typeof item === 'string' ? { t: textStr } : item);

                // 正则匹配章节
                if (chapterRegex.test(textStr)) {
                    chapters.push({ title: textStr.trim(), lineIndex: formattedLines.length - 1 });
                }
            }
        } else {
            // 如果已经是标准对象
            formattedLines = rawData.lines || [];
            chapters = rawData.chapters || [];
        }

        return new Promise(resolve => {
            let tx = db.transaction(STORE_NAME, "readwrite");
            // 以 {lines, chapters} 的标准结构存入数据库
            tx.objectStore(STORE_NAME).put({ lines: formattedLines, chapters: chapters }, id.toString());
            tx.oncomplete = () => resolve(true);
            tx.onerror = () => resolve(false);
        });
    },

    async loadBook(id) {
        let db = await this.open();
        if (!db) return null;
        return new Promise(resolve => {
            try {
                let tx = db.transaction(STORE_NAME, "readonly");
                let req = tx.objectStore(STORE_NAME).get(id.toString());
                req.onsuccess = () => resolve(req.result);
                req.onerror = () => resolve(null);
            } catch (e) { resolve(null); }
        });
    },

    async deleteBook(id) {
        let db = await this.open();
        if (!db) return false;
        return new Promise(resolve => {
            let tx = db.transaction(STORE_NAME, "readwrite");
            tx.objectStore(STORE_NAME).delete(id.toString());
            tx.oncomplete = () => resolve(true);
            tx.onerror = () => resolve(false);
        });
    }
};
