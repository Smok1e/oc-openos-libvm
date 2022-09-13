-- Virtual machine library (vm)
-- Helps to handle with virtual components, filesystem, etc.

-------------------------------------------

local component = require ("component")
local computer  = require ("computer")
local crc32     = require ("libvm_crc32")

local gpu = component.gpu
local fs = component.proxy (computer.getBootAddress ())

local vm = {}
vm.vendor = "Smok1e shitcode Ltd."

------------------------------------------- Components

vm.component = {}
vm.component.list = {}
vm.component.proxyLog = false -- Set this value to true will enable virtual components proxy functions logging

function vm.component.generateComponentID (componentName)
    checkArg (1, componentName, "string")

    local id = "libvm-virtual-" .. componentName .. "-"
    for i = 1, 8 do
        id = id .. string.char (math.random (string.byte ('0'), string.byte ('9')))
    end
    
    id = id .. '-'
    for i = 1, 8 do
        id = id .. string.char (math.random (string.byte ('a'), string.byte ('z')))
    end

    return id
end

function vm.component.registerVirtualComponent (instance)
    checkArg (1, instance, "table")
    if vm.component.list[instance.address] then
        error ("component exists")
    end
    
    vm.component.list[instance.address] = instance 
    vm.computer.api.pushSignal ("component_added", instance.address, instance.name)
    return instance
end

function vm.component.deleteVirtualComponent (instance)
    checkArg (1, instance, "table", "table")
    if not vm.component.list[instance.address] then
        error ("no such component")
    end

    vm.component.list[instance.address] = nil
    vm.computer.api.pushSignal ("component_removed", instance.address, instance.name)
    return true
end

-- If <noexcept> is not false or nil, calls error if such component does not exist
function vm.component.getInstance (address, noexcept)
    checkArg (1, address,  "string",  "nil")
    checkArg (1, noexcept, "boolean", "nil")

    if not address then
        if noexcept then
            return nil, "no such component"
        end

        error ("no such component")
    end

    local instance = vm.component.list[address]
    if not instance then
        if noexcept then
            return nil, "no such component"
        end

        error ("no such component")
    end

    return instance
end

-- Calls release function for each registered (i. e. created) virtual component
-- Returns count of objects that wasn't released yet
function vm.component.releaseAll ()
    local count = 0
    for address, instance in pairs (vm.component.list) do
        if instance:release () then
            count = count+1
        end
    end

    return count
end

------------------------------------------- Component API

vm.component.api = {}

function vm.component.api.slot (address)
    checkArg (1, address, "string")
    if not vm.component.list[address] then
        error ("no such component")
    end

    -- -1 is value returned by original component.slot function when component is external (keyboard, screen, holo, etc).
    -- So we also do this cause all of our components are virtual
    return -1
end

function vm.component.api.type (address)
    checkArg (1, address, "string")
    return vm.component.getInstance (address).name
end

function vm.component.methods (address)
    checkArg (1, address, "string")
    
    local instance = vm.component.getInstance (address)
    local methods = {}
    for key, method in pairs (instance) do
        if type (method) == "function" then
            methods[key] = true
        end
    end

    return methods
end

function vm.component.api.fields (address)
    checkArg (1, address, "string")
    
    local instance = vm.component.getInstance (address)
    local fields = {}
    for key, field in pairs (instance) do
        if type (field) ~= "function" then
            fields[key] = true
        end
    end

    return fields
end

function vm.component.api.doc (address, method)
    checkArg (1, address, "string")
    checkArg (2, method,  "string")

    return "Virtual component documentation is not yet implemented. Use original component api to get documentation"
end

function vm.component.api.invoke (address, method, ...)
    checkArg (1, address, "string")
    checkArg (2, method,  "string")

    local instance = vm.component.getInstance (address)
    if not instance[method] then
        error ("no such method")
    end

    return instance[method] (instance, ...)
end

function vm.component.api.list (filter, exact)
    checkArg (1, filter, "string",  "nil")
    checkArg (2, exact,  "boolean", "nil")

    local list = {}
    for address, instance in pairs (vm.component.list) do
        if filter then
            if exact then
                if instance.name == filter then
                    list[address] = instance.name
                end
            else
                if string.find (instance.name, filter) then
                    list[address] = instance.name
                end
            end
        else
            list[address] = instance.name
        end
    end

    local key = nil
    return setmetatable (list, {
        __call = function ()
            key = next (list, key)
            if key then
                return key, list[key]
            end
        end
    })
end

function vm.component.api.proxy (address)
    checkArg (1, address, "string")
    
    local instance, reason = vm.component.getInstance (address, true)
    if not instance then
        return nil, reason
    end

    return instance:proxy ()
end

function vm.component.api.get (address, componentType)
    checkArg (1, address,       "string"       )
    checkArg (2, componentType, "string", "nil")

    for existingAddress, instance in pairs (vm.component.list) do
        if existingAddress:find (address) then
            if componentType then
                if instance.name == componentType then
                    return existingAddress
                end

                return nil
            else
                return existingAddress
            end
        end
    end

    return nil, "no such component"
end

------------------------------------------- Computer

vm.computer = {}
vm.computer.address = vm.component.generateComponentID ("computer")
vm.computer.startTime = computer.uptime ()
vm.computer.eventQueue = {}
vm.computer.eventLog = false -- Set this value to true will enable virtual coumputer events logging

function vm.computer.handleEvent (event)
    checkArg (1, event, "table")

    if #event < 1 then
        return false
    end

    for address, instance in pairs (vm.component.list) do
        if instance:handleEvent (event) then
            return true
        end
    end

    local function pass ()
        vm.computer.api.pushSignal (table.unpack (event))
        return true
    end

    local eventType = event[1]
    if eventType == 'key_down'      then return pass () end
    if eventType == 'modem_message' then return pass () end

    return true
end

function vm.computer.getDeviceInfo ()
    return {
        vendor = vm.vendor,
        class = "system",
        description = "libvm Virtual Computer",
        product = "Shitmachine v1.0"
    }
end

function vm.computer.setTmpAddress (address)
    checkArg (1, address, "string")
    if not vm.component.list[address] or vm.component.list[address].name ~= "filesystem" then
        return false, "no such component"
    end

    vm.computer.tmlFilesystemAddress = address
    return address
end

------------------------------------------- Computer API

vm.computer.api = {}

function vm.computer.api.uptime ()
    return computer.uptime () - vm.computer.startTime
end

function vm.computer.api.users ()
    return {} -- TODO: Implement user list
end

function vm.computer.api.addUser ()
    return false
end

function vm.computer.api.setArchitecture (architecture)
    checkArg (1, architecture, "string")
    return false
end

function vm.computer.api.getArchitecture ()
    return computer.getArchitecture ()
end

function vm.computer.api.getArchitectures ()
    return {
        computer.getArchitecture (),
        n = 1
    }
end

function vm.computer.api.totalMemory ()
    return computer.totalMemory ()
end

function vm.computer.api.freeMemory ()
    return computer.freeMemory ()
end

function vm.computer.api.getDeviceInfo ()
    info = {}

    info[vm.computer.address] = vm.computer.getDeviceInfo ()
    for address, instance in pairs (vm.component.list) do
        info[address] = instance:getDeviceInfo ()
    end
end

function vm.computer.api.pushSignal (name, ...)
    checkArg (1, name, "string")
    vm.computer.eventQueue[#vm.computer.eventQueue+1] = {name, ...}
end

function vm.computer.api.pullSignal (timeout)
    checkArg (1, timeout, "number", "nil")

    for index, instance in pairs (vm.component.list) do
        if instance.name == 'screen' and instance.autoDisplay ~= true then
            instance:display ()
        end
    end

    vm.computer.handleEvent ({computer.pullSignal (timeout)})
    if #vm.computer.eventQueue > 0 then
        if vm.computer.eventLog then
            local handle = fs.open ('/vm_events.log', 'a')
            if handle then
                for index, value in pairs (vm.computer.eventQueue[1]) do
                    fs.write (handle, string.format ("%-10s", tostring (value)))
                end

                fs.write (handle, "\n")
            end

            fs.close (handle)
        end

        return table.unpack (table.remove (vm.computer.eventQueue, 1))
    end
end

function vm.computer.api.beep (...)
    return computer.beep (...)
end

function vm.computer.api.energy (...)
    return computer.energy (...)
end

function vm.computer.api.maxEnergy (...)
    return computer.maxEnergy (...)
end

function vm.computer.api.shutdown (reboot)
    checkArg (1, reboot, "boolean", "nil")

    -- Intentionally throws an error that interrupts virtual machine process
    if reboot then
        error ("libvm_reboot")
    else
        error ("libvm_shutdown")
    end
end

function vm.computer.api.setBootAddress (bootAddress)
    checkArg (1, bootAddress, "string")

    local eeprom, reason = vm.component.getInstance (vm.component.api.list ("eeprom")(), true)
    if not eeprom then
        return nil, reason
    end

    eeprom:setData (bootAddress)
end

function vm.computer.api.getBootAddress ()
    local eeprom, reason = vm.component.getInstance (vm.component.api.list ("eeprom")(), true)
    if not eeprom then
        return nil, reason
    end

    return eeprom:getData ()
end

function vm.computer.api.tmpAddress ()
    return vm.computer.tmlFilesystemAddress
end

------------------------------------------- Virtual components

-- Destructor can be used to free any data that component allocates.
-- vram-buffers of virtual gpu for example
local function virtualComponentRelease (virtualComponent)
    if virtualComponent.destructed then
        return false
    end

    vm.component.deleteVirtualComponent (virtualComponent)
    virtualComponent.destructed = true
    return true
end

-- Returns component proxy, which allows to call methods with '.' instead of ':', like gpu.fill (1, 1, 10, 10, ' ')
local function virtualComponentProxy (virtualComponent)
    return setmetatable ({}, {
        __index = function (_, key)
            local value = virtualComponent[key]

            if type (value) == "function" then
                local wrapper = function (...)
                    if vm.component.proxyLog then -- Writing proxies logs in debugging purposes
                        local handle = fs.open ('/vm_proxies.log', 'a')
                        if handle then
                            fs.write (handle, string.format ("%-48s %-10s   %-10s ", virtualComponent.address, virtualComponent.name, key))
                            for index, value in pairs ({...}) do
                                fs.write (handle, string.format ("%-10s ", tostring (value)))
                            end
                            fs.write (handle, "\n")
                            fs.close (handle)
                        end
                    end

                    return value (virtualComponent, ...)
                end

                return wrapper
            end

            return value
        end
    })
end

-- Information returned by this function will be returned from vm.computer.api.getDeviceInfo ()
local function virtualComponentGetDeviceInfo (virtualComponent)
    return {
        vendor = vm.vendor,
        class = "basic",
        desctiption = "Basic (abstract) virtual component",
        product = "libvm Virtual Component"
    }
end

local function virtualComponentHandleEvent (virtualComponent, event)
    return false
end

function vm.component.newVirtualComponent (componentName)
    local virtualComponent = {
        destructed = false, -- Used to avoid destructing an already destructed object
        name = componentName,
        address = vm.component.generateComponentID (componentName),

        release = virtualComponentRelease,
        proxy = virtualComponentProxy,
        handleEvent = virtualComponentHandleEvent,
        getDeviceInfo = virtualComponentGetDeviceInfo
    }

    return vm.component.registerVirtualComponent (virtualComponent)
end

------------------------------------------- GPU

local function virtualGpuRelease (virtualGpu)
    if virtualGpu.destructed then
        return false
    end

    if virtualGpu.screenBuffer then
        gpu.freeBuffer (virtualGpu.screenBuffer)
    end

    if virtualGpu.boundScreen then
        if virtualGpu.boundScreen.boundGpu == virtualGpu then
            virtualGpu.boundScreen.boundGpu = nil
        end

        virtualGpu.boundScreen = nil
    end

    return virtualComponentRelease (virtualGpu)
end

local function virtualGpuGetDeviceInfo (virtualGpu)
    return {
        vendor = vm.vendor,
        class = "display",
        product = "VirtualGraphicalUnit X-slow",
        description = "libvm Virtual GPU"
    }
end

-- Used to execute gpu methods in local screen buffer
local function virtualGpuExecute (virtualGpu, method, ...)
    local oldBuffer = gpu.getActiveBuffer ()
    gpu.setActiveBuffer (virtualGpu.activeBuffer)
    
    local result = {xpcall (method, debug.traceback, ...)}
    gpu.setActiveBuffer (oldBuffer)

    if not result[1] then
        error (result[2])
    end

    if virtualGpu.boundScreen and virtualGpu.boundScreen.autoDisplay then
        virtualGpu.boundScreen:display ()
    end

    return table.unpack (result, 1)
end

local function virtualGpuMaxResolution (virtualGpu)
    return virtualGpu.maxResolutionX, virtualGpu.maxResolutionY
end

local function virtualGpuSetResolution (virtualGpu, resolutionX, resolutionY)
    checkArg (1, resolutionX, "number")
    checkArg (2, resolutionY, "number")

    if resolutionX < 1 or resolutionX > virtualGpu.maxResolutionX or resolutionY < 1 or resolutionY > virtualGpu.maxResolutionY then
        error ("unsupported resolution")
    end

    if resolutionX == virtualGpu.resolutionX and resolutionY == virtualGpu.resolutionY then
        return false
    end

    -- Resizing video buffer
    virtualGpu.releaseBuffer (screenBuffer)
    virtualGpu.screenBuffer, reason = virtualGpu.allocateBuffer (resolutionX, resolutionY)
    if not virtualGpu.screenBuffer then
        error (reason)
    end

    virtualGpu.resolutionX = resolutionX
    virtualGpu.resolutionY = resolutionY
    return true
end

local function virtualGpuGetResolution (virtualGpu)
    return virtualGpu.resolutionX, virtualGpu.resolutionY
end

local function virtualGpuSet (virtualGpu, x, y, text, vertical)
    checkArg (1, x,        "number"        )
    checkArg (2, y,        "number"        )
    checkArg (3, text,     "string"        )
    checkArg (4, vertical, "boolean", "nil")

    return virtualGpu:execute (gpu.set, x, y, text, vertical)
end

local function virtualGpuGet (virtualGpu, x, y)
    checkArg (1, x, "number")
    checkArg (2, y, "number")

    return virtualGpu:execute (gpu.set, x, y)
end

local function virtualGpuFill (virtualGpu, x, y, width, height, character)
    checkArg (1, x,         "number")
    checkArg (2, y,         "number")
    checkArg (3, width,     "number")
    checkArg (4, height,    "number")
    checkArg (5, character, "string")

    return virtualGpu:execute (gpu.fill, x, y, width, height, character)
end

local function virtualGpuSetBackground (virtualGpu, value, palette)
    checkArg (1, value,   "number"       )
    checkArg (2, palette, "number", "nil")

    -- Опытным путём я выяснил, что background и foreground привязаны к vram-буферу
    -- По этому можно не кешировать эти параметры и полагаться полностью на видеопамять
    return virtualGpu:execute (gpu.setBackground, value, palette)
end

local function virtualGpuGetBackground (virtualGpu)
    return virtualGpu:execute (gpu.getBackground)
end

local function virtualGpuSetForeground (virtualGpu, value, palette)
    checkArg (1, value,   "number"       )
    checkArg (2, palette, "number", "nil")

    return virtualGpu:execute (gpu.setForeground, value, palette)
end

local function virtualGpuGetForeground (virtualGpu)
    return virtualGpu:execute (gpu.getForeground)
end

local function virtualGpuBind (virtualGpu, address, reset)
    checkArg (1, address, "string"        )
    checkArg (2, reset,   "boolean", "nil")

    local screenInstance, reason = vm.component.getInstance (address, true)
    if not screenInstance then
        return nil, reason
    end

    screenInstance.boundGpu = virtualGpu
    virtualGpu.boundScreen  = screenInstance

    return true
end

local function virtualGpuGetScreen (virtualGpu)
    if virtualGpu.boundScreen then
        return virtualGpu.boundScreen.address
    end
end

function vm.component.newVirtualGpu (maxResolutionX, maxResolutionY)
    checkArg (1, resolutionX, "number", "nil")
    checkArg (2, resolutionY, "number", "nil")

    local actualMaxResolutionX, actualMaxResolutionY = gpu.getResolution ()
    local virtualGpu = vm.component.newVirtualComponent ("gpu")

    virtualGpu.maxResolutionX = maxResolutionX or actualMaxResolutionX
    virtualGpu.maxResolutionY = maxResolutionY or actualMaxResolutionY
    virtualGpu.resolutionX = virtualGpu.maxResolutionX
    virtualGpu.resolutionY = virtualGpu.maxResolutionY
    virtualGpu.boundScreen = nil -- Sets with bound function

    virtualGpu.release = virtualGpuRelease
    virtualGpu.execute = virtualGpuExecute
    virtualGpu.getDeviceInfo = virtualGpuGetDeviceInfo

    virtualGpu.maxResolution = virtualGpuMaxResolution
    virtualGpu.setResolution = virtualGpuSetResolution
    virtualGpu.getResolution = virtualGpuGetResolution
    virtualGpu.set = virtualGpuSet
    virtualGpu.get = virtualGpuGet
    virtualGpu.fill = virtualGpuFill
    virtualGpu.setBackground = virtualGpuSetBackground
    virtualGpu.getBackground = virtualGpuGetBackground
    virtualGpu.setForeground = virtualGpuSetForeground
    virtualGpu.getForeground = virtualGpuGetForeground
    virtualGpu.bind = virtualGpuBind
    virtualGpu.getScreen = virtualGpuGetScreen

    virtualGpu.screenBuffer, reason = gpu.allocateBuffer (virtualGpu.resolutionX, virtualGpu.resolutionY)
    if not virtualGpu.screenBuffer then
        virtualGpu:release ()
        error (reason)
    end

    virtualGpu.activeBuffer = virtualGpu.screenBuffer
    return virtualGpu
end

------------------------------------------- Screen

local function virtualScreenRelease (virtualScreen)
    if virtualScreen.desrtucted then
        return false
    end

    if virtualScreen.boundGpu then
        if virtualScreen.boundGpu.boundScreen == virtualScreen then
            virtualScreen.boundGpu.boundScreen = nil
        end

        virtualScreen.boundGpu = nil
    end

    return virtualComponentRelease (virtualScreen)
end

local function virtualScreenHandleEvent (virtualScreen, event)
    local eventType, address, x, y, button, nickname = table.unpack (event)

    if eventType == "touch" or eventType == "drag" or eventType == "drop" or eventType == "scroll" then
        local sizeX, sizeY = virtualScreen:getVisualSize ()
        local screenX, screenY = x-virtualScreen.visualPositionX, y-virtualScreen.visualPositionY
        
        if screenX >= 1 and screenX < sizeX+1 and screenY >= 1 and screenY < sizeY+1 then
            vm.computer.api.pushSignal (eventType, virtualScreen.address, screenX, screenY, button, nickname)
            return true
        end
    end
end

local function virtualScreenGetDeviceInfo (virtualScreen)
    return {
        vendor = vm.vendor,
        class = "display",
        product = "CoolScreen model turbo",
        description = "libvm Virtual Text Screen"
    }
end

-- Displays virtual screen like window
local function virtualScreenDisplay (virtualScreen)
    local sizeX, sizeY = virtualScreen:getVisualSize ()
    local x, y = virtualScreen.visualPositionX, virtualScreen.visualPositionY

    gpu.setBackground (0x000000)
    gpu.setForeground (virtualScreen.visualBorderColor)
    gpu.fill (x+1,       y,         sizeX, 1,     '⣀')
    gpu.fill (x+1,       y+sizeY+1, sizeX, 1,     '⠉')
    gpu.fill (x,         y+1,       1,     sizeY, '⢸')
    gpu.fill (x+sizeX+1, y+1,       1,     sizeY, '⡇')

    local lines = {}
    if not virtualScreen.power    then table.insert (lines, "Screen is turned off") end
    if not virtualScreen.boundGpu then table.insert (lines, "GPU Not bound"       ) end

    if #lines > 0 then
        gpu.setBackground (0x000000)
        gpu.setForeground (virtualScreen.visualTextColor)
        gpu.fill (x+1, y+1, sizeX, sizeY, ' ')
        
        for index, text in pairs (lines) do
            gpu.set (x+1+sizeX/2-#text/2, y+sizeY/2-#lines/2+index, text)
        end
    elseif virtualScreen.boundGpu then
        gpu.bitblt (0, x+1, y+1, virtualScreen.boundGpu.resolutionX, virtualScreen.boundGpu.resolutionY, virtualScreen.boundGpu.screenBuffer)
    end
end

-- If any gpu is bound to the screen, the function returns it's resolution.
-- Otherwise returns half of real used gpu resolution as default value
local function virtualScreenGetVisualSize (virtualScreen)
    if virtualScreen.boundGpu then
        return virtualScreen.boundGpu.resolutionX, virtualScreen.boundGpu.resolutionY
    end

    local realResolutionX, realResolutionY = gpu.getResolution ()
    return math.floor (realResolutionX/2), math.floor (realResolutionY/2)
end

local function virtualScreenSetPrecise (virtualScreen, enabled)
    checkArg (1, enabled, "boolean")
    return false -- Unfortunately, there is no way to emulate precise touch events
end

local function virtualScreenIsPrecise (virtualScreen)
    return false
end

local function virtualScreenTurnOff (virtualScreen)
    if virtualScreen.power then
        virtualScreen.power = false
        return true
    end

    return false
end

local function virtualScreenTurnOn (virtualScreen)
    if not virtualScreen.power then
        virtualScreen.power = true
        return true
    end

    return false
end

local function virtualScreenIsOn (virtualScreen)
    return virtualScreen.power
end

local function virtualScreenSetTouchModeInverted (value)
    checkArg (1, value, "boolean")
    return true
end

local function virtualScreenIsTouchModeInverted (virtualScreen)
    return false
end

local function virtualScreenGetAspectRatio (virtualScreen)
    return 1, 1
end

local function virtualScreenGetKeyboards (virtualScreen)
    -- TODO: Return something...
    return {}
end 

function vm.component.newVirtualScreen (x, y)
    local virtualScreen = vm.component.newVirtualComponent ("screen")

    virtualScreen.boundGpu = nil -- Sets only with gpu.bind function
    virtualScreen.power = true -- Emulate screen power. When power is off, screen only shows 'Screen turned off'

    -- Visual style properties that can be changed by user
    virtualScreen.visualBorderColor = 0x696969
    virtualScreen.visualTextColor = 0xFFFFFF
    virtualScreen.visualPositionX = x or 1
    virtualScreen.visualPositionY = y or 1
    virtualScreen.autoDisplay = false -- Set this value to true will display any changes on screen instantly

    virtualScreen.display = virtualScreenDisplay
    virtualScreen.getVisualSize = virtualScreenGetVisualSize
    virtualScreen.release = virtualScreenRelease
    virtualScreen.handleEvent = virtualScreenHandleEvent
    virtualScreen.getDeviceInfo = virtualScreenGetDeviceInfo

    virtualScreen.setTouchModeInverted = virtualScreenSetTouchModeInverted
    virtualScreen.isTouchModeInverted = virtualScreenIsTouchModeInverted
    virtualScreen.getAspectRatio = virtualScreenGetAspectRatio
    virtualScreen.getKeyboards = virtualScreenGetKeyboards
    virtualScreen.setPrecise = virtualScreenSetPrecise
    virtualScreen.isPrecise = virtualScreenIsPrecise
    virtualScreen.turnOff = virtualScreenTurnOff
    virtualScreen.turnOn = virtualScreenTurnOn
    virtualScreen.isOn = virtualScreenIsOn

    return virtualScreen
end

------------------------------------------- Filesystem

local function virtualFilesystemRelease (virtualFilesystem)
    if virtualFilesystem.destructed then
        return false
    end

    for handle in pairs (virtualFilesystem.openedFiles) do
        virtualFilesystem:close (handle)
    end

    return virtualComponentRelease (virtualFilesystem)
end

local function virtualFilesystemGetDeviceInfo (virtualFilesystem)
    return {
        vendor = vm.vendor,
        class = "volume",
        product = "VFS 3.0",
        description = "libvm Virtual Filesystem"
    }
end

local function virtualFilesystemCheckHandle (virtualFilesystem, handle)
    checkArg (1, handle, "table")
    if virtualFilesystem.openedFiles[handle] ~= nil then
        return true
    end

    return false, "bad file descriptor"
end

local function virtualFilesystemResolve (virtualFilesystem, path)
    checkArg (1, path, "string")
    return virtualFilesystem.localRoot .. '/' .. path
end

local function virtualFilesystemSpaceUsed (virtualFilesystem)
    return fs.spaceUsed ()
end

local function virtualFilesystemOpen (virtualFilesystem, path, mode)
    checkArg (1, path, "string"       )
    checkArg (2, mode, "string", "nil")
    
    local handle, reason = fs.open (virtualFilesystem:resolve (path), mode)
    if not handle then
        return nil, reason
    end

    virtualFilesystem.openedFiles[handle] = true
    return handle
end

local function virtualFilesystemClose (virtualFilesystem, handle)
    checkArg (1, handle, "table")

    local valid, reason = virtualFilesystem:checkHandle (handle)
    if not valid then
        return nil, reason
    end

    result = {fs.close (handle)}
    virtualFilesystem.openedFiles[handle] = nil
    return table.unpack (result)
end

local function virtualFilesystemSeek (virtualFilesystem, handle, whence, offset)
    checkArg (1, handle, "table")
    checkArg (2, whence, "string")
    checkArg (3, offset, "number")

    local valid, reason = virtualFilesystem:checkHandle (handle)
    if not valid then
        return nil, reason
    end

    return fs.seek (handle, whence, offset)
end

local function virtualFilesystemMakeDirectory (virtualFilesystem, path)
    checkArg (1, path, "string")
    return fs.makeDirectory (virtualFilesystem:resolve (path))
end

local function virtualFilesystemExists (virtualFilesystem, path)
    checkArg (1, path, "string")
    return fs.exists (virtualFilesystem:resolve (path))
end

local function virtualFilesystemIsReadOnly (virtualFilesystem)
    return fs.isReadOnly ()
end

local function virtualFilesystemWrite (virtualFilesystem, handle, value)
    checkArg (1, handle, "table")
    checkArg (2, value,  "string")

    local valid, reason = virtualFilesystem:checkHandle (handle)
    if not valid then
        return nil, reason
    end

    return fs.write (handle, value)
end

local function virtualFilesystemSpaceTotal (virtualFilesystem)
    return fs.spaceTotal ()
end

local function virtualFilesystemIsDirectory (virtualFilesystem, path)
    checkArg (1, path, "string")
    return fs.isDirectory (virtualFilesystem:resolve (path))
end

local function virtualFilesystemRename (virtualFilesystem, from, to)
    checkArg (1, from, "string")
    checkArg (1, to,   "string")
    return fs.rename (virtualFilesystem:resolve (from), virtualFilesystem:resolve (to))
end

local function virtualFilesystemList (virtualFilesystem, path)
    checkArg (1, path, "string")
    return fs.list (virtualFilesystem:resolve (path))
end

local function virtualFilesystemLastModified (virtualFilesystem, path)
    checkArg (1, path, "string")
    return fs.lastModified (virtualFilesystem:resolve (path))
end

local function virtualFilesystemGetLabel (virtualFilesystem)
    return virtualFilesystem.label
end

local function virtualFilesystemRemove (virtualFilesystem, path)
    checkArg (1, path, "string")
    return fs.remove (virtualFilesystem:resolve (path))
end

local function virtualFilesystemSize (virtualFilesystem, path)
    checkArg (1, path, "string")
    return fs.size (virtualFilesystem:resolve (path))
end

local function virtualFilesystemRead (virtualFilesystem, handle, count)
    checkArg (1, handle, "table")
    checkArg (2, count,  "number")

    local valid, reason = virtualFilesystem:checkHandle (handle)
    if not valid then
        return nil, reason
    end

    return fs.read (handle, count)
end

local function virtualFilesystemSetLabel (virtualFilesystem, value)
    checkArg (1, value, "string")
    virtualFilesystem.label = value:sub (1, virtualFilesystem.labelSizeLimit) -- Filesystem labels are limited by 16 characters
    return virtualFilesystem.value
end

-- Virtual filesystem limited by local root directory
function vm.component.newVirtualFilesystem (localRoot, label)
    checkArg (1, localRoot, "string"       )
    checkArg (1, label,     "string", "nil")
    
    if not fs.isDirectory (localRoot) then
        error ("invalid filesystem root directory")
    end

    local virtualFilesystem = vm.component.newVirtualComponent ("filesystem")

    virtualFilesystem.labelSizeLimit = 16
    virtualFilesystem.localRoot = localRoot
    virtualFilesystem.label = nil
    virtualFilesystem.openedFiles = {}
    
    virtualFilesystem.release = virtualFilesystemRelease
    virtualFilesystem.resolve = virtualFilesystemResolve
    virtualFilesystem.checkHandle = virtualFilesystemCheckHandle

    virtualFilesystem.spaceUsed = virtualFilesystemSpaceUsed
    virtualFilesystem.open = virtualFilesystemOpen
    virtualFilesystem.close = virtualFilesystemClose
    virtualFilesystem.seek = virtualFilesystemSeek
    virtualFilesystem.makeDirectory = virtualFilesystemMakeDirectory
    virtualFilesystem.exists = virtualFilesystemExists
    virtualFilesystem.isReadOnly = virtualFilesystemIsReadOnly
    virtualFilesystem.write = virtualFilesystemWrite
    virtualFilesystem.spaceTotal = virtualFilesystemSpaceTotal
    virtualFilesystem.isDirectory = virtualFilesystemIsDirectory
    virtualFilesystem.rename = virtualFilesystemRename
    virtualFilesystem.list = virtualFilesystemList
    virtualFilesystem.lastModified = virtualFilesystemLastModified
    virtualFilesystem.getLabel = virtualFilesystemGetLabel
    virtualFilesystem.remove = virtualFilesystemRemove
    virtualFilesystem.size = virtualFilesystemSize
    virtualFilesystem.read = virtualFilesystemRead
    virtualFilesystem.setLabel = virtualFilesystemSetLabel

    if label then
        virtualFilesystem:setLabel (label) 
    end

    return virtualFilesystem
end

------------------------------------------- Eeprom

local function virtualEepromGetDeviceInfo (virtualEeprom)
    return {
        vendor = vm.vendor,
        class = "memory",
        product = "VirtualWare v-EEPROM 6000",
        description = "libvm Virtual EEPROM"
    }
end
 
local function virtualEepromLoadFromFile (virtualEeprom, path)
    checkArg (1, path, "string")
    local handle = fs.open (path)
    if not handle then
        return nil, "Failed to read file"
    end

    local data, chunk = ""
    while true do
        chunk = fs.read (handle, 4096)
        if chunk then
            data = data .. chunk
        else
            break
        end
    end

    fs.close (handle)
    virtualEeprom:set (data)

    return true
end

local function virtualEepromGet (virtualEeprom)
    return virtualEeprom.code
end

local function virtualEepromSet (virtualEeprom, data)
    checkArg (1, data, "string")
    if virtualEeprom.readonly then
        return nil, "storage is readonly"
    end

    if #data > virtualEeprom.codeSizeLimit then
        error ("not enough space")
    end
    virtualEeprom.code = data
end

local function virtualEepromGetLabel (virtualEeprom)
    return virtualEeprom.label
end

local function virtualEepromSetLabel (virtualEeprom, label)
    checkArg (1, label, "string")
    virtualEeprom.label = label:sub (1, virtualEeprom.labelSizeLimit)
    return virtualEeprom.label
end

local function virtualEepromGetData (virtualEeprom)
    return virtualEeprom.data
end

local function virtualEepromSetData (virtualEeprom, data)
    checkArg (1, data, "string")
    if #data > virtualEeprom.dataSizeLimit then
        error ("not enough space")
    end
    virtualEeprom.data = data
end

local function virtualEepromGetSize (virtualEeprom)
    return virtualEeprom.codeSizeLimit
end

local function virtualEepromGetDataSize (virtualEeprom)
    return virtualEeprom.dataSizeLimit
end

local function virtualEepromGetChecksum (virtualEeprom)
    return string.format ("%x", crc32.hash (virtualEeprom.code))
end

local function virtualEepromMakeReadonly (virtualEeprom, checksum)
    checkArg (1, checksum, "string")
    if checksum ~= virtualEeprom:getChecksum () then
        return nil, "incorrect checksum"
    end
    return true
end

function vm.component.newVirtualEeprom (label)
    checkArg (1, label, "string", "nil")

    local virtualEeprom = vm.component.newVirtualComponent ("eeprom")

    virtualEeprom.codeSizeLimit = math.huge
    virtualEeprom.dataSizeLimit = 256
    virtualEeprom.labelSizeLimit = 24
    virtualEeprom.readonly = false
    virtualEeprom.label = "EEPROM"
    virtualEeprom.code = ""
    virtualEeprom.data = ""

    virtualEeprom.loadFromFile = virtualEepromLoadFromFile

    virtualEeprom.set = virtualEepromSet
    virtualEeprom.get = virtualEepromGet
    virtualEeprom.setData = virtualEepromSetData
    virtualEeprom.getData = virtualEepromGetData
    virtualEeprom.getSize = virtualEepromGetSize
    virtualEeprom.getDataSize = virtualEepromGetDataSize
    virtualEeprom.getChecksum = virtualEepromGetChecksum
    virtualEeprom.makeReadonly = virtualEepromMakeReadonly    

    if label then
        virtualEeprom:setLabel (label)
    end

    return virtualEeprom
end

-------------------------------------------

return vm