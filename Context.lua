-- Chat.lua
-- Adds a clickable [Note <icon>] tag in chat for players who have a GuildNotes entry.
-- Clicking the tag opens the GuildNotes UI filtered to that player.
-- Also enriches the unit tooltip with: "GuildNote: <icon> <label>".

local ADDON_NAME, ns = ...

GuildNotesChat = GuildNotesChat or {}
local Chat = GuildNotesChat

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function HasNote(full)
  if not full or not GuildNotes or not GuildNotes.GetEntry then return false end
  local e = GuildNotes:GetEntry(full)
  return e and not e._deleted
end

local function StatusIconFor(full)
  if not (ns and ns.StatusIcon3 and GuildNotes and GuildNotes.GetEntry) then return "" end
  local e = GuildNotes:GetEntry(full)
  if not e then return "" end
  local st = (ns.GetStatus and ns:GetStatus(e)) or e.status or "S"
  return ns:StatusIcon3(st) or ""
end

-- Build a CLICKABLE tag using Blizzard's "player" link so it never prints raw.
-- We stash a marker "GN" as the 4th field: |Hplayer:<full>:0:GN|h[Note <icon>]|h
local function BuildClickableTag(full)
  local icon = StatusIconFor(full)
  local inner = (icon ~= "" and ("Note "..icon)) or "Note"
  return "|cffA3BE8C|Hplayer:"..full..":0:GN|h["..inner.."]|h|r"
end

local function KeyForAuthor(author)
  -- author is usually "Name-Realm"; if not, ns:PlayerKey will add realm.
  if not author or author == "" then return nil end
  if ns and ns.PlayerKey then return ns:PlayerKey(author) end
  return author
end

-- ---------------------------------------------------------------------------
-- Chat filter: prepend our clickable tag
-- ---------------------------------------------------------------------------

local FILTERED = {
  "CHAT_MSG_SAY","CHAT_MSG_YELL","CHAT_MSG_GUILD",
  "CHAT_MSG_PARTY","CHAT_MSG_PARTY_LEADER",
  "CHAT_MSG_RAID","CHAT_MSG_RAID_LEADER",
  "CHAT_MSG_WHISPER","CHAT_MSG_CHANNEL",
  -- add if you want:
  -- "CHAT_MSG_INSTANCE_CHAT","CHAT_MSG_INSTANCE_CHAT_LEADER",
}

local function OnChatFilter(self, event, msg, author, ...)
  local key = KeyForAuthor(author)
  if key and HasNote(key) then
    local tag = BuildClickableTag(key)
    return false, (tag.." "..(msg or "")), author, ...
  end
  return false, msg, author, ...
end

-- ---------------------------------------------------------------------------
-- Click handler: intercept only our special player link (4th field == "GN")
-- ---------------------------------------------------------------------------

local _GN_OrigSetItemRef = SetItemRef
SetItemRef = function(link, text, button, chatFrame)
  local typ, rest = link:match("^(.-):(.*)$")
  if typ == "player" and rest then
    -- player link shape: name[:lineID[:chatType[:extra]]]
    local name, lineID, chatType, extra = rest:match("^([^:]*):?([^:]*):?([^:]*):?(.*)$")
    if extra == "GN" then
      local full = name
      if GuildNotesUI and GuildNotesUI.Toggle then
        GuildNotesUI:Toggle()
        if GuildNotesUI.searchBox and full then
          local nameOnly = full:match("^[^-]+") or full
          GuildNotesUI.searchBox:SetText(nameOnly)
          if GuildNotesUI.Refresh then GuildNotesUI:Refresh() end
        end
      end
      return
    end
  end
  return _GN_OrigSetItemRef(link, text, button, chatFrame)
end

-- ---------------------------------------------------------------------------
-- Tooltip enrichment: "GuildNote: <icon> <label>"
-- ---------------------------------------------------------------------------

GameTooltip:HookScript("OnTooltipSetUnit", function(tt)
  local _, unit = tt:GetUnit()
  unit = unit or "mouseover"
  if not unit or not UnitExists(unit) then return end

  local name, realm = UnitName(unit)
  if not name then return end

  local full = realm and (name.."-"..realm) or name
  local key  = ns and ns.PlayerKey and ns:PlayerKey(full) or full
  if not (GuildNotes and GuildNotes.GetEntry and key) then return end

  local e = GuildNotes:GetEntry(key)
  if e and not e._deleted then
    local st    = (ns.GetStatus and ns:GetStatus(e)) or e.status or "S"
    local icon  = (ns.StatusIcon3 and ns:StatusIcon3(st)) or ""
    local label = (ns.StatusLabel  and ns:StatusLabel(st)) or st
    tt:AddLine(("GuildNote: %s%s"):format(icon ~= "" and (icon.." ") or "", label), 1, 1, 1)
    tt:Show()
  end
end)

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------

function Chat:Init()
  for _,ev in ipairs(FILTERED) do
    ChatFrame_AddMessageEventFilter(ev, OnChatFilter)
  end
end

-- auto-boot
if not Chat._boot then
  Chat._boot = CreateFrame("Frame")
  Chat._boot:RegisterEvent("PLAYER_LOGIN")
  Chat._boot:SetScript("OnEvent", function() Chat:Init() end)
end
