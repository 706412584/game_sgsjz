-- ============================================================================
-- ui_start.lua — 开始界面
-- 全屏背景图 + 游戏标题 + 进入游戏按钮
-- ============================================================================
local UI = require("urhox-libs/UI")
local Config = require("data_config")

local M = {}

---@type table|nil
local startScreen_ = nil
---@type table|nil
local serverSlot_ = nil
---@type fun()|nil
local onEnterCallback_ = nil

--- 创建开始界面(覆盖层)
---@param onEnter fun() 点击进入游戏后的回调
---@return table panel
function M.Create(onEnter)
    onEnterCallback_ = onEnter

    startScreen_ = UI.Panel {
        id = "start_screen",
        width = "100%",
        height = "100%",
        position = "absolute",
        top = 0,
        left = 0,
        zIndex = 900,
        justifyContent = "center",
        alignItems = "center",
        overflow = "hidden",
        backgroundColor = { 18, 22, 20, 255 },
    }

    -- 背景图(高清 1350x2400, 9:16)
    local screenW = graphics:GetWidth()
    local screenH = graphics:GetHeight()
    local screenRatio = screenW / screenH
    local imageRatio = 9 / 16
    local ratioDiff = math.abs(screenRatio - imageRatio)
    local bgFit = ratioDiff < 0.02 and "contain" or "cover"

    startScreen_:AddChild(UI.Panel {
        backgroundImage = "image/仙山云海背景_20260412110254.png",
        backgroundFit = bgFit,
        width = "100%",
        height = "100%",
        position = "absolute",
        top = 0,
        left = 0,
    })

    -- 底部渐变遮罩(水墨深色过渡，与背景画风融合)
    startScreen_:AddChild(UI.Panel {
        width = "100%",
        height = "55%",
        position = "absolute",
        bottom = 0,
        left = 0,
        backgroundGradient = {
            direction = "to-bottom",
            colors = {
                { 0, 0, 0, 0 },
                { 20, 25, 22, 200 },
            },
        },
    })

    -- 顶部轻微遮罩(让标题文字更清晰)
    startScreen_:AddChild(UI.Panel {
        width = "100%",
        height = "25%",
        position = "absolute",
        top = 0,
        left = 0,
        backgroundGradient = {
            direction = "to-top",
            colors = {
                { 0, 0, 0, 0 },
                { 20, 25, 22, 80 },
            },
        },
    })

    -- 内容区: 三段式布局(上:标题 中:留白 下:按钮)
    local contentPanel = UI.Panel {
        width = "100%",
        height = "100%",
        justifyContent = "space-between",
        alignItems = "center",
    }

    -- 上部: 标题区域
    local topSection = UI.Panel {
        width = "100%",
        alignItems = "center",
        paddingTop = 50,
        gap = 10,
        children = {
            -- 标题图片(放大)
            UI.Panel {
                backgroundImage = "image/game_title.png",
                backgroundFit = "contain",
                width = 360,
                height = 120,
            },

        },
    }
    contentPanel:AddChild(topSection)

    -- 下部: 统一底部区域(半透明面板包裹区服选择 + 进入按钮)
    serverSlot_ = UI.Panel {
        id = "start_server_slot",
        alignItems = "center",
        justifyContent = "center",
    }

    -- 区服选择背景面板(紧凑包裹，居中)
    local serverBg = UI.Panel {
        alignItems = "center",
        justifyContent = "center",
        paddingLeft = 12,
        paddingRight = 12,
        paddingTop = 6,
        paddingBottom = 6,
        borderRadius = 0,
        backgroundColor = { 25, 30, 28, 150 },
        children = {
            serverSlot_,
        },
    }

    local bottomSection = UI.Panel {
        width = "85%",
        maxWidth = 300,
        alignItems = "center",
        marginBottom = 50,
        gap = 16,
        children = {
            -- 区服选择区(带背景)
            serverBg,
            -- 进入游戏按钮(无背景面板，独立放置)
            UI.Button {
                text = "进入游戏",
                fontSize = 14,
                fontWeight = "bold",
                width = 160,
                height = 38,
                backgroundColor = { 60, 80, 65, 220 },
                textColor = { 230, 215, 170, 255 },
                borderRadius = 20,
                borderWidth = 1.5,
                borderColor = { 190, 170, 110, 180 },
                shadowColor = { 0, 0, 0, 60 },
                shadowOffset = { 0, 2 },
                onClick = function(self)
                    M.Hide()
                    if onEnterCallback_ then
                        onEnterCallback_()
                    end
                end,
            },
        },
    }
    contentPanel:AddChild(bottomSection)

    startScreen_:AddChild(contentPanel)

    return startScreen_
end

--- 显示开始界面
function M.Show()
    if startScreen_ then
        startScreen_:Show()
    end
end

--- 隐藏开始界面
function M.Hide()
    if startScreen_ then
        startScreen_:Hide()
    end
end

--- 是否可见
---@return boolean
function M.IsVisible()
    return startScreen_ ~= nil and startScreen_:IsVisible()
end

--- 获取区服插槽面板(供 ui_server.lua 嵌入区服选择)
---@return table|nil
function M.GetServerSlot()
    return serverSlot_
end

return M
