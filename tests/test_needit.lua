-- Minimal WoW API mock to exercise NeedIt's tooltip verdicts outside the game.
-- Run from the repo root:  lua tests/test_needit.lua NeedIt.lua
local ADDON = arg[1]

-- item database: link -> { equipLoc, classID, subID, stats, lines }
local ITEMS = {
  staff      = { "INVTYPE_2HWEAPON", 2, 10, { ITEM_MOD_INTELLECT_SHORT = 10 }, { "Staff", "20.0 damage per second", "Equip: Increases damage done by magical spells and effects by up to 10." } },
  castDagger = { "INVTYPE_WEAPON",   2, 15, { ITEM_MOD_INTELLECT_SHORT = 4 },  { "Dagger", "10.0 damage per second", "Equip: Increases damage done by magical spells and effects by up to 5." } },
  mace1h     = { "INVTYPE_WEAPON",   2, 4,  { ITEM_MOD_INTELLECT_SHORT = 8 },  { "Mace", "15.0 damage per second" } },
  mace1hBig  = { "INVTYPE_WEAPON",   2, 4,  { ITEM_MOD_INTELLECT_SHORT = 14 }, { "Mace", "15.0 damage per second" } },
  shield     = { "INVTYPE_SHIELD",   4, 6,  { ITEM_MOD_INTELLECT_SHORT = 1 },  { "Shield" } },
  sword1h    = { "INVTYPE_WEAPON",   2, 7,  { ITEM_MOD_AGILITY_SHORT = 5 },    { "Sword", "20.0 damage per second" } },
  sword1hW   = { "INVTYPE_WEAPON",   2, 7,  { ITEM_MOD_STRENGTH_SHORT = 5 },   { "Sword", "20.0 damage per second" } },
  axe2h      = { "INVTYPE_2HWEAPON", 2, 1,  { ITEM_MOD_STRENGTH_SHORT = 12 },  { "Axe", "30.0 damage per second" } },
  plateChest = { "INVTYPE_CHEST",    4, 4,  { ITEM_MOD_STRENGTH_SHORT = 10 },  { "Plate" } },
  mailChest  = { "INVTYPE_CHEST",    4, 3,  { ITEM_MOD_STRENGTH_SHORT = 10 },  { "Mail" } },
  axe1h      = { "INVTYPE_WEAPON",   2, 0,  { ITEM_MOD_AGILITY_SHORT = 5 },    { "Axe", "20.0 damage per second" } },
  rapRing    = { "INVTYPE_FINGER",   4, 0,  {}, { "Ring", "Equip: +30 ranged Attack Power." } },
  feralStaff = { "INVTYPE_2HWEAPON", 2, 10, {}, { "Staff", "10.0 damage per second", "Equip: Increases attack power by 200 in Cat, Bear, Dire Bear, and Moonkin forms only." } },
  libram     = { "INVTYPE_RELIC",    4, 7,  { ITEM_MOD_INTELLECT_SHORT = 3 }, { "Libram" } },
  clothChest = { "INVTYPE_CHEST",    4, 1,  { ITEM_MOD_INTELLECT_SHORT = 5, ITEM_MOD_SPIRIT_SHORT = 5 }, { "Cloth" } },
}

local state
local MODERN = { "GetSpecialization", "GetSpecializationInfo", "GetNumSpecializations", "C_TooltipInfo",
                 "C_SpecializationInfo", "C_ClassTalents", "C_Traits" }
local TESTDIR = (arg[0] or ""):match("^(.*[/\\])") or ""
local FOREVER_HUNTER = dofile(TESTDIR .. "forever_hunter_tree.lua")

-- WoW Forever: one class-wide spec, no Classic talent-tab API, all trees in one C_Traits tree.
-- s.forever = { [nodeName] = ranks } overrides the captured ranks (nil = use the real capture).
local function mockForever(s)
  GetNumTalentTabs, GetTalentTabInfo = nil, nil
  C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 1485, s.class:sub(1,1) .. s.class:sub(2):lower() end,
    GetNumSpecializationsForClassID = function() return 1 end,
  }
  C_ClassTalents = { GetActiveConfigID = function() return 539272 end }
  local byID = {}
  for _, n in ipairs(FOREVER_HUNTER) do
    local ranks = n[3]
    if s.forever.ranks then ranks = s.forever.ranks[n[5]] or 0 end
    byID[n[1]] = { ID = n[1], posX = n[2], ranksPurchased = ranks, currentRank = ranks, groupIDs = n[4], isVisible = true }
  end
  C_Traits = {
    GetConfigInfo = function() return { ID = 539272, treeIDs = { 1091 } } end,
    GetTreeNodes = function() local ids = {} for _, n in ipairs(FOREVER_HUNTER) do ids[#ids + 1] = n[1] end return ids end,
    GetNodeInfo = function(_, id) return byID[id] end,
  }
end

local function reset(s)
  state = s
  state.equipped = state.equipped or {}
  for _, k in ipairs(MODERN) do _G[k] = nil end
  GetNumTalentTabs = function() return 3 end
  if s.forever then mockForever(s) return end
  if s.modernSpec then  -- retail-style spec API: { index, name, count }
    GetSpecialization = function() return s.modernSpec[1] end
    GetSpecializationInfo = function() return 100, s.modernSpec[2] end
    GetNumSpecializations = function() return s.modernSpec[3] end
  end
  if s.tabNames then
    GetTalentTabInfo = function(i) return s.tabNames[i], "icon", (s.talents or {0,0,0})[i], "file" end
  else
    GetTalentTabInfo = function(i) return "Tree" .. i, "icon", (s.talents or {0,0,0})[i], "file" end
  end
  if s.tooltipInfo then
    C_TooltipInfo = { GetHyperlink = function(link)
      local lines = { { leftText = "Name" } }
      for _, l in ipairs(ITEMS[link][5]) do lines[#lines + 1] = { leftText = l } end
      return { lines = lines }
    end }
  end
end

function GetItemInfoInstant(link) local i = ITEMS[link] return 1, "", "", i[1], 0, i[2], i[3] end
function GetItemStats(link) return ITEMS[link][4] end
function UnitClass() return state.class:sub(1,1) .. state.class:sub(2):lower(), state.class end
function UnitName() return "Tester" end
function GetRealmName() return "Realm" end
function UnitLevel() return state.level end
function GetInventoryItemLink(_, slot) return state.equipped[slot] end
function GetNumTalentTabs() return 3 end
function GetTalentTabInfo(i) return "Tree" .. i, "icon", (state.talents or {0,0,0})[i], "file" end
function CanDualWield() return state.dualWield end
local printed = {}
function print(m) printed[#printed + 1] = m end
function GetBuildInfo() return "1.60.1", "70058", "Sep 2026", 16001 end
function GetContainerItemLink(bag, slot) return state.bags and state.bags[slot] end
local bagButtons = {}
local function newButton(id)
  local b = { id = id }
  function b:GetID() return self.id end
  function b:GetBagID() return 0 end
  function b:CreateTexture()
    local t = { shown = false }
    function t:SetSize() end function t:SetPoint() end function t:SetColorTexture(r, g) self.color = g > 0.5 and "green" or "red" end
    function t:Show() self.shown = true end function t:Hide() self.shown = false end
    return t
  end
  return b
end
for i = 1, 3 do bagButtons[i] = newButton(i) end
ContainerFrame1 = { shown = true, IsShown = function(self) return self.shown end, GetID = function() return 0 end,
  HookScript = function() end,
  EnumerateValidItems = function() return ipairs(bagButtons) end }
UIParent = {}
Enum = { TooltipDataType = { Item = 0 } }

local postCall
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) postCall = fn end }

local eventHandler
function CreateFrame(kind, name)
  if kind == "GameTooltip" then
    local tip = { lines = {} }
    function tip:SetOwner() end
    function tip:ClearLines() self.lines = {} end
    function tip:SetHyperlink(link)
      self.lines = { "Name" }
      for _, l in ipairs(ITEMS[link][5]) do self.lines[#self.lines + 1] = l end
      for i, l in ipairs(self.lines) do _G[name .. "TextLeft" .. i] = { GetText = function() return l end } end
    end
    function tip:NumLines() return #self.lines end
    return tip
  end
  return { RegisterEvent = function(_, ev) end,
           SetScript = function(_, ev, fn) if ev == "OnEvent" then eventHandler = fn end end }
end

local function newTip() return { lines = {}, AddLine = function(self, t) self.lines[#self.lines + 1] = t end,
                                  Show = function() end, HookScript = function() end } end
GameTooltip = newTip()
ItemRefTooltip = newTip()
SlashCmdList = {}

dofile(ADDON)
eventHandler(nil, "PLAYER_LOGIN")

local function strip(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function hover(link)
  eventHandler(nil, "PLAYER_EQUIPMENT_CHANGED") -- invalidate caches between scenarios
  NeedItDB.chars = nil
  GameTooltip.lines, GameTooltip.__needit = {}, nil
  postCall(GameTooltip, { hyperlink = link })
  return strip(table.concat(GameTooltip.lines, " / "))
end

local pass, fail = 0, 0
local function check(title, s, link, expect)
  reset(s)
  local out = hover(link)
  local ok = out:find(expect, 1, true) ~= nil
  if ok then pass = pass + 1 else fail = fail + 1 end
  print_ = io.write((ok and "PASS " or "FAIL ") .. title .. "\n     -> " .. out .. "\n")
end

-- 1. Mage with a staff: a 1H dagger must be compared to the staff, not the empty off hand
check("Mage w/ staff vs weaker 1H dagger (not 'empty slot')",
  { class = "MAGE", level = 30, talents = {0,0,20}, dualWield = false, equipped = { [16] = "staff" } },
  "castDagger", "GREED")
-- 2. Holy paladin w/ shield: 1H mace compared to main hand, not the shield
check("Paladin w/ shield: 1H mace compared to main hand",
  { class = "PALADIN", level = 30, talents = {20,0,0}, dualWield = false, equipped = { [16] = "mace1hBig", [17] = "shield" } },
  "mace1h", "not an upgrade")
-- 3. Rogue with empty off hand: 1H really is an upgrade for the empty slot
check("Rogue w/ empty off hand: 1H fills it",
  { class = "ROGUE", level = 30, talents = {0,20,0}, dualWield = true, equipped = { [16] = "sword1h" } },
  "sword1h", "empty slot")
-- 4. Prot warrior w/ shield can dual wield but off hand is a shield -> compare main hand only
check("Warrior w/ shield: 1H compared to main hand only",
  { class = "WARRIOR", level = 30, talents = {0,0,20}, dualWield = true, equipped = { [16] = "sword1hW", [17] = "shield" } },
  "sword1hW", "not an upgrade")
-- 5. Two-hander compared to main hand + off hand combined
check("Warrior 2H vs MH+OH combined",
  { class = "WARRIOR", level = 30, talents = {20,0,0}, dualWield = true, equipped = { [16] = "sword1hW", [17] = "sword1hW" } },
  "axe2h", "vs equipped")
-- 6. Level 25 warrior: plate not yet wearable
check("Level 25 warrior hovering plate",
  { class = "WARRIOR", level = 25, talents = {15,0,0}, dualWield = true },
  "plateChest", "can't wear plate until level 40")
-- 7. Level 25 warrior: mail is their best armor, so it's a NEED
check("Level 25 warrior hovering mail",
  { class = "WARRIOR", level = 25, talents = {15,0,0}, dualWield = true },
  "mailChest", "NEED")
-- 8. Level 45 warrior: mail is now lower armor type
check("Level 45 warrior hovering mail",
  { class = "WARRIOR", level = 45, talents = {30,0,0}, dualWield = true },
  "mailChest", "lower armor type")
-- 9. Level 45 warrior: plate now fine
check("Level 45 warrior hovering plate",
  { class = "WARRIOR", level = 45, talents = {30,0,0}, dualWield = true },
  "plateChest", "NEED")
-- 10. Level 5 priest, no talents: uses leveling default instead of "Couldn't detect"
check("Level 5 priest, no talents",
  { class = "PRIEST", level = 5, talents = {0,0,0}, dualWield = false },
  "clothChest", "assuming Shadow")
-- 11. Level 5 mage, no talents: still gets a real verdict
check("Level 5 mage, no talents -> NEED",
  { class = "MAGE", level = 5, talents = {0,0,0}, dualWield = false },
  "clothChest", "NEED")
-- 12. Cloth class still can't wear plate
check("Mage hovering plate",
  { class = "MAGE", level = 50, talents = {0,0,31}, dualWield = false },
  "plateChest", "can't wear this armor type")

-- v0.4 checks
check("Rogue can't use axes",
  { class = "ROGUE", level = 30, talents = {0,20,0}, dualWield = true }, "axe1h", "can't use this weapon type")
check("Warrior: ranged AP is wasted",
  { class = "WARRIOR", level = 30, talents = {20,0,0}, dualWield = true }, "rapRing", "Wasted: Ranged Attack Power")
check("Hunter: ranged AP is good",
  { class = "HUNTER", level = 30, talents = {20,0,0}, dualWield = true }, "rapRing", "Good: +30 Ranged Attack Power")
check("Feral druid values feral AP",
  { class = "DRUID", level = 30, talents = {0,20,0}, dualWield = false }, "feralStaff", "Good: +200 Feral Attack Power")
check("Enhancement shaman: feral AP wasted",
  { class = "SHAMAN", level = 30, talents = {0,20,0}, dualWield = false }, "feralStaff", "Wasted: Feral Attack Power")
check("Mage can't use a libram",
  { class = "MAGE", level = 30, talents = {0,0,20}, dualWield = false }, "libram", "Librams are for another class")
check("Paladin can use a libram",
  { class = "PALADIN", level = 30, talents = {20,0,0}, dualWield = false }, "libram", "Holy")
check("Modern spec API: rogue 'Outlaw' -> Combat",
  { class = "ROGUE", level = 30, dualWield = true, modernSpec = { 2, "Outlaw", 3 } }, "sword1h", "Combat")
check("Modern spec API: 4-spec druid index 3 -> Guardian",
  { class = "DRUID", level = 30, dualWield = false, modernSpec = { 3, "Guardian", 4 } }, "feralStaff", "Guardian")
check("Talent trees in unexpected order matched by name",
  { class = "MAGE", level = 30, dualWield = false, tabNames = { "Frost", "Fire", "Arcane" }, talents = {20,0,0} }, "clothChest", "Frost")
check("Modern spec API returning bogus index falls back to talents/default",
  { class = "MAGE", level = 5, dualWield = false, modernSpec = { 5, "Initial", 3 } }, "clothChest", "assuming Frost")
check("C_TooltipInfo path reads stats",
  { class = "HUNTER", level = 30, talents = {20,0,0}, dualWield = true, tooltipInfo = true }, "rapRing", "+30 Ranged Attack Power")

-- WoW Forever talent tree (real capture: 11 points in Beast Mastery)
check("Forever: real Hunter tree -> Beast Mastery (auto, not leveling default)",
  { class = "HUNTER", level = 20, dualWield = true, forever = {} }, "rapRing", "Upgrade for Beast Mastery (empty slot) / Good")
check("Forever: points in Marksmanship talents -> Marksmanship",
  { class = "HUNTER", level = 20, dualWield = true, forever = { ranks = { ["Lethal Attacks"] = 5, ["Efficiency"] = 5, ["Deadly Aspects"] = 1 } } },
  "rapRing", "Upgrade for Marksmanship")
check("Forever: points in Survival talents -> Survival",
  { class = "HUNTER", level = 20, dualWield = true, forever = { ranks = { ["Deflection"] = 5, ["Surefooted"] = 3 } } },
  "rapRing", "Upgrade for Survival")
check("Forever: no points spent at level 5 -> leveling default",
  { class = "HUNTER", level = 5, dualWield = true, forever = { ranks = {} } },
  "rapRing", "No talents yet - assuming Beast Mastery")
reset({ class = "HUNTER", level = 20, dualWield = true, forever = {} })
eventHandler(nil, "PLAYER_EQUIPMENT_CHANGED")
printed = {}
SlashCmdList.NEEDIT("debug")
local dbg = table.concat(printed, "\n")
local okDbg = dbg:find("Talent tree (Forever-style): Beast Mastery 11, Marksmanship 0, Survival 0", 1, true)
  and dbg:find("spec Beast Mastery (auto)", 1, true)
io.write((okDbg and "PASS " or "FAIL ") .. "Forever: /needit debug shows per-tree points\n")
if not okDbg then io.write(dbg, "\n") end
if okDbg then pass = pass + 1 else fail = fail + 1 end

-- event-driven bag markers
reset({ class = "WARRIOR", level = 30, talents = {20,0,0}, dualWield = true, bags = { "plateChest", "mailChest", "clothChest" } })
NeedItDB.chars = nil
eventHandler(nil, "PLAYER_EQUIPMENT_CHANGED")
for _, b in ipairs(bagButtons) do b.needitMark = nil end
eventHandler(nil, "BAG_UPDATE_DELAYED")
local m = {}
for i, b in ipairs(bagButtons) do m[i] = b.needitMark and b.needitMark.shown and b.needitMark.color or "none" end
local okMarks = m[1] == "none" and m[2] == "green" and m[3] == "red"   -- plate@30 = GREED (no mark), mail = NEED, cloth = PASS
io.write((okMarks and "PASS " or "FAIL ") .. "Bag markers refresh on BAG_UPDATE_DELAYED\n     -> " .. table.concat(m, ", ") .. "\n")
if okMarks then pass = pass + 1 else fail = fail + 1 end

SlashCmdList.NEEDIT("bags")
local cleared = not bagButtons[2].needitMark.shown and not bagButtons[3].needitMark.shown
io.write((cleared and "PASS " or "FAIL ") .. "/needit bags off clears markers\n")
if cleared then pass = pass + 1 else fail = fail + 1 end
SlashCmdList.NEEDIT("bags")

-- slash commands run without errors
printed = {}
local okCmds = pcall(function()
  SlashCmdList.NEEDIT("debug"); SlashCmdList.NEEDIT("help"); SlashCmdList.NEEDIT("spec 9"); SlashCmdList.NEEDIT("spec")
  SlashCmdList.NEEDIT("spec 2"); SlashCmdList.NEEDIT("spec auto"); SlashCmdList.NEEDIT("")
end)
local out = table.concat(printed, "\n")
local okSlash = okCmds and out:find("interface 16001", 1, true) and out:find("Unknown spec '9'", 1, true)
  and out:find("spec Fury (manual)", 1, true) and out:find("1 = Arms, 2 = Fury, 3 = Protection", 1, true)
io.write((okSlash and "PASS " or "FAIL ") .. "Slash commands (debug/help/spec)\n")
if not okSlash then io.write(out, "\n") end
if okSlash then pass = pass + 1 else fail = fail + 1 end

io.write(string.format("\n%d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
