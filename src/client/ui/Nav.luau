--!strict
-- 画面の重ね方（D-134・D-222）。NavStack（純粋）の上に、見た目と入力をつなぐ。
--   - 画面は register(id, build) で登録し、open / replace / close / home で動かす。
--   - 重ねた画面の後ろには暗幕（約75%：D-222 ⑪）。画面ごとに暗幕の濃さを変えられる（D-225 ③）。
--   - ゲームパッドの B・キーボードの Esc で一段閉じる（D-139・D-222）。

local ContextActionService = game:GetService("ContextActionService")

local Create = require("./Create")
local NavStack = require("./NavStack")
local Root = require("./Root")
local Tokens = require("./Tokens")

local Nav = {}

export type Api = {
	close: () -> (),
	replace: (id: string, params: any?) -> (),
	open: (id: string, params: any?) -> (),
	home: () -> (),
}
-- passThrough：画面の外（暗幕）を押しても下へ通す（3D マップのカメラを動かせるように：D-270）
export type Built = { frame: GuiObject, scrim: number?, destroy: (() -> ())?, passThrough: boolean? }
export type Builder = (params: any?, api: Api) -> Built

local builders: { [string]: Builder } = {}
local stack = NavStack.new()
local layers: { { holder: Frame, built: Built } } = {}

local api: Api

local function destroyLayer(layer: { holder: Frame, built: Built })
	if layer.built.destroy then
		layer.built.destroy()
	end
	layer.holder:Destroy()
end

local function makeLayer(id: string, params: any?): { holder: Frame, built: Built }
	local build = builders[id]
	assert(build, "画面が登録されていない: " .. id)
	local built = build(params, api)
	local scrim = built.scrim or Tokens.transparency.scrim
	local holder: Frame = Create.new("Frame", {
		Name = "Layer_" .. id,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Tokens.color.scrim,
		BackgroundTransparency = scrim,
		ZIndex = 10 + #layers * 10,
		Active = not built.passThrough, -- 下の画面を押せないようにする（3D マップの面は通す）
		Parent = Root.canvas,
	})
	built.frame.Parent = holder
	return { holder = holder, built = built }
end

function Nav.register(id: string, build: Builder)
	builders[id] = build
end

function Nav.open(id: string, params: any?)
	local pushedOut = stack:push(id, params)
	if pushedOut then
		destroyLayer(table.remove(layers, 1) :: any)
	end
	table.insert(layers, makeLayer(id, params))
end

function Nav.replace(id: string, params: any?)
	stack:replace(id, params)
	local top = table.remove(layers)
	if top then
		destroyLayer(top)
	end
	table.insert(layers, makeLayer(id, params))
end

function Nav.close()
	if stack:pop() then
		local top = table.remove(layers)
		if top then
			destroyLayer(top)
		end
	end
end

function Nav.home()
	stack:home()
	while #layers > 0 do
		destroyLayer(table.remove(layers) :: any)
	end
end

function Nav.depth(): number
	return stack:depth()
end

-- いちばん上の画面が、下（3D マップ）へ入力を通す面か（パーティ・ダンジョンの面：D-270）
function Nav.topPassThrough(): boolean
	local top = layers[#layers]
	return top ~= nil and top.built.passThrough == true
end

api = {
	close = Nav.close,
	replace = Nav.replace,
	open = Nav.open,
	home = Nav.home,
}

ContextActionService:BindAction("GuildUIClose", function(_, state)
	if state == Enum.UserInputState.Begin and stack:depth() > 0 then
		Nav.close()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.ButtonB, Enum.KeyCode.Escape)

return Nav
