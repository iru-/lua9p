data = require "data"
dio  = require "data_io"
io   = require "io"

fidfree   = nil
fidactive = nil
nextfid   = 0

function newfid()
  local f = fidfree

  if (f) then
    fidfree = f.next
  else
    f = {}
    f.fid = nextfid;
    nextfid = nextfid + 1;
    f.next = fidactive
    fidactive = f
  end

  return f
end

function freefid(f)
  f.next = fidfree
  fidfree = f
end

function tag()
  return 1
end


function perr(s) io.stderr:write(s .. "\n") end

-- Returns a 9P number in table format. Offset and size in bytes
function num9p(offset, size)
  return {offset*8, size*8, 'number', 'le'}
end

function putstr(to, s)
  if #s > #to - 2 then return 0 end

  local p = to:segment():layout{len = num9p(0, 2), s = {2, #s, 's'}}

  p.len = #s
  p.s = s
  return 2 + #s
end

function getstr(from)
  local p = from:segment()
  local len = p:layout{len = num9p(0, 2)}.len
  return p:layout{str = {2, len, 's'}}.str
end

function readmsg(to)
  local p = to:segment():layout{size = num9p(0, 4)}

  dio.read(to, 0, 4)
  dio.read(to, 4, p.size - 4)
end 

function putheader(to, type, size)
  local Lheader = data.layout{
                    size = num9p(0, 4),
                    type = num9p(4, 1),
                    tag  = num9p(5, 2),
  }

  local p = to:segment():layout(Lheader)

  p.size = 7 + size
  p.type = type
  p.tag  = tag()
  return p.size
end

function version()
  local LXversion = data.layout{
                    msize = num9p(7, 4),
  }

  local buf = data.new(19)
  buf:layout(LXversion)
  buf.msize = 8192

  putstr(buf:segment(11), "9P2000")
  putheader(buf, 100, 4 + 2 + 6)
  dio.write(buf, 0, 19)

  buf = data.new(8192)
  buf:layout(LXversion)

  readmsg(buf)
  return buf.msize
end

function attach(uname, aname)
  local LTattach = data.layout{
                   fid  = num9p(7, 4),
                   afid = num9p(11, 4),
  }

  local LRattach = data.layout{
                   qtype = num9p(7, 1),
                   qvers = num9p(8, 4),
                   qpath = num9p(12, 8),
  }

  local tx = txbuf:segment()
  tx:layout(LTattach)

  tx.fid  = newfid()
  tx.afid = -1
  local n = putstr(tx:segment(15), uname)
  n = n + putstr(tx:segment(15 + n), aname)
  
  n = putheader(tx, 104, 8 + n)
  dio.write(tx, 0, n)

  local rx = rxbuf:segment()
  rx:layout(LRattach)
  readmsg(rx)
end

-- name == nil clones ofid to nfid
function walk(ofid, nfid, name)
  local LTwalk = data.layout{
                 fid    = num9p(7, 4),
                 nfid   = num9p(11, 4),
                 nwname = num9p(15, 2),
  }

  local LRwalk = data.layout{
                 size   = num9p(0, 4),
                 type   = num9p(4, 1),
                 tag    = num9p(5, 2),
                 nwqid  = num9p(7, 2),
  }

  local tx = txbuf:segment()
  tx:layout(LTwalk)
  tx.fid    = ofid
  tx.nfid   = nfid

  local n = 0
  if (name) then
    tx.nwname = 1
    n = putstr(tx:segment(17), name)
  else
    tx.nwname = 0
  end

  n = putheader(tx, 110, 10 + n)
  dio.write(tx, 0, n)

  local rx = rxbuf:segment()
  rx:layout(LRwalk)
  readmsg(rx)
end

function _test()
   msize = version()
   txbuf = data.new(msize)
   rxbuf = data.new(msize)
   attach("iru", "")
   local f = newfid() 
   walk(0, f, "/tmp")
   walk(f, newfid())
end

_test()
