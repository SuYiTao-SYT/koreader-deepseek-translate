local ffi = require("ffi")

ffi.cdef[[
void *curl_easy_init(void);
int curl_easy_setopt(void *handle, int option, ...);
int curl_easy_perform(void *handle);
int curl_easy_getinfo(void *handle, int info, ...);
void curl_easy_cleanup(void *handle);
void *curl_slist_append(void *list, const char *string);
void curl_slist_free_all(void *list);
]]

local Transport = {}
local options = {
    url = 10002, post_fields = 10015, post_size = 60, headers = 10023,
    writer = 20011, connect_timeout_ms = 156, timeout_ms = 155, no_signal = 99,
    verify_peer = 64, verify_host = 81, ca_info = 10065, follow_location = 52,
}
local response_code = 0x200002
local body_limit = 160 * 1024
local base = "https://api.deepseek.com"

local function loadCurl()
    local ok, lib = pcall(ffi.load, "libs/libcurl.so.4")
    if ok then return lib end
    ok, lib = pcall(ffi.load, "libcurl.so.4")
    if ok then return lib end
end

function Transport.request(path, key, payload)
    if (path ~= "/models" and path ~= "/chat/completions") or not key:match("^[%w_%-]+$") then
        return nil, nil, "setup"
    end
    local curl = loadCurl()
    if not curl then return nil, nil, "curl" end
    local handle = curl.curl_easy_init()
    if handle == nil then return nil, nil, "curl" end

    local headers, callback
    local chunks, size = {}, 0
    local url, ca_path = base .. path, "data/ca-bundle.crt"
    local function set(option, value)
        if curl.curl_easy_setopt(handle, options[option], value) ~= 0 then error("curl option") end
    end
    local function setLong(option, value)
        set(option, ffi.new("long", value))
    end
    local function append(value)
        local next_headers = curl.curl_slist_append(headers, value)
        if next_headers == nil then error("curl headers") end
        headers = next_headers
    end

    local ok, status, failure = pcall(function()
        append("Authorization: Bearer " .. key)
        append("Accept: application/json")
        if payload then append("Content-Type: application/json") end
        callback = ffi.cast("size_t (*)(char *, size_t, size_t, void *)", function(ptr, unit, count)
            local bytes = tonumber(unit * count)
            if bytes > body_limit - size then return 0 end
            if bytes > 0 then chunks[#chunks + 1] = ffi.string(ptr, bytes) end
            size = size + bytes
            return bytes
        end)

        set("url", ffi.cast("const char *", url))
        set("headers", headers)
        set("writer", callback)
        set("ca_info", ffi.cast("const char *", ca_path))
        setLong("connect_timeout_ms", 8000)
        setLong("timeout_ms", 35000)
        setLong("no_signal", 1)
        setLong("verify_peer", 1)
        setLong("verify_host", 2)
        setLong("follow_location", 0)
        if payload then
            setLong("post_size", #payload)
            set("post_fields", ffi.cast("const char *", payload))
        end

        local rc = curl.curl_easy_perform(handle)
        if rc ~= 0 then
            if rc == 28 then return nil, "timeout" end
            if rc == 35 or rc == 51 or rc == 58 or rc == 60 or rc == 77 then return nil, "tls" end
            return nil, "network"
        end
        local status_buf = ffi.new("long[1]")
        if curl.curl_easy_getinfo(handle, response_code, status_buf) ~= 0 then return nil, "network" end
        return tonumber(status_buf[0])
    end)
    curl.curl_easy_cleanup(handle)
    if headers ~= nil then curl.curl_slist_free_all(headers) end
    if callback then callback:free() end
    if not ok then return nil, nil, "curl" end
    if not status then return nil, nil, failure end
    return status, table.concat(chunks)
end

-- LuaJIT must not compile a C call that synchronously invokes a Lua callback.
if jit then jit.off(Transport.request, true) end

return Transport
