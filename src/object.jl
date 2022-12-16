"""
    Object{[TypeTag]}([objs::Object...] ; [static=s,] [mutable=m,] [prototype=p])




    Object{[TypeTag]}([StorageType] [; kwargs...])

Create a structured `Object` with properties specified by keyword arguments `kwargs`. Object type can be specified by `StorageType`, and additional type parameters can be specified by `TypeTag`. Later properties override earlier ones.

Other iterable key=>value mappings, as from generators, dictionaries, named tuples, and other `Object`s, can be splatted into the keyword arguments as well.

`StorageType` can be `Static`, `Mutable`, or `Dynamic`, depending on performance needs. If not specified, default is `Mutable`.

`TypeTag` is optional and does not affect `Object` behavior, but can be used to leverage Julia's type inference engine for multiple method dispatch.

    Object{[TypeTag]}([StorageType,] props::AbstractDict)

Create an `Object` from a dictionary recursively.

    Object{[TypeTag]}([StorageType,] obj::Any)

Create an `Object` from an arbitrary composite type.

    Object{[TypeTag]}([StorageType,] obj::Object)

Convert an `Object` from one set of `StorageType` and `TypeTag` to another, keeping prototype. 

    (proto::Object)([; kwargs...])

Every `Object` is a constructor. Call on the object to use it as a template for creating a new object with the exact same property names and types.

    Object{[TypeTag]}([StorageType,] (proto::Object,) [; kwargs...])

Create a new object which references object `proto` as its prototype. Notice that `proto` has been placed into a single-element Tuple.

    obj.meth = function(self, a, b, c) #=...=# end
    obj.meth(a, b, c)

Call a member method `meth`, passing `obj` as the first argument.

    obj[k]

access obj.k

    obj[(:k1,:k2,:k3)]

return new object with properties specified by tuple of symbols

    obj[::Base.Generator]

return new object with properties set by generator

    drop(obj, :k1, :k2)

return new object with keys removed (own keys only; prototype unchanged)

    (; obj...)

splat object into a named tuple

    (obj...,)

splat into a tuple of values (useful for splatting into a constructor, e.g. MyStruct(obj...))

    ((k,v) for (k,v) ∈ zip(keys(obj),values(obj)))

generator to iterate over object's property names and values

    (; x, y, z) = obj

Destructure properties `x`, `y`, and `z` out of `obj`.
"""
module Internals
export object, AbstractObject, Object, Undef, hasprops, propsmatch, typematch, drop, getprototype
export Prop, R, isassigned, getboxtype, StaticType, MutableType, ProtoType, propsmutable, indexablematch

struct Undef{T} end # type for describing uninitialized values
Undef(::Type{T}) where T = Undef{T}()
Undef() = Undef{Any}()

abstract type Prop{n,T} end # type for describing object property names and types
prop_type_assembler(nTs::NamedTuple) = Union{(Prop{n,>:T} for (n,T) ∈ zip(keys(nTs),values(nTs)))...}

mutable struct R{X} # my own `Ref` type (to disambiguate from Base `Ref` type)
    x::X
    R()             = new{Any}() # ideally Core.Ref should have this too
    R{X}()  where X = new{X}()
    R(x::X) where X = new{X}(x)
    R{X}(x) where X = new{X}(x)
end
Base.getindex(r::R) = r.x
Base.setindex!(r::R, x) = (r.x = x)
Base.:(==)(a::R{T1}, b::R{T2}) where {T1,T2} = isassigned(a) && isassigned(b) && a[] == b[] || (!isassigned(a) && !isassigned(b) && T1 == T2)
isassigned(r::R) = isdefined(r, :x)
getboxtype(::R{T}) where T = T
Base.copy(r::R{T}) where T = isassigned(r) ? R{T}(r[]) : R{T}()

make_mutable(v::T) where T = R{T}(v)
make_mutable(v::R{T}) where T = v
make_mutable(::Undef{T}) where T = R{T}()

equiv(x,y) = x===y
equiv(y) = Base.Fix2(equiv, y)

const StaticType = NamedTuple
const MutableType = NamedTuple{<:Any,<:NTuple{N,R} where N}
const ProtoType = Tuple

abstract type AbstractObject{UserType, I, PT, PTM} end

struct Object{UserType, I, PT, PTM, P<:ProtoType, S<:StaticType, M<:MutableType} <: AbstractObject{UserType, I, PT, PTM}
    indexable::I
    prototype::P 
    static::S    
    mutable::M   

    Object{UserType}(indexable::I, prototype::P, static::S, mutable::M) where 
    {UserType, I, P<:ProtoType, S<:StaticType, M<:MutableType} = begin
        # hygiene: if mutable has properties in static, throw error
        for k ∈ keys(static) @assert k∉keys(mutable) "Repeated property $k in both static and mutable collections disallowed" end
        # hygiene: if there are any repeated prototypes, throw error
        reduce((acc,x)->(@assert(!any(y->x===y, acc), "Invalid repeated prototype $x"); (acc...,x)), prototype; init=())            
        # build out property type information
        muttypes = NamedTuple{keys(mutable)}(map(getboxtype, values(mutable)))
        protoTypes = foldr(merge, map(get_prop_types, prototype), init=(;))
        proptypes = (; protoTypes..., NamedTuple{keys(static)}(map(typeof, values(static)))..., muttypes...)
        new{UserType, I, prop_type_assembler(proptypes), prop_type_assembler(muttypes), P, S, M}(indexable, prototype, static, mutable) 
    end #𝓏𝓇
end

get_prop_types(o::T) where T = begin
    !ismutable(o) && return NamedTuple{propertynames(o)}(map(n->typeof(getproperty(o, n)), propertynames(o)))
    NamedTuple{fieldnames(T)}(T.types)
end
get_prop_types(o::Object) = begin
    static, mutable = getfield(o, :static), getfield(o, :mutable)
    s = NamedTuple{keys(static)}(map(typeof, values(static)))
    m = NamedTuple{keys(mutable)}(map(getboxtype, values(mutable)))
    protoTypes = merge((;), map(get_prop_types, getfield(o, :prototype))...)
    (; protoTypes..., s...,  m...)
end

hasprops(::AbstractObject{<:Any,<:Any,PT}) where PT = AbstractObject{<:Any,<:Any,>:PT}
propsmutable(::AbstractObject{<:Any,<:Any,<:Any,PTM}) where PTM = AbstractObject{<:Any,<:Any,<:Any,>:PTM}
propsmatch(::AbstractObject{<:Any,<:Any,PT,PTM}) where {PT,PTM} = AbstractObject{<:Any,<:Any,>:PT,>:PTM} 
indexablematch(::AbstractObject{<:Any,I}) where {I} = AbstractObject{<:Any,<:I}
typematch(::AbstractObject{UT,I,PT,PTM}) where {UT,I,PT,PTM} = isbits(UT) ? AbstractObject{UT,<:I,>:PT,>:PTM} : AbstractObject{<:UT,<:I,>:PT,>:PTM}

_prop_hygiene(static, mutable) = begin
    s, m = NamedTuple(static), NamedTuple(mutable)
    m = m isa MutableType ? NamedTuple{keys(m)}(map(copy, values(m))) : NamedTuple{keys(m)}(map(make_mutable, values(m)))
    skeys = filter(!Base.Fix2(∈, keys(m)), keys(s))
    s = NamedTuple{skeys}(map(Base.Fix1(getindex, s), skeys))
    (s, m)
end
_prototype_hygiene(p) = (p,)
_prototype_hygiene(p::ProtoType) = foldr((x,acc)->any(equiv(x), acc) ? acc : (x, acc...), p; init=())
_merge_objects(objl::Object{UTL}, objr::Object{UTR}) where {UTL,UTR} = begin
    ia, ib = getfield(objl, :indexable),   getfield(objr, :indexable)
    sa, sb = getfield(objl, :static),      getfield(objr, :static)
    ma, mb = getfield(objl, :mutable),     getfield(objr, :mutable)
    pa, pb = getfield(objl, :prototype),   getfield(objr, :prototype)
    indexable   = isnothing(ib) ? ia : ib
    prototype   = _prototype_hygiene((pa..., pb...))
    s           = (; sa..., sb...)
    m           = (; ma..., mb...)
    static, mutable = _prop_hygiene(s, m)
    Object{UTR}(indexable, prototype, static, mutable)
end

Object{UT}(; indexable=nothing, prototype=(), static=(;), mutable=(;)) where {UT} = begin
    Object{UT}(indexable, _prototype_hygiene(prototype), _prop_hygiene(static, mutable)...)
end
Object{UT}(objl::Object; indexable=nothing, prototype=(), static=(;), mutable=(;)) where {UT} = begin
    objr = Object{UT}(indexable, _prototype_hygiene(prototype), _prop_hygiene(static, mutable)...)
    _merge_objects(objl, objr)
end #𝓏𝓇
Object{UT}(objl::Object, objr::Object, objs::Object...; indexable=nothing, prototype=(), static=(;), mutable=(;)) where {UT} = begin
    obj = _merge_objects(objl, objr)
    Object{UT}(obj, objs...; indexable, prototype, static, mutable)
end #𝓏𝓇
Object{UT}(d::AbstractDict{Symbol}) where UT = Object{UT}(mutable = NamedTuple{(keys(d)...,)}(map(v->v isa AbstractDict{Symbol} ? Object{UT}(v) : v, values(d))))
Object(args...; kwargs...) = Object{Any}(args...; kwargs...)
(o::Object{UT})(; kwargs...) where {UT} = begin
    @assert all(Base.Fix2(∈, propertynames(o)), keys(kwargs)) "Argument not in template"
    static = let s=getfield(o, :static)
        NamedTuple{keys(s)}(map(k->k∈keys(kwargs) ? kwargs[k] : s[k], keys(s)))
    end
    mutable = let m=getfield(o, :mutable)
        NamedTuple{keys(m)}(map(k->k∈keys(kwargs) ? make_mutable(kwargs[k]) : isassigned(m[k]) ? R{getboxtype(m[k])}(m[k][]) : R{getboxtype(m[k])}(), keys(m)))
    end
    Object{UT}(o[], static, mutable, getfield(o, :prototype)) #𝓏𝓇
end

object(; var"##ib##"=nothing, kwargs...) = Object(indexable = var"##ib##", mutable = kwargs)
object(arg; var"##ib##"=nothing, kwargs...) = Object(indexable = var"##ib##", static = (; arg...), mutable = kwargs)
object(arg1, arg2, args...; kwargs...) = object((; arg1..., arg2...), args...; kwargs...)
struct IndexableBuilder{I} i::I end
Base.getindex(::typeof(object)) = IndexableBuilder(Dict())
Base.getindex(::typeof(object), d) = IndexableBuilder(d)
(ib::IndexableBuilder)(args...; kwargs...) = object(args...; kwargs..., var"##ib##"=ib.i)

struct Method{F,X<:AbstractObject} f::F; x::X end
(f::Method)(args...; kwargs...) = f.f(f.x, args...; kwargs...)
Base.show(io::IO, f::Method{F}) where {F} = 
    print(io, "$(f.f)(::AbstractObject, _...; _...)")

# Here's the magic
_getpropnested(o::AbstractObject, s::Symbol) = getproperty(o, s, true)
_getpropnested(o, s::Symbol) = getfield(o, s)
Base.getproperty(o::AbstractObject, s::Symbol, nested=false) = begin
    val = 
        if s ∈ propertynames(getfield(o, :mutable)) getproperty(getfield(o, :mutable), s)
        elseif s ∈ propertynames(getfield(o, :static)) getproperty(getfield(o, :static), s)[]
        else _getpropnested(getfield(o, :prototype)[findlast(p -> s ∈ propertynames(p), getfield(o, :prototype))], s)
        end
    val = val isa R ? val[] : val
    val isa Function && !nested && return Method(val, o)
    val
end #𝓏𝓇
Base.setproperty!(o::AbstractObject, s::Symbol, x) = begin
    s ∈ propertynames(getfield(o, :static)) && setproperty!(getfield(o, :static), s, x) # throw a nice error
    getproperty(getfield(o, :mutable), s)[] = x
end
Base.propertynames(o::AbstractObject) = begin
    props = (map(propertynames, (getfield(o, :static), getfield(o, :mutable)))..., map(propertynames, getfield(o, :prototype))...)
    props = reduce((acc,x)->(acc...,x...), props)
    props = reduce((acc,x)->x ∈ acc ? acc : (acc...,x), props, init=())
end
Base.NamedTuple(o::AbstractObject) = NamedTuple{propertynames(o)}(map(k->getproperty(o,k), propertynames(o)))
Base.merge(nt::NamedTuple, o::AbstractObject) = merge(nt, NamedTuple(o))
Base.getindex(o::AbstractObject) = getfield(o, :indexable)
Base.iterate(o::AbstractObject, n) = iterate(o[], n)
Base.iterate(o::AbstractObject) = iterate(o[])
Base.keys(o::AbstractObject) = keys(o[])
Base.values(o::AbstractObject) = values(o[])
Base.getindex(o::AbstractObject, k...) = getindex(o[], k...)
Base.setindex!(o::AbstractObject, x, k...) = setindex!(o[], x, k...)
Base.length(o::AbstractObject) = length(o[])
Base.size(o::AbstractObject) = size(o[])
Base.axes(o::AbstractObject) = axes(o[])
Base.firstindex(o::AbstractObject) = firstindex(o[])
Base.lastindex(o::AbstractObject) = lastindex(o[])
Base.:(==)(a::Object{UT1}, b::Object{UT2}) where {UT1,UT2} = begin
    UT1 == UT2 && a[] == b[] &&
    getfield(a, :static) == getfield(b, :static) &&
    getfield(a, :mutable) == getfield(b, :mutable) && 
    getfield(a, :prototype) == getfield(b, :prototype)
end
Base.copy(o::AbstractObject) = o()


Base.show(io::IO, o::Object{UT}) where UT = begin
    istr = replace("$(getfield(o, :indexable))", "\n" => "\n    ")
    s = getfield(o, :static)
    sstr = isempty(s) ? "(;)" : replace("$s", "\n" => "\n    ")
    mstr = replace("$(getfield(o, :mutable))", "\n" => "\n    ")
    pstr = replace("$(getfield(o, :prototype))", "\n" => "\n    ")
    print(io, "Object{$UT}(\n    indexable = $istr\n    static    = $sstr\n    mutable   = $mstr\n    prototype = $pstr\n)")
end
Base.show(io::IO, mut::MutableType) = begin
    itr = zip(keys(mut), map(getboxtype, values(mut)), map(v->isassigned(v) ? v[] : "#undef", values(mut)))
    itr = (" $k"*(typeof(v) ≠ T ? "::$T" : "")*" = $v," for (k, T, v) ∈ itr)
    print(io, "(;" * join(itr)[1:end-1] * ")")
end


drop(o::Object{UT}, props::Val{P}) where {UT,P} = begin
    args = P isa Symbol ? (P,) : P
    @assert args isa NTuple{N,Symbol} where N "Cannot drop non-Symbol identifiers"
    i = getfield(o, :indexable)
    s = getfield(o, :static)
    m = getfield(o, :mutable)
    p = getfield(o, :prototype)
    @assert all(k->k∈keys(m) || k∈keys(s), args) "Cannot drop property"

    ks = filter(k->k∉args, keys(s))
    km = filter(k->k∉args, keys(m))
    Object{UT}(indexable = i, static = NamedTuple{ks}(map(Base.Fix1(getindex, s), ks)), mutable = NamedTuple{km}(map(Base.Fix1(getindex, m), km)), prototype=p)
end
getprototype(o::AbstractObject) = getfield(o, :prototype)
staticpropertynames(o::AbstractObject) = propertynames(getfield(o, :static))
mutablepropertynames(o::AbstractObject) = propertynames(getfield(o, :mutable))
ownpropertynames(o::AbstractObject) = (staticpropertynames(o)..., mutablepropertynames(o)...)


end


# Object-to-Dictionary conversions
#Base.convert(T::Type{<:AbstractDict}, obj::Object) = begin
#    store = getfield(obj, :store); props = _getprops(store)
#    isnothing(_getproto(store)) ? T(k=>v isa Object ? convert(T, v) : v for (k,v) ∈ zip(keys(props), values(props))) :
#    merge(convert(T, _getproto(store)), T(k=>v isa Object ? convert(T, v) : v for (k,v) ∈ zip(keys(props), values(props))))
#end







#=


struct Object{UserType, StorageType}
    store::StorageType
end


# default constructors
Object{UT}(store::OT) where {UT,OT<:StorageType} = Object{UT,OT}(store)
Object(store::OT) where {OT<:StorageType} = Object{Nothing,OT}(store)

# constructing from scratch
# too much copypasta ... fix this up someday like a real programmer

# splatted objects and keyword arguments
Object{UT}(OT::Type{<:StorageType}; kwargs...) where {UT} = Object{UT}(OT(nothing, kwargs))
Object(OT::Type{<:StorageType}; kwargs...) = Object{Nothing}(OT(nothing, kwargs))
Object{UT}(; kwargs...) where {UT} = Object{UT}(DEFAULT_STORAGE_TYPE(nothing, kwargs))
Object(; kwargs...) = Object{Nothing}(; kwargs...)


# cute utility taken shamelessly from ConstructionBase.jl
@generated function _constructorof(::Type{T}) where T
    getfield(parentmodule(T), nameof(T))
end

# conversion
# arbitrary composite types
Object{UT}(OT::Type{<:StorageType}, obj) where {UT} = Object{UT}(OT(nothing, (; (k => getproperty(obj,k) for k ∈ propertynames(obj))...)))
Object(OT::Type{<:StorageType}, obj) = Object{Nothing}(OT, obj)
Object{UT}(obj) where {UT} = Object{UT}(DEFAULT_STORAGE_TYPE, obj)
Object(obj) = Object{Nothing}(obj)

# object type
Object{UTnew}(OTnew::Type{<:StorageType}, obj::Object) where UTnew = Object{UTnew}(OTnew(_getproto(getfield(obj, :store)), _getprops(getfield(obj, :store))))
Object(OTnew::Type{<:StorageType}, obj::Object{UT,OT}) where {UT,OT} = Object{UT}(OTnew(_getproto(getfield(obj, :store)), _getprops(getfield(obj, :store))))
Object{UTnew}(obj::Object{UT,OT}) where {UTnew,UT,OT} = Object{UTnew}(_constructorof(OT)(_getproto(getfield(obj, :store)), _getprops(getfield(obj, :store))))
Object(obj::Object) = obj

# recursive dict expansion
Object{UT}(OT::Type{<:StorageType}, dict::AbstractDict) where {UT} = 
    Object{UT}(OT(nothing, (; (Symbol(k) => v isa AbstractDict ? Object{UT}(OT, v) : v for (k,v) ∈ dict)...)))
Object(OT::Type{<:StorageType}, dict::AbstractDict) = 
    Object{Nothing}(OT(nothing, (; (Symbol(k) => v isa AbstractDict ? Object(OT, v) : v for (k,v) ∈ dict)...)))
Object{UT}(dict::AbstractDict) where {UT} =
    Object{UT}(DEFAULT_STORAGE_TYPE(nothing, (; (Symbol(k) => v isa AbstractDict ? Object{UT}(v) : v for (k,v) ∈ dict)...)))
Object(dict::AbstractDict) = Object{Nothing}(dict)


# code reuse
# constructing from a template
(template::Object{UT,OT})(; kwargs...) where {UT,OT} = Object{UT,OT}(OT(Val(:template), getfield(template, :store), kwargs))

# prototype inheritance
const PrototypeTypes = Union{Object, Nothing}
Object{UT}(OT::Type{<:StorageType}, proto::Tuple{PrototypeTypes}; kwargs...) where {UT} = Object{UT}(OT(first(proto), kwargs))
Object(OT::Type{<:StorageType}, proto::Tuple{PrototypeTypes}; kwargs...) = Object{Nothing}(OT(first(proto), kwargs))
Object{newUT}(proto::Tuple{Object{UT,OT}}; kwargs...) where {newUT,UT,OT} = Object{newUT}(_constructorof(OT)(first(proto), kwargs))
Object(proto::Tuple{Object{UT,OT}}; kwargs...) where {UT,OT} = Object{UT}(_constructorof(OT)(first(proto), kwargs))

# interface
struct Method{F,UT,OT} f::F; x::Object{UT,OT} end
(f::Method)(ar...; kw...) = f.f(f.x, ar...; kw...)
Base.show(io::IO, f::Method{F,UT,OT}) where {F,UT,OT} = print(io, "$(f.f)(::Object{$UT, $(nameof(OT))}, _...; _...)")
Base.getproperty(obj::Object, s::Symbol) = begin
    v = getfield(obj, :store)[s]
    v isa Function && return Method(v, obj)
    v
end
Base.setproperty!(obj::Object, s::Symbol, v) = (getfield(obj, :store)[s] = v)
Base.propertynames(obj::Object) = (keys(getfield(obj, :store))...,)

Base.keys(obj::Object) = (keys(getfield(obj, :store))...,)
Base.values(obj::Object) = (values(getfield(obj, :store))...,) # if you don't splat first, then sending values(obj) to NamedTuple in merge() is super slow 
#Base.iterate(obj::Object, itr=zip(keys(obj), values(obj))) = Iterators.peel(itr) # keys,values
Base.iterate(obj::Object, itr=values(obj)) = Iterators.peel(itr) # values only!
Base.merge(nt::NamedTuple, obj::Object) = (; nt..., NamedTuple{keys(obj)}(values(obj))...)

Base.length(obj::Object) = length(keys(getfield(obj, :store)))
Base.getindex(obj::Object, n) = getproperty(obj, Symbol(n))
Base.getindex(obj::Object{UT,OT}, n::NTuple{N,Symbol}) where {N,UT,OT} =
    Object{UT}(_constructorof(OT); NamedTuple{n}((; obj...))...)
Base.getindex(obj::Object, n::Base.Generator) = getindex(obj, (n...,))
Base.setindex!(obj::Object, x, n) = setproperty!(obj, Symbol(n), x)

drop(obj::Object{UT,OT}, n::Symbol...) where {UT,OT} = begin
    store = getfield(obj, :store)
    ownkeys = keys(store.properties)
    newkeys = (k for k ∈ ownkeys if k ∉ (n...,))
    valgen = (store[k] for k ∈ ownkeys)
    Object{UT}(_constructorof(OT), (getprototype(obj),); NamedTuple{(newkeys...,)}((; zip(keys(store.properties), valgen)...))...)
end

Base.show(io::IO, obj::Object{UT,OT}) where {UT,OT} = begin
    store = getfield(obj, :store); props = _getprops(store)
    print(io, "Object{",(UT isa Symbol ? ":" : ""), string(UT),", ", string(nameof(OT)), "}(\n    prototype: ", 
        replace(string(isnothing(_getproto(store)) ? "none" : _getproto(store)), "\n"=>"\n    "), ",\n    properties: ⟨", 
        replace(join([(v isa Object ? "\n" : "")*"$k = $v" for (k,v) ∈ zip(keys(props), values(props))], ", "), "\n"=>"\n    "), "⟩\n)")
end
Base.copy(obj::Object) = begin
    store = getfield(obj, :store)
    typeof(obj)(typeof(store)(_getproto(store), copy(store.properties)))
end
Base.deepcopy(obj::Object) = begin
    store = getfield(obj, :store)
    typeof(obj)(typeof(store)(deepcopy(_getproto(store)), copy(store.properties)))
end
Base.:<<(a::Object, b::Object) = (aproto = getfield(a, :store).prototype; isnothing(aproto) ? false : (aproto==b || aproto<<b))
Base.:>>(a::Object, b::Object) = b << a
Base.:(==)(a::Object, b::Object) = (typeof(a) == typeof(b)) && (getprototype(a) == getprototype(b)) && ((a...,) == (b...,))

# Object-to-Dictionary conversions
Base.convert(T::Type{<:AbstractDict}, obj::Object) = begin
    store = getfield(obj, :store); props = _getprops(store)
    isnothing(_getproto(store)) ? T(k=>v isa Object ? convert(T, v) : v for (k,v) ∈ zip(keys(props), values(props))) :
    merge(convert(T, _getproto(store)), T(k=>v isa Object ? convert(T, v) : v for (k,v) ∈ zip(keys(props), values(props))))
end

"""
    getprototype(obj::Object)::Union{Object, Nothing}

Retrieves `obj`'s prototype object.
"""
getprototype(obj::Object) = _getproto(getfield(obj, :store))

"""
    ownpropertynames(obj::Object)::Tuple

Retrieves `obj`'s property names, excluding those of its prototype
"""
ownpropertynames(obj::Object) = Tuple(keys(_getprops(getfield(obj, :store))))
"""
    ownproperties(obj::Object)::Base.Generator

Returns a generator for splatting `obj`'s own properties.
"""
ownproperties(obj::Object) = _ownprops_itr(getfield(obj, :store))

#zr
=#