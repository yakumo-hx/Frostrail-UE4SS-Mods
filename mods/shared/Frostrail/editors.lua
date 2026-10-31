-- F8 controls belong to the panel's WidgetTree. Closing the panel drops the readers.
local settings=require("Frostrail.settings")
local json=require("Frostrail.json")
local M={}
function M.equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in pairs(a) do if not M.equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
function M.normalized(field,value)
    if field.type=="number" then return tonumber(value) end
    if field.type=="bool" then return value==true end
    if field.type=="color" then return tostring(value or ""):gsub("#",""):upper() end
    if field.type=="list" or field.type=="map" or field.type=="choice" then return value end
    return tostring(value==nil and "" or value)
end
function M.read(field,editor,language)
    if field.type=="bool" then return editor:IsChecked() end
    local text=editor:GetText():ToString()
    local label=settings.label(field.label,language)
    if field.type=="number" then
        local value=tonumber(text)
        assert(value and (not field.integer or value%1==0) and (not field.min or value>=field.min)
            and (not field.max or value<=field.max),label..(language=="en" and ": enter a valid number" or "：请输入有效数值"))
        return value
    end
    if field.type=="color" then
        local value=text:gsub("#",""):upper()
        assert(value:match("^%x%x%x%x%x%x$"),label..(language=="en" and ": enter six hex digits" or "：请输入六位颜色值"))
        return value
    end
    return text
end
function M.create(C,owner,field,value,default,language)
    local tree=owner.WidgetTree
    local function new(name) return C.new("/Script/UMG."..name,tree) end
    local owner_name=owner:GetFullName()
    local function active()
        return C.instance(owner,owner_name) and C.panel_state and C.panel_state.widget_name==owner_name
            and owner:IsInViewport()
    end
    if field.type=="list" or field.type=="map" then
        local body=new("VerticalBox")
        local entries={}
        local is_map=field.type=="map"
        local sample=type(default)=="table" and (is_map and select(2,next(default)) or default[1]) or nil
        local columns=field.columns or {}
        local function add(key,item)
            local line=new("HorizontalBox")
            local entry={readers={},original=item}
            entries[#entries+1]=entry
            if is_map then
                local control,read=M.create(C,owner,{type="string"},key,"",language)
                line:AddChildToHorizontalBox(control)
                entry.key=read
            end
            local function cell(column,current,fallback)
                local spec={}
                for k,v in pairs(column) do spec[k]=v end
                spec.type=settings.kind(spec,fallback)
                if fallback==nil and field.value_type then spec.type=field.value_type end
                local control,read=M.create(C,owner,spec,current,fallback,language)
                line:AddChildToHorizontalBox(control):SetSize({SizeRule=1,Value=1})
                entry.readers[#entry.readers+1]={key=column.key,read=read}
            end
            if #columns>0 then
                for _,column in ipairs(columns) do
                    cell(column,settings.get(item or {},column.key),settings.get(sample or {},column.key))
                end
            else cell(field,item,sample) end
            local remove=C.ui.button(C,owner,language=="en" and "Remove" or "删除",function()
                if not active() or entry.removed then return end
                entry.removed=true
                line:RemoveFromParent()
            end)
            line:AddChildToHorizontalBox(remove.widget)
            body:AddChildToVerticalBox(line)
        end
        if #columns>0 then
            local header=new("HorizontalBox")
            for _,column in ipairs(columns) do
                header:AddChildToHorizontalBox(C.ui.text(C,tree,settings.label(column.label,language),12))
                    :SetSize({SizeRule=1,Value=1})
            end
            body:AddChildToVerticalBox(header)
        end
        local iterate=is_map and pairs or ipairs
        for k,v in iterate(value or {}) do add(k,v) end
        local button=C.ui.button(C,owner,language=="en" and "Add" or "添加",function()
            if not active() then return end
            local initial=sample~=nil and json.decode(json.encode(sample)) or (field.value_type=="number" and 0 or "")
            add("",initial)
        end)
        body:AddChildToVerticalBox(button.widget)
        return body,function()
            local result={}
            for _,entry in ipairs(entries) do
                if not entry.removed then
                    local item
                    if #columns>0 then
                        item=type(entry.original)=="table" and json.decode(json.encode(entry.original)) or {}
                        for _,reader in ipairs(entry.readers) do settings.set(item,reader.key,reader.read()) end
                    else item=entry.readers[1].read() end
                    result[is_map and entry.key() or #result+1]=item
                end
            end
            return result
        end
    end
    if field.type=="choice" then
        local editor=new("ComboBoxString")
        local choices={}
        for _,option in ipairs(field.options) do
            local selected=option
            if type(option)=="table" then selected=option.value end
            local label=type(option)=="table" and settings.label(option.label,language) or tostring(option)
            editor:AddOption(label)
            choices[label]=selected
            if M.equal(selected,value) then editor:SetSelectedOption(label) end
        end
        return editor,function()
            local selected=editor:GetSelectedOption()
            local label=type(selected)=="string" and selected or selected:ToString()
            if choices[label]~=nil then return choices[label] end
            return value
        end
    end
    local editor
    if field.type=="bool" then
        editor=new("CheckBox")
        editor:SetIsChecked(value==true)
    else
        editor=new("EditableTextBox")
        editor.WidgetStyle.TextStyle.Font.Size=12
        editor.MinimumDesiredWidth=140
        editor:SetForegroundColor({R=0.025,G=0.04,B=0.055,A=1})
        editor:SetText(FText(tostring(value==nil and "" or value)))
    end
    return editor,function() return M.read(field,editor,language) end
end
return M
