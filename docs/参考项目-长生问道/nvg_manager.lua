-- ============================================================================
-- NanoVG 集中渲染管理器
-- 解决多模块共享 NanoVGRender / Update 事件订阅冲突
-- 用法:
--   local NVG = require("nvg_manager")
--   NVG.Register("myKey", renderFn, updateFn)  -- renderFn(ctx), updateFn(dt)
--   NVG.Unregister("myKey")
-- ============================================================================

local M = {}

---@type userdata
local ctx = nil
local renderers = {}   -- { [key] = function(ctx) }
local updaters  = {}   -- { [key] = function(dt)  }
local subscribed = false

-- ---- 内部事件处理 ----

local function HandleNVGRender(eventType, eventData)
    if not ctx then return end
    local dpr = graphics:GetDPR()
    local w = graphics:GetWidth() / dpr
    local h = graphics:GetHeight() / dpr
    nvgBeginFrame(ctx, w, h, dpr)
    -- 快照遍历：回调内部可安全调用 Register/Unregister
    local snapshot = {}
    for _, fn in pairs(renderers) do
        snapshot[#snapshot + 1] = fn
    end
    for _, fn in ipairs(snapshot) do
        fn(ctx)
    end
    nvgEndFrame(ctx)
end

local function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    -- 快照遍历：回调内部可安全调用 Register/Unregister
    local snapshot = {}
    for _, fn in pairs(updaters) do
        snapshot[#snapshot + 1] = fn
    end
    for _, fn in ipairs(snapshot) do
        fn(dt)
    end
end

-- ---- 公开 API ----

--- 初始化管理器（在 Start 中调用一次）
function M.Init()
    if subscribed then return end
    subscribed = true
    ctx = nvgCreate(1)
    SubscribeToEvent("NanoVGRender", HandleNVGRender)
    SubscribeToEvent("Update", HandleUpdate)
end

--- 获取共享的 NanoVG 上下文
---@return userdata
function M.GetContext()
    return ctx
end

--- 注册渲染/更新回调
---@param key string 唯一标识
---@param renderFn function(ctx)  NanoVG 渲染回调（在 BeginFrame/EndFrame 之间调用）
---@param updateFn function(dt)?  帧更新回调（可选）
function M.Register(key, renderFn, updateFn)
    renderers[key] = renderFn
    if updateFn then updaters[key] = updateFn end
end

--- 注销渲染/更新回调
---@param key string
function M.Unregister(key)
    renderers[key] = nil
    updaters[key] = nil
end

--- 关闭管理器
function M.Shutdown()
    if not subscribed then return end
    subscribed = false
    UnsubscribeFromEvent("NanoVGRender")
    UnsubscribeFromEvent("Update")
    renderers = {}
    updaters = {}
end

return M
