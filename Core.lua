local ADDON_NAME, ns = ...

GuildNotes = {}
local M = GuildNotes

local function SafeRandomSeed()
  local seed = (GetServerTime and GetServerTime()) or time() or 0
  if math.randomseed then pcall(math.randomseed, seed); math.random(); math.random(); math.random() end
end

M.frame = CreateFrame("Frame", ADDON_NAME.."EventFrame")

local DEFAULTS = {
  version = ns.VERSION,
  debug = false,
  notes = {}, -- ["Player-Server"] = { name, class, race, guild, status, note, author, updated, _deleted? }
}

local function EnsureDB()
  GuildNotesDB = GuildNotesDB or {}
  for k,v in pairs(DEFAULTS) do if GuildNotesDB[k] == nil then GuildNotesDB[k] = ns:DeepCopy(v) end end
  ns.db = GuildNotesDB
end

local function normStatus(s)
  if s == true or s == false then return (s and "S" or "A") end
  if s == "G" or s == "S" or s == "C" or s == "A" then return s end
  return "S"
end

-- Permissions
local function PlayerRankIndex()
  if not IsInGuild() then return nil end
  local _, _, rankIndex = GetGuildInfo("player")
  return rankIndex
end
local function IsTop3()
  local ri = PlayerRankIndex()
  return ri ~= nil and ri <= 2
end

-- API
function M:GetEntry(key) return ns.db.notes[key] end

function M:SetEntry(fullName, data, silent)
  local key = ns:PlayerKey(fullName)
  if not key then return end
  data.updated = data.updated or ns:Now()
  ns.db.notes[key] = data
  if not silent and GuildNotesUI and GuildNotesUI.Refresh then GuildNotesUI:Refresh() end
end

-- Anyone can add; only top3 can edit existing
function M:AddOrEditEntry(nameOrFull, data)
  if not nameOrFull or nameOrFull == "" or type(data) ~= "table" then return end
  if not IsInGuild() then
    print("|cffff5555GuildNotes:|r You must be in a guild to add notes.")
    return
  end
  local full = ns:PlayerKey(nameOrFull)
  local existing = ns.db.notes[full]
  if existing and not existing._deleted and not IsTop3() then
    print("|cffff5555GuildNotes:|r Only the top 3 guild ranks can edit notes.")
    return
  end
  data.status = normStatus(data.status)
  data.safe = (data.status ~= "A")
  data.author = ns:PlayerKey(UnitName("player"))
  data.updated = ns:Now()
  data._deleted = nil
  M:SetEntry(full, data)
  if GuildNotesComm and GuildNotesComm.Broadcast then GuildNotesComm:Broadcast(data, full) end
end

function M:DeleteEntry(fullName)
  if not IsTop3() then
    print("|cffff5555GuildNotes:|r Only the top 3 guild ranks can delete notes.")
    return
  end
  local key = ns:PlayerKey(fullName)
  if not key then return end
  local tomb = ns.db.notes[key] or { name = ns:AmbiguateName(key) }
  tomb._deleted = true
  tomb.updated = ns:Now()
  ns.db.notes[key] = tomb
  if GuildNotesUI and GuildNotesUI.Refresh then GuildNotesUI:Refresh() end
  if GuildNotesComm and GuildNotesComm.BroadcastDeletion then
    GuildNotesComm:BroadcastDeletion(key, tomb.updated)
  end
end

-- Latest updated wins (tombstones included)
function M:MergeIncoming(fullName, incoming)
  local key = ns:PlayerKey(fullName)
  if not key then return end
  local current = ns.db.notes[key]
  local incUp = tonumber(incoming.updated or 0) or 0
  local curUp = tonumber(current and current.updated or 0) or 0
  if (not current) or incUp >= curUp then
    ns.db.notes[key] = incoming
    if GuildNotesUI and GuildNotesUI.Refresh then GuildNotesUI:Refresh() end
  end
end

function M:AllKeys()
  local t = {}
  for k in pairs(ns.db.notes) do
    if ns.db.notes[k] and not ns.db.notes[k]._deleted then
      t[#t+1] = k
    end
  end
  return t
end

function M:FilteredKeys(query)
  local terms = {}
  query = (query or ""):gsub("^%s+",""):gsub("%s+$","")
  for w in string.gmatch(query, "%S+") do terms[#terms+1]=w:lower() end

  local keys = {}
  for key, e in pairs(ns.db.notes) do
    if e and not e._deleted then
      local hay = table.concat({
        key:lower(),
        (e.name or ""):lower(),
        (e.guild or ""):lower(),
        (e.class or ""):lower(),
        (e.race or ""):lower(),
        (e.note or ""):lower(),
        (e.author or ""):lower(),
      }, " ")
      local ok = true
      for _,term in ipairs(terms) do if not string.find(hay, term, 1, true) then ok=false; break end end
      if ok then keys[#keys+1] = key end
    end
  end
  return ns:SortKeysWithGroupFirst(keys)
end

-- Events
local function _InitAll()
  EnsureDB(); SafeRandomSeed()
  if GuildNotesComm and GuildNotesComm.Init then GuildNotesComm:Init() end
  if GuildNotesUI and GuildNotesUI.Init then GuildNotesUI:Init() end
  if GuildNotesChat and GuildNotesChat.Init then GuildNotesChat:Init() end
end

M.frame:RegisterEvent("ADDON_LOADED")
M.frame:RegisterEvent("PLAYER_LOGIN")
M.frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name == ADDON_NAME then _InitAll() end
  elseif event == "PLAYER_LOGIN" then
    if GuildNotesComm and GuildNotesComm.RequestFullSync then
      GuildNotesComm:RequestFullSync()
    end
    if GuildNotesUI and GuildNotesUI.Refresh then GuildNotesUI:Refresh() end
  end
end)

-- Slash
SLASH_GUILDNOTES1 = "/gnotes"
SlashCmdList["GUILDNOTES"] = function()
  if GuildNotesUI and GuildNotesUI.Toggle then GuildNotesUI:Toggle() end
end
