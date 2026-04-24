-- ============================================================================
-- 《问道长生》路由状态机
-- ============================================================================

local UI = require("urhox-libs/UI")

local Router = {}

-- Toast 覆盖层注入（由 main.lua 设置）
local toastOverlayProvider_ = nil

-- 全局弹窗层（由 ShowOverlayDialog 设置，覆盖在所有内容之上）
local overlayDialog_ = nil

-- 页面状态常量
Router.STATE_TITLE       = 1
Router.STATE_CREATE_ROLE = 2
Router.STATE_MENU        = 3
Router.STATE_HOME        = 4
Router.STATE_EXPLORE     = 5
Router.STATE_ALCHEMY     = 6
Router.STATE_BAG         = 7
Router.STATE_SECT        = 8
Router.STATE_WORLD_MAP   = 9
Router.STATE_CHAT        = 10
Router.STATE_PET         = 11
Router.STATE_MORE        = 12
Router.STATE_ATTR        = 13  -- 属性
Router.STATE_SKILL       = 14  -- 功法
Router.STATE_ARTIFACT    = 15  -- 法宝
Router.STATE_DAO         = 16  -- 悟道
Router.STATE_TRIBULATION = 17  -- 渡劫
Router.STATE_PILL        = 18  -- 丹药
Router.STATE_MARKET      = 19  -- 坊市
Router.STATE_RANKING     = 20  -- 排行榜
Router.STATE_TRIAL       = 21  -- 试炼
Router.STATE_QUEST       = 22  -- 任务
Router.STATE_STORY       = 23  -- 开场故事
Router.STATE_MAIL        = 24  -- 仙信（邮件）
Router.STATE_SOCIAL      = 25  -- 社交（好友/师徒/道侣）
Router.STATE_STATS       = 26  -- 战斗统计
Router.STATE_BOSS        = 27  -- 组队Boss
Router.STATE_SIGNIN      = 28  -- 每日签到
Router.STATE_GIFT        = 29  -- 礼包商城
Router.STATE_RECHARGE    = 30  -- 仙石充值
Router.STATE_MONTHCARD   = 31  -- 月卡
Router.STATE_VIP         = 32  -- VIP
Router.STATE_GACHA       = 33  -- 抽奖
Router.STATE_BATTLEPASS  = 34  -- 通行证

-- 底部导航 key -> 状态映射
Router.NAV_MAP = {
    home    = Router.STATE_HOME,
    bag     = Router.STATE_BAG,
    map     = Router.STATE_WORLD_MAP,
    sect    = Router.STATE_SECT,
    social  = Router.STATE_SOCIAL,
    more    = Router.STATE_MORE,
    -- 以下保留供内部跳转使用（不在底部导航显示）
    alchemy = Router.STATE_ALCHEMY,
    explore = Router.STATE_EXPLORE,
    chat    = Router.STATE_CHAT,
}

-- 状态 -> 底部导航 key 的反向映射
Router.STATE_TO_TAB = {
    [Router.STATE_HOME]      = "home",
    [Router.STATE_BAG]       = "bag",
    [Router.STATE_WORLD_MAP] = "map",
    [Router.STATE_PET]       = "home",
    [Router.STATE_MORE]      = "more",
    -- 角色页悬浮按钮 / 功能栏子页面高亮"角色"
    [Router.STATE_ALCHEMY]     = "home",
    [Router.STATE_EXPLORE]     = "home",
    [Router.STATE_TRIAL]       = "home",
    [Router.STATE_QUEST]       = "home",
    [Router.STATE_SIGNIN]      = "home",
    [Router.STATE_MONTHCARD]   = "home",
    [Router.STATE_GIFT]        = "home",
    [Router.STATE_MARKET]      = "home",
    [Router.STATE_MAIL]        = "home",
    [Router.STATE_RECHARGE]    = "home",
    -- 角色页横向栏子页面
    [Router.STATE_ATTR]        = "home",
    [Router.STATE_SKILL]       = "home",
    [Router.STATE_ARTIFACT]    = "home",
    [Router.STATE_DAO]         = "home",
    [Router.STATE_TRIBULATION] = "home",
    [Router.STATE_PILL]        = "home",
    -- 宗门
    [Router.STATE_SECT]        = "sect",
    -- 聊天
    [Router.STATE_CHAT]        = "home",
    [Router.STATE_STATS]       = "home",
    -- 社交
    [Router.STATE_SOCIAL]      = "social",
    -- 更多子页面高亮"更多"
    [Router.STATE_RANKING]     = "home",
    [Router.STATE_BOSS]        = "map",
    [Router.STATE_VIP]         = "home",
    [Router.STATE_GACHA]       = "home",
    [Router.STATE_BATTLEPASS]  = "home",
}

-- 内部状态
local currentState_ = Router.STATE_TITLE
local statePayload_ = nil

-- 页面构建函数注册表
local builders_ = {}

-- 页面退出回调注册表（用于清理粒子等资源）
local exitCallbacks_ = {}

-- ============================================================================
-- 注册页面构建函数
-- state: 状态常量
-- builder: function(payload) -> UI.Panel
-- ============================================================================
function Router.Register(state, builder)
    builders_[state] = builder
end

-- ============================================================================
-- 注册页面退出回调（用于清理粒子等资源）
-- state: 状态常量
-- callback: function()
-- ============================================================================
function Router.RegisterExit(state, callback)
    exitCallbacks_[state] = callback
end

-- ============================================================================
-- 切换状态
-- state: 状态常量
-- payload: 可选传参
-- ============================================================================
function Router.EnterState(state, payload)
    -- 触发旧页面的退出回调
    if currentState_ ~= state and exitCallbacks_[currentState_] then
        exitCallbacks_[currentState_]()
    end
    currentState_ = state
    statePayload_ = payload
    Router.RebuildUI()
end

-- ============================================================================
-- 获取当前状态
-- ============================================================================
function Router.GetCurrentState()
    return currentState_
end

-- ============================================================================
-- 获取当前页面对应的底部导航 tab key
-- ============================================================================
function Router.GetActiveTab()
    return Router.STATE_TO_TAB[currentState_] or ""
end

-- ============================================================================
-- 底部导航回调（供 Comp.BuildBottomNav 使用）
-- ============================================================================
function Router.HandleNavigate(tabKey)
    local targetState = Router.NAV_MAP[tabKey]
    if targetState and targetState ~= currentState_ then
        Router.EnterState(targetState)
    end
end

-- ============================================================================
-- 设置全局覆盖层提供器（用于 Toast 等全局组件）
-- provider: function() -> UI.Panel 或 nil
-- ============================================================================
function Router.SetOverlayProvider(provider)
    toastOverlayProvider_ = provider
end

-- ============================================================================
-- 显示全局弹窗（覆盖在所有内容之上，不可被页面切换清除）
-- dialog: UI.Panel（通常由 Comp.Dialog 生成）
-- ============================================================================
function Router.ShowOverlayDialog(dialog)
    overlayDialog_ = dialog
    Router.RebuildUI()
end

-- ============================================================================
-- 隐藏全局弹窗
-- ============================================================================
function Router.HideOverlayDialog()
    overlayDialog_ = nil
    Router.RebuildUI()
end

-- ============================================================================
-- 重建 UI
-- ============================================================================
function Router.RebuildUI()
    local builder = builders_[currentState_]
    local pageRoot
    if builder then
        pageRoot = builder(statePayload_)
    else
        -- fallback: 未注册的页面显示占位
        pageRoot = UI.Panel {
            width = "100%",
            height = "100%",
            justifyContent = "center",
            alignItems = "center",
            backgroundColor = { 35, 30, 25, 255 },
            children = {
                UI.Label {
                    text = "页面开发中...(状态: " .. tostring(currentState_) .. ")",
                    fontSize = 18,
                    fontColor = { 200, 168, 85, 255 },
                },
            },
        }
    end

    -- 注入全局覆盖层（Toast 容器为 absolute 定位，不影响页面布局）
    local overlay = toastOverlayProvider_ and toastOverlayProvider_()
    local wrapperChildren = { pageRoot }
    if overlay then
        wrapperChildren[#wrapperChildren + 1] = overlay
    end
    -- 注入全局弹窗层（最顶层，覆盖 Toast 和 Loading）
    if overlayDialog_ then
        wrapperChildren[#wrapperChildren + 1] = overlayDialog_
    end
    local wrapper = UI.Panel {
        width = "100%", height = "100%",
        children = wrapperChildren,
    }
    UI.SetRoot(wrapper, true)
end

return Router
