# 三国神将录 - AI 开发规则

> 项目级智能体规则，所有 AI 会话必须遵守。
> 每次完成功能/修复后，必须 git 提交（见末尾 Git 规则）。

---

## 项目简介

三国题材自动战斗养成手游，横屏 16:9。

- **引擎**: UrhoX (Lua 5.4)
- **架构**: 纯 C/S (persistent_world)
- **数据**: serverCloud 服务端权威
- **UI**: urhox-libs/UI (Yoga Flexbox)

---

## 一、架构规则

### 1.1 纯 C/S，服务端权威

```
客户端 = 只读展示 + 发送 GAME_ACTION
服务端 = 状态持有 + 逻辑执行 + serverCloud 存储
```

**禁止在客户端直接修改游戏状态**。所有状态变更必须走：

```
客户端 → GAME_ACTION(action, data) → 服务端处理 → GAME_SYNC/GAME_EVT → 客户端刷新
```

### 1.2 入口文件与构建参数

| 端 | 入口 | 职责 |
|----|------|------|
| 客户端 | `client_main.lua` | UI 渲染、用户输入、网络通信 |
| 服务端 | `server_main.lua` | 游戏逻辑、状态管理、云存储 |

**构建时只传 `entry` 和 `entry_server`，禁止传 `entry_client`**：

```
entry = "client_main.lua"
entry_server = "server_main.lua"
persistent_world.enabled = true
```

- `entry_client` 会覆盖 `entry` 写入 `project.json` 的 `entry@client`，一旦指向错误文件（如无 `Start()` 的模块），导致白屏崩溃
- `entry_server` 必须指向 `server_main.lua`（包含 `Start()` 函数），禁止指向 `server_game.lua` 等业务模块

**排查 `Start()` 找不到时**：
1. 检查 `.project/project.json` 是否存在 `entry@client` 字段 — 有则删除
2. 检查 `entry@server` 是否指向 `server_main.lua`
3. 检查 `dist/` 下 manifest 中 `"entry"` 字段
4. 确认入口文件中存在全局 `function Start()`

### 1.3 客户端启动流程

```
Start()
  → UI.Init()
  → 构建底层游戏 UI（不可见）
  → ClientNet.Init()
  → 显示开始界面 (zIndex=900)
  → 并行: 云探测 + 用户选服
  → 两线汇合 → enterGameFromStart()
  → 服务端发 GAME_INIT → 客户端进入游戏
```

**开始界面关闭前，游戏 UI 不可交互。**

### 1.4 身份升级

```lua
-- 服务端 HandleClientReady 中:
local identityUid = connection.identity["user_id"]
local userId = tonumber(identityUid:GetInt64())
-- tempId → realUserId 映射更新
-- 同一 userId 重复登录 → 踢旧连接
```

**身份升级完成后，等选服才加载数据（防 sid=0 误操作）。**

---

## 二、代码架构规则

### 2.1 模块拆分（强制）

每个独立功能必须拆分为单独的 Lua 文件，禁止所有逻辑堆在单个文件中。

### 2.2 单文件上限 500 行

单个 Lua 文件不得超过 500 行（含注释和空行）。超出必须拆分。

### 2.3 职责分离

| 前缀 | 职责 | 示例 |
|------|------|------|
| `client_main.lua` / `server_main.lua` | 仅初始化和模块加载，不写业务逻辑 | - |
| `ui/page_*.lua` | UI 页面，每个页面一个文件 | `page_city.lua`, `page_map.lua` |
| `data/data_*.lua` | 数据配置和常量定义 | `data_heroes.lua`, `data_maps.lua` |
| `data/battle_engine.lua` | 战斗引擎（仅服务端） | - |
| `network/*.lua` | 网络通信模块 | `shared.lua`, `client_net.lua` |

### 2.4 模块间通信

通过 `require` 返回值或事件系统解耦，**禁止跨文件直接访问局部变量**。

### 2.5 模块归属

| 模块 | 客户端 | 服务端 |
|------|--------|--------|
| `network/shared.lua` | 引用 | 引用 |
| `data/data_heroes.lua` | 引用 | 引用 |
| `data/data_maps.lua` | 引用 | 引用 |
| `data/battle_engine.lua` | **禁用** | 引用 |
| `data/data_state.lua` | 只读 | 读写 |
| `ui/*` | 引用 | **禁用** |

---

## 三、引擎内置全局变量

以下变量由 UrhoX 引擎填充，**全局可用，不需要也不能 require**：

| 变量 | 说明 | 可用范围 |
|------|------|---------|
| `cjson` | JSON 编解码 | 客户端 + 服务端 |
| `vg` | NanoVG 上下文句柄 | 仅 NanoVGRender 事件回调 |

```lua
-- 正确：直接使用全局变量
local ok, data = pcall(cjson.decode, jsonStr)

-- 错误：require 会报 Module not found
local cjson = require("cjson")  -- 运行时报错！
```

---

## 四、UI 规范

### 4.1 禁止 Emoji

**禁止在 UI 中使用任何 Emoji 表情符号**。所有界面文本、按钮、标签、提示一律使用纯中文/英文文字。

### 4.2 图标规则

- 优先使用图片资源（`assets/image/`）
- 无图片时生成相关图片，生成后需确认图片是否符合要求
- 必要时可用 NanoVG 绘制同类替代
- **禁止用 Emoji 替代图标**

### 4.3 只用 urhox-libs/UI

```lua
local UI = require("urhox-libs/UI")
```

禁止使用原生 UIElement。

### 4.4 Panel 绝对定位只接受像素数字

```lua
-- 正确
UI.Panel { position = "absolute", top = 50, left = 100, width = 200, height = 300 }

-- 错误（会静默失败）
UI.Panel { position = "absolute", top = "10%", left = "5%" }
```

### 4.5 弹窗用 modal_manager（不用 UI.Modal）

```lua
local Modal = require("ui.modal_manager")
Modal.Confirm("标题", "内容", function() ... end)
```

### 4.6 按钮用贴图

```lua
Comp.SanButton {
    text = "确认",
    variant = "primary",  -- primary/danger/gold/secondary
    onClick = function(self) ... end,
}
```

贴图路径: `Textures/ui/btn_primary.png` 等，9-patch 切片。

### 4.7 动态修改 onClick 必须用 props.onClick

```lua
-- 正确：通过 props 修改
btn.props.onClick = function(self) doSomething() end

-- 错误：直接赋值到控件对象，框架不会读取
btn.onClick = function(self) doSomething() end
```

此规则适用于所有通过 `FindById` 或变量获取的控件。

### 4.8 隐藏 absolute 浮层必须同时设置 Display

`position = "absolute"` 的全屏浮层，关闭时 `SetVisible(false)` 不够——隐藏后仍会拦截点击事件。必须同时设置 `YGDisplayNone`：

```lua
-- 关闭浮层
overlayPanel:SetVisible(false)
YGNodeStyleSetDisplay(overlayPanel.node, YGDisplayNone)

-- 打开浮层
overlayPanel:SetVisible(true)
YGNodeStyleSetDisplay(overlayPanel.node, YGDisplayFlex)
```

---

## 五、分区（区服）规则

### 5.1 realmKey 隔离

所有玩家数据 key 必须带区服后缀：

```lua
local function realmKey(baseKey, sid)
    if not sid or sid == 0 then return baseKey end
    return baseKey .. "_" .. tostring(sid)
end
```

**禁止使用不带后缀的裸 key 存储玩家数据。**

### 5.2 云端 Key 清单

#### 玩家数据 (per-user)

| Key | 类型 | 说明 |
|-----|------|------|
| `save_{sid}` | Score (JSON) | 完整存档 |
| `save_bak_{sid}` | Score (JSON) | 兜底备份 |
| `name_{sid}` | Score (string) | 玩家昵称 |
| `power_{sid}` | iScore (int) | 总战力（排行榜） |
| `stage_{sid}` | iScore (int) | 最远关卡（排行榜） |

#### 全局数据 (userId=0)

| Key | 说明 |
|-----|------|
| `server_list` | 区服列表 JSON |

#### 排行榜

| 榜单 | Key | 排序 |
|------|-----|------|
| 战力榜 | `power_{sid}` | 降序 |
| 关卡榜 | `stage_{sid}` | 降序 |

**新增 key 时必须更新本文档和 `docs/architecture.md`。**

### 5.3 存档结构

存档是一个 JSON blob，存在 `save_{sid}` 中：

```lua
{
    copper, yuanbao, stamina, staminaMax,  -- 基础资源
    jianghun, zhaomuling, power,           -- 特殊资源
    heroes = { [heroId] = { level, star, exp, fragments } },
    inventory = { exp_wine, star_stone, breakthrough, awaken_stone },
    lineup = { formation, front = {}, back = {} },
    currentMap, nodeStars = {}, clearedMaps = {},
    lastSaveTime, lastStaminaTime,
}
```

单个存档 < 10KB，原子读写，不拆分多 key。

---

## 六、服务端数据兼容性规则

### 6.1 新增字段必须兼底旧存档

所有新增状态字段，在 `OnPlayerLoaded` 或读取时必须做 nil 兜底：

```lua
-- 正确
if s.newFeatureFlag == nil then s.newFeatureFlag = false end
if s.newCounter == nil then s.newCounter = 0 end

-- 错误：老玩家 s.newField 为 nil，运行时崩溃
local val = s.newField + 1
```

### 6.2 禁止删除现有字段

已上线的状态字段不能删除或重命名。废弃字段可停止使用，但必须保留定义。

### 6.3 禁止修改字段语义

不得将现有字段的类型改为不兼容形式（如数字改字符串、单值改数组）。

### 6.4 云变量 Key 同理

`serverCloud`/`clientCloud` 的 `SetInt`/`Set` key 一经上线不可删除或更改类型，只可新增。

---

## 七、事件通信规则

### 7.1 事件常量集中定义

所有事件名在 `network/shared.lua` 中定义，禁止散落的字符串字面量：

```lua
-- 正确
local Shared = require("network.shared")
connection:SendRemoteEvent(Shared.EVENTS.GAME_ACTION, true, data)

-- 错误
connection:SendRemoteEvent("SG_GameAction", true, data)
```

### 7.2 GAME_ACTION 格式

```lua
local data = VariantMap()
data["Action"] = Variant("use_exp_wine")
data["Data"]   = Variant(cjson.encode({ heroId = "lvbu", count = 10 }))
connection:SendRemoteEvent(Shared.EVENTS.GAME_ACTION, true, data)
```

#### 已定义的 Action

| Action | Data | 说明 |
|--------|------|------|
| `game_start` | - | 进入游戏 |
| `battle` | `{mapId, nodeId, nodeType}` | 发起战斗 |
| `use_exp_wine` | `{heroId, count}` | 使用经验酒 |
| `star_up` | `{heroId}` | 英雄升星 |
| `recruit` | - | 招募 |
| `compose_hero` | `{heroId}` | 碎片合成 |
| `set_lineup` | `{formation, front, back}` | 设置阵容 |
| `buy_shop_item` | `{itemId}` | 购买资源商品 |
| `buy_gift_pack` | `{packId}` | 购买礼包 |
| `recharge` | `{tierId}` | 模拟充值 |
| `equip_wear` | `{heroId, bagIndex}` | 穿戴装备 |
| `equip_remove` | `{heroId, slot}` | 卸下装备 |
| `equip_enhance` | `{heroId, slot}` | 强化装备 |
| `equip_refine` | `{heroId, slot}` | 精炼装备 |
| `equip_reforge` | `{heroId, slot, lockIndexes}` | 洗练装备 |

**新增 Action 时必须更新本清单。**

---

## 八、游戏数据规则

### 8.1 英雄 ID 用拼音

`caocao`, `lvbu`, `zhugeliang`, `guanyu`, `zhaozilong` 等。

### 8.2 品质映射偏移

```lua
-- data_heroes 品质: 1-6 (绿→金)
-- theme.lua 品质色: 1-7 (白→金)
-- 显示时:
Theme.QualityColor(heroData.quality + 1)
```

### 8.3 三围体系

| 属性 | 中文 | 战斗作用 |
|------|------|---------|
| tong | 统率 | 普攻伤害 |
| yong | 勇武 | 战法伤害 |
| zhi  | 智力 | 法攻伤害 |

### 8.4 士气系统

初始 0，命中 +25，被击 +15，击杀 +30，满 100 自动释放战法。

### 8.5 阵型

前排 2 + 后排 3，自动回合制，20 回合超时判负。

---

## 九、目录结构

```
scripts/
├── client_main.lua           # 客户端入口
├── server_main.lua           # 服务端入口
├── network/
│   ├── shared.lua            # 事件常量（两端共享）
│   ├── client_net.lua        # 客户端网络
│   └── cloud_polyfill.lua    # clientCloud 透明桥
├── data/
│   ├── data_state.lua        # 状态管理（服务端写/客户端读）
│   ├── data_heroes.lua       # 英雄数据库（两端共享）
│   ├── data_maps.lua         # 地图数据库（两端共享）
│   └── battle_engine.lua     # 战斗引擎（仅服务端）
└── ui/
    ├── theme.lua             # 主题
    ├── components.lua        # 通用组件
    ├── modal_manager.lua     # 弹窗
    ├── hud.lua               # 顶栏
    ├── page_city.lua         # 主城
    ├── page_map.lua          # 地图
    ├── page_battle.lua       # 战斗回放
    ├── page_heroes.lua       # 英雄养成
    ├── page_formation.lua    # 阵容编辑
    ├── page_start.lua        # 开始界面
    └── page_server.lua       # 区服选择
```

---

## 十、开发工作流

### 10.1 添加新功能的标准流程

1. **确认端归属**: 逻辑在服务端还是客户端？
2. **服务端**: 在 `server_main.lua` 添加 GAME_ACTION handler
3. **客户端**: 在对应 `page_*.lua` 添加 UI，发送 GAME_ACTION
4. **事件**: 新 Action 在 `shared.lua` 和本文档注册
5. **云端**: 新 key 在 `realmKey` 体系中定义并更新文档
6. **构建**: 修改后必须调用 build 工具
7. **提交**: 构建通过后执行 git commit

### 10.2 添加新页面

1. 创建 `ui/page_xxx.lua`，导出 `M.Create(state, callbacks)` 和 `M.Refresh(state)`
2. 在 `client_main.lua` 的 `switchPage()` 中注册
3. UI 中的所有操作通过 `GAME_ACTION` 发送给服务端

### 10.3 添加新英雄

1. 在 `data/data_heroes.lua` 的 `HEROES` 表中添加
2. 生成头像贴图放到 `assets/Textures/heroes/`
3. 服务端 `createDefaultState()` 中不需要改（新英雄通过招募获得）

### 10.4 变更通知

每次修改后，列出所有变更文件及修改摘要，然后提交 git。

---

## 十一、.gitignore 保护规则

### 11.1 禁止覆写 .gitignore

- **绝对禁止**用 Write 工具替换 `.gitignore` 的全部内容
- 新增忽略规则**只能用 Edit 工具追加行**，不得删除或修改现有规则
- 如果发现 `.gitignore` 内容异常（行数过少、缺少关键目录），必须从 git 历史恢复

### 11.2 提交前必须检查 .gitignore

执行 `git add` 前必须检查：

```bash
# 1. 检查行数（正常 >= 20 行）
wc -l .gitignore

# 2. 确认关键排除规则存在
grep -c '\.project/' .gitignore   # 必须 >= 1
grep -c 'logs/' .gitignore        # 必须 >= 1

# 3. 确认 git status 中没有敏感目录
git status --short | grep -E '^\?\? \.(project|tmp|claude|cli|agent)/' && echo "危险！" && exit 1
```

检查不通过时**立即停止，先修复 .gitignore**。

### 11.3 禁止 git add 敏感目录

以下目录永远不得出现在 `git add` 命令中：

```
.ssh/         # SSH 密钥
.project/     # 引擎项目配置
.tmp/         # 临时文件
.claude/      # AI 工作流配置
.cli/         # CLI 工具
.agent/       # Agent 配置
.emmylua/     # LSP 类型定义
logs/         # 构建日志
dist/         # 发布产物
.build/       # 构建产物
engine-docs/  examples/  templates/  urhox-libs/  schemas/  lua-tools/
```

---

## 十二、Git 规则

### 12.1 每次完成必须提交

每次完成一个功能/修复/文档更新后，必须执行 git commit。提交信息用中文，简洁描述变更内容。

### 12.2 推送命令

```bash
/home/Maker/.venv/bin/python3 /workspace/.ssh/git_push.py
```

- SSH 密钥: `/workspace/.ssh/id_ed25519`
- 代理: `127.0.0.1:1080` (HTTP CONNECT → ssh.github.com:443)
- 必须用 venv 的 python（系统 python 无 paramiko）
- 默认 master 分支推送到 `git@github.com:706412584/game_djbtz.git`

### 12.3 仓库只跟踪以下目录

```
scripts/           # 游戏代码
assets/            # 资源文件
docs/              # 设计文档
game_material/     # 游戏素材（图标/截图/宣传图）
.gitignore         # 忽略规则
CLAUDE.md          # 智能体规则
```

引擎目录和内部配置均已排除。

---

## 参考资源

- **架构详细文档**: `docs/architecture.md`
- **设计总稿**: `docs/docs/三国100图完整设计总稿.md`
- **参考项目**: `docs/参考项目-渡劫摆摊传/`（C/S 架构参考，不复用 UI）
- **引擎文档**: `engine-docs/`（API、recipes、脚手架等）
