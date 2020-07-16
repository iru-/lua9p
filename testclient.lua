--[[
Copyright (c) 2014-2020 Iruatã M.S. Souza <iru.muzgo@gmail.com>
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.
3. The name of the Author may not be used to endorse or promote products
   derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
SUCH DAMAGE.
]]

local data = require'data'
local np = require'9p'

local msize = np.version()
txbuf = data.new(msize)

local root = np.attach("iru", "")
local f, g = np.newfid(), np.newfid()

np.walk(root, f, "/tmp")
np.walk(f, g)

np.create(g, "file", 420, 1)

local ftext = "this is a test\n"
local buf = data.new(ftext)

local n = np.write(g, 0, buf)
if n ~= #buf then
  error("test: expected to write " .. #buf .. " bytes but wrote " .. n)
end

np.clunk(g)

if pcall(np.walk, root, g, "/tmp/.lua9p.non.existant..") ~= false then
  error("test: succeeded when shouldn't (walking to non-existing file)")
end

np.walk(root, g, "/tmp/file")
np.open(g, 0)

local st = np.stat(g)

-- Remove last byte of the file
st.length = st.length - 1
np.wstat(g, st)

buf = np.read(g, 0, st.length)

np.remove(g)

buf:layout{str = {0, #buf, 'string'}}

-- The trailing \n was removed by wstat, we add it again to check the read
if buf.str .. "\n" == ftext then
  io.stderr:write("test ok\n")
else
  error("test failed")
end

np.clunk(f)
np.clunk(root)
