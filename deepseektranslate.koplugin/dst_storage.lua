local lfs = require("libs/libkoreader-lfs")
local sha256 = require("ffi/sha2").sha256

local Storage = {}
Storage.__index = Storage
local max_cached = 256

local function read(path, limit)
    local file = io.open(path, "rb")
    if not file then return end
    local bytes = file:read(limit + 1)
    file:close()
    if bytes and #bytes <= limit then return bytes end
end

local function write(path, bytes)
    local temporary = path .. ".tmp"
    local file = io.open(temporary, "wb")
    if not file then return end
    local wrote = file:write(bytes)
    local closed = file:close()
    if wrote and closed and os.rename(temporary, path) then return true end
    os.remove(temporary)
end

function Storage.new(settings_dir, import_path)
    return setmetatable({
        key_path = settings_dir .. "/deepseektranslate.key",
        cache_dir = settings_dir .. "/deepseektranslate-cache",
        import_path = import_path,
    }, Storage)
end

local function readKey(path)
    local key = read(path, 300)
    return key and key:gsub("^\239\187\191", ""):match("^%s*(.-)%s*$")
end

function Storage:readKey()
    return readKey(self.key_path)
end

function Storage:saveKey(key)
    return write(self.key_path, key .. "\n")
end

function Storage:readImport()
    if not self.import_path or lfs.attributes(self.import_path, "mode") ~= "file" then return nil, false end
    return readKey(self.import_path), true
end

function Storage:importKey(expected)
    local current = self:readImport()
    if not current or current ~= expected then return nil, "changed" end
    if self:readKey() ~= current then
        if not self:saveKey(current) or self:readKey() ~= current then return nil, "write" end
    end
    if not os.remove(self.import_path) then return true, "retained" end
    return true
end

function Storage:removeKey()
    if lfs.attributes(self.key_path, "mode") ~= "file" then return true end
    return os.remove(self.key_path)
end

function Storage.cacheId(source, language, model, prompt_version, context)
    local fields = { prompt_version, model, language, source }
    if context then
        fields[#fields + 1] = context.before
        fields[#fields + 1] = context.after
    end
    return sha256(table.concat(fields, "\0"))
end

function Storage:get(id)
    return read(self.cache_dir .. "/" .. id .. ".txt", 160 * 1024)
end

local function cacheFiles(directory)
    local found = {}
    if lfs.attributes(directory, "mode") ~= "directory" then return found end
    for name in lfs.dir(directory) do
        if #name == 68 and name:match("^[0-9a-f]+%.txt$") then
            local path = directory .. "/" .. name
            local attrs = lfs.attributes(path)
            if attrs and attrs.mode == "file" then
                found[#found + 1] = { path = path, time = attrs.modification }
            end
        end
    end
    return found
end

function Storage:put(id, value)
    if lfs.attributes(self.cache_dir, "mode") ~= "directory" and not lfs.mkdir(self.cache_dir) then return end
    local path = self.cache_dir .. "/" .. id .. ".txt"
    if not write(path, value) then return end
    local files = cacheFiles(self.cache_dir)
    if #files > max_cached then
        table.sort(files, function(a, b) return a.time < b.time end)
        local remove = #files - max_cached
        for _, file in ipairs(files) do
            if remove == 0 then break end
            if file.path ~= path and os.remove(file.path) then remove = remove - 1 end
        end
    end
    return true
end

function Storage:clearCache()
    local ok = true
    for _, file in ipairs(cacheFiles(self.cache_dir)) do
        if not os.remove(file.path) then ok = false end
    end
    return ok
end

return Storage
