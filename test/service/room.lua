---
-- @function: 获取table的字符串格式内容，递归
-- @tab： table
-- @ind：不用传此参数，递归用（前缀格式（空格））
-- @return: format string of the table
function dumpTab(tab,ind)
  if(tab==nil)then return "nil" end;
  local str="{";
  if(ind==nil)then ind="  "; end;
  --//each of table
  for k,v in pairs(tab) do
    --//key
    if(type(k)=="string")then
      k=tostring(k).." = ";
    else
      k="["..tostring(k).."] = ";
    end;--//end if
    --//value
    local s="";
    if(type(v)=="nil")then
      s="nil";
    elseif(type(v)=="boolean")then
      if(v) then s="true"; else s="false"; end;
    elseif(type(v)=="number")then
      s=v;
    elseif(type(v)=="string")then
      s="\""..v.."\"";
    elseif(type(v)=="table")then
      s=dumpTab(v,ind.."  ");
      s=string.sub(s,1,#s-1);
    elseif(type(v)=="function")then
      s="function : "..v;
    elseif(type(v)=="thread")then
      s="thread : "..tostring(v);
    elseif(type(v)=="userdata")then
      s="userdata : "..tostring(v);
    else
      s="nuknow : "..tostring(v);
    end;--//end if
    --//Contact
    str=str.."\n"..ind..k..s.." ,";
  end --//end for
  --//return the format string
  local sss=string.sub(str,1,#str-1);
  if(#ind>0)then ind=string.sub(ind,1,#ind-2) end;
  sss=sss.."\n"..ind.."}\n";
  return sss;--string.sub(str,1,#str-1).."\n"..ind.."}\n";
end;--//end function
 
--//网摘,直接打印到屏幕
function printTable(t, n)
  if "table" ~= type(t) then
    return 0;
  end
  n = n or 0;
  local str_space = "";
  for i = 1, n do
    str_space = str_space.."  ";
  end
  print(str_space.."{");
  for k, v in pairs(t) do
    local str_k_v
    if(type(k)=="string")then
      str_k_v = str_space.."  "..tostring(k).." = ";
    else
      str_k_v = str_space.."  ["..tostring(k).."] = ";
    end
    if "table" == type(v) then
      print(str_k_v);
      printTable(v, n + 1);
    else
      if(type(v)=="string")then
        str_k_v = str_k_v.."\""..tostring(v).."\"";
      else
        str_k_v = str_k_v..tostring(v);
      end
      print(str_k_v);
    end
  end
  print(str_space.."}");
end
 


-- test

local skynet = require "skynet"

local socket = require "skynet.socket"

local CMD = {}

local roles = {}

local redisd

local game = {
    random_value = 0,
    user_turn = 0,
    up_limit = 100,
    down_limit = 1,
    turns = {},
}

local function sendto(clientfd, arg)
    -- local ret = tconcat({"fd:", clientfd, arg}, " ")
    -- socket.write(clientfd, ret .. "\n")
    socket.write(clientfd, arg .. "\n\r")
end

local function broadcast(msg)
    for _, role in pairs(roles) do
        if role.isonline > 0 then
            sendto(role.fd, msg)
        end
    end
end

function CMD.start(members)
    for _, role in ipairs(members) do
        role.isonline = 1
        roles[role.name] = role
        game.turns[#game.turns+1] = role.name
    end
    game.random_value = math.random(1, 100)
    broadcast(("房间:%d 系统已经随机一个数字"):format(skynet.self()))
    local rv = math.random(1, 1500)
    if rv <= 500 then
        game.user_turn = 1
    elseif rv <= 1000 then
        game.user_turn = 2
    else
        game.user_turn = 3
    end
    local name = game.turns[game.user_turn]
    broadcast(("请玩家%s开始猜数字"):format(name))
	local role = assert(roles[name])
	sendto(role.fd, ("！！！！！！！！！请%s开始猜数字"):format(name))
	
	--//test code
	b={[printTable]=1,[dumpTab]=33}
	a={inter={ext=1000,uuid="432-43243-43124324",inter2={ext=1000,uuid="432-43243-43124324",[printTable]=2},"anil",nil},"fda",fdsaf,true};
	 
	local sa=dumpTab(b);
	print("145 sa~~~~~~~~~~~~~~~~~~~~~~")
	print(sa);
	 
	sa=dumpTab(a);
	print("149 sa~~~~~~~~~~~~~~~~~~~~~~")
	print(sa);
	print("151 a~~~~~~~~~~~~~~~~~~~~~~")
	printTable(a)
	print("153 b~~~~~~~~~~~~~~~~~~~~~~")
	printTable(b)
	--//test code
	
end

function CMD.offline(name)
    if roles[name] then
        roles[name].isonline = 0
        broadcast(("%s 玩家已经掉线，请求呼叫他上线"):format(name))
    end
    skynet.retpack()
end

function CMD.online(client)
    local name = client.name
    if roles[name] then
        roles[name] = client
        roles[name].isonline = 1
        broadcast(("%s 玩家已经上线"):format(name))
        sendto(client.fd, ("范围变为 [%d - %d], 接下来由 %s 来操作"):format(game.down_limit, game.up_limit, game.turns[game.user_turn]))
    end
    skynet.retpack()
end

local function game_over()
    for _, role in pairs(roles) do
        if role.isonline == 0 then
            skynet.call(redisd, "hset", "role:"..role.name, "isgame", 0)
        else
            skynet.send(role.agent, "lua", "game_over")
            sendto(role.fd, "离开房间")
        end
    end
    skynet.fork(skynet.exit)
end

function CMD.guess(name, val)
    local role = assert(roles[name])
    if game.turns[game.user_turn] ~= name then
        sendto(role.fd, ("错误：还没轮到你操作，现在由 %s 来操作"):format(game.turns[game.user_turn]))
        return
    end
    if not val or val < game.down_limit or val > game.up_limit then
        sendto(role.fd, ("错误：请输入[%d - %d]之间的数字"):format(game.down_limit, game.up_limit))
        return
    end
    game.user_turn = game.user_turn % 3+1
    local next = game.turns[game.user_turn]
    if val == game.random_value then
        broadcast(("游戏结束，%s猜中了数字%d，输了"):format(name, val))
        game_over()
        return
    end
    if val < game.random_value then
        game.down_limit = val+1
        if game.down_limit == game.up_limit then
            broadcast(("游戏结束，只剩下一个数字%d %s输了"):format(val+1, next))
            game_over()
            return
        end
        broadcast(("%s输入的数字太小，范围变为 [%d - %d], 接下来由 %s 来操作"):format(name, game.down_limit, game.up_limit, next))
        return
    end
    if val > game.random_value then
        game.up_limit = val-1
        if game.down_limit == game.up_limit then
            broadcast(("游戏结束，只剩下一个数字%d %s输了"):format(val-1, next))
            game_over()
            return
        end
        broadcast(("%s输入的数字太大，范围变为 [%d - %d], 接下来由 %s 来操作"):format(name, game.down_limit, game.up_limit, next))
        return
    end
end

skynet.start(function ()
    local seed = math.floor(skynet.time()*100)
    math.randomseed(seed, skynet.self())
    redisd = skynet.uniqueservice("redis")
    skynet.dispatch("lua", function (_, _, cmd, ...)
        local func = CMD[cmd]
        if not func then
            return
        end
        func(...)
    end)
end)
