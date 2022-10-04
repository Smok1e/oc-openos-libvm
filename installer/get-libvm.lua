local component = require ("component")
local bit32 = require ("bit32")
local fs = require ("filesystem")
local shell = require ("shell")

local gpu = component.gpu
local internet = component.internet

local args, options = shell.parse (...)
local command = args[1]

-------------------------------------------

-- Testing for opencomputers version
if not gpu.allocateBuffer then
    print ("LibVM requires opencomputers v1.7.6 or higher :c")
    print ("To check your opencomputers version, press escape => mod options, and find 'opencomputers'")
    return nil
end

-------------------------------------------

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

-- Downloads whole file
local function download (url)
    checkArg (1, url, "string")

    local request, reason = internet.request (url)
    if not request then
        return nil, reason
    end

    local data, chunk = ""
    repeat
        chunk = request.read (math.huge)
        data = data .. (chunk or "")
    until not chunk
    request.close ()

    return data
end

------------------------------------------- LibVM Picture format

local function pictureDraw (picture, x, y)
    gpu.bitblt (nil, x, y, nil, nil, picture.buffer)
end

local function pictureRelease (picture)
    if picture.buffer then
        gpu.freeBuffer (picture.buffer)
    end
end

-- Loads a picture of lvmp (libvm picture) format, used only here for displaying the libvm logo xd
-- The format is very simple:
-- signature: 4 bytes string (should be "LVMP")
-- sizeX: 2 bytes unsigned
-- sizeY: 2 bytes unsigned
-- pallete: 48 bytes array (16 RGB colors, 3 bytes per channel)
-- picture data: each byte (except last, see above) stores 2 pixels in 16 variations of colors from 0x0 to 0xF
-- If pixels count is odd then last 4 bits of byte will be zero, because you just can't write 1/2 byte to file
local function loadPictureFromMemory (rawData)
    checkArg (1, rawData, "string")

    local position = 1 
    local function read (bytesCount) 
        bytesCount = bytesCount or 1
        position = position+bytesCount 
        return rawData:sub (position-bytesCount, position-1) 
    end

    local function readNumber (length)
        return string.byte (read (length), 1, length or 1)
    end

    if read (4) ~= "LVMP" then
        return nil, "invalid signature"
    end

    local picture = {}
    picture.sizeX = math.floor (readNumber (2)  )
    picture.sizeY = math.floor (readNumber (2)/2) -- Actual picture height is divided by 2 because of semi-pixels

    local pallete = {}
    for i = 1, 16 do
        pallete[i] = bit32.bor (bit32.lshift (readNumber (), 16), bit32.bor (bit32.lshift (readNumber (), 8), readNumber ()))
    end

    picture.buffer, reason = gpu.allocateBuffer (picture.sizeX, picture.sizeY)
    if not picture.buffer then
        return nil, "Failed to allocate v-ram buffer. Run this program with -f option to free all vram buffers, or with -n option to prevent program for allocation vram."
    end

    local function getPalleteColor (index) -- Do not be confused with gpu.getPalleteColor
        return pallete[index+1]
    end

    local function nextPixel ()
        local byte = readNumber ()
        return getPalleteColor (bit32.rshift (bit32.band (byte, 0xF0), 4)),
               getPalleteColor (bit32.band (byte, 0xF))
    end

    local lastActiveBuffer = gpu.getActiveBuffer ()
    gpu.setActiveBuffer (picture.buffer)
    for x = 1, picture.sizeX do
        for y = 1, picture.sizeY do
            local foreground, background = nextPixel ()
            gpu.setForeground (foreground)
            gpu.setBackground (background)
            gpu.set (x, y, '⠛')
        end
    end
    gpu.setActiveBuffer (lastActiveBuffer)

    picture.draw = pictureDraw
    picture.release = pictureRelease

    return picture
end

local function loadPictureFromFile (path)
    checkArg (1, path, "string")
    
    local rawData, reason = readFile (path)
    if not rawData then
        return nil, reason
    end

    return loadPictureFromMemory (rawData)
end

local function loadPictureFromURL (url)
    checkArg (1, url, "string")
    
    local rawData, reason = download (url)
    if not rawData then
        return nil, reason
    end

    return loadPictureFromMemory (rawData)
end

local function info (text)
    if not options['q'] and not options['--quiet'] then
        print (text)
    end
end

-------------------------------------------

local function help ()
    print ("Usage: get-libvm [COMMAND] [OPTIONS]")
    print ("Commands:")
    print ("  <no commands>: Install LibVM")
    print ("  help: Get help")
    print ("Options:")
    print ("-q --quiet: Do not print or draw anything excluding errors")
    print ("-f --free-vram: Free all vram-buffers before starting installation")
    print ("-n --no-logo: Do not show LibVM logo and status, just print everything")
end

local function install ()
    if options['f'] or options['free-vram'] then
        info ("Freeing all vram buffers...")
        gpu.freeAllBuffers ()
    end

    info ("Starting LibVM installer...")

    local screenBuffer, reason
    if not options['n'] and not options['no-logo'] then
        screenBuffer, reason = gpu.allocateBuffer ()

        if not screenBuffer then
            error ("Failed to allocate v-ram buffer. Run this program with -f option to free all vram buffers, or with -n option to prevent program for allocation vram.")
        end
        
        gpu.bitblt (screenBuffer, nil, nil, nil, nil, 0)
    end

    local logo, reason
    if not options['n'] and not options['--no-logo'] then
        logo, reason = loadPictureFromURL ("https://github.com/Smok1e/oc-openos-libvm/blob/main/logo.lvmp?raw=true")
        if not logo then
            print ("Failed to load LibVM logo: " .. reason)
            return false
        end
    end

    local function release ()
        if logo then
            logo:release ()
        end

        if screenBuffer then 
            gpu.bitblt (0, nil, nil, nil, nil, screenBuffer)
            gpu.freeBuffer (screenBuffer)
        end
    end

    local function throw (err)
        release ()
        error (err)
    end

    local resX, resY = gpu.getResolution ()
    local function status (format, ...)
        if options['q'] or options['quiet'] then
            return nil
        end
        
        if options['n'] or options['no-logo'] then
            info (string.format (format, ...))
            return nil
        end

        local x, y = resX/2-logo.sizeX/2, resY/2-logo.sizeY/2
        logo:draw (x, y)

        gpu.setBackground (0x000000)
        gpu.setForeground (0xFFFFFF)
        gpu.set (x, y+logo.sizeY-1, string.format (format, ...))
    end

    local function downloadAndSave (url, path)
        status ("Downloading %s...", path)
        local data, reason = download (url)
        if not data then
            throw (reason)
        end

        local file, reason = fs.open (path, 'wb')
        if not file then
            throw (reason)
        end

        file:write (data)
        file:close ()
    end

    local function mkdir (path)
        status ("Creating directory %s", path)

        if not fs.isDirectory (path) then
            if fs.exists (path) then
                throw ("Failed to create directory '" .. path .. "', because it is an existing file. Delete this file and retry the installation")
            end

            fs.makeDirectory (path)
        end
    end

    -- So all installation staff is here
    mkdir ("/usr")
    mkdir ("/usr/bin")
    mkdir ("/usr/lib")
    mkdir ("/usr/lib/libvm")

    downloadAndSave ("https://raw.githubusercontent.com/Smok1e/oc-openos-libvm/main/libvm.lua", "/usr/lib/libvm.lua" )
    downloadAndSave ("https://raw.githubusercontent.com/Smok1e/oc-openos-libvm/main/libvm/libvm_crc32.lua", "/usr/lib/libvm/libvm_crc32.lua" )
    downloadAndSave ("https://raw.githubusercontent.com/Smok1e/oc-openos-libvm/main/libvm/libvm_virtual_machine.lua", "/usr/lib/libvm/libvm_virtual_machine.lua")
    downloadAndSave ("https://raw.githubusercontent.com/Smok1e/oc-openos-libvm/main/vm.lua", "/usr/bin/vm.lua")

    status ("Installation complete")

    release ()
    info ("LibVM has been installed succesfully!")
end

-------------------------------------------

local function setCommand (cmd, func)
    if command and command:lower () == cmd:lower () then
        local lastActiveBuffer = gpu.getActiveBuffer ()
        local result = {xpcall (func, debug.traceback)}
        gpu.setActiveBuffer (lastActiveBuffer)
        
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

if not setCommand ("help", help) then
    install ()
end

-------------------------------------------