-- GuildNotes_Core.lua
-- Core namespace, shared helpers, constants

local ADDON_NAME, ns = ...
ns = ns or {}
_G[ADDON_NAME] = ns

-- Version metadata (from .toc)
do
  local version = nil
  if type(GetAddOnMetadata) == "function" then
    version = GetAddOnMetadata(ADDON_NAME, "Version")
  end
  if type(version) ~= "string" or version == "" then
    version = ns.VERSION or "0.0.0"
  end
  ns.VERSION = version
end

-- Public UI table
GuildNotesUI = GuildNotesUI or {}
ns.UI = GuildNotesUI

-- ===== Pretty helpers =====
ns.CLASS_PRETTY = {
  WARRIOR="Warrior", PALADIN="Paladin", HUNTER="Hunter", ROGUE="Rogue",
  PRIEST="Priest", MAGE="Mage", WARLOCK="Warlock", DRUID="Druid",
}
ns.CLASS_ICON = {
  WARRIOR="Interface/ICONS/ClassIcon_Warrior",
  PALADIN="Interface/ICONS/ClassIcon_Paladin",
  HUNTER ="Interface/ICONS/ClassIcon_Hunter",
  ROGUE  ="Interface/ICONS/ClassIcon_Rogue",
  PRIEST ="Interface/ICONS/ClassIcon_Priest",
  MAGE   ="Interface/ICONS/ClassIcon_Mage",
  WARLOCK="Interface/ICONS/ClassIcon_Warlock",
  DRUID  ="Interface/ICONS/ClassIcon_Druid",
}
ns.RACE_PRETTY = { Human="Human", Dwarf="Dwarf", NightElf="Night Elf", Gnome="Gnome" }
ns.RACE_ICON = {
  Human   ="Interface/ICONS/Achievement_Character_Human_Male",
  Dwarf   ="Interface/ICONS/Achievement_Character_Dwarf_Male",
  NightElf="Interface/ICONS/Achievement_Character_Nightelf_Male",
  Gnome   ="Interface/ICONS/Achievement_Character_Gnome_Male",
}

function ns.ClassPretty(t) return (t and ns.CLASS_PRETTY[t]) or (t or "?") end
function ns.ClassIcon(t) return t and ns.CLASS_ICON[t] end
function ns.RacePretty(t)  return (t and ns.RACE_PRETTY[t]) or (t or "?") end
function ns.RaceIcon(t)    return t and ns.RACE_ICON[t] end

function ns.CellWithIcon(icon, text)
  return icon and ("|T"..icon..":14|t "..(text or "")) or (text or "")
end

-- ===== Permissions =====
local function IsTop3()
  if not IsInGuild() then return false end
  local _, _, r = GetGuildInfo("player")
  return r and r <= 2
end
function GuildNotesUI:RecomputePermissions()
  self.canEdit = IsTop3()
  if self.deleteBtn and self.currentKey then self.deleteBtn:SetShown(self.canEdit) end
  if self.reviewBtn then self.reviewBtn:SetShown(self.canEdit) end
  if self.UpdateReviewButton then self:UpdateReviewButton() end
end

-- ===== Safe lower / sanitize =====
function ns.SafeLower(s)
  if not s then return "" end
  s = tostring(s)
  s = s:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
  s = s:gsub("|T.-|t","")
  return string.lower(s)
end

-- ===== One-line ellipsis =====
function ns.TruncateToWidth(fs, text, maxW)
  text = (text or ""):gsub("\r\n","\n"):gsub("\r","\n")
  text = text:gsub("\n.*$","")
  if text == "" then fs:SetText(""); return end
  fs:SetText(text)
  if fs:GetStringWidth() <= maxW then return end
  local left, right = 0, #text
  local best = "…"
  while left <= right do
    local mid = math.floor((left + right)/2)
    local cand = text:sub(1, mid) .. "…"
    fs:SetText(cand)
    if fs:GetStringWidth() <= maxW then best = cand; left = mid + 1 else right = mid - 1 end
  end
  fs:SetText(best)
end
-- === Status helpers ===
local STATUS_LABEL = {
  G = "Great player",
  S = "Safe",
  C = "Be cautious",
  A = "Avoid",
  K = "Griefer",         -- NEW
}
function ns:StatusLabel(code)
  return STATUS_LABEL[code] or code or "S"
end

-- Extend StatusIcon3 with Skull for "K"
local _OldStatusIcon3 = ns.StatusIcon3
function ns:StatusIcon3(code)
  if code == "K" then
    return "|TInterface/TargetingFrame/UI-RaidTargetingIcon_8:14|t" -- Skull
  end
  if _OldStatusIcon3 then return _OldStatusIcon3(self, code) end
  -- tiny fallback if original wasn’t defined
  if     code == "G" or code == "S" then return "|TInterface/RAIDFRAME/ReadyCheck-Ready:14|t"
  elseif code == "C"                then return "|TInterface/Buttons/UI-GroupLoot-Dice-Up:14|t"
  elseif code == "A"                then return "|TInterface/RAIDFRAME/ReadyCheck-NotReady:14|t"
  else return "" end
end

-- Preserve "K" when determining status from an entry
local _OldGetStatus = ns.GetStatus
function ns:GetStatus(entry)
  local s = _OldGetStatus and _OldGetStatus(self, entry) or (entry and entry.status) or "S"
  if entry and entry.status == "K" then return "K" end
  return s
end
