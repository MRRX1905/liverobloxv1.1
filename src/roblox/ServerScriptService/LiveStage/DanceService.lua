--!strict
local DanceService = {}
local Registry: any

function DanceService.Init(registry: any) Registry = registry end
function DanceService.Play(model: Model, name: string?): boolean return Registry.Play(model, name) end
function DanceService.List(): {any} return Registry.List() end

return DanceService
