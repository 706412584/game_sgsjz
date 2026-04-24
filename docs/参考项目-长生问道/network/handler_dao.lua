-- ============================================================================
-- 《问道长生》悟道处理器（服务端权威）
-- 职责：悟道参悟 — 服务端掷骰 + 进度判定 + 悟透奖励
-- Actions: dao_meditate
-- ============================================================================

local HandlerUtils = require("network.handler_utils")
local DataSkills   = require("data_skills")

local M = {}
M.Actions = {}

-- 每次参悟增加的进度范围（与客户端保持一致）
local PROGRESS_MIN = 5
local PROGRESS_MAX = 15

-- 参悟修为消耗：cost = tier × 100 × (meditateCount + 1)
-- 例：炼气(tier1)第1次=100，第2次=200；筑基(tier3)第1次=300，第2次=600
local function CalcMeditateCost(tier, meditateCount)
    local base = (tier or 1) * 100
    return base * (meditateCount + 1)
end

-- ============================================================================
-- 每日道心追踪工具
-- ============================================================================
local function GetTodayStr()
    return os.date("%Y-%m-%d")
end

--- 获取或重置每日道心追踪数据
--- daoDaily = { date = "YYYY-MM-DD", freeUsed = N, daoGained = N }
local function GetDaoDaily(playerData)
    local today = GetTodayStr()
    local dd = playerData.daoDaily
    if type(dd) ~= "table" or dd.date ~= today then
        dd = { date = today, freeUsed = 0, daoGained = 0 }
        playerData.daoDaily = dd
    end
    return dd
end

--- 检查每日道心上限，返回实际可获得的道心数（可能被裁剪为0）
local function ClampDaoGain(playerData, rawGain)
    local tier = playerData.tier or 1
    local cap = DataSkills.GetDailyDaoHeartCap(tier)
    local dd = GetDaoDaily(playerData)
    local remaining = math.max(0, cap - (dd.daoGained or 0))
    return math.min(rawGain, remaining)
end

--- 记录每日道心获取
local function RecordDaoGain(playerData, amount)
    if amount <= 0 then return end
    local dd = GetDaoDaily(playerData)
    dd.daoGained = (dd.daoGained or 0) + amount
end

-- ============================================================================
-- Action: dao_meditate — 服务端参悟
-- params: { playerKey: string, daoName: string }
-- 返回: { gain, progress, maxProgress, mastered, effectMsg? } + sync
-- ============================================================================

M.Actions["dao_meditate"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local daoName   = params.daoName

    if not playerKey or playerKey == "" then
        reply(false, { msg = "缺少 playerKey" })
        return
    end
    if not daoName or daoName == "" then
        reply(false, { msg = "缺少 daoName" })
        return
    end

    if not serverCloud then
        reply(false, { msg = "服务端存储不可用" })
        return
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores, iscores)
            -- pcall 保护整个异步回调，防止运行时错误导致 reply 永不调用（客户端转圈）
            local cbOk, cbErr = pcall(function()

            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                reply(false, { msg = "玩家数据解析失败" })
                return
            end

            -- 服务端迁移：daoInsights 初始化（镜像客户端 AttachDerived 逻辑）
            if not playerData.daoInsights or #playerData.daoInsights == 0 then
                playerData.daoInsights = {}
                for _, def in ipairs(DataSkills.DAO_INSIGHTS) do
                    playerData.daoInsights[#playerData.daoInsights + 1] = {
                        id           = def.id,
                        name         = def.name,
                        desc         = def.desc or "",
                        reward       = def.reward,
                        maxProgress  = def.maxProgress,
                        progress     = 0,
                        mastered     = false,
                        locked       = (def.unlockTier ~= nil),
                        meditateCount = 0,
                    }
                end
            end

            -- 查找悟道
            local dao = nil
            for _, d in ipairs(playerData.daoInsights or {}) do
                if d.name == daoName then
                    dao = d
                    break
                end
            end
            if not dao then
                reply(false, { msg = "未拥有该悟道" })
                return
            end
            if dao.locked then
                reply(false, { msg = "该悟道尚未解锁" })
                return
            end
            local maxProg = dao.maxProgress or 100
            if (dao.progress or 0) >= maxProg then
                reply(false, { msg = "已悟透此道" })
                return
            end

            -- 每日免费悟道次数
            local tier          = playerData.tier or 1
            local meditateCount = dao.meditateCount or 0
            local daoDaily      = GetDaoDaily(playerData)
            local freeLimit     = DataSkills.FREE_MEDITATE_DAILY or 5
            local isFree        = (daoDaily.freeUsed or 0) < freeLimit

            -- 修为消耗校验（免费次数内跳过）
            local cost = 0
            if not isFree then
                cost = CalcMeditateCost(tier, meditateCount)
                local curCult = playerData.cultivation or 0
                if curCult < cost then
                    reply(false, { msg = string.format("修为不足（需要 %d，当前 %d）", cost, curCult) })
                    return
                end
                -- 扣除修为
                playerData.cultivation = (playerData.cultivation or 0) - cost
            else
                -- 消耗免费次数
                daoDaily.freeUsed = (daoDaily.freeUsed or 0) + 1
            end

            -- 累计参悟次数
            dao.meditateCount = meditateCount + 1

            -- 服务端掷骰计算进度
            local wisdomBonus = math.floor((playerData.wisdom or 0) / 50)
            local gain = math.random(PROGRESS_MIN, PROGRESS_MAX) + wisdomBonus
            local oldProg = dao.progress or 0
            dao.progress = math.min(maxProg, oldProg + gain)

            -- 检查是否悟透
            local mastered = dao.progress >= maxProg
            local effectMsg = ""
            local moneyRewards = {}
            print("[DaoMeditate] PRE-SAVE daoName=" .. daoName
                .. " oldProg=" .. oldProg .. " gain=" .. gain
                .. " newProg=" .. dao.progress .. "/" .. maxProg
                .. " mastered=" .. tostring(mastered)
                .. " uid=" .. tostring(userId))
            if mastered then
                dao.mastered = true  -- 持久化 mastered 标记
                local def = DataSkills.GetInsight(dao.id)
                local rewardStr = def and def.reward or dao.reward or ""
                print("[DaoMeditate] MASTERED rewardStr=" .. tostring(rewardStr) .. " daoId=" .. tostring(dao.id))
                playerData._preDaoHeart = playerData.daoHeart or 0  -- 快照用于裁剪
                effectMsg, moneyRewards = HandlerUtils.ApplyEffectToData(playerData, rewardStr)
                -- 悟透产出的道心受每日上限约束
                local rawDaoGain = (playerData.daoHeart or 0) - (playerData._preDaoHeart or 0)
                -- 回退再按上限重新加
                if rawDaoGain > 0 then
                    playerData.daoHeart = playerData._preDaoHeart or 0
                    local clamped = ClampDaoGain(playerData, rawDaoGain)
                    playerData.daoHeart = (playerData.daoHeart or 0) + clamped
                    RecordDaoGain(playerData, clamped)
                end
                playerData._preDaoHeart = nil  -- 清理临时字段
                print("[DaoMeditate] ApplyEffect done effectMsg=" .. tostring(effectMsg) .. " moneyRewards#=" .. #moneyRewards)
            end

            -- 保存（不含灵石，灵石走 money 子系统）
            print("[DaoMeditate] calling serverCloud:Set uid=" .. tostring(userId))
            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    print("[DaoMeditate] Set OK " .. daoName
                        .. " gain=" .. gain
                        .. " prog=" .. dao.progress .. "/" .. maxProg
                        .. (mastered and " MASTERED" or "")
                        .. " uid=" .. tostring(userId))

                    -- 构造 sync 字段
                    local syncFields = {
                        daoInsights = playerData.daoInsights,
                        cultivation = playerData.cultivation,  -- 参悟已扣修为
                        daoDaily    = playerData.daoDaily,     -- 每日道心追踪
                    }
                    -- 悟透时同步被修改的属性
                    if mastered then
                        syncFields.attack     = playerData.attack
                        syncFields.defense    = playerData.defense
                        syncFields.speed      = playerData.speed
                        syncFields.sense      = playerData.sense
                        syncFields.wisdom     = playerData.wisdom
                        syncFields.fortune    = playerData.fortune
                        syncFields.hp         = playerData.hp
                        syncFields.hpMax      = playerData.hpMax
                        syncFields.mp         = playerData.mp
                        syncFields.mpMax      = playerData.mpMax
                        syncFields.cultivation = playerData.cultivation
                        syncFields.crit       = playerData.crit
                        syncFields.lifespan   = playerData.lifespan
                        syncFields.gameYear   = playerData.gameYear
                        syncFields.daoHeart   = playerData.daoHeart
                    end

                    -- 免费次数与每日道心统计
                    local dd = GetDaoDaily(playerData)
                    local freeRemain = math.max(0, freeLimit - (dd.freeUsed or 0))
                    local daoCap = DataSkills.GetDailyDaoHeartCap(tier)

                    local progressStr = dao.progress .. "/" .. maxProg
                    local freeTag = isFree and "（免费）" or ""
                    local resultMsg = mastered
                        and ("已悟透「" .. daoName .. "」！" .. (effectMsg ~= "" and effectMsg or ""))
                        or  ("参悟「" .. daoName .. "」" .. freeTag .. "，进度 " .. progressStr)
                    local nextCost = isFree and 0 or CalcMeditateCost(tier, dao.meditateCount)
                    -- 如果免费次数还有剩余，下次仍然免费
                    if freeRemain > 0 then
                        nextCost = 0
                    else
                        nextCost = CalcMeditateCost(tier, dao.meditateCount)
                    end
                    local resultData = {
                        msg         = resultMsg,
                        gain        = gain,
                        progress    = dao.progress,
                        maxProgress = maxProg,
                        mastered    = mastered,
                        effectMsg   = mastered and effectMsg or nil,
                        costPaid    = cost,
                        nextCost    = nextCost,
                        isFree      = isFree,
                        freeRemain  = freeRemain,
                        daoDailyGained = dd.daoGained or 0,
                        daoDailyCap    = daoCap,
                    }

                    -- 发放货币奖励（如有灵石等）
                    if #moneyRewards > 0 then
                        print("[DaoMeditate] granting moneyRewards#=" .. #moneyRewards .. " uid=" .. tostring(userId))
                        HandlerUtils.GrantMoneyRewards(userId, moneyRewards, function(balances)
                            if balances then
                                for k2, v2 in pairs(balances) do
                                    syncFields[k2] = v2
                                end
                            end
                            print("[DaoMeditate] REPLY(money) ok=true uid=" .. tostring(userId))
                            reply(true, resultData, syncFields)
                        end)
                    else
                        print("[DaoMeditate] REPLY ok=true mastered=" .. tostring(mastered) .. " uid=" .. tostring(userId))
                        reply(true, resultData, syncFields)
                    end
                end,
                error = function(code, reason)
                    print("[DaoMeditate] Set FAILED uid=" .. tostring(userId) .. " code=" .. tostring(code) .. " reason=" .. tostring(reason))
                    reply(false, { msg = "数据保存失败" })
                end,
            })

            end) -- pcall end
            if not cbOk then
                print("[DaoMeditate] CALLBACK ERROR: " .. tostring(cbErr))
                reply(false, { msg = "服务器内部错误" })
            end
        end,
        error = function(code, reason)
            reply(false, { msg = "读取数据失败" })
        end,
    })
end

return M
