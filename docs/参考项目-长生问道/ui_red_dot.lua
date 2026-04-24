-- ============================================================================
-- 《问道长生》红点通知系统
-- 系统化管理 UI 按钮右上角的红点提示，支持显示/隐藏/数字角标
-- ============================================================================

local RedDot = {}

-- 红点状态存储 { [key] = { visible = bool, count = number|nil } }
local dotStates_ = {}

-- 状态变更回调列表 { [key] = { fn1, fn2, ... } }
local listeners_ = {}

-- ============================================================================
-- 核心 API
-- ============================================================================

--- 显示红点
---@param key string 红点标识（如 "home.attr", "bag", "alchemy"）
---@param count? number 可选数字角标（nil 或 0 表示纯红点，>0 显示数字）
function RedDot.Show(key, count)
    dotStates_[key] = { visible = true, count = count or 0 }
    RedDot._notify(key)
end

--- 隐藏红点
---@param key string
function RedDot.Hide(key)
    dotStates_[key] = { visible = false, count = 0 }
    RedDot._notify(key)
end

--- 切换红点
---@param key string
function RedDot.Toggle(key)
    if RedDot.IsVisible(key) then
        RedDot.Hide(key)
    else
        RedDot.Show(key)
    end
end

--- 查询红点是否可见
---@param key string
---@return boolean
function RedDot.IsVisible(key)
    local state = dotStates_[key]
    return state ~= nil and state.visible == true
end

--- 查询红点数字
---@param key string
---@return number
function RedDot.GetCount(key)
    local state = dotStates_[key]
    if state and state.visible then
        return state.count or 0
    end
    return 0
end

--- 批量显示
---@param keys string[]
function RedDot.ShowAll(keys)
    for _, key in ipairs(keys) do
        dotStates_[key] = { visible = true, count = 0 }
    end
    for _, key in ipairs(keys) do
        RedDot._notify(key)
    end
end

--- 批量隐藏
---@param keys string[]
function RedDot.HideAll(keys)
    for _, key in ipairs(keys) do
        dotStates_[key] = { visible = false, count = 0 }
    end
    for _, key in ipairs(keys) do
        RedDot._notify(key)
    end
end

--- 清除所有红点
function RedDot.Clear()
    dotStates_ = {}
end

-- ============================================================================
-- 监听机制（用于触发页面刷新）
-- ============================================================================

--- 注册监听
---@param key string
---@param fn function
function RedDot.Listen(key, fn)
    if not listeners_[key] then
        listeners_[key] = {}
    end
    listeners_[key][#listeners_[key] + 1] = fn
end

--- 通知监听者
function RedDot._notify(key)
    local fns = listeners_[key]
    if fns then
        for _, fn in ipairs(fns) do
            fn(key, dotStates_[key])
        end
    end
end

-- ============================================================================
-- 红点 key 常量（统一管理，避免拼写错误）
-- ============================================================================
RedDot.KEYS = {
    -- 洞府功能按钮
    HOME_ATTR       = "home.attr",       -- 属性
    HOME_SKILL      = "home.skill",      -- 功法
    HOME_ARTIFACT   = "home.artifact",   -- 法宝
    HOME_DAO        = "home.dao",        -- 悟道
    HOME_TRIBULATION = "home.tribulation", -- 渡劫
    HOME_PILL       = "home.pill",       -- 丹药

    -- 底部导航
    NAV_HOME  = "nav.home",
    NAV_BAG   = "nav.bag",
    NAV_MAP   = "nav.map",
    NAV_PET   = "nav.pet",
    NAV_MORE  = "nav.more",

    -- 更多页面入口
    MORE_ALCHEMY  = "more.alchemy",
    MORE_SECT     = "more.sect",
    MORE_EXPLORE  = "more.explore",
    MORE_CHAT     = "more.chat",
    MORE_MARKET   = "more.market",
    MORE_RANKING  = "more.ranking",
    MORE_TRIAL    = "more.trial",
    MORE_QUEST    = "more.quest",
}

return RedDot
