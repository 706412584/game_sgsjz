# 三国神将录 - 项目架构文档

> 最后更新: 2026-04-21

---

## 1. 项目概述

三国神将录是一款三国题材自动战斗养成手游，横屏 16:9。

- **引擎**: UrhoX (Lua 5.4)
- **网络架构**: 纯 C/S (Client/Server)，persistent_world 模式
- **数据持久化**: serverCloud（服务端权威）
- **UI 框架**: urhox-libs/UI (Yoga Flexbox)

### 核心玩法

| 系统 | 说明 |
|------|------|
| 推图 | 100 张地图 × 24 节点（战斗/事件/宝箱/精英/BOSS） |
| 战斗 | 5v5 自动回合制（前排2 + 后排3），三围体系（统/勇/智） |
| 养成 | 英雄升级(经验酒)、升星(碎片)、32+ 英雄收集 |
| 招募 | 招募令抽卡，碎片合成 |
| 阵容 | 阵型选择 + 位置编排 |

---

## 2. 网络架构

### 2.1 纯 C/S 模式

```
┌─────────────────┐         ┌─────────────────────────┐
│  客户端 (Client) │ ◄─────► │  服务端 (Server)          │
│  client_main.lua │  事件   │  server_main.lua          │
│                  │         │                           │
│  - UI 渲染展示    │         │  - 游戏逻辑（战斗/升级等）  │
│  - 用户输入采集    │         │  - 状态持有 & 权威修改      │
│  - 状态只读展示    │         │  - serverCloud 读写        │
└─────────────────┘         └─────────────────────────┘
```

- **服务端权威**: 所有状态修改（升级、战斗、招募等）只在服务端执行
- **客户端只读**: 客户端持有状态副本，仅用于 UI 展示，不直接修改
- **事件驱动**: 客户端发送 `GAME_ACTION`，服务端处理后通过 `GAME_SYNC` 同步状态

### 2.2 构建配置

```
entry@client = client_main.lua
entry@server = server_main.lua
persistent_world.enabled = true
```

### 2.3 连接生命周期

```
客户端启动
  │
  ├─ UI.Init() → 构建底层游戏 UI（不可见）
  ├─ ClientNet.Init() → 建立网络连接
  └─ 显示【开始界面】覆盖层 (zIndex=900)
       │
       ├─ 并行线1: 云探测 startProbe()
       │    idle → probe → loading → done
       │
       └─ 并行线2: 用户操作
            选择区服 → 点击"进入游戏"
       │
  enterGameFromStart()  ← 两线汇合
       │
  SendGameAction("game_start")
       │
  服务端 HandleClientReady → 身份升级 → 选服 → 加载存档
       │
  服务端发 GAME_INIT → 客户端收到完整状态
       │
  关闭开始界面 → 进入游戏
```

### 2.4 身份升级

```
连接建立 → 匿名临时 ID
  │
  客户端发 CLIENT_READY
  │
  服务端 HandleClientReady:
    1. 从 connection.identity["user_id"] 提取真实 userId
       userId = tonumber(identityUid:GetInt64())
    2. 更新映射: tempId → realUserId
    3. 检查重复登录 → 踢旧连接 ("duplicate_login")
    4. 等待选服后再加载数据（防止 sid=0 时误操作）
```

---

## 3. 分区（区服）设计

### 3.1 分区模型

- 每个区服 = 独立存档 + 独立排行榜
- 玩家可在不同区服创建不同进度
- 换服 = 保存旧区数据 → 加载新区数据

### 3.2 区服列表

存储在全局 key `"server_list"` (userId=0)：

```lua
[
    { id = 1, name = "S1 桃园", status = "正常" },
    { id = 2, name = "S2 虎牢", status = "正常" },
]
```

状态: `"正常"` | `"火爆"` | `"维护"`

### 3.3 realmKey 隔离

```lua
local function realmKey(baseKey, sid)
    if not sid or sid == 0 then return baseKey end
    return baseKey .. "_" .. tostring(sid)
end

-- 示例:
-- realmKey("save", 1) → "save_1"
-- realmKey("power", 2) → "power_2"
```

### 3.4 换服流程

```
客户端发 SERVER_SELECT (serverId)
  │
  服务端 HandleServerSelect:
    1. 保存旧区数据 → BatchSet(uid, save_{oldSid}, ...)
    2. 更新映射 → userServerId_[uid] = newSid
    3. 加载新区数据 → BatchGet(uid, save_{newSid}, ...)
    4. 发 GAME_INIT → 客户端刷新
```

---

## 4. 云端 Key 设计

### 4.1 玩家数据 (per-user, 带区服后缀)

| Key | 类型 | 说明 |
|-----|------|------|
| `save_{sid}` | Score (JSON) | 完整游戏存档 |
| `save_bak_{sid}` | Score (JSON) | 兜底备份（定时覆盖） |
| `name_{sid}` | Score (string) | 玩家昵称 |
| `power_{sid}` | iScore (int) | 总战力（可排行） |
| `stage_{sid}` | iScore (int) | 最远关卡编号（可排行） |

### 4.2 存档 JSON 结构 (`save_{sid}`)

```lua
{
    -- 基础资源
    copper      = 5000,       -- 铜钱
    yuanbao     = 100,        -- 元宝
    stamina     = 115,        -- 体力
    staminaMax  = 120,
    jianghun    = 0,          -- 将魂
    zhaomuling  = 3,          -- 招募令
    power       = 2450,       -- 总战力

    -- 英雄
    heroes = {
        caocao = { level = 10, star = 3, exp = 200, fragments = 5 },
        lvbu   = { level = 15, star = 2, exp = 0,   fragments = 12 },
        -- ...最多 32 个
    },

    -- 背包
    inventory = {
        exp_wine     = 20,    -- 经验酒
        star_stone   = 0,     -- 升星石
        breakthrough = 0,     -- 突破丹
        awaken_stone = 0,     -- 觉醒石
    },

    -- 阵容
    lineup = {
        formation = "feng_shi",
        front = { "lvbu", "zhangfei" },
        back  = { "zhugeliang", "guanyu", "zhaoyun" },
    },

    -- 推图进度
    currentMap  = 5,
    nodeStars   = { ["1_1"] = 3, ["1_2"] = 2, ... },
    clearedMaps = { [1] = true, [2] = true, ... },

    -- 时间记录
    lastSaveTime    = 1713700000,
    lastStaminaTime = 1713700000,
}
```

预估单个存档 < 10KB，一个 Score key 原子读写。

### 4.3 排行榜 (iScore, 带区服后缀)

| 排行榜 | Key | 排序 |
|--------|-----|------|
| 战力榜 | `power_{sid}` | 降序 |
| 关卡榜 | `stage_{sid}` | 降序 |

排行榜完全按区服隔离：区服1查 `power_1`，区服2查 `power_2`。

### 4.4 全局数据 (userId=0, 无区服后缀)

| Key | 说明 |
|-----|------|
| `server_list` | 区服列表 JSON |

### 4.5 读写示例

```lua
-- 保存
serverCloud:BatchSet(uid)
    :Set(realmKey("save", sid), cjson.encode(state))
    :SetInt(realmKey("power", sid), state.power)
    :SetInt(realmKey("stage", sid), maxStageNum)
    :Save("存档")

-- 加载
serverCloud:BatchGet(uid)
    :Key(realmKey("save", sid))
    :Fetch({
        ok = function(scores, iscores)
            local json = scores[realmKey("save", sid)]
            state = json and cjson.decode(json) or createDefaultState()
        end
    })

-- 排行榜查询
serverCloud:GetRankList(realmKey("power", sid), 1, 20, { ok = ... })
```

---

## 5. 目录结构

```
scripts/
├── client_main.lua           # 客户端入口（thin wrapper → main 游戏逻辑）
├── server_main.lua           # 服务端入口（游戏逻辑、状态管理、云存储）
│
├── network/
│   ├── shared.lua            # 事件常量定义 + 批量注册函数
│   ├── client_net.lua        # 客户端网络（连接/断线重连/身份升级/状态同步）
│   └── cloud_polyfill.lua    # clientCloud → RemoteEvent → serverCloud 透明桥
│
├── data/
│   ├── data_state.lua        # 游戏状态管理（服务端写 / 客户端只读展示）
│   ├── data_heroes.lua       # 英雄数据库（32 英雄，两端共享）
│   ├── data_maps.lua         # 地图数据库（100 地图，两端共享）
│   └── battle_engine.lua     # 战斗引擎（服务端执行）
│
├── ui/
│   ├── theme.lua             # 主题色 & UI 常量
│   ├── components.lua        # 通用 UI 组件（SanButton, HeroAvatar 等）
│   ├── modal_manager.lua     # 弹窗管理器（Panel-based, 非 UI.Modal）
│   ├── hud.lua               # 顶栏 HUD
│   ├── page_city.lua         # 主城页
│   ├── page_map.lua          # 地图选关页
│   ├── page_battle.lua       # 战斗回放页
│   ├── page_heroes.lua       # 英雄养成页
│   ├── page_formation.lua    # 阵容编辑页
│   ├── page_start.lua        # 开始界面（覆盖层, zIndex=900）
│   └── page_server.lua       # 区服选择（嵌入开始界面）
│
└── assets/
    └── Textures/ui/          # UI 贴图（按钮、边框、头像等）
```

### 客户端/服务端代码分布

| 模块 | 客户端 | 服务端 | 说明 |
|------|--------|--------|------|
| `network/shared.lua` | 引用 | 引用 | 事件常量，两端共享 |
| `data/data_heroes.lua` | 引用 | 引用 | 只读数据，两端共享 |
| `data/data_maps.lua` | 引用 | 引用 | 只读数据，两端共享 |
| `data/battle_engine.lua` | - | 引用 | 仅服务端执行战斗 |
| `data/data_state.lua` | 只读 | 读写 | 服务端权威修改 |
| `ui/*` | 引用 | - | 仅客户端渲染 |
| `network/client_net.lua` | 引用 | - | 仅客户端 |
| `server_main.lua` | - | 入口 | 仅服务端 |

---

## 6. 事件通信协议

### 6.1 客户端 → 服务端

| 事件 | 数据 | 说明 |
|------|------|------|
| `CLIENT_READY` | - | 连接就绪，请求身份升级 |
| `SERVER_SELECT` | `{ServerId}` | 选择区服 |
| `GAME_ACTION` | `{Action, Data}` | 游戏操作请求 |

### 6.2 服务端 → 客户端

| 事件 | 数据 | 说明 |
|------|------|------|
| `GAME_INIT` | `{StateJson, UserId}` | 初始化完整状态 |
| `GAME_SYNC` | `{StateJson}` | 定时状态同步（每2秒） |
| `GAME_EVT` | `{Event, Data}` | 单次事件通知（战斗结果等） |
| `KICKED` | `{Reason}` | 被踢下线 |

### 6.3 GAME_ACTION 操作列表

| Action | Data | 说明 |
|--------|------|------|
| `game_start` | - | 进入游戏 |
| `battle` | `{mapId, nodeId, nodeType}` | 发起战斗 |
| `use_exp_wine` | `{heroId, count}` | 使用经验酒 |
| `star_up` | `{heroId}` | 英雄升星 |
| `recruit` | - | 招募 |
| `compose_hero` | `{heroId}` | 碎片合成 |
| `set_lineup` | `{formation, front, back}` | 设置阵容 |

---

## 7. 数据流示例

### 7.1 战斗流程

```
客户端点击关卡节点
  │
  GAME_ACTION { action="battle", data={mapId=1, nodeId=5, nodeType="normal"} }
  │
  服务端:
    1. 校验体力 ≥ cost → 扣除体力
    2. BattleEngine.QuickBattle(state, mapId, nodeId, nodeType) → battleLog
    3. ApplyBattleRewards(state, battleLog) → rewards
    4. 保存状态 → serverCloud
    5. 发 GAME_EVT { event="battle_result", data={log=battleLog, rewards=rewards} }
  │
  客户端收到 → BattlePage 播放战斗回放 → 显示结果弹窗
```

### 7.2 英雄升级流程

```
客户端点击"升级 ×10"
  │
  GAME_ACTION { action="use_exp_wine", data={heroId="lvbu", count=10} }
  │
  服务端:
    1. 校验经验酒库存
    2. DataState.UseExpWine(state, heroId, count)
    3. RecalcPower(state)
    4. 保存 → serverCloud
    5. GAME_SYNC → 客户端刷新 UI
```

---

## 8. 关键约定

### 8.1 英雄 ID

使用拼音: `caocao`, `lvbu`, `zhugeliang`, `guanyu`, `zhaozilong` 等。

### 8.2 品质映射

- `data_heroes.lua` 品质: 1-6（绿→金）
- `theme.lua` 品质色: 1-7（白→金）
- 显示时: `Theme.QualityColor(heroData.quality + 1)`

### 8.3 三围战斗体系

| 属性 | 中文 | 战斗作用 |
|------|------|---------|
| tong | 统率 | 普攻伤害 |
| yong | 勇武 | 战法伤害 |
| zhi  | 智力 | 法攻伤害 |

### 8.4 士气系统

初始 0，命中 +25，被击 +15，击杀 +30，满 100 自动释放战法。

### 8.5 阵型

前排 2 人 + 后排 3 人，20 回合超时判负。
