-- ============================================================================
-- ui_ad.lua — 仙缘福利页面 (合并为3大福利)
-- 3种广告增益: 仙缘加持(客流+自动售卖) / 天降横财(补货+商人) / 修仙助力(减免+离线)
-- ============================================================================
local UI = require("urhox-libs/UI")
local Config = require("data_config")
local State = require("data_state")
local GameCore = require("game_core")

local M = {}

local adPanel = nil
local adDirty_ = true  -- 脏标记: 数据变化时设为 true, Refresh 重建后设为 false
local buffTimer_ = 0   -- buff面板刷新计时器

-- 广告超时保护(含播放时间, 需足够长)
local AD_TIMEOUT = 120  -- 秒
local adWaiting_ = false       -- 是否正在等待广告回调
local adWaitStart_ = 0         -- 开始等待时间 (os.time)
local adFinishedFlag_ = false  -- 回调已处理标记(防双重触发)

-- nonce 生成(用于广告奖励幂等性)
local nonceCounter_ = 0
local function generateNonce()
    nonceCounter_ = nonceCounter_ + 1
    return tostring(os.time()) .. "_" .. tostring(nonceCounter_)
end

-- ========== 广告调用封装 ==========

--- 播放广告(或跳过), 成功后回调 onSuccess
--- 服务端模式: 不修改客户端状态, 由服务端统一处理
--- 单机模式: 客户端直接修改状态
---@param rewardKey string 奖励类型key
---@param onSuccess function
local function showRewardAd(rewardKey, onSuccess)
    -- 次数检查(服务端模式由服务端二次校验, 客户端仅做前置拦截)
    if not State.CanClaimAdReward(rewardKey) then
        local limit = State.GetDailyAdLimit(rewardKey)
        UI.Toast.Show("今日已领" .. limit .. "次，明日再来", { variant = "warning", duration = 2 })
        return
    end

    -- 广告播放成功后的处理
    local function onAdComplete()
        if State.serverMode then
            -- 服务端模式: 先持久化待确认记录, 再发 GameAction
            local nonce = generateNonce()
            State.state.pendingAdReward = { key = rewardKey, nonce = nonce }
            GameCore.SendGameAction("ad_reward", { key = rewardKey, nonce = nonce })
        else
            -- 单机模式: 客户端直接处理
            State.UseAdRewardCount(rewardKey)
            State.state.totalAdWatched = State.state.totalAdWatched + 1
            adDirty_ = true
            onSuccess()
        end
    end

    if State.IsAdFree() then
        onAdComplete()
        return
    end

    ---@diagnostic disable-next-line: undefined-global
    if sdk and sdk.ShowRewardVideoAd then
        -- 启动超时保护
        adWaiting_ = true
        adWaitStart_ = os.time()
        adFinishedFlag_ = false

        ---@diagnostic disable-next-line: undefined-global
        sdk:ShowRewardVideoAd(function(result)
            -- 回调到达, 立即取消超时定时器
            adWaiting_ = false
            adFinishedFlag_ = true
            if result and result.success then
                onAdComplete()
            else
                local errMsg = (result and result.msg and result.msg ~= "") and result.msg or "广告未完成"
                UI.Toast.Show(errMsg, { variant = "warning", duration = 3 })
            end
        end)
    else
        -- 无 SDK(开发环境): 直接通过
        onAdComplete()
    end
end

-- ========== 合并后的3大广告项 ==========
local AD_ITEMS = {
    {
        key = "bless",
        name = "仙缘加持",
        desc = "客流翻倍5分钟 + 售价x1.5持续2小时",
        icon = "image/icon_bless.png",
        color = Config.Colors.orange,
        action = function()
            State.state.adFlowBoostEnd = os.time() + 300
            State.state.adPriceBoostEnd = os.time() + 7200
            GameCore.AddLog("仙缘加持! 客流翻倍5分钟+售价x1.5持续2小时", Config.Colors.orange)
            UI.Toast.Show("仙缘加持已激活!", { variant = "success", duration = 2 })
        end,
        isActive = function()
            return GameCore.IsFlowBoosted() or GameCore.IsPriceBoosted()
        end,
        remainText = function()
            local parts = {}
            if GameCore.IsFlowBoosted() then
                table.insert(parts, "客流" .. math.floor(GameCore.FlowBoostRemain()) .. "s")
            end
            if GameCore.IsPriceBoosted() then
                table.insert(parts, "售价" .. math.floor(GameCore.PriceBoostRemain() / 60) .. "min")
            end
            return table.concat(parts, " / ")
        end,
    },
    {
        key = "fortune",
        name = "天降横财",
        desc = "补货20分钟材料 + 商人3倍收购",
        icon = "image/icon_fortune.png",
        color = Config.Colors.gold,
        action = function()
            -- 1) 补货
            for _, mat in ipairs(Config.Materials) do
                State.AddMaterial(mat.id, mat.rate * 20)
            end
            -- 2) 神秘商人3倍清库存
            local totalEarned = 0
            local realmMul = Config.GetRealmPriceMultiplier(State.GetRealmIndex())
            for _, prod in ipairs(Config.Products) do
                local stock = State.state.products[prod.id]
                if stock and stock > 0 then
                    local price = math.floor(prod.price * realmMul * 3)
                    local total = price * stock
                    State.state.products[prod.id] = 0
                    State.AddLingshi(total)
                    totalEarned = totalEarned + total
                end
            end
            if totalEarned > 0 then
                GameCore.AddLog("天降横财! 补货+商人收购 +" .. totalEarned .. "灵石", Config.Colors.gold)
            else
                GameCore.AddLog("天降横财! 材料已补货", Config.Colors.gold)
            end
            UI.Toast.Show("天降横财!", { variant = "success", duration = 2 })
        end,
    },
    {
        key = "aid",
        name = "修仙助力",
        desc = "升级/突破减免30%x3次(2h) + 离线+1小时",
        icon = "image/icon_aid.png",
        color = Config.Colors.purple,
        action = function()
            -- 1) 升级/突破减免 3次, 2小时有效
            State.state.adUpgradeDiscount = 3
            State.state.adDiscountExpire = os.time() + 7200
            -- 2) 离线延长
            local _, adMax = GameCore.GetOfflineAdExtend()
            local extMsg = ""
            if State.state.offlineAdExtend < adMax then
                State.state.offlineAdExtend = State.state.offlineAdExtend + 1
                local remain = adMax - State.state.offlineAdExtend
                extMsg = " + 离线+1h(剩" .. remain .. "次)"
            else
                extMsg = " (离线延长已满)"
            end
            GameCore.AddLog("修仙助力! 升级/突破减免30%x3次" .. extMsg, Config.Colors.purple)
            UI.Toast.Show("修仙助力已激活!", { variant = "success", duration = 2 })
        end,
        isActive = function()
            return State.HasUpgradeDiscount()
        end,
        remainText = function()
            local parts = {}
            if State.HasUpgradeDiscount() then
                local remain = State.state.adUpgradeDiscount or 0
                local secs = math.max(0, (State.state.adDiscountExpire or 0) - os.time())
                local mins = math.floor(secs / 60)
                table.insert(parts, "减免剩" .. remain .. "次(" .. mins .. "min)")
            end
            local ext = State.state.offlineAdExtend or 0
            if ext > 0 then
                table.insert(parts, "离线+" .. ext .. "h")
            end
            return table.concat(parts, " / ")
        end,
    },
    {
        key = "dungeon_ticket",
        name = "秘境探险券",
        desc = "所有秘境今日额外+3次探险机会",
        icon = "image/icon_dungeon_ticket.png",
        color = Config.Colors.jade,
        action = function()
            -- 单机模式: 客户端直接加3次(服务端模式由服务端处理)
            -- 先执行跨天重置, 避免残留旧日期导致后续 CheckDailyReset 清掉今天的 bonus
            State.CheckDailyReset()
            local Config_ = require("data_config")
            for _, dg in ipairs(Config_.Dungeons) do
                if not State.state.dungeonBonusUses then State.state.dungeonBonusUses = {} end
                State.state.dungeonBonusUses[dg.id] = (State.state.dungeonBonusUses[dg.id] or 0) + 3
            end
            GameCore.AddLog("秘境探险券! 所有秘境+3次", Config.Colors.jade)
            UI.Toast.Show("秘境探险券已激活!", { variant = "success", duration = 2 })
        end,
        isActive = function()
            local bonus = State.state.dungeonBonusUses
            if type(bonus) ~= "table" then return false end
            for _, v in pairs(bonus) do
                if v and v > 0 then return true end
            end
            return false
        end,
        remainText = function()
            local bonus = State.state.dungeonBonusUses
            if type(bonus) ~= "table" then return "" end
            local perDungeon = 0
            for _, v in pairs(bonus) do
                if (v or 0) > 0 then perDungeon = v; break end
            end
            if perDungeon <= 0 then return "" end
            return "每秘境+" .. perDungeon .. "次"
        end,
    },
}

-- ========== 广告卡片 (大卡片, 视觉更清晰) ==========

---@param item table
local function createAdCard(item)
    local active = item.isActive and item.isActive()
    local used = State.GetDailyAdCount(item.key)
    local limit = State.GetDailyAdLimit(item.key)
    local exhausted = used >= limit

    -- 按钮文字和状态
    local btnText, btnDisabled
    if exhausted then
        btnText = "已用完"
        btnDisabled = true
    else
        btnText = State.IsAdFree() and "免费领取" or "看广告领取"
        btnDisabled = false
    end

    local btnBg
    if btnDisabled then
        btnBg = { 60, 60, 70, 200 }
    elseif State.IsAdFree() then
        btnBg = Config.Colors.goldDark
    else
        btnBg = Config.Colors.jadeDark
    end

    -- 状态行文本
    local statusText = ""
    if active and item.remainText then
        statusText = item.remainText()
    end

    -- 图标组件: 优先用图片, 回退到文字
    local iconChild
    local iconPath = item.icon
    ---@diagnostic disable-next-line: undefined-global
    local hasIcon = iconPath and cache and cache:Exists(iconPath)
    if hasIcon then
        iconChild = UI.Panel {
            backgroundImage = iconPath,
            backgroundFit = "contain",
            width = 28, height = 28,
            borderRadius = 4,
        }
    else
        -- 文字回退
        local short = item.name:sub(1, 6) -- 取前两个汉字(UTF-8 一个汉字3字节)
        iconChild = UI.Panel {
            width = 28, height = 28,
            borderRadius = 4,
            backgroundColor = item.color,
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Label { text = short, fontSize = 11, fontColor = { 255, 255, 255, 255 } },
            },
        }
    end

    return UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        paddingHorizontal = 6,
        paddingVertical = 5,
        gap = 6,
        backgroundColor = Config.Colors.panelLight,
        borderRadius = 6,
        borderWidth = active and 1 or 1,
        borderColor = active and item.color or Config.Colors.border,
        children = {
            -- 图标
            iconChild,
            -- 信息区
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                gap = 1,
                children = {
                    UI.Label {
                        text = item.name,
                        fontSize = 11,
                        fontColor = active and item.color or Config.Colors.textPrimary,
                        fontWeight = "bold",
                    },
                    UI.Label {
                        text = item.desc,
                        fontSize = 8,
                        fontColor = Config.Colors.textSecond,
                    },
                    -- 状态 + 次数
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 4,
                        children = {
                            statusText ~= "" and UI.Label {
                                text = statusText,
                                fontSize = 8,
                                fontColor = item.color,
                            } or nil,
                            UI.Label {
                                text = "今日 " .. (limit - used) .. "/" .. limit,
                                fontSize = 8,
                                fontColor = exhausted and Config.Colors.red or Config.Colors.textSecond,
                            },
                        },
                    },
                },
            },
            -- 按钮
            UI.Button {
                text = btnText,
                fontSize = 8,
                width = 58,
                height = 26,
                borderRadius = 4,
                backgroundColor = btnBg,
                fontColor = (not btnDisabled) and { 255, 255, 255, 255 } or Config.Colors.textSecond,
                opacity = btnDisabled and 0.6 or 1.0,
                onClick = function(self)
                    if btnDisabled then return end
                    showRewardAd(item.key, item.action)
                end,
            },
        },
    }
end

-- ========== 当前加成面板 ==========

local function refreshBuffPanel()
    if not adPanel then return end
    local buffPanel = adPanel:FindById("buff_detail")
    if not buffPanel then return end

    buffPanel:ClearChildren()

    -- 收集所有激活的 buff
    local buffs = {}

    -- 1) 客流翻倍
    if GameCore.IsFlowBoosted() then
        local secs = math.floor(GameCore.FlowBoostRemain())
        local m, s = math.floor(secs / 60), secs % 60
        table.insert(buffs, {
            label = "客流翻倍",
            value = string.format("%d:%02d", m, s),
            color = Config.Colors.orange,
        })
    end

    -- 2) 售价加成
    if GameCore.IsPriceBoosted() then
        local secs = math.floor(GameCore.PriceBoostRemain())
        local m = math.floor(secs / 60)
        table.insert(buffs, {
            label = "售价x1.5",
            value = m .. "min",
            color = Config.Colors.orange,
        })
    end

    -- 3) 升级/突破减免
    if State.HasUpgradeDiscount() then
        local cnt = State.state.adUpgradeDiscount or 0
        local secs = math.max(0, (State.state.adDiscountExpire or 0) - os.time())
        local m = math.floor(secs / 60)
        table.insert(buffs, {
            label = "升级减免30%",
            value = cnt .. "次/" .. m .. "min",
            color = Config.Colors.purple,
        })
    end

    -- 4) 离线延长
    local ext = State.state.offlineAdExtend or 0
    if ext > 0 then
        table.insert(buffs, {
            label = "离线延长",
            value = "+" .. ext .. "小时",
            color = Config.Colors.jade,
        })
    end

    -- 5) 秘境探险券(显示每秘境的额外次数,取任一秘境值即可,都相同)
    local dungeonBonus = State.state.dungeonBonusUses
    if type(dungeonBonus) == "table" then
        local perDungeon = 0
        for _, v in pairs(dungeonBonus) do
            if (v or 0) > 0 then
                perDungeon = v
                break
            end
        end
        if perDungeon > 0 then
            table.insert(buffs, {
                label = "秘境探险券",
                value = "+" .. perDungeon .. "次/秘境",
                color = Config.Colors.jade,
            })
        end
    end

    -- 6) 免广告特权
    if State.IsAdFree() then
        table.insert(buffs, {
            label = "免广告特权",
            value = State.AdFreeRemainDays() .. "天",
            color = Config.Colors.gold,
        })
    end

    if #buffs > 0 then
        -- 标题行
        buffPanel:AddChild(UI.Label {
            text = "-- 当前加成 --",
            fontSize = 9,
            fontColor = Config.Colors.textGold,
            textAlign = "center",
            width = "100%",
            marginTop = 2,
        })
        -- buff 条目 (两列布局)
        local row = nil
        for i, b in ipairs(buffs) do
            if (i - 1) % 2 == 0 then
                row = UI.Panel {
                    flexDirection = "row",
                    gap = 6,
                    width = "100%",
                }
                buffPanel:AddChild(row)
            end
            row:AddChild(UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                flexGrow = 1,
                flexBasis = 0,
                gap = 3,
                paddingHorizontal = 4,
                paddingVertical = 2,
                backgroundColor = { b.color[1], b.color[2], b.color[3], 25 },
                borderRadius = 4,
                borderWidth = 1,
                borderColor = { b.color[1], b.color[2], b.color[3], 60 },
                children = {
                    UI.Panel {
                        width = 4, height = 4,
                        borderRadius = 2,
                        backgroundColor = b.color,
                    },
                    UI.Label {
                        text = b.label,
                        fontSize = 8,
                        fontColor = Config.Colors.textPrimary,
                    },
                    UI.Panel { flexGrow = 1 },
                    UI.Label {
                        text = b.value,
                        fontSize = 8,
                        fontColor = b.color,
                        fontWeight = "bold",
                    },
                },
            })
        end
    else
        buffPanel:AddChild(UI.Label {
            text = "暂无激活加成，看广告领取福利吧",
            fontSize = 8,
            fontColor = Config.Colors.textSecond,
            textAlign = "center",
            width = "100%",
            marginTop = 4,
        })
    end
end

-- ========== 公开接口 ==========

function M.Create()
    adPanel = UI.Panel {
        id = "ad_page",
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        padding = 6,
        gap = 4,
        children = {
            -- 标题
            UI.Label {
                text = State.IsAdFree()
                    and "-- 仙缘福利 --  免广告特权(" .. State.AdFreeRemainDays() .. "天)"
                    or "-- 仙缘福利 --",
                fontSize = 11,
                fontColor = State.IsAdFree() and Config.Colors.gold or Config.Colors.textGold,
                textAlign = "center",
                width = "100%",
            },
            UI.Label {
                text = "每次可获得组合增益，每项每日可领取",
                fontSize = 8,
                fontColor = Config.Colors.textSecond,
                textAlign = "center",
                width = "100%",
            },
            -- 广告列表
            UI.Panel { id = "ad_list", gap = 4 },
            -- 当前加成详情
            UI.Panel { id = "buff_detail", gap = 3 },
            -- 统计
            UI.Panel {
                id = "ad_stats",
                flexGrow = 1,
                flexBasis = 0,
                justifyContent = "flex-end",
                alignItems = "center",
                paddingVertical = 4,
            },
        },
    }
    return adPanel
end

function M.Refresh()
    if not adPanel then return end
    if not adDirty_ then return end
    adDirty_ = false

    local adList = adPanel:FindById("ad_list")
    if adList then
        adList:ClearChildren()
        for _, item in ipairs(AD_ITEMS) do
            adList:AddChild(createAdCard(item))
        end
    end

    refreshBuffPanel()

    local statsPanel = adPanel:FindById("ad_stats")
    if statsPanel then
        statsPanel:ClearChildren()
        statsPanel:AddChild(UI.Label {
            text = "累计领取: " .. State.state.totalAdWatched .. " 次",
            fontSize = 8,
            fontColor = Config.Colors.textSecond,
        })
        -- QQ群提示
        local qqNumber = "1098193873"
        statsPanel:AddChild(UI.Panel {
            width = "100%",
            backgroundColor = { 40, 35, 55, 200 },
            borderRadius = 8,
            borderWidth = 1,
            borderColor = Config.Colors.purple,
            padding = 8,
            gap = 4,
            alignItems = "center",
            marginTop = 4,
            children = {
                UI.Label {
                    text = "加入QQ群获取更多福利",
                    fontSize = 10,
                    fontColor = Config.Colors.purple,
                    fontWeight = "bold",
                    textAlign = "center",
                    width = "100%",
                },
                UI.Label {
                    text = "群号: " .. qqNumber,
                    fontSize = 12,
                    fontColor = Config.Colors.textGold,
                    fontWeight = "bold",
                    textAlign = "center",
                    width = "100%",
                },
            },
        })
    end
end

--- 标记需要刷新(切换Tab时外部调用)
function M.MarkDirty()
    adDirty_ = true
end

--- 广告调用封装(供外部模块使用, 如离线双倍)
---@param onSuccess function
---@param rewardKey? string 奖励类型key(默认"offline")
function M.ShowRewardAd(onSuccess, rewardKey)
    showRewardAd(rewardKey or "offline", onSuccess)
end

--- 纯播放广告(不走 ad_reward 计数, 仅播放广告并回调)
--- 用于离线双倍等场景: 广告只是门槛, 奖励由调用方自行发 GameAction
--- onResult(watched): watched=true 表示广告已播放(无论SDK报成功还是失败), false 表示未播放
---@param onResult function(watched:boolean) 广告结果回调
function M.PlayAdThenCallback(onResult)
    if State.IsAdFree() then
        onResult(true)
        return
    end

    ---@diagnostic disable-next-line: undefined-global
    if sdk and sdk.ShowRewardVideoAd then
        adWaiting_ = true
        adWaitStart_ = os.time()
        adFinishedFlag_ = false

        ---@diagnostic disable-next-line: undefined-global
        sdk:ShowRewardVideoAd(function(result)
            adWaiting_ = false
            adFinishedFlag_ = true
            if result and result.success then
                -- 广告明确成功
                onResult(true)
            else
                -- 广告SDK返回失败, 但广告可能已播放完毕
                -- 视为已观看, 让调用方决定如何处理(按钮变已观看状态)
                local errMsg = (result and result.msg and result.msg ~= "") and result.msg or "广告播放异常"
                print("[Ad] PlayAdThenCallback SDK报失败: " .. errMsg)
                onResult(true)
            end
        end)
    else
        -- 无 SDK(开发环境): 直接通过
        onResult(true)
    end
end

--- 重连时重置广告等待状态(防止 adWaiting_ 卡死)
function M.ResetAdState()
    if adWaiting_ then
        print("[Ad] 重连: 重置 adWaiting_ 状态")
        adWaiting_ = false
        adFinishedFlag_ = true
    end
end

--- 重连时重发未确认的广告奖励(pendingAdReward 不为 nil 说明广告看了但服务端未确认)
function M.RetryPendingAdReward()
    local pending = State.state.pendingAdReward
    if pending and pending.key and pending.nonce then
        print("[Ad] 重连: 发现未确认的广告奖励, key=" .. pending.key .. " nonce=" .. pending.nonce .. ", 重新发送")
        GameCore.SendGameAction("ad_reward", { key = pending.key, nonce = pending.nonce })
    end
end

--- 超时检测 + buff面板定时刷新(需在 HandleUpdate 中调用)
---@param dt number
function M.Update(dt)
    -- 广告超时保护
    if adWaiting_ and not adFinishedFlag_ then
        if os.time() - adWaitStart_ >= AD_TIMEOUT then
            adFinishedFlag_ = true
            adWaiting_ = false
            UI.Toast.Show("广告加载超时，请稍后再试", { variant = "warning", duration = 3 })
        end
    end

    -- buff面板每秒刷新一次(倒计时实时更新)
    if adPanel then
        buffTimer_ = buffTimer_ + (dt or 0)
        if buffTimer_ >= 1.0 then
            buffTimer_ = 0
            refreshBuffPanel()
        end
    end
end

return M
