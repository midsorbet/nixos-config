-- Draw rounded borders around the manager panes.
require("full-border"):setup { type = ui.Border.ROUNDED }

-- Display Git status indicators in the file list.
require("git"):setup()

-- Show the hovered symlink target in the status bar.
Status:children_add(function(self)
	local h = self._current.hovered
	if h and h.link_to then
		return " -> " .. tostring(h.link_to)
	else
		return ""
	end
end, 3300, Status.LEFT)
