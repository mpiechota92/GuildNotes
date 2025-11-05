local ADDON_NAME, ns = ...

GuildNotesComm = GuildNotesComm or {}
local C = GuildNotesComm

-- =============================================================
-- Config / Globals
-- =============================================================

-- Addon message prefix (<=16 chars)
local PREFIX = ns and ns.PRFX or "GuildNotes"

-- Peer registry: map[name] = lastSeenTime (only addon users)
C._peers = C._peers or {}

-- =============================================================
-- Utilities
-- =============================================================

local function Now()
  return (GetServerTime and GetServerTime()) or time()
end

-- Debug helper (enable with ns.db.debug = true)
local function dbg(...)
  if ns and ns.db and ns.db.debug then
    print("|cff88c0d0[GuildNotes]|r", ...)
  end
end

-- Ensure SavedVariables roots exist
local function EnsureDB()
  ns.db = ns.db or {}
  ns.db.notes = ns.db.notes or {}
end

local function tryToNumber(v)
  local n = tonumber(v)
  if n then return n end
  local d = type(v) == "string" and v:match("(%d+)") or nil
  return tonumber(d) or 0
end

-- Escape/unescape ^ and % inside payloads
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

-- Classic whisper target (strip -Realm)
local function WhisperTargetFromFull(full)
  if not full or full == "" then return full end
  return (full:match("^[^-]+")) or full
end

-- Safe addon message send (group channels)
local function SendAddonMessageCompat(msg, channel)
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(PREFIX, msg, channel)
  else
    if RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(PREFIX) end
    SendAddonMessage(PREFIX, msg, channel)
  end
end

-- Safe addon message send (WHISPER; invisible to chat)
local function SendAddonMessageCompatWhisper(msg, target)
  target = WhisperTargetFromFull(target)
  if not target or target == "" then return end
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(PREFIX, msg, "WHISPER", target)
  else
    if RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(PREFIX) end
    SendAddonMessage(PREFIX, msg, "WHISPER", target)
  end
end

-- HELLO so peers can discover each other
local function SendHello()
  local name, realm = UnitName("player"), GetNormalizedRealmName()
  local me = (realm and (name.."-"..realm)) or name
  local payload = "H|"..me
  if IsInGuild() then
    SendAddonMessageCompat(payload, "GUILD")
  end
end

-- Safe merge if Core.MergeIncoming isn't ready yet
local function MergeIncomingSafe(key, incoming)
  EnsureDB()
  if GuildNotes and GuildNotes.MergeIncoming then
    local ok = GuildNotes:MergeIncoming(key, incoming)
    ns.db.lastSyncAt = Now()
    return ok
  end
  local cur = ns.db.notes[key]
  local iu = tonumber(incoming and incoming.updated or 0) or 0
  local cu = tonumber(cur       and cur.updated       or 0) or 0
  if (not cur) or (iu > cu) then
    ns.db.notes[key] = incoming
  end
  ns.db.lastSyncAt = Now()
  if GuildNotesUI and GuildNotesUI.Refresh then GuildNotesUI:Refresh() end
end

-- =============================================================
-- Init
-- =============================================================

function C:Init()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  elseif RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(PREFIX)
  end
  dbg("Comm Init; prefix:", PREFIX)
end

-- =============================================================
-- Wire format
-- =============================================================
-- E|name-realm^updated^status^class^race^guild^author^note
-- D|name-realm^updated
-- R|<version>|<requester>
-- F|entry~entry~...  (legacy batch; entry is E payload without "E|")
-- H|name-realm       (peer hello)
-- MF|k1^t1~k2^t2~... (manifest of key^timestamp pairs)
-- N|k1~k2~k3         (request specific keys)

local function DeserializeEntry(payload)
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
    name     = (full:match("^[^-]+")) or full,
    updated  = updated,
    status   = st,
    safe     = (st ~= "A"),
    class    = class ~= "" and class or nil,
    race     = race  ~= "" and race  or nil,
    guild    = guild ~= "" and guild or nil,
    author   = author~= "" and author or nil,
    note     = note   ~= "" and note   or nil,
    _deleted = false,
  }
  return full, e
end

-- =============================================================
-- Outgoing: full to target, deletions to target
-- =============================================================

local function SendFullSyncTo(target)
  if not GuildNotes or not GuildNotes.AllKeys then return end
  local keys = GuildNotes:AllKeys()
  local batchSize = 10
  for i=1,#keys,batchSize do
    for j=i, math.min(i+batchSize-1,#keys) do
      local k = keys[j]
      local e = GuildNotes:GetEntry(k)
      if e and not e._deleted then
        local up     = tostring(e.updated or Now())
        local status = e.status or ((e.safe == false) and "A" or "S")
        local class  = e.class or ""
        local race   = e.race or ""
        local guild  = e.guild or ""
        local author = e.author or ""
        local note   = e.note or ""
        local payload = "E|"..table.concat({esc(k), esc(up), esc(status), esc(class), esc(race), esc(guild), esc(author), esc(note)}, "^")
        SendAddonMessageCompatWhisper(payload, target)
      end
    end
  end
  dbg("Sent full E to", target)
end

local function SendFullDeletionsTo(target)
  if not GuildNotes or not GuildNotes.AllKeys then return end
  local keys = GuildNotes:AllKeys()
  for _,k in ipairs(keys) do
    local e = GuildNotes:GetEntry(k)
    if e and e._deleted then
      local up = tostring(e.updated or Now())
      local payload = "D|"..esc(k).."^"..esc(up)
      SendAddonMessageCompatWhisper(payload, target)
    end
  end
  dbg("Sent full D to", target)
end

-- Broadcast deltas on change (existing behavior)
function C:Broadcast(entry, fullName)
  if not (entry and fullName) then return end
  if entry._deleted then return end
  local up     = tostring(entry.updated or Now())
  local status = entry.status or ((entry.safe == false) and "A" or "S")
  local class  = entry.class or ""
  local race   = entry.race or ""
  local guild  = entry.guild or ""
  local author = entry.author or ""
  local note   = entry.note or ""
  local payload = "E|"..table.concat({ esc(fullName), esc(up), esc(status), esc(class), esc(race), esc(guild), esc(author), esc(note) }, "^")
  if IsInGuild() then SendAddonMessageCompat(payload, "GUILD") end
  if IsInRaid() then SendAddonMessageCompat(payload, "RAID")
  elseif IsInGroup() then SendAddonMessageCompat(payload, "PARTY") end
  dbg("Broadcast E for", fullName)
end

function C:BroadcastDeletion(fullName, updated)
  if not fullName then return end
  local up = tostring(updated or Now())
  local payload = "D|"..esc(fullName).."^"..up
  if IsInGuild() then SendAddonMessageCompat(payload, "GUILD") end
  if IsInRaid() then SendAddonMessageCompat(payload, "RAID")
  elseif IsInGroup() then SendAddonMessageCompat(payload, "PARTY") end
  dbg("Broadcast D for", fullName)
end

-- Legacy group full sync (kept for compatibility)
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
        local up     = tostring(e.updated or Now())
        local status = e.status or ((e.safe == false) and "A" or "S")
        local class  = e.class or ""
        local race   = e.race or ""
        local guild  = e.guild or ""
        local author = e.author or ""
        local note   = e.note or ""
        parts[#parts+1] = table.concat({ esc(k), esc(up), esc(status), esc(class), esc(race), esc(guild), esc(author), esc(note) }, "^")
      end
    end
    if #parts > 0 then
      local msg = "F|"..table.concat(parts, "~")
      if IsInGuild() then SendAddonMessageCompat(msg, "GUILD") end
      if IsInRaid() then SendAddonMessageCompat(msg, "RAID")
      elseif IsInGroup() then SendAddonMessageCompat(msg, "PARTY") end
    end
  end
  dbg("Broadcast legacy F")
end

-- =============================================================
-- Requests
-- =============================================================

function C:RequestFullSync()
  local payload = "R|"..(ns and ns.VERSION or "2.0.0")
  if IsInGuild() then SendAddonMessageCompat(payload, "GUILD") end
  if IsInRaid() then SendAddonMessageCompat(payload, "RAID")
  elseif IsInGroup() then SendAddonMessageCompat(payload, "PARTY") end
  dbg("Requested legacy full sync")
end

function C:RequestFullSyncSelf()
  local name, realm = UnitName("player"), GetNormalizedRealmName()
  local me = (realm and (name.."-"..realm)) or name
  if not me or me == "" then return end
  local payload = "R|"..(ns and ns.VERSION or "2.0.0").."|"..me
  if IsInGuild() then SendAddonMessageCompat(payload, "GUILD") end
  if IsInRaid() then SendAddonMessageCompat(payload, "RAID")
  elseif IsInGroup() then SendAddonMessageCompat(payload, "PARTY") end
  dbg("Requested targeted sync:", me)
end

-- =============================================================
-- Responder election (among addon peers only)
-- =============================================================

local function IsEligibleResponder(limit, requester)
  limit = limit or 2
  local meName, meRealm = UnitName("player"), GetNormalizedRealmName()
  local meFull = (meRealm and (meName.."-"..meRealm)) or meName

  -- Build fresh peer list (seen within 30 minutes)
  local peers = {}
  local cutoff = Now() - (30*60)
  for name, seenAt in pairs(C._peers) do
    if seenAt and seenAt >= cutoff then
      peers[#peers+1] = name
    end
  end

  -- If no peer knowledge yet, be helpful and respond.
  if #peers == 0 then return true end

  table.sort(peers, function(a,b) return a < b end)

  local eligibleCount = 0
  for _,name in ipairs(peers) do
    if name ~= requester and name ~= (requester and requester:match("^[^-]+")) then
      eligibleCount = eligibleCount + 1
      if name == meFull or name == meName or name:match("^"..meName.."%-") then
        return eligibleCount <= limit
      end
      if eligibleCount >= limit then
        -- we've passed our slot; keep looping only if we might be later in list
      end
    end
  end

  -- If our name wasn't in peers (first contact), allow response
  return true
end

-- Pick a single online guild peer (alphabetical) other than self
local function PickOnePeer()
  if not IsInGuild() then return nil end
  C_GuildInfo.GuildRoster()
  local num = (GetNumGuildMembers and GetNumGuildMembers()) or 0
  local meName, meRealm = UnitName("player"), GetNormalizedRealmName()
  local meFull = (meRealm and (meName.."-"..meRealm)) or meName
  local pool = {}
  for i=1,num do
    local name, _, _, _, _, _, _, _, isOnline, _, _, _, _, isMobile = GetGuildRosterInfo(i)
    if name and isOnline and not isMobile and name ~= meFull and name ~= meName then
      pool[#pool+1] = name
    end
  end
  table.sort(pool, function(a,b) return a < b end)
  return pool[1]  -- nil if none
end

-- =============================================================
-- Anti-entropy: Manifests (MF) & Need lists (N)
-- =============================================================

local function BuildNewestKeys(limit)
  EnsureDB()
  limit = limit or 50
  local arr = {}
  for k,e in pairs(ns.db.notes) do
    arr[#arr+1] = { key = k, ts = tonumber(e and e.updated or 0) or 0 }
  end
  table.sort(arr, function(a,b) return a.ts > b.ts end)
  local out = {}
  for i=1, math.min(limit, #arr) do out[i] = arr[i] end
  return out
end

local function BuildRandomKeys(limit)
  EnsureDB()
  limit = limit or 20
  local all = {}
  for k,e in pairs(ns.db.notes) do
    all[#all+1] = { key = k, ts = tonumber(e and e.updated or 0) or 0 }
  end
  if #all <= limit then return all end
  for i=#all,2,-1 do
    local j = math.random(i)
    all[i], all[j] = all[j], all[i]
  end
  local out = {}
  for i=1,limit do out[i] = all[i] end
  return out
end

local function SendManifestTo(target, keys)
  target = WhisperTargetFromFull(target)
  if not target or target == "" or not keys or #keys == 0 then return end
  local batch, bufLen = {}, 0
  local function flush()
    if #batch == 0 then return end
    local payload = "MF|"..table.concat(batch, "~")
    SendAddonMessageCompatWhisper(payload, target)
    wipe(batch); bufLen = 0
  end
  for _,it in ipairs(keys) do
    local part = esc(it.key).."^"..esc(tostring(it.ts or 0))
    if bufLen + #part + 3 > 230 then flush() end -- safe under 255
    batch[#batch+1] = part
    bufLen = bufLen + #part + 1
  end
  flush()
  dbg("Sent MF to", target, "(", #keys, "keys )")
end

local function OnManifest(sender, list)
  EnsureDB()
  local need = {}
  for pair in string.gmatch(list, "([^~]+)") do
    local k, t = pair:match("^([^%^]+)%^(.+)$")
    if k and t then
      k = unesc(k)
      local theirs = tonumber(unesc(t)) or 0
      local mine = 0
      local e = ns.db.notes[k]
      if e then mine = tonumber(e.updated or 0) or 0 end
      if theirs > mine then need[#need+1] = esc(k) end
    end
  end
  if #need > 0 then
    local cap = 50
    local chunk = {}
    for i=1, math.min(#need, cap) do chunk[i] = need[i] end
    local payload = "N|"..table.concat(chunk, "~")
    SendAddonMessageCompatWhisper(payload, WhisperTargetFromFull(sender))
    dbg("Replied with N to", sender, "(", #chunk, "keys )")
  end
end

local function OnNeedList(target, list)
  target = WhisperTargetFromFull(target)
  for key in string.gmatch(list, "([^~]+)") do
    key = unesc(key)
    local e = GuildNotes and GuildNotes.GetEntry and GuildNotes:GetEntry(key)
    if not e and ns and ns.db and ns.db.notes then
      e = ns.db.notes[key]
    end
    if e then
      if e._deleted then
        local up = tostring(e.updated or Now())
        SendAddonMessageCompatWhisper("D|"..esc(key).."^"..esc(up), target)
      else
        local up     = tostring(e.updated or Now())
        local status = e.status or ((e.safe == false) and "A" or "S")
        local class  = e.class or ""
        local race   = e.race or ""
        local guild  = e.guild or ""
        local author = e.author or ""
        local note   = e.note or ""
        local payload = "E|"..table.concat({esc(key), esc(up), esc(status), esc(class), esc(race), esc(guild), esc(author), esc(note)}, "^")
        SendAddonMessageCompatWhisper(payload, target)
      end
    end
  end
  dbg("Fulfilled N for", target)
end

-- =============================================================
-- Incoming dispatcher
-- =============================================================

local function OnComm(prefix, msg, channel, sender)
  if prefix ~= PREFIX or not msg then return end
  local kind, rest = msg:match("^([^|]+)|(.+)$")
  if not kind then return end

  -- Record addon peer (whoever spoke our prefix)
  if sender and sender ~= "" then
    C._peers[sender] = Now()
  end

  if kind == "H" then
    -- Peer hello; already recorded above
    return
  end

  if kind == "E" then
    local key, e = DeserializeEntry(rest)
    if key and e then MergeIncomingSafe(key, e) end

  elseif kind == "D" then
    local full, up = rest:match("^([^%^]*)%^(.+)$")
    if full and up then
      local key = unesc(full)
      local updated = tryToNumber(up)
      local tomb = { _deleted=true, updated=updated, name = key:match("^[^-]+") }
      local existing = (GuildNotes and GuildNotes.GetEntry and GuildNotes:GetEntry(key)) or (ns.db and ns.db.notes and ns.db.notes[key])
      if existing then
        for k,v in pairs(existing) do if tomb[k] == nil then tomb[k] = v end end
      end
      MergeIncomingSafe(key, tomb)
    end

  elseif kind == "R" then
    -- R|<version>|<requester>
    local ver, requester = rest:match("^([^|]+)|(.+)$")
    requester = requester or ""
    local meName, meRealm = UnitName("player"), GetNormalizedRealmName()
    local me = (meRealm and (meName.."-"..meRealm)) or meName

    if requester == me or requester == meName then
      dbg("Ignoring my own R")
    else
      if IsEligibleResponder(2, requester) then
        local function doRespond()
          local tgt = WhisperTargetFromFull(requester)
          SendFullSyncTo(tgt)
          SendFullDeletionsTo(tgt)
          -- also start anti-entropy so BOTH sides converge
          SendManifestTo(tgt, BuildNewestKeys(50))
          dbg("Responded to R from", requester)
        end
        local delay = math.random(5, 20) / 10  -- 0.5–2.0s jitter
        if C_Timer and C_Timer.After then C_Timer.After(delay, doRespond) else doRespond() end
      else
        dbg("Not eligible (peer election)")
      end
    end

  elseif kind == "F" then
    -- legacy batch
    for part in string.gmatch(rest, "([^~]+)") do
      local key, e = DeserializeEntry(part)
      if key and e then MergeIncomingSafe(key, e) end
    end
    dbg("Processed legacy F")

  elseif kind == "MF" then
    OnManifest(sender, rest)

  elseif kind == "N" then
    OnNeedList(sender, rest)
  end
end

-- =============================================================
-- Boot: register prefix, HELLO, freshness-gated pull, anti-entropy
-- =============================================================

if not C._boot then
  C._boot = CreateFrame("Frame")
  C._boot:RegisterEvent("ADDON_LOADED")
  C._boot:RegisterEvent("PLAYER_LOGIN")
  C._boot:RegisterEvent("PLAYER_ENTERING_WORLD")
  C._boot:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and (arg1 == ADDON_NAME or arg1 == "Blizzard_Communities") then
      if C.Init then C:Init() end
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
      if C.Init then C:Init() end
      SendHello()

      -- Freshness gate: empty or >7d since lastSyncAt => targeted full pull
      EnsureDB()
      local stale = (not next(ns.db.notes)) or (Now() - (ns.db.lastSyncAt or 0) > 7*24*60*60)
      if stale and C.RequestFullSyncSelf then
        dbg("DB stale/empty -> requesting targeted full sync")
        C:RequestFullSyncSelf()
      end

      -- Periodic HELLO (peer list freshness) every 5 minutes
      if C_Timer and not C._helloTicker and C_Timer.NewTicker then
        C._helloTicker = C_Timer.NewTicker(300, function()
          SendHello()
        end)
      end

      -- Periodic anti-entropy: every 10 minutes send a small MF to one peer
      if C_Timer and not C._antiTicker and C_Timer.NewTicker then
        C._antiTicker = C_Timer.NewTicker(600, function()
          local peer = PickOnePeer()
          if peer then
            SendManifestTo(peer, BuildRandomKeys(20))
          end
        end)
        dbg("Anti-entropy ticker active")
      end
    end
  end)
end

-- =============================================================
-- Slash commands
-- =============================================================

SLASH_GNOTESSYNC1 = "/gnotesync"
SlashCmdList["GNOTESSYNC"] = function()
  if C and C.RequestFullSyncSelf then
    print("|cff88c0d0[GuildNotes]|r requesting targeted sync…")
    C:RequestFullSyncSelf()
  else
    print("|cff88c0d0[GuildNotes]|r sync unavailable (Comm not initialized?)")
  end
end

SLASH_GNOTESEND1 = "/gnotesend"
SlashCmdList["GNOTESEND"] = function(msg)
  local target = (msg or ""):match("^(%S+)")
  if not target or target == "" then
    print("|cff88c0d0[GuildNotes]|r usage: /gnotesend PlayerName")
    return
  end
  print("|cff88c0d0[GuildNotes]|r sending full DB to:", target)
  SendFullSyncTo(target)
  SendFullDeletionsTo(target)
  -- also send a manifest so receiver can ask back if *they* have newer bits
  SendManifestTo(target, BuildNewestKeys(50))
end

-- =============================================================
-- Event wiring
-- =============================================================

local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(_, event, ...)
  if event == "CHAT_MSG_ADDON" then
    local prefix, msg, channel, sender = ...
    OnComm(prefix, msg, channel, sender)
  end
end)
