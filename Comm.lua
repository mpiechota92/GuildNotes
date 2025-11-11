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

-- Active sync sessions: map[requester] = { sender, dbVersion, startTime }
-- Used to prevent accepting multiple simultaneous syncs
C._activeSyncs = C._activeSyncs or {}

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

local function IsSyncOnCooldown()
  return ns and ns.IsSyncOnCooldown and ns:IsSyncOnCooldown()
end

local function SyncCooldownRemaining()
  if ns and ns.GetSyncCooldownRemaining then
    return ns:GetSyncCooldownRemaining()
  elseif ns and ns.GetSyncCooldownEndsAt and ns.Now then
    local remaining = (ns:GetSyncCooldownEndsAt() or 0) - ns:Now()
    if remaining < 0 then remaining = 0 end
    return remaining
  end
  return 0
end

local function StartSyncCooldown()
  if ns and ns.StartSyncCooldown then
    return ns:StartSyncCooldown()
  end
end

local function ParseVersionParts(v)
  local parts = {}
  if type(v) == "number" then
    parts[1] = math.floor(v)
  elseif type(v) == "string" then
    for token in v:gmatch("(%d+)") do
      parts[#parts+1] = tonumber(token) or 0
    end
  end
  if #parts == 0 then
    parts[1] = 0
  end
  return parts
end

local function CompareVersions(a, b)
  local ap = ParseVersionParts(a)
  local bp = ParseVersionParts(b)
  local len = math.max(#ap, #bp)
  for i = 1, len do
    local av = ap[i] or 0
    local bv = bp[i] or 0
    if av > bv then
      return 1
    elseif av < bv then
      return -1
    end
  end
  return 0
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

local function escReportField(v)
  v = esc(v or "")
  v = v:gsub(";", "%%;")
  v = v:gsub("~", "%%~")
  return v
end

local function unescReportField(v)
  v = (v or ""):gsub("%%~", "~"):gsub("%%;", ";")
  return unesc(v)
end

local function SerializeReports(reports)
  if not reports or #reports == 0 then return "" end
  local all = {}
  for _, rep in ipairs(reports) do
    local fields = {
      escReportField(rep.author or ""),
      escReportField(rep.status or ""),
      escReportField(tostring(rep.ts or 0)),
      escReportField(rep.note or ""),
      escReportField(rep.requestedStatus or ""),
      escReportField(rep.class or ""),
      escReportField(rep.race or ""),
      escReportField(rep.guild or ""),
    }
    all[#all+1] = table.concat(fields, "~")
  end
  return table.concat(all, ";")
end

local function DeserializeReports(blob)
  if not blob or blob == "" then return {} end
  local reports = {}
  for chunk in string.gmatch(blob, "([^;]+)") do
    local fields, idx = {}, 1
    for part in string.gmatch(chunk .. "~", "([^~]*)~") do
      fields[idx] = unescReportField(part)
      idx = idx + 1
    end
    local rep = {
      author = fields[1] or "",
      status = fields[2] or "S",
      ts     = tryToNumber(fields[3]) or 0,
      note   = fields[4] or "",
    }
    if fields[5] and fields[5] ~= "" then rep.requestedStatus = fields[5] end
    if fields[6] and fields[6] ~= "" then rep.class = fields[6] end
    if fields[7] and fields[7] ~= "" then rep.race = fields[7] end
    if fields[8] and fields[8] ~= "" then rep.guild = fields[8] end
    reports[#reports+1] = rep
  end
  return reports
end

local function BuildEntryFields(fullName, entry)
  if not (fullName and entry) then return nil end
  local up     = tostring(entry.updated or Now())
  local status = entry.status or ((entry.safe == false) and "A" or "S")
  local class  = entry.class or ""
  local race   = entry.race or ""
  local guild  = entry.guild or ""
  local author = entry.author or ""
  local note   = entry.note or ""
  local reports = SerializeReports(entry.reports)
  return { esc(fullName), esc(up), esc(status), esc(class), esc(race), esc(guild), esc(author), esc(note), esc(reports) }
end

local function BuildEntryPayload(fullName, entry)
  local fields = BuildEntryFields(fullName, entry)
  if not fields then return nil end
  return "E|"..table.concat(fields, "^")
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
-- E|name-realm^updated^status^class^race^guild^author^note^reports
-- D|name-realm^updated
-- R|<version>|<requester>|<dbVersion>  (dbVersion is max updated timestamp)
-- F|entry~entry~...  (legacy batch; entry is E payload without "E|")
-- H|name-realm       (peer hello)
-- MF|k1^t1~k2^t2~... (manifest of key^timestamp pairs)
-- N|k1~k2~k3         (request specific keys)

local function DeserializeEntry(payload)
  local f1,f2,f3,f4,f5,f6,f7,rest = payload:match("^([^%^]*)%^([^%^]*)%^([^%^]*)%^([^%^]*)%^([^%^]*)%^([^%^]*)%^([^%^]*)%^(.*)$")
  if not f1 then return nil end
  local f8, f9 = rest or "", ""
  local caretPos = rest and rest:find("^", 1, true)
  if caretPos then
    f8 = rest:sub(1, caretPos - 1)
    f9 = rest:sub(caretPos + 1)
  end
  local full    = unesc(f1)
  local updated = tryToNumber(unesc(f2))
  local status  = unesc(f3)
  local class   = unesc(f4)
  local race    = unesc(f5)
  local guild   = unesc(f6)
  local author  = unesc(f7)
  local note    = unesc(f8 or "")
  local reports = DeserializeReports(unesc(f9 or ""))
  if full == "" then return nil end
  local st = (status=="G" or status=="S" or status=="C" or status=="A" or status=="K") and status or "S"
  local e = {
    name     = (full:match("^[^-]+")) or full,
    updated  = updated,
    status   = st,
    safe     = (st ~= "A" and st ~= "K"),
    class    = class ~= "" and class or nil,
    race     = race  ~= "" and race  or nil,
    guild    = guild ~= "" and guild or nil,
    author   = author~= "" and author or nil,
    note     = note   ~= "" and note   or nil,
    _deleted = false,
    reports  = reports,
  }
  if (#reports > 0) and (not e.note or e.note == "") and (st == "S") then
    e._pendingOnly = true
  end
  return full, e
end

-- =============================================================
-- Outgoing: full to target, deletions to target
-- =============================================================

local function SendFullSyncTo(target)
  if not GuildNotes or not GuildNotes.AllKeys then return end
  local keys = GuildNotes:AllKeys()
  local batchSize = 10
  local sent = 0
  for i=1,#keys,batchSize do
    for j=i, math.min(i+batchSize-1,#keys) do
      local k = keys[j]
      local e = GuildNotes:GetEntry(k)
      if e and not e._deleted then
        local payload = BuildEntryPayload(k, e)
        if payload then
          SendAddonMessageCompatWhisper(payload, target)
          sent = sent + 1
        end
      end
    end
  end
  dbg("Sent full E to", target, "(", sent, "entries )")
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
  local payload = BuildEntryPayload(fullName, entry)
  if not payload then return end
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
        local fields = BuildEntryFields(k, e)
        if fields then
          parts[#parts+1] = table.concat(fields, "^")
        end
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

function C:RequestFullSync(opts)
  opts = opts or {}
  if IsSyncOnCooldown() then
    return false, "cooldown", SyncCooldownRemaining()
  end
  if IsResting and not IsResting() then
    return false, "not_resting"
  end

  StartSyncCooldown()
  local payload = "R|"..(ns and ns.VERSION or "2.0.0")
  if IsInGuild() then SendAddonMessageCompat(payload, "GUILD") end
  if IsInRaid() then SendAddonMessageCompat(payload, "RAID")
  elseif IsInGroup() then SendAddonMessageCompat(payload, "PARTY") end
  dbg("Requested legacy full sync")
  return true
end

function C:RequestFullSyncSelf(opts)
  opts = opts or {}
  if IsSyncOnCooldown() then
    return false, "cooldown", SyncCooldownRemaining()
  end
  if IsResting and not IsResting() then
    return false, "not_resting"
  end
  local name, realm = UnitName("player"), GetNormalizedRealmName()
  local me = (realm and (name.."-"..realm)) or name
  if not me or me == "" then return false, "no_player" end
  StartSyncCooldown()
  
  -- Clear any existing sync sessions
  C._activeSyncs = {}
  
  -- Get our database version
  local dbVersion = 0
  if GuildNotes and GuildNotes.GetDatabaseVersion then
    dbVersion = GuildNotes:GetDatabaseVersion() or 0
  end
  
  local payload = "R|"..(ns and ns.VERSION or "2.0.0").."|"..me.."|"..tostring(dbVersion)
  if IsInGuild() then SendAddonMessageCompat(payload, "GUILD") end
  if IsInRaid() then SendAddonMessageCompat(payload, "RAID")
  elseif IsInGroup() then SendAddonMessageCompat(payload, "PARTY") end
  dbg("Requested targeted sync:", me, "dbVersion:", dbVersion)
  return true
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

-- Get our database version for sync responses
local function GetOurDatabaseVersion()
  if GuildNotes and GuildNotes.GetDatabaseVersion then
    return GuildNotes:GetDatabaseVersion() or 0
  end
  -- Fallback: calculate manually
  EnsureDB()
  local maxUpdated = 0
  for _, entry in pairs(ns.db.notes) do
    if entry and entry.updated then
      local updated = tonumber(entry.updated) or 0
      if updated > maxUpdated then
        maxUpdated = updated
      end
    end
  end
  return maxUpdated
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
        local payload = BuildEntryPayload(key, e)
        if payload then
          SendAddonMessageCompatWhisper(payload, target)
        end
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
    -- R|<version>|<requester>|<dbVersion>
    local ver, requester, requesterDbVersion = rest:match("^([^|]+)|([^|]*)|?(.*)$")
    requester = requester or ""
    requesterDbVersion = tonumber(requesterDbVersion) or 0
    local myVersion = ns and ns.VERSION
    local meName, meRealm = UnitName("player"), GetNormalizedRealmName()
    local me = (meRealm and (meName.."-"..meRealm)) or meName

    if myVersion and CompareVersions(ver, myVersion) < 0 then
      dbg("Ignoring sync request from older version:", sender, "their:", ver, "ours:", myVersion)
      return
    end

    if IsResting and not IsResting() then
      dbg("Ignoring sync request - not resting:", sender or "unknown")
      return
    end

    if IsSyncOnCooldown() then
      dbg("Ignoring sync request - cooldown active:", sender or "unknown")
      return
    end

    if requester == me or requester == meName then
      dbg("Ignoring my own R")
    else
      -- Get our database version
      local ourDbVersion = GetOurDatabaseVersion()
      
      -- Only respond if we have newer or equal data (or if requester has no data)
      local shouldRespond = (ourDbVersion >= requesterDbVersion) or (requesterDbVersion == 0)
      
      if shouldRespond and IsEligibleResponder(2, requester) then
        -- Check if there's already an active sync for this requester
        local existingSync = C._activeSyncs[requester]
        if existingSync then
          -- If we have a newer database version than the current responder, replace them
          local existingVersion = existingSync.dbVersion or 0
          if ourDbVersion > existingVersion then
            dbg("Replacing existing sync responder (we have newer data)")
            C._activeSyncs[requester] = { sender = me, dbVersion = ourDbVersion, startTime = Now() }
          else
            dbg("Ignoring R - another peer is already syncing with better data")
            return
          end
        else
          -- Start new sync session
          C._activeSyncs[requester] = { sender = me, dbVersion = ourDbVersion, startTime = Now() }
        end
        
        local function doRespond()
          local tgt = WhisperTargetFromFull(requester)
          SendFullSyncTo(tgt)
          SendFullDeletionsTo(tgt)
          -- also start anti-entropy so BOTH sides converge
          SendManifestTo(tgt, BuildNewestKeys(50))
          dbg("Responded to R from", requester, "ourDbVersion:", ourDbVersion, "theirDbVersion:", requesterDbVersion)
          
          -- Clean up sync session after 30 seconds
          if C_Timer and C_Timer.After then
            C_Timer.After(30, function()
              if C._activeSyncs[requester] and C._activeSyncs[requester].sender == me then
                C._activeSyncs[requester] = nil
              end
            end)
          end
        end
        local delay = math.random(5, 20) / 10  -- 0.5–2.0s jitter
        if C_Timer and C_Timer.After then C_Timer.After(delay, doRespond) else doRespond() end
      else
        if not shouldRespond then
          dbg("Not responding - requester has newer data (their:", requesterDbVersion, "our:", ourDbVersion, ")")
        else
          dbg("Not eligible (peer election)")
        end
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

      -- Automatic sync on login removed - use manual sync button instead

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
    local ok, reason, extra = C:RequestFullSyncSelf()
    if ok then
      print("|cff88c0d0[GuildNotes]|r requesting targeted sync…")
    elseif reason == "cooldown" then
      local remaining = extra or SyncCooldownRemaining()
      local minutes = math.ceil((remaining or 0) / 60)
      print("|cff88c0d0[GuildNotes]|r Sync is on cooldown ("..minutes.." min remaining).")
    elseif reason == "not_resting" then
      print("|cff88c0d0[GuildNotes]|r You must be resting (inn or capital) to request a sync.")
    elseif reason == "no_player" then
      print("|cff88c0d0[GuildNotes]|r Unable to determine player name; sync aborted.")
    else
      print("|cff88c0d0[GuildNotes]|r Sync unavailable (unknown reason).")
    end
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
