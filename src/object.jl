module Internals
export object, AbstractObject, Object, Undef, hasprops, propsmatch, typematch, drop, getprototypes, property_type_assembler, getpropertytypes
export Prop, R, isassigned, getreftype, StaticStorage, MutableStorage, ProtoType, propsmutable, dynamicmatch, DynamicObject, DynamicStorage, Method

"""```
    Undef(::Type{T}) where T
```
Signals that an uninitialized reference to an object of type `T` should be created.

Example:
```
    x = object(a=Undef(Number))
    x.a = 5
    x.a = 3.14
```"""
struct Undef{T} end # type for describing uninitialized values
Undef(::Type{T}) where T = Undef{T}()
Undef() = Undef{Any}()

"""```
    Prop{n::Symbol,T<:Type}
    Prop{:a, Int}
```
A type for describing property types.
"""
abstract type Prop{n,T} end

"""```
    property_type_assembler(nTs::NamedTuple)
```
From a `NamedTuple` of types such as `(a=String, b=Number)`, construct a property `Union`.

Example:
```
    my_obj isa Object{<:Any, <:Any, >:property_type_assembler((a=String, b=Number))}
```"""
property_type_assembler(nTs::NamedTuple) = Union{(Prop{n,>:T} for (n,T) ∈ zip(keys(nTs), values(nTs)))...}
property_type_assembler(; kw...) = property_type_assembler(NamedTuple(kw))

"""```
    R(x::X) == R{X}(x)
    R{X}()  == R(Undef{X})
    R()     == R{Any}()
```
Construct a reference to `obj`. Behaves like `Core.Ref`, but has type-specialized behaviors specific to the `Object` type."""
mutable struct R{X} # my own `Ref` type (to disambiguate from Base `Ref` type & offer better behaviors)
    x::X
    R()             = new{Any}() # ideally Core.Ref should have this too
    R{X}()  where X = new{X}()
    R(x::X) where X = new{X}(x)
    R{X}(x) where X = new{X}(x)
    R(::Undef{X}) where X = new{X}()
    R{Undef{X}}() where X = new{X}()
    R{Undef{X}}(x) where X = new{X}()
end
Base.getindex(r::R) = r.x
Base.setindex!(r::R, x) = (r.x = x)
Base.:(==)(a::R{T1}, b::R{T2}) where {T1,T2} = isassigned(a) && isassigned(b) && a[] == b[] || (!isassigned(a) && !isassigned(b) && T1 == T2)
isassigned(r::R) = isdefined(r, :x)
"""```
    getreftype(r::R{T})
```
Gets the type `T` of object that is pointed to by the reference `r`."""
getreftype(::R{T}) where T = T
Base.copy(r::R{T}) where T = isassigned(r) ? R{T}(r[]) : R{T}()

"""```
    make_mutable(v)
```
Internal utility."""
make_mutable(v::T) where T = R{T}(v)
make_mutable(v::R{T}) where T = v
make_mutable(::Undef{T}) where T = R{T}()
make_mutable(T, v) = R{T}(v)
make_mutable(T, v::Undef{Tv}) where Tv = R{Tv}()

"""```
    equiv(x, y) = x===y
```
Tests equivalence.
```
    equiv(y)
```
Curried variant; call equiv(y)(x).

Example:
```
    filter(equiv(y), xs)
```"""
equiv(x,y) = x===y
equiv(y) = Base.Fix2(equiv, y)

const StaticStorage = NamedTuple
const MutableStorage = NamedTuple{<:Any,<:NTuple{N,R} where N}
const ProtoType = Tuple

Base.show(io::IO, mut::MutableStorage) = begin # necessary because of R type and Undef values
    itr = zip(keys(mut), map(getreftype, values(mut)), map(v->isassigned(v) ? v[] : "#undef", values(mut)))
    itr = (" $k"*(typeof(v) ≠ T ? "::$T" : "")*" = $v," for (k, T, v) ∈ itr)
    print(io, "(;" * join(itr)[1:end-1] * ")")
end
Base.copy(ms::MutableStorage) = typeof(ms)(map(copy, ms))

struct DynamicStorage{T} 
    d::Dict{Symbol,T} 
    DynamicStorage{T}(d::Dict{Symbol, T}) where T = new{T}(d)
end
DynamicStorage(d::DynamicStorage) = d
DynamicStorage{T}(d) where T = DynamicStorage{T}(Dict{Symbol,T}(d))
DynamicStorage{T}(; kwargs...) where T = DynamicStorage{T}(NamedTuple(kwargs))
DynamicStorage(d) = DynamicStorage{Any}(d)
DynamicStorage(; kwargs...) = DynamicStorage(NamedTuple(kwargs))
DynamicStorage(p::Pair...) = DynamicStorage(; p...)
Base.getindex(d::DynamicStorage, k::Symbol) = d.d[k]
Base.setindex(d::DynamicStorage, x, k::Symbol) = (d.d[k] = x;)
Base.keys(d::DynamicStorage) = keys(d.d)
Base.values(d::DynamicStorage) = values(d.d)
Base.copy(d::DynamicStorage) = typeof(d)(copy(d.d))
Base.merge(d::DynamicStorage) = d
Base.merge(dl::DynamicStorage{DL}, dr::DynamicStorage{DR}, d...) where {DL,DR} = merge(DynamicStorage{typejoin(DL,DR)}(merge(dl.d, dr.d)), d...)
#Base.show(io::IO, d::DynamicStorage{T}) where T = print(io, "Objects.DynamicStorage{$T}(" * join(("$k = $v" for (k,v) ∈ zip(keys(d.d), values(d.d))), ", ") * ")")

abstract type AbstractObject{TypeTag, D, PT, PTM} end
const DynamicObject = AbstractObject{<:Any, <:DynamicStorage}

DynamicStorage{T}(d::Union{NamedTuple, AbstractObject, Dict}) where T = DynamicStorage{T}(Dict{Symbol, T}((Symbol(k),v) for (k,v) ∈ zip(keys(d), values(d))))


"""
See also `object`, which is a more convenient `Object` builder for simple `Object`s.
```
    o = Object{[TypeTag]}([objs::Object...] ; [dynamic,] [prototype,] [static,] [mutable])
```
Construct an `Object` with optional type annotation `TypeTag`.

`dynamic` can be any object which is ideally (but not necessarily) accessible by index. To access index `i` of `dynamic`, use `o[i]`. To access `dynamic` itself, use `o[]`.

`prototype` can be any object, or a `Tuple` of objects, that the `Object` will inherit properties from. If a property is not present in the object's own properties, then a search is made of its prototype(s).

`static` and `mutable` can be any object which can be converted to a `NamedTuple`. Static properties are immutable and require no allocations, while mutable properties create a reference and an allocation.

Whenever conflicts arise, they are resolved by merging in a left-to-right fashion. For example, if there are two prototypes `(pa, pb)` that both have the same property, then it is taken from `pb`. Likewise, an object's own static properties override its prototype-inherited properties, and mutable properties override static.

Examples:
```
    o1 = Object(static=(a=1, b=2), mutable=(b=3, c=4))
    (; a, b, c) = o1
    (a, b, c)   # (1, 3, 4) (mutable .b overrides static .b)
    o1.b = 0    # ok (mutable property)
    o1.a = 1    # error (static property)

    o2 = Object(static=(a=0,))

    o3 = Object(dynamic=[1,2,3], prototype=(o1,o2), mutable=(c=5,))
    o3[2]       # 2 (index read)
    o3[2] = 6   # ok (index write)
    o3[]        # [1, 6, 3]
    o3.c        # 5 (own property overrides prototype)
    o3.a        # 0 (o2 dominates o1)
    o3.b        # 0 (prototype access)
    o3.b = 2    # error (cannot overwrite prototype)
    o1.b = 1    # ok 
    o3.b        # 1 (changes to prototype propagate to inheritor)
```
Objects can also be merged, in left-to-right fashion.
```
    o1 = Object(static=(a=1, b=2), prototype=(x=1,y=2))
    o2 = Object(mutable=(b=3, c=4), prototype=(y=3,z=4))
    o3 = Object(o1, o2)
    (; o3...)   # (x = 1, y = 3, z = 4, a = 1, b = 3, c = 4)
```
Additionally, every `Object` is callable, serving as a template to construct a replica of itself. Any unspecified properties will default to the values in the template.
```
    template = Object(static=(a=1,), mutable=(b=2,))
    template()            # independent copy
    template()==template  # true
    template()===template # false
    template(a=5, b=6)    # ok
    template(c=2)         # error
```
The type annotation `TypeTag` is optional, and can be used for dispatch (as a form of self-type-identification for any method which respects it). The interface of an `Object` can be tested using `hasprops`, `propsmatch`, or `typematch`. 

See also: `object`, `Undef`, `hasprops`, `propsmatch`, `typematch`."""
struct Object{TypeTag, D, PT, PTM, P<:ProtoType, S<:StaticStorage, M<:MutableStorage} <: AbstractObject{TypeTag, D, PT, PTM}
    dynamic::D
    prototype::P 
    static::S    
    mutable::M   

    Object{TypeTag}(dynamic::D, prototype::P, static::S, mutable::M) where 
    {TypeTag, D<:Union{Nothing,DynamicStorage}, P<:ProtoType, S<:StaticStorage, M<:MutableStorage} = begin
        # hygiene: if mutable has properties in static, or if dynamic has properties in either, throw error
        for k ∈ keys(static) @assert k∉keys(mutable) "Repeated property `$k` in both static and mutable collections disallowed" end
        !isnothing(dynamic) && for k ∈ keys(dynamic) @assert k∉keys(mutable) && k∉keys(static) "Repeated property `$k` in dynamic collection disallowed" end
        # hygiene: if there are any repeated prototypes, throw error
        reduce((acc,x)->(@assert(!any(equiv(x), acc), "Invalid repeated prototype `$x`"); (acc...,x)), prototype; init=())            
        # build out property type information
        sTypes = getpropertytypes(static)
        mTypes = getpropertytypes(mutable)
        protoTypes = merge((;), map(getpropertytypes, prototype)...)
        propTypes = (; protoTypes..., sTypes..., mTypes...)
        new{TypeTag, D, property_type_assembler(propTypes), property_type_assembler(mTypes), P, S, M}(dynamic, prototype, static, mutable) 
    end #𝓏𝓇
end

"""```
    getpropertytypes(o)
```
Retrieves the property names and types of an object `o` and returns them in a `NamedTuple`. Note that the properties must be fields of the object's type. When called on an `Object`, returns *only* non-dynamic property types."""
getpropertytypes(o::T) where T = NamedTuple{fieldnames(T)}(T.types) 

#let pns=Tuple(propertynames(o)), pts=NamedTuple{fieldnames(T)}(T.types)
#    NamedTuple{pns}(map(Base.Fix1(getfield, pts), pns))
#end
getpropertytypes(m::MutableStorage) = NamedTuple{keys(m)}(map(getreftype, values(m)))
getpropertytypes(o::Object) = begin
    static, mutable = getfield(o, :static), getfield(o, :mutable)
    s = getpropertytypes(static)
    m = getpropertytypes(mutable)
    protoTypes = merge((;), map(getpropertytypes, getfield(o, :prototype))...)
    merge(protoTypes, s, m)
end

"""```
    namedtuple(o)
```
Returns a `NamedTuple` of the properties and values of object `o`, with property types as defined by the object type instead of each property's concrete type."""
namedtuple(o::NamedTuple) = o
namedtuple(o::T) where T = let pns = Tuple(propertynames(o)), pts=getpropertytypes(o)
    #NamedTuple{fieldnames(T), Tuple{T.types...}}(map(Base.Fix1(getfield, o), fieldnames(T)))
    NamedTuple{pns, Tuple{map(Base.Fix1(getfield, pts), pns)...}}(map(Base.Fix1(getproperty, o), pns))
end

"""```
    hasprops(o::AbstractObject)
```
Construct a type which tests for `Object`s that have *at least* the properties of `o`.

Example:
```
    o1 = object(a=1)
    o2 = object((a=2, b=3))
    o2 isa hasprops(o1) # true
    o1 isa hasprops(o2) # false
```"""
hasprops(::AbstractObject{<:Any,<:Any,PT}) where PT = AbstractObject{<:Any,<:Any,>:PT}
"    propsmutable(o::AbstractObject)\n\nConstruct a type which tests for `Object`s that have *at least* the mutable properties of `o`.\n\nSee also: hasprops"
propsmutable(::AbstractObject{<:Any,<:Any,<:Any,PTM}) where PTM = AbstractObject{<:Any,<:Any,<:Any,>:PTM}
"""```
    propsmatch(o::AbstractObject)
```
Construct a type which tests for `Object`s that have *at least* the properties *and* mutable properties of `o`.

Example:
```
    o1 = object(a=1)        # mutable
    o2 = object(a=1, b=2)   # mutable
    o3 = object(o2)         # static
    o2 isa propsmatch(o1)   # true
    o3 isa propsmatch(o1)   # false
```
See also: `hasprops`, `propsmutable`, `typematch`
"""
propsmatch(::AbstractObject{<:Any,<:Any,PT,PTM}) where {PT,PTM} = AbstractObject{<:Any,<:Any,>:PT,>:PTM} 
dynamicmatch(::AbstractObject{<:Any,D}) where {D} = AbstractObject{<:Any,<:D}
"""```
    typematch(o::AbstractObject)
```
Construct a type which tests for `Object`s that satisfy `propsmatch` and with satisfying `dynamic` type and `TypeTag`."""
typematch(::AbstractObject{TypeTag,D,PT,PTM}) where {TypeTag,D,PT,PTM} = 
    isbits(TypeTag) ? AbstractObject{TypeTag,<:D,>:PT,>:PTM} : AbstractObject{<:TypeTag,<:D,>:PT,>:PTM}

"_prop_hygiene(dynamic, static, mutable) : assert correct types, copy references, and eliminate overlap."
_prop_hygiene(d::Nothing, static, mutable) = (d, _stat_mut_hygiene(static, mutable)...)
_prop_hygiene(dynamic, static, mutable) = begin
    s, m = _stat_mut_hygiene(static, mutable)
    d = let dyn = DynamicStorage(dynamic)
        dkeys = Tuple(filter(k->k ∉ keys(m) && k ∉ keys(s), keys(dyn)))
        DynamicStorage(map(k->k=>dyn[k], dkeys))
    end
    (d, s, m)
end
_stat_mut_hygiene(static, mutable) = begin
    s, m = NamedTuple(static), _mutable_hygiene(NamedTuple(mutable))
    skeys = filter(!Base.Fix2(∈, keys(m)), keys(s))
    s = NamedTuple{skeys, Tuple{map(Base.Fix1(getfield, getpropertytypes(s)), skeys)...}}(map(Base.Fix1(getfield, s), skeys))
    (s, m)
end
# This would've been preferred but it complains about the lambdas.
#= @generated _prop_hygiene(dynamic::D, static, mutable) where D = begin
    if D <: Nothing;  dynhygiene = :dynamic
    else dynhygiene = quote
        let dyn = DynamicStorage(dynamic)
            dkeys = Tuple(filter(k->k ∉ keys(m) && k ∉ keys(s), keys(dyn)))
            DynamicStorage(map(k->k=>dyn[k], dkeys))
        end
    end end
    quote
        s, m = NamedTuple(static), _mutable_hygiene(NamedTuple(mutable))
        skeys = filter(!Base.Fix2(∈, keys(m)), keys(s))
        s = NamedTuple{skeys, Tuple{map(Base.Fix1(getfield, getpropertytypes(s)), skeys)...}}(map(Base.Fix1(getfield, s), skeys))
        d = $dynhygiene 
        (d, s, m)
    end
end =#
_mutable_hygiene(m::MutableStorage) = NamedTuple{keys(m)}(map(copy, values(m)))
_mutable_hygiene(m::NamedTuple) = let pt=getpropertytypes(m); NamedTuple{keys(m)}(map(k->R{pt[k]}(m[k]), keys(m))) end

"_prototype_hygiene(proto) : ensure prototype is a tuple, and eliminate any copies of the same prototype."
_prototype_hygiene(p) = (p,)
_prototype_hygiene(p::ProtoType) = foldr((x,acc)->any(equiv(x), acc) ? acc : (x, acc...), p; init=())

_object_hygiene(dynamic, prototype, static, mutable) = begin
    d, s, m = _prop_hygiene(dynamic, static, mutable)
    p = _prototype_hygiene(prototype)
    (d, p, s, m)
end

"_merge_object(o1, o2) : merge o1 and o2 rightward, merging their `prototype`, `static`, and `mutable` collections. Choose `o2`'s `TypeTag` and `dynamic`."
_merge_objects(objl::Object{TypeTagL}, objr::Object{TypeTagR}) where {TypeTagL,TypeTagR} = begin
    da, db = getfield(objl, :dynamic),      getfield(objr, :dynamic)
    sa, sb = getfield(objl, :static),       getfield(objr, :static)
    ma, mb = getfield(objl, :mutable),      getfield(objr, :mutable)
    pa, pb = getfield(objl, :prototype),    getfield(objr, :prototype)
    d           = isnothing(objl) && isnothing(objr) ? nothing : 
                  isnothing(objl) ? objr :
                  isnothing(objr) ? objl :
                  merge(da, db)
    prototype   = _prototype_hygiene((pa..., pb...))
    s           = (; sa..., sb...)
    m           = (; ma..., mb...)
    dynamic, static, mutable = _prop_hygiene(d, s, m)
    Object{TypeTagR}(dynamic, prototype, static, mutable)
end

Object(obj::Object) = obj
@generated Object(objs...; kwargs...) = begin
    # extract TypeTag from last item. See comment below for why I had to make this a @generated function.
    length(objs) > 0 && objs[end] <: AbstractObject && return :( Object{$(objs[end].parameters[1])}(objs...; kwargs...) )
    :( Object{Any}(objs...; kwargs...) )
end
#Object(objs..., objr::Object{TypeTag}; kwargs...) where TypeTag = Object{TypeTag}(objs..., objr; kwargs...) doesn't work yet

Object{TypeTag}(obj::Object{TypeTag}) where TypeTag = obj
Object{TypeTag}(obj::Object) where TypeTag = Object{TypeTag}(map(copy ∘ Base.Fix1(getfield, obj), (:dynamic, :prototype, :static, :mutable))...)
Object{TypeTag}(objs...; dynamic=nothing, prototype=(), static=(;), mutable=(;)) where TypeTag =
    Object{TypeTag}(objs..., Object{TypeTag}(_object_hygiene(dynamic, prototype, static, mutable)...))


Object{TypeTag}(obj, objs...) where TypeTag = Object{TypeTag}(Object(obj), objs...)
Object{TypeTag}(objl::Object, objr, objs...) where TypeTag = Object{TypeTag}(objl, Object(objr), objs...)
Object{TypeTag}(objl::Object, objr::Object, objs...) where TypeTag = Object{TypeTag}(_merge_objects(objl, objr), objs...)

Object{TypeTag}(d::AbstractDict{Symbol}) where TypeTag = 
    Object{TypeTag}(mutable = NamedTuple{(keys(d)...,)}(map(v->v isa AbstractDict{Symbol} ? Object{TypeTag}(v) : v, values(d))))
Object{TypeTag}(o) where TypeTag = ismutable(o) ? Object{TypeTag}(mutable=namedtuple(o)) : Object{TypeTag}(static=namedtuple(o))

Base.getindex(::Type{Object}) = let
    obj(d::AbstractDict{Symbol}) = object[DynamicStorage(map((k,v)->v isa AbstractDict{Symbol} ? k=>obj(v) : k=>v, keys(d), values(d))...)]()
    
end

"Template constructor"
(o::Object{TypeTag})(; kwargs...) where {TypeTag} = begin
    for k ∈ keys(kwargs)  @assert k ∈ propertynames(o, true) "Argument `$k` not in template"  end
    static = let s=getfield(o, :static); NamedTuple{keys(s)}(map(k->k∈keys(kwargs) ? kwargs[k] : s[k], keys(s))) end
    mutable = let m=getfield(o, :mutable), mT = getpropertytypes(m)
        NamedTuple{keys(m)}(map(keys(m)) do k
            k ∈ keys(kwargs) && return make_mutable(mT[k], kwargs[k])
            isassigned(m[k]) && return R{getreftype(m[k])}(m[k][])
            R{getreftype(m[k])}()
        end)
    end
    cpy(o) = copy(o); cpy(o::Nothing) = nothing
    Object{TypeTag}(cpy(o[]), getfield(o, :prototype), static, mutable) #𝓏𝓇
end
(o::Object)(args...) = o(; merge((;), args)...)


"""```
    o = object((p1, p2), s1, s2; m3..., m4...)
    o = object[]((p1, p2), s1, s2; m3..., m4...)
```
Convenient `Object` builder. Prototypes `p1` and `p2` become the new object's prototypes, collections `s1` and `s2` become static properties of `o`, and `m3` and `m4` become mutable properties.

Note that even if any of `s1` ... `m4` are `Object`s with their own mutability settings, `o` splats them out and applies its own mutability settings.

Introducing the `[]` indicates that `o` will accept dynamic properties.

Example:
```
    o1 = object(a=1, b=2)    # fully mutable
    o2 = object((a=1, b=2))  # fully static
    o3 = object((a=1,), b=2) # part static, part mutable
    o4 = object(o3)          # fully static
    o5 = object(; o3...)     # fully mutable
    o6 = object[(a=1,)](b=2) # :a dynamic, :b mutable
```

"""
object(stat=(;); var"#~#dyno#~#"=nothing, var"#~#proto#~#"=(), kwargs...) = 
    Object(dynamic=var"#~#dyno#~#", prototype=var"#~#proto#~#", static=(; stat...), mutable=kwargs)
object(proto::Tuple, args...; kwargs...) = object(args...; var"#~#proto#~#"=_prototype_hygiene(proto), kwargs...)
object(arg1, arg2, args...; kwargs...) = object((; arg1..., arg2...), args...; kwargs...)

struct DynamicBuilder{D} i::D end
Base.getindex(::typeof(object)) = DynamicBuilder(DynamicStorage())
Base.getindex(::typeof(object), d) = DynamicBuilder(DynamicStorage(d))
Base.getindex(::typeof(object), d::Union{AbstractObject, NamedTuple}) = DynamicBuilder(DynamicStorage(; d...))
Base.getindex(::typeof(object), p::Pair...) = DynamicBuilder(DynamicStorage(; p...))
Base.getindex(::typeof(object), p::NTuple{N,Pair} where N) = DynamicBuilder(DynamicStorage(; p...))
(ib::DynamicBuilder)(args...; kwargs...) = object(args...; kwargs..., var"#~#dyno#~#"=ib.i)

struct Method{F,X<:AbstractObject} f::F; x::X end
(f::Method)(args...; kwargs...) = f.f(f.x, args...; kwargs...)
Base.show(io::IO, f::Method{F}) where {F} = 
    print(io, "$(f.f)(::AbstractObject, _...; _...)")

# Here's the magic (or is it?)
_getpropnested(o::AbstractObject, s::Symbol) = getproperty(o, s, true)
_getpropnested(o, s::Symbol) = getfield(o, s)
_getpropnamesnested(o::AbstractObject) = keys(getpropertytypes(o)) # ignores dynamic properties
_getpropnamesnested(o) = propertynames(o)
Base.getproperty(o::AbstractObject, s::Symbol, nested=false) = begin
    val = # try own nondynamic properties
        if s ∈ keys(getfield(o, :mutable))  getfield(getfield(o, :mutable), s)[]
        elseif s ∈ keys(getfield(o, :static))  getfield(getfield(o, :static), s)
        else # try prototypes' nondynamic properties
            i = findlast(p -> s ∈ _getpropnamesnested(p), getfield(o, :prototype))
            if !isnothing(i)  _getpropnested(getfield(o, :prototype)[i], s)
            elseif o isa DynamicObject # try dynamic properties if o is dynamic
                if s ∈ keys(o[].d)  getindex(o[].d, s)
                else # try prototypes' dynamic properties 
                    j = findlast(p -> s ∈ propertynames(p), getfield(o, :prototype))
                    if !isnothing(j)  getproperty(getfield(o, :prototype)[j], s)
                    else  throw("Property `$s` not found")
                    end
                end
            else  throw("Property `$s` not found")
            end
        end
    val isa Function && !nested && return Method(val, o)
    val
end #𝓏𝓇
Base.setproperty!(o::AbstractObject, s::Symbol, x) = begin
    if s ∈ propertynames(getfield(o, :static))  throw("Cannot set static property `$s`")
    elseif s ∈ propertynames(getfield(o, :mutable))  getproperty(getfield(o, :mutable), s)[] = x
    elseif any(p -> s ∈ _getpropnamesnested(p), getfield(o, :prototype))  throw("Cannot set prototype's property `$s`")
    elseif o isa DynamicObject  setindex!(o[].d, x, s)
    else throw("Property `$s` not found") end
    x
end
Base.propertynames(o::AbstractObject) = keys(getpropertytypes(o))
Base.propertynames(o::DynamicObject) = Tuple(keys(merge(map(NamedTuple, getfield(o, :prototype))..., NamedTuple(o))))
InnateNamedTuple(o::AbstractObject) = let pts=getpropertytypes(o); NamedTuple{keys(pts), Tuple{values(pts)...}}(map(Base.Fix1(getproperty,o), keys(pts))) end
Base.NamedTuple(o::AbstractObject) = InnateNamedTuple(o)
Base.NamedTuple(o::DynamicObject) = merge(NamedTuple(o[].d), InnateNamedTuple(o))
Base.merge(o::AbstractObject) = o
Base.merge(ol::AbstractObject, or::AbstractObject{TypeTag}, args...) where TypeTag = 
    merge(getfield(parentmodule(typeof(or)), nameof(typeof(or))){TypeTag}(ol, or), args...)
Base.merge(nt::NamedTuple, o::AbstractObject, args...) = merge(merge(nt, NamedTuple(o)), args...)
Base.merge(nt::NamedTuple, o::DynamicObject, args...) = merge(merge(nt, NamedTuple(o[].d), NamedTuple(o)), args...)
Base.getindex(o::AbstractObject) = getfield(o, :dynamic)

Base.iterate(o::AbstractObject, n) = nothing
Base.iterate(o::AbstractObject) = (o, nothing)
Base.length(o::AbstractObject) = 1

Base.keys(o::AbstractObject) = propertynames(o)
Base.values(o::AbstractObject) = map(Base.Fix1(getproperty, o), propertynames(o))

Base.getindex(o::AbstractObject, n) = getproperty(o, Symbol(n))
Base.setindex!(o::AbstractObject, x, n) = setproperty!(o, Symbol(n), x)
Base.haskey(o::AbstractObject, n) = Symbol(n) ∈ propertynames(o)
Base.get(o::AbstractObject, n, default) = haskey(o, n) ? o[n] : default
Base.get(f::Function, o::AbstractObject, n) = haskey(o, n) ? o[n] : f()
Base.get!(o::AbstractObject, n, default) = haskey(o, n) ? o[n] : (o[n] = default)
Base.get!(f::Function, o::AbstractObject, n) = haskey(o, n) ? o[n] : (o[n] = f())
Base.getkey(o::AbstractObject, n, default) = haskey(o, n) ? n : default
# Base.delete!
# Base.pop!
Base.pairs(o::AbstractObject) = (k=>v for (k,v) ∈ zip(keys(o), values(o)))
# Base.mergewith
Base.keytype(::AbstractObject) = Symbol



Base.:(==)(a::Object, b::Object) = 
    typeof(a) == typeof(b)  && a[] == b[] &&
    getfield(a, :static)    == getfield(b, :static) &&
    getfield(a, :mutable)   == getfield(b, :mutable) && 
    getfield(a, :prototype) == getfield(b, :prototype)
Base.copy(o::AbstractObject) = o()

Base.show(io::IO, o::Object{TypeTag}) where TypeTag = begin
    istr = replace("$(isnothing(o[]) ? nothing : NamedTuple(o[].d))", "\n" => "\n    ")
    s = getfield(o, :static)
    sstr = isempty(s) ? "(;)" : replace("$s", "\n" => "\n    ")
    mstr = replace("$(getfield(o, :mutable))", "\n" => "\n    ")
    pstr = replace("$(getfield(o, :prototype))", "\n" => "\n    ")
    print(io, "Object{$TypeTag}(\n    dynamic   = $istr,\n    prototype = $pstr,\n    static    = $sstr,\n    mutable   = $mstr\n)")
end

drop(o::Object{TypeTag}, props::Val{P}) where {TypeTag,P} = begin
    args = P isa Symbol ? (P,) : P
    @assert args isa NTuple{N,Symbol} where N "Cannot drop non-Symbol identifiers"
    i = getfield(o, :dynamic)
    s = getfield(o, :static)
    m = getfield(o, :mutable)
    p = getfield(o, :prototype)
    @assert all(k->k∈keys(m) || k∈keys(s), args) "Cannot drop property"

    ks = filter(k->k∉args, keys(s))
    km = filter(k->k∉args, keys(m))
    Object{TypeTag}(
        dynamic = i, 
        static = let pts=getpropertytypes(s); NamedTuple{ks, Tuple{map(Base.Fix1(getindex, pts), ks)...}}(map(Base.Fix1(getindex, s), ks)) end,
        mutable = let pts=getpropertytypes(m); NamedTuple{km, Tuple{map(k->R{pts[k]}, km)...}}(map(Base.Fix1(getindex, m), km)) end, 
        prototype=p
    )
end
getprototypes(o::AbstractObject) = getfield(o, :prototype)
staticpropertynames(o::AbstractObject) = propertynames(getfield(o, :static))
mutablepropertynames(o::AbstractObject) = propertynames(getfield(o, :mutable))
ownpropertynames(o::AbstractObject) = (staticpropertynames(o)..., mutablepropertynames(o)...)




proptypes(o) = begin end
proptypes(o::Object) = begin end

#Create new function for dynamic type checks

#proptypes(o::Object) -> returns union of all property types, including those of dynamic objects
#e.g. (if proptypes(my_obj) <: proptypes(template_type))
#returns Prop{>:Union{Prop{:a,Int}, Prop{:b, Number}}} etc.
    


#struct ObjectViewer{TypeTag, D, P, PTM, } <: AbstractObject{TypeTag, D, PT, PTM}
#
#end
#
#function objectview(; kwargs...)
#
#end
#
#macro objectview(ex...)
#
#end

end


# Object-to-Dictionary conversions
#Base.convert(T::Type{<:AbstractDict}, obj::Object) = begin
#    store = getfield(obj, :store); props = _getprops(store)
#    isnothing(_getproto(store)) ? T(k=>v isa Object ? convert(T, v) : v for (k,v) ∈ zip(keys(props), values(props))) :
#    merge(convert(T, _getproto(store)), T(k=>v isa Object ? convert(T, v) : v for (k,v) ∈ zip(keys(props), values(props))))
#end

