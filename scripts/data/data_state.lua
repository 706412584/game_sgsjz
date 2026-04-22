------------------------------------------------------------
-- data/data_state.lua  —— 三国神将录 游戏状态管理
-- 负责：存档读档、英雄升级/升星、资源增减、推图进度
-- C/S 模式：服务端读写，客户端只读（通过 ApplyServerInit/Sync）
------------------------------------------------------------
local DH = require("data.data_heroes")
local DM = require("data.data_maps")

local M = {}

--- 当前游戏状态（客户端只读引用，服务端可写）
---@type table|nil
M.state = nil

--- UI 刷新回调（客户端注册，状态变更后自动调用）
---@type fun()|nil
M.onStateChanged = nil

------------------------------------------------------------
-- 常量
------------------------------------------------------------

--- 每级所需经验 (简化：level * 100)
local function expForLevel(lv)
    return lv * 100
end

--- 每升一星需碎片数
local STAR_COST = { 10, 20, 40, 80, 160 }  -- 1→2, 2→3, 3→4, 4→5, 5→6

--- 经验酒每瓶经验值
M.EXP_WINE_VALUE = 50

--- 英雄等级上限
M.MAX_HERO_LEVEL = 80

--- 英雄星级上限
M.MAX_HERO_STAR  = 6

--- 体力恢复速率 (秒/点)
M.STAMINA_REGEN_SEC = 360  -- 6分钟

------------------------------------------------------------
-- 默认初始状态（新玩家）
------------------------------------------------------------
function M.CreateDefaultState()
    return {
        -- 基础资源
        power       = 2450,
        copper      = 5000,
        yuanbao     = 100,
        stamina     = 115,
        staminaMax  = 120,

        -- 推图进度
        currentMap  = 1,
        nodeStars   = {},       -- ["mapId_nodeId"] = stars (1-3)
        clearedMaps = {},       -- [mapId] = true

        -- 已拥有英雄 (key = heroId)
        heroes = {
            lvbu         = { level = 10, star = 1, exp = 0, fragments = 0 },
            guanyu       = { level = 8,  star = 1, exp = 0, fragments = 0 },
            zhangfei     = { level = 7,  star = 1, exp = 0, fragments = 0 },
            zhaoyun      = { level = 9,  star = 1, exp = 0, fragments = 0 },
            zhugeliang   = { level = 6,  star = 1, exp = 0, fragments = 0 },
            sunshangxiang = { level = 7, star = 1, exp = 0, fragments = 0 },
            diaochan     = { level = 5,  star = 1, exp = 0, fragments = 0 },
            daqiao       = { level = 4,  star = 1, exp = 0, fragments = 0 },
            caiwenji     = { level = 5,  star = 1, exp = 0, fragments = 0 },
            zhenji       = { level = 6,  star = 1, exp = 0, fragments = 0 },
            huangzhong   = { level = 8,  star = 1, exp = 0, fragments = 0 },
            xiaohoudun   = { level = 7,  star = 1, exp = 0, fragments = 0 },
        },

        -- 阵容
        lineup = {
            formation = "feng_shi",
            front = { "lvbu", "zhangfei" },
            back  = { "zhugeliang", "guanyu", "zhaoyun" },
        },

        -- 背包
        inventory = {
            exp_wine      = 20,  -- 经验酒
            star_stone    = 0,   -- 升星石
            breakthrough  = 0,   -- 突破丹
            awaken_stone  = 0,   -- 觉醒石
        },

        -- 特殊货币
        jianghun   = 0,   -- 将魂
        zhaomuling = 3,   -- 招募令

        -- 招募池已解锁英雄
        recruitPool = {},  -- heroId list

        -- 时间记录
        lastSaveTime = 0,
        lastStaminaTime = 0,
    }
end

------------------------------------------------------------
-- 存档 / 读档
------------------------------------------------------------

--- 保存游戏状态到本地
---@param state table
---@return boolean
function M.Save(state)
    state.lastSaveTime = os.time()
    local ok, jsonStr = pcall(cjson.encode, state)
    if not ok then
        print("[存档] 序列化失败: " .. tostring(jsonStr))
        return false
    end
    local file = File("sanguo_save.json", FILE_WRITE)
    if not file:IsOpen() then
        print("[存档] 无法写入文件")
        return false
    end
    file:WriteString(jsonStr)
    file:Close()
    print("[存档] 保存成功, 大小=" .. #jsonStr .. " bytes")
    return true
end

--- 读取存档，返回 state 或 nil
---@return table|nil
function M.Load()
    if not fileSystem:FileExists("sanguo_save.json") then
        print("[存档] 无存档文件，使用默认状态")
        return nil
    end
    local file = File("sanguo_save.json", FILE_READ)
    if not file:IsOpen() then
        print("[存档] 无法读取文件")
        return nil
    end
    local jsonStr = file:ReadString()
    file:Close()
    local ok, data = pcall(cjson.decode, jsonStr)
    if not ok then
        print("[存档] 解析失败: " .. tostring(data))
        return nil
    end
    -- 兼容旧存档：补充缺失字段
    data.inventory = data.inventory or {}
    data.inventory.exp_wine = data.inventory.exp_wine or 0
    data.recruitPool = data.recruitPool or {}
    data.lastStaminaTime = data.lastStaminaTime or 0
    -- 旧存档 heroes 中 evolve 字段迁移为 star
    for id, h in pairs(data.heroes or {}) do
        if h.star == nil then
            h.star = 1
        end
        if h.fragments == nil then
            h.fragments = 0
        end
    end
    print("[存档] 读取成功")
    return data
end

------------------------------------------------------------
-- 英雄升级
------------------------------------------------------------

--- 使用经验酒升级英雄
---@param state table
---@param heroId string
---@param wineCount number  要使用的经验酒数量
---@return boolean success
---@return string  message
function M.UseExpWine(state, heroId, wineCount)
    local hero = state.heroes[heroId]
    if not hero then return false, "英雄不存在" end
    if hero.level >= M.MAX_HERO_LEVEL then return false, "已满级" end

    local available = state.inventory.exp_wine or 0
    if available <= 0 then return false, "经验酒不足" end

    -- 限制实际使用量
    wineCount = math.min(wineCount, available)

    local totalExp = wineCount * M.EXP_WINE_VALUE
    hero.exp = hero.exp + totalExp

    local leveled = false
    while hero.level < M.MAX_HERO_LEVEL do
        local need = expForLevel(hero.level)
        if hero.exp >= need then
            hero.exp = hero.exp - need
            hero.level = hero.level + 1
            leveled = true
        else
            break
        end
    end

    if hero.level >= M.MAX_HERO_LEVEL then
        hero.exp = 0
    end

    state.inventory.exp_wine = available - wineCount

    -- 重算战力
    M.RecalcPower(state)

    local heroData = DH.HEROES[heroId]
    local name = heroData and heroData.name or heroId
    if leveled then
        return true, name .. " 升至 Lv." .. hero.level
    else
        return true, name .. " 获得 " .. totalExp .. " 经验"
    end
end

--- 升星
---@param state table
---@param heroId string
---@return boolean success
---@return string  message
function M.StarUp(state, heroId)
    local hero = state.heroes[heroId]
    if not hero then return false, "英雄不存在" end
    if hero.star >= M.MAX_HERO_STAR then return false, "已满星" end

    local cost = STAR_COST[hero.star] or 999
    if hero.fragments < cost then
        return false, "碎片不足 (需要" .. cost .. ", 拥有" .. hero.fragments .. ")"
    end

    hero.fragments = hero.fragments - cost
    hero.star = hero.star + 1

    M.RecalcPower(state)

    local heroData = DH.HEROES[heroId]
    local name = heroData and heroData.name or heroId
    return true, name .. " 升至 " .. hero.star .. " 星！"
end

--- 获取升星所需碎片
function M.GetStarCost(currentStar)
    return STAR_COST[currentStar] or 999
end

--- 获取升级进度信息
function M.GetLevelInfo(state, heroId)
    local hero = state.heroes[heroId]
    if not hero then return nil end
    local need = expForLevel(hero.level)
    return {
        level    = hero.level,
        exp      = hero.exp,
        expNeed  = need,
        maxLevel = hero.level >= M.MAX_HERO_LEVEL,
    }
end

------------------------------------------------------------
-- 资源操作
------------------------------------------------------------

--- 增加资源
function M.AddResource(state, key, amount)
    if key == "copper" then
        state.copper = (state.copper or 0) + amount
    elseif key == "yuanbao" then
        state.yuanbao = (state.yuanbao or 0) + amount
    elseif key == "stamina" then
        state.stamina = math.min((state.stamina or 0) + amount, state.staminaMax or 120)
    elseif key == "jianghun" then
        state.jianghun = (state.jianghun or 0) + amount
    elseif key == "zhaomuling" then
        state.zhaomuling = (state.zhaomuling or 0) + amount
    elseif key == "exp_wine" then
        state.inventory.exp_wine = (state.inventory.exp_wine or 0) + amount
    end
end

--- 处理战斗胜利奖励
---@param state table
---@param battleLog table  战斗引擎输出的 log
---@return table rewards  { items = { {name, count} ... } }
function M.ApplyBattleRewards(state, battleLog)
    local rewards = { items = {} }
    if not battleLog.result or not battleLog.result.win then return rewards end

    local mapId  = battleLog.map_id or 1
    local nodeId = battleLog.node_id or 1
    local stars  = battleLog.result.stars or 1
    local drops  = battleLog.result.drops or {}

    -- 记录通关星级
    local key = mapId .. "_" .. nodeId
    local oldStars = state.nodeStars[key] or 0
    state.nodeStars[key] = math.max(oldStars, stars)

    -- 发放掉落
    for itemName, count in pairs(drops) do
        if itemName == "铜钱" then
            state.copper = state.copper + count
            rewards.items[#rewards.items + 1] = { name = "铜钱", count = count }
        elseif itemName == "经验酒" then
            state.inventory.exp_wine = (state.inventory.exp_wine or 0) + count
            rewards.items[#rewards.items + 1] = { name = "经验酒", count = count }
        elseif itemName == "将魂" then
            state.jianghun = (state.jianghun or 0) + count
            rewards.items[#rewards.items + 1] = { name = "将魂", count = count }
        elseif itemName == "招募令" then
            state.zhaomuling = (state.zhaomuling or 0) + count
            rewards.items[#rewards.items + 1] = { name = "招募令", count = count }
        end
    end

    -- 战力增长
    local powerGain = math.random(10, 30) + stars * 5
    state.power = state.power + powerGain

    -- 检查当前地图是否全部通关 → 解锁下一张地图
    M.CheckMapClear(state, mapId)

    return rewards
end

------------------------------------------------------------
-- 推图进度
------------------------------------------------------------

--- 检查地图是否全部通关
function M.CheckMapClear(state, mapId)
    -- 检查 24 个节点是否都有星级记录
    local allCleared = true
    for nodeId = 1, 24 do
        local key = mapId .. "_" .. nodeId
        if not state.nodeStars[key] or state.nodeStars[key] <= 0 then
            allCleared = false
            break
        end
    end

    if allCleared and not state.clearedMaps[mapId] then
        state.clearedMaps[mapId] = true
        -- 解锁下一张地图
        if mapId >= state.currentMap then
            state.currentMap = mapId + 1
        end
        print("[进度] 地图 " .. mapId .. " 全部通关！解锁地图 " .. state.currentMap)
    end
end

--- 获取地图通关进度
function M.GetMapProgress(state, mapId)
    local cleared = 0
    local totalStars = 0
    for nodeId = 1, 24 do
        local key = mapId .. "_" .. nodeId
        local s = state.nodeStars[key] or 0
        if s > 0 then
            cleared = cleared + 1
            totalStars = totalStars + s
        end
    end
    return {
        cleared    = cleared,
        total      = 24,
        totalStars = totalStars,
        maxStars   = 72,  -- 24 * 3
        isComplete = (cleared >= 24),
    }
end

------------------------------------------------------------
-- 招募系统
------------------------------------------------------------

------------------------------------------------------------
-- 招募系统
------------------------------------------------------------

--- 招募卡池概率配置
M.RECRUIT_CONFIG = {
    --- 单抽消耗招募令
    singleCost  = 1,
    --- 十连消耗招募令
    tenCost     = 10,
    --- 品质概率 (百分比, 总和=100)
    rates = {
        { quality = 3, rate = 58 },  -- 紫 58%
        { quality = 4, rate = 30 },  -- 橙 30%
        { quality = 5, rate = 10 },  -- 红 10%
        { quality = 6, rate = 2  },  -- 金 2%
    },
    --- 保底: 每 N 抽必出该品质
    pity = {
        { quality = 4, every = 10 },  -- 10抽保底橙
        { quality = 5, every = 50 },  -- 50抽保底红
    },
    --- 碎片数量 (按品质)
    fragByQuality = {
        [3] = 8,   -- 紫
        [4] = 5,   -- 橙
        [5] = 3,   -- 红
        [6] = 2,   -- 金
    },
    --- 整将概率 (百分比, 在抽到该品质后再判定)
    wholeHeroRate = 8,
}

--- 初始化招募计数器 (兼容旧存档)
---@param state table
local function ensureRecruitCounters(state)
    if not state.recruitCount then state.recruitCount = 0 end
    if not state.pityCount4 then state.pityCount4 = 0 end
    if not state.pityCount5 then state.pityCount5 = 0 end
end

--- 内部: 执行一次招募抽取
---@param state table
---@param guaranteed number|nil 保底品质 (nil=正常概率)
---@return table result { heroId, heroName, quality, type, count }
local function rollOnce(state, guaranteed)
    ensureRecruitCounters(state)
    state.recruitCount = state.recruitCount + 1
    state.pityCount4   = state.pityCount4 + 1
    state.pityCount5   = state.pityCount5 + 1

    local cfg = M.RECRUIT_CONFIG

    -- 确定品质
    local quality = 3
    if guaranteed then
        quality = guaranteed
    else
        -- 检查保底
        local pityHit = false
        for _, p in ipairs(cfg.pity) do
            local counter = (p.quality == 4) and state.pityCount4
                         or (p.quality == 5) and state.pityCount5
                         or 0
            if counter >= p.every then
                quality = math.max(quality, p.quality)
                pityHit = true
            end
        end
        if not pityHit then
            -- 正常概率抽取
            local roll = math.random(1, 100)
            local cumulative = 0
            for _, r in ipairs(cfg.rates) do
                cumulative = cumulative + r.rate
                if roll <= cumulative then
                    quality = r.quality
                    break
                end
            end
        end
    end

    -- 重置对应保底计数
    if quality >= 4 then state.pityCount4 = 0 end
    if quality >= 5 then state.pityCount5 = 0 end

    -- 从对应品质池中随机选英雄
    local pool = DH.GetByQualityRange(quality, quality)
    if #pool == 0 then
        pool = DH.GetByQualityRange(3, 4)  -- fallback
    end
    local entry = pool[math.random(1, #pool)]
    local heroId   = entry.id
    local heroData = entry.data
    local fragCount = cfg.fragByQuality[quality] or 5

    -- 判定整将还是碎片
    local wholeRoll = math.random(1, 100)
    local isWhole = (wholeRoll <= cfg.wholeHeroRate)

    if isWhole and (not state.heroes[heroId] or state.heroes[heroId].level <= 0) then
        -- 获得整将
        if not state.heroes[heroId] then
            state.heroes[heroId] = { level = 1, star = 1, exp = 0, fragments = 0 }
        else
            state.heroes[heroId].level = 1
            state.heroes[heroId].star  = 1
        end
        return {
            heroId   = heroId,
            heroName = heroData.name,
            quality  = heroData.quality,
            type     = "hero",
            count    = 1,
        }
    else
        -- 给碎片
        if isWhole and state.heroes[heroId] and state.heroes[heroId].level > 0 then
            fragCount = fragCount * 3  -- 已有英雄整将转碎片加量
        end
        if state.heroes[heroId] then
            state.heroes[heroId].fragments = (state.heroes[heroId].fragments or 0) + fragCount
        else
            state.heroes[heroId] = { level = 0, star = 0, exp = 0, fragments = fragCount }
        end
        return {
            heroId   = heroId,
            heroName = heroData.name,
            quality  = heroData.quality,
            type     = "fragments",
            count    = fragCount,
        }
    end
end

--- 单次招募 (兼容旧接口)
---@param state table
---@return boolean success
---@return string  heroId|message
---@return table|nil heroInfo
function M.DoRecruit(state)
    if (state.zhaomuling or 0) < M.RECRUIT_CONFIG.singleCost then
        return false, "招募令不足", nil
    end
    state.zhaomuling = state.zhaomuling - M.RECRUIT_CONFIG.singleCost

    local result = rollOnce(state, nil)
    return true, result.heroId, result
end

--- 十连招募
---@param state table
---@return boolean success
---@return string message
---@return table[] results  每次抽取结果列表
function M.DoRecruit10(state)
    local cost = M.RECRUIT_CONFIG.tenCost
    if (state.zhaomuling or 0) < cost then
        return false, "招募令不足(需要" .. cost .. ")", {}
    end
    state.zhaomuling = state.zhaomuling - cost

    local results = {}
    for i = 1, 10 do
        -- 第10次保底至少橙将
        local guaranteed = nil
        if i == 10 then
            ensureRecruitCounters(state)
            -- 检查这10抽是否出过橙以上
            local hasOrange = false
            for _, r in ipairs(results) do
                if r.quality >= 4 then hasOrange = true; break end
            end
            if not hasOrange then guaranteed = 4 end
        end
        results[#results + 1] = rollOnce(state, guaranteed)
    end
    return true, "十连招募完成", results
end

--- 获取招募统计信息
---@param state table
---@return table { total, pity4, pity5, nextPity4, nextPity5 }
function M.GetRecruitStats(state)
    ensureRecruitCounters(state)
    local cfg = M.RECRUIT_CONFIG
    return {
        total     = state.recruitCount,
        pity4     = state.pityCount4,
        pity5     = state.pityCount5,
        nextPity4 = cfg.pity[1].every - state.pityCount4,
        nextPity5 = cfg.pity[2].every - state.pityCount5,
    }
end

--- 碎片合成英雄（需要 30 碎片）
function M.ComposeHero(state, heroId)
    local hero = state.heroes[heroId]
    if not hero then return false, "无此英雄碎片" end
    if hero.level > 0 then return false, "已拥有该英雄" end
    if hero.fragments < 30 then
        return false, "碎片不足 (需要30, 拥有" .. hero.fragments .. ")"
    end
    hero.fragments = hero.fragments - 30
    hero.level = 1
    hero.star = 1
    local heroData = DH.HEROES[heroId]
    local name = heroData and heroData.name or heroId
    return true, name .. " 合成成功！"
end

------------------------------------------------------------
-- 战力计算
------------------------------------------------------------

--- 计算单个英雄战力
function M.CalcHeroPower(heroId, heroState)
    if not heroState or heroState.level <= 0 then return 0 end
    local heroData = DH.HEROES[heroId]
    if not heroData then return 0 end

    local s = heroData.stats
    local base = (s.tong + s.yong + s.zhi) * 2
    local levelBonus = heroState.level * 15
    local starBonus = (heroState.star or 1) * 50
    return base + levelBonus + starBonus
end

--- 重新计算总战力
function M.RecalcPower(state)
    local total = 0
    -- 仅计算阵容中英雄的战力
    local inLineup = {}
    for _, id in ipairs(state.lineup.front) do inLineup[id] = true end
    for _, id in ipairs(state.lineup.back)  do inLineup[id] = true end

    for heroId, heroState in pairs(state.heroes) do
        if inLineup[heroId] then
            total = total + M.CalcHeroPower(heroId, heroState)
        end
    end
    state.power = math.max(total, 100)
    return state.power
end

------------------------------------------------------------
-- 体力恢复（基于时间）
------------------------------------------------------------
function M.UpdateStamina(state)
    local now = os.time()
    if state.lastStaminaTime <= 0 then
        state.lastStaminaTime = now
        return
    end
    local elapsed = now - state.lastStaminaTime
    if elapsed <= 0 then return end

    local regenPoints = math.floor(elapsed / M.STAMINA_REGEN_SEC)
    if regenPoints > 0 and state.stamina < state.staminaMax then
        state.stamina = math.min(state.stamina + regenPoints, state.staminaMax)
        state.lastStaminaTime = state.lastStaminaTime + regenPoints * M.STAMINA_REGEN_SEC
    end
end

------------------------------------------------------------
-- C/S 同步接口（客户端调用）
------------------------------------------------------------

--- 兼容旧存档字段补丁
---@param s table
local function patchState(s)
    s.inventory = s.inventory or {}
    s.inventory.exp_wine = s.inventory.exp_wine or 0
    s.inventory.star_stone = s.inventory.star_stone or 0
    s.inventory.breakthrough = s.inventory.breakthrough or 0
    s.inventory.awaken_stone = s.inventory.awaken_stone or 0
    s.recruitPool = s.recruitPool or {}
    s.lastStaminaTime = s.lastStaminaTime or 0
    s.nodeStars = s.nodeStars or {}
    s.clearedMaps = s.clearedMaps or {}
    s.jianghun = s.jianghun or 0
    s.zhaomuling = s.zhaomuling or 0
    s.lineup = s.lineup or { formation = "feng_shi", front = {}, back = {} }
    -- heroes 字段补丁
    for _, h in pairs(s.heroes or {}) do
        if h.star == nil then h.star = 1 end
        if h.fragments == nil then h.fragments = 0 end
    end
end

--- 首次登录/换服时接收服务端完整状态
---@param stateTable table  服务端推送的完整 state
function M.ApplyServerInit(stateTable)
    patchState(stateTable)
    M.state = stateTable
    local heroCount = 0
    for _ in pairs(stateTable.heroes or {}) do heroCount = heroCount + 1 end
    print("[State] ApplyServerInit: power=" .. (stateTable.power or 0)
        .. " heroes=" .. heroCount)
    if M.onStateChanged then
        M.onStateChanged()
    end
end

--- 周期同步时接收服务端完整状态
---@param stateTable table
function M.ApplyServerSync(stateTable)
    patchState(stateTable)
    M.state = stateTable
    if M.onStateChanged then
        M.onStateChanged()
    end
end

return M
