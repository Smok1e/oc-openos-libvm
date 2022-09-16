-- LibVM Virtual machine manager
-- OpenOS program to manage and run virtual machines

-- TODO: Remove this on release
package.loaded.libvm = nil

local libvm     = require ("libvm")
local component = require ("component")
local shell     = require ("shell")

local args, options = shell.parse (...)
local command = args[1]

-------------------------------------------

local function help ()
    print ("Usage: vm [COMMAND] [OPTIONS]")
    print ("Commands:")
    print (" run: Run virtual machine")
    print (" help: Get help")
    print ("Options:")
    print (" -l --logging: Enable debug logging")
    print (" -d --auto-display: Update virtual screen instantly (after each gpu operation)")
    print ("    --resolution=WIDTHxHEIGHT: Override virtual gpu resolution")
    print ("    --bios=FILENAME: Override virtual bios source filename")
    print (" -f --free-vram: Free all gpu buffers before running machine")
end

-------------------------------------------

local function run ()
    local machine, reason = libvm.newVirtualMachine ()
    if not machine then
        error (reason)
    end

    local loggingEnabled = options['l'] or options['logging'] or false
    local autoDisplay = options['d'] or options['auto-display'] or false
    local resX = 100
    local resY = 40
    local biosFilename = options['bios'] or "mineos_efi.lua"
    local mainFilesystemRoot = "mineos/"
    local tmpFilesystemRoot = "tmpfs/"
    local virtualMachineDirectory = "/home/VirtualMachine1/"

    if loggingEnabled then
        print ("Logging enabled; Log will be saved as '" .. machine.logPath .. "'")
        logEnabled = true
    end

    if autoDisplay then
        print ("Screen changes will be displayed instantly")
    end
    
    if options['resolution'] then
        local optionResX, optionResY = string.match (options['resolution'], "(%d+)x(%d+)")
        optionResX = tonumber (optionResX or nil)
        optionResY = tonumber (optionResY or nil)

        if not optionResX or not optionResY then
            print (string.format ("Invalid resolution option value: %s; Used default resolution: %dx%d", options['resolution'], resX, resY))
        else
            resX = optionResX
            resY = optionResY
        end
    end

    if options['f'] or options['free-vram'] then
        component.gpu.freeAllBuffers ()
        print ("All GPU vram buffers freed")
    end

    local actualResX, actualResY = component.gpu.getResolution ()

    print ("Initializing machine")
    machine.component.newVirtualGpu (resX, resY)
    machine.component.newVirtualScreen (actualResX/2-resX/2-1, actualResY/2-resY/2)
    machine.component.newVirtualFilesystem (virtualMachineDirectory .. "/" .. mainFilesystemRoot, "main volume")
    
    local result, reason = machine.component.newVirtualEeprom ():loadFromFile (virtualMachineDirectory .. "/" .. biosFilename)
    if not result then
        machine:displayError ("Bios loading failed: " .. reason)
        machine:release ()
        return false
    end
    
    tmpfs = machine.component.newVirtualFilesystem (virtualMachineDirectory .. "/" .. tmpFilesystemRoot, "tmpfs")
    machine.computer.setTmpAddress (tmpfs.address)

    print ("Starting machine")
    local exitCode, exitMessage
    repeat
        if exitCode == libvm.INTERRUPTION_REBOOT then
            print ("Rebooting machine")
        end

        exitCode, exitMessage = machine:start ()
        component.gpu.setForeground (0xFFFFFF)
        component.gpu.setBackground (0x000000)
    until exitCode ~= libvm.INTERRUPTION_REBOOT

    machine:release ()
    print (string.format ("Machine stopped with exit code 0x%04X: %s", exitCode, exitMessage))
end

-------------------------------------------

if not command then
    return help ()
end

local function setCommand (cmd, func)
    if command:lower () == cmd:lower () then
        local result = {xpcall (func, debug.traceback)}
        if not result[1] then
            component.gpu.setBackground (0x000000)
            component.gpu.setForeground (0xFFFFFF)
            print ("Runtime error")
            print (result[2])
        end

        return true
    end

    return false
end

if  not setCommand ("help", help)
and not setCommand ("run",  run )

then help () end

-------------------------------------------