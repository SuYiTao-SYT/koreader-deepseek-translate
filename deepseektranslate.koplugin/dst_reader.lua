local Reader = {}
Reader.context_choices = { 25, 50, 75, 100, 200 }
Reader.default_context_words = 75

function Reader.contextWordCount(value)
    for _, count in ipairs(Reader.context_choices) do
        if value == count then return count end
    end
    return Reader.default_context_words
end

function Reader.clean(text)
    if type(text) ~= "string" then return end
    text = text:gsub("\r\n?", "\n"):gsub("%z", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text ~= "" then return text end
end

local function extract(ui, width, height)
    local doc = ui.document
    local start_pos, end_pos
    if ui.rolling then
        start_pos, end_pos = { x = 0, y = 0 }, { x = width, y = height }
    elseif ui.paging then
        local page = ui:getCurrentPage()
        local rows = doc:getTextBoxes(page)
        local first, last
        for _, row in ipairs(rows or {}) do
            if type(row) == "table" then
                for _, box in ipairs(row) do
                    if type(box) == "table" and box.word and box.x0 and box.y0 and box.x1 and box.y1 then
                        first, last = first or box, box
                    end
                end
            end
        end
        if not first then return end
        start_pos = { x = first.x0, y = first.y0, page = page }
        end_pos = { x = last.x1, y = last.y1 }
    else
        return
    end
    local result = doc:getTextFromPositions(start_pos, end_pos, true)
    return Reader.clean(result and result.text)
end

function Reader.pageText(ui, width, height)
    if not ui or not ui.document then return end
    local config = ui.paging and ui.document.configurable
    local wrap = config and config.text_wrap
    if config then config.text_wrap = 0 end
    local ok, text = pcall(extract, ui, width, height)
    if config then config.text_wrap = wrap end
    if ok then return text end
end

local function fitContext(text, tail, word_limit)
    text = Reader.clean(text)
    if not text then return end
    text = text:gsub("\194\160", " ")
    local starts, ends = {}, {}
    for first, last in text:gmatch("()%S+()") do
        starts[#starts + 1] = first
        ends[#ends + 1] = last
    end
    if #starts > word_limit then
        text = tail and text:sub(starts[#starts - word_limit + 1]) or text:sub(1, ends[word_limit] - 1)
    end
    local byte_limit = math.min(4096, word_limit * 24)
    if #text <= byte_limit then return Reader.clean(text) end
    if tail then
        return Reader.clean((text:sub(-byte_limit):gsub("^[\128-\191]+", "")))
    end
    local cut = byte_limit + 1
    while cut > 1 and text:byte(cut) >= 128 and text:byte(cut) <= 191 do cut = cut - 1 end
    return Reader.clean(text:sub(1, cut - 1))
end

local function compact(text)
    return Reader.clean(text) and text:gsub("\194\160", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
end

function Reader.selectionContext(highlight, ui, text, width, height, words)
    local count = Reader.contextWordCount(words)
    local before, after
    if highlight.getSelectedWordContext then
        -- CREngine's implementation walks inclusive bounds; paged PDFs count words directly.
        local native_count = ui.rolling and count - 1 or count
        local ok, previous, following = pcall(highlight.getSelectedWordContext, highlight, native_count)
        if ok then before, after = fitContext(previous, true, count), fitContext(following, false, count) end
    end
    if not before and not after then
        local visible, selected = compact(Reader.pageText(ui, width, height)), compact(text)
        local start, finish
        if visible and selected and selected ~= "" then start, finish = visible:find(selected, 1, true) end
        if start and not visible:find(selected, start + 1, true) then
            before = fitContext(visible:sub(1, start - 1), true, count)
            after = fitContext(visible:sub(finish + 1), false, count)
        end
    end
    if before or after then return { before = before or "", after = after or "" } end
end

return Reader
