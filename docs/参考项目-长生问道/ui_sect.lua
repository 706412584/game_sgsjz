-- ============================================================================
-- 《问道长生》宗门页
-- 两个视图：散修（无宗门）→ 浏览/创建；有宗门 → 信息/成员/管理
-- ============================================================================

local UI       = require("urhox-libs/UI")
local Theme    = require("ui_theme")
local Comp     = require("ui_components")
local Router   = require("ui_router")
local GamePlayer = require("game_player")
local GameSect   = require("game_sect")
local DataSect   = require("data_sect")
local ClientNet  = require("network.client_net")
local DataRealms = require("data_realms")

local M = {}

-- 境界颜色：仙界紫色，凡人金色
local _REALM_PURPLE = { 167, 139, 250, 255 }
local _REALM_GOLD   = { 230, 195, 100, 255 }

local function RealmColor(realmName)
    if not realmName or realmName == "" then return Theme.colors.textSecondary end
    local tier = DataRealms.ParseFullName(realmName)
    if tier and tier >= 11 then return _REALM_PURPLE end
    if tier and tier >= 1  then return _REALM_GOLD end
    return Theme.colors.textSecondary
end

-- ============================================================================
-- 弹窗状态
-- ============================================================================

local dialogState_ = {
    type = nil,       -- "create" / "browse" / "pending" / "confirm_leave" / "confirm_kick" / "confirm_transfer" / "donate" / "tasks"
    inputName = "",   -- 创建宗门名输入
    targetUid = nil,  -- 踢人/转让目标
    targetName = "",
    browseRaceFilter = nil,  -- 浏览列表种族筛选: nil=全部, "human"/"demon"/"spirit"/"monster"
    donateAmount = "",       -- 捐献灵石数量输入
}

local dataRequested_ = false  -- 防止 Build→请求→刷新→Build 无限循环

local function CloseDialog()
    dialogState_.type = nil
    dialogState_.inputName = ""
    dialogState_.targetUid = nil
    dialogState_.targetName = ""
    dialogState_.browseRaceFilter = nil
    dialogState_.donateAmount = ""
    M.Refresh()
end

function M.Refresh()
    if Router.GetCurrentState and Router.GetCurrentState() == Router.STATE_SECT then
        Router.RebuildUI()
    end
end

-- ============================================================================
-- 初始化：注册刷新回调
-- ============================================================================

local inited_ = false

local function EnsureInit()
    if inited_ then return end
    inited_ = true
    GameSect.SetRefreshCallback(function()
        -- UX#7: 如果审批弹窗正打开，自动重新拉取待审批列表
        if dialogState_.type == "pending" then
            GameSect.RequestPending()
        end
        M.Refresh()
    end)
end

-- ============================================================================
-- 散修视图
-- ============================================================================

local function BuildFreelancerView(p)
    return {
        -- 散修联盟标题
        UI.Panel {
            width = "100%",
            alignItems = "center",
            gap = 6,
            paddingVertical = 12,
            children = {
                UI.Label {
                    text = DataSect.FREELANCER.name,
                    fontSize = Theme.fontSize.title or 22,
                    fontWeight = "bold",
                    fontColor = Theme.colors.textGold,
                },
                UI.Label {
                    text = DataSect.FREELANCER.desc,
                    fontSize = Theme.fontSize.small,
                    fontColor = Theme.colors.textLight,
                    textAlign = "center",
                    paddingHorizontal = 16,
                },
            },
        },

        -- 操作按钮
        UI.Panel {
            width = "100%",
            gap = 10,
            alignItems = "center",
            paddingVertical = 8,
            children = {
                Comp.BuildInkButton("创建宗门", function()
                    dialogState_.type = "create"
                    dialogState_.inputName = ""
                    M.Refresh()
                end, { width = "70%", fontSize = Theme.fontSize.body }),

                Comp.BuildSecondaryButton("浏览宗门", function()
                    dialogState_.type = "browse"
                    GameSect.RequestBrowseList()
                    -- 不立即 Refresh：等数据回来后由 refreshCallback 自动刷新
                    -- 避免先显示空弹窗再闪烁为有数据的弹窗
                end, { width = "70%", fontSize = Theme.fontSize.body }),
            },
        },

        -- 提示
        Comp.BuildCardPanel("温馨提示", {
            UI.Label {
                text = "创建宗门需要 " .. DataSect.CREATE_COST .. " 灵石。\n"
                    .. "你也可以浏览已有宗门，申请加入。",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textLight,
            },
        }),
    }
end

-- ============================================================================
-- 宗门成员列表（单行）
-- ============================================================================

local function BuildMemberRow(member, myRole)
    local roleLabel = DataSect.ROLE_LABEL[member.role] or "弟子"
    local roleColor = DataSect.ROLE_COLOR[member.role] or Theme.colors.textSecondary
    local isMe = member.userId == ClientNet.GetUserId()

    local actions = {}
    if not isMe then
        -- 踢人按钮
        if myRole and DataSect.ROLE_PERMISSION.kick[myRole] then
            local canKick = member.role == DataSect.ROLE.MEMBER
                or (myRole == DataSect.ROLE.LEADER and member.role ~= DataSect.ROLE.LEADER)
            if canKick then
                actions[#actions + 1] = Comp.BuildTextButton("逐出", function()
                    dialogState_.type = "confirm_kick"
                    dialogState_.targetUid = member.userId
                    dialogState_.targetName = member.name or "未知"
                    M.Refresh()
                end, { fontSize = Theme.fontSize.tiny, fontColor = Theme.colors.danger })
            end
        end
        -- 转让按钮（仅宗主可见）
        if myRole == DataSect.ROLE.LEADER and member.role ~= DataSect.ROLE.LEADER then
            actions[#actions + 1] = Comp.BuildTextButton("转让", function()
                dialogState_.type = "confirm_transfer"
                dialogState_.targetUid = member.userId
                dialogState_.targetName = member.name or "未知"
                M.Refresh()
            end, { fontSize = Theme.fontSize.tiny, fontColor = Theme.colors.gold })
        end
    end

    -- 周贡献标签
    local wc = member.weeklyContribution or 0
    local wcLabel = wc > 0 and ("本周:" .. wc) or ""

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingVertical = 6,
        paddingHorizontal = 8,
        gap = 8,
        borderBottomWidth = 1,
        borderColor = Theme.colors.divider,
        children = {
            -- 角色标签
            UI.Panel {
                paddingHorizontal = 6,
                paddingVertical = 2,
                borderRadius = 4,
                backgroundColor = { roleColor[1], roleColor[2], roleColor[3], 60 },
                children = {
                    UI.Label {
                        text = roleLabel,
                        fontSize = Theme.fontSize.tiny,
                        fontColor = roleColor,
                    },
                },
            },
            -- 名字
            UI.Label {
                text = (member.name or "未知") .. (isMe and " (我)" or ""),
                fontSize = Theme.fontSize.body,
                fontColor = isMe and Theme.colors.textGold or Theme.colors.textPrimary,
                flex = 1,
            },
            -- 周贡献
            wcLabel ~= "" and UI.Label {
                text = wcLabel,
                fontSize = Theme.fontSize.tiny,
                fontColor = { 120, 200, 140, 220 },
            } or nil,
            -- 操作
            UI.Panel {
                flexDirection = "row",
                gap = 4,
                children = actions,
            },
        },
    }
end

-- ============================================================================
-- 贡献进度条
-- ============================================================================

local function BuildContributionBar(current, target, label)
    local pct = target > 0 and math.min(current / target, 1.0) or 1.0

    return UI.Panel {
        width = "100%",
        gap = 4,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                children = {
                    UI.Label {
                        text = label or "宗门贡献",
                        fontSize = Theme.fontSize.small,
                        fontColor = Theme.colors.textGold,
                    },
                    UI.Label {
                        text = current .. " / " .. target,
                        fontSize = Theme.fontSize.small,
                        fontColor = Theme.colors.textLight,
                    },
                },
            },
            UI.Panel {
                width = "100%",
                height = 10,
                borderRadius = 5,
                backgroundColor = { 50, 45, 35, 255 },
                borderColor = Theme.colors.borderGold,
                borderWidth = 1,
                overflow = "hidden",
                children = {
                    UI.Panel {
                        width = tostring(math.floor(pct * 100)) .. "%",
                        height = "100%",
                        borderRadius = 5,
                        backgroundColor = { 120, 180, 80, 255 },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 每周贡献排名卡片
-- ============================================================================

function M.BuildWeeklyRankingCard(sectInfo)
    local ranking = sectInfo and sectInfo.lastWeeklyRanking
    if not ranking or #ranking == 0 then
        return Comp.BuildCardPanel("每周贡献排名", {
            UI.Label {
                text = "每周一结算上周贡献排名，前10名可获灵石/仙石奖励",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
            },
        })
    end

    -- 奖励说明
    local rewardDesc = {}
    for _, r in ipairs(DataSect.WEEKLY_REWARDS) do
        local txt = r.label .. ": " .. r.lingStone .. "灵石"
        if r.xianStone > 0 then
            txt = txt .. " + " .. r.xianStone .. "仙石"
        end
        rewardDesc[#rewardDesc + 1] = txt
    end

    local rows = {}
    -- 只显示前 10
    local showCount = math.min(#ranking, 10)
    for i = 1, showCount do
        local r = ranking[i]
        local reward = DataSect.GetWeeklyReward(i)
        local rankColor = i <= 3 and Theme.colors.textGold or Theme.colors.textLight
        rows[#rows + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            paddingVertical = 4,
            paddingHorizontal = 6,
            gap = 6,
            borderBottomWidth = (i < showCount) and 1 or 0,
            borderColor = Theme.colors.divider,
            children = {
                UI.Label {
                    text = "#" .. tostring(i),
                    fontSize = Theme.fontSize.small,
                    fontWeight = i <= 3 and "bold" or "normal",
                    fontColor = rankColor,
                    width = 30,
                },
                UI.Label {
                    text = r.name or "无名",
                    fontSize = Theme.fontSize.small,
                    fontColor = Theme.colors.textPrimary,
                    flex = 1,
                },
                UI.Label {
                    text = tostring(r.weeklyContribution or 0),
                    fontSize = Theme.fontSize.small,
                    fontColor = { 120, 200, 140, 220 },
                },
                reward and UI.Label {
                    text = reward.lingStone .. "灵石" .. (reward.xianStone > 0 and ("+" .. reward.xianStone .. "仙石") or ""),
                    fontSize = Theme.fontSize.tiny,
                    fontColor = Theme.colors.textGold,
                } or nil,
            },
        }
    end

    return Comp.BuildCardPanel("上周贡献排名", {
        UI.Label {
            text = "奖励: " .. table.concat(rewardDesc, " | "),
            fontSize = Theme.fontSize.tiny,
            fontColor = Theme.colors.textSecondary,
            paddingBottom = 4,
        },
        UI.Panel {
            width = "100%",
            maxHeight = 200,
            overflow = "scroll",
            children = rows,
        },
    })
end

-- ============================================================================
-- 宗门视图
-- ============================================================================

local function BuildSectView(p)
    local info = GameSect.GetSectInfo()
    local members = GameSect.GetMembers()
    local myRole = GameSect.GetMyRole()

    if not info then
        return { UI.Label { text = "加载中...", fontSize = Theme.fontSize.body, fontColor = Theme.colors.textLight } }
    end

    -- 成员行
    local memberRows = {}
    for _, m in ipairs(members) do
        memberRows[#memberRows + 1] = BuildMemberRow(m, myRole)
    end

    -- 管理按钮
    local manageButtons = {}

    -- 审批（宗主/长老）
    if GameSect.HasPermission("approve") then
        manageButtons[#manageButtons + 1] = Comp.BuildSecondaryButton("审批申请", function()
            dialogState_.type = "pending"
            GameSect.RequestPending()
        end, { width = "45%", fontSize = Theme.fontSize.small })
    end

    -- 编辑公告（宗主/长老）
    if GameSect.HasPermission("notice") then
        manageButtons[#manageButtons + 1] = Comp.BuildSecondaryButton("编辑公告", function()
            local Toast = require("ui_toast")
            Toast.Show("公告编辑功能即将开放")
        end, { width = "45%", fontSize = Theme.fontSize.small })
    end

    -- 退出宗门（非宗主）
    if myRole and myRole ~= DataSect.ROLE.LEADER then
        manageButtons[#manageButtons + 1] = Comp.BuildTextButton("退出宗门", function()
            dialogState_.type = "confirm_leave"
            M.Refresh()
        end, { fontSize = Theme.fontSize.small, fontColor = Theme.colors.danger })
    end

    local levelInfo = DataSect.GetLevelInfo(info.level or 1)
    local curLevel = info.level or 1
    local totalContrib = info.totalContribution or 0
    local isMaxLevel = curLevel >= #DataSect.LEVEL_TABLE

    -- 升级进度区域
    local upgradeChildren = {}
    if not isMaxLevel then
        local nextInfo = DataSect.LEVEL_TABLE[curLevel + 1]
        upgradeChildren[#upgradeChildren + 1] = BuildContributionBar(
            totalContrib, nextInfo.reqContribution, "升级进度")
        upgradeChildren[#upgradeChildren + 1] = UI.Label {
            text = "下一级: " .. nextInfo.name .. " (上限" .. nextInfo.maxMembers .. "人)",
            fontSize = Theme.fontSize.tiny,
            fontColor = Theme.colors.textSecondary,
        }
        -- 升级按钮（仅宗主、贡献达标）
        if myRole == DataSect.ROLE.LEADER and totalContrib >= nextInfo.reqContribution then
            upgradeChildren[#upgradeChildren + 1] = Comp.BuildInkButton("升级宗门", function()
                GameSect.UpgradeSect()
            end, { fontSize = Theme.fontSize.small })
        end
    else
        upgradeChildren[#upgradeChildren + 1] = UI.Label {
            text = "总贡献: " .. totalContrib .. "  (已达最高等级)",
            fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.textGold,
        }
    end

    -- 捐献按钮
    upgradeChildren[#upgradeChildren + 1] = Comp.BuildSecondaryButton("捐献灵石", function()
        dialogState_.type = "donate"
        dialogState_.donateAmount = ""
        M.Refresh()
    end, { fontSize = Theme.fontSize.small })

    -- 种族加成提示
    local raceBonus = DataSect.GetRaceBonus(info.race or "human", curLevel)
    local bonusText
    if raceBonus then
        bonusText = "种族加成: " .. raceBonus.desc
    elseif curLevel < 3 then
        bonusText = "种族加成: 宗门等级达到「兴盛」后激活"
    end

    return {
        -- 宗门标题
        UI.Panel {
            width = "100%",
            alignItems = "center",
            gap = 4,
            paddingVertical = 10,
            children = {
                UI.Label {
                    text = info.name or "宗门",
                    fontSize = Theme.fontSize.title or 22,
                    fontWeight = "bold",
                    fontColor = Theme.colors.textGold,
                },
                UI.Label {
                    text = (DataSect.RACE_LABEL[info.race or "human"] or "人族") .. " · "
                        .. (levelInfo.name or "草创") .. " · 成员 "
                        .. tostring(info.memberCount or #members) .. "/" .. tostring(levelInfo.maxMembers),
                    fontSize = Theme.fontSize.small,
                    fontColor = Theme.colors.textLight,
                },
                bonusText and UI.Label {
                    text = bonusText,
                    fontSize = Theme.fontSize.tiny,
                    fontColor = raceBonus and { 120, 220, 120, 255 } or Theme.colors.textSecondary,
                } or nil,
            },
        },

        -- 公告
        Comp.BuildCardPanel("宗门公告", {
            UI.Label {
                text = info.notice or DataSect.DEFAULT_NOTICE,
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textLight,
            },
        }),

        -- 等级与贡献
        Comp.BuildCardPanel("宗门建设", upgradeChildren),

        -- 宗门任务 + 宗门宝库入口
        Comp.BuildCardPanel("宗门活动", {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Label {
                        text = "完成任务获得贡献，宝库兑换物资",
                        fontSize = Theme.fontSize.small,
                        fontColor = Theme.colors.textLight,
                        flex = 1,
                    },
                },
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 8,
                paddingTop = 6,
                children = {
                    Comp.BuildInkButton("每日任务", function()
                        dialogState_.type = "tasks"
                        GameSect.RequestTasks()
                    end, { fontSize = Theme.fontSize.small, flex = 1 }),
                    Comp.BuildSecondaryButton("宗门宝库", function()
                        dialogState_.type = "shop"
                        M.Refresh()
                    end, { fontSize = Theme.fontSize.small, flex = 1 }),
                    Comp.BuildInkButton("宗门秘境", function()
                        dialogState_.type = "realm"
                        M.Refresh()
                    end, { fontSize = Theme.fontSize.small, flex = 1 }),
                },
            },
        }),

        -- 每周贡献排名（显示上周结果）
        M.BuildWeeklyRankingCard(info),

        -- 成员列表
        Comp.BuildSectionTitle("门派弟子 (" .. tostring(#members) .. ")"),
        UI.Panel {
            width = "100%",
            backgroundColor = Theme.colors.bgDark,
            borderRadius = Theme.radius.md,
            borderColor = Theme.colors.borderGold,
            borderWidth = 1,
            padding = 4,
            maxHeight = 250,
            overflow = "scroll",
            children = memberRows,
        },

        -- 管理按钮
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            flexWrap = "wrap",
            justifyContent = "center",
            gap = 10,
            paddingVertical = 8,
            children = manageButtons,
        },
    }
end

-- ============================================================================
-- 弹窗：创建宗门
-- ============================================================================

local function BuildCreateDialog()
    local p = GamePlayer.Get()
    local myRace = p and p.race or "human"
    local raceLabel = DataSect.RACE_LABEL[myRace] or "人族"

    local content = UI.Panel {
        width = "100%",
        gap = 10,
        children = {
            -- 种族提示
            UI.Panel {
                width = "100%",
                backgroundColor = { 60, 50, 30, 200 },
                borderRadius = 6,
                padding = 8,
                children = {
                    UI.Label {
                        text = "本宗门将为「" .. raceLabel .. "」宗门，仅同族修士可加入。",
                        fontSize = Theme.fontSize.small,
                        fontColor = Theme.colors.gold,
                    },
                },
            },
            UI.Label {
                text = "宗门名需 " .. DataSect.NAME_MIN_LEN .. "-" .. DataSect.NAME_MAX_LEN .. " 个字",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textLight,
            },
            UI.TextField {
                value = dialogState_.inputName,
                placeholder = "请输入宗门名称",
                onChange = function(self, val)
                    dialogState_.inputName = val
                end,
            },
            UI.Label {
                text = "消耗灵石: " .. DataSect.CREATE_COST,
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.gold,
            },
        },
    }

    return Comp.Dialog("创建宗门", content, {
        { text = "取消", onClick = CloseDialog },
        { text = "创建", onClick = function()
            local name = dialogState_.inputName or ""
            if name == "" then
                local Toast = require("ui_toast")
                Toast.Show("请输入宗门名称", { variant = "error" })
                return
            end
            GameSect.CreateSect(name)
            CloseDialog()
        end, primary = true },
    }, { onClose = CloseDialog })
end

-- ============================================================================
-- 弹窗：浏览宗门列表
-- ============================================================================

local function BuildBrowseRow(sect)
    local p = GamePlayer.Get()
    local myRace = p and p.race or "human"
    local sectRace = sect.race or "human"
    local sameRace = (myRace == sectRace)
    local raceLabel = DataSect.RACE_LABEL[sectRace] or "人族"

    -- 申请按钮：已有宗门不显示；异族显示灰色不可点击
    local applyBtn = nil
    if not GameSect.HasSect() then
        if sameRace then
            applyBtn = Comp.BuildTextButton("申请", function()
                GameSect.ApplyToSect(sect.sectId or sect.id)
            end, { fontSize = Theme.fontSize.small, fontColor = Theme.colors.accent })
        else
            applyBtn = UI.Label {
                text = "异族",
                fontSize = Theme.fontSize.tiny,
                fontColor = Theme.colors.textDisabled or { 100, 100, 100, 180 },
            }
        end
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingVertical = 6,
        paddingHorizontal = 8,
        gap = 6,
        borderBottomWidth = 1,
        borderColor = Theme.colors.divider,
        children = {
            -- 种族标签
            UI.Panel {
                paddingHorizontal = 4,
                paddingVertical = 1,
                borderRadius = 3,
                backgroundColor = sameRace and { 60, 80, 50, 180 } or { 60, 50, 50, 120 },
                children = {
                    UI.Label {
                        text = raceLabel,
                        fontSize = Theme.fontSize.tiny,
                        fontColor = sameRace and Theme.colors.textGold or Theme.colors.textSecondary,
                    },
                },
            },
            -- 宗门名
            UI.Label {
                text = sect.name or "？",
                fontSize = Theme.fontSize.body,
                fontWeight = "bold",
                fontColor = Theme.colors.textGold,
                flex = 1,
            },
            -- 宗主
            UI.Label {
                text = sect.leaderName or "",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
            },
            -- 人数
            UI.Label {
                text = tostring(sect.memberCount or 0) .. "人",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textLight,
            },
            -- 申请按钮
            applyBtn,
        },
    }
end

local function BuildBrowseDialog()
    local list = GameSect.GetBrowseList()
    local filter = dialogState_.browseRaceFilter  -- nil=全部

    -- 种族筛选 Tab
    local tabItems = {}
    local allTabs = { { key = nil, label = "全部" } }
    for _, raceKey in ipairs(DataSect.RACE_LIST) do
        allTabs[#allTabs + 1] = { key = raceKey, label = DataSect.RACE_LABEL[raceKey] or raceKey }
    end
    for _, tab in ipairs(allTabs) do
        local isActive = (filter == tab.key)
        tabItems[#tabItems + 1] = UI.Panel {
            paddingHorizontal = 10,
            paddingVertical = 4,
            borderRadius = 4,
            backgroundColor = isActive and { 80, 70, 40, 200 } or { 40, 40, 40, 100 },
            borderWidth = isActive and 1 or 0,
            borderColor = Theme.colors.gold,
            onClick = function()
                dialogState_.browseRaceFilter = tab.key
                M.Refresh()
            end,
            children = {
                UI.Label {
                    text = tab.label,
                    fontSize = Theme.fontSize.small,
                    fontColor = isActive and Theme.colors.textGold or Theme.colors.textSecondary,
                },
            },
        }
    end

    -- 过滤列表
    local filtered = {}
    for _, sect in ipairs(list) do
        if filter == nil or (sect.race or "human") == filter then
            filtered[#filtered + 1] = sect
        end
    end

    local rows = {}
    if #filtered == 0 then
        local emptyText = filter and ("暂无" .. (DataSect.RACE_LABEL[filter] or "") .. "宗门")
            or "暂无宗门，成为第一个创建者吧！"
        rows[#rows + 1] = UI.Label {
            text = emptyText,
            fontSize = Theme.fontSize.body,
            fontColor = Theme.colors.textSecondary,
            textAlign = "center",
            paddingVertical = 20,
        }
    else
        for _, sect in ipairs(filtered) do
            rows[#rows + 1] = BuildBrowseRow(sect)
        end
    end

    local content = UI.Panel {
        width = "100%",
        gap = 6,
        children = {
            -- 筛选 Tab 行
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 6,
                justifyContent = "center",
                paddingBottom = 4,
                children = tabItems,
            },
            -- 列表
            UI.Panel {
                width = "100%",
                maxHeight = 240,
                overflow = "scroll",
                children = rows,
            },
        },
    }

    return Comp.Dialog("浏览宗门", content, {
        { text = "关闭", onClick = CloseDialog, primary = true },
    }, { onClose = CloseDialog })
end

-- ============================================================================
-- 弹窗：审批申请列表
-- ============================================================================

local function BuildPendingRow(item)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingVertical = 6,
        paddingHorizontal = 8,
        gap = 6,
        borderBottomWidth = 1,
        borderColor = Theme.colors.divider,
        children = {
            UI.Label {
                text = item.name or "无名",
                fontSize = Theme.fontSize.body,
                fontColor = Theme.colors.textPrimary,
                flex = 1,
            },
            UI.Label {
                text = item.realm or "",
                fontSize = Theme.fontSize.small,
                fontColor = RealmColor(item.realm),
            },
            Comp.BuildTextButton("同意", function()
                GameSect.Approve(item.userId)
            end, { fontSize = Theme.fontSize.small, fontColor = Theme.colors.accent }),
            Comp.BuildTextButton("拒绝", function()
                GameSect.Reject(item.userId)
            end, { fontSize = Theme.fontSize.small, fontColor = Theme.colors.danger }),
        },
    }
end

local function BuildPendingDialog()
    local list = GameSect.GetPendingList()

    local rows = {}
    if #list == 0 then
        rows[#rows + 1] = UI.Label {
            text = "暂无待审批的申请",
            fontSize = Theme.fontSize.body,
            fontColor = Theme.colors.textSecondary,
            textAlign = "center",
            paddingVertical = 20,
        }
    else
        for _, item in ipairs(list) do
            rows[#rows + 1] = BuildPendingRow(item)
        end
    end

    local content = UI.Panel {
        width = "100%",
        maxHeight = 280,
        overflow = "scroll",
        children = rows,
    }

    return Comp.Dialog("入门审批", content, {
        { text = "关闭", onClick = CloseDialog, primary = true },
    }, { onClose = CloseDialog })
end

-- ============================================================================
-- 弹窗：捐献灵石
-- ============================================================================

local function BuildDonateDialog()
    local p = GamePlayer.Get()
    local balance = p and p.lingStone or 0
    local rate = DataSect.DONATE_RATE

    local content = UI.Panel {
        width = "100%",
        gap = 10,
        children = {
            UI.Label {
                text = "每 " .. rate .. " 灵石兑换 1 点贡献",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textLight,
            },
            UI.Label {
                text = "当前灵石: " .. tostring(balance),
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textGold,
            },
            UI.TextField {
                value = dialogState_.donateAmount,
                placeholder = "输入灵石数量 (最低" .. DataSect.DONATE_MIN .. ")",
                onChange = function(self, val)
                    dialogState_.donateAmount = val
                end,
            },
            UI.Label {
                text = "每日上限: " .. DataSect.DONATE_DAILY_MAX .. " 灵石",
                fontSize = Theme.fontSize.tiny,
                fontColor = Theme.colors.textSecondary,
            },
        },
    }

    return Comp.Dialog("捐献灵石", content, {
        { text = "取消", onClick = CloseDialog },
        { text = "捐献", onClick = function()
            local amount = tonumber(dialogState_.donateAmount) or 0
            if amount < DataSect.DONATE_MIN then
                local Toast = require("ui_toast")
                Toast.Show("最少捐献 " .. DataSect.DONATE_MIN .. " 灵石", { variant = "error" })
                return
            end
            GameSect.DonateLingStone(amount)
            CloseDialog()
        end, primary = true },
    }, { onClose = CloseDialog })
end

-- ============================================================================
-- 弹窗：宗门任务列表
-- ============================================================================

local function BuildTaskRow(task)
    local done = task.progress >= task.target
    local claimed = task.claimed

    -- 进度百分比
    local pct = task.target > 0 and math.min(task.progress / task.target, 1.0) or 0

    -- 右侧按钮/状态
    local rightWidget
    if claimed then
        rightWidget = UI.Label {
            text = "已领取",
            fontSize = Theme.fontSize.tiny,
            fontColor = Theme.colors.textSecondary,
        }
    elseif done then
        rightWidget = Comp.BuildTextButton("领取", function()
            GameSect.ClaimTask(task.id)
        end, { fontSize = Theme.fontSize.small, fontColor = Theme.colors.accent })
    else
        rightWidget = UI.Label {
            text = tostring(task.progress) .. "/" .. tostring(task.target),
            fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.textLight,
        }
    end

    return UI.Panel {
        width = "100%",
        paddingVertical = 8,
        paddingHorizontal = 8,
        gap = 4,
        borderBottomWidth = 1,
        borderColor = Theme.colors.divider,
        opacity = claimed and 0.5 or 1.0,
        children = {
            -- 上行：名称 + 奖励 + 操作
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                children = {
                    UI.Label {
                        text = task.name or "",
                        fontSize = Theme.fontSize.body,
                        fontWeight = "bold",
                        fontColor = claimed and Theme.colors.textSecondary or Theme.colors.textPrimary,
                        flex = 1,
                    },
                    UI.Label {
                        text = "+" .. tostring(task.reward) .. "贡献",
                        fontSize = Theme.fontSize.tiny,
                        fontColor = Theme.colors.textGold,
                    },
                    rightWidget,
                },
            },
            -- 下行：描述 + 进度条
            UI.Label {
                text = task.desc or "",
                fontSize = Theme.fontSize.tiny,
                fontColor = Theme.colors.textSecondary,
            },
            -- 进度条
            UI.Panel {
                width = "100%",
                height = 6,
                borderRadius = 3,
                backgroundColor = { 50, 45, 35, 255 },
                overflow = "hidden",
                children = {
                    UI.Panel {
                        width = tostring(math.floor(pct * 100)) .. "%",
                        height = "100%",
                        borderRadius = 3,
                        backgroundColor = claimed and { 80, 80, 80, 200 }
                            or done and { 120, 220, 80, 255 }
                            or { 80, 140, 200, 255 },
                    },
                },
            },
        },
    }
end

local function BuildTasksDialog()
    local taskData = GameSect.GetTaskData()

    local rows = {}
    if not taskData or not taskData.tasks then
        rows[#rows + 1] = UI.Label {
            text = "加载中...",
            fontSize = Theme.fontSize.body,
            fontColor = Theme.colors.textSecondary,
            textAlign = "center",
            paddingVertical = 20,
        }
    else
        for _, task in ipairs(taskData.tasks) do
            rows[#rows + 1] = BuildTaskRow(task)
        end

        -- 全部完成额外奖励
        local allDone = true
        for _, task in ipairs(taskData.tasks) do
            if not task.claimed then
                allDone = false
                break
            end
        end

        rows[#rows + 1] = UI.Panel {
            width = "100%",
            paddingVertical = 10,
            alignItems = "center",
            gap = 6,
            children = {
                UI.Panel {
                    width = "100%",
                    height = 1,
                    backgroundColor = Theme.colors.divider,
                },
                UI.Label {
                    text = "全部完成额外奖励: +" .. DataSect.TASK_BONUS_ALL .. "贡献",
                    fontSize = Theme.fontSize.small,
                    fontColor = Theme.colors.textGold,
                },
                (allDone and not taskData.allClaimed)
                    and Comp.BuildInkButton("领取额外奖励", function()
                        GameSect.ClaimAllBonus()
                    end, { fontSize = Theme.fontSize.small })
                    or (taskData.allClaimed
                        and UI.Label {
                            text = "已领取",
                            fontSize = Theme.fontSize.small,
                            fontColor = Theme.colors.textSecondary,
                        }
                        or UI.Label {
                            text = "完成所有任务后可领取",
                            fontSize = Theme.fontSize.tiny,
                            fontColor = Theme.colors.textSecondary,
                        }),
            },
        }
    end

    local content = UI.Panel {
        width = "100%",
        maxHeight = 320,
        overflow = "scroll",
        children = rows,
    }

    return Comp.Dialog("每日宗门任务", content, {
        { text = "刷新", onClick = function()
            GameSect.RequestTasks()
        end },
        { text = "关闭", onClick = CloseDialog, primary = true },
    }, { onClose = CloseDialog })
end

-- ============================================================================
-- 弹窗：宗门宝库
-- ============================================================================

local function BuildShopRow(shopItem, sectLevel, myContrib)
    local locked = shopItem.reqLevel and sectLevel < shopItem.reqLevel
    local lvInfo = locked and DataSect.GetLevelInfo(shopItem.reqLevel) or nil
    local cantAfford = myContrib < shopItem.cost

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingVertical = 8,
        paddingHorizontal = 8,
        gap = 6,
        borderBottomWidth = 1,
        borderColor = Theme.colors.divider,
        opacity = locked and 0.4 or 1.0,
        children = {
            -- 商品名 + 描述
            UI.Panel {
                flex = 1,
                gap = 2,
                children = {
                    UI.Label {
                        text = shopItem.name,
                        fontSize = Theme.fontSize.body,
                        fontWeight = "bold",
                        fontColor = locked and Theme.colors.textSecondary or Theme.colors.textPrimary,
                    },
                    UI.Label {
                        text = shopItem.desc or "",
                        fontSize = Theme.fontSize.tiny,
                        fontColor = Theme.colors.textSecondary,
                    },
                    locked and UI.Label {
                        text = "需要宗门等级: " .. (lvInfo and lvInfo.name or ""),
                        fontSize = Theme.fontSize.tiny,
                        fontColor = Theme.colors.danger,
                    } or nil,
                    shopItem.dailyLimit and UI.Label {
                        text = "每日限购" .. shopItem.dailyLimit .. "次",
                        fontSize = Theme.fontSize.tiny,
                        fontColor = Theme.colors.textSecondary,
                    } or nil,
                },
            },
            -- 价格
            UI.Label {
                text = tostring(shopItem.cost) .. "贡献",
                fontSize = Theme.fontSize.small,
                fontColor = cantAfford and Theme.colors.danger or Theme.colors.textGold,
            },
            -- 购买按钮
            (not locked) and Comp.BuildTextButton("兑换", function()
                GameSect.BuyShopItem(shopItem.id)
            end, {
                fontSize = Theme.fontSize.small,
                fontColor = cantAfford and Theme.colors.textSecondary or Theme.colors.accent,
            }) or nil,
        },
    }
end

local function BuildShopDialog()
    local info = GameSect.GetSectInfo()
    local members = GameSect.GetMembers()
    local sectLevel = info and info.level or 1

    -- 查找自己的贡献
    local myContrib = 0
    local myUid = ClientNet.GetUserId()
    for _, m in ipairs(members) do
        if m.userId == myUid then
            myContrib = m.contribution or 0
            break
        end
    end

    local rows = {}
    for _, shopItem in ipairs(DataSect.SECT_SHOP_ITEMS) do
        rows[#rows + 1] = BuildShopRow(shopItem, sectLevel, myContrib)
    end

    local content = UI.Panel {
        width = "100%",
        gap = 4,
        children = {
            UI.Label {
                text = "我的贡献: " .. tostring(myContrib),
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textGold,
                paddingBottom = 4,
            },
            UI.Panel {
                width = "100%",
                maxHeight = 320,
                overflow = "scroll",
                children = rows,
            },
        },
    }

    return Comp.Dialog("宗门宝库", content, {
        { text = "关闭", onClick = CloseDialog, primary = true },
    }, { onClose = CloseDialog })
end

-- ============================================================================
-- 弹窗：宗门秘境（选难度 / 战斗结果）
-- ============================================================================

--- 构建秘境难度选择行
local function BuildRealmDiffRow(diff, sectLevel, myContrib)
    local locked = diff.reqLevel and sectLevel < diff.reqLevel
    local cantAfford = myContrib < diff.cost

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingVertical = 8,
        paddingHorizontal = 6,
        gap = 8,
        opacity = locked and 0.4 or 1.0,
        children = {
            -- 名称+描述
            UI.Panel {
                flex = 1, flexShrink = 1,
                children = {
                    UI.Label {
                        text = diff.name .. "（" .. diff.floors .. "层）",
                        fontSize = Theme.fontSize.base,
                        fontColor = Theme.colors.textPrimary,
                    },
                    UI.Label {
                        text = diff.desc,
                        fontSize = Theme.fontSize.xs,
                        fontColor = Theme.colors.textLight,
                        marginTop = 2,
                    },
                    UI.Label {
                        text = "每日" .. diff.dailyLimit .. "次 | 消耗贡献" .. diff.cost,
                        fontSize = Theme.fontSize.xs,
                        fontColor = Theme.colors.textLight,
                        marginTop = 2,
                    },
                    locked and UI.Label {
                        text = "需宗门等级" .. diff.reqLevel,
                        fontSize = Theme.fontSize.xs,
                        fontColor = Theme.colors.danger,
                        marginTop = 2,
                    } or nil,
                },
            },
            -- 进入按钮
            Comp.BuildInkButton(locked and "未解锁" or "进入", function()
                if locked then return end
                if cantAfford then
                    local Toast = require("ui_toast")
                    Toast.Show("贡献不足", { variant = "error" })
                    return
                end
                GameSect.EnterRealm(diff.id)
                dialogState_.type = "realm_waiting"
                M.Refresh()
            end, {
                fontSize = Theme.fontSize.small,
                disabled = locked,
            }),
        },
    }
end

local function BuildRealmDialog()
    local info = GameSect.GetSectInfo()
    local members = GameSect.GetMembers()
    local sectLevel = info and info.level or 1
    local myContrib = 0
    local myUid = ClientNet.GetUserId()
    for _, m in ipairs(members) do
        if m.userId == myUid then myContrib = m.contribution or 0; break end
    end

    local rows = {}
    for _, diff in ipairs(DataSect.REALM_DIFFICULTIES) do
        rows[#rows + 1] = BuildRealmDiffRow(diff, sectLevel, myContrib)
    end

    local content = UI.Panel {
        width = "100%",
        children = {
            UI.Label {
                text = "当前贡献: " .. myContrib,
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.golden,
                marginBottom = 8,
            },
            table.unpack(rows),
        },
    }

    return Comp.Dialog("宗门秘境", content, {
        { text = "关闭", onClick = CloseDialog, primary = true },
    }, { onClose = CloseDialog })
end

--- 等待秘境结果（loading 状态）
local function BuildRealmWaitingDialog()
    local content = UI.Panel {
        width = "100%",
        alignItems = "center",
        paddingVertical = 20,
        children = {
            UI.Label {
                text = "秘境探索中...",
                fontSize = Theme.fontSize.base,
                fontColor = Theme.colors.textPrimary,
            },
        },
    }
    return Comp.Dialog("宗门秘境", content, {}, { onClose = function() end })
end

--- 构建秘境战斗结果弹窗
local function BuildRealmResultDialog()
    local result = GameSect.GetRealmResult()
    if not result then
        CloseDialog()
        return nil
    end

    local children = {}
    -- 总体结果
    local allCleared = result.cleared >= result.floors
    children[#children + 1] = UI.Label {
        text = result.diffName .. " - " .. (allCleared and "全部通关!" or ("通关 " .. result.cleared .. "/" .. result.floors .. " 层")),
        fontSize = Theme.fontSize.base,
        fontColor = allCleared and Theme.colors.golden or Theme.colors.textPrimary,
        textAlign = "center",
        width = "100%",
        marginBottom = 8,
    }

    -- 每层战斗结果
    for _, fight in ipairs(result.fights or {}) do
        children[#children + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            paddingVertical = 3,
            gap = 6,
            children = {
                UI.Label {
                    text = "第" .. fight.floor .. "层",
                    fontSize = Theme.fontSize.xs,
                    fontColor = Theme.colors.textLight,
                    width = 48,
                },
                UI.Label {
                    text = fight.enemy,
                    fontSize = Theme.fontSize.xs,
                    fontColor = Theme.colors.textPrimary,
                    flex = 1, flexShrink = 1,
                },
                UI.Label {
                    text = fight.win and "胜" or "败",
                    fontSize = Theme.fontSize.xs,
                    fontColor = fight.win and Theme.colors.success or Theme.colors.danger,
                },
            },
        }
    end

    -- 奖励汇总
    children[#children + 1] = UI.Panel {
        width = "100%", height = 1,
        backgroundColor = Theme.colors.divider,
        marginVertical = 8,
    }
    children[#children + 1] = UI.Label {
        text = "-- 奖励 --",
        fontSize = Theme.fontSize.small,
        fontColor = Theme.colors.golden,
        textAlign = "center",
        width = "100%",
    }
    if (result.rewardLing or 0) > 0 then
        children[#children + 1] = UI.Label {
            text = "灵石 +" .. result.rewardLing,
            fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.textPrimary,
            textAlign = "center",
            width = "100%",
            marginTop = 4,
        }
    end
    if (result.rewardContrib or 0) > 0 then
        children[#children + 1] = UI.Label {
            text = "贡献 +" .. result.rewardContrib,
            fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.textPrimary,
            textAlign = "center",
            width = "100%",
            marginTop = 2,
        }
    end
    -- 额外掉落
    for _, bi in ipairs(result.bonusItems or {}) do
        children[#children + 1] = UI.Label {
            text = bi.name,
            fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.golden,
            textAlign = "center",
            width = "100%",
            marginTop = 2,
        }
    end

    local content = UI.ScrollView {
        width = "100%",
        maxHeight = 350,
        children = {
            UI.Panel {
                width = "100%",
                children = children,
            },
        },
    }

    return Comp.Dialog("秘境结果", content, {
        { text = "确定", onClick = function()
            GameSect.ClearRealmResult()
            CloseDialog()
        end, primary = true },
    }, { onClose = function()
        GameSect.ClearRealmResult()
        CloseDialog()
    end })
end

-- ============================================================================
-- 确认弹窗（退出/踢人/转让）
-- ============================================================================

local function BuildConfirmDialog(title, message, onConfirm)
    return Comp.Dialog(title, message, {
        { text = "取消", onClick = CloseDialog },
        { text = "确认", onClick = function()
            onConfirm()
            CloseDialog()
        end, primary = true },
    }, { onClose = CloseDialog })
end

-- ============================================================================
-- 入口
-- ============================================================================

--- 页面进入时重置标志（由 Router 或外部调用）
function M.OnEnter()
    dataRequested_ = false
end

function M.Build(payload)
    EnsureInit()

    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    -- 首次进入宗门页 → 拉取数据（仅一次，防止刷新循环）
    if not dataRequested_ then
        dataRequested_ = true
        GameSect.RequestSectInfo()
    end

    -- 根据宗门状态决定视图
    local contentChildren
    if GameSect.HasSect() then
        contentChildren = BuildSectView(p)
    else
        contentChildren = BuildFreelancerView(p)
    end

    -- 弹窗层
    local dialog = nil
    if dialogState_.type == "create" then
        dialog = BuildCreateDialog()
    elseif dialogState_.type == "browse" then
        dialog = BuildBrowseDialog()
    elseif dialogState_.type == "pending" then
        dialog = BuildPendingDialog()
    elseif dialogState_.type == "confirm_leave" then
        dialog = BuildConfirmDialog("退出宗门",
            "确定要退出当前宗门吗？退出后需要重新申请。",
            function() GameSect.LeaveSect() end)
    elseif dialogState_.type == "confirm_kick" then
        dialog = BuildConfirmDialog("逐出弟子",
            "确定将 " .. dialogState_.targetName .. " 逐出宗门吗？",
            function() GameSect.KickMember(dialogState_.targetUid) end)
    elseif dialogState_.type == "confirm_transfer" then
        dialog = BuildConfirmDialog("转让宗主",
            "确定将宗主之位转让给 " .. dialogState_.targetName .. " 吗？此操作不可撤销。",
            function() GameSect.Transfer(dialogState_.targetUid) end)
    elseif dialogState_.type == "donate" then
        dialog = BuildDonateDialog()
    elseif dialogState_.type == "tasks" then
        dialog = BuildTasksDialog()
    elseif dialogState_.type == "shop" then
        dialog = BuildShopDialog()
    elseif dialogState_.type == "realm" then
        dialog = BuildRealmDialog()
    elseif dialogState_.type == "realm_waiting" then
        local rr = GameSect.GetRealmResult()
        if rr then
            dialogState_.type = "realm_result"
            dialog = BuildRealmResultDialog()
        else
            dialog = BuildRealmWaitingDialog()
        end
    elseif dialogState_.type == "realm_result" then
        dialog = BuildRealmResultDialog()
    end

    local page = Comp.BuildPageShell("sect", p, contentChildren, Router.HandleNavigate)

    -- 弹窗叠加（绝对定位覆盖整页，需追加到 pageShell 而非 ScrollView 内容）
    if dialog then
        page:AddChild(dialog)
    end

    return page
end

return M
