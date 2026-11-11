local API = require("dst_api")
local Page = require("dst_reader")
local Storage = require("dst_storage")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local NetworkMgr = require("ui/network/manager")
local TextViewer = require("ui/widget/textviewer")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local Translate = WidgetContainer:extend{ name = "deepseektranslate", is_doc_only = false }
local title = "DeepSeek 翻译"
local highlight_id = "07_deepseektranslate"
local import_filename = "deepseek-api-key.txt"
local startup_import_checked = false
local languages = {
    { id = "zh-CN", label = "简体中文", prompt = "Simplified Chinese" },
    { id = "zh-TW", label = "繁體中文", prompt = "Traditional Chinese" },
    { id = "en", label = "English", prompt = "English" },
    { id = "ja", label = "日本語", prompt = "Japanese" },
}

local function notice(text)
    UIManager:show(InfoMessage:new{ text = text })
end

function Translate:init()
    local directory = DataStorage:getSettingsDir()
    self.settings = LuaSettings:open(directory .. "/deepseektranslate.lua")
    self.storage = Storage.new(directory, Device:isKindle() and ("/mnt/us/" .. import_filename) or nil)
    self.generation = 0
    self.auto_task = function() self:translatePage(true) end
    self.ui.menu:registerToMainMenu(self)
    if self.storage.import_path and not startup_import_checked then
        UIManager:nextTick(function()
            if startup_import_checked or self.closed then return end
            startup_import_checked = true
            self:offerImport(true)
        end)
    end
    local highlight = self.ui.highlight
    if highlight and highlight.addToHighlightDialog then
        highlight:addToHighlightDialog(highlight_id, function(widget)
            return {
                text = title,
                callback = function()
                    local text = widget.selected_text and Page.clean(widget.selected_text.text)
                    local context
                    if text and self.settings:readSetting("selection_context", false) then
                        local screen = Device.screen
                        context = Page.selectionContext(widget, self.ui, text, screen:getWidth(), screen:getHeight(), self:contextWords())
                    end
                    if widget.highlight_dialog then UIManager:close(widget.highlight_dialog) end
                    self:translate(text, "selection", false, context)
                end,
            }
        end)
    end
end

function Translate:language()
    local current = self.settings:readSetting("language", "zh-CN")
    for _, language in ipairs(languages) do
        if language.id == current then return language end
    end
    return languages[1]
end

function Translate:contextWords()
    return Page.contextWordCount(self.settings:readSetting("selection_context_words", Page.default_context_words))
end

function Translate:addToMainMenu(menu_items)
    local language_rows = {}
    for _, language in ipairs(languages) do
        language_rows[#language_rows + 1] = {
            text = language.label,
            checked_func = function() return self:language().id == language.id end,
            callback = function()
                self.settings:saveSetting("language", language.id):flush()
                self.auto_seen = nil
                self:pageChanged()
            end,
        }
    end
    local context_rows = {}
    for _, count in ipairs(Page.context_choices) do
        context_rows[#context_rows + 1] = {
            text = count .. " 词",
            checked_func = function() return self:contextWords() == count end,
            callback = function() self.settings:saveSetting("selection_context_words", count):flush() end,
        }
    end
    local rows = {}
    if self.ui.document then
        rows[#rows + 1] = { text = "翻译当前页", callback = function() self:translatePage(false) end }
        rows[#rows + 1] = {
            text = "本书翻页自动翻译",
            checked_func = function() return self.auto_enabled == true end,
            callback = function() self:toggleAuto() end,
        }
    end
    rows[#rows + 1] = {
        text_func = function() return "译文语言：" .. self:language().label end,
        sub_item_table = language_rows,
    }
    rows[#rows + 1] = {
        text = "选段翻译附带附近上下文",
        checked_func = function() return self.settings:readSetting("selection_context", false) end,
        callback = function()
            local enabled = self.settings:readSetting("selection_context", false)
            if enabled then
                self.settings:saveSetting("selection_context", false):flush()
            else
                UIManager:show(ConfirmBox:new{
                    text = "以后选段翻译时，把选段前后各最多 " .. self:contextWords()
                        .. " 词也发送给 DeepSeek，用来判断语境？",
                    ok_text = "开启上下文",
                    ok_callback = function() self.settings:saveSetting("selection_context", true):flush() end,
                })
            end
        end,
    }
    rows[#rows + 1] = {
        text_func = function() return "每侧上下文：" .. self:contextWords() .. " 词" end,
        sub_item_table = context_rows,
    }
    rows[#rows + 1] = {
        text_func = function()
            return API.validKey(self.storage:readKey()) and "更换 API 密钥" or "设置 API 密钥"
        end,
        callback = function() self:editKey() end,
    }
    if self.storage.import_path then
        rows[#rows + 1] = { text = "从 USB 文本导入密钥", callback = function() self:offerImport(false) end }
    end
    rows[#rows + 1] = { text = "测试连接", callback = function() self:testConnection() end }
    rows[#rows + 1] = {
        text = "移除 API 密钥",
        callback = function()
            UIManager:show(ConfirmBox:new{
                text = "移除这台设备保存的 DeepSeek API 密钥？",
                ok_text = "移除",
                ok_callback = function()
                    self:stopAuto()
                    if self.storage:removeKey() then notice("已移除密钥。") else notice("无法移除密钥。") end
                end,
            })
        end,
    }
    rows[#rows + 1] = {
        text = "清除翻译缓存",
        callback = function()
            UIManager:show(ConfirmBox:new{
                text = "清除这台设备缓存的译文？",
                ok_text = "清除",
                ok_callback = function()
                    self.auto_seen = nil
                    if self.storage:clearCache() then notice("已清除缓存。") else notice("部分缓存未能清除。") end
                end,
            })
        end,
    }
    menu_items.deepseektranslate = { text = title, sorting_hint = "tools", sub_item_table = rows }
end

function Translate:offerImport(quiet_if_missing)
    local key, found = self.storage:readImport()
    if not found then
        if not quiet_if_missing then notice("请用电脑把密钥保存为 Kindle 盘根目录的 " .. import_filename .. "，文件里只放密钥。") end
        return
    end
    if not API.validKey(key) then
        notice(import_filename .. " 中没有可导入的密钥。请用 UTF‑8 保存，文件里只放一行密钥。")
        return
    end
    local previous = self.storage:readKey()
    local replace = API.validKey(previous) and previous ~= key
    UIManager:show(ConfirmBox:new{
        text = "找到 " .. import_filename .. "。"
            .. (replace and "导入会替换当前密钥。" or "可以将密钥保存到 KOReader。")
            .. "保存成功后会移除这个临时文件。",
        ok_text = "导入并移除文件",
        cancel_text = "稍后",
        ok_callback = function()
            local ok, reason = self.storage:importKey(key)
            if not ok then
                notice(reason == "changed" and "导入文件已变化，请重新选择导入。" or "密钥保存失败，导入文件仍保留。")
                return
            end
            self:stopAuto()
            notice(reason == "retained" and "已导入密钥。临时文件未能移除，请在电脑上手动删除。"
                or "已导入密钥并移除临时文件。可点「测试连接」。")
        end,
    })
end

function Translate:editKey()
    local dialog
    dialog = InputDialog:new{
        title = "DeepSeek API 密钥",
        text_type = "password",
        input = "",
        buttons = {{
            { text = "取消", callback = function() UIManager:close(dialog) end },
            { text = "保存", callback = function()
                local key = (dialog:getInputText() or ""):match("^%s*(.-)%s*$")
                if not API.validKey(key) then notice("密钥格式不正确。") return end
                if not self.storage:saveKey(key) then notice("无法保存密钥。") return end
                UIManager:close(dialog)
                notice("密钥已保存在这台设备。可点「测试连接」。")
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Translate:runNetwork(message, auto, generation, task, finish, on_cancel)
    local function start()
        if self.closed or self.suspended or self.busy or generation ~= self.generation then return end
        if auto and not (self.auto_enabled or self.page_mode) then return end
        self.busy = true
        Trapper:wrap(function()
            local completed, result = Trapper:dismissableRunInSubprocess(function()
                local ok, value, err = pcall(task)
                if not ok then return { error = "DeepSeek 请求没有完成。" } end
                return { value = value, error = err }
            end, message)
            self.busy = false
            if self.closed or self.suspended then return end
            if generation ~= self.generation then
                self:queueAuto()
                return
            end
            if completed and (not auto or self.auto_enabled or self.page_mode) then
                finish(type(result) == "table" and result or { error = "DeepSeek 请求没有完成。" })
            elseif not completed and on_cancel then
                on_cancel()
            end
        end)
    end
    if NetworkMgr:isConnected() then start()
    elseif not auto then NetworkMgr:runWhenConnected(start) end
end

function Translate:testConnection()
    local key = self.storage:readKey()
    if not API.validKey(key) then self:editKey() return end
    self:runNetwork("正在检查 DeepSeek 连接…", false, self.generation, function() return API.check(key) end, function(result)
        notice(result.value and "DeepSeek 已连通，可以开始翻译。" or result.error)
    end)
end

function Translate:toggleAuto()
    if self.auto_enabled then self:exitPageMode() return end
    if not API.validKey(self.storage:readKey()) then self:editKey() return end
    UIManager:show(ConfirmBox:new{
        text = "这次读这本书时，每次翻页会把页面文字发送给 DeepSeek 翻译。联网请求按 API 用量计费。",
        ok_text = "开启自动翻译",
        ok_callback = function()
            self.auto_enabled = true
            self.auto_seen = nil
            self:queueAuto()
        end,
    })
end

function Translate:stopAuto()
    self.auto_enabled = false
    self.auto_seen = nil
    UIManager:unschedule(self.auto_task)
end

function Translate:queueAuto()
    if (self.auto_enabled or self.page_mode) and self.ui.document and not self.closed and not self.suspended then
        UIManager:unschedule(self.auto_task)
        UIManager:scheduleIn(0.65, self.auto_task)
    end
end

function Translate:pageChanged()
    self.generation = self.generation + 1
    self:queueAuto()
end

function Translate:onPageUpdate()
    self:pageChanged()
end

function Translate:onPosUpdate()
    self:pageChanged()
end

function Translate:onSuspend()
    self.suspended = true
    self.generation = self.generation + 1
    UIManager:unschedule(self.auto_task)
end

function Translate:onResume()
    self.suspended = false
    if self.page_view and self.page_view.loading then
        self.auto_seen = nil
        self:queueAuto()
    end
end

function Translate:onCloseDocument()
    self.closed = true
    self:exitPageMode()
    if self.ui.highlight and self.ui.highlight.removeFromHighlightDialog then
        self.ui.highlight:removeFromHighlightDialog(highlight_id)
    end
end

function Translate:translatePage(auto)
    if self.closed or self.suspended or not self.ui.document or self.busy then return end
    if auto and not (self.auto_enabled or self.page_mode) then return end
    local width, height = Device.screen:getWidth(), Device.screen:getHeight()
    self:translate(Page.pageText(self.ui, width, height), "page", auto)
end

function Translate:translate(text, kind, auto, context)
    if self.closed or self.busy then return end
    local whole_page = kind == "page"
    local function report(message)
        if whole_page then self:showPage(message, false, true) else notice(message) end
    end
    if not text or #text > API.max_input then
        report(text and "当前文字太长，可以返回原文后选择较短的一段。" or "没有取到可翻译的文字。扫描件需要文字层。")
        return
    end
    local language = self:language()
    local id = Storage.cacheId(text, language.id, API.model, API.prompt_version, context)
    if auto and self.auto_seen == id and not (self.page_view and self.page_view.loading) then return end
    local cached = self.storage:get(id)
    if cached then
        if whole_page then self.auto_seen = id end
        self:showResult(text, cached, kind)
        return
    end
    local key = self.storage:readKey()
    if not API.validKey(key) then
        if not auto then
            self:editKey()
        else
            self:stopAuto()
            report("请设置 DeepSeek API 密钥，然后重试。")
        end
        return
    end
    local online = NetworkMgr:isConnected()
    if auto and not online then
        report("本页还没有离线译文。联网后可点「重试」。")
        return
    end
    if whole_page then
        self.auto_seen = id
        if not (online and self.page_view and self.page_view.loading) then
            self:showPage(online and "正在翻译本页…" or "连上 Wi‑Fi 后可翻译本页。", online, not online)
        end
    end
    self:runNetwork("正在翻译… 点一下可取消", auto, self.generation, function()
        return API.translate(key, text, language.prompt, context)
    end, function(result)
        if not result.value then
            if auto then self:stopAuto() end
            self.auto_seen = nil
            report(result.error or "没有收到译文。")
            return
        end
        pcall(self.storage.put, self.storage, id, result.value)
        self:showResult(text, result.value, kind)
    end, whole_page and function()
        self.auto_seen = nil
        report("本页翻译已取消。")
    end or nil)
end

function Translate:showResult(source, translation, kind)
    if kind == "page" then self:showPage(translation) return end
    UIManager:show(TextViewer:new{
        title = "选段翻译",
        text = "原文\n" .. source .. "\n\n译文\n" .. translation,
    })
end

function Translate:showPage(text, loading, retry)
    if self.closed then return end
    self.page_mode = true
    if self.page_view then UIManager:close(self.page_view) end
    local page = self.ui.getCurrentPage and self.ui:getCurrentPage()
    local PageView = require("dst_pageview")
    self.page_view = PageView:new{
        title = page and ("译文阅读 · 第 " .. page .. " 页") or "译文阅读",
        text = text,
        loading = loading,
        retry_callback = retry and function() self:translatePage(false) end or nil,
        turn_callback = function(direction)
            local generation = self.generation
            self.ui:handleEvent(Event:new("GotoViewRel", direction))
            if generation ~= self.generation then self:showPage("正在准备本页…", true) end
        end,
        exit_callback = function() self:exitPageMode() end,
    }
    UIManager:show(self.page_view)
end

function Translate:exitPageMode()
    self.page_mode = false
    self.generation = self.generation + 1
    self:stopAuto()
    if self.page_view then
        UIManager:close(self.page_view)
        self.page_view = nil
    end
end

return Translate
