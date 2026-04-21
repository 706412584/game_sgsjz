-- ============================================================================
-- server_player.lua — 服务端玩家状态管理
-- 职责：加载/保存/管理在线玩家的完整游戏状态
-- 使用 serverCloud BatchGet/BatchSet 进行持久化
-- ============================================================================

---@diagnostic disable: undefined-global

local Config = require("data_config")
local cjson = cjson

local M = {}

-- ========== 云变量 Key 定义 ==========
local ISCORE_KEYS = {
    "lingshi", "xiuwei", "totalEarned", "totalSold",
    "totalCrafted", "totalAdWatched", "stallLevel", "realmLevel",
}
local GAME_STATE_KEY = "gameState"

-- ========== 在线玩家数据 ==========
---@type table<number, table>  userId -> state
local players_ = {}
---@type table<number, boolean> userId -> dirty
local dirty_ = {}
---@type table<number, number> userId -> timer
local saveTimers_ = {}
---@type table<number, number> userId -> serverId (当前区服)
local serverId_ = {}

local SAVE_INTERVAL = 30  -- 脏数据定期保存间隔(秒)

-- ========== 兜底存档（备份） ==========
local BACKUP_KEY = "gameState_bak"
local BACKUP_INTERVAL = 4 * 3600  -- 每4小时备份一次
---@type table<number, number> userId -> 距上次备份的累计时间
local backupTimers_ = {}

-- ========== 默认状态(与 data_state.lua 保持一致) ==========
local function createDefaultState()
    return {
        lingshi = 0,
        xiuwei = 0,
        materials = { lingcao = 0, lingzhi = 0, xuantie = 0 },
        products = {
            juqi_dan = 0, huichun_fu = 0, dijie_faqi = 0,
            ninghun_dan = 0, poxu_fu = 0, xianqi_canpian = 0,
            zhuji_lingyao = 0, wanling_juan = 0, tianjie_faqi = 0, feisheng_dan = 0,
        },
        stallLevel = 1,
        shelf = {},
        totalSold = 0,
        totalEarned = 0,
        totalCrafted = 0,
        todayEarned = 0,
        todayDate = "",
        craftQueue = {},
        adFlowBoostEnd = 0,
        adPriceBoostEnd = 0,
        adUpgradeDiscount = 0,
        adDiscountExpire = 0,
        totalAdWatched = 0,
        adFreeExpire = 0,
        dailyAdCounts = {},
        dailyAdDate = "",
        offlineAdExtend = 0,
        realmLevel = 1,
        lifespan = 100,
        rebirthCount = 0,
        dead = false,
        highestRealmEver = 1,
        myTodayRank = nil,
        storyPlayed = false,
        tutorialStep = 0,
        newbieGiftClaimed = false,
        fieldLevel = 1,
        fieldPlots = {},
        lastEncounterTime = 0,
        redeemedCDKs = {},
        autoRefine = false,
        playerName = "",
        playerGender = "",
        playerId = "",
        serverId = 0,

        -- 口碑系统
        reputation = 100,
        repStreak = 0,

        -- 讨价还价统计
        totalBargains = 0,
        bargainWins = 0,

        -- 每日任务
        dailyTasks = {},
        dailyTaskDate = "",
        dailyTasksClaimed = 0,

        -- 法宝系统
        artifacts = {},
        equippedArtifacts = {},

        -- 珍藏物品
        collectibles = {},

        bgmEnabled = true,
        sfxEnabled = true,
        lastSaveTime = 0,

        -- 广播邮件补发
        lastBroadcastId = 0,

        -- 广告幂等去重
        lastAdNonces = {},

        -- 师徒系统
        masterId = nil,            -- 师父userId (nil=无师父)
        masterName = "",           -- 师父名字(展示用)
        masterRealmAtBind = 0,     -- 拜师时师父境界(出师目标)
        disciples = {},            -- 徒弟列表 [{userId,name,realmAtBind,acceptTime}]
        mentorXiuweiEarned = 0,    -- 累计从徒弟获得的修为
        graduatedCount = 0,        -- 已出师徒弟数
        pendingMentorInvites = {},  -- 待处理师徒邀请
    }
end

-- ========== 提取 gameState blob ==========
---@param state table
---@return table
local function extractGameStateBlob(state)
    return {
        materials = state.materials,
        products = state.products,
        shelf = state.shelf,
        craftQueue = state.craftQueue,
        realmLevel = state.realmLevel,
        lifespan = state.lifespan,
        rebirthCount = state.rebirthCount,
        highestRealmEver = state.highestRealmEver or 1,
        dead = state.dead,
        adFlowBoostEnd = state.adFlowBoostEnd,
        adPriceBoostEnd = state.adPriceBoostEnd,
        adUpgradeDiscount = state.adUpgradeDiscount,
        adDiscountExpire = state.adDiscountExpire,
        adFreeExpire = state.adFreeExpire,
        dailyAdCounts = state.dailyAdCounts,
        dailyAdDate = state.dailyAdDate,
        offlineAdExtend = state.offlineAdExtend,
        storyPlayed = state.storyPlayed,
        tutorialStep = state.tutorialStep,
        newbieGiftClaimed = state.newbieGiftClaimed,
        fieldLevel = state.fieldLevel,
        fieldPlots = state.fieldPlots,
        lastEncounterTime = state.lastEncounterTime,
        redeemedCDKs = state.redeemedCDKs,
        guideCompleted = state.guideCompleted,
        playerName = state.playerName,
        playerGender = state.playerGender,
        playerId = state.playerId,
        serverId = state.serverId,
        bgmEnabled = state.bgmEnabled,
        sfxEnabled = state.sfxEnabled,
        autoRefine = state.autoRefine,
        -- 口碑系统
        reputation = state.reputation,
        repStreak = state.repStreak,
        -- 讨价还价统计
        totalBargains = state.totalBargains,
        bargainWins = state.bargainWins,
        -- 每日任务
        dailyTasks = state.dailyTasks,
        dailyTaskDate = state.dailyTaskDate,
        dailyTasksClaimed = state.dailyTasksClaimed,
        lastSaveTime = state.lastSaveTime,
        -- 灵童 & 炼器傀儡
        fieldServant = state.fieldServant,
        craftPuppet = state.craftPuppet,
        -- 今日收入(排行榜)
        todayEarned = state.todayEarned,
        todayDate = state.todayDate,
        -- 秘境系统
        dungeonDailyUses = state.dungeonDailyUses,
        dungeonDailyDate = state.dungeonDailyDate,
        dungeonHistory = state.dungeonHistory,
        -- 渡劫小游戏
        dujieDailyDate = state.dujieDailyDate,
        dujieFreeUses = state.dujieFreeUses,
        dujiePaidUses = state.dujiePaidUses,
        -- 法宝系统
        artifacts = state.artifacts,
        equippedArtifacts = state.equippedArtifacts,
        -- 珍藏物品
        collectibles = state.collectibles,
        -- 广播邮件补发
        lastBroadcastId = state.lastBroadcastId,
        -- 广告幂等去重
        lastAdNonces = state.lastAdNonces,
        -- 秘境广告奖励次数
        dungeonBonusUses = state.dungeonBonusUses,
        -- 师徒系统
        masterId = state.masterId,
        masterName = state.masterName,
        masterRealmAtBind = state.masterRealmAtBind,
        disciples = state.disciples,
        mentorXiuweiEarned = state.mentorXiuweiEarned,
        graduatedCount = state.graduatedCount,
        pendingMentorInvites = state.pendingMentorInvites,
        mentorGiftCount = state.mentorGiftCount,
        mentorGiftDate = state.mentorGiftDate,
        -- 风水阵
        fengshui = state.fengshui,
        -- 聚宝阁每日限购
        dailyShopBuys = state.dailyShopBuys,
        dailyShopDate = state.dailyShopDate,
    }
end

-- ========== 兜底存档 blob（包含 iScore 值，实现完整自恢复） ==========
---@param state table
---@return table
local function extractFullBackupBlob(state)
    local blob = extractGameStateBlob(state)
    -- 将 iScore 值嵌入备份，主存档丢失时 iScore 也可能被覆盖为0
    blob._bak_iscores = {
        lingshi = state.lingshi,
        xiuwei = state.xiuwei,
        totalEarned = state.totalEarned,
        totalSold = state.totalSold,
        totalCrafted = state.totalCrafted,
        totalAdWatched = state.totalAdWatched,
        stallLevel = state.stallLevel,
        realmLevel = state.realmLevel,
        todayEarned = state.todayEarned,
    }
    blob._bak_time = os.time()
    return blob
end

-- ========== 获取今日日期 key ==========
local function getTodayKey()
    return os.date("!%Y%m%d", os.time() + 8 * 3600)  -- UTC+8 北京时间零点刷新
end

-- ========== 区服 key 前缀 ==========

--- 根据当前区服生成带后缀的存储 key
--- serverId=0 或 nil 时返回原始 key（兼容旧数据）
---@param baseKey string
---@param sid number|nil
---@return string
local function realmKey(baseKey, sid)
    if not sid or sid == 0 then return baseKey end
    return baseKey .. "_" .. tostring(sid)
end

--- 公开版 realmKey(供 server_main.lua GM 操作使用)
---@param baseKey string
---@param sid number|nil
---@return string
function M.RealmKey(baseKey, sid)
    return realmKey(baseKey, sid)
end

--- 暴露默认状态创建(供 gm_reset 使用)
---@return table
function M.CreateDefaultState()
    return createDefaultState()
end

-- ========== 公开接口 ==========

--- 设置玩家当前区服 ID（换服时由 server_main 调用）
---@param userId number
---@param sid number
function M.SetServerId(userId, sid)
    serverId_[userId] = sid
    print("[PlayerMgr] SetServerId: uid=" .. tostring(userId) .. " sid=" .. tostring(sid))
end

--- 获取玩家当前区服 ID
---@param userId number
---@return number
function M.GetServerId(userId)
    return serverId_[userId] or 0
end

--- 从 serverCloud 加载玩家数据（失败自动重试）
---@param userId number
---@param callback fun(success: boolean, state: table|nil, hasCloudData: boolean)
---@param _retryCount? number 内部参数：当前重试次数
function M.LoadPlayer(userId, callback, _retryCount)
    _retryCount = _retryCount or 0
    local MAX_RETRIES = 2  -- 最多重试2次(共3次尝试)

    if not serverCloud then
        print("[PlayerMgr] serverCloud 不可用")
        callback(false, nil, false)
        return
    end

    local sid = serverId_[userId] or 0
    local todayIScoreKey = realmKey("earned_" .. getTodayKey(), sid)
    local batchGet = serverCloud:BatchGet(userId)
    for _, key in ipairs(ISCORE_KEYS) do
        batchGet:Key(realmKey(key, sid))
    end
    batchGet:Key(todayIScoreKey)  -- 今日收入 iScore（兜底恢复用）
    batchGet:Key(realmKey(GAME_STATE_KEY, sid))
    batchGet:Key(realmKey(BACKUP_KEY, sid))  -- 兜底存档 key（一起拉取，无额外延迟）

    batchGet:Fetch({
        ok = function(scores, iscores)
            scores = scores or {}
            iscores = iscores or {}
            local state = createDefaultState()

            -- 从 iscores 恢复（带区服前缀）
            state.lingshi = iscores[realmKey("lingshi", sid)] or 0
            state.xiuwei = iscores[realmKey("xiuwei", sid)] or 0
            state.totalEarned = iscores[realmKey("totalEarned", sid)] or 0
            state.totalSold = iscores[realmKey("totalSold", sid)] or 0
            state.totalCrafted = iscores[realmKey("totalCrafted", sid)] or 0
            state.totalAdWatched = iscores[realmKey("totalAdWatched", sid)] or 0
            state.stallLevel = math.max(iscores[realmKey("stallLevel", sid)] or 1, 1)

            -- 从 gameState blob 恢复
            local gsRaw = scores[realmKey(GAME_STATE_KEY, sid)]
            local gs = nil
            if gsRaw and gsRaw ~= "" then
                local decOk, decoded = pcall(cjson.decode, gsRaw)
                if decOk and type(decoded) == "table" then
                    gs = decoded
                end
            end

            -- 判断云端是否有存档数据（gsRaw 存在且能解码为 table）
            local hasCloudData = (gs ~= nil)
            local restoredFromBackup = false

            -- ====== 兜底存档恢复：主存档不存在时尝试从备份恢复 ======
            if not hasCloudData then
                local bakRaw = scores[realmKey(BACKUP_KEY, sid)]
                if bakRaw and bakRaw ~= "" then
                    local bakOk, bakData = pcall(cjson.decode, bakRaw)
                    if bakOk and type(bakData) == "table"
                        and type(bakData.playerName) == "string"
                        and bakData.playerName ~= "" then
                        print("[PlayerMgr] *** 兜底存档恢复 *** uid=" .. tostring(userId)
                            .. " name=" .. tostring(bakData.playerName)
                            .. " backupTime=" .. tostring(bakData._bak_time))
                        gs = bakData
                        hasCloudData = true
                        restoredFromBackup = true
                        -- 从备份恢复 iScore 值（主存档的 iScore 可能已被覆盖为0）
                        if type(bakData._bak_iscores) == "table" then
                            local bi = bakData._bak_iscores
                            state.lingshi = bi.lingshi or state.lingshi
                            state.xiuwei = bi.xiuwei or state.xiuwei
                            state.totalEarned = bi.totalEarned or state.totalEarned
                            state.totalSold = bi.totalSold or state.totalSold
                            state.totalCrafted = bi.totalCrafted or state.totalCrafted
                            state.totalAdWatched = bi.totalAdWatched or state.totalAdWatched
                            state.stallLevel = math.max(bi.stallLevel or 1, 1)
                        end
                    end
                end
            end

            if gs then
                -- 材料(兼容新增: 先用defaults兜底, 再合并云端所有key)
                if type(gs.materials) == "table" then
                    for k, v in pairs(state.materials) do
                        state.materials[k] = gs.materials[k] or v
                    end
                    -- 合并非defaults中的高级材料(gaoji_lingcao等)
                    for k, v in pairs(gs.materials) do
                        if state.materials[k] == nil then
                            state.materials[k] = v
                        end
                    end
                end
                -- 商品(兼容新增: 先用defaults兜底, 再合并云端所有key)
                if type(gs.products) == "table" then
                    for k, v in pairs(state.products) do
                        state.products[k] = gs.products[k] or v
                    end
                    for k, v in pairs(gs.products) do
                        if state.products[k] == nil then
                            state.products[k] = v
                        end
                    end
                end
                state.shelf = gs.shelf or {}
                state.craftQueue = gs.craftQueue or {}
                state.adFlowBoostEnd = gs.adFlowBoostEnd or 0
                state.adPriceBoostEnd = gs.adPriceBoostEnd or gs.adAutoSellEnd or 0
                -- 兼容旧存档: boolean → number
                if type(gs.adUpgradeDiscount) == "boolean" then
                    state.adUpgradeDiscount = gs.adUpgradeDiscount and 1 or 0
                else
                    state.adUpgradeDiscount = gs.adUpgradeDiscount or 0
                end
                state.adDiscountExpire = gs.adDiscountExpire or 0
                state.adFreeExpire = gs.adFreeExpire or 0
                state.dailyAdCounts = type(gs.dailyAdCounts) == "table" and gs.dailyAdCounts or {}
                state.dailyAdDate = gs.dailyAdDate or ""
                state.offlineAdExtend = gs.offlineAdExtend or 0
                state.realmLevel = math.max(gs.realmLevel or 1, iscores.realmLevel or 1, 1)
                state.lifespan = gs.lifespan or Config.Realms[state.realmLevel].lifespan
                state.rebirthCount = gs.rebirthCount or 0
                state.highestRealmEver = math.max(gs.highestRealmEver or 1, state.realmLevel)
                state.dead = (gs.dead == true)
                state.storyPlayed = (gs.storyPlayed == true)
                state.tutorialStep = gs.tutorialStep or 0
                state.newbieGiftClaimed = (gs.newbieGiftClaimed == true)
                state.fieldLevel = gs.fieldLevel or 1
                -- fieldPlots: JSON 反序列化后数字索引键会变字符串，需恢复
                local rawPlots = type(gs.fieldPlots) == "table" and gs.fieldPlots or {}
                local fixedPlots = {}
                for k, v in pairs(rawPlots) do
                    local numKey = tonumber(k)
                    if numKey then fixedPlots[numKey] = v else fixedPlots[k] = v end
                end
                state.fieldPlots = fixedPlots
                state.lastEncounterTime = gs.lastEncounterTime or 0
                state.redeemedCDKs = type(gs.redeemedCDKs) == "table" and gs.redeemedCDKs or {}
                state.guideCompleted = (gs.guideCompleted == true)
                state.bgmEnabled = (gs.bgmEnabled ~= false)
                state.sfxEnabled = (gs.sfxEnabled ~= false)
                state.autoRefine = (gs.autoRefine == true)
                -- 口碑系统
                state.reputation = type(gs.reputation) == "number" and gs.reputation or 100
                state.repStreak = type(gs.repStreak) == "number" and gs.repStreak or 0
                -- 讨价还价统计
                state.totalBargains = gs.totalBargains or 0
                state.bargainWins = gs.bargainWins or 0
                -- 每日任务
                state.dailyTasks = type(gs.dailyTasks) == "table" and gs.dailyTasks or {}
                state.dailyTaskDate = type(gs.dailyTaskDate) == "string" and gs.dailyTaskDate or ""
                state.dailyTasksClaimed = gs.dailyTasksClaimed or 0
                state.playerName = type(gs.playerName) == "string" and gs.playerName or ""
                state.playerGender = type(gs.playerGender) == "string" and gs.playerGender or ""
                state.playerId = type(gs.playerId) == "string" and gs.playerId or ""
                state.serverId = type(gs.serverId) == "number" and gs.serverId or 0
                state.lastSaveTime = gs.lastSaveTime or 0
                -- 灵童 & 炼器傀儡
                if type(gs.fieldServant) == "table" then state.fieldServant = gs.fieldServant end
                if type(gs.craftPuppet) == "table" then state.craftPuppet = gs.craftPuppet end
                -- 今日收入(排行榜恢复)
                state.todayEarned = gs.todayEarned or 0
                state.todayDate = type(gs.todayDate) == "string" and gs.todayDate or ""
                -- 秘境系统
                state.dungeonDailyUses = type(gs.dungeonDailyUses) == "table" and gs.dungeonDailyUses or {}
                state.dungeonDailyDate = type(gs.dungeonDailyDate) == "string" and gs.dungeonDailyDate or ""
                state.dungeonHistory = type(gs.dungeonHistory) == "table" and gs.dungeonHistory or {}
                -- 渡劫小游戏
                state.dujieDailyDate = type(gs.dujieDailyDate) == "string" and gs.dujieDailyDate or ""
                state.dujieFreeUses = type(gs.dujieFreeUses) == "number" and gs.dujieFreeUses or 0
                state.dujiePaidUses = type(gs.dujiePaidUses) == "number" and gs.dujiePaidUses or 0
                -- 法宝系统
                state.artifacts = type(gs.artifacts) == "table" and gs.artifacts or {}
                state.equippedArtifacts = type(gs.equippedArtifacts) == "table" and gs.equippedArtifacts or {}
                -- 珍藏物品
                state.collectibles = type(gs.collectibles) == "table" and gs.collectibles or {}
                -- 广播邮件补发
                state.lastBroadcastId = gs.lastBroadcastId or 0
                -- 广告幂等去重
                state.lastAdNonces = type(gs.lastAdNonces) == "table" and gs.lastAdNonces or {}
                -- 秘境广告奖励次数
                state.dungeonBonusUses = type(gs.dungeonBonusUses) == "table" and gs.dungeonBonusUses or {}
                -- 师徒系统
                state.masterId = gs.masterId  -- nil 表示无师父，不能用 or 兜底
                state.masterName = type(gs.masterName) == "string" and gs.masterName or ""
                state.masterRealmAtBind = gs.masterRealmAtBind or 0
                state.disciples = type(gs.disciples) == "table" and gs.disciples or {}
                state.mentorXiuweiEarned = gs.mentorXiuweiEarned or 0
                state.graduatedCount = gs.graduatedCount or 0
                state.pendingMentorInvites = type(gs.pendingMentorInvites) == "table" and gs.pendingMentorInvites or {}
                state.mentorGiftCount = gs.mentorGiftCount or 0
                state.mentorGiftDate = type(gs.mentorGiftDate) == "string" and gs.mentorGiftDate or ""
                -- 风水阵
                state.fengshui = type(gs.fengshui) == "table" and gs.fengshui or {}
                -- 聚宝阁每日限购
                state.dailyShopBuys = type(gs.dailyShopBuys) == "table" and gs.dailyShopBuys or {}
                state.dailyShopDate = type(gs.dailyShopDate) == "string" and gs.dailyShopDate or ""
            end

            -- 兜底: 如果 blob 中没有 todayEarned（旧存档），从 iScore 回读
            if (state.todayEarned or 0) == 0 and state.todayDate == "" then
                local iVal = iscores[todayIScoreKey]
                if iVal and iVal > 0 then
                    state.todayEarned = iVal
                    state.todayDate = getTodayKey()
                    print("[PlayerMgr] todayEarned 从 iScore 回读: uid=" .. tostring(userId)
                        .. " todayEarned=" .. tostring(iVal))
                end
            end

            players_[userId] = state
            dirty_[userId] = false
            saveTimers_[userId] = 0

            -- 从兜底存档恢复时，立即标记 dirty 以便回写到主存档
            if restoredFromBackup then
                dirty_[userId] = true
                print("[PlayerMgr] 兜底恢复数据已标记 dirty，将在下次保存周期回写主存档")
            end

            print("[PlayerMgr] 加载玩家成功: uid=" .. tostring(userId)
                .. " lingshi=" .. state.lingshi .. " realm=" .. state.realmLevel
                .. " sid=" .. tostring(serverId_[userId] or 0)
                .. " name=" .. tostring(state.playerName)
                .. " playerId=" .. tostring(state.playerId)
                .. " hasCloudData=" .. tostring(hasCloudData)
                .. (restoredFromBackup and " [FROM_BACKUP]" or ""))
            callback(true, state, hasCloudData)
        end,
        error = function(code, reason)
            print("[PlayerMgr] 加载玩家失败: uid=" .. tostring(userId)
                .. " reason=" .. tostring(reason) .. " retry=" .. tostring(_retryCount))
            if _retryCount < MAX_RETRIES then
                -- 自动重试（下次调用增加重试计数）
                print("[PlayerMgr] 将重试加载 uid=" .. tostring(userId)
                    .. " (" .. tostring(_retryCount + 1) .. "/" .. MAX_RETRIES .. ")")
                M.LoadPlayer(userId, callback, _retryCount + 1)
            else
                print("[PlayerMgr] 加载玩家最终失败(已重试" .. MAX_RETRIES .. "次): uid=" .. tostring(userId))
                callback(false, nil, false)
            end
        end,
    })
end

--- 保存玩家数据到 serverCloud
---@param userId number
---@param callback? fun(success: boolean)
function M.SavePlayer(userId, callback)
    local state = players_[userId]
    if not state then
        if callback then callback(false) end
        return
    end
    if not serverCloud then
        if callback then callback(false) end
        return
    end

    state.lastSaveTime = os.time()

    local sid = serverId_[userId] or 0
    local todayKey = realmKey("earned_" .. getTodayKey(), sid)
    local gsBlob = extractGameStateBlob(state)
    local gsJson = cjson.encode(gsBlob)

    serverCloud:BatchSet(userId)
        :SetInt(realmKey("lingshi", sid), math.floor(state.lingshi))
        :SetInt(realmKey("xiuwei", sid), math.floor(state.xiuwei))
        :SetInt(realmKey("totalEarned", sid), math.floor(state.totalEarned))
        :SetInt(realmKey("totalSold", sid), math.floor(state.totalSold))
        :SetInt(realmKey("totalCrafted", sid), math.floor(state.totalCrafted))
        :SetInt(realmKey("totalAdWatched", sid), math.floor(state.totalAdWatched))
        :SetInt(realmKey("stallLevel", sid), state.stallLevel)
        :SetInt(realmKey("realmLevel", sid), state.realmLevel)
        :SetInt(realmKey("fengshuiLevel", sid), (function()
            local fs = state.fengshui or {}; local t = 0
            for _, f in ipairs(Config.FengshuiFormations) do t = t + (fs[f.id] or 0) end
            return t
        end)())
        :SetInt(todayKey, math.floor(state.todayEarned or 0))
        :Set(realmKey("playerName", sid), state.playerName or "")
        :Set(realmKey("playerGender", sid), state.playerGender or "male")
        :Set(realmKey("playerId", sid), state.playerId or "")
        :Set(realmKey(GAME_STATE_KEY, sid), gsJson)
        :Save("server_save", {
            ok = function()
                dirty_[userId] = false
                if callback then callback(true) end
            end,
            error = function(code, reason)
                print("[PlayerMgr] 保存失败: uid=" .. tostring(userId) .. " " .. tostring(reason))
                if callback then callback(false) end
            end,
        })
end

--- 保存兜底存档（完整快照，含 iScore）
--- 仅对已有角色名的玩家备份，避免空数据覆盖有效备份
---@param userId number
function M.BackupPlayer(userId)
    local state = players_[userId]
    if not state then return end
    if not serverCloud then return end
    -- 只备份已创建角色的玩家（有道号）
    if not state.playerName or state.playerName == "" then return end

    local sid = serverId_[userId] or 0
    local bakBlob = extractFullBackupBlob(state)
    local bakJson = cjson.encode(bakBlob)

    serverCloud:BatchSet(userId)
        :Set(realmKey(BACKUP_KEY, sid), bakJson)
        :Save("backup_save", {
            ok = function()
                print("[PlayerMgr] 兜底存档已保存: uid=" .. tostring(userId)
                    .. " name=" .. tostring(state.playerName)
                    .. " sid=" .. tostring(sid)
                    .. " size=" .. #bakJson .. "B")
            end,
            error = function(code, reason)
                print("[PlayerMgr] 兜底存档保存失败: uid=" .. tostring(userId)
                    .. " " .. tostring(reason))
            end,
        })
end

--- 获取在线玩家状态
---@param userId number
---@return table|nil
function M.GetState(userId)
    return players_[userId]
end

--- 标记玩家数据为脏
---@param userId number
function M.SetDirty(userId)
    dirty_[userId] = true
end

--- 玩家是否已加载
---@param userId number
---@return boolean
function M.IsLoaded(userId)
    return players_[userId] ~= nil
end

--- 获取所有在线玩家 ID
---@return number[]
function M.GetAllPlayerIds()
    local ids = {}
    for uid, _ in pairs(players_) do
        table.insert(ids, uid)
    end
    return ids
end

--- 强制移除玩家（不保存，直接丢弃内存数据）
--- 用于身份升级时丢弃临时 ID 的数据，避免误保存到 serverCloud
---@param userId number
function M.ForceRemovePlayer(userId)
    if not players_[userId] then return end
    players_[userId] = nil
    dirty_[userId] = nil
    saveTimers_[userId] = nil
    backupTimers_[userId] = nil
    -- 注意: 不清理 serverId_，换服流程需要保留
    print("[PlayerMgr] 玩家已强制移除(不保存): uid=" .. tostring(userId))
end

--- 移除玩家(先保存再移除)
--- 🔴 关键：异步保存回调中用引用比较防止覆盖新会话数据（竞态修复）
---@param userId number
---@param callback? fun()
function M.RemovePlayer(userId, callback)
    if not players_[userId] then
        if callback then callback() end
        return
    end
    if dirty_[userId] then
        -- 捕获当前 state 引用：如果回调执行时 players_[userId] 已被新 LoadPlayer 替换，
        -- 说明玩家已重连并加载了新会话，旧回调不能清理新数据
        local stateRef = players_[userId]
        M.SavePlayer(userId, function()
            if players_[userId] ~= stateRef then
                -- 新会话已加载，跳过清理，避免覆盖新数据
                print("[PlayerMgr] RemovePlayer: 新会话已加载, 跳过清理 uid=" .. tostring(userId))
                if callback then callback() end
                return
            end
            players_[userId] = nil
            dirty_[userId] = nil
            saveTimers_[userId] = nil
            backupTimers_[userId] = nil
            serverId_[userId] = nil
            print("[PlayerMgr] 玩家已保存并移除: uid=" .. tostring(userId))
            if callback then callback() end
        end)
    else
        players_[userId] = nil
        dirty_[userId] = nil
        saveTimers_[userId] = nil
        backupTimers_[userId] = nil
        serverId_[userId] = nil
        print("[PlayerMgr] 玩家已移除: uid=" .. tostring(userId))
        if callback then callback() end
    end
end

--- 定期保存脏数据 & 兜底存档(在 HandleUpdate 中调用)
---@param dt number
function M.UpdateAll(dt)
    for userId, _ in pairs(players_) do
        -- 脏数据定期保存（每30秒）
        saveTimers_[userId] = (saveTimers_[userId] or 0) + dt
        if saveTimers_[userId] >= SAVE_INTERVAL and dirty_[userId] then
            saveTimers_[userId] = 0
            M.SavePlayer(userId)
        end

        -- 兜底存档定期备份（每4小时）
        backupTimers_[userId] = (backupTimers_[userId] or 0) + dt
        if backupTimers_[userId] >= BACKUP_INTERVAL then
            backupTimers_[userId] = 0
            M.BackupPlayer(userId)
        end
    end
end

return M
