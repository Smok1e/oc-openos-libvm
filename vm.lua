-- LibVM Virtual machine manager
-- OpenOS program to manage and run virtual machines

-- TODO: Remove this on release
package.loaded.libvm = nil

local libvm     = require("libvm")
local component = require("component")
local shell     = require("shell")

local gpu = component.gpu

local args, options = shell.parse(...)
local command = args[1]

-------------------------------------------

local function info(...)
    if not options['q'] and not options['quiet'] then
        print(...)
    end
end

-------------------------------------------

local function help()
    print("Usage: vm [COMMAND] [OPTIONS]")
    print("Commands:")
    print("  run: Run virtual machine")
    print("  help: Get help")
    print("Options:")
    print("  -q --quiet: Do not print anything")
    print("  -l --logging: Save degub log(events, proxy calls, etc)")
    print("  -d --auto-display: Update virtual screen instantly(after each gpu operation)")
    print("  -r --resolution=WIDTHxHEIGHT: Override virtual gpu resolution")
    print("  -b --bios=FILENAME: Override virtual bios source file")
    print("  -n --no-buffer: Do not save screen buffer before running machine")
    print("  -f --free-vram: Free all gpu buffers before running machine")
end

-------------------------------------------

local function run()
    local machine, reason = libvm.newVirtualMachine()
    if not machine then
        error(reason)
    end

    local loggingEnabled = options['l'] or options['logging'] or false
    local autoDisplay = options['d'] or options['auto-display'] or false
    local resX = 100
    local resY = 40
    local biosFilename = options['bios'] or options['b'] or "bios.lua"
    local mainFilesystemRoot = "filesystem/"
    local tmpFilesystemRoot = "tmpfs/"
    local virtualMachineDirectory = "/home/VirtualMachine1/"

    if loggingEnabled then
        info("Logging enabled; Log will be saved as '" .. machine.logPath .. "'")
        machine.logging = true
    end

    if autoDisplay then
        info("Screen changes will be displayed instantly")
    end
    
    if options['resolution'] or options['r'] then
        local optionResX, optionResY = string.match(options['resolution'] or options['r'], "(%d+)x(%d+)")
        optionResX = tonumber(optionResX or nil)
        optionResY = tonumber(optionResY or nil)

        if not optionResX or not optionResY then
            info(string.format("Invalid resolution option value: %s; Used default resolution: %dx%d", options['resolution'], resX, resY))
        else
            resX = optionResX
            resY = optionResY
        end
    end

    if options['f'] or options['free-vram'] then
        component.gpu.freeAllBuffers()
        info("All GPU vram buffers freed")
    end

    local actualResX, actualResY = component.gpu.getResolution()
    local screenPosX, screenPosY = actualResX/2-resX/2-1, actualResY/2-resY/2

    info("Initializing machine")
    machine.component.newVirtualGpu(resX, resY)
    machine.component.newVirtualKeyboard()
    machine.component.newVirtualInternetCard()

    screen = machine.component.newVirtualScreen(screenPosX, screenPosY)
    screen.autoDisplay = autoDisplay
    
    main_volume = machine.component.newVirtualFilesystem(virtualMachineDirectory .. "/" .. mainFilesystemRoot, "main volume")
    machine.computer.api.setBootAddress(main_volume.address)
    
    local result, reason = machine.component.newVirtualEeprom():loadFromFile(virtualMachineDirectory .. "/" .. biosFilename)
    if not result then
        machine:displayError("Bios loading failed: " .. reason)
        machine:release()
        return false
    end
    
    tmpfs = machine.component.newVirtualFilesystem(virtualMachineDirectory .. "/" .. tmpFilesystemRoot, "tmpfs")
    machine.computer.setTmpAddress(tmpfs.address)
    
    machine.component.newMachineInterface(screen.visualPositionX - 12, screen.visualPositionY)

    info("Starting machine")

    local screenBuffer, reason
    if not options['n'] and not options['no-buffer'] then
        screenBuffer, reason = gpu.allocateBuffer()
        if screenBuffer then
            gpu.bitblt(screenBuffer)
        else
            info("Failed to allocate screen buffer: " .. reason)
        end
    end

    local exitCode, exitMessage
    repeat
        if exitCode == libvm.INTERRUPTION_REBOOT then
            info("Rebooting machine")
        end

        exitCode, exitMessage = machine:start()
        component.gpu.setForeground(0xFFFFFF)
        component.gpu.setBackground(0x000000)
    until exitCode ~= libvm.INTERRUPTION_REBOOT

    if screenBuffer then
        gpu.bitblt(0, 1, 1, actualResX, actualResY, screenBuffer)
        gpu.freeBuffer(screenBuffer)
    end

    machine:release()
    info(string.format("Machine stopped with exit code 0x%04X: %s", exitCode, exitMessage))
end

-------------------------------------------

if not command then
    return help()
end

local function setCommand(cmd, func)
    if command:lower() == cmd:lower() then
        local result = {xpcall(func, debug.traceback)}
        if not result[1] then
            component.gpu.setBackground(0x000000)
            component.gpu.setForeground(0xFFFFFF)
            print("Runtime error")
            print(result[2])
        end

        return true
    end

    return false
end

if  not setCommand("help", help)
and not setCommand("run",  run )

then help() end

-------------------------------------------