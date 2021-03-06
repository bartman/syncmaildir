-- Released under the terms of GPLv3 or at your option any later version.
-- No warranties.
-- Copyright 2009 Enrico Tassi <gares@fettunta.org>
--
-- common code for smd-client/server

local PROTOCOL_VERSION="1.0"

local verbose = false

local PREFIX = '@PREFIX@'

local __G = _G

module('syncmaildir',package.seeall)

-- set mddiff path
MDDIFF = ""
if string.sub(PREFIX,1,1) == '@' then
		MDDIFF = os.getenv('HOME')..'/Projects/syncmaildir/mddiff'
		io.stderr:write('smd-client not installed, assuming mddiff is: ',
			MDDIFF,'\n')
else
		MDDIFF = PREFIX .. '/bin/mddiff'
end

-- set sha1sum executable name
SHA1SUM = '@SHA1SUM@'
if string.sub(SHA1SUM,1,1) == '@' then
		SHA1SUM = 'sha1sum'
end

-- set xdelta executable name
XDELTA = '@XDELTA@'
if string.sub(XDELTA,1,1) == '@' then
		XDELTA = 'xdelta'
end

CPN = '@CPN@'
if string.sub(CPN,1,1) == '@' then
		CPN = 'cp -n'
end

function set_verbose(v)
	verbose = v
end

function log(msg)
	if verbose then
		io.stderr:write(msg,'\n')
	end
end

function log_error(msg)
	io.stderr:write('ERROR: ',msg,'\n')
end

function log_tag(tag)
	io.stderr:write('TAGS: ',tag,'\n')
end

function log_tags(context, cause, human, ...)
	if human then human = "necessary" else human = "avoidable" end
	local suggestions = {}
	local suggestions_string = ""
	if select('#',...) > 0 then 
			suggestions_string = 
				"suggested-actions("..table.concat({...}," ")..")"
	else 
			suggestions_string = "" 
	end
	log_tag("error::context("..context..") "..
		"probable-cause("..cause..") "..
		"human-intervention("..human..") ".. suggestions_string)
end

-- ======================== data transmission protocol ======================

function transmit(out, path, what)
	what = what or "all"
	local f, err = io.open(path,"r")
	if not f then
		log_error("Unable to open "..path..": "..(err or "no error"))
		log_error("The problem should be transient, please retry.")
		log_tags("transmit", "simultaneous-mailbox-edit",false,"retry")
		error('Unable to open requested file.')
	end
	local size, err = f:seek("end")
	if not size then
		log_error("Unable to calculate the size of "..path)
		log_error("If it is not a regular file, please move it away.")
		log_error("If it is a regular file, please report the problem.")
		log_tags("transmit", "non-regular-file",true,
			"display-permissions("..quote(path)..")")
		error('Unable to calculate the size of the requested file.')
	end
	f:seek("set")

	if what == "header" then
		local line
		local header = {}
		size = 0
		while line ~= "" do
			line = assert(f:read("*l"))
			header[#header+1] = line
			header[#header+1] = "\n"
			size = size + 1 + string.len(line)
		end
		f:close()
		out:write("chunk " .. size .. "\n")
		out:write(unpack(header))
		out:flush()
		return
	end

	if what == "body" then
		local line
		while line ~= "" do
			line = assert(f:read("*l"))
			size = size -1 -string.len(line)
		end
	end

	out:write("chunk " .. size .. "\n")
	while true do
		local data = f:read(16384)
		if data == nil then break end
		out:write(data)
	end
	out:flush()

	f:close()
end

function receive(inf,outfile)
	local outf = io.open(outfile,"w")
	if not outf then
			log_error("Unable to open "..outfile.." for writing.")
			log_error('It may be caused by bad directory permissions, '..
				'please check.')
			log_tags("receive", "non-writeable-file",true,
				"display-permissions("..quote(outfile)..")")
			error("Unable to write incoming data")
	end

	local line = inf:read("*l")
	if line == nil or line == "ABORT" then
		log_error("Data transmission failed.")
		log_error("This problem is transient, please retry.")
		error('server sent ABORT or connection died')
	end
	local len = tonumber(line:match('^chunk (%d+)'))
	while len > 0 do
		local next_chunk = 16384
		if len < next_chunk then next_chunk = len end
		local data = inf:read(next_chunk)
		len = len - data:len()
		outf:write(data)
	end
	outf:close()
end

function handshake(dbfile)
	-- send the protocol version and the dbfile sha1 sum
	io.write('protocol ',PROTOCOL_VERSION,'\n')
	touch(dbfile)
	local inf = io.popen(SHA1SUM..' '.. dbfile,'r')
	local db_sha = inf:read('*a'):match('^(%S+)')
	io.write('dbfile ',db_sha,'\n')
	io.flush()

	-- check protocol version and dbfile sha
	local line = io.read('*l')
	if line == nil then
		log_error("Network error.")
		log_error("Unable to get any data from the other endpoint.")
		log_error("This problem may be transient, please retry.")
		log_error("Hint: did you correctly setup the SERVERNAME variable")
		log_error("on your client? Did you add an entry for it in your ssh")
		log_error("configuration file?")
		log_tags("handshake", "network",false,"retry")
		error('Network error')
	end
	local protocol = line:match('^protocol (.+)$')
	if protocol ~= PROTOCOL_VERSION then
		log_error('Wrong protocol version.')
		log_error('The same version of syncmaildir must be used on '..
			'both endpoints')
		log_tags("handshake", "protocol-mismatch",true)
		error('Protocol version mismatch')
	end
	line = io.read('*l')
	if line == nil then
		log_error "The client disconnected during handshake"
		log_tags("handshake", "network",false,"retry")
		error('Network error')
	end
	local sha = line:match('^dbfile (%S+)$')
	if sha ~= db_sha then
		log_error('Local dbfile and remote db file differ.')
		log_error('Remove both files and push/pull again.')
		log_tags("handshake", "db-mismatch",true,"run(rm "..
			quote(dbfile)..")")
		error('Database mismatch')
	end
end

function dbfile_name(endpoint, mailboxes)
	local HOME = os.getenv('HOME')
	os.execute('mkdir -p '..HOME..'/.smd/')
	local dbfile = HOME..'/.smd/' ..endpoint:gsub('/$',''):gsub('/','_').. '__' 
		..table.concat(mailboxes,'__'):gsub('/$',''):gsub('/','_').. '.db.txt'
	return dbfile
end

-- =================== fast/maildir aware mkdir -p ==========================

local mkdir_p_cache = {}

-- function to create the dir calling the real mkdir command
-- pieces is a list components of the patch, they are concatenated
-- separated by '/' and if absolute is true prefixed by '/'
function make_dir_aux(absolute, pieces)
	local root = ""
	if absolute then root = '/' end
	local dir = root .. table.concat(pieces,'/')
	if not mkdir_p_cache[dir] then
		local rc = os.execute('mkdir -p '..dir)
		if rc ~= 0 then
			log_error("Unable to create directory "..dir)
			log_error('It may be caused by bad directory permissions, '..
				'please check.')
			log_tags("mkdir", "wrong-permissions",true,
				"display-permissions("..quote(dir)..")")
			error("Directory creation failed")
		end
		mkdir_p_cache[dir] = true
	end
end

-- creates a directory that can contains a path, should be equivalent
-- to mkdir -p `dirname path`. moreover, if the last component is 'tmp',
-- siblings 'cur' and 'new' are created too. exampels:
--  mkdir_p('/foo/bar')     creates /foo
--  mkdir_p('/foo/bar/')    creates /foo/bar/
--  mkdir_p('/foo/tmp/baz') creates /foo/tmp/, /foo/cur/ and /foo/new/
function mkdir_p(path)
	local t = {} 

	local absolute = false
	if string.byte(path,1) == string.byte('/',1) then absolute = true end

	-- tokenization
	for m in path:gmatch('([^/]+)') do t[#t+1] = m end

	-- strip last component is not ending with '/'
	if string.byte(path,string.len(path)) ~= string.byte('/',1) then 
		table.remove(t,#t) 
	end

	make_dir_aux(absolute, t)

	-- if we are building a new maildir folder, also add new and cur
	if t[#t] == "tmp" then
		t[#t] = "new"
		make_dir_aux(absolute, t)
		t[#t] = "cur"
		make_dir_aux(absolute, t)
	end
end

-- ============== maildir aware tempfile name generator =====================

-- complex function to generate a valid tempfile name for path, possibly using
-- the tmp directory if a subdir of path is new or cur and use_tmp is true
--
function tmp_for(path,use_tmp)
	if use_tmp == nil then use_tmp = true end
	local t = {} 
	local absolute = ""
	if string.byte(path,1) == string.byte('/',1) then absolute = '/' end
	for m in path:gmatch('([^/]+)') do t[#t+1] = m end
	local fname = t[#t]
	local time, pid, host, tags = fname:match('^(%d+)%.(%d+)%.([^:]+)(.*)$')
	time = time or os.date("%s")
	pid = pid or "1"
	host = host or "localhost"
	tags = tags or ""
	table.remove(t,#t)
	local i, found = 0, false
	if use_tmp then
		for i=#t,1,-1 do
			if t[i] == 'cur' or t[i] == 'new' then 
				t[i] = 'tmp' 
				found = true
				break
			end
		end
	end
	make_dir_aux(absolute == '/', t)
	local newpath
	if not found then
		time = os.date("%s")
		t[#t+1] = time..'.'..pid..'.'..host..tags
	else
		t[#t+1] = fname
	end
	newpath = absolute .. table.concat(t,'/') 
	local attempts = 0
	while exists(newpath) do 
		if attempts > 10 then
			error('unable to generate a fresh tmp name')			
		else 
			time = os.date("%s")
			host = host .. 'x'
			t[#t] = time..'.'..pid..'.'..host..tags
			newpath = absolute .. table.concat(t,'/') 
			attempts = attempts + 1
		end
	end
	return newpath
end

-- =========================== misc helpers =================================

function sha_file(name)
	local inf = io.popen(MDDIFF .. ' ' .. name)
	local hsha, bsha = inf:read('*a'):match('(%S+) (%S+)') 
	inf:close()
	return hsha, bsha
end

function exists(name)
	local f = io.open(name,'r')
	if f ~= nil then
		f:close()
		return true
	else
		return false		
	end
end

function exists_and_sha(name)
	if exists(name) then
		local h, b = sha_file(name)
		return true, h, b
	else
		return false
	end
end

function touch(f)
	local h = io.open(f,'r')
	if h == nil then
		h = io.open(f,'w')
		if h == nil then
			log_error('Unable to touch '..quote(f))
			log_tags("touch","bad-permissions",true,
				"display-permissions("..quote(f)..")")
			error("Unable to touch a file")
		else
			h:close()
		end
	else
		h:close()
	end
end

function quote(s)
	return '"' .. s:gsub('"','\\"'):gsub("%)","\\)").. '"'
end

function homefy(s)
	if string.byte(s,1) == string.byte('/',1) then
		return s
	else
		return os.getenv('HOME')..'/'..s
	end
end	

function assert_exists(name)
	local name = name:match('^([^ ]+)')
	local rc = os.execute('type '..name..' >/dev/null 2>&1')
	assert(rc == 0,'Not found: "'..name..'"')
end

-- prints the stack trace. idiom is 'rewturn(trance(x))' so that
-- we have in the log the path for the leaf that computed x
function trace(x)
	if verbose then
		local t = {}
		local n = 2
		while true do
			local d = debug.getinfo(n,"nl")
			if not d or not d.name then break end
			t[#t+1] = d.name ..":".. (d.currentline or "?")
			n=n+1
		end
		io.stderr:write('TRACE: ',table.concat(t," | "),'\n')
	end
	return x
end

function set_strict()
-- strict access to the global environment
	setmetatable(__G,{
		__newindex = function (t,k,v)
			local d = debug.getinfo(2,"nl")
			error((d.name or '?')..': '..(d.currentline or '?')..
				' :attempt to create new global '..k)
		end;
		__index = function(t,k)
			local d = debug.getinfo(2,"nl")
			error((d.name or '?')..': '..(d.currentline or '?')..
				' :attempt to read undefined global '..k)
		end;
	})
end

-- vim:set ts=4:
