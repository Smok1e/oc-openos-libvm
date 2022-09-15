-- LibVM - Virtual machine library for OpenOS

local fs = require ("filesystem")
local libvm = {}

------------------------------------------- Service functions

-- Reads whole file
local function readFile (path)
    checkArg (1, path, "string")
    
    local file, reason = fs.open (path, 'rb')
    if not file then
        return nil, reason
    end

    local data, chunk = ""
    repeat
        chunk = file:read (math.huge)
        data = data .. (chunk or "")
    until not chunk
    file:close ()

    return data
end

-- Same as default require, but allows to pass the scope label and env to load ()
local function loadModule (path, label, env)
    checkArg (1, path,  "string"       )
    checkArg (2, label, "string", "nil")
    checkArg (3, env,   "table",  "nil")

    local source, reason = readFile (path)
    if not source then
        return nil, reason
    end

    local executable, syntaxError = load (source, label, env)
    if not executable then
        return nil, "Module syntax error:\n" .. syntaxError
    end

    local result, value = xpcall (executable, debug.traceback)
    if not result then
        return nil, "Module runtime error:\n" .. value
    end

    return value
end

------------------------------------------- Virtual machine instance

local function virtualMachineRelease (virtualMachine)
    virtualMachine.component.releaseAll ()
end

------------------------------------------- Displaying error

local function virtualMachineDisplayError (virtualMachine, errorMessage)
    local gpuAddress    = virtualMachine.component.api.list ("gpu")   ()
    local screenAddress = virtualMachine.component.api.list ("screen")()
    if not gpuAddress or not screenAddress then
        print ("Virtual machine has no gpu or screen")
        print (errorMessage)
        return false
    end

    local gpu    = virtualMachine.component.api.proxy (gpuAddress   )
    local screen = virtualMachine.component.api.proxy (screenAddress)
    gpu.bind (screen.address)
    
    local resX, resY = gpu.getResolution ()
    gpu.setBackground (0x0000FF)
    gpu.setForeground (0xFFFFFF)
    gpu.fill (1, 1, resX, resY, ' ')

    local lines = {}
    table.insert (lines, "Unrecoverable error")
    table.insert (lines, ""                   )
    for line in string.gmatch (tostring (errorMessage), "[^\r\n\t]+") do
        table.insert (lines, line)
    end
    table.insert (lines, ""                           )
    table.insert (lines, "[Press any key to continue]")
    
    gpu.set (2, 2, "бля((9")
    for i, line in pairs (lines) do
        gpu.set (resX/2-#line/2, resY/2-#lines/2+i, line)
    end

    screen.display ()
    while virtualMachine.computer.api.pullSignal () ~= "key_down" do
    end    
end

------------------------------------------- Virtual machine runtime

local function virtualMachineStart (virtualMachine)
    local eepromAddress = virtualMachine.component.api.list ("eeprom")()
    if not eepromAddress then
        virtualMachine:displayError ("no bios found; install a configured EEPROM")
        return false
    end

    local eepromProxy = virtualMachine.component.api.proxy (eepromAddress)
    local eepromExecutable, eepromSyntaxError = load (eepromProxy.get (), "=virtual_bios", "bt", virtualMachine.env)
    if not eepromExecutable then
        virtualMachine:displayError ("failed loading bios: " .. eepromSyntaxError)
        return false
    end

    local result, value = xpcall (eepromExecutable, debug.traceback)
    if not result then
        virtualMachine:displayError (value)
        return false
    end

    virtualMachine:displayError ("computer halted")
    return true
end

------------------------------------------- Virtual machine creation

function libvm.newVirtualMachine ()
    local virtualMachine, reason = loadModule ("/usr/lib/libvm/libvm_virtual_machine.lua", "=virtual_machine")
    if not virtualMachine then
        return nil, reason
    end

    -- Copying everything excluding component and computer APIs from lua global scope into the virtual machine environment
    virtualMachine.env = {
        computer = virtualMachine.computer.api,
        component = virtualMachine.component.api,
        unicode = require ("unicode")
    }

    virtualMachine.env._G = virtualMachine.env

    for key, value in pairs (_G) do
        if virtualMachine.env[key] == nil then
            virtualMachine.env[key] = value
        end
    end

    virtualMachine.release = virtualMachineRelease
    virtualMachine.displayError = virtualMachineDisplayError
    virtualMachine.start = virtualMachineStart
    return virtualMachine
end

-------------------------------------------

return libvm