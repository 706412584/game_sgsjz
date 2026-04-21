-- ============================================================================
-- ui_guide.lua -- 新手引导系统(交互式)
-- 三种步骤类型:
--   click_tab    = 必须点击高亮Tab按钮推进
--   click_button = 必须点击页面内指定按钮推进(遮罩不阻止目标按钮点击)
--   info         = 点击任意位置继续
-- 引导流程: 制作→炼制→灵田→种植→角色→炼化→摆摊→(提示)→福利→(完成)
-- ============================================================================
local UI = require("urhox-libs/UI")
local Config = require("data_config")
local State = require("data_state")
local GameCore = require("game_core")

local M = {}

-- ========== 引导步骤定义 ==========
local STEPS = {
    -- 1. 制作页
    { targetId = "craft",       action = "click_tab",    text = "欢迎来到修仙世界!\n点击下方「制作」进入炼丹坊。" },
    { targetId = "craft_btn",   action = "click_button", text = "点击「炼制」按钮，\n开始炼制你的第一颗丹药!" },
    -- 2. 灵田页
    { targetId = "field",       action = "click_tab",    text = "接下来点「灵田」，\n种植灵草补充炼丹材料!" },
    { targetId = "plant_btn",   action = "click_button", text = "点击空地上的种子按钮，\n种下灵草!" },
    -- 3. 角色页
    { targetId = "upgrade",     action = "click_tab",    text = "点「角色」查看修炼进度!" },
    { targetId = "refine_btn",  action = "click_button", text = "点击「炼化」按钮，\n将灵石转化为修为!" },
    -- 4. 摆摊页
    { targetId = "stall",       action = "click_tab",    text = "点「摆摊」看看你的摊位!" },
    { targetId = "stall",       action = "info",         text = "丹药炼好后自动上架售卖，\n散修会自动来购买!" },
    -- 5. 福利页
    { targetId = "ad",          action = "click_tab",    text = "最后点「福利」，\n每天记得领取奖励!" },
    { targetId = "ad",          action = "info",         text = "引导完成!\n开始你的修仙摆摊之旅吧!" },
}

-- ========== 状态 ==========
local active_     = false
local step_       = 1
local vg_         = nil
local nvgActive_  = false
local fontReady_  = false
local container_  = nil
local tabButtons_ = nil
local switchTab_  = nil
local onComplete_ = nil

-- 页面内按钮注册表: id -> widget
local guideTargets_ = {}

-- 动画
local animTime_   = 0
local fadeAlpha_  = 0
local positioned_ = false
local guideSwitching_ = false  -- 引导系统内部切Tab标记，绕过锁定检查

-- UI 元素
local overlayPanel_     = nil   -- 全屏遮罩
local npcPanel_         = nil   -- NPC 立绘
local handPanel_        = nil   -- 手势图标
local bubblePanel_      = nil   -- 对话气泡
local highlightPanel_   = nil   -- 高亮框
local targetClickPanel_ = nil   -- 目标按钮上方的可点击面板(click_tab 用)
local bubbleLabel_      = nil   -- 气泡文字
local tipLabel_         = nil   -- 步骤提示

-- Tab ID → 中文名映射
local TAB_NAMES = {
    craft = "制作", stall = "摆摊", field = "灵田",
    upgrade = "角色", ad = "福利", chat = "聊天",
}

local RENDER_ORDER = 999992

-- 前向声明
local currentStep

-- ========== 页面内按钮注册 ==========

--- 注册页面内引导目标按钮
---@param id string 与 STEPS 中 targetId 对应
---@param widget any UI widget
function M.RegisterTarget(id, widget)
    guideTargets_[id] = widget
    -- 如果当前步骤正好等待这个目标，重新定位
    if active_ then
        local stepDef = currentStep()
        if stepDef and stepDef.targetId == id then
            positioned_ = false
        end
    end
end

--- 取消注册
---@param id string
function M.UnregisterTarget(id)
    guideTargets_[id] = nil
end

--- 页面按钮被点击时调用，通知引导推进
---@param actionId string
function M.NotifyAction(actionId)
    if not active_ then return end
    local stepDef = currentStep()
    if stepDef and stepDef.action == "click_button" and stepDef.targetId == actionId then
        M.AdvanceStep()
    end
end

-- ========== 初始化 ==========

function M.Init()
    if vg_ then return end
    vg_ = nvgCreate(1)
    if vg_ then
        nvgSetRenderOrder(vg_, RENDER_ORDER)
        nvgCreateFont(vg_, "sans", "Fonts/MiSans-Regular.ttf")
        fontReady_ = true
    end
end

---@param opts table { container, tabButtons, switchTab }
function M.Setup(opts)
    container_  = opts.container
    tabButtons_ = opts.tabButtons
    switchTab_  = opts.switchTab
end

-- ========== 获取目标按钮布局 ==========

---@param targetId string
---@return table|nil {x, y, w, h}
local function getTargetLayout(targetId)
    -- 1. 先查 Tab 按钮
    if tabButtons_ and tabButtons_[targetId] then
        local btn = tabButtons_[targetId]
        local l = btn:GetAbsoluteLayoutForHitTest()
        if l and l.w > 0 and l.h > 0 then
            return l
        end
    end
    -- 2. 再查注册的页面内按钮
    if guideTargets_[targetId] then
        local widget = guideTargets_[targetId]
        local l = widget:GetAbsoluteLayoutForHitTest()
        if l and l.w > 0 and l.h > 0 then
            return l
        end
    end
    return nil
end

-- ========== 获取当前步骤信息 ==========

---@return table|nil
currentStep = function()
    return STEPS[step_]
end

local function isClickTabStep()
    local s = currentStep()
    return s and s.action == "click_tab"
end

local function isClickButtonStep()
    local s = currentStep()
    return s and s.action == "click_button"
end

-- ========== UI 构建 ==========

--- 更新或创建目标点击面板(click_tab 步骤专用)
local function updateTargetClickPanel(tl)
    if not container_ then return end
    if targetClickPanel_ then
        targetClickPanel_:SetStyle({
            left = tl.x,
            top = tl.y,
            width = tl.w,
            height = tl.h,
            display = "flex",
        })
    else
        targetClickPanel_ = UI.Panel {
            position = "absolute",
            left = tl.x,
            top = tl.y,
            width = tl.w,
            height = tl.h,
            zIndex = 803,
            pointerEvents = "auto",
            backgroundColor = { 0, 0, 0, 1 },
            borderRadius = 4,
            onClick = function(self)
                M.HandleTargetClicked()
            end,
        }
        container_:AddChild(targetClickPanel_)
    end
end

--- 隐藏目标点击面板
local function hideTargetClickPanel()
    if targetClickPanel_ then
        targetClickPanel_:SetStyle({ display = "none" })
    end
end

--- 更新遮罩的点击行为(click_button 步骤时不阻止点击)
local function updateOverlayPointerEvents()
    if not overlayPanel_ then return end
    if isClickButtonStep() then
        -- click_button: 遮罩仅视觉，不阻止底层按钮接收点击
        overlayPanel_:SetStyle({ pointerEvents = "none" })
    else
        -- click_tab / info: 遮罩阻止其他区域点击
        overlayPanel_:SetStyle({ pointerEvents = "auto" })
    end
end

--- 更新高亮框和手势位置
---@return boolean 是否定位成功
local function updateHighlightPosition()
    local stepDef = currentStep()
    if not stepDef then return false end

    local tl = getTargetLayout(stepDef.targetId)
    if not tl then
        positioned_ = false
        return false
    end

    if highlightPanel_ then
        local pad = 4
        highlightPanel_:SetStyle({
            left = tl.x - pad,
            top = tl.y - pad,
            width = tl.w + pad * 2,
            height = tl.h + pad * 2,
            display = "flex",
        })
    end

    if handPanel_ then
        if isClickTabStep() or isClickButtonStep() then
            handPanel_:SetStyle({
                left = tl.x + tl.w / 2 - 14,
                top = tl.y - 36,
                display = "flex",
            })
        else
            handPanel_:SetStyle({ display = "none" })
        end
    end

    -- click_tab: 目标按钮上方放可点击面板
    if isClickTabStep() then
        updateTargetClickPanel(tl)
    else
        hideTargetClickPanel()
    end

    -- 更新遮罩点击行为
    updateOverlayPointerEvents()

    -- 更新气泡文字
    if bubbleLabel_ then
        bubbleLabel_:SetText(stepDef.text)
    end

    -- 更新步骤提示
    if tipLabel_ then
        if isClickTabStep() or isClickButtonStep() then
            tipLabel_:SetText("(" .. step_ .. "/" .. #STEPS .. ")  请点击高亮按钮")
        else
            tipLabel_:SetText("(" .. step_ .. "/" .. #STEPS .. ")  点击任意位置继续")
        end
    end

    positioned_ = true
    return true
end

--- 构建引导 UI 元素
local function buildGuideUI()
    if not container_ then return end

    -- 全屏遮罩
    overlayPanel_ = UI.Panel {
        position = "absolute",
        left = 0, right = 0, top = 0, bottom = 0,
        zIndex = 800,
        pointerEvents = "auto",
        backgroundColor = { 0, 0, 0, 80 },
        onClick = function(self)
            M.HandleOverlayClicked()
        end,
    }
    container_:AddChild(overlayPanel_)

    -- 高亮框
    highlightPanel_ = UI.Panel {
        position = "absolute",
        left = 0, top = 0,
        width = 0, height = 0,
        zIndex = 801,
        pointerEvents = "none",
        borderWidth = 2,
        borderColor = { 200, 170, 80, 220 },
        borderRadius = 6,
        backgroundColor = { 80, 70, 50, 140 },
        display = "none",
    }
    container_:AddChild(highlightPanel_)

    -- NPC 立绘
    npcPanel_ = UI.Panel {
        position = "absolute",
        left = 6, bottom = 38,
        width = 68, height = 110,
        zIndex = 802,
        pointerEvents = "none",
        backgroundImage = "image/guide_master.png",
        backgroundFit = "contain",
    }
    container_:AddChild(npcPanel_)

    -- 手势图标
    handPanel_ = UI.Panel {
        position = "absolute",
        left = 0, top = 0,
        width = 28, height = 28,
        zIndex = 802,
        pointerEvents = "none",
        backgroundImage = "image/guide_hand.png",
        backgroundFit = "contain",
        display = "none",
    }
    container_:AddChild(handPanel_)

    -- 对话气泡
    local stepDef = currentStep() or STEPS[1]

    bubbleLabel_ = UI.Label {
        text = stepDef.text,
        fontSize = 11,
        fontColor = { 230, 220, 190, 240 },
        width = "100%",
        whiteSpace = "normal",
    }

    tipLabel_ = UI.Label {
        text = "(1/" .. #STEPS .. ")  请点击高亮按钮",
        fontSize = 9,
        fontColor = { 180, 170, 140, 180 },
        marginTop = 2,
    }

    bubblePanel_ = UI.Panel {
        position = "absolute",
        left = 82, bottom = 56, right = 12,
        zIndex = 802,
        pointerEvents = "none",
        backgroundColor = { 35, 50, 45, 230 },
        borderWidth = 1,
        borderColor = { 150, 130, 80, 180 },
        borderRadius = 8,
        paddingHorizontal = 8,
        paddingVertical = 6,
        children = { bubbleLabel_, tipLabel_ },
    }
    container_:AddChild(bubblePanel_)
end

--- 销毁引导 UI 元素
local function destroyGuideUI()
    if overlayPanel_ then overlayPanel_:Destroy(); overlayPanel_ = nil end
    if highlightPanel_ then highlightPanel_:Destroy(); highlightPanel_ = nil end
    if npcPanel_ then npcPanel_:Destroy(); npcPanel_ = nil end
    if handPanel_ then handPanel_:Destroy(); handPanel_ = nil end
    if bubblePanel_ then bubblePanel_:Destroy(); bubblePanel_ = nil end
    if targetClickPanel_ then targetClickPanel_:Destroy(); targetClickPanel_ = nil end
    bubbleLabel_ = nil
    tipLabel_ = nil
end

-- ========== NanoVG 渲染(仅高亮脉冲特效) ==========

function HandleGuideOverlayRender(eventType, eventData)
    if not active_ or not vg_ then return end

    local uiScale = UI.GetScale()
    local sw = graphics:GetWidth() / uiScale
    local sh = graphics:GetHeight() / uiScale

    nvgBeginFrame(vg_, sw, sh, uiScale)

    local stepDef = currentStep()
    if stepDef then
        local tl = getTargetLayout(stepDef.targetId)
        if tl then
            local pad = 6
            local pulseA = math.abs(math.sin(animTime_ * 2.5)) * 100
            local alpha = math.min(fadeAlpha_, 1.0)

            nvgBeginPath(vg_)
            nvgRoundedRect(vg_, tl.x - pad, tl.y - pad,
                tl.w + pad * 2, tl.h + pad * 2, 8)
            nvgStrokeColor(vg_, nvgRGBA(230, 200, 100,
                math.floor(pulseA * alpha)))
            nvgStrokeWidth(vg_, 2)
            nvgStroke(vg_)
        end
    end

    nvgEndFrame(vg_)
end

-- ========== 点击处理 ==========

--- 遮罩层被点击
function M.HandleOverlayClicked()
    if not active_ then return end

    if isClickTabStep() then
        -- click_tab: 点击遮罩无效，提示点击高亮Tab
        if bubbleLabel_ then
            local stepDef = currentStep()
            local name = TAB_NAMES[stepDef and stepDef.targetId or ""] or ""
            bubbleLabel_:SetText("请点击下方高亮的「" .. name .. "」按钮哦!")
        end
        return
    end

    -- click_button 步骤遮罩已设为 pointerEvents=none，不会到这里
    -- info 步骤: 点击任意位置推进
    M.AdvanceStep()
end

--- 目标按钮被点击(click_tab 步骤专用)
function M.HandleTargetClicked()
    if not active_ then return end

    local stepDef = currentStep()
    if not stepDef or stepDef.action ~= "click_tab" then return end

    -- 切换到目标 Tab 并推进（标记为引导内部切换，绕过锁定）
    if switchTab_ then
        guideSwitching_ = true
        switchTab_(stepDef.targetId)
        guideSwitching_ = false
    end

    M.AdvanceStep()
end

--- 推进到下一步
function M.AdvanceStep()
    if not active_ then return end

    step_ = step_ + 1
    animTime_ = 0
    fadeAlpha_ = 0

    if step_ > #STEPS then
        M.Complete()
        return
    end

    local stepDef = currentStep()
    if stepDef then
        -- info 步骤自动切换到对应 Tab（标记为引导内部切换，绕过锁定）
        if stepDef.action == "info" and switchTab_ then
            guideSwitching_ = true
            switchTab_(stepDef.targetId)
            guideSwitching_ = false
        end
        -- click_button 步骤自动切换到目标 Tab(按钮所在的页面)
        -- targetId 格式: "refine_btn" 等，需要从步骤上下文推断所属 Tab
        -- 但 click_tab 已经先切好了，click_button 紧跟其后无需再切
    end

    -- 标记需要重新定位
    positioned_ = false
end

--- 检查引导激活时是否允许切换到指定 Tab
--- 供 main.lua 的 switchTab 调用，防止玩家在引导期间乱切 Tab 导致流程错乱
---@param tabId string
---@return boolean
function M.IsAllowedTabSwitch(tabId)
    if not active_ then return true end
    if guideSwitching_ then return true end  -- 引导系统自身切换，始终允许
    -- 引导激活期间，禁止玩家手动切换 Tab
    return false
end

--- 完成引导
function M.Complete()
    active_ = false
    destroyGuideUI()

    if vg_ and nvgActive_ then
        UnsubscribeFromEvent(vg_, "NanoVGRender")
        nvgActive_ = false
    end

    State.state.guideCompleted = true
    print("[Guide] Complete() 设置 guideCompleted=true, serverMode=" .. tostring(State.serverMode))
    if State.serverMode then
        GameCore.SendGameAction("guide_completed")
    end
    State.Save()

    GameCore.AddLog("引导完成!开始你的修仙摆摊之旅!",
        Config.Colors.textGold)

    if onComplete_ then
        onComplete_()
    end
end

-- ========== 公开 API ==========

---@param callback? function 完成回调
function M.Start(callback)
    print("[Guide] Start() called, active=" .. tostring(active_)
        .. ", guideCompleted=" .. tostring(State.state.guideCompleted))
    if active_ then return end
    if State.state.guideCompleted then
        print("[Guide] 引导已完成,跳过")
        return
    end

    M.Init()

    active_ = true
    step_ = 1
    animTime_ = 0
    fadeAlpha_ = 0
    onComplete_ = callback

    -- 第一步是 click_tab，不自动切换，等玩家点击
    local stepDef = currentStep()
    if stepDef and stepDef.action == "info" and switchTab_ then
        switchTab_(stepDef.targetId)
    end

    buildGuideUI()
    positioned_ = false

    if vg_ and not nvgActive_ then
        SubscribeToEvent(vg_, "NanoVGRender", "HandleGuideOverlayRender")
        nvgActive_ = true
    end

    print("[Guide] 新手引导开始, step=" .. step_)
end

---@return boolean
function M.IsActive()
    return active_
end

--- 获取当前步骤期望的 targetId(供外部判断)
---@return string|nil
function M.GetCurrentTargetId()
    if not active_ then return nil end
    local stepDef = currentStep()
    return stepDef and stepDef.targetId or nil
end

---@param dt number
function M.Update(dt)
    if not active_ then return end
    animTime_ = animTime_ + dt
    if fadeAlpha_ < 1.0 then
        fadeAlpha_ = math.min(1.0, fadeAlpha_ + dt * 3.0)
    end

    if not positioned_ then
        updateHighlightPosition()
    end
end

function M.Skip()
    if not active_ then return end
    M.Complete()
end

return M
