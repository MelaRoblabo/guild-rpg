--!strict
-- インスタンスを宣言的に作る小さな関数（D-227 ①：外部のライブラリは使わない）。
--   Create("Frame", { Size = ..., [Create.Children] = { ... }, [Create.Event("Activated")] = fn })
-- 子は配列で渡す（nil・false は飛ばす）。Parent は最後に入れる（作り終える前に画面へ出さない）。

local Create = {}

export type EventKey = { event: string }

local CHILDREN = { children = true }
Create.Children = CHILDREN

local eventKeys: { [string]: EventKey } = {}

-- イベントのキー（同じ名前には同じキーを返す）
function Create.Event(name: string): EventKey
	local key = eventKeys[name]
	if key == nil then
		key = { event = name }
		eventKeys[name] = key
	end
	return key
end

function Create.new(className: string, props: { [any]: any }?): any
	local inst = Instance.new(className)
	local parent: Instance? = nil
	for k, v in props or {} do
		if k == CHILDREN then
			for _, child in v do
				if child then
					(child :: Instance).Parent = inst
				end
			end
		elseif k == "Parent" then
			parent = v
		elseif type(k) == "string" then
			(inst :: any)[k] = v
		elseif type(k) == "table" and k.event then
			((inst :: any)[k.event] :: RBXScriptSignal):Connect(v)
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

return Create
