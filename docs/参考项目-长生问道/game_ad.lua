-- ============================================================================
-- 《问道长生》广告系统 - 客户端广告管理器
-- 职责：频率控制、场景限制、SDK 调用、奖励回调
-- ============================================================================

---@class SdkGlobal
---@field ShowRewardVideoAd fun(self: SdkGlobal, callback: fun(result: {success: boolean, msg: string}))
---@type SdkGlobal|nil
local sdk = sdk  ---@diagnostic disable-line: undefined-global  -- 运行时注入的全局 SDK 对象

local DataMon = require("data_monetization")
local Toast   = require("ui_toast")

local M = {}

-- ============================================================================
-- 内部状态（客户端本地追踪，不持久化）
-- ============================================================================

local sessionStartTime_ = 0     -- 本次会话开始时间戳
local lastAdTime_       = 0     -- 上次播放广告的时间戳
local hourlyCount_      = 0     -- 本小时已播放次数
local hourlyResetTime_  = 0     -- 上次重置小时计数的时间
local dailyCount_       = 0     -- 今日已播放次数
local dailyResetDate_   = ""    -- 今日日期字符串
local sceneDailyCounts_ = {}    -- 各场景今日已播放次数 { [sceneId] = count }

-- ============================================================================
-- 初始化
-- ============================================================================

--- 初始化广告管理器（在游戏启动时调用）
function M.Init()
    sessionStartTime_ = os.time()
    lastAdTime_       = 0
    hourlyCount_      = 0
    hourlyResetTime_  = os.time()
    dailyCount_       = 0
    dailyResetDate_   = os.date("%Y-%m-%d")
    sceneDailyCounts_ = {}
end

-- ============================================================================
-- 频率控制（内部）
-- ============================================================================

--- 检查并重置每日/每小时计数器
local function RefreshCounters_()
    local now = os.time()
    local today = os.date("%Y-%m-%d")

    -- 跨天重置
    if today ~= dailyResetDate_ then
        dailyCount_       = 0
        dailyResetDate_   = today
        sceneDailyCounts_ = {}
    end

    -- 跨小时重置
    if now - hourlyResetTime_ >= 3600 then
        hourlyCount_     = 0
        hourlyResetTime_ = now
    end
end

--- 检查是否可以播放广告（全局频率）
---@return boolean canShow
---@return string|nil reason 不可播放的原因
local function CheckGlobalFrequency_()
    RefreshCounters_()

    local cfg = DataMon.AD_CONFIG
    local now = os.time()

    -- 会话最短时间检查
    if now - sessionStartTime_ < cfg.minSessionTimeSec then
        local remain = cfg.minSessionTimeSec - (now - sessionStartTime_)
        return false, "请先体验游戏（" .. math.ceil(remain) .. "秒后可用）"
    end

    -- 全局冷却检查
    if lastAdTime_ > 0 and (now - lastAdTime_) < cfg.globalCooldownSec then
        local remain = cfg.globalCooldownSec - (now - lastAdTime_)
        return false, "广告冷却中（" .. math.ceil(remain) .. "秒）"
    end

    -- 每小时上限
    if hourlyCount_ >= cfg.maxPerHour then
        return false, "本小时广告次数已用完"
    end

    -- 每日上限
    if dailyCount_ >= cfg.maxPerDay then
        return false, "今日广告次数已用完"
    end

    return true, nil
end

--- 检查指定场景是否可以播放广告
---@param sceneId string
---@return boolean canShow
---@return string|nil reason
local function CheckSceneLimit_(sceneId)
    local sceneCfg = DataMon.AD_SCENE_MAP[sceneId]
    if not sceneCfg then
        return false, "未知的广告场景"
    end

    RefreshCounters_()

    local used = sceneDailyCounts_[sceneId] or 0
    if used >= sceneCfg.maxDaily then
        return false, sceneCfg.label .. "今日次数已用完（" .. used .. "/" .. sceneCfg.maxDaily .. "）"
    end

    return true, nil
end

-- ============================================================================
-- 公开 API
-- ============================================================================

--- 检查指定场景是否可以看广告
---@param sceneId string 广告场景 ID（如 "signin_double", "cultivate_boost"）
---@return boolean canShow
---@return string|nil reason 不可播放的原因
function M.CanShow(sceneId)
    -- 先检查全局频率
    local globalOk, globalReason = CheckGlobalFrequency_()
    if not globalOk then
        return false, globalReason
    end

    -- 再检查场景限制
    local sceneOk, sceneReason = CheckSceneLimit_(sceneId)
    if not sceneOk then
        return false, sceneReason
    end

    return true, nil
end

--- 获取场景今日剩余次数
---@param sceneId string
---@return number remaining
---@return number maxDaily
function M.GetRemaining(sceneId)
    RefreshCounters_()
    local sceneCfg = DataMon.AD_SCENE_MAP[sceneId]
    if not sceneCfg then
        return 0, 0
    end
    local used = sceneDailyCounts_[sceneId] or 0
    return math.max(0, sceneCfg.maxDaily - used), sceneCfg.maxDaily
end

--- 获取全局今日剩余次数
---@return number remaining
---@return number maxDaily
function M.GetGlobalRemaining()
    RefreshCounters_()
    return math.max(0, DataMon.AD_CONFIG.maxPerDay - dailyCount_), DataMon.AD_CONFIG.maxPerDay
end

--- 获取全局冷却剩余秒数（0 = 已就绪）
---@return number seconds
function M.GetCooldown()
    if lastAdTime_ <= 0 then return 0 end
    local elapsed = os.time() - lastAdTime_
    local remain = DataMon.AD_CONFIG.globalCooldownSec - elapsed
    return math.max(0, remain)
end

--- 播放激励视频广告
--- 这是核心入口，所有广告场景统一通过此函数调用
---@param sceneId string 广告场景 ID
---@param callback fun(success: boolean, sceneId: string) 播放结果回调
function M.ShowAd(sceneId, callback)
    -- 前置检查
    local canShow, reason = M.CanShow(sceneId)
    if not canShow then
        Toast.Show(reason or "暂时无法观看广告")
        if callback then callback(false, sceneId) end
        return
    end

    -- 调用 SDK 播放广告
    if not sdk then
        -- 开发环境：模拟广告成功
        Toast.Show("[开发模式] 模拟广告播放成功")
        M.OnAdCompleted_(sceneId, true)
        if callback then callback(true, sceneId) end
        return
    end

    sdk:ShowRewardVideoAd(function(result)
        local success = result and result.success
        if success then
            M.OnAdCompleted_(sceneId, true)
        else
            Toast.Show("广告播放未完成")
        end
        if callback then callback(success == true, sceneId) end
    end)
end

--- 广告播放完成（内部更新计数器）
---@param sceneId string
---@param success boolean
function M.OnAdCompleted_(sceneId, success)
    if not success then return end

    local now = os.time()
    lastAdTime_  = now
    hourlyCount_ = hourlyCount_ + 1
    dailyCount_  = dailyCount_ + 1

    sceneDailyCounts_[sceneId] = (sceneDailyCounts_[sceneId] or 0) + 1
end

--- 获取场景配置信息
---@param sceneId string
---@return table|nil
function M.GetSceneConfig(sceneId)
    return DataMon.AD_SCENE_MAP[sceneId]
end

--- 获取所有广告场景列表
---@return table[]
function M.GetAllScenes()
    return DataMon.AD_SCENES
end

return M
