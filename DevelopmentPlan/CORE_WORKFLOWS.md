# 阅游 (YueYou) - 核心业务流程文档

本文档使用 PlantUML 时序图详细记录了阅游的核心业务流程，供 AI 与开发人员精确理解系统交互、数据流向及异常处理分支。

## 1. TTS 朗读核心流程

该流程涵盖了从触发朗读、检查缓存、向服务端请求下载到最终播放与状态同步的完整链路。

```plantuml
@startuml
skinparam maxMessageSize 150
autonumber

actor "用户 / UI" as User
participant "ReaderProvider" as Reader
participant "TtsEngineService" as Engine
participant "TtsCacheManager" as Cache
participant "TtsHttpClient" as Http
participant "Go 业务服务器" as GoServer
participant "OSS/CDN" as OSS
participant "TtsAudioPlayer" as Player

User -> Reader: toggleTTS()
activate Reader

alt _sentences 为空或未加载书籍
    Reader --> User: 返回 noContent
else 正常状态
    Reader -> Engine: play()
    activate Engine
    
    Engine -> Engine: 检查缓冲队列 (预取)
    Engine -> Cache: 检查是否有本地缓存 (URL/音频)
    activate Cache
    Cache --> Engine: 命中或未命中
    deactivate Cache
    
    alt 缓存未命中
        Engine -> Http: POST 获取播放 URL (附带文本)
        activate Http
        Http -> GoServer: 校验与分发请求
        activate GoServer
        GoServer --> Http: {"status": "success", "url": "https://..."}
        deactivate GoServer
        Http --> Engine: 返回响应解析 URL
        deactivate Http
        
        Engine -> Http: GET 下载音频文件
        activate Http
        Http -> OSS: 请求音频流
        activate OSS
        OSS --> Http: 音频二进制数据
        deactivate OSS
        Http -> Cache: 保存至本地缓存
        activate Cache
        Cache --> Http: 存储成功
        deactivate Cache
        Http --> Engine: 下载完成，返回本地路径
        deactivate Http
    end
    
    Engine -> Player: setSource(本地缓存路径)
    activate Player
    Player --> Engine: 资源准备完毕
    Engine -> Player: resume()
    Player --> Engine: 播放中
    deactivate Player
    
    Engine --> Reader: 状态变更为 playing
    Reader --> User: 更新 UI 播放状态
    deactivate Engine
end
deactivate Reader
@enduml
```

## 2. 书籍导入与解析流程

该流程涵盖从本地选择文本文件、读取、在独立 Isolate 中清洗和解析、再到挂载至 Provider 的完整链路。

```plantuml
@startuml
skinparam maxMessageSize 150
autonumber

actor 用户 as User
participant "CyberImportButton" as UI
participant "FilePicker" as Picker
participant "FileImportService" as Import
participant "TextParser (Isolate)" as Parser
participant "ReaderProvider" as Reader

User -> UI: 点击导入书籍
activate UI
UI -> Picker: 唤起文件选择器
activate Picker
Picker --> UI: 返回所选 .txt 文件路径
deactivate Picker

UI -> Import: importTxtFile(path)
activate Import
Import -> Import: 校验文件后缀与大小
Import -> Import: 读取文件文本 (Isolate 异步读取)
Import --> UI: 返回 rawText 与书名
deactivate Import

UI -> Reader: loadBook(rawText, bookId)
activate Reader
Reader -> Reader: 置 _isParsing = true\n并 notifyListeners() (UI 显示加载态)

Reader -> Parser: TextParser.parse(rawText)
activate Parser
note right of Parser
  在独立 Isolate 中执行：
  1. 预清洗合并符号
  2. 按照标点精准切分
  3. 长句强制二次截断 (防溢出)
end note
Parser --> Reader: 返回 ParseResult (sentences, rawLineOrigins)
deactivate Parser

Reader -> Reader: 映射原始行与句子，清理章节标题
Reader -> Reader: 保存进度至 StorageService
Reader -> Reader: 置 _isParsing = false\n并 notifyListeners()
Reader --> UI: 加载完毕
deactivate Reader
UI --> User: 渲染小说阅读/提词器界面
deactivate UI
@enduml
```

## 3. 2048 游戏核心逻辑

该流程说明了用户的滑动操作如何触发矩阵变换、合并得分、驱动动画粒子并在必要时结合吉祥物反馈。

```plantuml
@startuml
skinparam maxMessageSize 150
autonumber

actor "用户 (手势识别)" as User
participant "SquareBoard" as UI
participant "GameProvider" as Game
participant "StorageService" as Storage
participant "Cyber吉祥物" as Mascot

User -> UI: 滑动手势 (Up/Down/Left/Right)
activate UI
UI -> Game: move(Direction)
activate Game

Game -> Game: _lastMoveDirection = Direction
Game -> Game: 判断是否已 isOver
alt isOver = true
    Game --> UI: 直接返回，不响应
else isOver = false
    Game -> Game: 遍历计算每行/列的方块位移
    Game -> Game: 相同数字且未合并过的方块合并 (value * 2)
    Game -> Game: 记录最大合并数值 _lastMergedValue
    
    alt 有方块发生位移或合并
        Game -> Game: 增加 combo (如上一次也是有效移动)
        Game -> Game: updateScore() 重新计算总分
        Game -> Game: 随机生成 1 或 2 个新方块 (2 或 4)
        Game -> Game: 调度 _persistState() (防抖保存状态)
        Game -> Storage: 异步保存棋盘与分数
        
        Game -> Game: _checkGameOver() 检查是否无法再移动
        alt 无法再移动
            Game -> Game: _markGameOver()
        end
        
        Game -> Game: notifyListeners()
        Game --> UI: 状态更新，UI执行平移/合并/新生动画
        
        alt 产生了高分合并 (_lastMergedValue 大于阈值)
            Game -> Mascot: 触发吉祥物欢呼/兴奋动画
        end
    else 没有任何位移或合并 (无效滑动)
        Game -> Game: _combo = 0 (断连)
        Game -> Mascot: 触发吉祥物困惑/生气动画
        Game --> UI: 不触发重绘
    end
end
deactivate Game
deactivate UI
@enduml
```
