--!strict
-- 装備の見た目（D-254）
local EquipmentLook = require("../src/core/EquipmentLook")
local Fixtures = require("./helpers/Fixtures")

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()

	describe("D-254 装備の名前と絵は段とレアリティで変わる", function()
		it("剣は段を2つずつまとめた素材の名前になる", function()
			expect(EquipmentLook.nameEn({ baseId = "eq_wpn_sword", itemLevel = 1, rarity = 1 }, master)).toBe(
				"Iron Sword"
			)
			expect(EquipmentLook.nameEn({ baseId = "eq_wpn_sword", itemLevel = 2, rarity = 3 }, master)).toBe(
				"Iron Sword"
			)
			expect(EquipmentLook.nameEn({ baseId = "eq_wpn_sword", itemLevel = 5, rarity = 2 }, master)).toBe(
				"Mithril Sword"
			)
			expect(EquipmentLook.nameEn({ baseId = "eq_wpn_sword", itemLevel = 12, rarity = 1 }, master)).toBe(
				"Celestial Sword"
			)
		end)
		it("エピック以上は銘入りになる", function()
			expect(EquipmentLook.nameEn({ baseId = "eq_wpn_sword", itemLevel = 5, rarity = 4 }, master)).toBe(
				"Azure Thunder"
			)
			expect(EquipmentLook.nameEn({ baseId = "eq_wpn_sword", itemLevel = 12, rarity = 6 }, master)).toBe(
				"Godslayer"
			)
		end)
		it("指輪・護符は4段ずつまとめ、銘入りはない", function()
			expect(EquipmentLook.nameEn({ baseId = "eq_sub_ring_power", itemLevel = 4, rarity = 6 }, master)).toBe(
				"Ring of Power"
			)
			expect(EquipmentLook.nameEn({ baseId = "eq_sub_ring_power", itemLevel = 5, rarity = 1 }, master)).toBe(
				"Ring of Might"
			)
			expect(EquipmentLook.nameEn({ baseId = "eq_sub_amulet_learning", itemLevel = 12, rarity = 1 }, master)).toBe(
				"Amulet of Enlightenment"
			)
		end)
		it("アイテムレベルのない古い品は段1として扱う", function()
			expect(EquipmentLook.nameEn({ baseId = "eq_arm_chainmail", rarity = 1 }, master)).toBe("Chainmail")
		end)
		it("見た目には画像のアセットIDがある", function()
			local img = EquipmentLook.image({ baseId = "eq_wpn_staff", itemLevel = 3, rarity = 1 }, master)
			expect(img ~= nil and string.match(img, "^rbxassetid://%d+$") ~= nil).toBe(true)
		end)
	end)
end
