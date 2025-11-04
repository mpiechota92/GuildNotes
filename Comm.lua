local ADDON_NAME, ns = ...

GuildNotesComm = GuildNotesComm or {}
local C = GuildNotesComm

-- Prefix we use for addon messages
local PREFIX = ns and ns.PRFX or "GuildNotes"

-- -------------------------------------------------------------
-- Utilities
-- -------------------------------------------------------------

local function SendAddonMessageCompat(msg, channel)
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(PREFIX, msg, channel)
  else
    SendAddonMessage(PREFIX, msg, channel)
  end
end

local function tryToNumber(v)
  -- single-arg tonumber only; fall back to digits-only extraction
  local n = tonumber(v)
  if n then return n end
  local d = type(v) == "string" and v:match("(%d+)") or nil
  return tonumber(d) or 0
end

-- very simple escaping to keep ^ and % safe in payloads
local function esc(s)
  s = s or ""
  s = tostring(s)
  s = s:gsub("%%","%%%%"):gsub("%^","%%^")
  return s
end
local function unesc(s)
  s = s or ""
  s = s:gsub("%%^","^"):gsub("%%%%","%%")
  return s
end

-- -------------------------------------------------------------
-- Init
-- -------------------------------------------------------------

function C:Init()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  end
end

-- -------------------------------------------------------------
-- Wire format
-- -------------------------------------------------------------
-- E|name-realm^updated^status^class^race^guild^author^note
-- D|name-realm^updated
-- R|<version>
-- F|entry~entry~...  (each entry is the E payload WITHOUT the leading "E|")

local function DeserializeEntry(payload)
  -- strictly capture 8 fields; allow empty final field
  local f1,f2,f3,f4,f5,f6,f7,f8 = payload:match("^([^%^]*)%^([^%^]*)%^([^%^]*)%^([^%^]*)%^([^%^]*)%^([^%^]*)%^([^%^]*)%^(.*)$")
  if not f1 then return nil end

  local full    = unesc(f1)
  local updated = tryToNumber(unesc(f2))
  local status  = unesc(f3)
  local class   = unesc(f4)
  local race    = unesc(f5)
  local guild   = unesc(f6)
  local author  = unesc(f7)
  local note    = unesc(f8)

  if full == "" then return nil end

  local st = (status=="G" or status=="S" or status=="C" or status=="A") and status or "S"

  local e = {
    name    = (full:match("^[^-]+")) or full,
    updated = updated,
    status  = st,
    safe    = (st ~= "A"),
    class   = class ~= "" and class or nil,
    race    = race  ~= "" and race  or nil,
    guild   = guild ~= "" and guild or nil,
    author  = author~= "" and author or nil,
    note    = note   ~= "" and note   or nil,
    _deleted = false,
  }
  return full, e
end

-- -------------------------------------------------------------
-- Outgoing
-- -------------------------------------------------------------

function C:Broadcast(entry, fullName)
  if not (entry and fullName) then return end
  if entry._deleted then return end
  local up     = tostring(entry.updated or (GetServerTime and GetServerTime()) or time())
  local status = entry.status or ((entry.safe == false) and "A" or "S")
  local class  = entry.class or ""
  local race   = entry.race or ""
  local guild  = entry.guild or ""
  local author = entry.author or ""
  local note   = entry.note or ""

  local payload = "E|"..table.concat({
    esc(fullName), esc(up), esc(status), esc(class), esc(race), esc(guild), esc(author), esc(note)
  }, "^")

  if IsInGuild() then SendAddonMessageCompat(payload, "GUILD") end
  if IsInRaid() then SendAddonMessageCompat(payload, "RAID")
  elseif IsInGroup() then SendAddonMessageCompat(payload, "PARTY") end
end

function C:BroadcastDeletion(fullName, updated)
  if not fullName then return end
  local up = tostring(updated or (GetServerTime and GetServerTime()) or time())
  local payload = "D|"..esc(fullName).."^"..up
  if IsInGuild() then SendAddonMessageCompat(payload, "GUILD") end
  if IsInRaid() then SendAddonMessageCompat(payload, "RAID")
  elseif IsInGroup() then SendAddonMessageCompat(payload, "PARTY") end
end

function C:RequestFullSync()
  local payload = "R|"..(ns and ns.VERSION or "2.0.0")
  if IsInGuild() then SendAddonMessageCompat(payload, "GUILD") end
  if IsInRaid() then SendAddonMessageCompat(payload, "RAID")
  elseif IsInGroup() then SendAddonMessageCompat(payload, "PARTY") end
end

local function SendFullSync()
  if not GuildNotes or not GuildNotes.AllKeys then return end
  local keys = GuildNotes:AllKeys()
  local batchSize = 10
  for i=1,#keys,batchSize do
    local parts = {}
    for j=i, math.min(i+batchSize-1,#keys) do
      local k = keys[j]
      local e = GuildNotes:GetEntry(k)
      if e and not e._deleted then
        local up     = tostring(e.updated or (GetServerTime and GetServerTime()) or time())
        local status = e.status or ((e.safe == false) and "A" or "S")
        local class  = e.class or ""
        local race   = e.race or ""
        local guild  = e.guild or ""
        local author = e.author or ""
        local note   = e.note or ""
        parts[#parts+1] = table.concat({
          esc(k), esc(up), esc(status), esc(class), esc(race), esc(guild), esc(author), esc(note)
        }, "^")
      end
    end
    if #parts > 0 then
      local msg = "F|"..table.concat(parts, "~")
      if IsInGuild() then SendAddonMessageCompat(msg, "GUILD") end
      if IsInRaid() then SendAddonMessageCompat(msg, "RAID")
      elseif IsInGroup() then SendAddonMessageCompat(msg, "PARTY") end
    end
  end
end

-- -------------------------------------------------------------
-- Incoming
-- -------------------------------------------------------------

local function OnComm(prefix, msg, channel, sender)
  if prefix ~= PREFIX or not msg then return end
  local kind, rest = msg:match("^([^|]+)|(.+)$")
  if not kind then return end

  if kind == "E" then
    local key, e = DeserializeEntry(rest)
    if key and e then GuildNotes:MergeIncoming(key, e) end

  elseif kind == "D" then
    local full, up = rest:match("^([^%^]*)%^(.+)$")
    if full and up then
      local key = unesc(full)
      local updated = tryToNumber(up)
      local tomb = { _deleted=true, updated=updated, name = key:match("^[^-]+") }
      local existing = GuildNotes:GetEntry(key)
      if existing then
        -- keep any metadata we had (for UI coloring etc.)
        for k,v in pairs(existing) do if tomb[k] == nil then tomb[k] = v end end
      end
      GuildNotes:MergeIncoming(key, tomb)
    end

  elseif kind == "R" then
    -- someone requested full sync
    SendFullSync()

  elseif kind == "F" then
    -- batch entries
    for part in string.gmatch(rest, "([^~]+)") do
      local key, e = DeserializeEntry(part)
      if key and e then GuildNotes:MergeIncoming(key, e) end
    end
  end
end

-- -------------------------------------------------------------
-- Event wiring
-- -------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(_, event, ...)
  if event == "CHAT_MSG_ADDON" then
    local prefix, msg, channel, sender = ...
    OnComm(prefix, msg, channel, sender)
  end
end)
