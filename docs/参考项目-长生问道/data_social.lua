-- ============================================================================
-- 《问道长生》社交系统数据常量
-- 好友关系配置、好感度等级、赠送物品、道侣/师徒配置
-- ============================================================================

local M = {}

-- ============================================================================
-- 关系类型配置
-- ============================================================================

M.RELATION_TYPES = {
    { key = "friend",          label = "好友" },
    { key = "master_disciple", label = "师徒" },
    { key = "dao_couple",      label = "道侣" },
}

M.RELATION_CONFIG = {
    friend = {
        label    = "好友",
        color    = { 99, 163, 65, 255 },
        maxCount = 50,
    },
    master_disciple = {
        label        = "师徒",
        color        = { 228, 193, 36, 255 },
        requireFavor = 500,
        requireRealm = 4,       -- 师傅需结丹以上（tier >= 4）
        maxDisciples = 3,
    },
    dao_couple = {
        label        = "道侣",
        color        = { 206, 77, 30, 255 },
        requireFavor = 1000,
        maxCount     = 1,
    },
}

-- ============================================================================
-- 好感度等级
-- ============================================================================

M.FAVOR_LEVELS = {
    { min = 0,    label = "一般", color = { 150, 140, 130, 255 } },
    { min = 100,  label = "良好", color = { 99, 163, 65, 255 } },
    { min = 500,  label = "仰慕", color = { 228, 193, 36, 255 } },
    { min = 1000, label = "挚友", color = { 206, 77, 30, 255 } },
}

--- 获取好感度等级信息
---@param favor number
---@return table { label, color }
function M.GetFavorLevel(favor)
    local result = M.FAVOR_LEVELS[1]
    for _, lv in ipairs(M.FAVOR_LEVELS) do
        if favor >= lv.min then
            result = lv
        end
    end
    return result
end

-- ============================================================================
-- 赠送物品配置
-- ============================================================================

M.FAVOR_GIFTS = {
    { id = "rose",     name = "玫瑰花", favor = 1,  price = 50,  desc = "淡雅花香，聊表心意" },
    { id = "wine",     name = "灵酒",   favor = 5,  price = 200, desc = "仙家佳酿，回味悠长" },
    { id = "incense",  name = "龙涎香", favor = 20, price = 800, desc = "稀世珍品，情谊深厚" },
}

-- 每日赠送次数限制（每个好友独立计数）
M.DAILY_GIFT_LIMIT = 5

-- ============================================================================
-- 道侣系统配置
-- ============================================================================

M.DAO_COUPLE_LEVELS = {
    { level = 1,  reqIntimacy = 250,    cultivateBonus = 0.15 },
    { level = 2,  reqIntimacy = 1000,   cultivateBonus = 0.25 },
    { level = 3,  reqIntimacy = 2250,   cultivateBonus = 0.35 },
    { level = 4,  reqIntimacy = 4000,   cultivateBonus = 0.45 },
    { level = 5,  reqIntimacy = 6250,   cultivateBonus = 0.50 },
    { level = 6,  reqIntimacy = 9000,   cultivateBonus = 0.55 },
    { level = 7,  reqIntimacy = 12250,  cultivateBonus = 0.65 },
    { level = 8,  reqIntimacy = 16000,  cultivateBonus = 0.75 },
    { level = 9,  reqIntimacy = 20250,  cultivateBonus = 0.85 },
    { level = 10, reqIntimacy = 25000,  cultivateBonus = 1.00 },
}

--- 获取当前道侣等级信息
---@param intimacy number
---@return table { level, cultivateBonus, nextReq }
function M.GetCoupleLevel(intimacy)
    local cur = M.DAO_COUPLE_LEVELS[1]
    for _, lv in ipairs(M.DAO_COUPLE_LEVELS) do
        if intimacy >= lv.reqIntimacy then
            cur = lv
        end
    end
    -- 下一级所需亲密度
    local nextLv = M.DAO_COUPLE_LEVELS[cur.level + 1]
    return {
        level = cur.level,
        cultivateBonus = cur.cultivateBonus,
        nextReq = nextLv and nextLv.reqIntimacy or nil,
    }
end

-- 道侣修炼消耗系数（灵石 = 玩家tier * COST_PER_TIER）
M.DAO_COUPLE_COST_PER_TIER = 550

-- 道侣修炼每日次数
M.DAO_COUPLE_DAILY_PRACTICE = 5

-- 道侣修炼亲密度增加概率（35%）和增量（+5）
M.DAO_COUPLE_INTIMACY_CHANCE = 0.35
M.DAO_COUPLE_INTIMACY_GAIN   = 5

-- ============================================================================
-- 师徒系统配置
-- ============================================================================

M.MASTER_DISCIPLE = {
    masterMinRealm = 4,    -- 师傅最低境界（结丹=tier4）
    maxDisciples   = 3,
    teachCooldown  = 3600, -- 传功冷却（秒）
    teachEfficiency = 1.5, -- 传功效率
}

-- ============================================================================
-- 切磋配置
-- ============================================================================

M.CHALLENGE = {
    cooldown     = 120,    -- 同一好友切磋冷却（秒）
    winFavor     = 5,      -- 胜利好感+5
    loseFavor    = 2,      -- 失败好感+2
}

-- ============================================================================
-- 社交操作枚举（客户端→服务端 Action 字段）
-- ============================================================================

M.ACTION = {
    -- 好友
    ADD_FRIEND     = "add_friend",
    ACCEPT_FRIEND  = "accept_friend",
    REJECT_FRIEND  = "reject_friend",
    REJECT_ALL     = "reject_all",
    REMOVE_FRIEND  = "remove_friend",
    SEND_GIFT      = "send_gift",
    GET_FRIENDS    = "get_friends",
    GET_PENDING    = "get_pending",
    -- 道侣
    PROPOSE_COUPLE   = "propose_couple",      -- 申请结为道侣
    COUPLE_PRACTICE  = "couple_practice",     -- 道侣修炼
    COUPLE_LEVELUP   = "couple_levelup",      -- 道侣亲密等级提升
    -- 师徒
    PROPOSE_MASTER   = "propose_master",      -- 申请拜师/收徒
    MASTER_TEACH     = "master_teach",        -- 传功
    -- 切磋
    CHALLENGE        = "challenge",           -- 好友切磋（请求对手数据）
    CHALLENGE_SETTLE = "challenge_settle",    -- 切磋结算
}

-- ============================================================================
-- 服务端回复类型枚举（服务端→客户端 Action 字段）
-- ============================================================================

M.RESP_ACTION = {
    FRIEND_LIST  = "friend_list",    -- 好友列表
    PENDING_LIST = "pending_list",   -- 待处理申请列表
    RESULT       = "result",         -- 操作结果（成功/失败）
}

return M
