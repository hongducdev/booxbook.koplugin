package.loaded["libs/libkoreader-lfs"] = package.loaded["libs/libkoreader-lfs"]
    or { symlinkattributes = function() return nil end, attributes = function() return nil end }
package.loaded["gettext"] = package.loaded["gettext"] or function(s) return s end
package.loaded["json"] = package.loaded["json"] or { decode = function() return nil end, encode = function() return "" end }

local Queue = require("booxbook.queue")
local tmp = os.tmpname()
os.remove(tmp)
assert(Queue.path("/a/b/") == "/a/b/queue.txt", "queue path joins received dir")
assert(Queue.path("") == nil, "queue path rejects empty dir")
assert(#Queue.read(tmp) == 0, "missing queue reads empty")
assert(Queue.append(tmp, "  https://example.com/book.epub  ") == true, "queue appends trimmed url")
assert(Queue.append(tmp, "https://example.com/book.epub") == false, "queue rejects duplicates")
assert(Queue.append(tmp, "ftp://example.com/x") == nil, "queue rejects non-http url")
assert(#Queue.read(tmp) == 1, "queue lists one entry")
assert(Queue.append(tmp, "https://example.com/other.pdf") == true, "queue appends second url")
assert(#Queue.read(tmp) == 2, "queue lists two entries")
assert(Queue.remove(tmp, "https://example.com/book.epub") == true, "queue removes entry")
assert(Queue.read(tmp)[1] == "https://example.com/other.pdf", "remaining entry intact")
assert(Queue.remove(tmp, "https://example.com/missing") == false, "removing unknown url fails")
assert(Queue.clear(tmp) == true and #Queue.read(tmp) == 0, "queue clears to empty")
os.remove(tmp)

local Backup = require("booxbook.backup")
assert(Backup.isBackupName("booxbook-backup-20260910-120000.json") == true, "backup name accepted")
assert(Backup.isBackupName("notes.txt") == false, "non-backup name rejected")
local listed = Backup.list("/received", function(dir)
    assert(dir == "/received", "backup list uses received dir")
    return { "b.txt", "booxbook-backup-20260909-010000.json", "booxbook-backup-20260910-120000.json" }
end)
assert(#listed == 2 and listed[1] == "booxbook-backup-20260910-120000.json", "backup list newest first")
assert(#Backup.list("/received", function() return nil end) == 0, "backup list fails closed")

local saved_manager = package.loaded["ui/network/manager"]
local prompts, ran = 0, 0
local state = { online = true, connected = true }
package.loaded["ui/network/manager"] = {
    isOnline = function() return state.online end,
    isConnected = function() return state.connected end,
    beforeWifiAction = function(_, fn) prompts = prompts + 1; fn() end,
}
package.loaded["booxbook.network"] = nil
local Network = require("booxbook.network")
assert(Network.ifOnline(function() ran = ran + 1 end) == true, "ifOnline runs when online")
assert(ran == 1 and prompts == 0, "ifOnline never prompts when online")
state.online, state.connected = false, false
assert(Network.ifOnline(function() ran = ran + 1 end) == false, "ifOnline skips when offline")
assert(ran == 1 and prompts == 0, "ifOnline never prompts when offline")
assert(Network.ifOnline(nil) == false, "ifOnline rejects missing callback")
package.loaded["ui/network/manager"] = saved_manager
package.loaded["booxbook.network"] = nil

local Settings = require("booxbook.store.settings")
local Update = require("booxbook.update")
Settings.set("update_last_check", 0)
assert(Update.shouldCheck(Update.lastCheck()) == true, "epoch check is due")
Update.noteChecked(1234567)
assert(Update.lastCheck() == 1234567, "noteChecked persists timestamp")
assert(Update.shouldCheck(Update.lastCheck(), 1234567 + Update.CHECK_INTERVAL - 1) == false,
    "fresh check is skipped")
Settings.set("update_last_check", 0)

print("Batch1 queue, backup list, ifOnline and update stamp checks passed")
