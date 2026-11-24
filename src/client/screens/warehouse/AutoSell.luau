--!strict
-- S-51 自動売却の設定（D-167・SetAutoSell）。倉庫の右上の茶のボタンから重ねる羊皮紙の面。
--   - オン／オフのスイッチ、売るレアリティの上限（形の列）、修飾語つきを残すスイッチ。
--   - 触ったらすぐ効く（保存ボタンなし）。閉じるのは右上の ×。
--   - 「商人で買った装備は売らない」「売却用アイテムは常に売る」は変えられないので出さない（Q19）。

local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local Nav = require("../../ui/Nav")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local WarehouseCommon = require("./WarehouseCommon")

local C = Tokens.color
local I = WarehouseCommon.icon
local new = Create.new
local CHILDREN = Create.Children

local function build(_params: any?, api: Nav.Api): Nav.Built
	local frame: Frame = new("Frame", {
		Name = "AutoSell",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	local busy = false
	local panel, content = Components.panel({
		size = UDim2.fromOffset(640, 360),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		title = I.recycle,
	})
	panel.Parent = frame
	local close = Components.closeButton(api.close)
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = UDim2.new(1, -18, 0, 18)
	close.ZIndex = 20
	close.Parent = panel

	local rows: Frame = new("Frame", {
		Name = "Rows",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = content,
	})

	local render: () -> ()
	local function set(enabled: boolean, maxRarity: number, keep: boolean)
		if busy then
			return
		end
		busy = true
		Session.sendAndWait({ type = "SetAutoSell", enabled = enabled, maxRarity = maxRarity, keepModified = keep })
		busy = false
		render()
	end

	render = function()
		rows:ClearAllChildren()
		local view = Session.view
		if view == nil then
			return
		end
		local a = view.settings.autoSell
		new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = rows })
		local function row(order: number, height: number, faded: boolean): Frame
			return new("Frame", {
				Name = "Row" .. order,
				LayoutOrder = order,
				Size = UDim2.new(1, 0, 0, height),
				BackgroundColor3 = C.ch75,
				BackgroundTransparency = if faded then 0.45 else 0,
				[CHILDREN] = { Components.corner(6), Components.padding(0, 12, 0, 16) },
				Parent = rows,
			})
		end
		-- オン／オフ
		local r1 = row(1, 84, false)
		local ic = Components.text({ text = I.recycle, size = 34, color = C.inkDark, font = Tokens.font.number })
		ic.AnchorPoint = Vector2.new(0, 0.5)
		ic.Position = UDim2.fromScale(0, 0.5)
		ic.Parent = r1
		local sw = WarehouseCommon.switch("Enabled", a.enabled, function()
			set(not a.enabled, a.maxRarity, a.keepModified ~= false)
		end)
		sw.AnchorPoint = Vector2.new(1, 0.5)
		sw.Position = UDim2.fromScale(1, 0.5)
		sw.Parent = r1
		-- 売るレアリティの上限
		local r2 = row(2, 92, not a.enabled)
		local steps = WarehouseCommon.raritySteps(a.maxRarity, 576, function(r)
			set(a.enabled, r, a.keepModified ~= false)
		end)
		steps.AnchorPoint = Vector2.new(0, 0.5)
		steps.Position = UDim2.new(0, -4, 0.5, 0)
		steps.Parent = r2
		-- 修飾語つきを残す
		local r3 = row(3, 84, not a.enabled)
		local keepIc = Components.text({
			text = I.modifier .. " " .. I.warehouse,
			size = 30,
			color = C.inkDark,
			font = Tokens.font.number,
		})
		keepIc.AnchorPoint = Vector2.new(0, 0.5)
		keepIc.Position = UDim2.fromScale(0, 0.5)
		keepIc.Parent = r3
		local sw2 = WarehouseCommon.switch("KeepModified", a.keepModified ~= false, function()
			set(a.enabled, a.maxRarity, not (a.keepModified ~= false))
		end)
		sw2.AnchorPoint = Vector2.new(1, 0.5)
		sw2.Position = UDim2.fromScale(1, 0.5)
		sw2.Parent = r3
	end

	render()
	local conn = Session.changed:connect(function()
		if not busy then
			render()
		end
	end)
	return {
		frame = frame,
		destroy = function()
			conn.disconnect()
		end,
	}
end

Nav.register("AutoSell", build)

return {}
