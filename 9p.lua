local data = require'data'

local np = {}

-- message types
local Tversion = 100
local Rversion = 101
local Tauth    = 102
local Rauth    = 103
local Tattach  = 104
local Rattach  = 105
local Rerror   = 107
local Tflush   = 108
local Rflush   = 109
local Twalk    = 110
local Rwalk    = 111
local Topen    = 112
local Ropen    = 113
local Tcreate  = 114
local Rcreate  = 115
local Tread    = 116
local Rread    = 117
local Twrite   = 118
local Rwrite   = 119
local Tclunk   = 120
local Rclunk   = 121
local Tremove  = 122
local Rremove  = 123
local Tstat    = 124
local Rstat    = 125
local Twstat   = 126
local Rwstat   = 127
local Tmax     = 128

local HEADSZ   = 7
local FIDSZ    = 4
local QIDSZ    = 13
local IOHEADSZ = 24  -- io (Twrite/Rread) header size, i.e. minimum msize

local fidfree   = nil
local fidactive = nil
local nextfid   = 0

function np.newfid()
  local f = fidfree

  if (f) then
    fidfree = f.next
  else
    f = {}
    f.fid = nextfid
    f.qid = nil
    f.next = fidactive
    
    nextfid = nextfid + 1;
    fidactive = f
  end

  return f
end

local function freefid(f)
  f.next = fidfree
  fidfree = f
end

local curtag = 0xFFFF
function tag()
  local t = curtag
  curtag = (curtag + 1) % 0xFFFF
  return t
end

local function pqid(q)
  perr("(" .. q.path .. " " .. q.version .. " " .. q.type .. ")")
end

local function pfid(f)
  perr("fid " .. f.fid .. " ")
  if f.qid then
    pqid(f.qid)
  end
  perr("\n")
end

local function pstat(st)
  perr("type " .. st.type .. " dev " .. st.dev .. " qid ")
  pqid(st.qid)
  perr(" mode " .. st.mode .. " atime " .. st.atime .. " mtime " .. st.mtime .. " length " .. st.length)
  perr(" name " .. st.name .. " uid " .. st.uid .. " gid " .. st.gid .. " muid " .. st.muid)
  perr("\n")
end


-- Returns a 9P number in table format. Offset and size in bytes
local function num9p(offset, size)
  return {offset*8, size*8, 'number', 'le'}
end

local function putstr(to, s)
  if #s > #to - 2 then
    return 0
  end

  local p = to:segment()
  p:layout{
    len = num9p(0, 2),
    s   = {2, #s, 's'},
  }

  p.len = #s
  p.s = s
  return 2 + #s
end

local function getstr(from)
  local p = from:segment():layout{len = num9p(0, 2)}
  p:layout{str = {2, p.len, 's'}}

  return p.str or ""
end

local function readmsg(type)
  local rawsize = io.read(4)
  local bsize = data.new(rawsize):segment()
  local size = bsize:layout{ size = num9p(0, 4) }.size

  local rawrest = io.read(size - 4)

  local buf = data.new(rawsize .. rawrest):segment()

  local p = buf:layout{
    size = num9p(0, 4),
    type = num9p(4, 1)
  }

  if (p.type ~= type) then
    if (p.type == Rerror) then
      return getstr(p:segment(HEADSZ))
    else
      return "Wrong response type " .. p.type .. ", expected " .. type
    end
  end
  return nil, buf
end

local function writemsg(buf)
  io.write(tostring(buf))
  io.output():flush()
end

local LQid = data.layout{
       type    = num9p(0, 1),
       version = num9p(1, 4),
       path    = num9p(5, 8),
}

local function getqid(from)
  if #from < QIDSZ then
    return nil
  end

  local p = from:segment():layout(LQid)
  local qid = {}

  qid.type    = p.type
  qid.version = p.version
  qid.path    = p.path

  return qid
end

local function putqid(to, qid)
  if #to < QIDSZ then
    return nil
  end

  local p = to:segment():layout(LQid)
  p.type    = qid.type
  p.version = qid.version
  p.path    = qid.path
  return to
end

local Lstat = data.layout{
        size   = num9p(0,  2),
        type   = num9p(2,  2),
        dev    = num9p(4,  4),
        qid    = num9p(8,  QIDSZ),
        mode   = num9p(21, 4),
        atime  = num9p(25, 4),
        mtime  = num9p(29, 4),
        length = num9p(33, 8),
}

local function getstat(seg)
  local p = seg:segment():layout(Lstat)
  local st = {}

  st.size   = p.size
  st.type   = p.type
  st.dev    = p.dev
  st.qid    = getqid(seg:segment(8))
  if not st.qid then
    return nil
  end

  st.mode   = p.mode
  st.atime  = p.atime
  st.mtime  = p.mtime
  st.length = p.length
  st.name   = getstr(seg:segment(41))
  st.uid    = getstr(seg:segment(41 + 2 + #st.name))
  st.gid    = getstr(seg:segment(41 + 2 + #st.name + 2 + #st.uid))
  st.muid   = getstr(seg:segment(41 + 2 + #st.name + 2 + #st.uid + 2 + #st.gid))

  return st
end

local function putstat(to, st)
  local p = to:segment():layout(Lstat)

  p.size   = st.size
  p.type   = st.type
  p.dev    = st.dev

  if not putqid(to:segment(8), st.qid) then
    return nil
  end

  p.mode   = st.mode
  p.atime  = st.atime
  p.mtime  = st.mtime
  p.length = st.length
  putstr(to:segment(41), st.name)
  putstr(to:segment(41 + 2 + #st.name), st.uid)
  putstr(to:segment(41 + 2 + #st.name + 2 + #st.uid), st.gid)
  putstr(to:segment(41 + 2 + #st.name + 2 + #st.uid + 2 + #st.gid), st.muid)

  return to
end

local function putheader(to, type, size)
  local Lheader = data.layout{
                  size = num9p(0, 4),
                  type = num9p(4, 1),
                  tag  = num9p(5, 2),
  }

  local p = to:segment():layout(Lheader)

  p.size = HEADSZ + size
  p.type = type
  p.tag  = tag()
  return p.size
end


function np.version()
  local LXversion = data.layout{
                    msize = num9p(HEADSZ, 4),
  }

  local buf = data.new(19)
  buf:layout(LXversion)
  buf.msize = 8192+IOHEADSZ

  local n = putstr(buf:segment(HEADSZ + 4), "9P2000")
  n = putheader(buf, Tversion, 4 + n)
  writemsg(buf)

  local err, buf = readmsg(Rversion)
  if err then return nil, err end

  buf:layout(LXversion)
  if buf.msize < IOHEADSZ then return "short msize" end

  return buf.msize
end

function np.attach(uname, aname)
  local LTattach = data.layout{
                   fid  = num9p(HEADSZ,          FIDSZ),
                   afid = num9p(HEADSZ + FIDSZ,  4),
  }

  local tx = txbuf:segment()
  tx:layout(LTattach)

  local fid = np.newfid()
  tx.fid  = fid.fid
  tx.afid = -1
  local n = putstr(tx:segment(HEADSZ + FIDSZ + FIDSZ), uname)
  n = n + putstr(tx:segment(HEADSZ + FIDSZ + FIDSZ + n), aname)
  
  n = putheader(tx, Tattach, FIDSZ + FIDSZ + n)
  writemsg(tx:segment(0, n))

  local err, rx = readmsg(Rattach)
  if err then
    return err, nil
  end

  fid.qid = getqid(rx:segment(HEADSZ))
  if not fid.qid then
    return "attach: overflow copying qid", nil
  end

  return nil, fid
end

local function breakpath(path)
  local t = {}
  local k = 1
  local i = 1

  while i < #path do
    local s, es = string.find(path, "[^/]+", i)
    t[k] = string.sub(path, s, es)
    k = k + 1
    i = es + 1
  end
  return t
end

-- path == nil clones ofid to nfid
function np.walk(ofid, nfid, path)
  local LTwalk = data.layout{
                 fid    = num9p(HEADSZ,                  FIDSZ),
                 newfid = num9p(HEADSZ + FIDSZ,          FIDSZ),
                 nwname = num9p(HEADSZ + FIDSZ + FIDSZ,  2),
  }

  local LRwalk = data.layout{
                 nwqid  = num9p(HEADSZ, 2),
  }

  local tx = txbuf:segment()
  tx:layout(LTwalk)
  tx.fid    = ofid.fid
  tx.newfid = nfid.fid

  local n = 0
  if (path) then
    local names = breakpath(path)
    tx.nwname = #names
    for i = 1, #names do
      n = n + putstr(tx:segment(HEADSZ + FIDSZ + FIDSZ + 2 + n), names[i])
    end
  else
    tx.nwname = 0
  end

  n = putheader(tx, Twalk, FIDSZ + FIDSZ + 2 + n)
  writemsg(tx:segment(0, n))

  local err, rx = readmsg(Rwalk)
  if err then
    return err
  end

  rx:layout(LRwalk)

  -- clone succeded
  if (rx.nwqid == 0 and not path) then
    nfid.qid = ofid.qid
    return nil
  end

  -- walk succeded
  if (rx.nwqid == tx.nwname) then
    nfid.qid = getqid(rx:segment(HEADSZ + 2 + (rx.nwqid-1)*QIDSZ))
    return nil
  end

  return "walk: file '" .. path .. "' not found"
end

function np.open(fid, mode)
  local LTopen = data.layout{
                 fid  = num9p(HEADSZ,          FIDSZ),
                 mode = num9p(HEADSZ + FIDSZ,  1),
  }

  local tx = txbuf:segment()
  tx:layout(LTopen)
  tx.fid  = fid.fid
  tx.mode = mode

  local n = putheader(tx, Topen, 5)
  writemsg(tx:segment(0, n))

  local err, rx = readmsg(Ropen)
  if err then return err end

  fid.qid = getqid(rx:segment(HEADSZ))
  if not fid.qid then
    return "open: overflow copying qid"
  end

  return nil
end

function np.create(fid, name, perm, mode)
  local tx = txbuf:segment()
  local n = putstr(tx:segment(11), name)
  
  local LTcreate = data.layout{
                   fid  = num9p(HEADSZ,                  FIDSZ),
                   perm = num9p(HEADSZ + FIDSZ + n,      4),
                   mode = num9p(HEADSZ + FIDSZ + n + 4,  1),
  }
  
  tx:layout(LTcreate)
  tx.fid  = fid.fid
  tx.perm = perm
  tx.mode = mode

  local n = putheader(tx, Tcreate, n + 9)
  writemsg(tx:segment(0, n))

  local err, rx = readmsg(Rcreate)
  if err then return err end

  fid.qid = getqid(rx:segment(HEADSZ))
  if not fid.qid then
    return "create: overflow copying qid"
  end

  return nil
end
                   
function np.read(fid, offset, count)
  local LTread = data.layout{
                 fid    = num9p(HEADSZ,              FIDSZ),
                 offset = num9p(HEADSZ + FIDSZ,      8),
                 count  = num9p(HEADSZ + FIDSZ + 8,  4),
  }
  
  local LRread = data.layout{
                 count = num9p(HEADSZ, 4)
  }

  local tx = txbuf:segment()
  tx:layout(LTread)
  tx.fid    = fid.fid
  tx.offset = offset
  tx.count  = count

  local n = putheader(tx, Tread, FIDSZ + 8 + 4)
  writemsg(tx:segment(0, n))

  local err, rx = readmsg(Rread)
  if err then return err, nil end

  rx:layout(LRread)

  return nil, rx:segment(HEADSZ + 4, rx.count)
end

function np.write(fid, offset, seg)
  local LTwrite = data.layout{
                  fid    = num9p(HEADSZ,              FIDSZ),
                  offset = num9p(HEADSZ + FIDSZ,      8),
                  count  = num9p(HEADSZ + FIDSZ + 8,  4),
  }

  local LRwrite = data.layout{
                 count = num9p(HEADSZ, 4)
  }
 
  local tx = txbuf:segment()
  tx:layout(LTwrite)
  tx.fid    = fid.fid
  tx.offset = offset
  tx.count  = #seg

  local n = putheader(tx, Twrite, FIDSZ + 8 + 4 + #seg)
  writemsg(tx:segment(0, n - #seg))
  writemsg(seg:segment(0, #seg))

  local err, rx = readmsg(Rwrite)
  if err then return err, -1 end

  rx:layout(LRwrite)
  return nil, rx.count
end

local function clunkrm(type, fid)
  local LTclunkrm = data.layout{
                   fid = num9p(HEADSZ, FIDSZ),
  }

  local tx = txbuf:segment()
  tx:layout(LTclunkrm)
  tx.fid = fid.fid

  local n = putheader(tx, type, FIDSZ)
  writemsg(tx:segment(0, n))

  local err, rx = readmsg(type+1)
  if err then return err end

  freefid(fid)
  return nil
end

function np.clunk(fid)
  return clunkrm(Tclunk, fid)
end

function np.remove(fid)
  return clunkrm(Tremove, fid)
end

function np.stat(fid)
  local LTstat = data.layout{
                 fid = num9p(HEADSZ, FIDSZ),
  }

  local tx = txbuf:segment()
  tx:layout(LTstat)
  tx.fid = fid.fid

  local n = putheader(tx, Tstat, FIDSZ)
  writemsg(tx:segment(0, n))
  
  local err, rx = readmsg(Rstat)
  if err then
    return err, nil
  end

  return nil, getstat(rx:segment(HEADSZ + 2))
end

function np.wstat(fid, st)
  local LTwstat = data.layout{
                 fid    = num9p(HEADSZ,          FIDSZ),
                 stsize = num9p(HEADSZ + FIDSZ,  2),
  }

  local tx = txbuf:segment()
  tx:layout(LTwstat)
  tx.fid    = fid.fid
  tx.stsize = st.size + 2

  local n = putheader(tx, Twstat, FIDSZ + 2 + tx.stsize)
  writemsg(tx:segment(0, n - tx.stsize))

  local seg = txbuf:segment(n - tx.stsize)

  if not putstat(seg, st) then
    return "wstat: tx buffer too small"
  end

  writemsg(seg:segment(0, tx.stsize))
  return readmsg(Rwstat)
end

return np
