-- ============================================================================
-- 《问道长生》大能传承面板
-- 故事第4幕结束后，在原背景上浮现传承界面
-- 大能逐句对白 → 选性别 → 输道号 → 踏入仙途
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Router = require("ui_router")
local GameServer = require("game_server")
local GamePlayer = require("game_player")
local DataRace   = require("data_race")

local M = {}

-- ============================================================================
-- 随机道号
-- ============================================================================
local NAME_PREFIXES = {
    "清", "玄", "紫", "青", "云", "风", "明", "星", "天", "灵",
    "无", "凌", "逸", "幽", "苍", "墨", "白", "素", "尘", "寒",
    "静", "虚", "道", "真", "玉", "鹤", "松", "竹", "兰", "梅",
}
local NAME_SUFFIXES = {
    "尘", "风", "云", "鹤", "阳", "虚", "玄", "真", "一", "然",
    "道", "心", "明", "远", "空", "逸", "默", "幽", "澜", "霄",
    "微", "渺", "朴", "素", "清", "宁", "安", "止", "觉", "悟",
}

local function RandomDaoName()
    local p = NAME_PREFIXES[math.random(1, #NAME_PREFIXES)]
    local s = NAME_SUFFIXES[math.random(1, #NAME_SUFFIXES)]
    while s == p do
        s = NAME_SUFFIXES[math.random(1, #NAME_SUFFIXES)]
    end
    return p .. s
end

-- ============================================================================
-- 大能对白阶段定义
-- ============================================================================
local DIALOGUE_STEPS = {
    { type = "line", text = "吾等此人，已三千载。" },
    { type = "line", text = "今观汝骨相奇特，堪承吾之衣钵。" },
    { type = "line", text = "汝为男子？女子？" },
    { type = "gender" },    -- 出现性别选择
    { type = "line", text = "嗯...汝身上气息特殊，似乎并非寻常出身。" },
    { type = "line", text = "汝可知自己源出何族？" },
    { type = "race" },      -- 出现种族选择
    { type = "line", text = "好。报上名来。" },
    { type = "name" },      -- 出现道号输入
    { type = "line", text = "甚好。从今日起，汝便是吾之传人。" },
    { type = "line", text = "吾将毕生所学，尽数传于汝。" },
    { type = "line", text = "去吧，走出自己的道。" },
    { type = "confirm" },   -- 出现"踏入仙途"按钮
}

-- ============================================================================
-- 状态
-- ============================================================================
local active_ = false
local stepIndex_ = 0
local stepTimer_ = 0
local STEP_INTERVAL = 1.0       -- 每句对白间隔
local gender_ = nil             -- 尚未选择
local race_ = nil               -- 种族 ID（尚未选择）
local daoName_ = ""
local panelElement_ = nil       -- 传承面板的 UI 引用
local onCleanup_ = nil          -- 清理回调（通知 ui_story 停止粒子等）

-- 各步骤 UI 元素引用（用于逐步淡入）
local stepElements_ = {}
local genderSelected_ = false
local raceSelected_ = false
local nameEntered_ = false

-- 按钮引用（用于切换高亮）
local genderButtons_ = {}   -- { "男" = element, "女" = element }
local raceButtons_ = {}     -- { [raceId] = element }

-- ============================================================================
-- 启动传承面板
-- onCleanup: 确认后的清理回调
-- ============================================================================
function M.Start(onCleanup)
    active_ = true
    stepIndex_ = 0
    stepTimer_ = 0
    gender_ = nil
    race_ = nil
    daoName_ = RandomDaoName()
    genderSelected_ = false
    raceSelected_ = false
    nameEntered_ = false
    onCleanup_ = onCleanup
    stepElements_ = {}
    genderButtons_ = {}
    raceButtons_ = {}
end

-- ============================================================================
-- 是否激活
-- ============================================================================
function M.IsActive()
    return active_
end

-- ============================================================================
-- 每帧更新（由故事页 NVG updater 调用）
-- ============================================================================
function M.Update(dt)
    if not active_ then return end

    -- 等待性别选择 / 道号输入 阶段不自动推进
    if stepIndex_ > 0 and stepIndex_ <= #DIALOGUE_STEPS then
        local step = DIALOGUE_STEPS[stepIndex_]
        if step.type == "gender" and not genderSelected_ then return end
        if step.type == "race" and not raceSelected_ then return end
        if step.type == "name" and not nameEntered_ then return end
        if step.type == "confirm" then return end
    end

    stepTimer_ = stepTimer_ + dt
    if stepTimer_ < STEP_INTERVAL then return end
    stepTimer_ = 0

    -- 推进到下一步
    stepIndex_ = stepIndex_ + 1
    if stepIndex_ > #DIALOGUE_STEPS then return end

    local step = DIALOGUE_STEPS[stepIndex_]
    local el = stepElements_[stepIndex_]
    if el then
        el:Animate({
            keyframes = {
                [0] = { opacity = 0, translateY = 10 },
                [1] = { opacity = 1, translateY = 0 },
            },
            duration = 0.6,
            easing = "easeOut",
            fillMode = "forwards",
        })
    end
end

-- ============================================================================
-- 确认选择性别
-- ============================================================================
local function SelectGender(g)
    gender_ = g
    genderSelected_ = true
    -- 重置所有性别按钮样式，再由 onClick 高亮当前按钮
    for key, btn in pairs(genderButtons_) do
        if key ~= g then
            btn:SetStyle({ backgroundColor = { 45, 38, 30, 200 }, borderColor = Theme.colors.borderGold })
            local lbl = btn:GetChildren()[1]
            if lbl then lbl:SetStyle({ fontColor = Theme.colors.textGold }) end
        end
    end
    stepTimer_ = 0  -- 重置计时，准备推进下一步
end

-- ============================================================================
-- 确认选择种族
-- ============================================================================
local function SelectRace(raceId)
    race_ = raceId
    raceSelected_ = true
    -- 重置所有种族按钮样式，再由 onClick 高亮当前按钮
    for rid, btn in pairs(raceButtons_) do
        if rid ~= raceId then
            local raceDef = DataRace.GetRace(rid)
            if raceDef then
                btn:SetStyle({
                    backgroundColor = { 45, 38, 30, 200 },
                    borderWidth = 1,
                })
            end
        end
    end
    stepTimer_ = 0
end

-- ============================================================================
-- 确认道号
-- ============================================================================
local function ConfirmName()
    if nameEntered_ then return end
    if #daoName_ == 0 then
        daoName_ = RandomDaoName()
    end
    nameEntered_ = true
    stepTimer_ = 0
end

-- ============================================================================
-- 踏入仙途
-- ============================================================================
local function EnterGame()
    active_ = false
    local charInfo = {
        gender = gender_ or "男",
        name = daoName_,
        avatarIndex = 1,
        race = race_ or DataRace.DEFAULT,
    }
    -- 保存到全局（供过渡阶段 UI 读取）
    M.roleData = charInfo

    -- 通过 GamePlayer 创建角色并保存到云端
    GamePlayer.CreateCharacter(charInfo, function(success)
        if success then
            print("[Inheritance] 角色创建并保存成功")
        else
            print("[Inheritance] 角色创建保存失败（本地已创建）")
        end
    end)

    if onCleanup_ then onCleanup_() end
    Router.EnterState(Router.STATE_HOME, { newPlayer = true })
end

-- ============================================================================
-- 跳过传承（跳过按钮用）
-- ============================================================================
function M.Skip()
    active_ = false
    local charInfo = {
        gender = "男",
        name = RandomDaoName(),
        avatarIndex = 1,
        race = DataRace.DEFAULT,
    }
    M.roleData = charInfo

    GamePlayer.CreateCharacter(charInfo, function(success)
        if success then
            print("[Inheritance] 跳过创角，数据已保存到云端")
        else
            print("[Inheritance] 跳过创角保存失败（本地已创建）")
        end
    end)

    if onCleanup_ then onCleanup_() end
    Router.EnterState(Router.STATE_HOME, { newPlayer = true })
end

-- ============================================================================
-- 构建传承面板 UI（叠加在故事页背景上）
-- ============================================================================
function M.Build()
    stepElements_ = {}

    -- 对白文字行构建
    local children = {}

    -- 标题
    children[#children + 1] = UI.Label {
        text = "得 上 古 传 承",
        fontSize = 26,
        fontWeight = "bold",
        fontColor = Theme.colors.textGold,
        textAlign = "center",
        marginBottom = 4,
    }
    children[#children + 1] = UI.Panel {
        width = 120, height = 1,
        backgroundColor = { 180, 150, 80, 100 },
        alignSelf = "center",
        marginBottom = 12,
    }

    -- 逐步对白
    for i, step in ipairs(DIALOGUE_STEPS) do
        if step.type == "line" then
            local el = UI.Label {
                text = step.text,
                fontSize = Theme.fontSize.body,
                fontColor = { 220, 210, 180, 255 },
                textAlign = "center",
                opacity = 0,
                marginTop = 4,
            }
            stepElements_[i] = el
            children[#children + 1] = el

        elseif step.type == "gender" then
            local el = UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "center",
                gap = 20,
                marginTop = 10,
                marginBottom = 6,
                opacity = 0,
                children = {
                    -- 男修
                    (function()
                        local btn = UI.Panel {
                            width = 100, height = 44,
                            borderRadius = Theme.radius.md,
                            backgroundColor = { 45, 38, 30, 200 },
                            borderColor = Theme.colors.borderGold,
                            borderWidth = 1,
                            justifyContent = "center",
                            alignItems = "center",
                            cursor = "pointer",
                            onClick = function(self)
                                SelectGender("男")
                                self:SetStyle({ backgroundColor = Theme.colors.gold, borderColor = Theme.colors.goldDark })
                                local lbl = self:GetChildren()[1]
                                if lbl then lbl:SetStyle({ fontColor = Theme.colors.btnPrimaryText }) end
                            end,
                            children = {
                                UI.Label {
                                    text = "男修",
                                    fontSize = Theme.fontSize.subtitle,
                                    fontWeight = "bold",
                                    fontColor = Theme.colors.textGold,
                                },
                            },
                        }
                        genderButtons_["男"] = btn
                        return btn
                    end)(),
                    -- 女修
                    (function()
                        local btn = UI.Panel {
                            width = 100, height = 44,
                            borderRadius = Theme.radius.md,
                            backgroundColor = { 45, 38, 30, 200 },
                            borderColor = Theme.colors.borderGold,
                            borderWidth = 1,
                            justifyContent = "center",
                            alignItems = "center",
                            cursor = "pointer",
                            onClick = function(self)
                                SelectGender("女")
                                self:SetStyle({ backgroundColor = Theme.colors.gold, borderColor = Theme.colors.goldDark })
                                local lbl = self:GetChildren()[1]
                                if lbl then lbl:SetStyle({ fontColor = Theme.colors.btnPrimaryText }) end
                            end,
                            children = {
                                UI.Label {
                                    text = "女修",
                                    fontSize = Theme.fontSize.subtitle,
                                    fontWeight = "bold",
                                    fontColor = Theme.colors.textGold,
                                },
                            },
                        }
                        genderButtons_["女"] = btn
                        return btn
                    end)(),
                },
            }
            stepElements_[i] = el
            children[#children + 1] = el

        elseif step.type == "race" then
            -- 种族选择：2×2 网格布局
            local raceButtonList = {}
            for _, raceDef in ipairs(DataRace.RACES) do
                local rid = raceDef.id
                local bonusDescs = DataRace.GetBonusDescs(rid)
                local bonusText = table.concat(bonusDescs, "  ")
                local btn = UI.Panel {
                    width = "48%",
                    paddingTop = 10, paddingBottom = 10,
                    paddingLeft = 8, paddingRight = 8,
                    borderRadius = Theme.radius.md,
                    backgroundColor = { 45, 38, 30, 200 },
                    borderColor = raceDef.color,
                    borderWidth = 1,
                    alignItems = "center",
                    gap = 4,
                    cursor = "pointer",
                    onClick = function(self)
                        SelectRace(rid)
                        self:SetStyle({
                            backgroundColor = { raceDef.color[1], raceDef.color[2], raceDef.color[3], 60 },
                            borderWidth = 2,
                        })
                    end,
                    children = {
                        UI.Label {
                            text = raceDef.name,
                            fontSize = Theme.fontSize.subtitle,
                            fontWeight = "bold",
                            fontColor = raceDef.color,
                        },
                        UI.Label {
                            text = raceDef.position,
                            fontSize = Theme.fontSize.tiny,
                            fontColor = { 180, 170, 150, 200 },
                        },
                        UI.Label {
                            text = bonusText,
                            fontSize = Theme.fontSize.tiny - 1,
                            fontColor = { 160, 200, 140, 220 },
                            textAlign = "center",
                        },
                    },
                }
                raceButtons_[rid] = btn
                raceButtonList[#raceButtonList + 1] = btn
            end
            local el = UI.Panel {
                width = "100%",
                flexDirection = "row",
                flexWrap = "wrap",
                justifyContent = "space-between",
                gap = 8,
                marginTop = 8,
                marginBottom = 6,
                opacity = 0,
                children = raceButtonList,
            }
            stepElements_[i] = el
            children[#children + 1] = el

        elseif step.type == "name" then
            local nameField_ = nil
            local nameTextField = UI.TextField {
                value = daoName_,
                placeholder = "输入道号...",
                maxLength = 12,
                fontSize = Theme.fontSize.body,
                flexGrow = 1,
                onChange = function(self, v)
                    daoName_ = v
                end,
            }
            nameField_ = nameTextField
            local el = UI.Panel {
                width = "100%",
                gap = 8,
                marginTop = 8,
                marginBottom = 6,
                opacity = 0,
                children = {
                    -- 道号输入 + 随机按钮
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        gap = 8,
                        alignItems = "center",
                        children = {
                            nameTextField,
                            UI.Panel {
                                paddingLeft = 12, paddingRight = 12,
                                paddingTop = 6, paddingBottom = 6,
                                borderRadius = Theme.radius.sm,
                                backgroundColor = { 45, 38, 30, 200 },
                                borderColor = Theme.colors.borderGold,
                                borderWidth = 1,
                                cursor = "pointer",
                                onClick = function(self)
                                    daoName_ = RandomDaoName()
                                    if nameField_ then
                                        nameField_:SetValue(daoName_)
                                    end
                                end,
                                children = {
                                    UI.Label {
                                        text = "随机",
                                        fontSize = Theme.fontSize.small,
                                        fontColor = Theme.colors.textGold,
                                    },
                                },
                            },
                        },
                    },
                    -- 确认道号按钮
                    UI.Panel {
                        width = "100%",
                        alignItems = "center",
                        children = {
                            UI.Panel {
                                paddingLeft = 24, paddingRight = 24,
                                paddingTop = 8, paddingBottom = 8,
                                borderRadius = Theme.radius.md,
                                backgroundColor = { 45, 38, 30, 200 },
                                borderColor = Theme.colors.borderGold,
                                borderWidth = 1,
                                cursor = "pointer",
                                onClick = function(self)
                                    ConfirmName()
                                end,
                                children = {
                                    UI.Label {
                                        text = "就叫这个",
                                        fontSize = Theme.fontSize.body,
                                        fontColor = Theme.colors.textGold,
                                    },
                                },
                            },
                        },
                    },
                },
            }
            stepElements_[i] = el
            children[#children + 1] = el

        elseif step.type == "confirm" then
            local el = UI.Panel {
                width = "100%",
                alignItems = "center",
                marginTop = 16,
                opacity = 0,
                children = {
                    UI.Panel {
                        width = "80%",
                        height = 48,
                        borderRadius = Theme.radius.md,
                        backgroundColor = Theme.colors.gold,
                        borderColor = Theme.colors.goldDark,
                        borderWidth = 1,
                        justifyContent = "center",
                        alignItems = "center",
                        cursor = "pointer",
                        onClick = function(self)
                            EnterGame()
                        end,
                        children = {
                            UI.Label {
                                text = "踏 入 仙 途",
                                fontSize = 20,
                                fontWeight = "bold",
                                fontColor = Theme.colors.btnPrimaryText,
                            },
                        },
                    },
                },
            }
            stepElements_[i] = el
            children[#children + 1] = el
        end
    end

    -- 面板容器（半透明深色底 + 金边）
    panelElement_ = UI.Panel {
        position = "absolute",
        left = 24, right = 24,
        top = "25%",
        backgroundColor = { 20, 16, 12, 200 },
        borderRadius = Theme.radius.lg,
        borderColor = { 180, 150, 80, 100 },
        borderWidth = 1,
        padding = { 24, 20 },
        alignItems = "center",
        gap = 2,
        opacity = 0,
        children = children,
    }

    -- 面板淡入
    panelElement_:Animate({
        keyframes = {
            [0] = { opacity = 0, translateY = 30 },
            [1] = { opacity = 1, translateY = 0 },
        },
        duration = 0.8,
        easing = "easeOut",
        fillMode = "forwards",
    })

    return panelElement_
end

return M
