package models

import (
	"database/sql"
	"log"

	_ "modernc.org/sqlite"
)

// DB 全局数据库对象
var DB *sql.DB

// InitDB 初始化数据库并创建表
func InitDB() {
	var err error
	DB, err = sql.Open("sqlite", "2048.db")
	if err != nil {
		log.Fatalf("Failed to open database: %v", err)
	}

	// 开启 WAL 模式提升并发写入性能
	_, err = DB.Exec(`PRAGMA journal_mode = WAL;`)
	if err != nil {
		log.Printf("Failed to set PRAGMA journal_mode: %v", err)
	}

	createTables := `
	CREATE TABLE IF NOT EXISTS users (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		phone VARCHAR(20) UNIQUE NOT NULL,
		password_hash VARCHAR(255) NOT NULL DEFAULT ''
	);

	CREATE TABLE IF NOT EXISTS game_states (
		user_id INTEGER UNIQUE NOT NULL,
		board_data TEXT NOT NULL,
		score INTEGER NOT NULL,
		novel_index INTEGER NOT NULL DEFAULT 0,
		current_novel_id INTEGER NOT NULL DEFAULT 1,
		updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
		FOREIGN KEY(user_id) REFERENCES users(id)
	);

	CREATE TABLE IF NOT EXISTS novels (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		title VARCHAR(255) UNIQUE NOT NULL,
		content_json TEXT NOT NULL,
		total_paragraphs INTEGER NOT NULL DEFAULT 0,
		uploader_id INTEGER NOT NULL,
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
		FOREIGN KEY(uploader_id) REFERENCES users(id)
	);

	CREATE TABLE IF NOT EXISTS novel_progress (
		user_id INTEGER NOT NULL,
		novel_id INTEGER NOT NULL,
		paragraph_index INTEGER NOT NULL DEFAULT 0,
		PRIMARY KEY(user_id, novel_id),
		FOREIGN KEY(user_id) REFERENCES users(id),
		FOREIGN KEY(novel_id) REFERENCES novels(id)
	);
	`

	_, err = DB.Exec(createTables)
	if err != nil {
		log.Fatalf("Failed to create tables: %v", err)
	}

	// 兼容老的数据库，尝试加入新字段
	_, _ = DB.Exec("ALTER TABLE game_states ADD COLUMN current_novel_id INTEGER NOT NULL DEFAULT 1")
	_, _ = DB.Exec("ALTER TABLE users ADD COLUMN password_hash VARCHAR(255) NOT NULL DEFAULT ''")
	_, _ = DB.Exec("ALTER TABLE novels ADD COLUMN total_paragraphs INTEGER NOT NULL DEFAULT 0")

	// 初始化一个默认小说（如果没有的话）
	var count int
	DB.QueryRow("SELECT COUNT(*) FROM novels").Scan(&count)
	if count == 0 {
		defaultContent := `[
			{"v": "zh-CN-YunyangNeural", "t": "东汉末年，天下大乱。黄巾贼寇四起，百姓流离失所。朝廷张榜招募义兵，有志之士纷纷响应。"},
			{"v": "zh-CN-YunxiNeural", "t": "我乃中山靖王之后，汉景帝阁下玄孙，姓刘名备，字玄德。见天下苍生受苦，常怀匡扶汉室之志，奈何力单势薄，无从施展啊。"},
			{"v": "zh-CN-YunyangNeural", "t": "刘备在榜文前长叹一声。忽闻身后一人厉声高喝。"},
			{"v": "zh-CN-YunxiaNeural", "t": "大丈夫不与国家出力，在这里长吁短叹，有什么用！我乃燕人张飞，字翼德，世居涿郡，颇有庄田。今愿与你共图大事！"},
			{"v": "zh-CN-YunxiNeural", "t": "我虽有此心，奈何满腔热血，无处挥洒。今得壮士相助，实乃天意！"},
			{"v": "zh-CN-YunyangNeural", "t": "二人相谈甚欢，遂入村中酒馆饮酒。正饮间，一大汉推门而入，身高九尺，须长二尺，面如重枣，唇若涂脂，相貌堂堂，威风凛凛。"},
			{"v": "zh-CN-YunjianNeural", "t": "小二，快斟酒来！我要赶去投军，先饮一碗壮行酒。"},
			{"v": "zh-CN-YunxiNeural", "t": "壮士请过来同坐。敢问尊姓大名？"},
			{"v": "zh-CN-YunjianNeural", "t": "某姓关名羽，字云长，河东解良人氏。因本处势豪倚势凌人，被吾杀了。逃难江湖，五六年矣。今闻此处招军破贼，特来应募。"},
			{"v": "zh-CN-YunxiaNeural", "t": "好！正合我意！我庄后有一座桃园，花开正盛。明日我三人何不就在园中结为兄弟，同心协力，共图大事？"},
			{"v": "zh-CN-YunyangNeural", "t": "次日，三人来到张飞庄后桃园。但见桃花灿烂如锦，落英缤纷。备下乌牛白马祭礼，焚香再拜，对天盟誓。"},
			{"v": "zh-CN-YunxiNeural", "t": "念刘备、关羽、张飞，虽然异姓，既结为兄弟，则同心协力，救困扶危，上报国家，下安黎庶。"},
			{"v": "zh-CN-YunjianNeural", "t": "不求同年同月同日生。"},
			{"v": "zh-CN-YunxiaNeural", "t": "但愿同年同月同日死！"},
			{"v": "zh-CN-YunxiNeural", "t": "皇天后土，实鉴此心。背义忘恩，天人共戮！"},
			{"v": "zh-CN-YunyangNeural", "t": "誓毕，拜刘备为兄，关羽次之，张飞为弟。桃园春风浩荡，三人从此肝胆相照，共赴天下。"},
			{"v": "zh-CN-YunxiaNeural", "t": "大哥二哥！我张飞散尽家财，招得乡勇三百余人。刀枪剑戟，样样齐全。随时可以出发！"},
			{"v": "zh-CN-YunjianNeural", "t": "兄长放心。关某虽一介武夫，但既已结义，便当以性命相报。刀山火海，在所不辞任务。"},
			{"v": "zh-CN-YunxiNeural", "t": "有二位贤弟相助，何愁大事不成？今日出发，破黄巾，安社稷，还天下一个太平！"},
			{"v": "zh-CN-YunyangNeural", "t": "桃花纷飞之中，三骑绝尘而去。自此，刘关张三兄弟的传奇，正式拉开了波澜壮阔的序幕。后人有诗赞曰：英雄露颖在今朝，一试矛兮一试刀。初出便将威力展，三分好把姓名标。"}
		]`
		DB.Exec("INSERT INTO users (id, phone) VALUES (1, 'system') ON CONFLICT DO NOTHING")
		DB.Exec("INSERT INTO novels (id, title, content_json, total_paragraphs, uploader_id) VALUES (1, '三国演义·桃园结义片段', ?, 20, 1)", defaultContent)
	}

	log.Println("Database initialized successfully.")
}
