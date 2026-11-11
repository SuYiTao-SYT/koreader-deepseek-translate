local BD = require("ui/bidi")
local BB = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")

local PageView = InputContainer:extend{
    covers_fullscreen = true,
    modal = true,
    stop_events_propagation = true,
}

function PageView:init()
    local screen = Device.screen
    local width, height = screen:getWidth(), screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = width, h = height }
    local top = TitleBar:new{
        width = width,
        title = self.title,
        align = "left",
        with_bottom_line = true,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }
    local buttons = {
        { text = "上一页", enabled = not self.loading, callback = function() self:turn(-1) end },
        { text = "返回原文", callback = function() self:onClose() end },
        { text = "下一页", enabled = not self.loading, callback = function() self:turn(1) end },
    }
    if self.retry_callback then
        table.insert(buttons, 3, { text = "重试", callback = self.retry_callback })
    end
    local bottom = ButtonTable:new{ width = width, buttons = { buttons }, zero_sep = true, show_parent = self }
    local body_height = height - top:getHeight() - bottom:getSize().h
    local margin = screen:scaleBySize(22)
    local body = ScrollTextWidget:new{
        text = self.text,
        face = Font:getFace("cfont", 23),
        width = width - 2 * margin,
        height = math.max(1, body_height - 2 * margin),
        auto_para_direction = true,
        dialog = self,
    }
    self[1] = FrameContainer:new{
        background = BB.COLOR_WHITE,
        bordersize = 0,
        margin = 0,
        padding = 0,
        VerticalGroup:new{
            top,
            CenterContainer:new{ dimen = Geom:new{ w = width, h = body_height }, body },
            bottom,
        },
    }
    if Device:isTouchDevice() then
        self.ges_events = {
            Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } },
        }
    end
    if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
end

function PageView:onShow()
    UIManager:setDirty(self, "ui", self.dimen)
end

function PageView:onCloseWidget()
    self:free()
    UIManager:setDirty(nil, "ui", self.dimen)
end

function PageView:turn(direction)
    if not self.loading then self.turn_callback(direction) end
    return true
end

function PageView:onSwipe(_, gesture)
    local direction = BD.flipDirectionIfMirroredUILayout(gesture.direction)
    if direction == "west" then return self:turn(1) end
    if direction == "east" then return self:turn(-1) end
end

function PageView:onClose()
    self.exit_callback()
    return true
end

return PageView
