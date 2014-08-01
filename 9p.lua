data = require "data"
dio  = require "data_io"
io   = require "io"

-- message types
Tversion = 100
Rversion = 101
Tauth    = 102
Rauth    = 103
Tattach  = 104
Rattach  = 105
Rerror   = 107
Tflush   = 108
Rflush   = 109
Twalk    = 110
Rwalk    = 111
Topen    = 112
Ropen    = 113
Tcreate  = 114
Rcreate  = 115
Tread    = 116
Rread    = 117
Twrite   = 118
Rwrite   = 119
Tclunk   = 120
Rclunk   = 121
Tremove  = 122
Rremove  = 123
Tstat    = 124
Rstat    = 125
Twstat   = 126
Rwstat   = 127
Tmax     = 128

-- io (Twrite/Rread) header size, i.e. minimum msize
IOHEADSZ = 24

fidfree   = nil
fidactive = nil
nextfid   = 0

function newfid()
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

function freefid(f)
  f.next = fidfree
  fidfree = f
end

function tag()
  return 1
end

function perr(s) io.stderr:write(s .. "\n") end
function pfid(f)
  local s = "fid " .. f.fid
  if f.qid then
    s = s .. " qid {type = " .. f.qid.type .. ", version = " .. f.qid.version .. ", path = " .. f.qid.path .. "}"
  end
  perr(s)
end

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

function readmsg(type, to)
  local p = to:segment():layout{size = num9p(0, 4), type = num9p(4, 1)}

  dio.read(to, 0, 4)
  dio.read(to, 4, p.size - 4)

  if (p.type ~= type) then
    if (p.type == Rerror) then
      return getstr(p:segment(7))
    else
      return "Wrong response type " .. p.type .. ", expected " .. type
    end
  end
  return nil
end

function getqid(buf)
  local LQid = data.layout{
                   type = num9p(0, 1),
                   vers = num9p(1, 4),
                   path = num9p(5, 8),
  }

  local p = buf:segment():layout(LQid)
  return {type = p.type, version = p.vers, path = p.path}
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
  buf.msize = 8192+IOHEADSZ

  putstr(buf:segment(11), "9P2000")
  putheader(buf, 100, 4 + 2 + 6)
  dio.write(buf, 0, 19)

  buf = data.new(8192)
  buf:layout(LXversion)

  local err = readmsg(Rversion, buf)
  return buf.msize, err
end

function attach(uname, aname)
  local LTattach = data.layout{
                   fid  = num9p(7, 4),
                   afid = num9p(11, 4),
  }

  local tx = txbuf:segment()
  tx:layout(LTattach)

  local fid = newfid()
  tx.fid  = fid.fid
  tx.afid = -1
  local n = putstr(tx:segment(15), uname)
  n = n + putstr(tx:segment(15 + n), aname)
  
  n = putheader(tx, Tattach, 8 + n)
  dio.write(tx, 0, n)

  local rx = rxbuf:segment()

  local err = readmsg(Rattach, rx)
  if err then return err, nil end

  fid.qid = getqid(rx:segment(7))
  return nil, fid
end

-- name == nil clones ofid to nfid
-- XXX we only support walking to a file at a time
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
  tx.fid    = ofid.fid
  tx.nfid   = nfid.fid

  local n = 0
  if (name) then
    tx.nwname = 1
    n = putstr(tx:segment(17), name)
  else
    tx.nwname = 0
  end

  n = putheader(tx, Twalk, 10 + n)
  dio.write(tx, 0, n)

  local rx = rxbuf:segment()
  rx:layout(LRwalk)

  local err = readmsg(Rwalk, rx)
  if err then return err end

  if (rx.nwqid == 0) then
    nfid.qid = ofid.qid
  else
    nfid.qid = getqid(rx:segment(9))
  end
end

function open(fid, mode)
  local LTopen = data.layout{
                 fid  = num9p(7, 4),
                 mode = num9p(11, 1),
  }

  local LRopen = data.layout{
                 size   = num9p(0, 4),
                 type   = num9p(4, 1),
                 tag    = num9p(5, 2),
  }

  local tx = txbuf:segment()
  tx:layout(LTopen)
  tx.fid  = fid.fid
  tx.mode = mode

  local n = putheader(tx, Topen, 5)
  dio.write(tx, 0, n)

  local rx = rxbuf:segment()
  rx:layout(LRopen)
  local err = readmsg(Ropen, rx)
  if err then return err end

  fid.qid = getqid(rx:segment(7))
  return nil
end

function create(fid, name, perm, mode)
  local tx = txbuf:segment()
  local n = putstr(tx:segment(11), name)
  
  local LTcreate = data.layout{
                   fid  = num9p(7, 4),
                   perm = num9p(11 + n, 4),
                   mode = num9p(11 + n + 4, 1),
  }
  
  tx:layout(LTcreate)
  tx.fid  = fid.fid
  tx.perm = perm
  tx.mode = mode

  local n = putheader(tx, Tcreate, n + 9)
  dio.write(tx, 0, n)

  local rx = rxbuf:segment()
  local err = readmsg(Rcreate, rx)
  if err then return err end

  fid.qid = getqid(rx:segment(7))
  return nil
end
                   
function read(fid, offset, count)
  local LTread = data.layout{
                 fid    = num9p(7, 4),
                 offset = num9p(11, 8),
                 count  = num9p(19, 4),
  }
  
  local LRread = data.layout{
                 count = num9p(7, 4)
  }

  local tx = txbuf:segment()
  tx:layout(LTread)
  tx.fid    = fid.fid
  tx.offset = offset
  tx.count  = count

  local n = putheader(tx, Tread, 16)
  dio.write(tx, 0, n)

  local rx = rxbuf:segment()
  rx:layout(LRread)
  local err = readmsg(Rread, rx)
  if err then return err, nil end

  return nil, rx:segment(11, rx.count)
end

function write(fid, offset, seg)
  local LTwrite = data.layout{
                  fid    = num9p(7, 4),
                  offset = num9p(11, 8),
                  count  = num9p(19, 4),
  }

  local LRwrite = data.layout{
                 count = num9p(7, 4)
  }
 
  local tx = txbuf:segment()
  tx:layout(LTwrite)
  tx.fid    = fid.fid
  tx.offset = offset
  tx.count  = #seg

  local n = putheader(tx, Twrite, 16 + #seg)
  dio.write(tx, 0, n - #seg)
  dio.write(seg, 0, #seg)

  local rx = rxbuf:segment()
  rx:layout(LRwrite)
  return readmsg(Rwrite, rx)
end

function clunkrm(type, fid)
  local LTclunkrm = data.layout{
                   fid = num9p(7, 4),
  }

  local tx = txbuf:segment()
  tx:layout(LTclunkrm)
  tx.fid = fid.fid

  local n = putheader(tx, type, 4)
  dio.write(tx, 0, n)

  local rx = rxbuf:segment()
  return readmsg(type+1, rx)
end

function clunk(fid)
  return clunkrm(Tclunk, fid)
end

function remove(fid)
  return clunkrm(Tremove, fid)
end

function _test()
  local msize, err = version()
  if err then
    perr(err)
    return
  end
  if msize < IOHEADSZ then
    perr("short msize")
    return
  end

  txbuf = data.new(msize)
  rxbuf = data.new(msize)

  err, root = attach("iru", "")
  if err then
    perr(err)
    return
  end

  local f, g = newfid(), newfid()

  err = walk(root, f, "/tmp")
  if err then
    perr(err)
    return
  end

  err = walk(f, g)
  if err then
    perr(err)
    return
  end

  err = create(g, "file", 420, 1)
  if err then
    perr(err)
    return
  end

  buf = data.new("write test\n")
  err = write(g, 0, buf)
  if err then
    perr(err)
    return
  end

  local err = clunk(g)
  if err then
    perr(err)
    return
  end

  local err = walk(root, g, "/tmp/file")
  if err then
    perr(err)
    return
  end

  local err = open(g, 0)
  if err then
    perr(err)
    return
  end

  local err, buf = read(g, 0, 16)
  if err then
    perr(err)
    return
  end
  perr("read " .. #buf .. " bytes")
  buf:layout{str = {0, #buf, 'string'}}
  perr(buf.str)

  local err = remove(g)
  if err then
    perr(err)
    return
  end
end

_test()
