local ADDON_NAME, ns = ...

ns.PRFX = "GuildNotes"
ns.VERSION = "2.0.0"

function ns:Debug(...) if ns.db and ns.db.debug then print("|cff88c0d0[GuildNotes]|r", ...) end end

function ns:PlayerKey(name, realm)
  if not name or name == "" then return nil end
  if name:find("-") then return name end
  realm = realm or GetNormalizedRealmName()
  return (name .. "-" .. (realm or ""))
end

function ns:AmbiguateName(full)
  if not full then return nil end
  local name = Ambiguate(full, "none")
  return name
end

function ns:RGBForClass(class)
  if not class then return 1,1,1 end
  local c = RAID_CLASS_COLORS[class]
  if c then return c.r, c.g, c.b end
  return 1,1,1
end

function ns:Now() return time() end

function ns:DeepCopy(tbl)
  if type(tbl) ~= "table" then return tbl end
  local copy = {}
  for k,v in pairs(tbl) do copy[k] = ns:DeepCopy(v) end
  return copy
end

function ns:IterateGroup()
  local units = {}
  if IsInRaid() then
    for i=1,40 do local u="raid"..i; if UnitExists(u) then units[#units+1]=u end end
  elseif IsInGroup() then
    for i=1,4 do local u="party"..i; if UnitExists(u) then units[#units+1]=u end end
  end
  units[#units+1] = "player"
  return units
end

function ns:GetCurrentGroupNames()
  local map = {}
  for _,u in ipairs(ns:IterateGroup()) do
    local n, realm = UnitName(u)
    if n then map[ns:PlayerKey(n, realm and realm:gsub(" ", ""))] = true end
  end
  return map
end

function ns:SortKeysWithGroupFirst(keys)
  local inGroup = ns:GetCurrentGroupNames()
  table.sort(keys, function(a,b)
    local ga, gb = inGroup[a], inGroup[b]
    if ga ~= gb then return ga and not gb end
    return a:lower() < b:lower()
  end)
  return keys
end

-- Status helpers
function ns:GetStatus(entry)
  if not entry then return "S" end
  local s = entry.status
  if s == "G" or s == "S" or s == "C" or s == "A" then return s end
  if entry.safe == false then return "A" end
  return "S"
end

function ns:StatusLabel(s)
  if s == "G" then return "Great player"
  elseif s == "S" then return "Safe"
  elseif s == "C" then return "Be cautious"
  elseif s == "A" then return "Avoid"
  else return "" end
end

function ns:StatusIcon3(status)
  if status == "G" then
    return "|TInterface/TargetingFrame/UI-RaidTargetingIcon_1:14:14|t"
  elseif status == "C" then
    return "|TInterface/RAIDFRAME/ReadyCheck-Waiting:14:14|t"
  elseif status == "A" then
    return "|TInterface/RAIDFRAME/ReadyCheck-NotReady:14:14|t"
  else
    return "|TInterface/RAIDFRAME/ReadyCheck-Ready:14:14|t"
  end
end

function ns:EscapePipes(s) return s and s:gsub("|", "||") or s end
