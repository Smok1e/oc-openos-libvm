local component = require("component")
local bit32 = require("bit32")
local fs = require("filesystem")
local shell = require("shell")

local gpu = component.gpu
local internet = component.internet

local args, options = shell.parse(...)
local command = args[1]

local REPO_PREFIX = "https://raw.githubusercontent.com/Smok1e/oc-openos-libvm/main/"

-------------------------------------------

-- Testing for opencomputers version
if not gpu.allocateBuffer then
    print("LibVM requires opencomputers v1.7.6 or higher :c")
    print("To check your opencomputers version, press escape => mod options, and find 'opencomputers'")
    return nil
end

-------------------------------------------

-- Downloads whole file
local function download(url)
    checkArg(1, url, "string")

    local request, reason = internet.request(url)
    if not request then
        return nil, reason
    end

    local data, chunk = ""
    repeat
        chunk = request.read(math.huge)
        data = data ..(chunk or "")
    until not chunk
    request.close()

    return data
end

------------------------------------------- OCIF loader

local Palette = {0x000000, 0x000040, 0x000080, 0x0000BF, 0x0000FF, 0x002400, 0x002440, 0x002480, 0x0024BF, 0x0024FF, 0x004900, 0x004940, 0x004980, 0x0049BF, 0x0049FF, 0x006D00, 0x006D40, 0x006D80, 0x006DBF, 0x006DFF, 0x009200, 0x009240, 0x009280, 0x0092BF, 0x0092FF, 0x00B600, 0x00B640, 0x00B680, 0x00B6BF, 0x00B6FF, 0x00DB00, 0x00DB40, 0x00DB80, 0x00DBBF, 0x00DBFF, 0x00FF00, 0x00FF40, 0x00FF80, 0x00FFBF, 0x00FFFF, 0x0F0F0F, 0x1E1E1E, 0x2D2D2D, 0x330000, 0x330040, 0x330080, 0x3300BF, 0x3300FF, 0x332400, 0x332440, 0x332480, 0x3324BF, 0x3324FF, 0x334900, 0x334940, 0x334980, 0x3349BF, 0x3349FF, 0x336D00, 0x336D40, 0x336D80, 0x336DBF, 0x336DFF, 0x339200, 0x339240, 0x339280, 0x3392BF, 0x3392FF, 0x33B600, 0x33B640, 0x33B680, 0x33B6BF, 0x33B6FF, 0x33DB00, 0x33DB40, 0x33DB80, 0x33DBBF, 0x33DBFF, 0x33FF00, 0x33FF40, 0x33FF80, 0x33FFBF, 0x33FFFF, 0x3C3C3C, 0x4B4B4B, 0x5A5A5A, 0x660000, 0x660040, 0x660080, 0x6600BF, 0x6600FF, 0x662400, 0x662440, 0x662480, 0x6624BF, 0x6624FF, 0x664900, 0x664940, 0x664980, 0x6649BF, 0x6649FF, 0x666D00, 0x666D40, 0x666D80, 0x666DBF, 0x666DFF, 0x669200, 0x669240, 0x669280, 0x6692BF, 0x6692FF, 0x66B600, 0x66B640, 0x66B680, 0x66B6BF, 0x66B6FF, 0x66DB00, 0x66DB40, 0x66DB80, 0x66DBBF, 0x66DBFF, 0x66FF00, 0x66FF40, 0x66FF80, 0x66FFBF, 0x66FFFF, 0x696969, 0x787878, 0x878787, 0x969696, 0x990000, 0x990040, 0x990080, 0x9900BF, 0x9900FF, 0x992400, 0x992440, 0x992480, 0x9924BF, 0x9924FF, 0x994900, 0x994940, 0x994980, 0x9949BF, 0x9949FF, 0x996D00, 0x996D40, 0x996D80, 0x996DBF, 0x996DFF, 0x999200, 0x999240, 0x999280, 0x9992BF, 0x9992FF, 0x99B600, 0x99B640, 0x99B680, 0x99B6BF, 0x99B6FF, 0x99DB00, 0x99DB40, 0x99DB80, 0x99DBBF, 0x99DBFF, 0x99FF00, 0x99FF40, 0x99FF80, 0x99FFBF, 0x99FFFF, 0xA5A5A5, 0xB4B4B4, 0xC3C3C3, 0xCC0000, 0xCC0040, 0xCC0080, 0xCC00BF, 0xCC00FF, 0xCC2400, 0xCC2440, 0xCC2480, 0xCC24BF, 0xCC24FF, 0xCC4900, 0xCC4940, 0xCC4980, 0xCC49BF, 0xCC49FF, 0xCC6D00, 0xCC6D40, 0xCC6D80, 0xCC6DBF, 0xCC6DFF, 0xCC9200, 0xCC9240, 0xCC9280, 0xCC92BF, 0xCC92FF, 0xCCB600, 0xCCB640, 0xCCB680, 0xCCB6BF, 0xCCB6FF, 0xCCDB00, 0xCCDB40, 0xCCDB80, 0xCCDBBF, 0xCCDBFF, 0xCCFF00, 0xCCFF40, 0xCCFF80, 0xCCFFBF, 0xCCFFFF, 0xD2D2D2, 0xE1E1E1, 0xF0F0F0, 0xFF0000, 0xFF0040, 0xFF0080, 0xFF00BF, 0xFF00FF, 0xFF2400, 0xFF2440, 0xFF2480, 0xFF24BF, 0xFF24FF, 0xFF4900, 0xFF4940, 0xFF4980, 0xFF49BF, 0xFF49FF, 0xFF6D00, 0xFF6D40, 0xFF6D80, 0xFF6DBF, 0xFF6DFF, 0xFF9200, 0xFF9240, 0xFF9280, 0xFF92BF, 0xFF92FF, 0xFFB600, 0xFFB640, 0xFFB680, 0xFFB6BF, 0xFFB6FF, 0xFFDB00, 0xFFDB40, 0xFFDB80, 0xFFDBBF, 0xFFDBFF, 0xFFFF00, 0xFFFF40, 0xFFFF80, 0xFFFFBF, 0xFFFFFF}

local function imageDraw(self, x, y)
    gpu.bitblt(nil, x, y, nil, nil, self.buffer)
end

local function imageRelease(self)
    if self.buffer then
        gpu.freeBuffer(self.buffer)
    end
end

local function loadImageFromMemory(rawData)
    checkArg(1, rawData, "string")

    -- Memory reading functions
    local position = 1
    local function skip(bytesCount) 
        position = position + bytesCount
    end

    local function readString(bytesCount)
        local string = rawData:sub(position, position + bytesCount - 1)
        
        skip(bytesCount)
        return string
    end
    
    local function readNumber(bytesCount)
        local bytes, number = {rawData:byte(position, position + bytesCount - 1)}, 0
    
        for index, byte in pairs(bytes) do
            number = (number << 8) | byte
        end
    
        skip(bytesCount)
        return number
    end

    local function readUnicodeCharacter()
        local bytes, size = {readNumber(1)}

        for bit = 0, 7 do
            if (bytes[1] >> (7-bit) & 1) == 0 then
                if bit == 1 then
                    return nil, "invalid UTF-8 character at position " .. position
                end

                size = bit + (bit == 0 and 1 or 0)
                break
            end
        end

        for i = 1, size-1 do
            table.insert(bytes, readNumber(1))
        end

        return string.char(table.unpack(bytes))
    end

    -- First 4 bytes stores OCIF signature
    local signature = readString(4)
    if signature ~= "OCIF" then
        return nil, "invalid signature (expected 'OCIF', read '" .. signature .. "')"
    end

    -- Next byte is OCIF version, this implementation only supports OCIF 8
    local encodingMethod = readNumber(1)
    if encodingMethod ~= 8 then
        return nil, "unsupported encoding method (supported only 8, not " .. encodingMethod .. ")"
    end

    -- Next 2 bytes are width and height
    local image = {}
    image.width  = math.floor(readNumber(1)) + 1
    image.height = math.floor(readNumber(1)) + 1

    image.buffer, reason = gpu.allocateBuffer(image.width, image.height)
    if not image.buffer then
        return nil, "Failed to allocate v-ram buffer. Run this program with -f option to free all vram buffers, or with -n option to prevent program for allocation vram."
    end

    local lastActiveBuffer = gpu.getActiveBuffer()
    local function cleanup(releaseBuffer)
        gpu.setActiveBuffer(lastActiveBuffer)

        if releaseBuffer == true then
            gpu.freeBuffer(image.buffer)
        end
    end

    gpu.setActiveBuffer(image.buffer)

    -- The rest part of the file is the actual image content stored as nested groups of
    -- pixel properties in such order: alpha -> character -> background -> foreground -> y -> x
    -- Before each group there is one byte to store the group length,
    -- except the character group which length is split into 2 bytes

    for alpha = 1, readNumber(1) + 1 do
        -- We don't need alpha
        skip(1)

        for character = 1, readNumber(2) + 1 do
            local currentCharacter = readUnicodeCharacter()

            for background = 1, readNumber(1) + 1 do
                gpu.setBackground(Palette[readNumber(1) + 1])

                for foreground = 1, readNumber(1) + 1 do
                    gpu.setForeground(Palette[readNumber(1) + 1])

                    for y = 1, readNumber(1) + 1 do
                        local currentY = readNumber(1) + 1
                        if currentY > image.height then
                            cleanup(true)
                            return nil, "invalid Y value (y = " .. currentY .. ", height = " .. image.height .. ")"
                        end

                        for x = 1, readNumber(1) + 1 do
                            local currentX = readNumber(1) + 1
                            if currentX > image.width then
                                cleanup(true)
                                return nil, "invalid X value (x = " .. currentX .. ", width = " .. image.width .. ")"
                            end

                            gpu.set(currentX, currentY, currentCharacter)
                        end
                    end
                end
            end
        end
    end

    cleanup()

    image.draw = imageDraw
    image.release = imageRelease

    return image
end

local function loadImageFromURL(url)
    checkArg(1, url, "string")
    
    local rawData, reason = download(url)
    if not rawData then
        return nil, reason
    end

    return loadImageFromMemory(rawData)
end

-------------------------------------------

local function help()
    print("Usage: get-libvm [COMMAND] [OPTIONS]")
    print("Commands:")
    print("  <no commands>: Install LibVM")
    print("  help: Get help")
    print("Options:")
    print("-q --quiet: Do not print or draw anything excluding errors")
    print("-f --free-vram: Free all vram-buffers before starting installation")
    print("-n --no-logo: Do not show LibVM logo and status, just print everything")
end

local function install()
    local function info(text)
        if not options['q'] and not options['--quiet'] then
            print(text)
        end
    end

    if options['f'] or options['free-vram'] then
        info("Freeing all vram buffers...")
        gpu.freeAllBuffers()
    end

    info("Starting LibVM installer...")

    local screenBuffer, reason
    if not options['n'] and not options['no-logo'] then
        screenBuffer, reason = gpu.allocateBuffer()

        if not screenBuffer then
            error("Failed to allocate v-ram buffer. Run this program with -f option to free all vram buffers, or with -n option to prevent program for allocation vram.")
        end
        
        gpu.bitblt(screenBuffer, nil, nil, nil, nil, 0)
    end

    local function release()
        if logo then
            logo:release()
        end

        if screenBuffer then 
            gpu.bitblt(0, nil, nil, nil, nil, screenBuffer)
            gpu.freeBuffer(screenBuffer)
        end
    end

    local function throw(err)
        release()
        error(err)
    end

    local logo, reason
    if not options['n'] and not options['--no-logo'] then
        logo, reason = loadImageFromURL(REPO_PREFIX .. "logo.pic")
        if not logo then
            throw("Failed to load LibVM logo: " .. reason)
            return false
        end
    end

    local resX, resY = gpu.getResolution()
    local function status(format, ...)
        if options['q'] or options['quiet'] then
            return nil
        end
        
        if options['n'] or options['no-logo'] then
            info(string.format(format, ...))
            return nil
        end

        local x, y = resX/2-logo.width/2, resY/2-logo.height/2
        logo:draw(x, y)

        gpu.setBackground(0x000000)
        gpu.setForeground(0xFFFFFF)
        gpu.set(x, y+logo.height-1, string.format(format, ...))
    end

    local function downloadAndSave(url, path)
        status("Downloading %s...", path)
        local data, reason = download(url)
        if not data then
            throw(reason)
        end

        local file, reason = fs.open(path, 'wb')
        if not file then
            throw(reason)
        end

        file:write(data)
        file:close()
    end

    local function mkdir(path)
        status("Creating directory %s", path)

        if not fs.isDirectory(path) then
            if fs.exists(path) then
                throw("Failed to create directory '" .. path .. "', because it is an existing file. Delete this file and retry the installation")
            end

            fs.makeDirectory(path)
        end
    end

    -- So all installation stuff is here
    mkdir("/usr")
    mkdir("/usr/bin")
    mkdir("/usr/lib")
    mkdir("/usr/lib/libvm")

    downloadAndSave(REPO_PREFIX .. "libvm.lua",                       "/usr/lib/libvm.lua"                      )
    downloadAndSave(REPO_PREFIX .. "libvm/libvm_crc32.lua",           "/usr/lib/libvm/libvm_crc32.lua"          )
    downloadAndSave(REPO_PREFIX .. "libvm/libvm_virtual_machine.lua", "/usr/lib/libvm/libvm_virtual_machine.lua")
    downloadAndSave(REPO_PREFIX .. "vm.lua",                          "/usr/bin/vm.lua"                         )

    status("Installation complete")

    release()
    info("LibVM has been installed succesfully!")
end

-------------------------------------------

local function setCommand(cmd, func)
    if command and command:lower() == cmd:lower() then
        local lastActiveBuffer = gpu.getActiveBuffer()
        local result = {xpcall(func, debug.traceback)}
        gpu.setActiveBuffer(lastActiveBuffer)
        
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

if not setCommand("help", help) then
    install()
end

-------------------------------------------