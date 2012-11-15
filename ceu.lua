_CEU = true

_OPTS = {
    input     = nil,
    output    = '_ceu_code.cceu',

    defs_file  = '_ceu_defs.h',

    join      = true,
    c_calls   = false,

    m4        = false,
    m4_args   = false,

    tp_word    = 4,
    tp_pointer = 4,
}

_OPTS_NPARAMS = {
    input     = nil,
    output    = 1,

    defs_file  = 1,

    join      = 0,
    c_calls   = 1,

    m4        = 0,
    m4_args   = 1,

    tp_word    = 1,
    tp_pointer = 1,
}

local params = {...}
local i = 1
while i <= #params
do
    local p = params[i]
    i = i + 1

    if p == '-' then
        _OPTS.input = '-'

    elseif string.sub(p, 1, 2) == '--' then
        local no = false
        local opt = string.gsub(string.sub(p,3), '%-', '_')
        if string.find(opt, '^no_') then
            no = true
            opt = string.sub(opt, 4)
        end
        if _OPTS_NPARAMS[opt] == 0 then
            _OPTS[opt] = not no
        else
            local opt = string.gsub(string.sub(p,3), '%-', '_')
            _OPTS[opt] = string.match(params[i], "%'?(.*)%'?")
            i = i + 1
        end

    else
        _OPTS.input = p
    end
end
if not _OPTS.input then
    io.stderr:write([[

    ./ceu <filename>           # Ceu input file, or `-´ for stdin
    
        --output <filename>    # C output file (stdout)
    
        --defs-file <filename> # define constants in a separate output file (no)

        --join (--no-join)     # join lines enclosed by /*{-{*/ and /*}-}*/ (join)
        --c-calls              # TODO

        --m4 (--no-m4)         # preprocess the input with `m4´ (no-m4)
        --m4-args              # preprocess the input with `m4´ passing arguments in between `"´ (no)

        --tp-word              # sizeof a word in bytes    (4)
        --tp-pointer           # sizeof a pointer in bytes (4)

]])
    os.exit(1)
end

-- C_CALLS
if _OPTS.c_calls then
    local t = {}
    for v in string.gmatch(_OPTS.c_calls, "(%w+)") do
        t[v] = true
    end
    _OPTS.c_calls = t
end


-- INPUT
local inp
if _OPTS.input == '-' then
    inp = io.stdin
else
    inp = assert(io.open(_OPTS.input))
end
_STR = inp:read'*a'

if _OPTS.m4 or _OPTS.m4_args then
    local args = _OPTS.m4_args and string.sub(_OPTS.m4_args, 2, -2) or ''   -- remove `"´
    local m4_file = (_OPTS.input=='-' and '_ceu_tmp.ceu_m4') or _OPTS.input..'_m4'
    local m4 = assert(io.popen('m4 '..args..' - > '..m4_file, 'w'))
    m4:write(_STR)
    m4:close()

    _STR = assert(io.open(m4_file)):read'*a'
    --os.remove(m4_file)
end

-- PARSE
do
    dofile 'tp.lua'

    dofile 'lines.lua'
    dofile 'parser.lua'
    dofile 'ast.lua'
    --_AST.dump(_AST.root)
    dofile 'env.lua'
    dofile 'tight.lua'
    dofile 'props.lua'
    dofile 'labels.lua'
    dofile 'mem.lua'
    dofile 'code.lua'
end

local tps = { [0]='void', [1]='u8', [2]='u16', [4]='u32' }

-- TEMPLATE
local tpl
do
    tpl = assert(io.open'template.c'):read'*a'

    local sub = function (str, from, to)
        local i,e = string.find(str, from)
        return string.sub(str, 1, i-1) .. to .. string.sub(str, e+1)
    end

    tpl = sub(tpl, '=== CEU_NMEM ===',     _MAIN.mem.max)
    tpl = sub(tpl, '=== CEU_NTRACKS ===',  _AST.root.ns.tracks)
    tpl = sub(tpl, '=== CEU_NLSTS ===',    _AST.root.ns.awaits)
    tpl = sub(tpl, '=== CEU_NLBLS ===',    #_LBLS.list)

    tpl = sub(tpl, '=== TCEU_NTRK ===',  tps[_ENV.types.tceu_ntrk])
    tpl = sub(tpl, '=== TCEU_NLST ===',  tps[_ENV.types.tceu_nlst])
    tpl = sub(tpl, '=== TCEU_NEVT ===',  tps[_ENV.types.tceu_nevt])
    tpl = sub(tpl, '=== TCEU_NLBL ===',  tps[_ENV.types.tceu_nlbl])

    tpl = sub(tpl, '=== LABELS ===', _LBLS.code)
    tpl = sub(tpl, '=== HOST ===',   _CODE.host)
    tpl = sub(tpl, '=== CODE ===',   _AST.root.code)

    -- LBL2FIN
    if _PROPS.has_fins then
        local t = {}
        for _, lbl in ipairs(_LBLS.list) do
            t[#t+1] = (string.find(lbl.id,'__fin') and 1) or 0
        end
        tpl = sub(tpl, '=== LBL2FIN ===', table.concat(t,','))
    end

    -- EVENTS
    local str = ''
    local t = {}
    local outs = 0
    for _, evt in ipairs(_ENV.evts) do
        if evt.input then
            str = str..'#define IN_'..evt.id..' '..evt.n..'\n'
        elseif evt.output then
            str = str..'#define OUT_'..evt.id..' '..outs..'\n'
            outs = outs + 1
        end
    end
    str = str..'#define OUT_n '..outs..'\n'

    -- FUNCTIONS called
    for id in pairs(_ENV.calls) do
        if id ~= '$anon' then
            str = str..'#define FUNC'..id..'\n'
        end
    end

    -- DEFINES
    if _PROPS.has_exts then
        str = str .. '#define CEU_EXTS\n'
    end
    if _PROPS.has_wclocks then
        str = str .. '#define CEU_WCLOCKS\n'
    end
    if _PROPS.has_asyncs then
        str = str .. '#define CEU_ASYNCS\n'
    end
    if _PROPS.has_emits then
        str = str .. '#define CEU_STACK\n'
    end
    if _PROPS.has_pses then
        str = str .. '#define CEU_PSES\n'
    end
    if _PROPS.has_fins then
        str = str .. '#define CEU_FINS\n'
    end

    -- TODO: goto _OPTS
    str = str .. '#define CEU_DEBUG\n'
    str = str .. '#define CEU_TREE\n'
    str = str .. '#define CEU_TREE_CHK\n'

    if _OPTS.defs_file then
        local f = io.open(_OPTS.defs_file,'w')
        f:write(str)
        f:close()
        tpl = sub(tpl, '=== DEFS ===',
                       '#include "'.. _OPTS.defs_file ..'"')
    else
        tpl = sub(tpl, '=== DEFS ===', str)
    end
end

if _OPTS.verbose or true then
    local T = {
        mem  = _MAIN.mem.max,
        trks = _AST.root.ns.tracks,
        lsts = _AST.root.ns.awaits,
        evts = #_ENV.evts,
        lbls = #_LBLS.list,

        exts    = _PROPS.has_exts,
        wclocks = _PROPS.has_wclocks,
        asyncs  = _PROPS.has_asyncs,
        emits   = _PROPS.has_emits,

        tree     = true,    -- TODO: goto _OPTS
        tree_chk = true,    -- TODO: goto _OPTS
    }
    local t = {}
    for k, v in pairs(T) do
        if v == true then
            t[#t+1] = k
        elseif v then
            t[#t+1] = k..'='..v
        end
    end
    table.sort(t)
    DBG('[ '..table.concat(t,' | ')..' ]')
end

-- OUTPUT
local out
if _OPTS.output == '-' then
    out = io.stdout
else
    out = assert(io.open(_OPTS.output,'w'))
end
out:write(tpl)
