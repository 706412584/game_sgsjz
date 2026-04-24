------------------------------------------------------------
-- ui/modal_manager.lua  —— 三国神将录 纯自定义栈式弹窗管理器
-- 完全基于 UI.Panel 叠加层，不使用 UI.Modal
-- 提供 Show / Close / CloseAll / Confirm / Alert / BattleResult
------------------------------------------------------------
local UI    = require("urhox-libs/UI")
local Theme = require("ui.theme")
local C     = Theme.colors
local S     = Theme.sizes

local M = {}

--- 弹窗栈 (LIFO)
local modalStack_ = {}

--- 全局覆盖层容器（由 Init 注入）
local overlayRoot_ = nil

------------------------------------------------------------
-- 初始化：调用方须传入一个全屏 Panel 作为弹窗层容器
------------------------------------------------------------
function M.Init(overlayPanel)
    overlayRoot_ = overlayPanel
end

------------------------------------------------------------
-- 内部：创建一个自定义按钮（使用生成纹理）
------------------------------------------------------------
local function makeBtn(text, variant, onClick)
    variant = variant or "primary"
    local bgImg, txtColor
    if variant == "primary" then
        bgImg    = "Textures/ui/btn_primary.png"
        txtColor = C.text
    elseif variant == "danger" then
        bgImg    = "Textures/ui/btn_primary.png"
        txtColor = C.text
    else
        bgImg    = "Textures/ui/btn_secondary.png"
        txtColor = C.text
    end

    return UI.Button {
        text                   = text or "确定",
        height                 = S.btnHeight,
        flexGrow               = 1,
        fontSize               = S.btnFontSize,
        fontWeight             = "bold",
        textColor              = txtColor,
        backgroundImage        = bgImg,
        backgroundFit          = "sliced",
        backgroundSlice        = { top = 16, right = 16, bottom = 16, left = 16 },
        backgroundColor        = { 0, 0, 0, 0 },
        hoverBackgroundColor   = { 255, 255, 255, 20 },
        pressedBackgroundColor = { 0, 0, 0, 40 },
        borderRadius           = S.btnRadius,
        transition             = "all 0.15s easeOut",
        onClick                = onClick,
    }
end

------------------------------------------------------------
-- 内部：创建通用弹窗面板
------------------------------------------------------------
local function createModalPanel(config)
    config = config or {}
    local width = config.width or S.modalMaxWidth

    -- 构建内容区
    local contentWidget
    if type(config.content) == "function" then
        contentWidget = config.content()
    elseif config.content then
        contentWidget = config.content
    else
        contentWidget = UI.Panel { height = 20 }
    end

    -- 按钮行
    local btnChildren = {}
    if config.buttons then
        for _, cfg in ipairs(config.buttons) do
            btnChildren[#btnChildren + 1] = makeBtn(cfg.text, cfg.variant, function(self)
                if cfg.noAutoClose then
                    if cfg.onClick then cfg.onClick() end
                    return
                end
                -- 先关闭当前弹窗，再执行回调
                -- 避免回调中弹出的新弹窗被 auto-close 误关
                M.Close()
                if cfg.onClick then cfg.onClick() end
            end)
        end
    end

    local btnRow = #btnChildren > 0 and UI.Panel {
        flexDirection = "row",
        gap           = 12,
        marginTop     = 16,
        width         = "100%",
        children      = btnChildren,
    } or nil

    -- 标题区
    local titleWidget = nil
    if config.title and config.title ~= "" then
        titleWidget = UI.Panel {
            width         = "100%",
            marginBottom  = 8,
            children = {
                UI.Label {
                    text      = config.title,
                    fontSize  = S.modalTitleSize,
                    fontColor = C.gold,
                    fontWeight = "bold",
                    textAlign = "center",
                    width     = "100%",
                },
                UI.Divider {
                    color   = C.divider,
                    spacing = 8,
                },
            },
        }
    end

    -- 关闭按钮（右上角 X）
    local closeBtn = UI.Button {
        text               = "✕",
        width              = 32,
        height             = 32,
        fontSize           = 16,
        textColor          = C.textDim,
        backgroundColor    = { 0, 0, 0, 0 },
        hoverBackgroundColor = { 255, 255, 255, 30 },
        borderRadius       = 16,
        position           = "absolute",
        top                = 6,
        right              = 6,
        onClick            = function()
            M.Close()
        end,
    }

    -- 对话框主面板（纯样式边框，不用贴图）
    -- onClick 拦截事件冒泡，防止点击对话框内部时触发 overlay 的关闭
    local dialogPanel = UI.Panel {
        width           = width,
        maxHeight       = "85%",
        backgroundColor = { 20, 30, 55, 240 },
        borderRadius    = S.modalRadius,
        borderColor     = C.gold,
        borderWidth     = 2,
        padding         = S.modalPadding,
        flexDirection   = "column",
        opacity         = 0,
        scale           = 0.9,
        transition      = "opacity 0.2s easeOut, scale 0.2s easeOutBack",
        onClick         = function(self) end,  -- 拦截冒泡，防止触发overlay关闭
        children        = {
            titleWidget,
            contentWidget,
            btnRow,
            closeBtn,
        },
    }

    -- 遮罩层
    local entry = {}

    local overlayPanel = UI.Panel {
        position        = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        width           = "100%",
        height          = "100%",
        backgroundColor = C.overlay,
        justifyContent  = "center",
        alignItems      = "center",
        opacity         = 0,
        transition      = "opacity 0.2s easeOut",
        onClick         = function(self)
            if config.closeOnOverlay ~= false then
                M.Close()
            end
        end,
        children = {
            dialogPanel,
        },
    }

    entry.overlay = overlayPanel
    entry.dialog  = dialogPanel
    entry.config  = config

    return entry
end

------------------------------------------------------------
-- 公开 API
------------------------------------------------------------

--- 显示自定义弹窗
---@param config table { title, width, closeOnOverlay, content, buttons, onClose }
function M.Show(config)
    if not overlayRoot_ then
        print("[ModalManager] overlayRoot not initialized!")
        return
    end

    local entry = createModalPanel(config)
    modalStack_[#modalStack_ + 1] = entry

    -- 显示弹窗层容器
    overlayRoot_:SetVisible(true)
    YGNodeStyleSetDisplay(overlayRoot_.node, YGDisplayFlex)

    overlayRoot_:AddChild(entry.overlay)

    -- 延迟一帧触发入场动画
    entry.overlay:SetStyle({ opacity = 1 })
    entry.dialog:SetStyle({ opacity = 1, scale = 1.0 })

    return entry
end

--- 关闭栈顶弹窗
function M.Close()
    if #modalStack_ == 0 then return end
    local entry = modalStack_[#modalStack_]
    table.remove(modalStack_, #modalStack_)

    -- 出场动画
    entry.overlay:SetStyle({ opacity = 0 })
    entry.dialog:SetStyle({ opacity = 0, scale = 0.9 })

    -- 回调
    if entry.config and entry.config.onClose then
        entry.config.onClose()
    end

    -- 弹窗全部关闭时隐藏容器
    if #modalStack_ == 0 then
        overlayRoot_:SetVisible(false)
        YGNodeStyleSetDisplay(overlayRoot_.node, YGDisplayNone)
    end

    -- 延迟移除（等动画播完）
    local removeTimer = 0
    local removeDone = false
    SubscribeToEvent("Update", function(_, ed)
        if removeDone then return end
        removeTimer = removeTimer + ed["TimeStep"]:GetFloat()
        if removeTimer > 0.3 then
            removeDone = true
            if entry.overlay then
                overlayRoot_:RemoveChild(entry.overlay)
            end
        end
    end)
end

--- 关闭所有弹窗
function M.CloseAll()
    for i = #modalStack_, 1, -1 do
        local entry = modalStack_[i]
        if entry.overlay then
            overlayRoot_:RemoveChild(entry.overlay)
        end
    end
    modalStack_ = {}
    -- 隐藏容器，避免拦截点击
    if overlayRoot_ then
        overlayRoot_:SetVisible(false)
        YGNodeStyleSetDisplay(overlayRoot_.node, YGDisplayNone)
    end
end

--- 确认弹窗
function M.Confirm(title, msg, onConfirm, onCancel)
    return M.Show({
        title = title,
        width = 360,
        content = function()
            return UI.Label {
                text        = msg,
                fontSize    = Theme.fontSize.body,
                fontColor   = C.text,
                whiteSpace  = "normal",
                width       = "100%",
                padding     = { 0, 4, 8, 4 },
            }
        end,
        buttons = {
            { text = "取消", variant = "secondary", onClick = onCancel },
            { text = "确认", variant = "primary",   onClick = onConfirm },
        },
    })
end

--- 提示弹窗
function M.Alert(title, msg, onOk)
    return M.Show({
        title = title,
        width = 340,
        content = function()
            return UI.Label {
                text        = msg,
                fontSize    = Theme.fontSize.body,
                fontColor   = C.text,
                whiteSpace  = "normal",
                width       = "100%",
                padding     = { 0, 4, 8, 4 },
            }
        end,
        buttons = {
            { text = "确定", variant = "primary", onClick = onOk },
        },
    })
end

--- 战斗结算弹窗
function M.BattleResult(result, onContinue)
    result = result or {}
    local isWin = result.win
    local stars = result.stars or 0
    local drops = result.drops or {}

    return M.Show({
        title = isWin and "战斗胜利" or "战斗失败",
        width = 400,
        closeOnOverlay = false,
        content = function()
            local children = {}

            if isWin then
                children[#children + 1] = UI.Label {
                    text      = Theme.StarsText(stars),
                    fontSize  = 28,
                    fontColor = C.gold,
                    textAlign = "center",
                    width     = "100%",
                    marginBottom = 12,
                }
            else
                children[#children + 1] = UI.Label {
                    text      = "部队全军覆没...",
                    fontSize  = Theme.fontSize.subtitle,
                    fontColor = C.red,
                    textAlign = "center",
                    width     = "100%",
                    marginBottom = 12,
                }
            end

            if isWin and next(drops) then
                children[#children + 1] = UI.Divider {
                    color   = C.divider,
                    spacing = 8,
                }
                children[#children + 1] = UI.Label {
                    text      = "获得奖励",
                    fontSize  = Theme.fontSize.bodySmall,
                    fontColor = C.textDim,
                    marginBottom = 4,
                }
                local rewardText = ""
                for k, v in pairs(drops) do
                    if rewardText ~= "" then rewardText = rewardText .. "  " end
                    rewardText = rewardText .. k .. " ×" .. Theme.FormatNumber(v)
                end
                children[#children + 1] = UI.Label {
                    text      = rewardText,
                    fontSize  = Theme.fontSize.body,
                    fontColor = C.gold,
                    textAlign = "center",
                    width     = "100%",
                    whiteSpace = "normal",
                }
            end

            return UI.Panel {
                width     = "100%",
                padding   = { 8, 4, 4, 4 },
                children  = children,
            }
        end,
        buttons = {
            { text = isWin and "继续" or "返回", variant = "primary", onClick = onContinue },
        },
    })
end

--- 当前弹窗栈深度
function M.GetStackSize()
    return #modalStack_
end

--- 是否有弹窗打开
function M.IsAnyOpen()
    return #modalStack_ > 0
end

return M
