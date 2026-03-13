// ======================================
// 本地 IndexedDB 管理器 (LocalDB.js)
// ======================================

const DB_NAME = "LocalBookDB";
const STORE_NAME = "books";

export const LocalDB = {
    async open() {
        return new Promise((resolve) => {
            let req = window.indexedDB.open(DB_NAME, 2);
            req.onupgradeneeded = e => {
                if (!e.target.result.objectStoreNames.contains(STORE_NAME)) {
                    e.target.result.createObjectStore(STORE_NAME);
                }
            };
            req.onsuccess = e => resolve(e.target.result);
            req.onerror = () => resolve(null);
        });
    },

    async saveBook(id, lines) {
        let db = await this.open();
        if(!db) return;
        return new Promise(resolve => {
            let tx = db.transaction(STORE_NAME, "readwrite");
            tx.objectStore(STORE_NAME).put(lines, id.toString());
            tx.oncomplete = () => resolve(true);
            tx.onerror = () => resolve(false);
        });
    },

    async loadBook(id) {
        let db = await this.open();
        if(!db) return null;
        return new Promise(resolve => {
            try {
                let tx = db.transaction(STORE_NAME, "readonly");
                let req = tx.objectStore(STORE_NAME).get(id.toString());
                req.onsuccess = () => resolve(req.result);
                req.onerror = () => resolve(null);
            } catch(e) { resolve(null); }
        });
    }
};
