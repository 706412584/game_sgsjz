------------------------------------------------------------
-- ui/page_start.lua  —— 三国神将录 开始界面
-- 全屏覆盖层 (zIndex=900)，显示在游戏 UI 之上
-- 包含：背景图 + 游戏标题 + 区服选择插槽 + 进入游戏按钮
------------------------------------------------------------
local UI    = require("urhox-libs/UI")
local Theme = require("ui.theme")
local C     = Theme.colors

local M = {}

---@type table|nil
local startScreen_ = nil
---@type table|nil
local serverSlot_  = nil
---@type fun()|nil
local onEnterCallback_ = nil
---@type table|nil
local enterBtn_ = nil
local enterEnabled_ = false

------------------------------------------------------------
-- 创建开始界面
------------------------------------------------------------

--- 创建开始界面覆盖层
---@param onEnter fun()  点击"进入游戏"后的回调
---@return table panel
function M.Create(onEnter)
    onEnterCallback_ = onEnter
    enterEnabled_ = false

    startScreen_ = UI.Panel {
        id            = "start_screen",
        width         = "100%",
        height        = "100%",
        position      = "absolute",
        top = 0, left = 0,
        zIndex        = 900,
        justifyContent = "center",
        alignItems    = "center",
        overflow      = "hidden",
        backgroundColor = C.bg,
    }

    -- 背景图
    startScreen_:AddChild(UI.Panel {
        backgroundImage = "image/bg_start_20260421150448.png",
        backgroundFit   = "cover",
        width           = "100%",
        height          = "100%",
        position        = "absolute",
        top = 0, left = 0,
    })

    -- 底部渐变遮罩（让下方按钮更清晰）
    startScreen_:AddChild(UI.Panel {
        width    = "100%",
        height   = "50%",
        position = "absolute",
        bottom   = 0,
        left     = 0,
        backgroundGradient = {
            direction = "to-bottom",
            colors = {
                { 0, 0, 0, 0 },
                { C.bg[1], C.bg[2], C.bg[3], 220 },
            },
        },
    })

    -- 顶部轻微遮罩（让标题更醒目）
    startScreen_:AddChild(UI.Panel {
        width    = "100%",
        height   = "20%",
        position = "absolute",
        top      = 0,
        left     = 0,
        backgroundGradient = {
            direction = "to-top",
            colors = {
                { 0, 0, 0, 0 },
                { C.bg[1], C.bg[2], C.bg[3], 100 },
            },
        },
    })

    -- 内容区：上-标题  下-区服+按钮
    local contentPanel = UI.Panel {
        width          = "100%",
        height         = "100%",
        justifyContent = "space-between",
        alignItems     = "center",
    }

    ------ 上部: 标题区域 ------
    contentPanel:AddChild(UI.Panel {
        width      = "100%",
        alignItems = "center",
        paddingTop = 60,
        gap        = 6,
        children = {
            UI.Label {
                text       = "三国神将录",
                fontSize   = 36,
                fontColor  = C.gold,
                fontWeight = "bold",
                textAlign  = "center",
            },
            UI.Label {
                text       = "百将争雄  逐鹿天下",
                fontSize   = 14,
                fontColor  = C.textDim,
                textAlign  = "center",
            },
        },
    })

    ------ 下部: 区服+进入按钮 ------
    serverSlot_ = UI.Panel {
        id             = "start_server_slot",
        alignItems     = "center",
        justifyContent = "center",
        height         = 36,
    }

    -- 区服选择背景面板
    local serverBg = UI.Panel {
        alignItems     = "center",
        justifyContent = "center",
        paddingHorizontal = 16,
        paddingVertical   = 6,
        borderRadius   = 16,
        backgroundColor = { C.bg[1], C.bg[2], C.bg[3], 180 },
        borderColor    = C.border,
        borderWidth    = 1,
        children       = { serverSlot_ },
    }

    enterBtn_ = UI.Button {
        text                   = "进入游戏",
        fontSize               = 16,
        fontWeight             = "bold",
        width                  = 200,
        height                 = 48,
        textColor              = C.text,
        backgroundImage        = "Textures/ui/btn_primary.png",
        backgroundFit          = "sliced",
        backgroundSlice        = { top = 16, right = 16, bottom = 16, left = 16 },
        backgroundColor        = { 0, 0, 0, 0 },
        hoverBackgroundColor   = { 255, 255, 255, 20 },
        pressedBackgroundColor = { 0, 0, 0, 40 },
        borderRadius           = 24,
        opacity                = 0.4,
        disabled               = true,
        transition             = "opacity 0.3s easeOut",
        onClick = function()
            if not enterEnabled_ then return end
            M.Hide()
            if onEnterCallback_ then
                onEnterCallback_()
            end
        end,
    }

    contentPanel:AddChild(UI.Panel {
        width        = "85%",
        maxWidth     = 340,
        alignItems   = "center",
        marginBottom = 60,
        gap          = 16,
        children = {
            serverBg,
            enterBtn_,
            UI.Label {
                text      = "v1.0.0",
                fontSize  = 10,
                fontColor = { C.textDim[1], C.textDim[2], C.textDim[3], 120 },
            },
        },
    })

    startScreen_:AddChild(contentPanel)
    return startScreen_
end

------------------------------------------------------------
-- 公开 API
------------------------------------------------------------

--- 显示开始界面
function M.Show()
    if startScreen_ then
        startScreen_:SetVisible(true)
        YGNodeStyleSetDisplay(startScreen_.node, YGDisplayFlex)
    end
end

--- 隐藏开始界面
function M.Hide()
    if startScreen_ then
        startScreen_:SetVisible(false)
        YGNodeStyleSetDisplay(startScreen_.node, YGDisplayNone)
    end
end

--- 是否可见
---@return boolean
function M.IsVisible()
    return startScreen_ ~= nil and startScreen_:IsVisible()
end

--- 获取区服插槽（供 page_server.lua 嵌入区服选择控件）
---@return table|nil
function M.GetServerSlot()
    return serverSlot_
end

--- 设置进入按钮可用状态
---@param enabled boolean
function M.SetEnterEnabled(enabled)
    enterEnabled_ = enabled
    if enterBtn_ then
        enterBtn_.disabled = not enabled
        enterBtn_:SetStyle({ opacity = enabled and 1 or 0.4 })
    end
end

return M
