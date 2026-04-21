-- ============================================================================
-- ui_daily.lua — 每日任务面板（弹窗式）
-- ============================================================================
local UI = require("urhox-libs/UI")
local Config = require("data_config")
local State = require("data_state")
local GameCore = require("game_core")

local M = {}

-- 挂载容器(由 main.lua 注入)
local container_ = nil

local overlayPanel = nil
local listContainer = nil

--- 创建单个任务行
---@param task table { type, desc, target, current, claimed, reward }
---@param idx number
local function createTaskRow(task, idx)
    local current = task.current or 0
    local target = task.target or 1
    local prog = math.min(1.0, current / target)
    local done = current >= target
    local claimed = task.claimed

    -- 奖励文本
    local rewardParts = {}
    local REWARD_NAMES = { lingshi = "灵石", xiuwei = "修为", lingcao = "灵草", lingzhi = "灵纸", xuantie = "玄铁" }
    if task.reward then
        for key, amt in pairs(task.reward) do
            if REWARD_NAMES[key] then
                table.insert(rewardParts, REWARD_NAMES[key] .. "+" .. amt)
            elseif key == "materials" then
                for matId, matAmt in pairs(amt) do
                    local mat = Config.GetMaterialById(matId)
                    table.insert(rewardParts, (mat and mat.name or matId) .. "+" .. matAmt)
                end
            end
        end
    end
    local rewardText = #rewardParts > 0 and table.concat(rewardParts, " ") or ""

    -- 状态颜色
    local bgColor = claimed and { 30, 40, 30, 200 }
        or (done and { 50, 45, 25, 230 } or Config.Colors.panelLight)
    local borderClr = claimed and { 60, 100, 60, 180 }
        or (done and Config.Colors.borderGold or Config.Colors.border)

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        padding = 6,
        backgroundColor = bgColor,
        borderRadius = 6,
        borderWidth = 1,
        borderColor = borderClr,
        children = {
            -- 左侧：任务信息
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                gap = 2,
                children = {
                    UI.Label {
                        text = task.desc or "",
                        fontSize = 10,
                        fontColor = claimed and Config.Colors.textSecond or Config.Colors.textPrimary,
                    },
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 4,
                        children = {
                            UI.ProgressBar {
                                value = prog,
                                flexGrow = 1,
                                height = 5,
                                variant = done and "success" or "primary",
                            },
                            UI.Label {
                                text = math.floor(current) .. "/" .. target,
                                fontSize = 8,
                                fontColor = done and Config.Colors.textGreen or Config.Colors.textSecond,
                            },
                        },
                    },
                    UI.Label {
                        text = rewardText,
                        fontSize = 8,
                        fontColor = Config.Colors.textGold,
                    },
                },
            },
            -- 右侧：状态/按钮
            claimed and UI.Label {
                text = "已领取",
                fontSize = 9,
                fontColor = Config.Colors.textSecond,
                paddingHorizontal = 8,
            } or (done and UI.Button {
                text = "领取",
                variant = "primary",
                fontSize = 9,
                paddingHorizontal = 10,
                paddingVertical = 4,
                onClick = function()
                    GameCore.ClaimDailyTask(idx)
                end,
            } or UI.Label {
                text = "进行中",
                fontSize = 9,
                fontColor = Config.Colors.textSecond,
                paddingHorizontal = 8,
            }),
        },
    }
end

--- 打开每日任务面板
function M.Open()
    if overlayPanel then
        overlayPanel:SetVisible(true)
        YGNodeStyleSetDisplay(overlayPanel.node, YGDisplayFlex)
        M.Refresh()
        return
    end

    overlayPanel = UI.Panel {
        id = "daily_overlay",
        position = "absolute",
        width = "100%",
        height = "100%",
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center",
        alignItems = "center",
        zIndex = 90,
        onClick = function() M.Close() end,
        children = {
            UI.Panel {
                width = "90%",
                maxWidth = 340,
                maxHeight = "80%",
                backgroundColor = Config.Colors.panel,
                borderRadius = 10,
                borderWidth = 1,
                borderColor = Config.Colors.borderGold,
                padding = 10,
                gap = 6,
                onClick = function() end, -- 阻止冒泡关闭
                children = {
                    -- 标题栏
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = "每日任务",
                                fontSize = 14,
                                fontColor = Config.Colors.textGold,
                                fontWeight = "bold",
                            },
                            UI.Button {
                                text = "X",
                                variant = "ghost",
                                fontSize = 12,
                                paddingHorizontal = 6,
                                paddingVertical = 2,
                                onClick = function() M.Close() end,
                            },
                        },
                    },
                    -- 累计已领取
                    UI.Label {
                        id = "daily_claimed_count",
                        text = "",
                        fontSize = 9,
                        fontColor = Config.Colors.textSecond,
                    },
                    -- 任务列表（可滚动）
                    UI.Panel {
                        id = "daily_task_list",
                        width = "100%",
                        flexGrow = 1,
                        flexShrink = 1,
                        overflow = "scroll",
                        gap = 4,
                    },
                },
            },
        },
    }
    listContainer = overlayPanel:FindById("daily_task_list")

    -- 挂载到 UI 树
    if container_ then
        container_:AddChild(overlayPanel)
    end

    M.Refresh()
end

--- 刷新任务列表
function M.Refresh()
    if not overlayPanel then return end
    if not listContainer then return end
    listContainer:ClearChildren()

    local tasks = State.state.dailyTasks or {}
    if #tasks == 0 then
        listContainer:AddChild(UI.Label {
            text = "暂无每日任务",
            fontSize = 10,
            fontColor = Config.Colors.textSecond,
            textAlign = "center",
            paddingVertical = 12,
        })
    else
        for i, task in ipairs(tasks) do
            listContainer:AddChild(createTaskRow(task, i))
        end
    end

    -- 累计领取数
    local claimedLbl = overlayPanel:FindById("daily_claimed_count")
    if claimedLbl then
        local total = State.state.dailyTasksClaimed or 0
        claimedLbl:SetText("累计已完成: " .. total .. " 个任务")
    end
end

--- 关闭面板
function M.Close()
    if overlayPanel then
        overlayPanel:SetVisible(false)
        YGNodeStyleSetDisplay(overlayPanel.node, YGDisplayNone)
    end
end

--- 是否打开
function M.IsOpen()
    return overlayPanel ~= nil and overlayPanel:IsVisible()
end

--- 设置挂载容器（由 main.lua 在 buildUI 后调用）
---@param container table UI 根节点
function M.SetContainer(container)
    container_ = container
end

--- 获取 overlay（用于挂载）
function M.GetOverlay()
    return overlayPanel
end

--- 检查是否有可领取任务（用于红点显示）
function M.HasClaimable()
    local tasks = State.state.dailyTasks or {}
    for _, task in ipairs(tasks) do
        if not task.claimed and (task.current or 0) >= (task.target or 1) then
            return true
        end
    end
    return false
end

return M
