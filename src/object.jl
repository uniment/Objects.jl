module Internals
export AbstractObject, Object, PropType, PropertyTypes, InnatePropertyTypes, Undef, ObjectViewer
export object, hasprops, propsmatch, typematch, typeeffective, drop, getprototypes, getfieldtypes, propertytypes, innatepropertytypes

export R, isassigned, getreftype, StaticStorage, MutableStorage, ProtoType, propsmutable, dynamicmatch, DynamicObject, DynamicStorage, Method

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
    PropType{n,T}
    PropType{:a, Int}
```
A type for describing property types.
    
See also: PropertyTypes, propertytypes"""
struct PropType{n,T} end

"""```
    PropertyTypes{>:Union{PropType{:a, String}, PropType{:b, Number}}}
```
A type to describe a set of properties.
```
    PropertyTypes(; kw...)
```
From keyword arguments of types such as `PropertyTypes(a=String, b=Number)`, construct an appropriate `PropertyTypes` type that describes the set that contains these properties.
```
    PropertyTypes(o)
```
Determine the concrete types of the properties of `o` and construct an appropriate `PropertyTypes` type. Useful for runtime checks of property types for objects whose property types may not be fixed.

Example:
```
    PropertyTypes(a=String, b=Number) == PropertyTypes{>:Union{PropType{:b, Number}, PropType{:a, String}}}
    my_obj = object(a="hi", b=2)
    my_obj isa AbstractObject{<:Any, <:Any, <:PropertyTypes(a=String, b=Int)}
    my_obj isa AbstractObject{<:Any, <:Any, <:PropertyTypes{>:Union{PropType{:a, String}, PropType{:b, B}}}} where B<:Number
    PropertyTypes(my_obj) <: PropertyTypes(a=String, b=Int)
    PropertyTypes((a=1, b=2)) <: PropertyTypes{PTs} where PTs>:Union{PropType{:a, T}, PropType{:b, T}} where T<:Number
    struct Foo{A,B} a::A; b::B end; PropertyTypes(Foo(1, 2.))
```
See also: propertytypes, InnatePropertyTypes, innatepropertytypes"""
struct PropertyTypes{PU} end
PropertyTypes(; kw...) = let nTs = NamedTuple(kw); Union{(PropType{n,T} for (n,T) ∈ zip(keys(nTs), values(nTs)))...} end
PropertyTypes(o) = PropertyTypes(; propertytypes(o)...)

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
DynamicStorage(p::Pair...) = DynamicStorage{Any}(Dict{Symbol,Any}(p))
Base.getindex(d::DynamicStorage, k::Symbol) = d.d[k]
Base.setindex(d::DynamicStorage, x, k::Symbol) = (d.d[k] = x;)
Base.keys(d::DynamicStorage) = keys(d.d)
Base.values(d::DynamicStorage) = values(d.d)
Base.copy(d::DynamicStorage) = typeof(d)(copy(d.d))
Base.merge(d::DynamicStorage) = d
Base.merge(dl::DynamicStorage{DL}, dr::DynamicStorage{DR}, d...) where {DL,DR} = merge(DynamicStorage{typejoin(DL,DR)}(merge(dl.d, dr.d)), d...)
Base.delete!(d::DynamicStorage, n::Symbol) = delete!(d.d, n)
Base.pop!(d::DynamicStorage, n::Symbol) = pop!(d.d, n)
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

`dynamic` must be an Objects.Dynamic container.

`prototype` can be any object, or a `Tuple` of objects, that the `Object` will inherit properties from. If a property is not present in the object's own properties, then a search is made of its prototype(s).

`static` and `mutable` can be any object which can be converted to a `NamedTuple`. Static properties are immutable and require no allocations, while mutable properties create a reference and an allocation.

Whenever conflicts arise, they are resolved by merging in a left-to-right fashion. For example, if there are two prototypes `(pa, pb)` that both have the same property, then it is taken from `pb`. Likewise, an object's own static properties override its prototype-inherited properties, and mutable properties override static.

Examples (feel free to run @btime on all of them):
```
    o1 = Object(static=(a=1, b=2), mutable=(b=3, c=4))
    (; a, b, c) = o1
    (a, b, c)   # (1, 3, 4) (mutable .b overrides static .b)
    o1.b = 0    # ok (mutable property)
    o1.a = 1    # error (static property)

    o2 = Object(static=(a=0,))

    o3 = Object(dynamic=(x=[1,2,3],), prototype=(o1,o2), mutable=(c=5,))
    o3.x
    o3.x = "hi" # dynamic properties are untyped
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

Finally, `Object`s can be constructed from objects of other types. Example:
```
    struct Foo{A,B} a::A; b::B end
    mutable struct Bar{B,C} b::B; c::C end
    Object(Foo(1,2), Bar(3,4))
```
See also: `AbstractObject`, `ObjectViewer`, `object`, `Undef`, `hasprops`, `propsmatch`, `typematch`."""
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
        sTypes = innatepropertytypes(static)
        mTypes = innatepropertytypes(mutable)
        protoTypes = merge((;), map(innatepropertytypes, prototype)...)
        propTypes = (; protoTypes..., sTypes..., mTypes...)
        new{TypeTag, D, PropertyTypes(; propTypes...), PropertyTypes(; mTypes...), P, S, M}(dynamic, prototype, static, mutable) 
    end #𝓏𝓇
end

"""```
    getfieldtypes(o)
```
Retrieves the field names and types of an object `o` and returns them in a `NamedTuple`.

See also: fieldnames, fieldtypes, propertynames, propertytypes, innatepropertytypes"""
getfieldtypes(::T) where T = NamedTuple{fieldnames(T)}(T.types) # using fieldtypes(T) is type-unstable!!! (???)
"""```
    innatepropertytypes(o)
```
Retrieves the property names and types of an object `o`, as specified by typeof(o), and returns them in a `NamedTuple`. Because property types are specified by typeof(o), they can be abstract types. Note that the properties must also be fields of the object's type.
```
    innatepropertytypes(o::Object)
```
Retrieves the property names and types of an `Object` and returns them in a `NamedTuple`. Returns *only* non-dynamic property types.

See also: propertytypes, fieldnames, fieldtypes, getfieldtypes"""
innatepropertytypes(o::T) where T = let pns=Tuple(propertynames(o)), fts=getfieldtypes(o); NamedTuple{pns}(map(Base.Fix1(getfield, fts), pns)) end
innatepropertytypes(m::MutableStorage) = NamedTuple{keys(m)}(map(getreftype, values(m)))
innatepropertytypes(o::Object) = begin
    static, mutable = getfield(o, :static), getfield(o, :mutable)
    s = innatepropertytypes(static)
    m = innatepropertytypes(mutable)
    protoTypes = merge((;), map(innatepropertytypes, getfield(o, :prototype))...)
    merge(protoTypes, s, m)
end
"""```
    InnatePropertyTypes(o)
```
Like `PropertyTypes`, but returns only properties which are within the object's type specification, namely the intersection of getproperties(o) and getfields(o).
"""
InnatePropertyTypes(o) = PropertyTypes(innatepropertytypes(; o...))
"""```
    propertytypes(o)
```
Retrieves the concrete property names and property types of object `o`. \n\nExample:
```
    o=object[(a=1,)](; NamedTuple{(:b,),Tuple{Number}}(2)...)
    PropertyTypes(; propertytypes(o)...) <: PropertyTypes(a=Int, b=Int)
```
"""
propertytypes(o) = let pns = propertynames(o); NamedTuple{pns}(map(typeof, map(Base.Fix1(getproperty, o), pns))) end

"""```
    namedtuple(o)
```
Internal utility. Returns a `NamedTuple` of the properties and values of object `o`, with property types as defined by the object type instead of each property's concrete type."""
namedtuple(o::NamedTuple) = o
namedtuple(o::T) where T = let pns = Tuple(propertynames(o)), pts=innatepropertytypes(o)
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
hasprops(::AbstractObject{TT,D,PT}) where {TT,D,PT} = AbstractObject{TypeTag, Dynamic, Props} where {TypeTag, Dynamic, Props>:PT}
"    propsmutable(o::AbstractObject)\n\nConstruct a type which tests for `Object`s that have *at least* the mutable properties of `o`.\n\nSee also: hasprops"
propsmutable(::AbstractObject{<:Any,<:Any,<:Any,PTM}) where PTM = AbstractObject{<:Any,<:Any,<:Any,MutableProps} where {MutableProps>:PTM}
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
See also: `hasprops`, `propsmutable`, `typematch`, `typeeffective`
"""
propsmatch(::AbstractObject{<:Any,<:Any,PT,PTM}) where {PT,PTM} = AbstractObject{<:Any,<:Any,Props,MutableProps} where {Props>:PT, MutableProps>:PTM}
dynamicmatch(::AbstractObject{<:Any,D}) where {D} = AbstractObject{<:Any,<:D}
"""```
    typematch(o::AbstractObject)
```
Returns a type descriptor matching objects whose behavior is a superset of `o`.

Example:```
    a = object((a=1,); b=2)     # :a static, :b mutable
    b = object(a=1, b=2, c=3)   # :a, :b, and :c mutable
    b isa typematch(a)
```""" # Why is the runtime so bad though? Why can't it constant-fold, even wtih Base.@pure??
typematch(::AbstractObject{TT,D,PT,PTM}) where {TT,D,PT,PTM} = 
    isbits(TT) ? AbstractObject{TT, Dynamic, Props, MutableProps} where {Dynamic<:D, Props>:PT, MutableProps>:PTM} : 
    AbstractObject{TypeTag, Dynamic, Props, MutableProps} where {TypeTag<:TT, Dynamic<:D, Props>:PT, MutableProps>:PTM}
"""```
    typeeffective(o::AbstractObject)
```
Returns a type descriptor for the object type which is functionally the same as `o`."""
typeeffective(::AbstractObject{TypeTag,D,PT,PTM}) where {TypeTag,D,PT,PTM} = AbstractObject{TypeTag,D,PT,PTM}

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
    s = NamedTuple{skeys, Tuple{map(Base.Fix1(getfield, innatepropertytypes(s)), skeys)...}}(map(Base.Fix1(getfield, s), skeys))
    (s, m)
end
_mutable_hygiene(m::MutableStorage) = NamedTuple{keys(m)}(map(copy, values(m)))
_mutable_hygiene(m::NamedTuple) = let pt=innatepropertytypes(m); NamedTuple{keys(m)}(map(k->R{pt[k]}(m[k]), keys(m))) end

"_prototype_hygiene(proto) : ensure prototype is a tuple, and eliminate any copies of the same prototype."
_prototype_hygiene(p) = (p,)
_prototype_hygiene(p::ProtoType) = foldr((x,acc)->any(equiv(x), acc) ? acc : (x, acc...), p; init=())

_object_hygiene(dynamic, prototype, static, mutable) = begin
    d, s, m = _prop_hygiene(dynamic, static, mutable)
    p = _prototype_hygiene(prototype)
    (d, p, s, m)
end

"_merge_object(o1, o2) : merge o1 and o2 rightward, merging their `prototype`, `static`, and `mutable` collections. Choose `o2`'s `TypeTag` and `dynamic`."
_merge_objects(objl::Object, objr::Object{TypeTag}) where TypeTag = begin
    da, db = getfield(objl, :dynamic),      getfield(objr, :dynamic)
    sa, sb = getfield(objl, :static),       getfield(objr, :static)
    ma, mb = getfield(objl, :mutable),      getfield(objr, :mutable)
    pa, pb = getfield(objl, :prototype),    getfield(objr, :prototype)
    d           = isnothing(da) && isnothing(db) ? nothing : 
                  isnothing(da) ? db :
                  isnothing(da) ? db :
                  merge(da, db)
    prototype   = _prototype_hygiene((pa..., pb...))
    s           = (; sa..., sb...)
    m           = (; ma..., mb...)
    dynamic, static, mutable = _prop_hygiene(d, s, m)
    Object{TypeTag}(dynamic, prototype, static, mutable)
end #𝓏𝓇

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

"""```
    (o::Object)(; kwargs...)
```
Template constructor. Calling an instance of `Object` creates a new `Object` with the same properties of the same types, whose values default to those of the template. Use keyword arguments to set new values.

Example:
```
    o = object((a=1,); b=2) # :a static, :b mutable
    o(a=2, b=3)             # :a static, :b mutable with new values
    o()                     # create replica
    o(c=3)                  # error
```"""
(o::Object{TypeTag})(; kwargs...) where {TypeTag} = begin
    for k ∈ keys(kwargs)  @assert k ∈ propertynames(o, true) "Argument `$k` not in template"  end
    static = let s=getfield(o, :static); NamedTuple{keys(s)}(map(k->k∈keys(kwargs) ? kwargs[k] : s[k], keys(s))) end
    mutable = let m=getfield(o, :mutable), mT = innatepropertytypes(m)
        NamedTuple{keys(m)}(map(keys(m)) do k
            k ∈ keys(kwargs) && return make_mutable(mT[k], kwargs[k])
            isassigned(m[k]) && return R{getreftype(m[k])}(m[k][])
            R{getreftype(m[k])}()
        end)
    end
    dynamic = isnothing(o[]) ? nothing : typeof(o[])(k∈keys(kwargs) ? k=>kwargs[k] : k=>o[][k] for (k,v) ∈ zip(keys(o[]), values(o[])))
    Object{TypeTag}(dynamic, getfield(o, :prototype), static, mutable) #𝓏𝓇
end #𝓏𝓇
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
    o7 = object((o6,), a=1)  # inherits :b
```"""
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
_getpropnamesnested(o::AbstractObject) = keys(innatepropertytypes(o)) # ignores dynamic properties
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
Base.propertynames(o::AbstractObject) = keys(innatepropertytypes(o))
Base.propertynames(o::DynamicObject) = Tuple(keys(merge(map(NamedTuple, getfield(o, :prototype))..., NamedTuple(o))))
InnateNamedTuple(o::AbstractObject) = let pts=innatepropertytypes(o); NamedTuple{keys(pts), Tuple{values(pts)...}}(map(Base.Fix1(getproperty,o), keys(pts))) end
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
Base.delete!(o::AbstractObject, n) = n ∈ keys(innatepropertytypes(o)) ? throw("Cannot delete property `$n`") : delete!(o[], n)
Base.pop!(o::AbstractObject, n) = n ∈ keys(innatepropertytypes(o)) ? throw("Cannot pop property `$n`") : pop!(o[], n)
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

    ks = filter(Base.Fix2(∉, args), keys(s))
    km = filter(Base.Fix2(∉, args), keys(m))
    Object{TypeTag}(
        dynamic = i, 
        static  = let pts=innatepropertytypes(s); NamedTuple{ks, Tuple{map(Base.Fix1(getindex, pts), ks)...}}(map(Base.Fix1(getindex, s), ks)) end,
        mutable = let pts=innatepropertytypes(m); NamedTuple{km, Tuple{map(k->R{pts[k]}, km)...}}(map(Base.Fix1(getindex, m), km)) end, 
        prototype=p
    )
end
getprototypes(o::AbstractObject) = getfield(o, :prototype)
ownpropertynames(o::AbstractObject) = (staticpropertynames(o)..., mutablepropertynames(o)...)

getstaticproperties(o::Object)  = getfield(o, :static)
getstaticproperties(o)          = ismutable(o) ? () : namedtuple(o)
getmutableproperties(o::Object) = let m=getfield(o, :mutable); NamedTuple{keys(m), Tuple{values(innatepropertytypes(m))...}}(values(m)) end
getmutableproperties(o)         = ismutable(o) ? namedtuple(o) : ()

staticpropertytypes(o::Object)  = innatepropertytypes(getfield(o, :static))
staticpropertytypes(o)          = ismutable(o) ? () : innatepropertytypes(o)
mutablepropertytypes(o::Object) = innatepropertytypes(getfield(o, :mutable))
mutablepropertytypes(o)         = ismutable(o) ? innatepropertytypes(o) : ()


"""```
    ObjectViewer(objects::Tuple, propids::NamedTuple{<:Any, <:NTuple{N,Int} where N})
    ObjectViewer(; kwargs...)
```

"""
struct ObjectViewer{TypeTag, D, PT, PTM, OT, PID} <: AbstractObject{TypeTag, D, PT, PTM}
    objects::OT
    propids::PID
    ObjectViewer{TypeTag}(objects::OT, propids::PID) where {TypeTag, OT<:Tuple, PID<:NamedTuple{<:Any, <:NTuple{N,Int} where N}} = begin
        # hygiene: if there are any repeated objects, throw error
        reduce((acc,x)->(@assert(!any(equiv(x), acc), "Invalid repeated object `$x`"); (acc...,x)), objects; init=())
        # hygiene: ensure all property id numbers are within bounds
        map(x->@assert(x ∈ eachindex(objects), "Invalid object id $x"), values(propids))
        # build out property type information
        allsTypes = map(staticpropertytypes, objects)
        allmTypes = map(mutablepropertytypes, objects)
        mTypes    = reduce(zip(keys(propids), values(propids)), init=(;)) do acc, (k,id)
            if      k ∈ keys(allmTypes[id])  merge(acc, NamedTuple{(k,)}((allmTypes[id][k],)))
            else    acc
            end
        end
        propTypes = reduce(zip(keys(propids), values(propids)), init=(;)) do acc, (k,id)
            if      k ∈ keys(allsTypes[id])  merge(acc, NamedTuple{(k,)}((allsTypes[id][k],)))
            elseif  k ∈ keys(allmTypes[id])  merge(acc, NamedTuple{(k,)}((allmTypes[id][k],)))
            else    acc  
            end
        end
        D = length(propTypes) == length(propids) ? Nothing : Any
        new{TypeTag, D, PropertyTypes(; propTypes...), PropertyTypes(; mTypes...), OT, PID}(objects, propids)
    end
end #𝓏𝓇
ObjectViewer{TypeTag}(; kwargs...) where TypeTag = begin
    props = NamedTuple(kwargs)
    objects = foldr(values(props), init=()) do x, acc
        if x ∈ acc  acc
        else  (x, acc...)
        end
    end
    propids = reduce(zip(keys(props), values(props)), init=(;)) do acc, (k, v)
        merge(acc, NamedTuple{(k,)}((findfirst(equiv(v), objects),)))
    end
    ObjectViewer{TypeTag}(objects, propids)
end
ObjectViewer(args...; kwargs...) = ObjectViewer{Any}(args...; kwargs...)
Base.show(io::IO, o::ObjectViewer{T1,T2}) where {T1,T2} = 
    print(io, "ObjectViewer{$T1, $T2}(\n    "*replace("$(getfield(o, :objects))", "\n"=>"\n    ")*",\n    "*replace("$(getfield(o, :propids))", "\n"=>"\n    ")*"\n)")

Base.getproperty(o::ObjectViewer, n::Symbol) = getproperty(getfield(o, :objects)[getfield(o, :propids)[n]], n)
Base.setproperty!(o::ObjectViewer, n::Symbol, x) = setproperty!(getfield(o, :objects)[getfield(o, :propids)[n]], n, x)
Base.propertynames(o::ObjectViewer) = Tuple(keys(getfield(o, :propids)))


end


# Object-to-Dictionary conversions
#Base.convert(T::Type{<:AbstractDict}, obj::Object) = begin
#    store = getfield(obj, :store); props = _getprops(store)
#    isnothing(_getproto(store)) ? T(k=>v isa Object ? convert(T, v) : v for (k,v) ∈ zip(keys(props), values(props))) :
#    merge(convert(T, _getproto(store)), T(k=>v isa Object ? convert(T, v) : v for (k,v) ∈ zip(keys(props), values(props))))
#end

