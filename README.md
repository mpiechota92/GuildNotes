# GuildNotes

A lightweight guild note management system for **World of Warcraft Classic** (including Hardcore).

GuildNotes helps guilds track and share structured player notes — useful for Hardcore trust networks, raiding vetting, or general community management.

---

## ✨ Features

- ✅ Add/edit/remove player notes
- ✅ Structured info:
  - Name
  - Guild
  - Class & Race
  - Status tag
  - Notes
  - Author & Timestamp
- ✅ Modal note editor with ESC handling (ESC closes only editor, not main UI)
- ✅ Scrollable list with page navigation
- ✅ Search & filtering
- ✅ Hover tooltip preview
- ✅ Works with ElvUI & Prat (no chat spam)
- ✅ Permissions:
  - Top 3 guild ranks = edit/delete
  - Everyone = can add notes
- ✅ Early targeted sync architecture (NWB-style, via addon WHISPER)
- ✅ Anti-entropy sync approach planned (MF/N)

---

## 🔧 Slash Commands

| Command | Action |
|--------|--------|
| `/gnotes` | Open main window |
| `/gnotesync` | Manual sync test |
| `/gnotesend` | Debug send for development |

---

## 🧠 Sync System (High-Level)

GuildNotes uses a **targeted peer sync model** similar to NovaWorldBuffs:

- Whisper-based sync
- Peer responder election
- Anti-entropy logic planned:
  - Missing notes request
  - Deletion propagation
  - Timestamp comparison

This prevents chat spam and stays compatible with popular chat addons.

---

## 🚀 Roadmap

- 🔄 Full sync implementation
- 🛡️ Officer mode / audit history
- 📊 Filter/sort UI
- ⚙️ Settings UI

---

## 📦 Installation

Extract into:
_**World of Warcraft/classic/Interface/AddOns/GuildNotes**_


Ensure folder name = `GuildNotes`.

---

## 🧪 Development Notes

This addon is designed with:

- Zero spam philosophy
- Minimal UI interference
- Respect for other addons
- No global pollution
- Future scalability

Contributions & reviews welcome!

---

## ❤️ Credits

Created by **mpiechota** aka **Deepbussy-Soulseeker** 


