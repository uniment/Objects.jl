module Internals
export object, AbstractObject, Object, Undef, hasprops, propsmatch, typematch, drop, getprototype, property_type_assembler, getpropertytypes
export Prop, R, isassigned, getreftype, StaticStorage, MutableStorage, ProtoType, propsmutable, indexablematch, DynamicObject, DynamicStorage, Method

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
property_type_assembler(nTs::NamedTuple) = Union{(Prop{n,>:T} for (n,T) ∈ zip(keys(nTs),values(nTs)))...}
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

abstract type AbstractObject{TypeTag, I, PT, PTM} end


"""
See also `object`, which is a more convenient `Object` builder for simple `Object`s.
```
    o = Object{[TypeTag]}([objs::Object...] ; [indexable,] [prototype,] [static,] [mutable])
```
Construct an `Object` with optional type annotation `TypeTag`.

`indexable` can be any object which is ideally (but not necessarily) accessible by index. To access index `i` of `indexable`, use `o[i]`. To access `indexable` itself, use `o[]`.

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

    o3 = Object(indexable=[1,2,3], prototype=(o1,o2), mutable=(c=5,))
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
struct Object{TypeTag, I, PT, PTM, P<:ProtoType, S<:StaticStorage, M<:MutableStorage} <: AbstractObject{TypeTag, I, PT, PTM}
    indexable::I
    prototype::P 
    static::S    
    mutable::M   

    Object{TypeTag}(indexable::I, prototype::P, static::S, mutable::M) where 
    {TypeTag, I, P<:ProtoType, S<:StaticStorage, M<:MutableStorage} = begin
        # hygiene: if mutable has properties in static, throw error
        for k ∈ keys(static) @assert k∉keys(mutable) "Repeated property `$k` in both static and mutable collections disallowed" end
        # hygiene: if there are any repeated prototypes, throw error
        reduce((acc,x)->(@assert(!any(equiv(x), acc), "Invalid repeated prototype `$x`"); (acc...,x)), prototype; init=())            
        # build out property type information
        sTypes = getpropertytypes(static)
        mTypes = getpropertytypes(mutable)
        protoTypes = merge((;), map(getpropertytypes, prototype)...)
        propTypes = (; protoTypes..., sTypes..., mTypes...)
        new{TypeTag, I, property_type_assembler(propTypes), property_type_assembler(mTypes), P, S, M}(indexable, prototype, static, mutable) 
    end #𝓏𝓇
end

"""```
    getpropertytypes(o)
```
Retrieves the property names and types of an object `o` and returns them in a `NamedTuple`."""
getpropertytypes(o::T) where T = NamedTuple{fieldnames(T)}(T.types)
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
namedtuple(o::T) where T = NamedTuple{fieldnames(T), Tuple{T.types...}}(map(Base.Fix1(getfield, o), fieldnames(T)))

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
indexablematch(::AbstractObject{<:Any,I}) where {I} = AbstractObject{<:Any,<:I}
"""```
    typematch(o::AbstractObject)
```
Construct a type which tests for `Object`s that satisfy `propsmatch` and with satisfying `indexable` type and `TypeTag`."""
typematch(::AbstractObject{TypeTag,I,PT,PTM}) where {TypeTag,I,PT,PTM} = 
    isbits(TypeTag) ? AbstractObject{TypeTag,<:I,>:PT,>:PTM} : AbstractObject{<:TypeTag,<:I,>:PT,>:PTM}

"_prop_hygiene(static, mutable) : assert correct types, copy references, and eliminate overlap."
_prop_hygiene(static, mutable) = begin
    s, m = NamedTuple(static), NamedTuple(mutable)
    m = m isa MutableStorage ? NamedTuple{keys(m)}(map(copy, values(m))) :
        NamedTuple{keys(m)}(map(let m=m; k->R{getpropertytypes(m)[k]}(m[k]) end, keys(m)))
    skeys = filter(!Base.Fix2(∈, keys(m)), keys(s))
    s = NamedTuple{skeys, Tuple{map(Base.Fix1(getfield, getpropertytypes(s)), skeys)...}}(map(Base.Fix1(getfield, s), skeys))
    (s, m)
end
"_prototype_hygiene(proto) : ensure prototype is a tuple, and eliminate any copies of the same prototype."
_prototype_hygiene(p) = (p,)
_prototype_hygiene(p::ProtoType) = foldr((x,acc)->any(equiv(x), acc) ? acc : (x, acc...), p; init=())
"_merge_object(o1, o2) : merge o1 and o2 rightward, merging their `prototype`, `static`, and `mutable` collections. Choose `o2`'s `TypeTag` and `indexable`."
_merge_objects(objl::Object{TypeTagL}, objr::Object{TypeTagR}) where {TypeTagL,TypeTagR} = begin
    ia, ib = getfield(objl, :indexable),   getfield(objr, :indexable)
    sa, sb = getfield(objl, :static),      getfield(objr, :static)
    ma, mb = getfield(objl, :mutable),     getfield(objr, :mutable)
    pa, pb = getfield(objl, :prototype),   getfield(objr, :prototype)
    indexable   = isnothing(ib) ? ia : ib
    prototype   = _prototype_hygiene((pa..., pb...))
    s           = (; sa..., sb...)
    m           = (; ma..., mb...)
    static, mutable = _prop_hygiene(s, m)
    Object{TypeTagR}(indexable, prototype, static, mutable)
end

Object{TypeTag}(; indexable=nothing, prototype=(), static=(;), mutable=(;)) where {TypeTag} =
    Object{TypeTag}(indexable, _prototype_hygiene(prototype), _prop_hygiene(static, mutable)...)
Object{TypeTag}(objl::Object; indexable=nothing, prototype=(), static=(;), mutable=(;)) where {TypeTag} = begin
    objr = Object{TypeTag}(indexable, _prototype_hygiene(prototype), _prop_hygiene(static, mutable)...)
    _merge_objects(objl, objr)
end #𝓏𝓇
Object{TypeTag}(objl::Object, objr::Object, objs::Object...; indexable=nothing, prototype=(), static=(;), mutable=(;)) where {TypeTag} = begin
    obj = _merge_objects(objl, objr)
    Object{TypeTag}(obj, objs...; indexable, prototype, static, mutable)
end #𝓏𝓇
Object{TypeTag}(d::AbstractDict{Symbol}) where TypeTag = 
    Object{TypeTag}(mutable = NamedTuple{(keys(d)...,)}(map(v->v isa AbstractDict{Symbol} ? Object{TypeTag}(v) : v, values(d))))
Object{TypeTag}(o) where TypeTag = ismutable(o) ? Object{TypeTag}(mutable=namedtuple(o)) : Object{TypeTag}(static=namedtuple(o))
Object(args...; kwargs...) = Object{Any}(args...; kwargs...)
Object(o::AbstractObject) = o

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
    Object{TypeTag}(o[], getfield(o, :prototype), static, mutable) #𝓏𝓇
end

"""```
    o = object(s1, s2; m3..., m4...)
    o = object[](s1, s2; m3..., m4...)
```
Convenient `Object` builder with no inheritance. Collections `s1` and `s2` become static properties of `o`, and `m3` and `m4` become mutable properties.

Note that even if any of `s1` ... `m4` are `Object`s with their own mutability settings, `o` splats them out and applies its own mutability settings.

Introducing the `[]` indicates that `o` will accept dynamic properties.

Example:
```
    o1 = object(a=1, b=2)   # fully mutable
    o2 = object((a=1, b=2)) # fully static
    o3 = object((a=1,), b=2)# part static, part mutable
```

"""
object(; var"##ib##"=nothing, kwargs...) = Object(indexable = var"##ib##", mutable = kwargs)
object(arg; var"##ib##"=nothing, kwargs...) = Object(indexable = var"##ib##", static = (; arg...), mutable = kwargs)
object(arg1, arg2, args...; kwargs...) = object((; arg1..., arg2...), args...; kwargs...)

struct DynamicStorage{T} d::Dict{Symbol,T} end
DynamicStorage(; kwargs...) = DynamicStorage(Dict{Symbol,Any}((k,v) for (k,v) ∈ zip(keys(kwargs), values(kwargs))))
DynamicStorage(p::Pair...) = DynamicStorage(Dict{Symbol,Any}(p...))
Base.getproperty(::DynamicStorage, n) = nothing
const DynamicObject = AbstractObject{<:Any, <:DynamicStorage}

struct IndexableBuilder{I} i::I end
Base.getindex(::typeof(object)) = IndexableBuilder(DynamicStorage())
Base.getindex(::typeof(object), d) = IndexableBuilder(d)
(ib::IndexableBuilder)(args...; kwargs...) = object(args...; kwargs..., var"##ib##"=ib.i)

struct Method{F,X<:AbstractObject} f::F; x::X end
(f::Method)(args...; kwargs...) = f.f(f.x, args...; kwargs...)
Base.show(io::IO, f::Method{F}) where {F} = 
    print(io, "$(f.f)(::AbstractObject, _...; _...)")

# Here's the magic (or is it?)
_getpropnested(o::AbstractObject, s::Symbol) = getproperty(o, s, true)
_getpropnested(o, s::Symbol) = getfield(o, s)
_getpropnamesnested(o::AbstractObject) = keys(getpropertytypes(o))
_getpropnamesnested(o) = propertynames(o)
Base.getproperty(o::AbstractObject, s::Symbol, nested=false) = begin
    val = 
        if s ∈ keys(getfield(o, :mutable))  getfield(getfield(o, :mutable), s)[]
        elseif s ∈ keys(getfield(o, :static))  getfield(getfield(o, :static), s)
        else 
            i = findlast(p -> s ∈ _getpropnamesnested(p), getfield(o, :prototype))
            if !isnothing(i)  _getpropnested(getfield(o, :prototype)[i], s)
            elseif o isa DynamicObject  getindex(getfield(o[], :d), s)
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
    elseif o isa DynamicObject  setindex!(getfield(o[], :d), x, s)
    else throw("Property `$s` not found") end
    x
end
Base.propertynames(o::AbstractObject) = keys(getpropertytypes(o))
Base.propertynames(o::DynamicObject) = (keys(getfield(o[], :d))..., keys(getpropertytypes(o))...)
_NamedTuple(o::AbstractObject) = let pts=getpropertytypes(o); NamedTuple{keys(pts), Tuple{values(pts)...}}(map(Base.Fix1(getproperty,o), keys(pts))) end
Base.NamedTuple(o::AbstractObject) = _NamedTuple(o)
Base.NamedTuple(o::DynamicObject) = merge(NamedTuple(getfield(o[], :d)), _NamedTuple(o))
Base.merge(o::AbstractObject) = o
Base.merge(ol::AbstractObject, or::AbstractObject{TypeTag}, args...) where TypeTag = 
    merge(getfield(parentmodule(typeof(or)), nameof(typeof(or))){TypeTag}(ol, or), args...)
Base.merge(nt::NamedTuple, o::AbstractObject, args...) = merge(merge(nt, NamedTuple(o)), args...)
Base.merge(nt::NamedTuple, o::DynamicObject, args...) = merge(merge(nt, NamedTuple(getfield(o[], :d)), NamedTuple(o)), args...)
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

Base.:(==)(a::Object{TypeTag1}, b::Object{TypeTag2}) where {TypeTag1,TypeTag2} = begin
    TypeTag1 == TypeTag2 && a[] == b[] &&
    getfield(a, :static) == getfield(b, :static) &&
    getfield(a, :mutable) == getfield(b, :mutable) && 
    getfield(a, :prototype) == getfield(b, :prototype)
end
Base.copy(o::AbstractObject) = o()

Base.show(io::IO, o::Object{TypeTag}) where TypeTag = begin
    istr = replace("$(o[])", "\n" => "\n    ")
    s = getfield(o, :static)
    sstr = isempty(s) ? "(;)" : replace("$s", "\n" => "\n    ")
    mstr = replace("$(getfield(o, :mutable))", "\n" => "\n    ")
    pstr = replace("$(getfield(o, :prototype))", "\n" => "\n    ")
    print(io, "Object{$TypeTag}(\n    indexable = $istr\n    prototype = $pstr\n    static    = $sstr\n    mutable   = $mstr\n)")
end
Base.show(io::IO, mut::MutableStorage) = begin # necessary because of R type and Undef values
    itr = zip(keys(mut), map(getreftype, values(mut)), map(v->isassigned(v) ? v[] : "#undef", values(mut)))
    itr = (" $k"*(typeof(v) ≠ T ? "::$T" : "")*" = $v," for (k, T, v) ∈ itr)
    print(io, "(;" * join(itr)[1:end-1] * ")")
end

drop(o::Object{TypeTag}, props::Val{P}) where {TypeTag,P} = begin
    args = P isa Symbol ? (P,) : P
    @assert args isa NTuple{N,Symbol} where N "Cannot drop non-Symbol identifiers"
    i = getfield(o, :indexable)
    s = getfield(o, :static)
    m = getfield(o, :mutable)
    p = getfield(o, :prototype)
    @assert all(k->k∈keys(m) || k∈keys(s), args) "Cannot drop property"

    ks = filter(k->k∉args, keys(s))
    km = filter(k->k∉args, keys(m))
    Object{TypeTag}(
        indexable = i, 
        static = let pts=getpropertytypes(s); NamedTuple{ks, Tuple{map(Base.Fix1(getindex, pts), ks)...}}(map(Base.Fix1(getindex, s), ks)) end,
        mutable = let pts=getpropertytypes(m); NamedTuple{km, Tuple{map(k->R{pts[k]}, km)...}}(map(Base.Fix1(getindex, m), km)) end, 
        prototype=p
    )
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

