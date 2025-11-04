-- GuildNotes_UI_Search.lua
local ADDON_NAME, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI

-- Use Core's backend filter (name-only in Core.lua)
function UI:FetchKeys(query)
  if GuildNotes and GuildNotes.FilteredKeys then
    return GuildNotes:FilteredKeys(query)
  end
  return {}
end
