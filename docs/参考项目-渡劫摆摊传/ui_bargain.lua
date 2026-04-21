-- ============================================================================
-- ui_bargain.lua — 讨价还价小游戏弹窗(多轮版)
-- 进度条区域命中判定，动画指针来回移动，点击停止
-- 支持最多3次讨价机会，顾客拒绝/接受机制
-- ============================================================================
local UI = require("urhox-libs/UI")
local Config = require("data_config")
local State = require("data_state")
local GameCore = require("game_core")

local M = {}

-- 挂载容器(由 main.lua 注入)
local container_ = nil

-- 自动讨价
local autoBargainEnabled_ = false
local autoBargainTimer_ = 0
local AUTO_BARGAIN_INTERVAL = 0.6  -- 每次自动讨价间隔(秒)
local AUTO_BARGAIN_CHANCE = 0.08   -- 每个顾客8%概率触发讨价
local skipBargainSet_ = {}          -- 已决策为"跳过"的顾客ID集合

-- 运行时状态
local overlayPanel = nil
local barPanel = nil
local indicatorPanel = nil
local resultPanel = nil
local btnArea = nil
local currentCustId = nil
local currentAttempt = 0  -- 当前第几次尝试
local maxAttempts = 3
local barPos = 0        -- 0~1 当前指针位置
local barDir = 1        -- 1=右 -1=左
local barSpeed = 0      -- 每秒移动量
local isRunning = false
local showResult = false
local resultTimer = 0
local RESULT_SHOW_TIME = 2.0
local waitingServer = false  -- 等待服务端返回中
local lastResultData = nil   -- 最近一次结果数据(用于多轮)

--- 获取区域颜色
local function getZoneColor(zoneId)
    if zoneId == "perfect" then return { 255, 215, 0, 255 }
    elseif zoneId == "good" or zoneId == "good2" then return { 100, 200, 100, 255 }
    elseif zoneId == "normal" or zoneId == "normal2" then return { 80, 120, 180, 255 }
    else return { 180, 60, 60, 255 }
    end
end

--- 创建进度条区域可视化(带标签)
local function createBarZones()
    local zones = Config.BargainConfig.zones
    local children = {}
    for _, zone in ipairs(zones) do
        local widthPct = math.floor(zone.size * 100 + 0.5) .. "%"
        local zoneChildren = {}
        -- 使用 zone.label 显示(如 "-15%", "原价", "+20%", "+50%")
        if zone.label and zone.size >= 0.10 then
            table.insert(zoneChildren, UI.Label {
                text = zone.label,
                fontSize = 7,
                fontColor = { 255, 255, 255, 220 },
            })
        end
        table.insert(children, UI.Panel {
            width = widthPct,
            height = "100%",
            backgroundColor = getZoneColor(zone.id),
            alignItems = "center",
            justifyContent = "center",
            overflow = "hidden",
            children = zoneChildren,
        })
    end
    return children
end

--- 根据当前尝试次数计算指针速度
local function calcBarSpeed()
    local base = 1.0 / Config.BargainConfig.barSpeed
    local speedUp = Config.BargainConfig.speedUpPerAttempt or 1.3
    -- 第1次正常速度，第2次x1.3，第3次x1.69
    return base * (speedUp ^ (currentAttempt - 1))
end

--- 重建按钮区域
local function rebuildBtnArea(mode, data)
    if not btnArea then return end
    btnArea:ClearChildren()

    if mode == "hit" then
        -- 出手按钮
        btnArea:AddChild(UI.Button {
            id = "bargain_hit_btn",
            text = "出手!",
            variant = "primary",
            width = 120,
            onClick = function()
                if isRunning then
                    M.DoHit()
                end
            end,
        })
    elseif mode == "waiting" then
        btnArea:AddChild(UI.Label {
            text = "等待结果...",
            fontSize = 11,
            fontColor = Config.Colors.textSecond,
        })
    elseif mode == "result_mid" then
        -- 非最终结果: 显示"接受"和"再试"按钮
        local remainAttempts = maxAttempts - (data and data.attempt or currentAttempt)
        btnArea:SetStyle({ flexDirection = "row", gap = 12 })
        btnArea:AddChild(UI.Button {
            text = "接受",
            variant = "primary",
            width = 80,
            onClick = function()
                -- 接受当前结果
                GameCore.BargainAccept(currentCustId)
                M.Close()
            end,
        })
        btnArea:AddChild(UI.Button {
            text = "再试(" .. remainAttempts .. "次)",
            width = 100,
            backgroundColor = Config.Colors.panelLight,
            borderWidth = 1,
            borderColor = Config.Colors.borderGold,
            fontColor = Config.Colors.textGold,
            onClick = function()
                -- 重新开始指针
                M.StartNextAttempt()
            end,
        })
    elseif mode == "result_final" then
        -- 最终结果(含拒绝): 只显示确定
        btnArea:SetStyle({ flexDirection = "row", gap = 12 })
        btnArea:AddChild(UI.Button {
            text = "确定",
            variant = "primary",
            width = 120,
            onClick = function()
                M.Close()
            end,
        })
    end
end

--- 打开讨价还价面板
---@param custId number 顾客服务端ID
function M.Open(custId)
    currentCustId = custId
    currentAttempt = 0
    maxAttempts = Config.BargainConfig.maxAttempts or 3
    lastResultData = nil
    waitingServer = false

    if overlayPanel then
        overlayPanel:SetVisible(true)
        YGNodeStyleSetDisplay(overlayPanel.node, YGDisplayFlex)
        M.StartNextAttempt()
        return
    end

    overlayPanel = UI.Panel {
        id = "bargain_overlay",
        position = "absolute",
        width = "100%",
        height = "100%",
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center",
        alignItems = "center",
        zIndex = 100,
        children = {
            UI.Panel {
                width = "85%",
                maxWidth = 320,
                backgroundColor = Config.Colors.panel,
                borderRadius = 10,
                borderWidth = 1,
                borderColor = Config.Colors.borderGold,
                padding = 12,
                gap = 8,
                alignItems = "center",
                children = {
                    -- 标题行
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        width = "100%",
                        children = {
                            UI.Label {
                                text = "讨价还价",
                                fontSize = 14,
                                fontColor = Config.Colors.textGold,
                                fontWeight = "bold",
                            },
                            UI.Label {
                                id = "bargain_attempt_label",
                                text = "",
                                fontSize = 10,
                                fontColor = Config.Colors.textSecond,
                            },
                        },
                    },
                    UI.Label {
                        text = "点击出手停下指针! 命中金色区域获得最高加成",
                        fontSize = 9,
                        fontColor = Config.Colors.textSecond,
                        textAlign = "center",
                    },
                    -- 进度条容器
                    UI.Panel {
                        width = "100%",
                        height = 28,
                        borderRadius = 4,
                        overflow = "hidden",
                        backgroundColor = { 30, 30, 40, 255 },
                        children = {
                            -- 区域色块
                            UI.Panel {
                                id = "bargain_bar",
                                position = "absolute",
                                width = "100%",
                                height = "100%",
                                flexDirection = "row",
                                children = createBarZones(),
                            },
                            -- 指针
                            UI.Panel {
                                id = "bargain_indicator",
                                position = "absolute",
                                width = 3,
                                height = "100%",
                                backgroundColor = { 255, 255, 255, 255 },
                                left = 0,
                            },
                        },
                    },
                    -- 结果显示
                    UI.Panel {
                        id = "bargain_result",
                        minHeight = 24,
                        alignItems = "center",
                        justifyContent = "center",
                        children = {},
                    },
                    -- 按钮区域
                    UI.Panel {
                        id = "bargain_btn_area",
                        alignItems = "center",
                        justifyContent = "center",
                        children = {},
                    },
                },
            },
        },
    }
    barPanel = overlayPanel:FindById("bargain_bar")
    indicatorPanel = overlayPanel:FindById("bargain_indicator")
    resultPanel = overlayPanel:FindById("bargain_result")
    btnArea = overlayPanel:FindById("bargain_btn_area")

    -- 挂载到 UI 树
    if container_ then
        container_:AddChild(overlayPanel)
    end

    M.StartNextAttempt()
end

--- 开始下一轮讨价(指针重新跑)
function M.StartNextAttempt()
    currentAttempt = currentAttempt + 1
    barPos = 0
    barDir = 1
    barSpeed = calcBarSpeed()
    isRunning = true
    showResult = false
    waitingServer = false
    resultTimer = 0

    -- 更新次数标签
    local attemptLabel = overlayPanel and overlayPanel:FindById("bargain_attempt_label")
    if attemptLabel then
        attemptLabel:SetText("第" .. currentAttempt .. "/" .. maxAttempts .. "次")
    end

    -- 清空结果面板
    if resultPanel then resultPanel:ClearChildren() end

    -- 设置按钮为出手模式
    rebuildBtnArea("hit")
end

--- 执行命中
function M.DoHit()
    if not isRunning then return end
    isRunning = false
    waitingServer = true
    -- 发送到服务端验证
    GameCore.Bargain(currentCustId, barPos)
    -- 显示等待
    rebuildBtnArea("waiting")
end

--- 显示结果（从 bargain_done 事件调用）
---@param data table { zone, mul, win, refused, isFinal, attempt, maxAttempts }
function M.ShowResult(data)
    waitingServer = false
    showResult = true
    lastResultData = data

    -- 更新服务端返回的次数
    if data.attempt then currentAttempt = data.attempt end
    if data.maxAttempts then maxAttempts = data.maxAttempts end

    -- 更新次数标签
    local attemptLabel = overlayPanel and overlayPanel:FindById("bargain_attempt_label")
    if attemptLabel then
        attemptLabel:SetText("第" .. currentAttempt .. "/" .. maxAttempts .. "次")
    end

    if resultPanel then
        resultPanel:ClearChildren()

        if data.refused then
            -- 顾客拒绝
            resultPanel:AddChild(UI.Label {
                text = "顾客不满意,生气离开了!",
                fontSize = 13,
                fontColor = Config.Colors.red,
                fontWeight = "bold",
            })
            rebuildBtnArea("result_final")
            resultTimer = RESULT_SHOW_TIME
        elseif data.isFinal then
            -- 最终结果(第3次或完美命中)
            local mulPct = math.floor((data.mul or 1.0) * 100)
            local win = data.win
            local text = win and ("讨价成功! 售价 x" .. mulPct .. "%") or ("售价 x" .. mulPct .. "%")
            resultPanel:AddChild(UI.Label {
                text = text,
                fontSize = 13,
                fontColor = win and Config.Colors.textGold or Config.Colors.textSecond,
                fontWeight = "bold",
            })
            rebuildBtnArea("result_final")
            resultTimer = RESULT_SHOW_TIME
        else
            -- 非最终: 可以选择接受或再试
            local mulPct = math.floor((data.mul or 1.0) * 100)
            local win = data.win
            local zoneLabel = data.zone or ""
            -- 找到对应 zone 的 label
            for _, z in ipairs(Config.BargainConfig.zones) do
                if z.id == data.zone then
                    zoneLabel = z.label or zoneLabel
                    break
                end
            end
            resultPanel:AddChild(UI.Label {
                text = "命中: " .. zoneLabel .. " (售价x" .. mulPct .. "%)",
                fontSize = 12,
                fontColor = win and Config.Colors.textGold or Config.Colors.textSecond,
                fontWeight = "bold",
            })
            resultPanel:AddChild(UI.Label {
                text = "接受此结果，还是再试一次?",
                fontSize = 9,
                fontColor = Config.Colors.textSecond,
                marginTop = 2,
            })
            rebuildBtnArea("result_mid", data)
        end
    end
end

--- 关闭面板
function M.Close()
    isRunning = false
    showResult = false
    waitingServer = false
    currentCustId = nil
    lastResultData = nil
    if overlayPanel then
        overlayPanel:SetVisible(false)
        YGNodeStyleSetDisplay(overlayPanel.node, YGDisplayNone)
    end
end

--- 是否打开中
function M.IsOpen()
    return overlayPanel ~= nil and (isRunning or waitingServer or showResult)
end

--- 刷新进度条位置
function M.RefreshBar()
    if not indicatorPanel or not barPanel then return end
    local pct = math.floor(barPos * 100 + 0.5)
    indicatorPanel:SetStyle({ left = pct .. "%" })
end

--- 每帧更新（在 Update 中调用）
---@param dt number
function M.Update(dt)
    if isRunning then
        -- 指针来回移动
        barPos = barPos + barDir * barSpeed * dt
        if barPos >= 1.0 then
            barPos = 1.0
            barDir = -1
        elseif barPos <= 0 then
            barPos = 0
            barDir = 1
        end
        M.RefreshBar()
        return
    end

    if showResult then
        -- 仅对 final 结果自动关闭
        if lastResultData and (lastResultData.isFinal or lastResultData.refused) then
            resultTimer = resultTimer - dt
            if resultTimer <= 0 then
                M.Close()
            end
        end
        return
    end

    -- 自动讨价逻辑(不在小游戏运行时才执行)
    if autoBargainEnabled_ and not waitingServer then
        autoBargainTimer_ = autoBargainTimer_ + dt
        if autoBargainTimer_ >= AUTO_BARGAIN_INTERVAL then
            autoBargainTimer_ = 0
            for _, cust in ipairs(GameCore.customers) do
                if cust.state == "buying" and cust.canBargain and not cust.bargainDone then
                    local cid = cust.serverId
                    if not skipBargainSet_[cid] then
                        if math.random() > AUTO_BARGAIN_CHANCE then
                            skipBargainSet_[cid] = true
                        else
                            -- 自动讨价: 直接发送一次，服务端决定结果
                            -- 自动模式只讨一次并自动接受
                            cust.bargainDone = true  -- 防止重复
                            GameCore.Bargain(cid, math.random())
                            break
                        end
                    end
                end
            end
        end
    end
end

--- 切换自动讨价
---@return boolean 切换后的状态
function M.ToggleAutoBargain()
    autoBargainEnabled_ = not autoBargainEnabled_
    autoBargainTimer_ = 0
    skipBargainSet_ = {}
    return autoBargainEnabled_
end

--- 是否开启自动讨价
---@return boolean
function M.IsAutoBargainEnabled()
    return autoBargainEnabled_
end

--- 设置挂载容器（由 main.lua 在 buildUI 后调用）
---@param container table UI 根节点
function M.SetContainer(container)
    container_ = container
end

--- 获取 overlay panel（用于挂载到 UI 树）
function M.GetOverlay()
    return overlayPanel
end

return M
