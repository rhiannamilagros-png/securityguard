local Guard = {}

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Player = Players.LocalPlayer

local LOADER_URL = "https://loader.scoophub.me/free"

local INTENT_FILE =
    "ScoopHub/FreeTeleportIntent.json"

local INTENT_LIFETIME = 45

local function getQueueFunction()
    if type(queue_on_teleport) == "function" then
        return queue_on_teleport
    end

    if type(queueonteleport) == "function" then
        return queueonteleport
    end

    if syn and type(syn.queue_on_teleport) == "function" then
        return syn.queue_on_teleport
    end

    if fluxus and type(fluxus.queue_on_teleport) == "function" then
        return fluxus.queue_on_teleport
    end

    return nil
end

local function filesystemSupported()
    return type(writefile) == "function"
        and type(readfile) == "function"
        and type(isfile) == "function"
        and type(delfile) == "function"
end

local function ensureFolder()
    if type(makefolder) ~= "function" then
        return
    end

    pcall(function()
        if type(isfolder) == "function" then
            if not isfolder("ScoopHub") then
                makefolder("ScoopHub")
            end
        else
            makefolder("ScoopHub")
        end
    end)
end

local function writeIntent(data)
    ensureFolder()

    local success = pcall(function()
        writefile(
            INTENT_FILE,
            HttpService:JSONEncode(data)
        )
    end)

    return success
end

local function deleteIntent()
    pcall(function()
        if isfile(INTENT_FILE) then
            delfile(INTENT_FILE)
        end
    end)
end

local function readIntent()
    local success, result = pcall(function()
        if not isfile(INTENT_FILE) then
            return nil
        end

        return HttpService:JSONDecode(
            readfile(INTENT_FILE)
        )
    end)

    if success then
        return result
    end

    return nil
end

local function createToken()
    return HttpService:GenerateGUID(false)
        .. "-"
        .. tostring(os.time())
end

local function markTeleportStarted(token)
    local data = readIntent()

    if type(data) ~= "table" then
        return
    end

    if data.Token ~= token then
        return
    end

    data.Started = true
    data.StartedAt = os.time()

    writeIntent(data)
end

function Guard:Queue(reason)
    if not filesystemSupported() then
        warn(
            "[ScoopHub] Teleport auto-execute disabled: "
            .. "filesystem unavailable."
        )

        return false
    end

    local queue = getQueueFunction()

    if not queue then
        warn(
            "[ScoopHub] queue_on_teleport unavailable."
        )

        return false
    end

    reason = tostring(reason or "")

    if reason ~= "rejoin"
        and reason ~= "server_hop"
    then
        return false
    end

    local token = createToken()

    local intent = {
        Token = token,
        Reason = reason,

        PlaceId = game.PlaceId,
        JobId = game.JobId,

        CreatedAt = os.time(),

        Started = false,
    }

    if not writeIntent(intent) then
        return false
    end

    local queuedCode = string.format([[
        local HttpService =
            game:GetService("HttpService")

        local FILE =
            %q

        local EXPECTED_TOKEN =
            %q

        local LOADER =
            %q

        local MAX_AGE =
            %d

        if type(readfile) ~= "function"
            or type(isfile) ~= "function"
            or type(delfile) ~= "function"
        then
            return
        end

        if not isfile(FILE) then
            return
        end

        local ok, data = pcall(function()
            return HttpService:JSONDecode(
                readfile(FILE)
            )
        end)

        if not ok or type(data) ~= "table" then
            return
        end

        if data.Token ~= EXPECTED_TOKEN then
            return
        end

        if data.Started ~= true then
            return
        end

        if tonumber(data.PlaceId) ~= game.PlaceId then
            return
        end

        local reason =
            tostring(data.Reason or "")

        if reason ~= "rejoin"
            and reason ~= "server_hop"
        then
            return
        end

        local startedAt =
            tonumber(data.StartedAt or 0)

        local age =
            os.time() - startedAt

        if age < 0 or age > MAX_AGE then
            pcall(function()
                delfile(FILE)
            end)

            return
        end

        pcall(function()
            delfile(FILE)
        end)

        task.wait(2)

        local source =
            game:HttpGet(LOADER)

        local fn =
            loadstring(source)

        if fn then
            fn()
        end
    ]],
        INTENT_FILE,
        token,
        LOADER_URL,
        INTENT_LIFETIME
    )

    local queued = pcall(function()
        queue(queuedCode)
    end)

    if not queued then
        deleteIntent()
        return false
    end

    local connection

    connection =
        Player.OnTeleport:Connect(function(state)
            local stateName =
                string.lower(tostring(state))

            if string.find(
                stateName,
                "failed",
                1,
                true
            ) then
                deleteIntent()

                if connection then
                    connection:Disconnect()
                end

                return
            end

            markTeleportStarted(token)
        end)

    task.delay(60, function()
        local data = readIntent()

        if type(data) == "table"
            and data.Token == token
            and data.Started ~= true
        then
            deleteIntent()
        end
    end)

    return true
end

function Guard:Clear()
    deleteIntent()
end

return Guard
