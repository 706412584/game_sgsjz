-- ============================================================================
-- game_tutorial.lua — 交互式新手引导系统 (6步)
-- 带醒目卡片 + "前往"按钮引导切换Tab页
-- ============================================================================
local UI = require("urhox-libs/UI")
local Config = require("data_config")
local State = require("data_state")

local M = {}

local tutorialPanel = nil
---@type function|nil
local tabSwitcherFn = nil

-- ========== 引导步骤定义 ==========
local STEPS = {
    {
        hint = "先制作一份聚气丹吧!",
        actionText = "去制作",
        targetTab = "craft",
        check = function()
            return State.state.totalCrafted >= 1
        end,
        completeMsg = "第一份丹药制作完成!",
    },
    {
        hint = "回到摊位等顾客来买丹药!",
        actionText = "回摊位",
        targetTab = "stall",
        check = function()
            return State.state.totalSold >= 1
        end,
        completeMsg = "售出第一单! 灵石到手!",
    },
    {
        hint = "攒够灵石后升级摊位到 Lv2!",
        actionText = "去升级",
        targetTab = "upgrade",
        check = function()
            return State.state.stallLevel >= 2
        end,
        completeMsg = "摊位升级成功!",
    },
    {
        hint = "继续赚灵石积累修为, 突破筑基解锁回春符!",
        actionText = nil,
        targetTab = nil,
        check = function()
            return State.GetRealmIndex() >= 2
        end,
        completeMsg = "突破筑基! 回春符已解锁!",
    },
    {
        hint = "看一次广告获得客流翻倍增益!",
        actionText = "领福利",
        targetTab = "ad",
        check = function()
            return State.state.totalAdWatched >= 1
        end,
        completeMsg = "广告福利已领取!",
    },
    {
        hint = "下次离线回归时领双倍收益即完成引导!",
        actionText = nil,
        targetTab = nil,
        check = function()
            return State.state.tutorialStep >= 7
        end,
        completeMsg = "恭喜完成全部新手引导!",
    },
}

-- ========== 公开接口 ==========

--- 注册 Tab 切换回调 (main.lua 调用)
---@param fn function
function M.SetTabSwitcher(fn)
    tabSwitcherFn = fn
end

--- 初始化: 对已有存档跳过已完成步骤 (静默)
function M.Init()
    if M.IsCompleted() then return end
    if State.state.tutorialStep == 0 and State.state.storyPlayed then
        State.state.tutorialStep = 1
    end
    -- 静默快进已完成的步骤
    local step = State.state.tutorialStep
    while step >= 1 and step <= #STEPS do
        if STEPS[step].check() then
            step = step + 1
        else
            break
        end
    end
    State.state.tutorialStep = step
end

--- 获取当前引导步骤 (1-6, 0=未开始, 7=已完成)
---@return number
function M.GetCurrentStep()
    return State.state.tutorialStep
end

--- 引导是否已全部完成
---@return boolean
function M.IsCompleted()
    return State.state.tutorialStep >= 7
end

--- 每帧检测并推进引导步骤
function M.Update()
    if M.IsCompleted() then return end

    -- 故事播完后才开始引导
    if State.state.tutorialStep == 0 then
        if State.state.storyPlayed then
            State.state.tutorialStep = 1
        end
        return
    end

    local step = State.state.tutorialStep
    if step >= 1 and step <= #STEPS then
        local stepDef = STEPS[step]
        if stepDef.check() then
            State.state.tutorialStep = step + 1
            local GameCore = require("game_core")
            GameCore.AddLog("[引导] " .. stepDef.completeMsg, Config.Colors.jade)
            UI.Toast.Show(stepDef.completeMsg, { variant = "success", duration = 2 })
            -- 同步到服务端, 防止 GameSync 回退
            if State.serverMode then
                GameCore.SendGameAction("tutorial_step", { step = State.state.tutorialStep })
            end
        end
    end
end

--- 手动完成第6步(离线回归领取双倍时调用)
function M.CompleteOfflineStep()
    if State.state.tutorialStep == 6 then
        State.state.tutorialStep = 7
        local GameCore = require("game_core")
        GameCore.AddLog("[引导] 全部引导完成! 自由发展吧!", Config.Colors.textGold)
        UI.Toast.Show("新手引导完成!", { variant = "success", duration = 3 })
    end
end

-- ========== UI 组件 ==========

--- 创建引导卡片(显示在页面内容区与日志栏之间)
---@return table UI.Panel
function M.Create()
    tutorialPanel = UI.Panel {
        id = "tutorial_bar",
        width = "100%",
        paddingHorizontal = 4,
        paddingVertical = 2,
        backgroundColor = { 45, 35, 18, 245 },
        borderTopWidth = 1,
        borderBottomWidth = 1,
        borderColor = Config.Colors.gold,
        flexDirection = "row",
        alignItems = "center",
        gap = 3,
        children = {
            -- 步骤标识
            UI.Panel {
                width = 16,
                height = 16,
                borderRadius = 8,
                backgroundColor = Config.Colors.goldDark,
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Label {
                        id = "tutorial_step_num",
                        text = "1",
                        fontSize = 9,
                        fontWeight = "bold",
                        fontColor = { 255, 255, 255, 255 },
                    },
                },
            },
            -- 引导文本区域
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                children = {
                    UI.Label {
                        id = "tutorial_hint_label",
                        text = "",
                        fontSize = 10,
                        fontWeight = "bold",
                        fontColor = Config.Colors.textPrimary,
                    },
                },
            },
            -- "前往"操作按钮
            UI.Button {
                id = "tutorial_action_btn",
                text = "前往",
                fontSize = 10,
                fontWeight = "bold",
                width = 46,
                height = 22,
                flexShrink = 0,
                borderRadius = 11,
                backgroundColor = Config.Colors.gold,
                textColor = { 30, 25, 15, 255 },
                onClick = function(self)
                    -- 由 Refresh 动态绑定
                end,
            },
        },
    }
    return tutorialPanel
end

-- ========== 攻略弹窗 ==========
function M.ShowGuideModal()
    local modal = UI.Modal {
        title = "游戏攻略",
        size = "sm",
        onClose = function(self) self:Destroy() end,
    }

    local rows = {}

    -- 辅助函数: 小节标题
    local function sectionTitle(text)
        table.insert(rows, UI.Label {
            text = "-- " .. text .. " --", fontSize = 10,
            fontColor = Config.Colors.textSecond, textAlign = "center",
            width = "100%", marginTop = 6,
        })
    end

    -- 辅助函数: 信息行
    local function infoRow(label, value, color)
        table.insert(rows, UI.Panel {
            flexDirection = "row", justifyContent = "space-between", width = "100%",
            paddingVertical = 2, paddingHorizontal = 4,
            children = {
                UI.Label { text = label, fontSize = 9, fontColor = Config.Colors.textPrimary, flexShrink = 1 },
                UI.Label { text = value, fontSize = 9, fontColor = color or Config.Colors.textSecond, flexShrink = 1, textAlign = "right", marginLeft = 4 },
            },
        })
    end

    -- ===== 基本玩法 =====
    sectionTitle("基本玩法")
    infoRow("制作丹药", "消耗灵田材料,制作后自动上架", Config.Colors.jade)
    infoRow("摆摊售卖", "顾客自动来买,满足需求涨口碑", Config.Colors.jade)
    infoRow("灵石吸收", "灵石转化为修为,提升境界", Config.Colors.jade)
    infoRow("转生重修", "寿元耗尽后转生,保留称号加成", Config.Colors.textGold)

    -- ===== 讨价还价 =====
    sectionTitle("讨价还价")
    local bc = Config.BargainConfig
    infoRow("出现概率", math.floor(bc.bargainChance * 100) .. "%的顾客可讨价", Config.Colors.textGold)
    infoRow("讨价次数", "每位顾客最多" .. bc.maxAttempts .. "次", Config.Colors.textPrimary)
    infoRow("速度递增", "每次加速x" .. bc.speedUpPerAttempt, Config.Colors.orange)
    -- 区域说明
    for _, zone in ipairs(bc.zones) do
        local pct = math.floor(zone.size * 100) .. "%"
        local extra = ""
        if zone.refuseChance and zone.refuseChance > 0 then
            extra = " (顾客" .. math.floor(zone.refuseChance * 100) .. "%概率拒绝)"
        end
        infoRow(zone.label .. " 区域", "占比" .. pct .. extra,
            zone.mul > 1.0 and Config.Colors.textGold
            or (zone.mul < 1.0 and Config.Colors.red or Config.Colors.textSecond))
    end

    -- ===== 顾客类型 =====
    sectionTitle("顾客类型")
    for _, ct in ipairs(Config.CustomerTypes) do
        local desc = "购买x" .. ct.buyCount .. " 付款x" .. ct.payMul
        infoRow(ct.name, desc, { ct.color[1], ct.color[2], ct.color[3], 255 })
    end

    -- ===== 口碑系统 =====
    sectionTitle("口碑系统")
    infoRow("满足顾客需求", "+" .. Config.ReputationGain.matched .. " 口碑", Config.Colors.jade)
    infoRow("卖出非需求物品", "+" .. Config.ReputationGain.unmatched .. " 口碑", Config.Colors.textSecond)
    infoRow("顾客超时离开", tostring(Config.ReputationGain.timeout) .. " 口碑", Config.Colors.red)
    infoRow("连续满足" .. Config.ReputationGain.streakAt .. "位", "+" .. Config.ReputationGain.streakBonus .. " 口碑", Config.Colors.textGold)
    table.insert(rows, UI.Label {
        text = "点击顶部[口碑]查看等级加成详情",
        fontSize = 8, fontColor = Config.Colors.textSecond,
        textAlign = "center", width = "100%",
    })

    -- ===== 境界一览 =====
    sectionTitle("境界成长")
    for i, realm in ipairs(Config.Realms) do
        local xiuweiStr = realm.xiuwei > 0 and (realm.xiuwei .. "修为") or "初始"
        infoRow(realm.name, xiuweiStr .. " | " .. realm.unlockDesc,
            i <= (State.GetRealmIndex and State.GetRealmIndex() or 1) and Config.Colors.jade or Config.Colors.textSecond)
    end

    -- ===== 成长建议 =====
    sectionTitle("成长建议")
    infoRow("1. 优先升级摊位", "增加展示位和顾客上限", Config.Colors.jade)
    infoRow("2. 种植高级灵田", "获取稀有材料制作高价丹", Config.Colors.jade)
    infoRow("3. 保持口碑", "高口碑吸引高付费顾客", Config.Colors.textGold)
    infoRow("4. 合理讨价", "命中+50%利润翻倍,贪心有风险", Config.Colors.orange)
    infoRow("5. 每日任务", "完成任务获取额外灵石奖励", Config.Colors.textGold)

    modal:AddContent(UI.ScrollView {
        width = "100%", maxHeight = 320,
        children = {
            UI.Panel { width = "100%", gap = 2, padding = 2, children = rows },
        },
    })

    modal:SetFooter(UI.Panel {
        flexDirection = "row", justifyContent = "center", width = "100%",
        children = {
            UI.Button {
                text = "关闭", variant = "secondary", width = 80,
                onClick = function() modal:Close() end,
            },
        },
    })

    modal:Open()
end

--- 刷新引导内容
function M.Refresh()
    if not tutorialPanel then return end

    local step = State.state.tutorialStep
    if step <= 0 or step > #STEPS then
        -- 引导完成: 显示攻略按钮
        if step > #STEPS then
            tutorialPanel:Show()
            local numLabel = tutorialPanel:FindById("tutorial_step_num")
            if numLabel then numLabel:SetText("?") end
            local hintLabel = tutorialPanel:FindById("tutorial_hint_label")
            if hintLabel then hintLabel:SetText("点击右侧查看游戏机制和成长攻略") end
            local actionBtn = tutorialPanel:FindById("tutorial_action_btn")
            if actionBtn then
                actionBtn:Show()
                YGNodeStyleSetDisplay(actionBtn.node, YGDisplayFlex)
                actionBtn:SetText("攻略")
                actionBtn.props.onClick = function() M.ShowGuideModal() end
            end
        else
            tutorialPanel:Hide()
        end
        return
    end

    tutorialPanel:Show()

    local stepDef = STEPS[step]

    -- 步骤数字
    local numLabel = tutorialPanel:FindById("tutorial_step_num")
    if numLabel then
        numLabel:SetText(tostring(step))
    end

    -- 提示文字
    local hintLabel = tutorialPanel:FindById("tutorial_hint_label")
    if hintLabel then
        hintLabel:SetText(step .. "/" .. #STEPS .. " " .. stepDef.hint)
    end

    -- 操作按钮: 统一显示"攻略"
    local actionBtn = tutorialPanel:FindById("tutorial_action_btn")
    if actionBtn then
        actionBtn:Show()
        YGNodeStyleSetDisplay(actionBtn.node, YGDisplayFlex)
        actionBtn:SetText("攻略")
        actionBtn.props.onClick = function() M.ShowGuideModal() end
    end
end

return M
