"""
See also `object`

    Object{[TypeTag]}([objs::Object...] ; [iterable,] [static,] [mutable,] [prototype])

Construct an `Object`


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
export Prop, R, isassigned, getboxtype, StaticType, MutableType, ProtoType, propsmutable, indexablematch, getpropertytypes

struct Undef{T} end # type for describing uninitialized values
Undef(::Type{T}) where T = Undef{T}()
Undef() = Undef{Any}()

abstract type Prop{n,T} end # type for describing object property names and types
prop_type_assembler(nTs::NamedTuple) = Union{(Prop{n,>:T} for (n,T) ∈ zip(keys(nTs),values(nTs)))...}

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
getboxtype(::R{T}) where T = T
Base.copy(r::R{T}) where T = isassigned(r) ? R{T}(r[]) : R{T}()

make_mutable(v::T) where T = R{T}(v)
make_mutable(v::R{T}) where T = v
make_mutable(::Undef{T}) where T = R{T}()
make_mutable(T, v) = R{T}(v)
make_mutable(T, v::Undef{Tv}) where Tv = R{Tv}()


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
        sTypes = getpropertytypes(static)
        mTypes = getpropertytypes(mutable)
        protoTypes = merge((;), map(getpropertytypes, prototype)...)
        propTypes = (; protoTypes..., sTypes..., mTypes...)
        new{UserType, I, prop_type_assembler(propTypes), prop_type_assembler(mTypes), P, S, M}(indexable, prototype, static, mutable) 
    end #𝓏𝓇
end

getpropertytypes(o::T) where T = NamedTuple{fieldnames(T)}(T.types)
getpropertytypes(m::MutableType) = NamedTuple{keys(m)}(map(getboxtype, values(m)))
getpropertytypes(o::Object) = begin
    static, mutable = getfield(o, :static), getfield(o, :mutable)
    s = getpropertytypes(static)
    m = getpropertytypes(mutable)
    protoTypes = merge((;), map(getpropertytypes, getfield(o, :prototype))...)
    merge(protoTypes, s,  m)
end

namedtuple(o::NamedTuple) = o
namedtuple(o::T) where T = NamedTuple{fieldnames(T), Tuple{T.types...}}(map(Base.Fix1(getfield, o), fieldnames(T)))

hasprops(::AbstractObject{<:Any,<:Any,PT}) where PT = AbstractObject{<:Any,<:Any,>:PT}
propsmutable(::AbstractObject{<:Any,<:Any,<:Any,PTM}) where PTM = AbstractObject{<:Any,<:Any,<:Any,>:PTM}
propsmatch(::AbstractObject{<:Any,<:Any,PT,PTM}) where {PT,PTM} = AbstractObject{<:Any,<:Any,>:PT,>:PTM} 
indexablematch(::AbstractObject{<:Any,I}) where {I} = AbstractObject{<:Any,<:I}
typematch(::AbstractObject{UT,I,PT,PTM}) where {UT,I,PT,PTM} = isbits(UT) ? AbstractObject{UT,<:I,>:PT,>:PTM} : AbstractObject{<:UT,<:I,>:PT,>:PTM}

_prop_hygiene(static, mutable) = begin
    s, m = NamedTuple(static), NamedTuple(mutable)
    m = m isa MutableType ? NamedTuple{keys(m)}(map(copy, values(m))) : 
        NamedTuple{keys(m)}(map(k->R{getpropertytypes(m)[k]}(m[k]), keys(m)))
    skeys = filter(!Base.Fix2(∈, keys(m)), keys(s))
    s = NamedTuple{skeys, Tuple{map(Base.Fix1(getfield, getpropertytypes(s)), skeys)...}}(map(Base.Fix1(getfield, s), skeys))
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
Object{UT}(o) where UT = ismutable(o) ? Object{UT}(mutable=namedtuple(o)) : Object{UT}(static=namedtuple(o))
Object(args...; kwargs...) = Object{Any}(args...; kwargs...)
Object(o::AbstractObject) = o
(o::Object{UT})(; kwargs...) where {UT} = begin
    @assert all(Base.Fix2(∈, propertynames(o)), keys(kwargs)) "Argument not in template"
    static = let s=getfield(o, :static)
        NamedTuple{keys(s)}(map(k->k∈keys(kwargs) ? kwargs[k] : s[k], keys(s)))
    end
    mutable = let m=getfield(o, :mutable)
        mT = getpropertytypes(m)
        NamedTuple{keys(m)}(map(k->k∈keys(kwargs) ? make_mutable(mT[k], kwargs[k]) : isassigned(m[k]) ? R{getboxtype(m[k])}(m[k][]) : R{getboxtype(m[k])}(), keys(m)))
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

# Here's the magic (or is it?)
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
Base.NamedTuple(o::AbstractObject) = NamedTuple{propertynames(o), Tuple{getpropertytypes(o)...}}(map(k->getproperty(o,k), propertynames(o)))
Base.merge(o::AbstractObject) = o
Base.merge(ol::AbstractObject, or::AbstractObject{UT}, args...) where UT = merge(getfield(parentmodule(typeof(or)), nameof(typeof(or))){UT}(ol, or), args...)
Base.merge(nt::NamedTuple, o::AbstractObject, args...) = merge(merge(nt, NamedTuple(o)), args...)
Base.getindex(o::AbstractObject) = getfield(o, :indexable)

Base.iterate(o::AbstractObject, n) = nothing
Base.iterate(o::AbstractObject) = (o, nothing)
Base.length(o::AbstractObject) = 1

Base.keys(o::AbstractObject) = propertynames(o)
Base.values(o::AbstractObject) = map(Base.Fix1(getproperty, o), propertynames(o))

Base.getindex(o::AbstractObject, k...) = getindex(o[], k...)
Base.setindex!(o::AbstractObject, x, k...) = setindex!(o[], x, k...)
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
Base.show(io::IO, mut::MutableType) = begin # necessary because of R type and Undef values
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

