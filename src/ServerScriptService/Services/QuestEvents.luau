--!strict
-- QuestEvents: other services report what players do here ("kill", "orb", ...)
-- and QuestService listens. It's a separate module so services don't have to
-- require each other in a circle.

local QuestEvents = {}
local handler: ((Player, string, any, number) -> ())? = nil

function QuestEvents.SetHandler(fn: (Player, string, any, number) -> ())
	handler = fn
end

function QuestEvents.Fire(player: Player, kind: string, key: any?, amount: number?)
	if handler then task.spawn(handler, player, kind, key, amount or 1) end
end

return QuestEvents
