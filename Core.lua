local ADDON_NAME, ns = ...

-- Public addon table
GuildNotes = GuildNotes or {}
local M = GuildNotes

-- ========= SavedVars / DB =========
local SVAR_NAME = "GuildNotesDB"
ns.db = ns.db or _G[SVAR_NAME]

local function EnsureDB()
  if type(_G[SVAR_NAME]) ~= "table" then _G[SVAR_NAME] = {} end
  local db = _G[SVAR_NAME]
  db.notes = db.notes or {}
  ns.db = db
end

-- ========= Utilities =========
local function SafeRandomSeed()
  local seed = (GetServerTime and GetServerTime()) or time() or 0
  if math.randomseed then pcall(math.randomseed, seed); math.random(); math.random(); math.random() end
end

M.frame = CreateFrame("Frame", ADDON_NAME.."EventFrame")

function ns:Now()
  return (GetServerTime and GetServerTime()) or time()
end

-- Calculate database version (max updated timestamp across all entries)
function M:GetDatabaseVersion()
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

function ns:PlayerKey(nameOrFull)
  if not nameOrFull or nameOrFull == "" then return nil end
  local name, realm = nameOrFull:match("^([^-]+)%-(.+)$")
  if not name then name = nameOrFull; realm = GetRealmName() end
  if not name or not realm then return nil end
  return name.."-"..realm
end

local function BaseNameFromKey(key) return (key and key:match("^[^-]+")) or "" end

local function CurrentPlayerKey()
  if not UnitName then return nil end
  local name, realm = UnitName("player")
  if not name then return nil end
  return ns:PlayerKey(name, realm)
end

local STATUS_ORDER = { G = 1, S = 2, C = 3, A = 4, K = 5 }
local REPORT_LIMIT = 5

function ns:StatusSeverity(code)
  return STATUS_ORDER[code or "S"] or STATUS_ORDER["S"]
end

local function ensureReports(entry)
  if type(entry) ~= "table" then return end
  if type(entry.reports) ~= "table" then entry.reports = {} end
end

local function appendReport(entry, report)
  ensureReports(entry)
  table.insert(entry.reports, report)
  while #entry.reports > REPORT_LIMIT do table.remove(entry.reports, 1) end
end

local function lower_clean(s)
  if not s then return "" end
  s = tostring(s)
  s = s:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
  s = s:gsub("|T.-|t","")
  return string.lower(s)
end

-- ===== Status helpers (accept K = Griefer) =====
local function normStatus(s)
  if s == true or s == false then return (s and "S" or "A") end
  if s == "G" or s == "S" or s == "C" or s == "A" or s == "K" then return s end
  return "S"
end

-- Make sure label covers K, without breaking an existing implementation
do
  local prev = ns.StatusLabel
  function ns:StatusLabel(code)
    if code == "K" then return "Griefer" end
    return prev and prev(self, code) or (code or "S")
  end
end

-- Make sure icons cover K (Skull), but honor an existing mapping for others
do
  local prev = ns.StatusIcon3
  function ns:StatusIcon3(code)
    if code == "K" then
      return "|TInterface/TargetingFrame/UI-RaidTargetingIcon_8:14|t" -- Skull
    end
    if prev then return prev(self, code) end
    -- tiny fallback set
    if code == "G" or code == "S" then return "|TInterface/RAIDFRAME/ReadyCheck-Ready:14|t"
    elseif code == "C" then return "|TInterface/Buttons/UI-GroupLoot-Dice-Up:14|t"
    elseif code == "A" then return "|TInterface/RAIDFRAME/ReadyCheck-NotReady:14|t"
    else return "" end
  end
end

-- Preserve explicit K when reading an entry’s status
do
  local prev = ns.GetStatus
  function ns:GetStatus(entry)
    if entry and entry.status == "K" then return "K" end
    return (prev and prev(self, entry)) or (entry and entry.status) or "S"
  end
end

-- ===== Backend =====
function M:GetEntry(key)
  EnsureDB()
  local entry = ns.db and ns.db.notes and ns.db.notes[key]
  if entry then ensureReports(entry) end
  return entry
end

function M:SetEntry(fullName, data, silent)
  EnsureDB()
  local key = ns:PlayerKey(fullName)
  if not key then return end
  ensureReports(data)
  local existing = ns.db.notes[key]
  if existing and existing.reports and not data.reports then
    data.reports = existing.reports
  end
  data.updated = data.updated or ns:Now()
  ns.db.notes[key] = data
  if not silent and GuildNotesUI and GuildNotesUI.Refresh then GuildNotesUI:Refresh() end
  if GuildNotesUI and GuildNotesUI.UpdateReviewButton then GuildNotesUI:UpdateReviewButton() end
end

function M:AddOrEditEntry(nameOrFull, data)
  EnsureDB()
  if not nameOrFull or nameOrFull == "" or type(data) ~= "table" then return end
  local full = ns:PlayerKey(nameOrFull)

  -- If there's a deleted entry for this player, remove it completely when adding new entry
  local existing = ns.db.notes[full]
  if existing and existing._deleted then
    ns.db.notes[full] = nil
  end

  data.status  = normStatus(data.status)
  data.safe    = (data.status ~= "A")
  data.author  = ns:PlayerKey(UnitName("player"))
  data.updated = ns:Now()
  data._deleted = nil

  M:SetEntry(full, data)
  if GuildNotesComm and GuildNotesComm.Broadcast then GuildNotesComm:Broadcast(data, full) end
end

function M:DeleteEntry(fullName)
  EnsureDB()
  local key = ns:PlayerKey(fullName); if not key then return end
  local tomb = ns.db.notes[key] or { name = BaseNameFromKey(key) }
  tomb._deleted = true
  tomb.updated  = ns:Now()
  ns.db.notes[key] = tomb
  if GuildNotesUI and GuildNotesUI.Refresh then GuildNotesUI:Refresh() end
  if GuildNotesComm and GuildNotesComm.BroadcastDeletion then
    GuildNotesComm:BroadcastDeletion(key, tomb.updated)
  end
end

-- Clean up deleted entries from saved variables
-- ageDays: remove deleted entries older than this many days (default: 30)
-- Returns count of removed entries
function M:CleanupDeletedEntries(ageDays)
  EnsureDB()
  ageDays = ageDays or 30
  local cutoff = ns:Now() - (ageDays * 24 * 60 * 60)
  local removed = 0
  local toRemove = {}
  
  -- First pass: collect keys to remove
  for key, entry in pairs(ns.db.notes) do
    if entry and entry._deleted then
      local updated = tonumber(entry.updated) or 0
      if updated < cutoff then
        table.insert(toRemove, key)
      end
    end
  end
  
  -- Second pass: remove them
  for _, key in ipairs(toRemove) do
    ns.db.notes[key] = nil
    removed = removed + 1
  end
  
  if removed > 0 and GuildNotesUI and GuildNotesUI.Refresh then
    GuildNotesUI:Refresh()
  end
  
  return removed
end

local function buildPendingList()
  EnsureDB()
  local pending = {}
  for key, entry in pairs(ns.db.notes) do
    -- Skip deleted entries - they shouldn't have pending reports
    if entry and not entry._deleted then
      ensureReports(entry)
      if entry.reports and #entry.reports > 0 then
        for idx, rep in ipairs(entry.reports) do
          pending[#pending+1] = { key = key, index = idx, report = rep, entry = entry }
        end
      end
    end
  end
  table.sort(pending, function(a,b)
    local ta = tonumber(a.report and a.report.ts or 0) or 0
    local tb = tonumber(b.report and b.report.ts or 0) or 0
    if ta == tb then
      return (a.key or "") < (b.key or "")
    end
    return ta > tb
  end)
  return pending
end

function M:GetPendingReports()
  local list = buildPendingList()
  local out = {}
  for i,item in ipairs(list) do
    local rep = item.report or {}
    out[i] = {
      key = item.key,
      index = item.index,
      report = {
        author = rep.author,
        status = rep.status,
        requestedStatus = rep.requestedStatus,
        note = rep.note,
        ts = rep.ts,
        class = rep.class,
        race = rep.race,
        guild = rep.guild,
      },
    }
  end
  return out
end

function M:PendingReportCount()
  local total = 0
  EnsureDB()
  for _, entry in pairs(ns.db.notes) do
    -- Skip deleted entries - they shouldn't have pending reports
    if entry and not entry._deleted then
      ensureReports(entry)
      total = total + (#entry.reports or 0)
    end
  end
  return total
end

local function normalizeReportStatus(existingStatus, requested)
  local req = normStatus(requested)
  local current = normStatus(existingStatus)
  if ns:StatusSeverity(req) < ns:StatusSeverity(current) then
    return current, true
  end
  return req, false
end

function M:SubmitReport(nameOrFull, data)
  EnsureDB()
  if not nameOrFull or nameOrFull == "" or type(data) ~= "table" then return end
  local key = ns:PlayerKey(nameOrFull)
  if not key then return end

  local entry = self:GetEntry(key)
  local isNew = false
  -- If entry is deleted, treat it as if it doesn't exist and remove it
  if entry and entry._deleted then
    ns.db.notes[key] = nil
    entry = nil
  end
  if not entry then
    isNew = true
    entry = {
      name = BaseNameFromKey(key),
      status = "S",
      safe = true,
      note = "",
      class = data.class,
      race  = data.race,
      guild = data.guild,
      author = CurrentPlayerKey(),
    }
  end

  ensureReports(entry)

  local existingStatus = "S"
  if ns.GetStatus then
    existingStatus = ns:GetStatus(entry) or entry.status or "S"
  else
    existingStatus = entry.status or "S"
  end
  local requestedStatus = normStatus(data.status)
  local finalStatus, blockedUpgrade = normalizeReportStatus(existingStatus, requestedStatus)

  local meKey = CurrentPlayerKey()
  local meName = nil
  if UnitName then meName = select(1, UnitName("player")) end

  local report = {
    author = meKey or meName or "",
    status = finalStatus,
    note   = (data.note or ""):gsub("^%s+", ""):gsub("%s+$", ""),
    ts     = ns:Now(),
  }
  if blockedUpgrade and requestedStatus ~= finalStatus then
    report.requestedStatus = requestedStatus
  end
  if data.guild and data.guild ~= "" then report.guild = data.guild end
  if data.class and data.class ~= "" then report.class = data.class end
  if data.race and data.race ~= "" then report.race = data.race end

  appendReport(entry, report)
  entry.updated = ns:Now()
  if isNew then entry._pendingOnly = true end

  self:SetEntry(key, entry)

  if blockedUpgrade then
    print("|cff88c0d0[GuildNotes]|r","Status upgrade requests require officer approval; submission recorded with existing status.")
  end
  print("|cff88c0d0[GuildNotes]|r","Report submitted for review.")

  if GuildNotesComm and GuildNotesComm.Broadcast then
    GuildNotesComm:Broadcast(entry, key)
  end
  return true
end

local function appendOfficerNote(entry, report)
  local stamp = (date and report.ts and date("!%Y-%m-%d", report.ts)) or tostring(report.ts or "")
  local author = (report.author or ""):gsub("%-.*$", "")
  local snippet = (report.note and report.note ~= "") and report.note or "(no note provided)"
  local block = string.format("[%s] %s: %s", stamp or "", author ~= "" and author or "unknown", snippet)
  if entry.note and entry.note ~= "" then
    entry.note = entry.note .. "\n\n" .. block
  else
    entry.note = block
  end
end

local function removeReport(entry, index)
  ensureReports(entry)
  table.remove(entry.reports, index)
end

function M:ApplyReport(key, index, overrideStatus, overrideNote)
  EnsureDB()
  local entry = self:GetEntry(key)
  if not entry then return end
  ensureReports(entry)
  local report = entry.reports and entry.reports[index]
  if not report then return end

  -- Use override values if provided, otherwise use report values
  local finalStatus = overrideStatus or report.status
  local finalNote = overrideNote or report.note

  -- Create a modified report for appending (with officer edits)
  local modifiedReport = {}
  for k, v in pairs(report) do modifiedReport[k] = v end
  modifiedReport.status = finalStatus
  modifiedReport.note = finalNote

  appendOfficerNote(entry, modifiedReport)

  local currentStatus = "S"
  if ns.GetStatus then
    currentStatus = ns:GetStatus(entry) or entry.status or "S"
  else
    currentStatus = entry.status or "S"
  end
  if ns:StatusSeverity(finalStatus) > ns:StatusSeverity(currentStatus) then
    entry.status = finalStatus
    entry.safe = (entry.status ~= "A" and entry.status ~= "K")
  end

  entry.class = entry.class or report.class
  entry.race  = entry.race  or report.race
  entry.guild = entry.guild or report.guild

  entry._pendingOnly = nil

  removeReport(entry, index)
  entry.updated = ns:Now()

  self:SetEntry(key, entry)
  if GuildNotesComm and GuildNotesComm.Broadcast then
    GuildNotesComm:Broadcast(entry, key)
  end
  return true
end

function M:RejectReport(key, index)
  EnsureDB()
  local entry = self:GetEntry(key)
  if not entry then return end
  ensureReports(entry)
  if not entry.reports[index] then return end
  removeReport(entry, index)
  local removed = false
  if entry._pendingOnly and (#entry.reports == 0) and (not entry.note or entry.note == "") then
    ns.db.notes[key] = nil
    removed = true
  else
    entry.updated = ns:Now()
    self:SetEntry(key, entry)
  end
  if removed then
    if GuildNotesComm and GuildNotesComm.BroadcastDeletion then
      GuildNotesComm:BroadcastDeletion(key, ns:Now())
    end
    if GuildNotesUI and GuildNotesUI.UpdateReviewButton then GuildNotesUI:UpdateReviewButton() end
  elseif GuildNotesComm and GuildNotesComm.Broadcast then
    GuildNotesComm:Broadcast(entry, key)
  end
  return true
end

-- ===== Filtering =====
local function match_query(e, q)
  if not q or q == "" then return true end
  q = lower_clean(q)
  if lower_clean(e.name or ""):find(q, 1, true) then return true end
  if lower_clean(e.guild or ""):find(q, 1, true) then return true end
  if lower_clean(e.note or ""):find(q, 1, true) then return true end
  if lower_clean(e.class or ""):find(q, 1, true) then return true end
  if lower_clean(e.race or ""):find(q, 1, true) then return true end
  return false
end

function M:FilteredKeys(query)
  EnsureDB()
  local keys = {}
  for key,e in pairs(ns.db.notes) do
    if not e._deleted and not e._pendingOnly and match_query(e, query) then table.insert(keys, key) end
  end
  table.sort(keys, function(a,b)
    local ea, eb = ns.db.notes[a] or {}, ns.db.notes[b] or {}
    local na, nb = lower_clean(ea.name or BaseNameFromKey(a)), lower_clean(eb.name or BaseNameFromKey(b))
    return na < nb
  end)
  return keys
end

function M:AllKeys()
  EnsureDB()
  local keys = {}
  for key in pairs(ns.db.notes) do
    table.insert(keys, key)
  end
  return keys
end

-- ===== Events & slash =====
M.frame:RegisterEvent("ADDON_LOADED")
M.frame:RegisterEvent("PLAYER_LOGIN")

M.frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    EnsureDB()
    SafeRandomSeed()
  elseif event == "PLAYER_LOGIN" then
    EnsureDB()
    -- Clean up deleted entries older than 30 days on login
    if M.CleanupDeletedEntries then
      local removed = M:CleanupDeletedEntries(30)
      if removed > 0 then
        print("|cff88c0d0[GuildNotes]|r Cleaned up", removed, "old deleted entries.")
      end
    end
    if GuildNotesUI and GuildNotesUI.Refresh then GuildNotesUI:Refresh() end
  end
end)

SLASH_GUILDNOTES1 = "/gnotes"
SlashCmdList["GUILDNOTES"] = function()
  if GuildNotesUI and GuildNotesUI.Toggle then GuildNotesUI:Toggle() end
end

SLASH_GNOTESDEBUG1 = "/gnotesdebug"
SlashCmdList["GNOTESDEBUG"] = function()
  if type(ns.db) ~= "table" then return end
  ns.db.debug = not ns.db.debug
  print("|cff88c0d0[GuildNotes]|r Debug is now", ns.db.debug and "|cff00ff00ON|r" or "|cffff0000OFF|r")
end
