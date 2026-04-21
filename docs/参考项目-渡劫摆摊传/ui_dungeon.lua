-- ============================================================================
-- ui_dungeon.lua — 秘境探险弹窗（overlay 模式）
-- 三个视图: list(秘境列表) / adventure(探险中) / settle(结算)
-- ============================================================================
local UI = require("urhox-libs/UI")
local Config = require("data_config")
local State = require("data_state")
local GameCore = require("game_core")

local M = {}

local container_ = nil
local overlayPanel = nil
local contentPanel = nil
local viewState = "list"  -- "list" / "adventure" / "settle"

-- 资源名称映射(基础 + 动态查找)
local RES_NAMES = {
    lingshi = "灵石", xiuwei = "修为",
}

--- 根据 ID 查找资源中文名称
local function getResName(id)
    if RES_NAMES[id] then return RES_NAMES[id] end
    local mat = Config.GetMaterialById(id)
    if mat then return mat.name end
    local prod = Config.GetProductById(id)
    if prod then return prod.name end
    return id
end

--- 格式化奖励表为文本
local function formatReward(reward)
    if not reward or not next(reward) then return "" end
    local parts = {}
    for k, v in pairs(reward) do
        local name = getResName(k)
        if v >= 0 then
            table.insert(parts, name .. "+" .. v)
        else
            table.insert(parts, name .. v)
        end
    end
    return table.concat(parts, "  ")
end

--- 获取某秘境今日已用次数
local function getDungeonUsed(dungeonId)
    local s = State.state
    -- 跨天重置检查(UTC+8 北京时间)
    local today = os.date("!%Y%m%d", os.time() + 8 * 3600)
    if (s.dungeonDailyDate or "") ~= today then
        return 0
    end
    if not s.dungeonDailyUses then return 0 end
    return s.dungeonDailyUses[dungeonId] or 0
end

--- 获取某秘境每日总上限(基础+广告奖励)
---@param dungeonId string
---@return number
local function getDungeonTotalLimit(dungeonId)
    local dg = Config.GetDungeonById(dungeonId)
    -- 仙界秘境每日基础限额1次，凡间秘境3次
    local base = (dg and dg.celestial) and 1 or (Config.DUNGEON_DAILY_LIMIT or 3)
    local bonus = 0
    local s = State.state
    if s.dungeonBonusUses and s.dungeonBonusUses[dungeonId] then
        bonus = s.dungeonBonusUses[dungeonId]
    end
    return base + bonus
end

--- 入场确认弹窗(高消耗秘境)
local confirmOverlay_ = nil
local function showEnterConfirm(dg)
    if confirmOverlay_ then
        confirmOverlay_:SetVisible(true)
        YGNodeStyleSetDisplay(confirmOverlay_.node, YGDisplayFlex)
        -- 更新内容
        local lbl = confirmOverlay_:FindById("confirm_msg")
        if lbl then lbl:SetText("进入「" .. dg.name .. "」需要 " .. dg.cost .. " 灵石，确认探险？") end
        local btn = confirmOverlay_:FindById("confirm_yes")
        if btn then btn.props.onClick = function() 
            confirmOverlay_:SetVisible(false)
            YGNodeStyleSetDisplay(confirmOverlay_.node, YGDisplayNone)
            GameCore.EnterDungeon(dg.id)
        end end
        return
    end
    confirmOverlay_ = UI.Panel {
        id = "dungeon_confirm_overlay",
        position = "absolute",
        width = "100%",
        height = "100%",
        backgroundColor = { 0, 0, 0, 180 },
        justifyContent = "center",
        alignItems = "center",
        zIndex = 95,
        onClick = function()
            confirmOverlay_:SetVisible(false)
            YGNodeStyleSetDisplay(confirmOverlay_.node, YGDisplayNone)
        end,
        children = {
            UI.Panel {
                width = "80%",
                maxWidth = 300,
                backgroundColor = Config.Colors.panel,
                borderRadius = 10,
                borderWidth = 1,
                borderColor = Config.Colors.borderGold,
                padding = 14,
                gap = 10,
                alignItems = "center",
                onClick = function() end,
                children = {
                    UI.Label {
                        text = "确认探险",
                        fontSize = 13,
                        fontWeight = "bold",
                        fontColor = Config.Colors.textGold,
                    },
                    UI.Label {
                        id = "confirm_msg",
                        text = "进入「" .. dg.name .. "」需要 " .. dg.cost .. " 灵石，确认探险？",
                        fontSize = 10,
                        fontColor = Config.Colors.textPrimary,
                        textAlign = "center",
                    },
                    UI.Panel {
                        flexDirection = "row",
                        gap = 12,
                        justifyContent = "center",
                        children = {
                            UI.Button {
                                text = "取消",
                                variant = "ghost",
                                fontSize = 10,
                                paddingHorizontal = 16,
                                paddingVertical = 5,
                                onClick = function()
                                    confirmOverlay_:SetVisible(false)
                                    YGNodeStyleSetDisplay(confirmOverlay_.node, YGDisplayNone)
                                end,
                            },
                            UI.Button {
                                id = "confirm_yes",
                                text = "确认",
                                variant = "primary",
                                fontSize = 10,
                                paddingHorizontal = 16,
                                paddingVertical = 5,
                                onClick = function()
                                    confirmOverlay_:SetVisible(false)
                                    YGNodeStyleSetDisplay(confirmOverlay_.node, YGDisplayNone)
                                    GameCore.EnterDungeon(dg.id)
                                end,
                            },
                        },
                    },
                },
            },
        },
    }
    if container_ then
        container_:AddChild(confirmOverlay_)
    end
end

-- ==================== 列表视图 ====================

local function buildListView()
    contentPanel:ClearChildren()
    local s = State.state
    local realmIdx = s.realmLevel or 1

    local isAscended = (s.ascended == true)
    print("[Dungeon] buildListView: ascended=" .. tostring(s.ascended) .. " isAscended=" .. tostring(isAscended) .. " realmLevel=" .. tostring(realmIdx) .. " totalDungeons=" .. #Config.Dungeons)

    -- 分类: 凡间秘境和仙界秘境
    local mortalDungeons = {}
    local celestialDungeons = {}
    for _, dg in ipairs(Config.Dungeons) do
        if dg.celestial then
            table.insert(celestialDungeons, dg)
        else
            table.insert(mortalDungeons, dg)
        end
    end

    -- 渲染函数: 单个秘境卡片
    local shownCount = 0
    local function renderDungeonCard(dg)
        local locked = realmIdx < dg.unlockRealm
        local used = getDungeonUsed(dg.id)
        local totalLimit = getDungeonTotalLimit(dg.id)
        local usedUp = used >= totalLimit
        local canAfford = (s.lingshi or 0) >= dg.cost
        local realmName = Config.Realms[dg.unlockRealm] and Config.Realms[dg.unlockRealm].name or ""

        -- 状态文字
        local statusText, statusColor
        if locked then
            statusText = "需要: " .. realmName
            statusColor = Config.Colors.textSecond
        elseif usedUp then
            statusText = "今日 " .. used .. "/" .. totalLimit
            statusColor = Config.Colors.orange
        elseif not canAfford then
            statusText = "灵石不足"
            statusColor = Config.Colors.red
        else
            statusText = "今日 " .. used .. "/" .. totalLimit
            statusColor = Config.Colors.textGreen
        end

        local canEnter = not locked and not usedUp and canAfford

        -- 卡片底色：锁定灰暗 / 可用时带秘境色调
        local cardBg = locked and { 30, 30, 35, 200 }
            or { dg.color[1] * 0.15 + 30, dg.color[2] * 0.15 + 30, dg.color[3] * 0.15 + 35, 230 }
        -- 边框发光：可进入时亮色、否则暗色
        local borderClr = locked and Config.Colors.border
            or canEnter and dg.color
            or { dg.color[1] * 0.5, dg.color[2] * 0.5, dg.color[3] * 0.5, 150 }

        contentPanel:AddChild(UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 10,
            padding = 10,
            backgroundColor = cardBg,
            borderRadius = 10,
            borderWidth = locked and 1 or 1.5,
            borderColor = borderClr,
            children = {
                -- 左侧图标
                UI.Panel {
                    width = 48, height = 48,
                    borderRadius = 10,
                    backgroundColor = locked and { 40, 40, 45, 200 } or { 20, 20, 28, 220 },
                    borderWidth = 1,
                    borderColor = locked and Config.Colors.border or { dg.color[1], dg.color[2], dg.color[3], 100 },
                    overflow = "hidden",
                    justifyContent = "center",
                    alignItems = "center",
                    children = {
                        UI.Panel {
                            width = 40, height = 40,
                            backgroundImage = dg.icon,
                            backgroundFit = "contain",
                            opacity = locked and 0.35 or 1.0,
                        },
                    },
                },
                -- 中间信息
                UI.Panel {
                    flexGrow = 1,
                    flexShrink = 1,
                    gap = 3,
                    children = {
                        UI.Label {
                            text = dg.name,
                            fontSize = 13,
                            fontWeight = "bold",
                            fontColor = locked and Config.Colors.textSecond or dg.color,
                        },
                        UI.Label {
                            text = dg.desc,
                            fontSize = 9,
                            fontColor = Config.Colors.textSecond,
                        },
                        UI.Panel {
                            flexDirection = "row",
                            gap = 8,
                            alignItems = "center",
                            children = {
                                UI.Label {
                                    text = dg.cost .. " 灵石",
                                    fontSize = 9,
                                    fontWeight = "bold",
                                    fontColor = canAfford and Config.Colors.textGold or Config.Colors.red,
                                },
                                UI.Panel {
                                    width = 1, height = 10,
                                    backgroundColor = Config.Colors.border,
                                },
                                UI.Label {
                                    text = statusText,
                                    fontSize = 9,
                                    fontColor = statusColor,
                                },
                            },
                        },
                    },
                },
                -- 右侧按钮
                canEnter and UI.Button {
                    text = "探险",
                    variant = "primary",
                    fontSize = 10,
                    paddingHorizontal = 14,
                    paddingVertical = 6,
                    borderRadius = 8,
                    onClick = (function(d)
                        return function()
                            if d.cost >= 1000 then
                                showEnterConfirm(d)
                            else
                                GameCore.EnterDungeon(d.id)
                            end
                        end
                    end)(dg),
                } or UI.Label {
                    text = locked and "未解锁" or (usedUp and "已用完" or "灵石不足"),
                    fontSize = 9,
                    fontColor = Config.Colors.textSecond,
                    paddingHorizontal = 8,
                },
            },
        })
        shownCount = shownCount + 1
    end

    -- 凡间秘境分类标题
    if #mortalDungeons > 0 then
        contentPanel:AddChild(UI.Label {
            text = "-- 凡间秘境 --",
            fontSize = 11,
            fontWeight = "bold",
            fontColor = Config.Colors.jade,
            textAlign = "center",
            paddingBottom = 2,
        })
        for _, dg in ipairs(mortalDungeons) do
            renderDungeonCard(dg)
        end
    end

    -- 仙界秘境分类标题（飞升后才显示）
    if isAscended and #celestialDungeons > 0 then
        contentPanel:AddChild(UI.Panel {
            width = "100%", height = 1,
            backgroundColor = Config.Colors.border,
            marginTop = 6, marginBottom = 4,
        })
        contentPanel:AddChild(UI.Label {
            text = "-- 仙界秘境 (每日1次) --",
            fontSize = 11,
            fontWeight = "bold",
            fontColor = Config.Colors.purple,
            textAlign = "center",
            paddingBottom = 2,
        })
        for _, dg in ipairs(celestialDungeons) do
            renderDungeonCard(dg)
        end
    end
    print("[Dungeon] buildListView done: shownCount=" .. shownCount)

    -- 底部统计
    contentPanel:AddChild(UI.Label {
        text = "累计探险: " .. (s.totalDungeonRuns or 0) .. " 次",
        fontSize = 9,
        fontColor = Config.Colors.textSecond,
        textAlign = "center",
        paddingTop = 4,
    })

    -- ============ 历史记录 ============
    local history = s.dungeonHistory or {}
    if #history > 0 then
        contentPanel:AddChild(UI.Panel {
            width = "100%",
            height = 1,
            backgroundColor = Config.Colors.border,
            marginTop = 6,
            marginBottom = 2,
        })
        contentPanel:AddChild(UI.Label {
            text = "近期探险记录 (24h)",
            fontSize = 10,
            fontWeight = "bold",
            fontColor = Config.Colors.textSecond,
            paddingBottom = 2,
        })

        -- 按时间倒序显示
        for i = #history, 1, -1 do
            local h = history[i]
            local cfg = Config.GetDungeonById(h.dungeonId)
            local dgName = cfg and cfg.name or "秘境"
            local dgColor = cfg and cfg.color or Config.Colors.jade

            -- 时间格式化
            local timeStr = ""
            if h.time then
                local elapsed = os.time() - h.time
                if elapsed < 60 then
                    timeStr = "刚刚"
                elseif elapsed < 3600 then
                    timeStr = math.floor(elapsed / 60) .. "分钟前"
                else
                    timeStr = math.floor(elapsed / 3600) .. "小时前"
                end
            end

            -- 奖励汇总
            local rewardText = formatReward(h.totalReward)
            if rewardText == "" then rewardText = "无收获" end

            -- 成功/失败计数
            local succCount, failCount = 0, 0
            if h.results then
                for _, r in ipairs(h.results) do
                    if r.success then succCount = succCount + 1 else failCount = failCount + 1 end
                end
            end
            local resultSummary = succCount .. "胜" .. failCount .. "负"

            local dgIcon = cfg and cfg.icon or nil
            contentPanel:AddChild(UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                backgroundColor = { 30, 30, 35, 200 },
                borderRadius = 8,
                borderWidth = 1,
                borderColor = h.abandoned and Config.Colors.border or dgColor,
                padding = 8,
                children = {
                    -- 小图标
                    dgIcon and UI.Panel {
                        width = 28, height = 28,
                        borderRadius = 6,
                        backgroundColor = { 20, 20, 28, 200 },
                        overflow = "hidden",
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            UI.Panel {
                                width = 22, height = 22,
                                backgroundImage = dgIcon,
                                backgroundFit = "contain",
                                opacity = h.abandoned and 0.4 or 0.8,
                            },
                        },
                    } or nil,
                    -- 文字信息
                    UI.Panel {
                        flexGrow = 1,
                        flexShrink = 1,
                        gap = 2,
                        children = {
                            -- 第一行: 秘境名 + 时间
                            UI.Panel {
                                flexDirection = "row",
                                justifyContent = "space-between",
                                alignItems = "center",
                                width = "100%",
                                children = {
                                    UI.Label {
                                        text = dgName .. (h.abandoned and " (放弃)" or ""),
                                        fontSize = 10,
                                        fontWeight = "bold",
                                        fontColor = h.abandoned and Config.Colors.textSecond or dgColor,
                                    },
                                    UI.Label {
                                        text = timeStr,
                                        fontSize = 8,
                                        fontColor = Config.Colors.textSecond,
                                    },
                                },
                            },
                            -- 第二行: 战绩 + 奖励
                            UI.Panel {
                                flexDirection = "row",
                                justifyContent = "space-between",
                                alignItems = "center",
                                width = "100%",
                                children = {
                                    UI.Label {
                                        text = resultSummary,
                                        fontSize = 9,
                                        fontColor = Config.Colors.textPrimary,
                                    },
                                    UI.Label {
                                        text = rewardText,
                                        fontSize = 9,
                                        fontColor = Config.Colors.textGold,
                                        flexShrink = 1,
                                        textAlign = "right",
                                    },
                                },
                            },
                        },
                    },
                },
            })
        end
    end
end

-- ==================== 探险视图 ====================

local function buildAdventureView()
    contentPanel:ClearChildren()
    local ds = GameCore.dungeonState
    if not ds then
        viewState = "list"
        buildListView()
        return
    end
    local cfg = Config.GetDungeonById(ds.dungeonId)
    local dgName = cfg and cfg.name or "秘境"
    local dgColor = cfg and cfg.color or Config.Colors.jade

    -- 顶部：图标 + 名称 + 进度
    contentPanel:AddChild(UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        width = "100%",
        gap = 10,
        children = {
            -- 秘境图标
            cfg and cfg.icon and UI.Panel {
                width = 40, height = 40,
                borderRadius = 8,
                backgroundColor = { 20, 20, 28, 220 },
                borderWidth = 1,
                borderColor = { dgColor[1], dgColor[2], dgColor[3], 100 },
                overflow = "hidden",
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Panel {
                        width = 34, height = 34,
                        backgroundImage = cfg.icon,
                        backgroundFit = "contain",
                    },
                },
            } or nil,
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                gap = 2,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        width = "100%",
                        children = {
                            UI.Label {
                                text = dgName,
                                fontSize = 13,
                                fontWeight = "bold",
                                fontColor = dgColor,
                            },
                            UI.Label {
                                text = "第 " .. ds.step .. "/" .. ds.totalSteps .. " 关",
                                fontSize = 10,
                                fontColor = Config.Colors.textSecond,
                            },
                        },
                    },
                    -- 进度条
                    UI.ProgressBar {
                        value = ds.step / ds.totalSteps,
                        width = "100%",
                        height = 6,
                        variant = "primary",
                    },
                },
            },
        },
    })

    -- 事件描述
    contentPanel:AddChild(UI.Panel {
        width = "100%",
        backgroundColor = { 25, 30, 42, 230 },
        borderRadius = 8,
        borderWidth = 1,
        borderColor = { dgColor[1], dgColor[2], dgColor[3], 60 },
        padding = 10,
        children = {
            UI.Label {
                text = ds.desc or "",
                fontSize = 11,
                fontColor = Config.Colors.textPrimary,
            },
        },
    })

    -- 三个选项按钮
    -- 成功率从 type 推断(服务端不再下发 successRate)
    local TYPE_RATES = { safe = 100, risk = 60, gamble = 30 }
    local choices = ds.choices or {}
    for i, ch in ipairs(choices) do
        local rate = TYPE_RATES[ch.type] or 50
        local typeLabel, typeColor
        if ch.type == "risk" then
            typeLabel = "冒险 " .. rate .. "%"
            typeColor = Config.Colors.orange
        elseif ch.type == "safe" then
            typeLabel = "稳妥 " .. rate .. "%"
            typeColor = Config.Colors.textGreen
        elseif ch.type == "gamble" then
            typeLabel = "豪赌 " .. rate .. "%"
            typeColor = Config.Colors.red
        else
            typeLabel = ""
            typeColor = Config.Colors.textSecond
        end

        contentPanel:AddChild(UI.Button {
            text = ch.text .. "  [" .. typeLabel .. "]",
            width = "100%",
            fontSize = 10,
            paddingVertical = 8,
            variant = ch.type == "safe" and "secondary" or (ch.type == "gamble" and "danger" or "primary"),
            onClick = function()
                GameCore.DungeonChoose(i)
            end,
        })
    end

    -- 已获得奖励汇总
    if ds.totalReward and next(ds.totalReward) then
        contentPanel:AddChild(UI.Label {
            text = "已获得: " .. formatReward(ds.totalReward),
            fontSize = 9,
            fontColor = Config.Colors.textGold,
            paddingTop = 4,
        })
    end

    -- 放弃按钮
    contentPanel:AddChild(UI.Button {
        text = "放弃探险",
        variant = "ghost",
        fontSize = 9,
        paddingVertical = 4,
        onClick = function()
            GameCore.AbandonDungeon()
        end,
    })
end

-- ==================== 结算视图 ====================

local settleData_ = nil

local function buildSettleView()
    contentPanel:ClearChildren()
    local data = settleData_
    if not data then
        viewState = "list"
        buildListView()
        return
    end
    local dungeonId = data.dungeonId or (GameCore.dungeonState and GameCore.dungeonState.dungeonId) or ""
    local cfg = Config.GetDungeonById(dungeonId)
    local dgName = cfg and cfg.name or "秘境"
    local dgColor = cfg and cfg.color or Config.Colors.jade

    -- 顶部：图标 + 标题
    contentPanel:AddChild(UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        width = "100%",
        gap = 10,
        paddingBottom = 4,
        children = {
            cfg and cfg.icon and UI.Panel {
                width = 36, height = 36,
                borderRadius = 8,
                backgroundColor = { 20, 20, 28, 220 },
                borderWidth = 1,
                borderColor = { dgColor[1], dgColor[2], dgColor[3], 100 },
                overflow = "hidden",
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Panel {
                        width = 30, height = 30,
                        backgroundImage = cfg.icon,
                        backgroundFit = "contain",
                    },
                },
            } or nil,
            UI.Label {
                text = dgName .. " - 探险结束",
                fontSize = 14,
                fontWeight = "bold",
                fontColor = Config.Colors.textGold,
            },
        },
    })

    -- 每步结果回顾
    local results = data.results or (settleData_ and settleData_.results) or {}
    for i, r in ipairs(results) do
        local rewardText = formatReward(r.reward)
        contentPanel:AddChild(UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 6,
            padding = 6,
            backgroundColor = r.success and { 30, 50, 30, 200 } or { 50, 30, 30, 200 },
            borderRadius = 6,
            children = {
                UI.Label {
                    text = "第" .. i .. "关",
                    fontSize = 9,
                    fontColor = Config.Colors.textSecond,
                    width = 36,
                },
                UI.Label {
                    text = r.choiceText or "",
                    fontSize = 9,
                    fontColor = Config.Colors.textPrimary,
                    flexGrow = 1,
                    flexShrink = 1,
                },
                UI.Label {
                    text = r.success and "成功" or "失败",
                    fontSize = 9,
                    fontColor = r.success and Config.Colors.textGreen or Config.Colors.red,
                },
            },
        })
        if rewardText ~= "" then
            contentPanel:AddChild(UI.Label {
                text = "  " .. rewardText,
                fontSize = 8,
                fontColor = r.success and Config.Colors.textGold or Config.Colors.red,
                paddingLeft = 36,
            })
        end
    end

    -- 总奖励
    local totalReward = data.totalReward or {}
    contentPanel:AddChild(UI.Panel {
        width = "100%",
        backgroundColor = { 40, 40, 20, 220 },
        borderRadius = 8,
        borderWidth = 1,
        borderColor = Config.Colors.borderGold,
        padding = 8,
        alignItems = "center",
        marginTop = 4,
        children = {
            UI.Label {
                text = "总收获",
                fontSize = 11,
                fontWeight = "bold",
                fontColor = Config.Colors.textGold,
            },
            UI.Label {
                text = next(totalReward) and formatReward(totalReward) or "无",
                fontSize = 10,
                fontColor = Config.Colors.textPrimary,
            },
        },
    })

    -- 返回按钮
    contentPanel:AddChild(UI.Button {
        text = "返回秘境列表",
        variant = "primary",
        fontSize = 11,
        paddingVertical = 6,
        width = "100%",
        marginTop = 4,
        onClick = function()
            settleData_ = nil
            viewState = "list"
            M.Refresh()
        end,
    })
end

-- ==================== 公开接口 ====================

function M.Open()
    -- 如果正在探险中, 直接进入探险视图
    if GameCore.dungeonState then
        viewState = "adventure"
    else
        viewState = "list"
    end

    if overlayPanel then
        overlayPanel:SetVisible(true)
        YGNodeStyleSetDisplay(overlayPanel.node, YGDisplayFlex)
        M.Refresh()
        return
    end

    overlayPanel = UI.Panel {
        id = "dungeon_overlay",
        position = "absolute",
        width = "100%",
        height = "100%",
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center",
        alignItems = "center",
        zIndex = 90,
        onClick = function()
            -- 探险中不允许点击背景关闭
            if viewState ~= "adventure" then
                M.Close()
            end
        end,
        children = {
            UI.Panel {
                width = "90%",
                maxWidth = 360,
                maxHeight = "85%",
                backgroundColor = Config.Colors.panel,
                borderRadius = 10,
                borderWidth = 1,
                borderColor = Config.Colors.borderGold,
                padding = 10,
                gap = 6,
                onClick = function() end, -- 阻止冒泡
                children = {
                    -- 标题栏
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                id = "dungeon_title",
                                text = "秘境探险",
                                fontSize = 14,
                                fontColor = Config.Colors.textGold,
                                fontWeight = "bold",
                            },
                            UI.Button {
                                id = "dungeon_close_btn",
                                text = "X",
                                variant = "ghost",
                                fontSize = 12,
                                paddingHorizontal = 6,
                                paddingVertical = 2,
                                onClick = function()
                                    if viewState == "adventure" then
                                        -- 探险中关闭: 最小化, 可从 HUD 按钮重新打开
                                        M.Close()
                                    else
                                        M.Close()
                                    end
                                end,
                            },
                        },
                    },
                    -- 内容区(可滚动)
                    UI.Panel {
                        id = "dungeon_content",
                        width = "100%",
                        flexGrow = 1,
                        flexShrink = 1,
                        overflow = "scroll",
                        gap = 6,
                    },
                },
            },
        },
    }
    contentPanel = overlayPanel:FindById("dungeon_content")

    if container_ then
        container_:AddChild(overlayPanel)
    end

    -- 监听事件
    State.On("dungeon_enter", function()
        viewState = "adventure"
        if M.IsOpen() then M.Refresh() end
    end)
    State.On("dungeon_next", function()
        if M.IsOpen() then M.Refresh() end
    end)
    State.On("dungeon_settle", function(_, data)
        viewState = "settle"
        settleData_ = data
        if M.IsOpen() then M.Refresh() end
    end)
    State.On("dungeon_abandon", function(_, data)
        viewState = "settle"
        settleData_ = data or { totalReward = {}, results = {} }
        if M.IsOpen() then M.Refresh() end
    end)

    M.Refresh()
end

function M.Refresh()
    if not overlayPanel or not contentPanel then return end

    -- 更新标题
    local titleLbl = overlayPanel:FindById("dungeon_title")
    if titleLbl then
        local isAscended = (State.state.ascended == true)
        if viewState == "adventure" then
            titleLbl:SetText("秘境探险中...")
        elseif viewState == "settle" then
            titleLbl:SetText("探险结算")
        else
            titleLbl:SetText(isAscended and "仙界秘境" or "秘境探险")
        end
    end

    if viewState == "adventure" then
        buildAdventureView()
    elseif viewState == "settle" then
        buildSettleView()
    else
        buildListView()
    end
end

function M.Close()
    if overlayPanel then
        overlayPanel:SetVisible(false)
        YGNodeStyleSetDisplay(overlayPanel.node, YGDisplayNone)
    end
end

function M.IsOpen()
    return overlayPanel ~= nil and overlayPanel:IsVisible()
end

function M.SetContainer(container)
    container_ = container
end

function M.GetOverlay()
    return overlayPanel
end

--- 是否可探险(红点判定): 有剩余每日次数 && 有足够灵石进入至少一个秘境
function M.CanExplore()
    local s = State.state
    local realmIdx = s.realmLevel or 1
    local isAscended = (s.ascended == true)
    for _, dg in ipairs(Config.Dungeons) do
        -- 只检查当前阶段（凡间/仙界）对应的秘境
        if (dg.celestial == true) ~= isAscended then goto continue2 end
        local totalLimit = getDungeonTotalLimit(dg.id)
        if realmIdx >= dg.unlockRealm
            and (s.lingshi or 0) >= dg.cost
            and getDungeonUsed(dg.id) < totalLimit then
            return true
        end
        ::continue2::
    end
    return false
end

return M
