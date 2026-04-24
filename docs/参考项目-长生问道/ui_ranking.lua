-- ============================================================================
-- 《问道长生》排行榜页
-- 多榜单切换 + 前三名特殊样式 + 云端排行榜数据
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local Router = require("ui_router")
local GamePlayer = require("game_player")
local GameServer = require("game_server")
local DataRealms = require("data_realms")
---@diagnostic disable-next-line: undefined-global
local cjson      = cjson
local RT         = require("rich_text")

local M = {}

-- 当前选中榜单索引
local selectedTab_ = 1

-- 排行榜配置
local RANK_TABS = {
    {
        category = "境界榜",
        cloudKey = "realm",   -- 对应 game_player.lua 中 REALM_RANK_KEY
        formatScore = function(score)
            -- score = tier*100 + sub*10, 解码为境界名
            local tier = math.floor(score / 100)
            local sub  = math.floor((score % 100) / 10)
            if tier < 1 then tier = 1 end
            if sub < 1 then sub = 1 end
            local name = DataRealms.GetFullName(tier, sub) or ("境界" .. score)
            -- 仙界境界（tier >= 11）使用紫色显示，并加前缀标识
            if tier >= 11 then
                return "<c=purple>[仙]" .. name .. "</c>"
            end
            return "<c=gold>" .. name .. "</c>"
        end,
        valueLabel = "境界",
    },
    {
        category = "战力榜",
        cloudKey = "power",   -- 对应 game_player.lua 中 POWER_RANK_KEY
        formatScore = function(score) return tostring(score) end,
        valueLabel = "战力",
    },
    {
        category = "财富榜",
        cloudKey = "wealth",  -- 对应 game_player.lua 中 WEALTH_RANK_KEY
        formatScore = function(score) return tostring(score) end,
        valueLabel = "财富",
    },
}

-- 缓存云端数据 { [tabIndex] = { entries={...}, loading=bool, error=string|nil } }
local rankCache_ = {}

-- ============================================================================
-- 云端拉取排行榜
-- ============================================================================
local function FetchRankList(tabIndex, callback)
    local tab = RANK_TABS[tabIndex]
    if not tab then return end

    local cache = rankCache_[tabIndex]
    if cache and cache.entries and not cache.loading then
        -- 已有缓存且非加载中，直接回调
        if callback then callback() end
        return
    end

    rankCache_[tabIndex] = { entries = nil, loading = true, error = nil }

    ---@diagnostic disable-next-line: undefined-global
    if clientCloud == nil then
        rankCache_[tabIndex] = { entries = {}, loading = false, error = "云服务未就绪" }
        if callback then callback() end
        return
    end

    local key = GameServer.GetGroupKey(tab.cloudKey)
    print("[Ranking] 拉取排行榜:", tab.category, "key:", key)

    -- 玩家数据在 score 中的 key（如 "s1_player"）
    local playerKey = GameServer.GetServerKey("player")

    ---@diagnostic disable-next-line: undefined-global
    clientCloud:GetRankList(key, 0, 50, {
        ok = function(list)
            print("[Ranking] 收到排行数据, 条目数:", #list)
            local entries = {}
            for i, entry in ipairs(list) do
                -- iscore 是 table: { key=intValue, ... }，提取排行 key 对应的数值
                local numScore = 0
                if type(entry.iscore) == "table" then
                    numScore = entry.iscore[key] or 0
                elseif type(entry.iscore) == "number" then
                    numScore = entry.iscore
                end

                -- 从 score 中提取角色名（entry.score[playerKey] 是玩家数据 table）
                local charName = nil
                local pData = entry.score and entry.score[playerKey]
                if type(pData) == "table" and pData.name then
                    charName = pData.name
                elseif type(pData) == "string" then
                    local ok2, decoded = pcall(cjson.decode, pData)
                    if ok2 and type(decoded) == "table" and decoded.name then
                        charName = decoded.name
                    end
                end

                entries[#entries + 1] = {
                    rank     = entry.rank or i,
                    userId   = entry.userId or entry.player or 0,
                    name     = charName or ("道友" .. tostring(entry.userId or entry.player or i)),
                    score    = numScore,
                    display  = tab.formatScore(numScore),
                }
            end

            rankCache_[tabIndex] = { entries = entries, loading = false, error = nil }
            print("[Ranking]", tab.category, "加载完成,", #entries, "条记录")
            Router.RebuildUI()

            if callback then callback() end
        end,
        error = function(code, reason)
            print("[Ranking]", tab.category, "加载失败:", code, reason)
            rankCache_[tabIndex] = {
                entries = {},
                loading = false,
                error = "加载失败: " .. tostring(reason or code),
            }
            if callback then callback() end
            Router.RebuildUI()
        end,
    }, playerKey)  -- 附加字段: 同时获取每个玩家的角色数据（包含 name）
end

--- 切换 tab 时刷新
local function SwitchTab(idx)
    selectedTab_ = idx
    FetchRankList(idx)
    Router.RebuildUI()
end

--- 强制刷新当前 tab
local function RefreshCurrent()
    rankCache_[selectedTab_] = nil
    FetchRankList(selectedTab_)
end

-- 名次颜色（金银铜）
local rankColors = {
    [1] = { 255, 215, 0, 255 },    -- 金
    [2] = { 192, 192, 192, 255 },  -- 银
    [3] = { 205, 127, 50, 255 },   -- 铜
}

-- ============================================================================
-- 返回行
-- ============================================================================
local function BuildBackRow()
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Panel {
                        paddingHorizontal = 8,
                        paddingVertical = 4,
                        cursor = "pointer",
                        onClick = function(self)
                            selectedTab_ = 1
                            rankCache_ = {}
                            Router.EnterState(Router.STATE_HOME)
                        end,
                        children = {
                            UI.Label {
                                text = "< 返回",
                                fontSize = Theme.fontSize.body,
                                fontColor = Theme.colors.gold,
                            },
                        },
                    },
                    UI.Label {
                        text = "排行榜",
                        fontSize = Theme.fontSize.heading,
                        fontWeight = "bold",
                        fontColor = Theme.colors.textGold,
                    },
                },
            },
            -- 刷新按钮
            UI.Panel {
                paddingHorizontal = 10,
                paddingVertical = 6,
                borderRadius = Theme.radius.sm,
                backgroundColor = { 50, 42, 35, 200 },
                borderColor = Theme.colors.borderGold,
                borderWidth = 1,
                cursor = "pointer",
                onClick = function(self)
                    RefreshCurrent()
                    local Toast = require("ui_toast")
                    Toast.Show("正在刷新排行榜...")
                end,
                children = {
                    UI.Label {
                        text = "刷新",
                        fontSize = Theme.fontSize.small,
                        fontColor = Theme.colors.gold,
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 榜单标签栏
-- ============================================================================
local function BuildRankTabs()
    local tabChildren = {}
    for i, r in ipairs(RANK_TABS) do
        local isActive = (i == selectedTab_)
        tabChildren[#tabChildren + 1] = UI.Panel {
            flexGrow = 1,
            paddingVertical = 8,
            borderRadius = Theme.radius.sm,
            backgroundColor = isActive and Theme.colors.gold or { 50, 42, 35, 200 },
            alignItems = "center",
            cursor = "pointer",
            onClick = function(self)
                SwitchTab(i)
            end,
            children = {
                UI.Label {
                    text = r.category,
                    fontSize = Theme.fontSize.body,
                    fontWeight = isActive and "bold" or "normal",
                    fontColor = isActive and Theme.colors.tabActiveText or Theme.colors.textLight,
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 6,
        children = tabChildren,
    }
end

-- ============================================================================
-- 前三名展示（特殊大卡片）
-- ============================================================================
local function BuildTopThree(entries, tab)
    if #entries < 1 then
        return Comp.BuildCardPanel(nil, {
            UI.Panel {
                width = "100%", paddingVertical = 24,
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "暂无数据",
                        fontSize = Theme.fontSize.body,
                        fontColor = Theme.colors.textSecondary,
                    },
                },
            },
        })
    end

    local topChildren = {}
    -- 显示顺序：第2、第1、第3（第1居中且更大）
    local order = { 2, 1, 3 }
    for _, idx in ipairs(order) do
        local e = entries[idx]
        if not e then goto continue end
        local isFirst = (idx == 1)
        local rankColor = rankColors[idx] or Theme.colors.textLight
        local rankText = tostring(idx)

        topChildren[#topChildren + 1] = UI.Panel {
            flexGrow = 1,
            alignItems = "center",
            gap = 4,
            marginTop = isFirst and 0 or 16,
            children = {
                -- 名次标识
                UI.Panel {
                    width = isFirst and 36 or 28,
                    height = isFirst and 36 or 28,
                    borderRadius = isFirst and 18 or 14,
                    backgroundColor = rankColor,
                    justifyContent = "center",
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = rankText,
                            fontSize = isFirst and Theme.fontSize.subtitle or Theme.fontSize.body,
                            fontWeight = "bold",
                            fontColor = Theme.colors.btnPrimaryText,
                        },
                    },
                },
                -- 名字
                UI.Label {
                    text = e.name,
                    fontSize = isFirst and Theme.fontSize.subtitle or Theme.fontSize.body,
                    fontWeight = "bold",
                    fontColor = rankColor,
                },
                -- 数值
                RT.Build(e.display, Theme.fontSize.small, Theme.colors.textLight),
            },
        }
        ::continue::
    end

    return Comp.BuildCardPanel(nil, {
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-around",
            alignItems = "flex-end",
            paddingVertical = 8,
            children = topChildren,
        },
    })
end

-- ============================================================================
-- 排行列表（第4名起）
-- ============================================================================
local function BuildRankList(entries, tab)
    local rows = {}
    local pp = GamePlayer.Get()
    for i = 4, #entries do
        local e = entries[i]
        local isPlayer = (pp and e.name == pp.name)
        rows[#rows + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            paddingVertical = 8,
            paddingHorizontal = 4,
            backgroundColor = isPlayer and { 200, 168, 85, 30 } or Theme.colors.transparent,
            borderRadius = Theme.radius.sm,
            gap = 8,
            children = {
                -- 名次
                UI.Panel {
                    width = 28,
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = tostring(e.rank),
                            fontSize = Theme.fontSize.body,
                            fontWeight = "bold",
                            fontColor = isPlayer and Theme.colors.gold or Theme.colors.textSecondary,
                        },
                    },
                },
                -- 名字
                UI.Panel {
                    flexGrow = 1,
                    flexShrink = 1,
                    gap = 2,
                    children = {
                        UI.Label {
                            text = e.name,
                            fontSize = Theme.fontSize.body,
                            fontWeight = isPlayer and "bold" or "normal",
                            fontColor = isPlayer and Theme.colors.textGold or Theme.colors.textLight,
                        },
                    },
                },
                -- 数值
                RT.Build(e.display, Theme.fontSize.body, isPlayer and Theme.colors.gold or Theme.colors.textLight),
            },
        }
        -- 分割线（非末尾）
        if i < #entries then
            rows[#rows + 1] = Comp.BuildInkDivider()
        end
    end

    if #rows == 0 then return nil end
    return Comp.BuildCardPanel(nil, rows)
end

-- ============================================================================
-- 加载中 / 错误状态
-- ============================================================================
local function BuildLoadingState(msg)
    return Comp.BuildCardPanel(nil, {
        UI.Panel {
            width = "100%", paddingVertical = 32,
            alignItems = "center",
            children = {
                UI.Label {
                    text = msg or "正在加载...",
                    fontSize = Theme.fontSize.body,
                    fontColor = Theme.colors.textSecondary,
                },
            },
        },
    })
end

-- ============================================================================
-- 构建页面
-- ============================================================================
function M.Build(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    -- 首次进入或切 tab 时自动拉取
    if not rankCache_[selectedTab_] then
        FetchRankList(selectedTab_)
    end

    local cache = rankCache_[selectedTab_] or {}
    local tab = RANK_TABS[selectedTab_]

    local contentChildren = {
        BuildBackRow(),
        BuildRankTabs(),
    }

    if cache.loading then
        contentChildren[#contentChildren + 1] = BuildLoadingState("正在加载排行榜...")
    elseif cache.error then
        contentChildren[#contentChildren + 1] = BuildLoadingState(cache.error)
    else
        local entries = cache.entries or {}
        contentChildren[#contentChildren + 1] = BuildTopThree(entries, tab)
        local list = BuildRankList(entries, tab)
        if list then
            contentChildren[#contentChildren + 1] = list
        end

        -- 我的排名提示
        if #entries == 0 then
            contentChildren[#contentChildren + 1] = Comp.BuildCardPanel(nil, {
                UI.Panel {
                    width = "100%", paddingVertical = 16,
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = "还没有人上榜，成为第一个吧",
                            fontSize = Theme.fontSize.small,
                            fontColor = Theme.colors.textSecondary,
                        },
                    },
                },
            })
        end
    end

    return Comp.BuildPageShell("home", p, contentChildren, Router.HandleNavigate)
end

return M
