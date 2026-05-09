if (rp.vars) then return end;

local a = {
  store = {};
  localStore = {};
  type = {};
} a.__index = a;

do
  local curVar
  a.Add = function(self, var)
    self.type[var] = {};
    curVar = var;
    return self
  end;
  a.Write = function(self, ...)
    self.type[curVar].Write = {...}
    return self
  end;
  a.Read = function(self, ...)
    self.type[curVar].Read = {...}
    return self
  end;
  a.PassesFilter = function(self, func)
    self.type[curVar].Filter = func;
  end;
end;

local pairs = pairs
local EntIndex = ENTITY.EntIndex

if CLIENT then
  local ReadUInt, ReadString, ReadData, ReadTable = net.ReadUInt, net.ReadString, net.ReadData, net.ReadTable;
  local ReadType, JSONToTable, Decompress = net.ReadType, util.JSONToTable, util.Decompress;
  local hookRun = hook.Run;
  local function removeVar()
    local i = ReadUInt(13);
    if (not rp.vars.store[i]) then return end;
    local var = ReadString();
    rp.vars.store[i][var] = nil;
    hookRun("varChanged", i, var)
    // auto clean
    if (not next(rp.vars.store[i])) then rp.vars.store[i] = nil end;
  end;

  local function removeLocalVar()
    local i = ReadUInt(13)
    if (not rp.vars.localStore[i]) then return end;
    local var = ReadString();
    rp.vars.localStore[i][var] = nil;
    hookRun("localVarChanged", var)
    // auto clean
    if (not next(rp.vars.localStore[i])) then rp.vars.localStore[i] = nil end;
  end;

  local function readVar(len)
    local index, var = ReadUInt(13), ReadString()

    rp.vars.store[index] = rp.vars.store[index] || {};
    if rp.vars.type[var] then
      local read = rp.vars.type[var].Read
      if read[1] == ReadTable then
        local data = JSONToTable(Decompress(ReadData(len*.125)))
        rp.vars.store[index][var] = data;
        return
      end;
      rp.vars.store[index][var] = read[1](read[2])
      return
    end;
    rp.vars.store[index][var] = ReadType();
    hookRun("varChanged", index, var, rp.vars.store[index][var]);
  end;

  local function readLocalVar(len)
    local index, var = ReadUInt(13), ReadString()
    rp.vars.localStore[index] = rp.vars.localStore[index] || {};
    if rp.vars.type[var] then
      local read = rp.vars.type[var].Read
      if read[1] == ReadTable then
        local data = JSONToTable(Decompress(ReadData(len*.125)))
        rp.vars.localStore[index][var] = data;
        hookRun("localVarChanged", var, data)
        return
      end;
      rp.vars.localStore[index][var] = read[1](read[2])
      hookRun("localVarChanged", var, rp.vars.localStore[index][var])
      return
    end;
    rp.vars.localStore[index][var] = ReadType();
    hookRun("localVarChanged", var, rp.vars.localStore[index][var])
  end;
  
  net.Receivers['rp.var.localsend'] = readLocalVar
  net.Receivers['rp.var.send'] = readVar
  net.Receivers['rp.var.localremove'] = removeLocalVar
  net.Receivers['rp.var.remove'] = removeVar
else
  util.AddNetworkString('rp.var.remove');
  util.AddNetworkString('rp.var.localremove');
  util.AddNetworkString('rp.var.send');
  util.AddNetworkString('rp.var.localsend');

  local Start, WriteString, WriteData = net.Start, net.WriteString, net.WriteData
  local Send, WriteType, WriteUInt = net.Send, net.WriteType, net.WriteUInt
  local Compress, TableToJSON = util.Compress, util.TableToJSON
  local WriteTable = net.WriteTable
  
  local function removeVar(entIndex, var, filter)
    if (not filter) then return end;
    Start("rp.var.remove");
    WriteUInt(entIndex, 13);
    WriteString(var);
    Send(filter);
  end;

  local function removeLocalVar(entIndex, var, filter)
    if (not filter) then return end;
    -- print("remove", Entity)
    -- if (istable(filter)) then
    --   PrintTable(filter)
    -- end;
    Start("rp.var.localremove");
    WriteUInt(entIndex, 13);
    WriteString(var);
    Send(filter);
  end;

  local function setVar(client, var, value)
    local entIndex = EntIndex(client)

    rp.vars.store[entIndex] = rp.vars.store[entIndex] || {};
    
    if not value then if (rp.vars.store[entIndex][var]) == nil then return end; rp.vars.store[entIndex][var] = nil; removeVar(entIndex, var, select(2, player.Iterator())) return end;
    rp.vars.store[entIndex][var] = value;

    Start("rp.var.send");
    WriteUInt(entIndex, 13);
    WriteString(var);
    
    if rp.vars.type[var] then
      local write = rp.vars.type[var].Write
      if write[1] == WriteTable then
        local data = Compress(TableToJSON(value))

        WriteData(data, #data);
        Send(select(2, player.Iterator()));
        return
      end;

      write[1](value, write[2]);
      Send(select(2, player.Iterator()));
      return
    end;

    WriteType(value);
    Send(select(2, player.Iterator()));
  end;

  local function setLocalVar(client, var, value)
    local entIndex = EntIndex(client)

    rp.vars.localStore[entIndex] = rp.vars.localStore[entIndex] || {};
    if (not value) then
      if (rp.vars.localStore[entIndex][var]) == nil then return end; 
      rp.vars.localStore[entIndex][var] = nil; 
      removeLocalVar(entIndex, var, rp.vars.type[var] && rp.vars.type[var].Filter && rp.vars.type[var]:Filter(client) || client)
    return 
    end;
    rp.vars.localStore[entIndex][var] = value;

    Start("rp.var.localsend");
    WriteUInt(entIndex, 13);
    WriteString(var);
    
    if rp.vars.type[var] then
      local write = rp.vars.type[var].Write
      if write[1] == WriteTable then
        local data = Compress(TableToJSON(value))

        WriteData(data, #data);
        Send(client);
        return
      end;

      write[1](value, write[2])
      Send(rp.vars.type[var].Filter && rp.vars.type[var]:Filter(client) || client);
      return
    end;

    WriteType(value);
    Send(client);
  end;

  function a.Clean(ent)
    local id = ent:EntIndex()
    -- if (rp.vars.type[var])
    if (rp.vars.localStore[id]) then
      for key in next, rp.vars.localStore[id] do
        if (not rp.vars.type[key] || not rp.vars.type[key].Filter) then continue end;
        -- print("remove", id, key)
        removeLocalVar(id, key, rp.vars.type[key]:Filter(ent))
      end;
      rp.vars.localStore[id] = nil;
    end;
    
      
    if not rp.vars.store[id] then return end; --xd
    local players = select(2, player.Iterator());
    for var in next, rp.vars.store[id] do
      removeVar(id, var, players)
    end;
    rp.vars.store[id] = nil;
    id = nil;
  end;

  function a.Sync(client)
    rp.vars.store[EntIndex(client)] = rp.vars.store[EntIndex(client)] || {}
    rp.vars.localStore[EntIndex(client)] = rp.vars.localStore[EntIndex(client)] || {}

    for id in next, rp.vars.store do
      for var, value in pairs(rp.vars.store[id]) do
        Start("rp.var.send");
        WriteUInt(id, 13)
        WriteString(var);
        
        if rp.vars.type[var] then
          local write = rp.vars.type[var].Write
          if write[1] == WriteTable then
            local data = Compress(TableToJSON(value))

            WriteData(data, #data);
            Send(client);
            continue
          end;

          write[1](value, write[2]);
          Send(client);
          continue
        end;

        WriteType(value);
        Send(client);
      end;
    end;
  end;

  ENTITY.SetRPVar = setVar
  ENTITY.SetLocalRPVar = setLocalVar
  PLAYER.SetRPVar = setVar
  PLAYER.SetLocalRPVar = setLocalVar
  
  a.SetVar = function(self, var, value)
    setVar(Entity(0), var, value)
  end;

  a.SetLocalVar = function(self, var, value)
    setLocalVar(Entity(0), var, value)
  end;
end;

a.GetVar = function(self, var, default) return self.store[0] && self.store[0][var] || default end;
a.GetLocalVar = function(self, var, default) return self.localStore[0] && self.localStore[0][var] || default end;

rp.vars = setmetatable({}, a);
rp.vars.store[0] = {}

ENTITY.GetRPVar = function(self, var, default) local entIndex = EntIndex(self); return rp.vars.store[entIndex]&&rp.vars.store[entIndex][var] || default end;
ENTITY.GetLocalRPVar = function(self, var, default) return rp.vars.localStore[EntIndex(self)]&&rp.vars.localStore[EntIndex(self)][var] || default end;
PLAYER.GetRPVar = function(self, var, default) local entIndex = EntIndex(self); return rp.vars.store[entIndex]&&rp.vars.store[entIndex][var] || default end;
PLAYER.GetLocalRPVar = function(self, var, default) return rp.vars.localStore[EntIndex(self)]&&rp.vars.localStore[EntIndex(self)][var] || default end;