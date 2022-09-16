-- LibVM - Virtual machine library for OpenOS

local fs = require ("filesystem")
local computer = require ("computer")
local component = require ("component")
local serialization = require ("serialization")
local libvm = {}

-- Machine exit codes
libvm.EXIT_SHUTDOWN  = 1
libvm.EXIT_REBOOT    = 2
libvm.EXIT_INTERRUPT = 3
libvm.EXIT_HALTED    = 4
libvm.EXIT_ERROR     = 5

libvm.customErrors = {
    libvm_shutdown  = libvm.EXIT_SHUTDOWN,
    libvm_reboot    = libvm.EXIT_REBOOT,
    libvm_interrupt = libvm.EXIT_INTERRUPT
}

------------------------------------------- Service functions

-- Prints arguments into game chat
local function debugLog (...)
    local str = ""
    for _, value in pairs ({...}) do
        str = str .. tostring (value) .. " "
    end

    local addr = component.list ('debug')()
    if addr then
        component.invoke (addr, "runCommand", "say §b§l[libvm]: " .. str)
    else
        print ("[libvm/debug]: " .. str)
    end
end

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

------------------------------------------- Hooking xpcall and pcall to pass libvm_shutdown and libvm_reboot errors

local function virtualMachineEnvXpcall (executable, msgh, ...)
    -- This function will be called first when error throws
    -- So we can be sure that error message will be original
    local asd
    local function handler (message, ...)
        local errorMessage, errorCode = tostring (message), ""
        for i = #errorMessage, 1, -1 do
            if errorMessage:sub (i, i) == ':' then
                errorCode = errorMessage:sub (i+2, #errorMessage)
                break
            end
        end

        asd = errorCode

        if libvm.customErrors[errorCode] then
            return errorCode
        else
            return msgh (message, ...)
        end
    end

    local result = {xpcall (executable, handler, ...)}
    if not result[1] then
        if libvm.customErrors[result[2]] then
            error (result[2])
        end
    end

    return table.unpack (result)
end

local function virtualMachineEnvPcall (executable, ...)
    return virtualMachineEnvXpcall (executable, function (...) return ... end)
end

------------------------------------------- Cleaning up

local function virtualMachineRelease (virtualMachine)
    virtualMachine.component.releaseAll ()

    -- To trigger garbage collection
    for i = 1, 10 do
        computer.pullSignal (0)
    end
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
        if libvm.customErrors[value] then
            return libvm.customErrors[value]
        else
            return libvm.EXIT_ERROR, value
        end
    end

    virtualMachine:displayError ("computer halted")
    return libvm.EXIT_HALTED, "Machine halted"
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
        unicode = require ("unicode"),
        pcall = virtualMachineEnvPcall,
        xpcall = virtualMachineEnvXpcall
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