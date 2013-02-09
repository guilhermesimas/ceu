_LBLS = {
    list = {},      -- { [lbl]={}, [i]=lbl }
    code_enum = '',
    code_fins = '',
}

function new (lbl)
    lbl.id = lbl[1] .. (lbl[2] and '' or '_'..CLS().id..'_'..#_LBLS.list)
    lbl.id = string.gsub(lbl.id, '%*','_')
    lbl.id = string.gsub(lbl.id, '%.','_')
    lbl.id = string.gsub(lbl.id, '%$','_')
    _LBLS.list[lbl] = true
    lbl.n = #_LBLS.list                   -- starts from 0
    _LBLS.list[#_LBLS.list+1] = lbl

    for n in _AST.iter() do
        if n.lbls_all then
            n.lbls_all[lbl] = true
        end
    end

    return lbl
end

F = {
    Node_pre = function (me)
        me.lbls = { #_LBLS.list }
    end,
    Node = function (me)
        me.lbls[2] = #_LBLS.list-1
    end,

    Root_pre = function (me)
        --new{'CEU_INACTIVE', true}
    end,
    Root = function (me)
        _ENV.c.tceu_nlbl.len = _TP.n2bytes(#_LBLS.list)

        -- enum of labels
        for i, lbl in ipairs(_LBLS.list) do
            _LBLS.code_enum = _LBLS.code_enum..'    '
                                ..lbl.id..' = '..lbl.n..',\n'
        end

        -- labels which are finalizers
        local t = {}
        for _, lbl in ipairs(_LBLS.list) do
            t[#t+1] = string.find(lbl.id,'__fin') and assert(lbl.depth) or 0
        end
        _LBLS.code_fins = table.concat(t,',')
    end,

    SetNew = function (me)
        me.lbl_cnt = new{'New_cont'}
    end,
    Block = function (me)
        local blk = unpack(me)

        if me.fins then
            me.lbl_fin     = new{'Block__fin', depth=me.depth}
            me.lbl_fin_cnt = new{'Block_fin_cnt'}
            for _, fin in ipairs(me.fins) do
                fin.lbl_true  = new{'Finalize_true'}
                fin.lbl_false = new{'Finalize_false'}
            end
        end
    end,

    Dcl_cls = function (me)
        me.lbl = new{'Class_'..me.id, true}
        if me.has_news then
            me.lbl_free = new{'Class__fin_'..me.id, depth=me.depth}
        end
    end,

    Dcl_var = function (me)
        local var = me.var
        if var.cls then
            var.lbl_cnt = new{'Dcl_cnt'}
        elseif var.arr and _ENV.clss[_TP.deref(var.tp)] then
            var.lbl_cnt = {}
            for i=1, var.arr do
                var.lbl_cnt[#var.lbl_cnt+1] = new{'Dcl_cnt'}
            end
        elseif _ENV.clss[_TP.raw(var.tp)] or var.tp=='void*' then
            var.lbl_cnt = new{'Dcl_cnt'}    -- used by `new´
        end
    end,

    SetBlock_pre = function (me)
        me.lbl_out = new{'Set_out',  prio=me.depth}
    end,

    _Par_pre = function (me)
        me.lbls_in  = {}
        for i, sub in ipairs(me) do
            me.lbls_in[i] = new{me.tag..'_sub_'..i}
        end
    end,
    ParEver_pre = function (me)
        F._Par_pre(me)
        me.lbl_out = new{'ParEver_out'}
    end,
    ParOr_pre = function (me)
        F._Par_pre(me)
        me.lbl_out = new{'ParOr_out',  prio=me.depth}
    end,
    ParAnd_pre = function (me)
        F._Par_pre(me)
        me.lbl_tst = new{'ParAnd_chk'}
        me.lbl_out = new{'ParAnd_out'}
    end,

    If = function (me)
        local c, t, f = unpack(me)
        me.lbl_t = new{'True'}
        me.lbl_f = f and new{'False'}
        me.lbl_e = new{'EndIf'}
    end,

    Async = function (me)
        me.lbl = new{'Async'}
    end,

    Loop_pre = function (me)
        me.lbl_ini = new{'Loop_ini'}
        if me.has_break then
            me.lbl_out = new{'Loop_out',  prio=me.depth }
        end
    end,

    EmitExtS = function (me)
        me.lbl_cnt = new{'Async_cont'}
    end,
    EmitT = function (me)
        me.lbl_cnt = new{'Async_cont'}
    end,

    EmitInt = function (me)
        local int = unpack(me)
        me.lbl_cnt = new{'Emit_cnt_'..int.var.id}
    end,

    AwaitT = function (me)
        if me[1].tag == 'WCLOCKE' then
            me.lbl = new{'Awake_'..me[1][1][1]}
        else
            me.lbl = new{'Awake_'..me[1][1]}
        end
    end,
    AwaitExt = function (me)
        local e = unpack(me);
        me.lbl = new{'Awake_'..e.ext.id}
        local t = _AWAITS.t[e.ext]
        if t then
            t[#t+1] = me.lbl
        end
    end,
    AwaitInt = function (me)
        local int = unpack(me)
        me.lbl_awk = new{'Awake_'..int.var.id}
        local t = _AWAITS.t[int.var]
        if t then
            t[#t+1] = me.lbl_awk
        end
    end,
}

_AST.visit(F)