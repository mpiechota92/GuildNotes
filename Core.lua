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

function ns:PlayerKey(nameOrFull)
  if not nameOrFull or nameOrFull == "" then return nil end
  local name, realm = nameOrFull:match("^([^-]+)%-(.+)$")
  if not name then name = nameOrFull; realm = GetRealmName() end
  if not name or not realm then return nil end
  return name.."-"..realm
end

local function BaseNameFromKey(key) return (key and key:match("^[^-]+")) or "" end

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
  return ns.db and ns.db.notes and ns.db.notes[key]
end

function M:SetEntry(fullName, data, silent)
  EnsureDB()
  local key = ns:PlayerKey(fullName)
  if not key then return end
  data.updated = data.updated or ns:Now()
  ns.db.notes[key] = data
  if not silent and GuildNotesUI and GuildNotesUI.Refresh then GuildNotesUI:Refresh() end
end

function M:AddOrEditEntry(nameOrFull, data)
  EnsureDB()
  if not nameOrFull or nameOrFull == "" or type(data) ~= "table" then return end
  local full = ns:PlayerKey(nameOrFull)

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
    if not e._deleted and match_query(e, query) then table.insert(keys, key) end
  end
  table.sort(keys, function(a,b)
    local ea, eb = ns.db.notes[a] or {}, ns.db.notes[b] or {}
    local na, nb = lower_clean(ea.name or BaseNameFromKey(a)), lower_clean(eb.name or BaseNameFromKey(b))
    return na < nb
  end)
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
    if GuildNotesUI and GuildNotesUI.Refresh then GuildNotesUI:Refresh() end
  end
end)

SLASH_GUILDNOTES1 = "/gnotes"
SlashCmdList["GUILDNOTES"] = function()
  if GuildNotesUI and GuildNotesUI.Toggle then GuildNotesUI:Toggle() end
end
