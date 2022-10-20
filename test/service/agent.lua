local skynet = require "skynet"
local socket = require "skynet.socket"

local tunpack = table.unpack
local tconcat = table.concat
local select = select

local clientfd, addr = ...
clientfd = tonumber(clientfd)

local hall

local function read_table(result)
	local reply = {}
	for i = 1, #result, 2 do reply[result[i]] = result[i + 1] end
	return reply
end

local rds = setmetatable({0}, {
    __index = function (t, k)
        if k == "hgetall" then
            t[k] = function (red, ...)
                return read_table(skynet.call(red[1], "lua", k, ...))
            end
        else
            t[k] = function (red, ...)
                return skynet.call(red[1], "lua", k, ...)
            end
        end
        return t[k]
    end
})

local client = {fd = clientfd}
local CMD = {}

local function client_quit()
    skynet.call(hall, "lua", "offline", client.name)
    if client.isgame and client.isgame > 0 then
        skynet.call(client.isgame, "lua", "offline", client.name)
    end
    skynet.fork(skynet.exit)
end

local function sendto(arg)
    -- local ret = tconcat({"fd:", clientfd, arg}, " ")
    -- socket.write(clientfd, ret .. "\n")
    socket.write(clientfd, arg .. "\n")
end

function CMD.login(name, password)
    if not name and not password then
        sendto("û�������û�����������")
        client_quit()
        return
    end
    local ok = rds:exists("role:"..name)
    if not ok then
        local score = 1000
        rds:hmset("role:"..name, tunpack({
            "name", name,
            "password", password,
            "score", score,
            "isgame", 0,
        }))
        client.name = name
        client.password = password
        client.score = score
        client.isgame = 0
        client.agent = skynet.self()
    else
        local dbs = rds:hgetall("role:"..name)
        if dbs.password ~= password then
            sendto("���������������������")
            return
        end
        client = dbs
        client.fd = clientfd
        client.isgame = tonumber(client.isgame)
        client.agent = skynet.self()
    end
    if client.isgame > 0 then
        local ok = pcall(skynet.call, client.isgame, "lua", "online", client)
        if not ok then
            client.isgame = 0
            sendto("��׼����ʼ��Ϸ������")
        end
    else
        sendto("��׼����ʼ��Ϸ������")
    end
end

function CMD.ready()
    if not client.name then
        sendto("���ȵ�½")
        return
    end
    if client.isgame and client.isgame > 0 then
        sendto("����Ϸ�У�����׼��")
        return
    end
    local ok, msg = skynet.call(hall, "lua", "ready", client)
    if not ok then
        sendto(msg)
        return
    end
    client.isgame = ok
    rds:hset("role:"..client.name, "isgame", ok)
end

function CMD.guess(val)
    if not client.name then
        sendto("�������ȵ�½")
        return
    end
    if not client.isgame or client.isgame == 0 then
        sendto("����û������Ϸ�У�����׼��")
        return
    end
    skynet.send(client.isgame, "lua", "guess", client.name, tonumber(val))
end

local function game_over()
    client.isgame = 0
    rds:hset("role:"..client.name, "isgame", 0)
end

function CMD.help()
    local params = tconcat({
        "*����*:��������Ϸ����ϵͳ���1-100���֣������䣬δ����Ӯ��",
        "help: ��ʾ���п����������;",
        "login: ��½����Ҫ�����û���������;",
        "ready: ׼����������Ϸ���У���Ա�Զ���ʼ��Ϸ;",
        "guess: �����֣�ֻ�ܲ�1~100֮�������;",
        "quit: �˳�",
    }, "\n\r")
    socket.write(clientfd, params .. "\n\r")
end

function CMD.quit()
    client_quit()
end

local function process_socket_events()
    while true do
        local data = socket.readline(clientfd)-- "\n"
        if not data then
            print("�Ͽ����� "..clientfd)
            client_quit()
            return
        end
        local pms = {}
        for pm in data:gmatch("%w+") do
            pms[#pms+1] = pm
        end
        if not next(pms) then
            sendto("error[format], recv data��������ݸ�ʽ\n\r")
            goto __continue__
        end
        local cmd = pms[1]
        if not CMD[cmd] then
            sendto(cmd.." ���������")
            CMD.help()
            goto __continue__
        end
        skynet.fork(CMD[cmd], select(2, tunpack(pms)))
::__continue__::
    end
end

skynet.start(function ()
    print("recv a connection:", clientfd, addr)
    rds[1] = skynet.uniqueservice("redis")
    hall = skynet.uniqueservice("hall")
    socket.start(clientfd)
    skynet.fork(process_socket_events)
    skynet.dispatch("lua", function (_, _, cmd, ...)
        if cmd == "game_over" then
            game_over()
        end
    end)
end)
