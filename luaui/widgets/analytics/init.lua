function widget:GetInfo()
	return {
		name      = 'Analytics',
		desc      = 'API for providing usage analytics',
		author    = 'gajop',
		date      = 'future',
		license   = 'GNU GPL v2',
		layer     = 0,
		enabled   = true,
		handler   = true,
	}
end


if not (Spring.GetConfigInt("LuaSocketEnabled", 0) == 1) then
	Spring.Echo("LuaSocketEnabled is disabled")
	return false
end

local socket = socket

local client

local LOG_SECTION = "analytics"
ANALYTICS_DIRNAME = "LuaUI/widgets/analytics/"
VFS.Include(ANALYTICS_DIRNAME .. "json.lua")

--local host = "localhost"
local host = "52.24.31.116" --"ec2-52-24-31-116.us-west-2.compute.amazonaws.com"
local port = 80
local connected = false
local lastMethod = nil
local sessionID
local gameID

local function dumpConfig()
	-- dump all luasocket related config settings to console
    Spring.Log(LOG_SECTION, LOG.NOTICE, "Dumping config...")
	for _, conf in ipairs({"TCPAllowConnect", "TCPAllowListen", "UDPAllowConnect", "UDPAllowListen"  }) do
		Spring.Log(LOG_SECTION, LOG.NOTICE, conf .. " = " .. Spring.GetConfigString(conf, ""))
	end

end

-- initiates a connection to host:port, returns true on success
local function SocketConnect(host, port)
	client = socket.tcp()
	client:settimeout(3000)
	res, err = client:connect(host, port)
	if not res and not res == "timeout" then
		Spring.Log(LOG_SECTION, LOG.ERROR, "Error in connect: " .. err)
		return false
	end
    --Spring.Echo("CONNECTED")
    connected = true
	return true
end

function widget:Initialize()
    Spring.Log(LOG_SECTION, LOG.NOTICE, "Initializing analytics usage tracking...")
    WG.analytics = self
	dumpConfig()
    -- FIXME: open session after game ID has been received
    self:OpenSession()
end

function widget:GameID(_gameID)
    --Spring.Echo("game ID: ", _gameID)
    gameID = _gameID
end

function widget:Shutdown()
    self:CloseSession()
end

-- called when data was received through a connection
function widget:SocketDataReceived(sock, str)
    self:ParseJsonRPC(str)
end

function widget:OnMethodCallback(method, result)
    --Spring.Echo("method callback", method, result)
    if method == "openSession" then
        sessionID = result
    end
end

function widget:ParseJsonRPC(str)
    Spring.Echo(str)
    --Spring.Log(LOG_SECTION, LOG.NOTICE, str)
    local startIndex = str:find('{')
    local jsonStr = str:sub(startIndex)
    local response = json.decode(jsonStr)
    if response["error"] ~= nil then
        Spring.Log(LOG_SECTION, LOG.ERROR, "Error invoking JSON RPC\n" .. str)
    end
    self:OnMethodCallback(lastMethod, response["result"])
end

function widget:CallJsonRPC(method, ...)
    Spring.Log(LOG_SECTION, LOG.NOTICE, "Calling method: " .. method)
    SocketConnect(host, port)
    local jsonRPC = { id = "jsonrpc", params = {...}, method = method, jsonrpc = "1.0" }
    local content = json.encode(jsonRPC)
    local contentLength = "Content-Length: " .. #content .. "\r\n"
    local msg = "POST /json/ HTTP/1.1\r\nHost: " .. host ..  " \r\n" .. 
        contentLength ..
        "Content-Type: text/plain;charset=UTF-8 \r\n\r\n" .. 
    content
    client:send(msg)
    Spring.Echo(msg)
    lastMethod = method
end

-- local clock = os.clock
-- function sleep(n)  -- seconds
--     local t0 = clock()
--     while clock() - t0 <= n do end
-- end
--     
function widget:CloseSession()
    self:CallJsonRPC("closeSession", sessionID)
    client:close()
end

function widget:OpenSession()
    local players = Spring.GetPlayerRoster()
    --Spring.Echo(players)
    --userName = players[Spring.GetMyPlayerID()].name
    --Spring.Echo(userName)
	self:CallJsonRPC("openSession", { 
        game_name = Game.gameName,
        game_short_name = Game.gameShortName,
        game_version = Game.gameVersion,
        engine_version = Game.version,
        engine_build_flags = Game.buildFlags,
        map_name = Game.mapName,
-- FIXME: gameID is only given once per game (why?!) and isn't a real (printable) string
--         engine_instance_id = gameID,
    --    user_name = userName
    })
end

function widget:Update()
    if client == nil then
        return
    end
	-- get sockets ready for read
	local readable, writeable, err = socket.select({client}, {client}, 3)
	if err ~= nil then
		-- some error happened in select
		if err=="timeout" then
			-- nothing to do, return
			return
		end
		Spring.Log(LOG_SECTION, LOG.ERROR, "Error in select: " .. error)
	end
	for _, input in ipairs(readable) do
		local s, status, partial = input:receive('*a') --try to read all data
		if status == "timeout" or status == nil then
            Spring.Echo("status", status)
			self:SocketDataReceived(input, s or partial)
		elseif status == "closed" then
            Spring.Echo("closed")
			input:close()
			client = nil
		end
	end
end