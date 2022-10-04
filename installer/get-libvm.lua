local component = require ("component")
local bit32 = require ("bit32")
local fs = require ("filesystem")

local gpu = component.gpu
local internet = component.internet

-------------------------------------------

-- Testing for opencomputers version
if not gpu.assllocateBuffer then
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
        return nil, reason
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

-------------------------------------------

local function main ()
    gpu.releaseAllBuffers ()

    local logo, reason = loadPictureFromURL ("https://github.com/Smok1e/oc-openos-libvm/blob/main/logo.lvmp?raw=true")
    if not logo then
        error (reason)
    end

    local function status (text)
        logo:draw ()
    end

    logo:release ()
end

-------------------------------------------