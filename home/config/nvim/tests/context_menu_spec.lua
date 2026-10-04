local context_menu = require("core.context_menu")
local test = context_menu._test

local function assert_equal(actual, expected, message)
	if not vim.deep_equal(actual, expected) then
		error((message or "values differ") .. ": expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
	end
end

local top_left = test.calculate_geometry({ screenrow = 2, screencol = 3 }, 20, 5, 120, 40)
assert_equal(top_left.anchor, "NW", "top-left anchor")
assert_equal(top_left.position, { row = 1, col = 2 }, "top-left position")

local bottom_right = test.calculate_geometry({ screenrow = 39, screencol = 119 }, 20, 5, 120, 40)
assert_equal(bottom_right.anchor, "SE", "bottom-right anchor")

local narrow_editor = test.calculate_geometry({ screenrow = 9, screencol = 19 }, 6, 4, 20, 10)
assert_equal(narrow_editor.anchor, "SE", "narrow editor anchor")
assert(narrow_editor.position.row < 10 and narrow_editor.position.col < 20, "narrow editor position should remain visible")

assert_equal(test.truncate_label("Open in Vertical Split", 10), "Open in V…", "long labels should preserve cell width")

assert(test.point_in_visual_selection(
	{ line = 3, column = 4 },
	"v",
	{ 0, 2, 2, 0 },
	{ 0, 4, 6, 0 }
), "character selection should contain an interior point")
assert(not test.point_in_visual_selection(
	{ line = 4, column = 7 },
	"v",
	{ 0, 2, 2, 0 },
	{ 0, 4, 6, 0 }
), "character selection should reject a point after its final column")
assert(test.point_in_visual_selection(
	{ line = 3, column = 80 },
	"V",
	{ 0, 2, 2, 0 },
	{ 0, 4, 6, 0 }
), "line selection should contain every column")
assert(test.point_in_visual_selection(
	{ line = 3, column = 4 },
	"\22",
	{ 0, 2, 2, 0 },
	{ 0, 4, 6, 0 }
), "block selection should contain an interior point")

local items = test.normalized_items({
	{ separator = true },
	{ label = "Open", key = "o", action = function() end },
	{ separator = true },
	{ separator = true },
	{ label = "Hidden", key = "h", action = function() end, enabled = false },
	{ label = "Close", key = "c", action = function() end },
	{ separator = true },
})
assert_equal(#items, 3, "separator normalization")
assert(items[2].separator, "one interior separator should remain")

local unique_shortcuts = pcall(test.normalized_items, {
	{ label = "First", key = "x", action = function() end },
	{ label = "Second", key = "x", action = function() end },
})
assert(not unique_shortcuts, "duplicate shortcuts should be rejected")

print("context-menu-tests-ok")
