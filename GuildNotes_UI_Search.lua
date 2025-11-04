-- GuildNotes_UI_Search.lua
-- Robust search: always local filtering over a normalized "all keys" set.
-- Uses backend only to fetch the universe, never for filtering.
-- Falls back to SavedVariables when needed.

local ADDON_NAME, ns = ...
local UI = ns.UI

-- Normalize any table to an array of string keys suitable for GetEntry(key)
local function NormalizeKeys(t)
  if type(t) ~= "table" then return {} end
  if #t > 0 then
    local out = {}
    for i = 1, #t do
      local v = t[i]
      if type(v) == "string" then
        table.insert(out, v)
      elseif type(v) == "table" then
        if type(v.key) == "string"   then table.insert(out, v.key)
        elseif type(v.id) == "string"   then table.insert(out, v.id)
        elseif type(v.name) == "string" then table.insert(out, v.name)
        end
      end
    end
    return out
  end
  local out = {}
  for k, v in pairs(t) do
    if type(k) == "string" and (v == true or v == 1) then
      table.insert(out, k)
    elseif type(v) == "string" then
      table.insert(out, v)
    elseif type(v) == "table" then
      if type(v.key) == "string"   then table.insert(out, v.key)
      elseif type(v.id) == "string"   then table.insert(out, v.id)
      elseif type(v.name) == "string" then table.insert(out, v.name)
      end
    end
  end
  return out
end

-- Safe lower (strip WoW color/texture codes)
local function L(s)
  if not s then return "" end
  s = tostring(s)
  s = s:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
  s = s:gsub("|T.-|t","")
  return string.lower(s)
end

-- Build the "all keys" universe from backend or SavedVariables.
local function GetAllKeys()
  -- Prefer backend if present
  if GuildNotes and GuildNotes.AllKeys then
    local keys = NormalizeKeys(GuildNotes:AllKeys())
    if #keys > 0 then return keys end
  end
  if GuildNotes and GuildNotes.FilteredKeys then
    local keys = NormalizeKeys(GuildNotes:FilteredKeys(""))
    if #keys > 0 then return keys end
  end
  -- Rock-solid fallback: SavedVariables
  local out = {}
  if GuildNotesDB and GuildNotesDB.notes and type(GuildNotesDB.notes) == "table" then
    for key, _ in pairs(GuildNotesDB.notes) do
      table.insert(out, key)
    end
  end
  return out
end

-- Public: UI:FetchKeys(query)
function UI:FetchKeys(query)
  local queryTrim = (query or ""):match("^%s*(.-)%s*$") or ""
  local q = string.lower(queryTrim)

  local all = GetAllKeys()

  -- No query => show all (minus deleted)
  if q == "" then
    local out = {}
    for _, key in ipairs(all) do
      local e = (GuildNotes and GuildNotes:GetEntry(key)) or (GuildNotesDB and GuildNotesDB.notes and GuildNotesDB.notes[key]) or nil
      if e and not e._deleted then
        table.insert(out, key)
      end
    end
    return out
  end

  -- Local, case-insensitive substring match
  local out = {}
  for _, key in ipairs(all) do
    local e = (GuildNotes and GuildNotes:GetEntry(key)) or (GuildNotesDB and GuildNotesDB.notes and GuildNotesDB.notes[key]) or nil
    if e and not e._deleted then
      local name   = L(e.name or (key:match("^[^-]+") or key))
      local guild  = L(e.guild)
      local class  = L(e.class or "")
      local classL = L((ns.CLASS_PRETTY and ns.CLASS_PRETTY[e.class]) or e.class or "")
      local race   = L(e.race or "")
      local raceL  = L((ns.RACE_PRETTY and ns.RACE_PRETTY[e.race]) or e.race or "")
      local note   = L(e.note)
      local author = L(e.author)
      local statL  = L(ns.StatusLabel and ns:StatusLabel(ns:GetStatus(e)) or "")

      if  name:find(q,1,true) or guild:find(q,1,true)
          or class:find(q,1,true) or classL:find(q,1,true)
          or race:find(q,1,true)  or raceL:find(q,1,true)
          or note:find(q,1,true)  or author:find(q,1,true)
          or statL:find(q,1,true)
      then
        table.insert(out, key)
      end
    end
  end

  return out
end