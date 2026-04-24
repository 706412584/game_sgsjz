-- ============================================================================
-- 《问道长生》炼丹处理器（服务端权威）
-- 职责：材料校验 + 消耗 + 成功率判定 + 丹药产出，全部由服务端执行
-- Actions: alchemy_craft
-- ============================================================================

local DataItems   = require("data_items")
local PillsHelper = require("network.pills_helper")

local M = {}
M.Actions = {}

-- 炼丹经验奖励
local ALCHEMY_EXP_SUCCESS = 10
local ALCHEMY_EXP_FAIL    = 3

-- ============================================================================
-- 气运 → 炼丹成功率加成（与客户端 game_alchemy.lua 保持一致）
-- ============================================================================
local FORTUNE_BONUS = {
    ["低迷"] = -5,
    ["普通"] = 0,
    ["小吉"] = 5,
    ["大吉"] = 10,
    ["天命"] = 15,
}

-- ============================================================================
-- 丹方数据（服务端需要独立的配方验证，不依赖客户端 DataItems）
-- 从 data_items.lua 同步
-- ============================================================================

local RECIPES = {}

-- 通用丹药
local PILLS_COMMON = {
    { id = "peiyuan",     name = "培元丹",     quality = "common",   effect = "修为+200",          materials = { ["灵草"] = 1, ["矿石"] = 2 },         rate = 80 },
    { id = "huiqi",       name = "回气丹",     quality = "common",   effect = "灵力恢复100",        materials = { ["灵草"] = 1, ["灵泉水"] = 1 },       rate = 80 },
    { id = "ningshen",    name = "凝神丹",     quality = "uncommon", effect = "神识+20",            materials = { ["灵草"] = 2, ["兽骨"] = 1 },         rate = 60 },
    { id = "tongmai",     name = "通脉丹",     quality = "rare",     effect = "修炼速度+20%(1小时)", materials = { ["灵草"] = 3, ["灵泉水"] = 1 },       rate = 40 },
    { id = "peiyuan_up",  name = "上品培元丹", quality = "uncommon", effect = "修为+1000",          materials = { ["灵草"] = 3, ["矿石"] = 5 },         rate = 50 },
    { id = "peiyuan_top", name = "极品培元丹", quality = "rare",     effect = "修为+5000",          materials = { ["灵草"] = 5, ["天材地宝"] = 1 },     rate = 30 },
}

-- 限制丹药
local PILLS_LIMITED = {
    { id = "hongyun",  name = "鸿运丹", quality = "rare",     effect = "气运+1级",     materials = { ["灵草"] = 5, ["天材地宝"] = 1 }, rate = 25 },
    { id = "qiangshen", name = "强身丹", quality = "uncommon", effect = "气血+50(永久)", materials = { ["灵草"] = 2, ["兽骨"] = 2 },    rate = 50 },
    { id = "linggong", name = "灵攻丹", quality = "uncommon", effect = "攻击+10(永久)", materials = { ["灵草"] = 2, ["矿石"] = 3 },    rate = 50 },
    { id = "guyuan",   name = "固元丹", quality = "uncommon", effect = "防御+8(永久)",  materials = { ["兽骨"] = 3, ["矿石"] = 2 },    rate = 50 },
    { id = "jifeng",   name = "疾风丹", quality = "rare",     effect = "速度+3(永久)",  materials = { ["灵草"] = 3, ["灵泉水"] = 2 },  rate = 35 },
    { id = "xisui",    name = "洗髓丹", quality = "rare",     effect = "悟性+5(永久)",  materials = { ["灵草"] = 3, ["天材地宝"] = 1 }, rate = 30 },
}

-- 突破丹药
local PILLS_BREAKTHROUGH = {
    { id = "zhuji",    name = "筑基丹", quality = "rare", effect = "渡劫成功率+20%", materials = { ["灵草"] = 5, ["天材地宝"] = 1 }, rate = 20 },
    { id = "qingxin",  name = "清心丹", quality = "rare", effect = "渡劫失败不降道心", materials = { ["灵草"] = 5, ["灵泉水"] = 3 },  rate = 25 },
    { id = "pojie",    name = "破劫丹", quality = "epic", effect = "渡劫成功率+30%", materials = { ["天材地宝"] = 3 },              rate = 10 },
}

-- 构建查找表
local function BuildRecipeIndex()
    for _, list in ipairs({ PILLS_COMMON, PILLS_LIMITED, PILLS_BREAKTHROUGH }) do
        for _, r in ipairs(list) do
            RECIPES[r.id] = r
        end
    end
end
BuildRecipeIndex()

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 在背包中查找材料数量
---@param bagItems table[]
---@param matName string
---@return number
local function CountMaterial(bagItems, matName)
    for _, item in ipairs(bagItems) do
        if item.name == matName then
            return item.count or 0
        end
    end
    return 0
end

--- 从背包中扣除材料
---@param bagItems table[]
---@param matName string
---@param amount number
local function RemoveMaterial(bagItems, matName, amount)
    for i, item in ipairs(bagItems) do
        if item.name == matName then
            item.count = (item.count or 0) - amount
            if item.count <= 0 then
                table.remove(bagItems, i)
            end
            return
        end
    end
end

--- 添加丹药到 pills 列表（堆叠同名）
---@param pills table[]
---@param recipe table
local function AddPill(pills, recipe)
    for _, pill in ipairs(pills) do
        if pill.name == recipe.name then
            pill.count = (pill.count or 0) + 1
            return
        end
    end
    pills[#pills + 1] = {
        name    = recipe.name,
        count   = 1,
        quality = recipe.quality or "common",
        desc    = recipe.effect or "",
        effect  = recipe.effect or "",
    }
end

-- ============================================================================
-- Action: alchemy_craft — 服务端炼丹
-- params: { recipeId: string, playerKey: string }
-- 返回: { success: bool, recipeId, pillName, rate, bagItems, pills }
-- ============================================================================

M.Actions["alchemy_craft"] = function(userId, params, reply)
    local recipeId  = params.recipeId
    local playerKey = params.playerKey

    -- 参数校验
    if not recipeId or recipeId == "" then
        reply(false, { msg = "缺少丹方 ID" })
        return
    end
    if not playerKey or playerKey == "" then
        reply(false, { msg = "缺少 playerKey" })
        return
    end

    -- 查找丹方
    local recipe = RECIPES[recipeId]
    if not recipe then
        reply(false, { msg = "未知丹方: " .. tostring(recipeId) })
        return
    end
    if not recipe.materials then
        reply(false, { msg = "丹方缺少材料配置" })
        return
    end

    if not serverCloud then
        reply(false, { msg = "服务端存储不可用" })
        return
    end

    -- 读取玩家数据
    serverCloud:Get(userId, playerKey, {
        ok = function(scores, iscores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                reply(false, { msg = "玩家数据解析失败" })
                return
            end

            local bagItems = playerData.bagItems or {}

            -- 从独立 key 读取丹药
            PillsHelper.Read(userId, function(pills, errMsg)
                if not pills then
                    reply(false, { msg = "丹药数据读取失败" })
                    return
                end

                -- 验证材料
                for matName, needCount in pairs(recipe.materials) do
                    local have = CountMaterial(bagItems, matName)
                    if have < needCount then
                        reply(false, { msg = matName .. "不足（需要" .. needCount .. "，持有" .. have .. "）" })
                        return
                    end
                end

                -- 消耗材料
                for matName, needCount in pairs(recipe.materials) do
                    RemoveMaterial(bagItems, matName, needCount)
                end

                -- 炼丹等级 & 加成
                local alchemyExp = playerData.alchemyExp or 0
                local levelInfo  = DataItems.GetAlchemyLevel(alchemyExp)

                -- 计算最终成功率
                local baseRate = recipe.rate or 50
                local fortune  = playerData.fortune or "普通"
                local bonus    = FORTUNE_BONUS[fortune] or 0
                local levelBonus = levelInfo.rateBonus or 0
                local finalRate = math.max(1, math.min(100, baseRate + bonus + levelBonus))

                -- 服务端掷骰
                local roll = math.random(100)
                local success = roll <= finalRate

                if success then
                    AddPill(pills, recipe)
                    playerData.alchemyExp = alchemyExp + ALCHEMY_EXP_SUCCESS
                else
                    playerData.alchemyExp = alchemyExp + ALCHEMY_EXP_FAIL
                end

                playerData.bagItems = bagItems
                playerData.pills = nil  -- 从 blob 中清除，已迁移到独立 key

                -- 写入丹药独立 key
                PillsHelper.Write(userId, pills, function(pillsOk)
                    if not pillsOk then
                        print("[Alchemy] pills 写入失败 uid=" .. tostring(userId))
                    end
                    -- 保存 playerData（bagItems + alchemyExp，不含 pills）
                    serverCloud:Set(userId, playerKey, playerData, {
                        ok = function()
                            print("[Alchemy] " .. (success and "成功" or "失败")
                                .. " recipe=" .. recipeId
                                .. " rate=" .. finalRate
                                .. " roll=" .. roll
                                .. " lvBonus=" .. levelBonus
                                .. " exp=" .. tostring(playerData.alchemyExp)
                                .. " uid=" .. tostring(userId))
                            reply(true, {
                                success  = success,
                                recipeId = recipeId,
                                pillName = recipe.name,
                                rate     = finalRate,
                            }, {
                                bagItems   = bagItems,
                                pills      = pills,
                                alchemyExp = playerData.alchemyExp,
                            })
                        end,
                        error = function(code, reason)
                            print("[Alchemy] 保存失败 uid=" .. tostring(userId) .. " " .. tostring(reason))
                            reply(false, { msg = "数据保存失败" })
                        end,
                    })
                end, playerKey)
            end, playerKey)
        end,
        error = function(code, reason)
            print("[Alchemy] 读取玩家数据失败 uid=" .. tostring(userId) .. " " .. tostring(reason))
            reply(false, { msg = "读取数据失败" })
        end,
    })
end

return M
