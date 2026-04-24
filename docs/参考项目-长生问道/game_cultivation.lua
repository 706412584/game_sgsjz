-- ============================================================================
-- 《问道长生》修炼系统
-- 职责：每秒修为累积、修炼日志、突破 / 渡劫判定
-- 依赖：game_player (数据读写), data_formulas (产出公式), data_realms (境界)
-- ============================================================================

local GamePlayer     = require("game_player")
local DataFormulas   = require("data_formulas")
local DataRealms     = require("data_realms")
local GameQuest      = require("game_quest")
local DataCultArts   = require("data_cultivation_arts")
local GameBattlePass = require("game_battlepass")

local M = {}
local function EnsureOnlineMode()
    if IsNetworkMode() then return true end
    return false, "当前版本仅支持联网模式"
end

-- ============================================================================
-- 配置
-- ============================================================================
local TICK_INTERVAL   = 1.0   -- 每秒结算一次修为
local LOG_INTERVAL    = 5.0   -- 每5秒写一条日志
local INSIGHT_CHANCE  = 0.05  -- 5% 概率触发顿悟（修为翻倍）
local HP_REGEN_PCT    = 0.03  -- 每次日志周期恢复 3% 最大气血
local MP_REGEN_PCT    = 0.02  -- 每次日志周期恢复 2% 最大灵力

-- ============================================================================
-- 状态
-- ============================================================================
local tickTimer_ = 0
local logTimer_  = 0
local running_   = false   -- 是否正在修炼（进入洞府后开启）
local flagSynced_ = false  -- 是否已同步过 cultivated 标记到服务端
local syncTimer_  = 0
local SYNC_INTERVAL = 30   -- 每30秒同步一次修为到服务端
local syncing_    = false  -- 防止并发同步

-- ============================================================================
-- 启动 / 停止
-- ============================================================================

--- 将客户端累积的修为/仙气同步到服务端（防止悟道读取旧值）
local function SyncToServer()
    if syncing_ then return end
    ---@diagnostic disable-next-line: undefined-global
    if not IsNetworkMode() then return end
    local p = GamePlayer.Get()
    if not p then return end

    local GameOps   = require("network.game_ops")
    local GameServer = require("game_server")
    syncing_ = true
    GameOps.Request("cult_sync", {
        playerKey   = GameServer.GetServerKey("player"),
        cultivation = p.cultivation or 0,
        xianQi      = p.xianQi or 0,
    }, function(ok, data)
        syncing_ = false
        if ok then
            print("[Cultivation] 修为同步成功")
        end
    end)
end

function M.Start()
    running_   = true
    tickTimer_ = 0
    logTimer_  = 0
    syncTimer_ = 0
    print("[Cultivation] 开始修炼")

    -- 首次修炼时，同步 cultivated 标记到服务端（用于任务 mq2 检查）
    if not flagSynced_ then
        flagSynced_ = true
        local p = GamePlayer.Get()
        -- 如果服务端已有标记（从 BatchGet 拉取的数据中），无需重复请求
        if p and p.quests and p.quests.mainFlags and p.quests.mainFlags.cultivated then
            return
        end
        GameQuest.SetMainFlag("cultivated", true)  -- 本地标记 + 自动同步服务端
    end
end

function M.Stop()
    if running_ then
        SyncToServer()  -- 停止修炼时立即同步一次
    end
    running_ = false
    print("[Cultivation] 停止修炼")
end

function M.IsRunning()
    return running_
end

-- ============================================================================
-- 计算当前每秒修为
-- ============================================================================

--- 获取当前每秒修为产出
---@return number baseRate, number coupleBonus
function M.GetPerSec()
    local p = GamePlayer.Get()
    if not p then return 0, 0 end
    -- V2: 从修炼功法计算速度加成
    local skillBonus = 0
    local cultArt = p.cultivationArt
    if cultArt and cultArt.id then
        skillBonus = DataCultArts.CalcBonus(cultArt.id, cultArt.level or 1)
    end
    local baseRate = DataFormulas.CalcCultivationPerSec(
        tonumber(p.tier) or 1,
        p.spiritRoots or {},
        skillBonus,
        0   -- 洞府灵气浓度（后续扩展）
    )
    -- 道侣修炼加成
    local coupleBonus = 0
    local GameSocial = require("game_social")
    local couple = GameSocial.GetDaoCouple()
    if couple then
        local DataSocial = require("data_social")
        local intimacy = couple.intimacy or 0
        local lvInfo = DataSocial.GetCoupleLevel(intimacy)
        coupleBonus = lvInfo.cultivateBonus or 0
    end
    -- 种族修炼速度加成
    local racePct = p.cultivationSpeedPct or 0
    return baseRate * (1 + coupleBonus + racePct), coupleBonus
end

-- ============================================================================
-- 每帧更新（由 main.lua HandleUpdate 调用）
-- ============================================================================

---@param dt number
function M.Update(dt)
    if not running_ then return end
    local p = GamePlayer.Get()
    if not p then return end

    -- 定期同步修为到服务端（每 SYNC_INTERVAL 秒）
    syncTimer_ = syncTimer_ + dt
    if syncTimer_ >= SYNC_INTERVAL then
        syncTimer_ = 0
        SyncToServer()
    end

    -- 修为结算
    tickTimer_ = tickTimer_ + dt
    if tickTimer_ >= TICK_INTERVAL then
        tickTimer_ = tickTimer_ - TICK_INTERVAL
        local perSec = M.GetPerSec()
        -- 顿悟判定
        local insight = false
        if math.random() < INSIGHT_CHANCE then
            perSec = perSec * 2
            insight = true
        end
        local gained = math.floor(perSec)
        -- 仙人期（tier >= 11）积累仙气；凡人期积累修为
        local isImmortal = (tonumber(p.tier) or 1) >= 11
        if gained > 0 then
            if isImmortal then
                GamePlayer.AddXianQi(gained)
            else
                GamePlayer.AddCultivation(gained)
            end
        end
        -- 日志（控制频率）
        logTimer_ = logTimer_ + TICK_INTERVAL
        if logTimer_ >= LOG_INTERVAL then
            logTimer_ = 0
            -- 任务通知：静修（每次日志周期算1次修炼）
            GameQuest.NotifyAction("cultivate", 1)

            -- 静修恢复气血和灵力
            local hpMax = p.hpMax or 100
            local mpMax = p.mpMax or 50
            local hpHeal = math.floor(hpMax * HP_REGEN_PCT)
            local mpHeal = math.floor(mpMax * MP_REGEN_PCT)
            local hpBefore = p.hp or 0
            local mpBefore = p.mp or 0
            if hpHeal > 0 and hpBefore < hpMax then
                GamePlayer.HealHP(hpHeal)
            end
            if mpHeal > 0 and mpBefore < mpMax then
                GamePlayer.HealMP(mpHeal)
            end

            -- 日志文本
            local healNote = ""
            local actualHpHeal = math.min(hpHeal, hpMax - hpBefore)
            local actualMpHeal = math.min(mpHeal, mpMax - mpBefore)
            if actualHpHeal > 0 or actualMpHeal > 0 then
                local parts = {}
                if actualHpHeal > 0 then parts[#parts + 1] = "气血+" .. actualHpHeal end
                if actualMpHeal > 0 then parts[#parts + 1] = "灵力+" .. actualMpHeal end
                healNote = "，" .. table.concat(parts, "、")
            end

            local resourceLabel = isImmortal and "仙气" or "修为"
            if insight then
                GamePlayer.AddLog("偶有所悟，" .. resourceLabel .. "+" .. gained .. healNote .. "!")
            else
                if isImmortal then
                    GamePlayer.AddLog("你正在仙府吐纳，" .. resourceLabel .. "+" .. gained .. healNote .. "...")
                else
                    GamePlayer.AddLog("你正在洞府静修，" .. resourceLabel .. "+" .. gained .. healNote .. "...")
                end
            end
        end
    end
end

-- ============================================================================
-- 突破（小境界晋升）
-- ============================================================================

--- 检查是否满足小境界晋升条件
---@return boolean canBreak, string reason, table|nil extra  extra={required,current} when reason=="dao_heart"
function M.CanAdvanceSub()
    local p = GamePlayer.Get()
    if not p then return false, "无角色数据" end
    local tier = tonumber(p.tier) or 1
    local sub  = tonumber(p.sub) or 1

    -- 资源检查：仙人期用仙气，凡人期用修为
    if tier >= 11 then
        local xianQi    = tonumber(p.xianQi) or 0
        local xianQiMax = tonumber(p.xianQiMax) or 0
        if xianQi < xianQiMax then
            return false, "仙气不足"
        end
    else
        local cult    = tonumber(p.cultivation) or 0
        local maxCult = tonumber(p.cultivationMax) or 0
        if cult < maxCult then
            return false, "修为不足"
        end
    end
    -- 已至大圆满，不能再晋升小境界
    if sub >= 4 then
        return false, "已至大圆满"
    end
    -- 道心检查（时间门）
    local required = DataRealms.GetDaoHeartReq(tier, sub)
    if required > 0 then
        local current = tonumber(p.daoHeart) or 0
        if current < required then
            return false, "dao_heart", { required = required, current = current }
        end
    end
    return true, ""
end

--- 执行小境界晋升（不消耗修为，直接升级）
---@param callback? fun(ok: boolean, msg: string)
---@return boolean success, string message
function M.AdvanceSub(callback)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then
        if callback then callback(false, onlineErr) end
        return false, onlineErr
    end

    -- 网络模式：跳过客户端校验，由服务端做权威验证（客户端缓存可能滞后）
    if not IsNetworkMode() then
        local ok, reason, extra = M.CanAdvanceSub()
        if not ok then
            local msg = reason
            if reason == "dao_heart" and extra then
                msg = string.format("道心不足（当前 %d，需 %d）", extra.current, extra.required)
            end
            if callback then callback(false, msg) end
            return false, msg
        end
    end

    local GameOps = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("advance_sub", {
        playerKey = GameServer.GetServerKey("player"),
    }, function(ok2, data)
        if ok2 then
            local msg = "突破成功：" .. (data.targetName or "未知境界")
            GamePlayer.AddLog(msg)
            -- 境界突破增加通行证经验
            GameBattlePass.AddExp("breakthrough")
            if callback then callback(true, msg) end
        else
            local msg = (data and data.msg) or "突破失败"
            if callback then callback(false, msg) end
        end
    end, { loading = "突破中..." })
    return true, "请求已发送"
end

function M.CanTribulation()
    local p = GamePlayer.Get()
    if not p then return false, "无角色数据" end
    local tier = tonumber(p.tier) or 1
    local sub  = tonumber(p.sub) or 1

    -- 必须在大圆满期（sub=4）方可渡劫
    if sub < 4 then
        return false, "需达到" .. DataRealms.GetFullName(tier, 4) .. "方可渡劫"
    end
    -- 修为需求
    local cult = tonumber(p.cultivation) or 0
    local maxCult = tonumber(p.cultivationMax) or 0
    if cult < maxCult then
        return false, "修为不足"
    end
    -- 最大阶数
    if tier >= 10 then
        return false, "已达最高境界"
    end
    return true, ""
end

--- 获取渡劫信息
---@return table|nil { name, successRate, pillBonus }
function M.GetTribulationInfo()
    local p = GamePlayer.Get()
    if not p then return nil end
    local targetTier = (tonumber(p.tier) or 1) + 1
    local trib = DataRealms.GetTribulation(targetTier)
    if not trib then return nil end
    return {
        name        = trib.name,
        targetTier  = targetTier,
        targetName  = DataRealms.GetFullName(targetTier, 1),
        baseRate    = trib.baseRate,
        pillBonus   = trib.pillBonus,
        successRate = DataFormulas.CalcBreakRate(targetTier, 0),
    }
end

--- 获取玩家持有的突破辅助丹药列表
---@return table[] { id, name, effect, count }
function M.GetBreakthroughPills()
    local p = GamePlayer.Get()
    if not p then return {} end

    local DataItems = require("data_items")
    local result = {}
    for _, def in ipairs(DataItems.PILLS_BREAKTHROUGH) do
        for _, pill in ipairs(p.pills or {}) do
            if pill.name == def.name and (pill.count or 0) > 0 then
                result[#result + 1] = {
                    id     = def.id,
                    name   = def.name,
                    effect = def.effect,
                    count  = pill.count,
                }
                break
            end
        end
    end
    return result
end

--- 处理 tribulation_attempt 结果（内部，小游戏结束后调用）
local function HandleTribulationResult(ok2, data, callback)
    if not ok2 then
        local msg = (data and data.msg) or "渡劫请求失败"
        if callback then callback(false, msg) end
        return
    end
    local d = data or {}
    if d.success then
        local msg = "渡劫成功：" .. (d.targetName or "未知境界")
        if d.awakened then
            local awakenMsg = "灵根觉醒！获得" .. (d.awakened.name or "未知灵根")
            GamePlayer.AddLog(awakenMsg)
            msg = msg .. "\n" .. awakenMsg
        end
        GamePlayer.AddLog(msg)
        if callback then callback(true, msg) end
    else
        local failMsg = "渡劫失败"
        if d.subDropped then failMsg = "渡劫失败，小境界下降" end
        GamePlayer.AddLog(failMsg)
        if callback then callback(false, failMsg) end
    end
end

--- 执行渡劫（含渡劫小游戏流程）
---@param pillNames? string[] 使用的辅助丹药名称列表（每种最多1枚）
---@param callback? fun(ok: boolean, msg: string)
---@return boolean success, string message
function M.DoTribulation(pillNames, callback)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then
        if callback then callback(false, onlineErr) end
        return false, onlineErr
    end

    -- 网络模式：跳过客户端校验，由服务端做权威验证
    if not IsNetworkMode() then
        local ok, reason = M.CanTribulation()
        if not ok then
            if callback then callback(false, reason) end
            return false, reason
        end
    end

    local GameOps    = require("network.game_ops")
    local GameServer = require("game_server")
    local playerKey  = GameServer.GetServerKey("player")

    -- 第一步：向服务端请求渡劫令牌（服务端校验前置条件 + 发放令牌）
    GameOps.Request("dujie_request", { playerKey = playerKey },
        function(reqOk, reqData)
            if not reqOk then
                local msg = (reqData and reqData.msg) or "渡劫请求失败"
                if callback then callback(false, msg) end
                return
            end

            local d = reqData or {}

            -- tier 1~5 无小游戏：直接发起渡劫
            if d.skipMiniGame then
                GameOps.Request("tribulation_attempt", {
                    playerKey = playerKey,
                    pillNames = pillNames,
                }, function(ok2, data2)
                    HandleTribulationResult(ok2, data2, callback)
                end, { loading = "渡劫中..." })
                return
            end

            -- tier 6~10：进入渡劫小游戏
            local token   = d.token
            local tierCfg = d.tierCfg
            if not tierCfg then
                if callback then callback(false, "小游戏配置错误") end
                return
            end

            local GameDujie = require("game_dujie")
            GameDujie.StartGame(tierCfg, function(survived)
                -- 无论胜负均消耗丹药，由服务端处理
                -- 将小游戏结果（survived）传给服务端（仅影响成功率加成，不影响必须丹消耗）
                GameOps.Request("tribulation_attempt", {
                    playerKey = playerKey,
                    pillNames = pillNames,
                    token     = token,
                    survived  = survived,  -- 供服务端日志/统计
                }, function(ok2, data2)
                    HandleTribulationResult(ok2, data2, callback)
                end, { loading = "结算中..." })
            end)
        end,
        { loading = "天劫将至..." }
    )
    return true, "请求已发送"
end

function M.ApplyOfflineGains()
    local secs, cult = GamePlayer.CalcOfflineGains()
    if cult > 0 then
        GamePlayer.AddCultivation(cult)
        local minutes = math.floor(secs / 60)
        GamePlayer.AddLog(string.format(
            "离线 %d 分钟，获得修为 %d", minutes, cult
        ))
        print(string.format(
            "[Cultivation] 离线收益: %d分钟, 修为+%d", minutes, cult
        ))
    end
    return secs, cult
end

return M
