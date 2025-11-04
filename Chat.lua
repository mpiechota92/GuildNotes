local ADDON_NAME, ns = ...

GuildNotesChat = GuildNotesChat or {}
local Chat = GuildNotesChat

local FILTERED = {
  "CHAT_MSG_SAY","CHAT_MSG_YELL","CHAT_MSG_GUILD","CHAT_MSG_PARTY","CHAT_MSG_PARTY_LEADER",
  "CHAT_MSG_RAID","CHAT_MSG_RAID_LEADER","CHAT_MSG_WHISPER","CHAT_MSG_CHANNEL",
}

local function HasNote(full)
  local e = GuildNotes:GetEntry(full)
  return e and not e._deleted
end

local function MakeClickableTag(full)
  return "|cffA3BE8C[Note]|r"
end

local function OnChatFilter(self, event, msg, author, ...)
  local key = ns:PlayerKey(author)
  if HasNote(key) then
    local tag = MakeClickableTag(key)
    local clickable = "|Hhgnote:"..key.."|h"..tag.."|h"
    local newMsg = clickable.." "..msg
    return false, newMsg, author, ...
  end
  return false, msg, author, ...
end

-- Handle custom hyperlink
local _GN_OrigSetItemRef = SetItemRef
SetItemRef = function(link, text, button, chatFrame)
  local linkType, payload = link:match("^(.-):(.*)")
  if linkType == "hgnote" then
    GuildNotesUI:Toggle()
    if GuildNotesUI.searchBox then
      local nameOnly = payload and payload:match("^[^-]+") or ""
      GuildNotesUI.searchBox:SetText(nameOnly)
      GuildNotesUI:Refresh()
    end
    return
  end
  return _GN_OrigSetItemRef(link, text, button, chatFrame)
end

-- Tooltip summary on mouseover target
GameTooltip:HookScript("OnTooltipSetUnit", function(tt)
  local name, unit = tt:GetUnit()
  unit = unit or "mouseover"
  if not unit or not UnitExists(unit) then return end
  local n, realm = UnitName(unit)
  if not n then return end
  local key = ns:PlayerKey(n, realm)
  local e = GuildNotes and GuildNotes:GetEntry(key)
  if e and not e._deleted then
    local st = ns:GetStatus(e)
    local iconText = ns:StatusIcon3(st)
    local line = ("|cffffd100Note:|r %s %s"):format(ns:StatusLabel(st), iconText or "")
    tt:AddLine(line)
    if e.note and e.note ~= "" then
      local firstLine = e.note:gsub("\r\n","\n"):gsub("\r","\n"):match("([^\n]+)")
      if firstLine then tt:AddLine(firstLine, .9,.9,.9, true) end
    end
    tt:Show()
  end
end)

function Chat:Init()
  for _,ev in ipairs(FILTERED) do
    ChatFrame_AddMessageEventFilter(ev, OnChatFilter)
  end
end
