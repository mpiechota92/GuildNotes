-- GuildNotes_Core.lua
-- Core namespace, shared helpers, constants

local ADDON_NAME, ns = ...
ns = ns or {}
_G[ADDON_NAME] = ns

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
function ns.RacePretty(t) return (t and ns.RACE_PRETTY[t]) or (t or "?") end
function ns.RaceIcon(t) return t and ns.RACE_ICON[t] end

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

-- External status helpers expected on ns (provided by the addon):
-- ns:GetStatus(entry) -> "G","S","C","A"
-- ns:StatusLabel(code) -> string
-- ns:StatusIcon3(code) -> icon string
-- ns:RGBForClass(class) -> r,g,b
-- ns:GetCurrentGroupNames() -> set-like table of keys in your group
