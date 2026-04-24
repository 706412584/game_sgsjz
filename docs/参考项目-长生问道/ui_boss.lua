-- ============================================================================
-- 《问道长生》组队 Boss 页面
-- 三阶段视图：大厅（创建/加入）→ 房间（组队等待）→ 战斗（回合动画+结算）
-- ============================================================================

local UI       = require("urhox-libs/UI")
local Theme    = require("ui_theme")
local Comp     = require("ui_components")
local Router   = require("ui_router")
local Toast    = require("ui_toast")
local GamePlayer = require("game_player")
local GameBoss   = require("game_boss")
local DataWorld  = require("data_world")
local RT         = require("rich_text")

local M = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

local view_ = "lobby"   -- "lobby" | "room" | "battle" | "result"
local selectedArea_ = nil
local errorMsg_ = nil

-- 防止无限重建和重复注册
local registered_ = false
local lobbyRequested_ = false
local leaving_ = false  -- 防止离开按钮重复点击

-- ============================================================================
-- 回调注册/注销
-- ============================================================================

local function RegisterCallbacks()
    if registered_ then return end
    registered_ = true

    GameBoss.On("team_update", function(team)
        view_ = "room"
        errorMsg_ = nil
        Router.RebuildUI()
    end)
    GameBoss.On("battle_start", function(team, boss)
        view_ = "battle"
        errorMsg_ = nil
        Router.RebuildUI()
    end)
    GameBoss.On("battle_round", function(roundData)
        Router.RebuildUI()
    end)
    GameBoss.On("battle_end", function(result)
        view_ = "result"
        Router.RebuildUI()
    end)
    GameBoss.On("settle_ready", function(info)
        Router.RebuildUI()
    end)
    GameBoss.On("settle_done", function(ok, data)
        Router.RebuildUI()
    end)
    GameBoss.On("room_list", function(rooms)
        Router.RebuildUI()
    end)
    GameBoss.On("error", function(msg)
        Toast.Show(msg, { variant = "error" })
    end)
    GameBoss.On("kicked", function(msg)
        view_ = "lobby"
        lobbyRequested_ = false
        leaving_ = false
        Toast.Show(msg, { variant = "error" })
        Router.RebuildUI()
    end)
    GameBoss.On("disbanded", function(msg)
        view_ = "lobby"
        lobbyRequested_ = false
        leaving_ = false
        Router.RebuildUI()
    end)
end

local function UnregisterCallbacks()
    GameBoss.OffAll()
    registered_ = false
    lobbyRequested_ = false
end

-- ============================================================================
-- 大厅视图：区域选择 + 创建房间 + 房间列表
-- ============================================================================

local function BuildLobby(p)
    local areas = DataWorld.AREAS
    local tier = p and p.tier or 1
    local sub  = p and p.sub or 1

    -- 区域选择列表（只显示有 Boss 的已解锁区域）
    local areaCards = {}
    for _, a in ipairs(areas) do
        local enc = DataWorld.GetAreaEncounters(a.id)
        if enc and enc.boss then
            local unlocked = DataWorld.IsAreaUnlocked(a.id, tier, sub)
            local isSelected = (selectedArea_ == a.id)
            local bgColor = isSelected and { 60, 50, 35, 220 }
                or (unlocked and Theme.colors.bgDark or { 40, 35, 30, 100 })
            local borderClr = isSelected and Theme.colors.gold or Theme.colors.border
            local borderW = isSelected and 2 or 1

            local areaId = a.id
            local bossName = enc.boss.name
            local bossHpMul = enc.boss.hpMul or 10

            areaCards[#areaCards + 1] = UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "space-between",
                paddingVertical = 8,
                paddingHorizontal = 10,
                marginBottom = 4,
                borderRadius = Theme.radius.sm,
                backgroundColor = bgColor,
                borderColor = borderClr,
                borderWidth = borderW,
                opacity = unlocked and 1 or 0.5,
                onClick = unlocked and function(self)
                    selectedArea_ = areaId
                    Router.RebuildUI()
                end or nil,
                children = {
                    UI.Panel {
                        flexShrink = 1,
                        children = {
                            UI.Label {
                                text = a.name,
                                fontSize = Theme.fontSize.body,
                                fontColor = unlocked and Theme.colors.text or Theme.colors.textLight,
                            },
                            UI.Label {
                                text = bossName .. (not unlocked and " (未解锁)" or ""),
                                fontSize = Theme.fontSize.small - 1,
                                fontColor = isSelected and Theme.colors.gold or Theme.colors.textLight,
                                marginTop = 1,
                            },
                        },
                    },
                    isSelected and UI.Label {
                        text = "[已选]",
                        fontSize = Theme.fontSize.small,
                        fontColor = Theme.colors.gold,
                    } or nil,
                },
            }
        end
    end

    -- 创建房间按钮
    local createBtn = Comp.BuildInkButton("创建房间", function()
        if not selectedArea_ then
            Toast.Show("请先选择一个区域", { variant = "error" })
            return
        end
        GameBoss.Create(selectedArea_)
    end, { width = "100%" })

    -- 分隔线
    local divider = UI.Panel {
        width = "100%", height = 1,
        backgroundColor = Theme.colors.border,
        marginVertical = Theme.spacing.md,
    }

    -- 刷新房间列表按钮
    local refreshBtn = Comp.BuildSecondaryButton("刷新房间列表", function()
        GameBoss.ListRooms()
    end, { width = "100%" })

    -- 房间列表
    local roomListItems = {}
    local roomList = GameBoss.GetRoomList()
    if #roomList > 0 then
        for _, r in ipairs(roomList) do
            local areaInfo = DataWorld.GetArea(r.areaId)
            local areaName = areaInfo and areaInfo.name or r.areaId
            local roomId = r.roomId
            roomListItems[#roomListItems + 1] = UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                paddingVertical = 8,
                paddingHorizontal = 10,
                marginBottom = 4,
                borderRadius = Theme.radius.sm,
                backgroundColor = Theme.colors.bgDark,
                borderColor = Theme.colors.border,
                borderWidth = 1,
                children = {
                    UI.Panel {
                        flexShrink = 1,
                        children = {
                            UI.Label {
                                text = areaName .. " - " .. (r.bossName or "Boss"),
                                fontSize = Theme.fontSize.body,
                                fontColor = Theme.colors.text,
                            },
                            UI.Label {
                                text = "房主: " .. (r.ownerName or "?") .. "  " .. r.memberCount .. "/" .. r.maxPlayers .. "人",
                                fontSize = Theme.fontSize.small - 1,
                                fontColor = Theme.colors.textLight,
                                marginTop = 1,
                            },
                        },
                    },
                    Comp.BuildInkButton("加入", function()
                        GameBoss.Join(roomId)
                    end, { width = 64, fontSize = Theme.fontSize.small }),
                },
            }
        end
    else
        roomListItems[#roomListItems + 1] = UI.Label {
            text = "暂无房间，创建一个试试",
            fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.textLight,
            textAlign = "center",
            width = "100%",
            marginTop = Theme.spacing.sm,
        }
    end

    return {
        Comp.BuildTextButton("< 返回地图", function()
            Router.EnterState(Router.STATE_WORLD_MAP)
        end),
        Comp.BuildSectionTitle("选择区域"),
        UI.Panel {
            width = "100%",
            maxHeight = 200,
            overflow = "scroll",
            children = areaCards,
        },
        -- 创建按钮
        UI.Panel { width = "100%", marginTop = Theme.spacing.sm, children = { createBtn } },
        divider,
        Comp.BuildSectionTitle("房间列表"),
        UI.Panel { width = "100%", marginBottom = Theme.spacing.xs, children = { refreshBtn } },
        UI.Panel { width = "100%", children = roomListItems },
    }
end

-- ============================================================================
-- 房间视图：成员列表 + 准备/开始
-- ============================================================================

local function BuildRoom(p)
    local team = GameBoss.GetTeam()
    if not team then
        return { UI.Label { text = "房间数据加载中...", fontSize = Theme.fontSize.body, fontColor = Theme.colors.textLight } }
    end

    local areaInfo = DataWorld.GetArea(team.areaId)
    local areaName = areaInfo and areaInfo.name or team.areaId
    local enc = DataWorld.GetAreaEncounters(team.areaId)
    local bossName = (enc and enc.boss) and enc.boss.name or "Boss"
    local isOwner = GameBoss.IsOwner()
    local myUid = require("network.client_net").GetUserId()
    local localName = p and p.name or nil

    -- 成员列表
    local memberRows = {}
    local allReady = true
    local memberCount = 0
    if team.members then
        for _, m in ipairs(team.members) do
            memberCount = memberCount + 1
            local isMe = (m.userId == myUid)
            if not m.ready and not m.isOwner then
                allReady = false
            end

            -- 显示名字：自己用本地存档名，其他人用服务端数据
            local displayName = isMe and (localName or m.name) or m.name

            local statusText = m.isOwner and "房主" or (m.ready and "已准备" or "未准备")
            local statusColor = m.isOwner and Theme.colors.gold
                or (m.ready and { 100, 200, 100, 255 } or { 180, 140, 100, 180 })

            -- 右侧区域
            local rightChildren = {
                UI.Panel {
                    paddingHorizontal = 6,
                    paddingVertical = 2,
                    borderRadius = 4,
                    backgroundColor = m.isOwner and { 80, 65, 30, 180 }
                        or (m.ready and { 30, 60, 30, 180 } or { 60, 50, 40, 120 }),
                    children = {
                        UI.Label {
                            text = statusText,
                            fontSize = Theme.fontSize.small - 1,
                            fontColor = statusColor,
                        },
                    },
                },
            }
            if isOwner and not isMe then
                rightChildren[#rightChildren + 1] = Comp.BuildTextButton("踢出", function()
                    GameBoss.Kick(m.userId)
                end, { fontSize = Theme.fontSize.small - 1, fontColor = { 200, 90, 90, 255 } })
            end

            memberRows[#memberRows + 1] = UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                paddingVertical = 8,
                paddingHorizontal = 10,
                marginBottom = 4,
                borderRadius = Theme.radius.sm,
                backgroundColor = isMe and { 55, 45, 30, 220 } or Theme.colors.bgDark,
                borderColor = isMe and Theme.colors.gold or Theme.colors.border,
                borderWidth = isMe and 2 or 1,
                children = {
                    UI.Label {
                        text = displayName .. (isMe and " (我)" or ""),
                        fontSize = Theme.fontSize.body,
                        fontColor = isMe and Theme.colors.gold or Theme.colors.text,
                        flexShrink = 1,
                    },
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 6,
                        children = rightChildren,
                    },
                },
            }
        end
    end

    -- 底部操作栏
    local actions = {}
    local cfg = DataWorld.GetGroupBossConfig()
    local minPlayers = cfg and cfg.minPlayers or 2

    if isOwner then
        local canStart = memberCount >= minPlayers and allReady
        actions[#actions + 1] = Comp.BuildInkButton(
            canStart and "开始战斗" or ("需" .. minPlayers .. "人开战"),
            function()
                if memberCount < minPlayers then
                    Toast.Show("至少需要 " .. minPlayers .. " 人才能开战", { variant = "error" })
                    return
                end
                if not allReady then
                    Toast.Show("还有队员未准备", { variant = "error" })
                    return
                end
                GameBoss.Start()
            end,
            { width = "48%", disabled = not canStart }
        )
    else
        actions[#actions + 1] = Comp.BuildInkButton("准备", function()
            GameBoss.Ready()
        end, { width = "48%" })
    end
    actions[#actions + 1] = Comp.BuildSecondaryButton(leaving_ and "离开中..." or "离开房间", function()
        if leaving_ then return end
        leaving_ = true
        Toast.Show("正在离开房间...", { variant = "info" })
        GameBoss.Leave()
        Router.RebuildUI()  -- 刷新按钮为禁用态
    end, { width = "48%", disabled = leaving_ })

    return {
        -- 房间标题卡片
        UI.Panel {
            width = "100%",
            padding = Theme.spacing.md,
            borderRadius = Theme.radius.md,
            backgroundColor = { 50, 40, 28, 200 },
            borderColor = Theme.colors.borderGold,
            borderWidth = 1,
            marginBottom = Theme.spacing.md,
            children = {
                UI.Label {
                    text = areaName .. " - " .. bossName,
                    fontSize = Theme.fontSize.subtitle,
                    fontColor = Theme.colors.gold,
                    textAlign = "center",
                },
                UI.Label {
                    text = "等待组队 (" .. memberCount .. "/" .. (team.maxPlayers or 5) .. ")",
                    fontSize = Theme.fontSize.small,
                    fontColor = Theme.colors.textLight,
                    textAlign = "center",
                    marginTop = 4,
                },
            },
        },
        -- 成员列表
        Comp.BuildSectionTitle("队伍成员"),
        UI.Panel { width = "100%", children = memberRows },
        -- 操作栏
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            gap = Theme.spacing.sm,
            marginTop = Theme.spacing.md,
            children = actions,
        },
    }
end

-- ============================================================================
-- 战斗视图：Boss 血条 + 回合日志
-- ============================================================================

local function BuildBattle(p)
    local boss = GameBoss.GetBoss()
    local logs = GameBoss.GetRoundLogs()

    if not boss then
        return { UI.Label { text = "战斗数据加载中...", fontSize = Theme.fontSize.body, fontColor = Theme.colors.textLight } }
    end

    -- Boss 血条
    local hpRatio = (boss.hpMax > 0) and (boss.hp / boss.hpMax) or 0
    local hpPct = math.max(0, math.floor(hpRatio * 100))
    local hpColor = hpRatio > 0.5 and { 200, 60, 60, 255 }
        or (hpRatio > 0.2 and { 200, 160, 40, 255 } or { 200, 60, 60, 255 })

    local bossPanel = UI.Panel {
        width = "100%",
        padding = Theme.spacing.md,
        borderRadius = Theme.radius.md,
        backgroundColor = { 50, 18, 18, 220 },
        borderColor = { 160, 50, 35, 255 },
        borderWidth = 2,
        marginBottom = Theme.spacing.md,
        children = {
            UI.Label {
                text = boss.name,
                fontSize = Theme.fontSize.subtitle,
                fontColor = { 255, 100, 80, 255 },
                textAlign = "center",
            },
            -- HP 条
            UI.Panel {
                width = "100%", height = 14,
                borderRadius = 7,
                backgroundColor = { 30, 15, 15, 220 },
                marginTop = 6,
                overflow = "hidden",
                children = {
                    UI.Panel {
                        width = tostring(hpPct) .. "%",
                        height = "100%",
                        borderRadius = 7,
                        backgroundColor = hpColor,
                    },
                },
            },
            UI.Label {
                text = boss.hp .. " / " .. boss.hpMax .. "  (" .. hpPct .. "%)",
                fontSize = Theme.fontSize.small - 1,
                fontColor = { 200, 160, 140, 200 },
                textAlign = "center",
                marginTop = 3,
            },
        },
    }

    -- 回合日志（显示最近 5 回合）
    local logItems = {}
    local startIdx = math.max(1, #logs - 4)
    for i = startIdx, #logs do
        local rd = logs[i]
        local lines = {}
        if rd.actions then
            for _, act in ipairs(rd.actions) do
                if act.type == "player_atk" then
                    local hitStr = act.hit and (act.crit and "<c=yellow>暴击</c>" or "命中") or "<c=gray>闪避</c>"
                    local dmgStr = act.hit and (" <c=red>" .. act.damage .. "</c>") or ""
                    lines[#lines + 1] = act.name .. " " .. hitStr .. " 造成" .. dmgStr
                elseif act.type == "boss_atk" then
                    local hitStr = act.hit and (act.crit and "<c=yellow>暴击</c>" or "命中") or "<c=gray>闪避</c>"
                    local dmgStr = act.hit and (" <c=orange>" .. act.damage .. "</c>") or ""
                    lines[#lines + 1] = "Boss -> " .. (act.targetName or "?") .. " " .. hitStr .. " 造成" .. dmgStr
                end
            end
        end
        local roundChildren = {
            UI.Label {
                text = "第 " .. rd.round .. " 回合",
                fontSize = Theme.fontSize.small - 1,
                fontColor = Theme.colors.gold,
            },
        }
        for _, line in ipairs(lines) do
            roundChildren[#roundChildren + 1] = RT.Build(line, Theme.fontSize.small - 1, Theme.colors.textLight)
        end
        logItems[#logItems + 1] = UI.Panel {
            width = "100%",
            padding = 6,
            marginBottom = 3,
            borderRadius = 4,
            backgroundColor = { 35, 30, 22, 160 },
            gap = 2,
            children = roundChildren,
        }
    end

    return {
        bossPanel,
        Comp.BuildSectionTitle("战斗日志"),
        UI.Panel { width = "100%", children = logItems },
    }
end

-- ============================================================================
-- 结果视图：胜败 + 贡献排名 + 结算按钮
-- ============================================================================

local function BuildResult(p)
    local result = GameBoss.GetBattleResult()
    local settle = GameBoss.GetSettleInfo()

    if not result then
        return { UI.Label { text = "等待结果...", fontSize = Theme.fontSize.body, fontColor = Theme.colors.textLight } }
    end

    local won = result.won
    local titleColor = won and Theme.colors.gold or { 200, 80, 60, 255 }
    local titleText = won and ("击败 " .. (result.bossName or "Boss") .. "!")
        or ("被 " .. (result.bossName or "Boss") .. " 击败")

    -- 贡献排名
    local rankRows = {}
    if result.contributions then
        for i, c in ipairs(result.contributions) do
            local medal = (i == 1) and "MVP " or ("#" .. i .. " ")
            rankRows[#rankRows + 1] = UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                paddingVertical = 6,
                paddingHorizontal = 8,
                marginBottom = 3,
                borderRadius = Theme.radius.sm,
                backgroundColor = (i == 1) and { 60, 50, 30, 200 } or Theme.colors.bgDark,
                borderColor = (i == 1) and Theme.colors.gold or Theme.colors.border,
                borderWidth = (i == 1) and 1 or 0,
                children = {
                    UI.Label {
                        text = medal .. c.name,
                        fontSize = Theme.fontSize.small,
                        fontColor = (i == 1) and Theme.colors.gold or Theme.colors.text,
                    },
                    UI.Label {
                        text = "伤害 " .. c.damage,
                        fontSize = Theme.fontSize.small,
                        fontColor = Theme.colors.textLight,
                    },
                },
            }
        end
    end

    -- 结算信息
    local settleChildren = {}
    if settle then
        settleChildren[#settleChildren + 1] = UI.Panel {
            width = "100%",
            padding = Theme.spacing.sm,
            borderRadius = Theme.radius.sm,
            backgroundColor = { 50, 45, 25, 200 },
            borderColor = Theme.colors.borderGold,
            borderWidth = 1,
            marginBottom = Theme.spacing.sm,
            children = {
                UI.Label {
                    text = "可领取: 灵石 " .. settle.reward .. " (贡献" .. settle.ratio .. "%)",
                    fontSize = Theme.fontSize.body,
                    fontColor = Theme.colors.gold,
                    textAlign = "center",
                },
            },
        }
        local settleText = GameBoss.IsSettling() and "结算中..." or "领取奖励"
        settleChildren[#settleChildren + 1] = Comp.BuildInkButton(settleText, function()
            GameBoss.Settle()
        end, { width = "100%", disabled = GameBoss.IsSettling() })
    elseif not won then
        settleChildren[#settleChildren + 1] = UI.Label {
            text = "战斗失败，无奖励",
            fontSize = Theme.fontSize.body,
            fontColor = { 200, 100, 80, 255 },
            textAlign = "center",
        }
    else
        settleChildren[#settleChildren + 1] = UI.Label {
            text = "奖励已领取",
            fontSize = Theme.fontSize.body,
            fontColor = { 100, 200, 100, 255 },
            textAlign = "center",
        }
    end

    -- 返回大厅按钮
    local backBtn = Comp.BuildSecondaryButton("返回大厅", function()
        GameBoss.Leave()
        view_ = "lobby"
        lobbyRequested_ = false
        Router.RebuildUI()
    end, { width = "100%" })

    return {
        -- 胜负标题
        UI.Panel {
            width = "100%",
            paddingVertical = Theme.spacing.md,
            alignItems = "center",
            children = {
                UI.Label {
                    text = titleText,
                    fontSize = Theme.fontSize.title,
                    fontColor = titleColor,
                    textAlign = "center",
                },
                UI.Label {
                    text = "共 " .. (result.rounds or 0) .. " 回合  总伤害 " .. (result.totalDamage or 0),
                    fontSize = Theme.fontSize.small,
                    fontColor = Theme.colors.textLight,
                    marginTop = 4,
                },
            },
        },
        -- 贡献排名
        Comp.BuildSectionTitle("贡献排名"),
        UI.Panel { width = "100%", children = rankRows, marginBottom = Theme.spacing.md },
        -- 结算区
        UI.Panel { width = "100%", children = settleChildren },
        -- 返回按钮
        UI.Panel { width = "100%", marginTop = Theme.spacing.md, children = { backBtn } },
    }
end

-- ============================================================================
-- 页面主构建函数
-- ============================================================================

function M.Build(payload)
    local p = GamePlayer.Get()

    -- 注册回调（仅一次）
    RegisterCallbacks()

    -- 大厅视图且不在房间内时，请求一次房间列表
    if view_ == "lobby" and not GameBoss.InRoom() and not lobbyRequested_ then
        lobbyRequested_ = true
        GameBoss.ListRooms()
    end

    -- 如果已在房间但 view 还在 lobby，修正
    if GameBoss.InRoom() and view_ == "lobby" then
        view_ = GameBoss.InBattle() and "battle" or "room"
    end
    -- 如果有战斗结果
    if GameBoss.GetBattleResult() and view_ == "battle" then
        view_ = "result"
    end

    -- 根据 view 选择内容
    local content
    if view_ == "room" then
        content = BuildRoom(p)
    elseif view_ == "battle" then
        content = BuildBattle(p)
    elseif view_ == "result" then
        content = BuildResult(p)
    else
        content = BuildLobby(p)
    end

    return Comp.BuildPageShell("map", p, content, Router.HandleNavigate)
end

-- ============================================================================
-- 页面退出清理
-- ============================================================================

function M.Cleanup()
    UnregisterCallbacks()
    errorMsg_ = nil
    view_ = "lobby"
    selectedArea_ = nil
end

return M
