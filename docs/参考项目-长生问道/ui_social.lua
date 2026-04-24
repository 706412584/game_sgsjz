-- ============================================================================
-- 《问道长生》社交页面
-- 好友列表 / 待处理申请 / 添加好友 / 赠送礼物
-- ============================================================================

local UI         = require("urhox-libs/UI")
local Theme      = require("ui_theme")
local Comp       = require("ui_components")
local Router     = require("ui_router")
local GamePlayer = require("game_player")
local GameSocial = require("game_social")
local DataSocial = require("data_social")
local Toast        = require("ui_toast")
local UIChallenge  = require("ui_challenge")
local DataRealms   = require("data_realms")

local M = {}

-- 境界颜色：仙界紫，凡人金
local _REALM_PURPLE = { 167, 139, 250, 255 }
local _REALM_GOLD   = { 230, 195, 100, 255 }

local function RealmColor(realmName)
    if not realmName or realmName == "" then return Theme.colors.textSecondary end
    local tier = DataRealms.ParseFullName(realmName)
    if tier and tier >= 11 then return _REALM_PURPLE end
    if tier and tier >= 1  then return _REALM_GOLD end
    return Theme.colors.textSecondary
end

-- 当前子标签：friends / pending / couple / master
local currentTab_ = "friends"

-- 弹窗状态
local showAddDialog_  = false   -- 添加好友弹窗
local addInputText_   = ""      -- 输入的ID文本
local showGiftDialog_ = false   -- 赠送礼物弹窗
local giftTarget_     = nil     -- 赠送目标好友对象
local dataRequested_  = false   -- 是否已经请求过数据

-- ============================================================================
-- 初始化：进入页面时请求数据
-- ============================================================================
local function RequestData()
    GameSocial.RequestFriends()
    GameSocial.RequestPending()
end

-- ============================================================================
-- 返回行
-- ============================================================================
local function BuildBackRow()
    local pendingCount = GameSocial.GetPendingCount()
    local pendingHint = ""
    if pendingCount > 0 then
        pendingHint = " (" .. pendingCount .. ")"
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 8,
                children = {
                    UI.Panel {
                        paddingHorizontal = 8, paddingVertical = 4, cursor = "pointer",
                        onClick = function(self)
                            Router.EnterState(Router.STATE_HOME)
                        end,
                        children = {
                            UI.Label { text = "< 返回", fontSize = Theme.fontSize.body, fontColor = Theme.colors.gold },
                        },
                    },
                    UI.Label {
                        text = "游戏关系",
                        fontSize = Theme.fontSize.heading, fontWeight = "bold", fontColor = Theme.colors.textGold,
                    },
                },
            },
            -- 好友数量
            UI.Label {
                text = "好友: " .. GameSocial.GetFriendCount() .. "/" .. DataSocial.RELATION_CONFIG.friend.maxCount,
                fontSize = Theme.fontSize.small, fontColor = Theme.colors.textSecondary,
            },
        },
    }
end

-- ============================================================================
-- 子标签栏
-- ============================================================================
local function BuildTabBar()
    local pendingCount = GameSocial.GetPendingCount()

    local function TabBtn(label, key, badge)
        local isActive = currentTab_ == key
        local text = label
        if badge and badge > 0 then
            text = label .. "(" .. badge .. ")"
        end
        return UI.Panel {
            flex = 1,
            paddingVertical = 8,
            alignItems = "center",
            cursor = "pointer",
            borderBottomWidth = isActive and 2 or 0,
            borderColor = Theme.colors.gold,
            onClick = function(self)
                if currentTab_ ~= key then
                    currentTab_ = key
                    Router.RebuildUI()
                end
            end,
            children = {
                UI.Label {
                    text = text,
                    fontSize = Theme.fontSize.body,
                    fontWeight = isActive and "bold" or "normal",
                    fontColor = isActive and Theme.colors.textGold or Theme.colors.textSecondary,
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        backgroundColor = Theme.colors.bgDark,
        borderRadius = Theme.radius.sm,
        children = {
            TabBtn("好友列表", "friends"),
            TabBtn("关系邀请", "pending", pendingCount),
            TabBtn("道侣", "couple"),
            TabBtn("师徒", "master"),
        },
    }
end

-- ============================================================================
-- 操作按钮行：添加好友 / 一键拒绝
-- ============================================================================
local function BuildActionBar()
    local children = {}

    -- 添加好友按钮
    children[#children + 1] = Comp.BuildInkButton("添加好友", function()
        showAddDialog_ = true
        addInputText_ = ""
        Router.RebuildUI()
    end, { flex = 1 })

    if currentTab_ == "pending" and GameSocial.GetPendingCount() > 0 then
        children[#children + 1] = Comp.BuildSecondaryButton("一键拒绝", function()
            GameSocial.RejectAll()
        end, { flex = 1 })
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 10,
        children = children,
    }
end

-- ============================================================================
-- 好友卡片
-- ============================================================================
local function BuildFriendCard(friend)
    local favorLv = DataSocial.GetFavorLevel(friend.favor or 0)

    -- 关系标签
    local relationLabel = "好友"
    local relationColor = DataSocial.RELATION_CONFIG.friend.color
    local cfg = DataSocial.RELATION_CONFIG[friend.relation]
    if cfg then
        relationLabel = cfg.label
        relationColor = cfg.color
    end

    return Comp.BuildCardPanel(nil, {
        -- 主信息行
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            children = {
                -- 左侧：名字 + 境界
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 8, flexShrink = 1,
                    children = {
                        UI.Label {
                            text = friend.friendName or "未知",
                            fontSize = Theme.fontSize.subtitle,
                            fontWeight = "bold",
                            fontColor = Theme.colors.textGold,
                        },
                        UI.Label {
                            text = friend.friendRealm or "",
                            fontSize = Theme.fontSize.small,
                            fontColor = RealmColor(friend.friendRealm),
                        },
                    },
                },
                -- 右侧：关系标签
                UI.Panel {
                    paddingHorizontal = 8, paddingVertical = 2,
                    borderRadius = 4,
                    backgroundColor = { relationColor[1], relationColor[2], relationColor[3], 40 },
                    borderColor = relationColor, borderWidth = 1,
                    children = {
                        UI.Label {
                            text = relationLabel,
                            fontSize = Theme.fontSize.tiny,
                            fontColor = relationColor,
                        },
                    },
                },
            },
        },
        -- 好感度行
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 12,
            children = {
                UI.Label {
                    text = "好感: " .. tostring(friend.favor or 0),
                    fontSize = Theme.fontSize.small,
                    fontColor = Theme.colors.textLight,
                },
                UI.Label {
                    text = favorLv.label,
                    fontSize = Theme.fontSize.small,
                    fontColor = favorLv.color,
                },
            },
        },
        -- 操作行（两行布局防止按钮过多挤压）
        UI.Panel {
            width = "100%",
            gap = 4,
            marginTop = 4,
            children = (function()
                local row1 = {}
                local row2 = {}
                -- 第一行：常用操作
                row1[#row1 + 1] = Comp.BuildSecondaryButton("送礼", function()
                    giftTarget_ = friend
                    showGiftDialog_ = true
                    Router.RebuildUI()
                end, { flex = 1, height = 28 })
                row1[#row1 + 1] = Comp.BuildSecondaryButton("切磋", function()
                    GameSocial.RequestChallenge(friend.friendUid)
                end, { flex = 1, height = 28 })
                row1[#row1 + 1] = Comp.BuildSecondaryButton("解除", function()
                    GameSocial.RemoveFriend(friend.friendUid)
                end, { flex = 1, height = 28 })

                -- 第二行：关系操作（仅在满足条件时显示）
                local hasDaoCouple = GameSocial.GetDaoCouple() ~= nil
                local reqFavor = DataSocial.RELATION_CONFIG.dao_couple.requireFavor
                if friend.relation == "friend" and (friend.favor or 0) >= reqFavor and not hasDaoCouple then
                    row2[#row2 + 1] = Comp.BuildInkButton("结缘", function()
                        GameSocial.ProposeDaoCouple(friend.friendUid)
                    end, { flex = 1, height = 28 })
                end
                local mdCfg = DataSocial.MASTER_DISCIPLE
                local myP = GamePlayer.Get()
                local myTier = myP and myP.realmTier or 1
                local friendTier = friend.friendTier or 1
                if friend.relation == "friend" and (friend.favor or 0) >= DataSocial.RELATION_CONFIG.master_disciple.requireFavor then
                    if friendTier >= mdCfg.masterMinRealm then
                        row2[#row2 + 1] = Comp.BuildInkButton("拜师", function()
                            GameSocial.ProposeMasterAsDisciple(friend.friendUid, friendTier)
                        end, { flex = 1, height = 28 })
                    end
                    if myTier >= mdCfg.masterMinRealm then
                        row2[#row2 + 1] = Comp.BuildInkButton("收徒", function()
                            GameSocial.ProposeMasterAsMaster(friend.friendUid, friendTier)
                        end, { flex = 1, height = 28 })
                    end
                end

                local rows = {}
                rows[#rows + 1] = UI.Panel {
                    width = "100%", flexDirection = "row", gap = 8, children = row1,
                }
                if #row2 > 0 then
                    rows[#rows + 1] = UI.Panel {
                        width = "100%", flexDirection = "row", gap = 8, children = row2,
                    }
                end
                return rows
            end)(),
        },
    }, { gap = 6 })
end

-- ============================================================================
-- 待处理申请卡片
-- ============================================================================
local function BuildPendingCard(item)
    return Comp.BuildCardPanel(nil, {
        -- 申请者信息
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 8, flexShrink = 1,
                    children = {
                        UI.Label {
                            text = item.fromName or "未知",
                            fontSize = Theme.fontSize.subtitle, fontWeight = "bold",
                            fontColor = Theme.colors.textGold,
                        },
                        UI.Label {
                            text = item.fromRealm or "",
                            fontSize = Theme.fontSize.small,
                            fontColor = Theme.colors.textSecondary,
                        },
                    },
                },
                UI.Label {
                    text = "请求加为好友",
                    fontSize = Theme.fontSize.small, fontColor = Theme.colors.textSecondary,
                },
            },
        },
        -- 操作行
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 8,
            marginTop = 4,
            children = {
                Comp.BuildInkButton("同意", function()
                    GameSocial.AcceptFriend(item)
                end, { flex = 1, height = 30 }),
                Comp.BuildSecondaryButton("拒绝", function()
                    GameSocial.RejectFriend(item)
                end, { flex = 1, height = 30 }),
            },
        },
    }, { gap = 6 })
end

-- ============================================================================
-- 列表内容
-- ============================================================================
-- ============================================================================
-- 道侣详情面板
-- ============================================================================
local function BuildCouplePanel()
    local couple = GameSocial.GetDaoCouple()
    if not couple then
        return UI.Panel {
            width = "100%", paddingVertical = 40, alignItems = "center",
            children = {
                UI.Label {
                    text = "尚未结缘",
                    fontSize = Theme.fontSize.subtitle, fontWeight = "bold",
                    fontColor = Theme.colors.textSecondary,
                },
                UI.Label {
                    text = "好感度达到 " .. DataSocial.RELATION_CONFIG.dao_couple.requireFavor
                        .. " 后可在好友列表中点击「结缘」",
                    fontSize = Theme.fontSize.small,
                    fontColor = { 100, 90, 75, 150 },
                    marginTop = 8, textAlign = "center", width = "80%",
                },
            },
        }
    end

    local intimacy = couple.intimacy or 0
    local lvInfo = DataSocial.GetCoupleLevel(intimacy)
    local bonusPct = math.floor(lvInfo.cultivateBonus * 100)
    local storedLv = tonumber(couple.coupleLevel) or 1
    local canLevelUp = lvInfo.level > storedLv

    -- 今日修炼次数
    local today = os.date("%Y-%m-%d")
    local usedToday = 0
    if couple.practiceDate == today then
        usedToday = tonumber(couple.practiceCount) or 0
    end
    local maxPractice = DataSocial.DAO_COUPLE_DAILY_PRACTICE

    -- 修炼消耗
    local p = GamePlayer.Get()
    local tier = p and p.realmTier or 1
    local cost = math.max(1, tier) * DataSocial.DAO_COUPLE_COST_PER_TIER

    -- 进度条（到下一级）
    local progressChildren = {}
    if lvInfo.nextReq then
        local curLvReq = DataSocial.DAO_COUPLE_LEVELS[storedLv] and DataSocial.DAO_COUPLE_LEVELS[storedLv].reqIntimacy or 0
        local range = lvInfo.nextReq - curLvReq
        local prog = range > 0 and math.min(1, (intimacy - curLvReq) / range) or 1
        progressChildren[#progressChildren + 1] = UI.Panel {
            width = "100%", height = 6, borderRadius = 3,
            backgroundColor = Theme.colors.bgDark,
            children = {
                UI.Panel {
                    width = tostring(math.floor(prog * 100)) .. "%",
                    height = "100%", borderRadius = 3,
                    backgroundColor = DataSocial.RELATION_CONFIG.dao_couple.color,
                },
            },
        }
        progressChildren[#progressChildren + 1] = UI.Label {
            text = intimacy .. " / " .. lvInfo.nextReq,
            fontSize = Theme.fontSize.tiny,
            fontColor = Theme.colors.textSecondary,
            marginTop = 2,
        }
    else
        progressChildren[#progressChildren + 1] = UI.Label {
            text = "亲密度已满 (" .. intimacy .. ")",
            fontSize = Theme.fontSize.tiny,
            fontColor = Theme.colors.textGold,
        }
    end

    return Comp.BuildCardPanel(nil, {
        -- 道侣名字 + 等级
        UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 8,
                    children = {
                        UI.Label {
                            text = couple.friendName or "未知",
                            fontSize = Theme.fontSize.heading, fontWeight = "bold",
                            fontColor = DataSocial.RELATION_CONFIG.dao_couple.color,
                        },
                        UI.Label {
                            text = couple.friendRealm or "",
                            fontSize = Theme.fontSize.small,
                            fontColor = RealmColor(couple.friendRealm),
                        },
                    },
                },
                UI.Panel {
                    paddingHorizontal = 8, paddingVertical = 2, borderRadius = 4,
                    backgroundColor = { 206, 77, 30, 40 },
                    borderColor = DataSocial.RELATION_CONFIG.dao_couple.color, borderWidth = 1,
                    children = {
                        UI.Label {
                            text = "道侣 Lv." .. storedLv,
                            fontSize = Theme.fontSize.tiny,
                            fontColor = DataSocial.RELATION_CONFIG.dao_couple.color,
                        },
                    },
                },
            },
        },

        -- 属性信息
        Comp.BuildStatRow("修炼加成", "+" .. bonusPct .. "%", {
            valueColor = Theme.colors.textGold,
        }),
        Comp.BuildStatRow("好感度", tostring(couple.favor or 0)),
        Comp.BuildStatRow("亲密度", tostring(intimacy)),

        -- 亲密度进度
        UI.Panel { width = "100%", gap = 2, marginTop = 4, children = progressChildren },

        -- 今日修炼次数
        Comp.BuildStatRow("今日修炼",
            usedToday .. " / " .. maxPractice, {
            valueColor = usedToday >= maxPractice and Theme.colors.error or Theme.colors.textLight,
        }),

        -- 操作按钮行
        UI.Panel {
            width = "100%", flexDirection = "row", gap = 8, marginTop = 8,
            children = (function()
                local btns = {}
                if usedToday < maxPractice then
                    btns[#btns + 1] = Comp.BuildInkButton(
                        "道侣修炼(" .. cost .. "灵石)", function()
                        GameSocial.CouplePractice(couple.friendUid)
                    end, { flex = 1, height = 32 })
                else
                    btns[#btns + 1] = Comp.BuildSecondaryButton(
                        "今日已满", function() end, { flex = 1, height = 32, disabled = true })
                end
                if canLevelUp then
                    btns[#btns + 1] = Comp.BuildInkButton(
                        "提升等级", function()
                        GameSocial.CoupleLevelUp(couple.friendUid)
                    end, { flex = 1, height = 32 })
                end
                return btns
            end)(),
        },
    }, { gap = 6 })
end

-- ============================================================================
-- 师徒详情面板
-- ============================================================================
local function BuildMasterPanel()
    local master = GameSocial.GetMaster()
    local disciples = GameSocial.GetDisciples()
    local p = GamePlayer.Get()
    local myTier = p and p.realmTier or 1
    local mdCfg = DataSocial.MASTER_DISCIPLE

    local children = {}

    -- === 师傅区域 ===
    children[#children + 1] = UI.Label {
        text = "-- 师傅 --",
        fontSize = Theme.fontSize.body, fontWeight = "bold",
        fontColor = Theme.colors.textGold, textAlign = "center", width = "100%",
    }

    if master then
        -- 传功冷却计算
        local teachDate = tonumber(master.teachDate) or 0
        local now = os.time()
        local cdLeft = math.max(0, mdCfg.teachCooldown - (now - teachDate))
        local cdText = ""
        if cdLeft > 0 then
            local mins = math.ceil(cdLeft / 60)
            cdText = " (冷却 " .. mins .. " 分钟)"
        end

        children[#children + 1] = Comp.BuildCardPanel(nil, {
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 8,
                        children = {
                            UI.Label {
                                text = master.friendName or "未知",
                                fontSize = Theme.fontSize.heading, fontWeight = "bold",
                                fontColor = DataSocial.RELATION_CONFIG.master_disciple.color,
                            },
                            UI.Label {
                                text = master.friendRealm or "",
                                fontSize = Theme.fontSize.small,
                                fontColor = RealmColor(master.friendRealm),
                            },
                        },
                    },
                    UI.Panel {
                        paddingHorizontal = 8, paddingVertical = 2, borderRadius = 4,
                        backgroundColor = { 228, 193, 36, 40 },
                        borderColor = DataSocial.RELATION_CONFIG.master_disciple.color, borderWidth = 1,
                        children = {
                            UI.Label {
                                text = "师傅",
                                fontSize = Theme.fontSize.tiny,
                                fontColor = DataSocial.RELATION_CONFIG.master_disciple.color,
                            },
                        },
                    },
                },
            },
            Comp.BuildStatRow("好感度", tostring(master.favor or 0)),
            -- 无操作按钮（徒弟不能主动传功）
            UI.Label {
                text = "师傅可对你传功" .. cdText,
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
                marginTop = 4,
            },
        }, { gap = 6 })
    else
        children[#children + 1] = UI.Panel {
            width = "100%", paddingVertical = 16, alignItems = "center",
            children = {
                UI.Label {
                    text = "尚未拜师",
                    fontSize = Theme.fontSize.body, fontColor = Theme.colors.textSecondary,
                },
                UI.Label {
                    text = "好感度达到 " .. DataSocial.RELATION_CONFIG.master_disciple.requireFavor
                        .. " 后可在好友列表中点击「拜师」",
                    fontSize = Theme.fontSize.small,
                    fontColor = { 100, 90, 75, 150 }, marginTop = 4, textAlign = "center", width = "80%",
                },
            },
        }
    end

    -- === 徒弟区域 ===
    children[#children + 1] = UI.Panel { width = "100%", height = 1, backgroundColor = Theme.colors.border, marginVertical = 8 }

    local canTakeDisciple = myTier >= mdCfg.masterMinRealm
    local discipleHeader = "-- 徒弟 (" .. #disciples .. "/" .. mdCfg.maxDisciples .. ") --"
    if not canTakeDisciple then
        discipleHeader = "-- 徒弟 (需结丹以上) --"
    end
    children[#children + 1] = UI.Label {
        text = discipleHeader,
        fontSize = Theme.fontSize.body, fontWeight = "bold",
        fontColor = Theme.colors.textGold, textAlign = "center", width = "100%",
    }

    if #disciples == 0 then
        children[#children + 1] = UI.Panel {
            width = "100%", paddingVertical = 16, alignItems = "center",
            children = {
                UI.Label {
                    text = canTakeDisciple and "尚无徒弟" or "境界不足，无法收徒",
                    fontSize = Theme.fontSize.body, fontColor = Theme.colors.textSecondary,
                },
            },
        }
    else
        for _, disc in ipairs(disciples) do
            -- 传功冷却
            local teachDate = tonumber(disc.teachDate) or 0
            local now = os.time()
            local cdLeft = math.max(0, mdCfg.teachCooldown - (now - teachDate))
            local canTeach = cdLeft <= 0
            local costXiuwei = math.max(100, math.floor((p.xiuwei or 0) * 0.1))

            children[#children + 1] = Comp.BuildCardPanel(nil, {
                UI.Panel {
                    width = "100%", flexDirection = "row",
                    justifyContent = "space-between", alignItems = "center",
                    children = {
                        UI.Panel {
                            flexDirection = "row", alignItems = "center", gap = 8,
                            children = {
                                UI.Label {
                                    text = disc.friendName or "未知",
                                    fontSize = Theme.fontSize.subtitle, fontWeight = "bold",
                                    fontColor = Theme.colors.textGold,
                                },
                                UI.Label {
                                    text = disc.friendRealm or "",
                                    fontSize = Theme.fontSize.small,
                                    fontColor = RealmColor(disc.friendRealm),
                                },
                            },
                        },
                        UI.Panel {
                            paddingHorizontal = 6, paddingVertical = 2, borderRadius = 4,
                            backgroundColor = { 228, 193, 36, 30 },
                            children = {
                                UI.Label {
                                    text = "徒弟",
                                    fontSize = Theme.fontSize.tiny,
                                    fontColor = DataSocial.RELATION_CONFIG.master_disciple.color,
                                },
                            },
                        },
                    },
                },
                Comp.BuildStatRow("好感度", tostring(disc.favor or 0)),
                -- 传功按钮
                UI.Panel {
                    width = "100%", flexDirection = "row", gap = 8, marginTop = 4,
                    children = {
                        canTeach
                            and Comp.BuildInkButton(
                                "传功(消耗" .. costXiuwei .. "修为)", function()
                                    GameSocial.MasterTeach(disc.friendUid)
                                end, { flex = 1, height = 32 })
                            or Comp.BuildSecondaryButton(
                                "冷却中(" .. math.ceil(cdLeft / 60) .. "分钟)", function() end,
                                { flex = 1, height = 32, disabled = true }),
                    },
                },
            }, { gap = 6 })
        end
    end

    return UI.Panel {
        width = "100%", gap = 10,
        children = children,
    }
end

-- ============================================================================
-- 列表内容
-- ============================================================================
local function BuildListContent()
    local children = {}

    if currentTab_ == "friends" then
        local friends = GameSocial.GetFriends()
        if #friends == 0 then
            children[#children + 1] = UI.Panel {
                width = "100%", paddingVertical = 40, alignItems = "center",
                children = {
                    UI.Label {
                        text = "暂无好友",
                        fontSize = Theme.fontSize.body,
                        fontColor = Theme.colors.textSecondary,
                    },
                    UI.Label {
                        text = "点击「添加好友」输入对方ID申请",
                        fontSize = Theme.fontSize.small,
                        fontColor = { 100, 90, 75, 150 },
                        marginTop = 8,
                    },
                },
            }
        else
            for _, friend in ipairs(friends) do
                children[#children + 1] = BuildFriendCard(friend)
            end
        end
    elseif currentTab_ == "couple" then
        children[#children + 1] = BuildCouplePanel()
    elseif currentTab_ == "master" then
        children[#children + 1] = BuildMasterPanel()
    else
        -- pending
        local pending = GameSocial.GetPending()
        if #pending == 0 then
            children[#children + 1] = UI.Panel {
                width = "100%", paddingVertical = 40, alignItems = "center",
                children = {
                    UI.Label {
                        text = "暂无好友申请",
                        fontSize = Theme.fontSize.body,
                        fontColor = Theme.colors.textSecondary,
                    },
                },
            }
        else
            for _, item in ipairs(pending) do
                children[#children + 1] = BuildPendingCard(item)
            end
        end
    end

    return UI.Panel {
        width = "100%",
        gap = 8,
        paddingBottom = 40,
        children = children,
    }
end

-- ============================================================================
-- 添加好友弹窗（使用通用 Dialog）
-- ============================================================================
local addInputField_ = nil  -- TextField 引用

local function CloseAddDialog()
    showAddDialog_ = false
    Router.RebuildUI()
end

local function DoAddFriend()
    local text = addInputField_ and addInputField_:GetValue() or ""
    local targetUid = tonumber(text)
    if not targetUid or targetUid <= 0 then
        Toast.Show("请输入有效的玩家ID", { variant = "error" })
        return
    end
    showAddDialog_ = false
    GameSocial.AddFriend(targetUid)
    Router.RebuildUI()
end

local function BuildAddFriendModal()
    if not showAddDialog_ then return nil end

    addInputField_ = UI.TextField {
        width = "100%",
        height = 36,
        placeholder = "输入玩家ID",
        fontSize = Theme.fontSize.body,
        onSubmit = function(field, text) DoAddFriend() end,
    }

    -- content 为自定义控件：提示文字 + 输入框
    local contentWidget = UI.Panel {
        width = "100%", gap = 10,
        children = {
            UI.Label {
                text = "请输入对方玩家ID",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
                textAlign = "center",
                width = "100%",
            },
            addInputField_,
        },
    }

    return Comp.Dialog("添加好友", contentWidget, {
        { text = "取消", onClick = CloseAddDialog },
        { text = "申请", onClick = DoAddFriend, primary = true },
    }, { onClose = CloseAddDialog })
end

-- ============================================================================
-- 赠送礼物弹窗（使用通用 Dialog）
-- ============================================================================
local function CloseGiftDialog()
    showGiftDialog_ = false
    giftTarget_ = nil
    Router.RebuildUI()
end

local function BuildGiftModal()
    if not showGiftDialog_ or not giftTarget_ then return nil end

    local giftRows = {}
    for _, gift in ipairs(DataSocial.FAVOR_GIFTS) do
        giftRows[#giftRows + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            paddingVertical = 6,
            paddingHorizontal = 8,
            borderRadius = Theme.radius.sm,
            backgroundColor = Theme.colors.bgDark,
            cursor = "pointer",
            onClick = function(self)
                local uid = giftTarget_.friendUid
                showGiftDialog_ = false
                giftTarget_ = nil
                GameSocial.SendGift(uid, gift.id)
                Router.RebuildUI()
            end,
            children = {
                UI.Panel {
                    gap = 2, flexShrink = 1,
                    children = {
                        UI.Label {
                            text = gift.name .. " (好感+" .. gift.favor .. ")",
                            fontSize = Theme.fontSize.body,
                            fontColor = Theme.colors.textGold,
                        },
                        UI.Label {
                            text = gift.desc,
                            fontSize = Theme.fontSize.tiny,
                            fontColor = Theme.colors.textSecondary,
                        },
                    },
                },
                UI.Label {
                    text = gift.price .. "灵石",
                    fontSize = Theme.fontSize.small,
                    fontColor = Theme.colors.warning,
                },
            },
        }
    end

    local giftList = UI.Panel { width = "100%", gap = 6, children = giftRows }

    return Comp.Dialog(
        "赠送给 " .. (giftTarget_.friendName or "好友"),
        giftList,
        { { text = "取消", onClick = CloseGiftDialog } },
        { onClose = CloseGiftDialog }
    )
end

-- ============================================================================
-- 构建页面
-- ============================================================================
function M.Build(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    -- 注册刷新回调
    GameSocial.SetRefreshCallback(function()
        Router.RebuildUI()
    end)

    -- 仅首次进入时请求数据（防止 Build→请求→回调→RebuildUI→Build 死循环）
    if not dataRequested_ then
        dataRequested_ = true
        RequestData()
    end

    local contentChildren = {
        BuildBackRow(),
        BuildTabBar(),
        BuildActionBar(),
        BuildListContent(),
    }

    local page = Comp.BuildPageShell("social", p, contentChildren, Router.HandleNavigate)

    -- 弹窗叠加层
    local modal = BuildAddFriendModal() or BuildGiftModal() or UIChallenge.BuildChallengeModal()
    if modal then
        page:AddChild(modal)
    end

    return page
end

--- 离开页面时清理状态
function M.Cleanup()
    dataRequested_ = false
    showAddDialog_ = false
    showGiftDialog_ = false
    giftTarget_ = nil
    GameSocial.SetRefreshCallback(nil)
end

return M
