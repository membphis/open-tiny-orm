local redis_c = require "resty.redis"
local cfg_fac = require "tiny.util.cfg"
local cjson = require 'cjson'
local M = {}
local mt = {__index = M}


function M:new(cfg)
    local ins = cfg_fac:get_redis_cfg(cfg)
    setmetatable(ins,mt)
    return ins
end


local function get_con(cfg)
    local red = redis_c:new()
    red:set_timeout(cfg.timeout)
    local ok,err = red:connect(cfg.clusters[1][1],cfg.clusters[1][2])
    if not ok then
        return nil
    end
    local count ,err = red:get_reused_times()
    if 0 == count then
        ok ,err = red:auth(cfg.password)
    elseif err then
        return nil
    end
    red:select(cfg.database)
    return red
end


local function keep_alive(red,cfg)
    local ok,err = red:set_keepalive(cfg.pool.maxIdleTime,cfg.pool.size)   
    if not ok then
        red:close()
    end
    return true
end


function M:subscribe(key,func)
    local co = coroutine.create(function()
        local red = get_con(self)
        local ok,err = red:subscribe(key)
        if not ok then
            return err
        end
        local flag = true
        
        while flag do
            if ngx.worker.exiting() then
                return
            end
            local res,err = red:read_reply()
            if err then
            ;
            else
            if res[1] == "message" then
                local obj = cjson.decode(res[3])
                flag = func(obj.msg)
            end
        end
        
        red:set_keepalive(100,100)
        end
    end)
    coroutine.resume(co)
end

function M:publish(key,msg)
    local red = get_con(self)
    local obj = {}
    obj.type = type(msg)
    obj.msg = msg
    local  ok,err = red:publish(key,cjson.encode(obj))
    keep_alive(red,self)
    if not ok then
        return false
    else
        return true
    end
end
return M
