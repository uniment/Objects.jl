"""
    Object{[TypeTag]}([ObjectType,] [args...]; kwargs...)

Create a structured `Object` with properties specified by pairs `args` or keyword arguments `props`. Object type can be specified by `ObjectType`, and additional type parameters can be specified by `TypeTag`. Later properties override earlier ones.

`ObjectType` can be `Static`, `Mutable`, or `Dynamic`, depending on performance needs. If not specified, default is `Mutable`.

`TypeTag` is optional and does not affect `Object` behavior, but can be used to leverage Julia's type inference engine for multiple method dispatch.

    Object{[TypeTag]}([ObjectType,] props::AbstractDict[, Val(:r)])

Create an `Object` from a dictionary. Add argument `Val(:r)` for recursion.

    Object{[TypeTag]}([ObjectType,] obj::Any)

Create an `Object` from an arbitrary composite type.    

    Object{[TypeTag]}([ObjectType,] props::Object)

Convert an `Object` from one set of `ObjectType` and `TypeTag` to another. 

    Object{[TypeTag]}([ObjectType,] ((obj::Object)...)...; [props...])

Splat and flatten the contents of `obj` to create an independent object with the same properties. Can splat more than one object, with later splatted objects overriding earlier ones. `props` sets instance-specific properties and overrides all.

    (proto::Object)([ObjectType;] [((obj::Object)...)...]; props...)

Every `Object` is a functor. Call prototype object `proto` to create a new object which inherits `proto`'s properties, with own properties specified by splatted objects (or dictionaries) and the keyword arguments `props`. Changes which occur to `proto` are reflected in the new object, except for those which are overridden by own-properties.

    obj.meth = function(self, a, b, c) #=...=# end
    obj.meth(a, b, c)

Calls a member method `meth` and passes `obj` as the first argument.

    (; x, y, z) = obj

Destructure properties `x`, `y`, and `z` out of `obj`.
"""
struct Object{UserType, ObjectType}
    store::ObjectType
end

# default constructor
Object{UT}(store::OT) where {UT,OT<:ObjectType} = Object{UT,OT}(store)

# constructors for base objects with no prototype
# too much copypasta ... fix this up someday like a real programmer

# splatted objects and keyword arguments
Object{UT}(OT::Type{<:ObjectType}, args::Pair...; kwargs...) where {UT} = Object{UT}(OT(nothing, (args...,kwargs...)))
Object(OT::Type{<:ObjectType}, args::Pair...; kwargs...) = Object{Nothing}(OT(nothing, (args...,kwargs...)))
Object{UT}(args::Pair...; kwargs...) where {UT} = Object{UT}(DEFAULT_OBJECT_TYPE(nothing, (args...,kwargs...)))
Object(args::Pair...; kwargs...) = Object{Nothing}(; (args...,kwargs...)...)

# recursive dict expansion
Object{UT}(OT::Type{<:ObjectType}, args::AbstractDict) where {UT} = 
    Object{UT}(OT(nothing, NamedTuple(Symbol(k) => v isa AbstractDict ? Object{UT}(OT, v) : v for (k,v) ∈ args)))
Object(OT::Type{<:ObjectType}, args::AbstractDict) = 
    Object{Nothing}(OT(nothing, NamedTuple(Symbol(k) => v isa AbstractDict ? Object(OT, v) : v for (k,v) ∈ args)))
Object{UT}(args::AbstractDict) where {UT} =
    Object{UT}(DEFAULT_OBJECT_TYPE(nothing, NamedTuple(Symbol(k) => v isa AbstractDict ? Object{UT}(v) : v for (k,v) ∈ args)))
Object(args::AbstractDict) = Object{Nothing}(args)

# user-custom composite types
Object{UT}(OT::Type{<:ObjectType}, obj, args::Pair...; kwargs...) where {UT} = 
    Object{UT}(OT(nothing, ((k => getproperty(obj,k) for k ∈ propertynames(obj))...,args...,kwargs...)))
Object(OT::Type{<:ObjectType}, obj, args::Pair...; kwargs...) =
    Object{Nothing}(OT, obj, args...; kwargs...)
Object{UT}(obj, args::Pair...; kwargs...) where {UT} = 
    Object{UT}(DEFAULT_OBJECT_TYPE, obj, args...; kwargs...)
Object(obj, args::Pair...; kwargs...) = Object{Nothing}(obj, args...; kwargs...)

_storeof(obj::Object) = getfield(obj, :store)

# cute utility taken shamelessly from ConstructionBase.jl
@generated function constructorof(::Type{T}) where T
    getfield(parentmodule(T), nameof(T))
end
# object type conversion
Object{UTnew}(OTnew::Type{<:ObjectType}, obj::Object) where UTnew = 
    Object{UTnew}(OTnew(getproto(_storeof(obj)), getprops(_storeof(obj))))
Object(OTnew::Type{<:ObjectType}, obj::Object{UT,OT}) where {UT,OT} = 
    Object{UT}(OTnew(getproto(_storeof(obj)), getprops(_storeof(obj))))
Object{UTnew}(obj::Object{UT,OT}) where {UTnew,UT,OT} = 
    Object{UTnew}(constructorof(OT)(getproto(_storeof(obj)), getprops(_storeof(obj))))
Object(obj::Object) = obj

# dis how we make bebbies
(prototype::Object{UT})(OT::Type{<:ObjectType}, args::Pair...; kwargs...) where {UT} = 
    Object{UT}(OT(prototype, (args...,kwargs...)))
(prototype::Object{UT,OT})(args::Pair...; kwargs...) where {UT,OT} = 
    Object{UT}(constructorof(OT)(prototype, (args...,kwargs...)))
 
# interface
Base.getproperty(obj::Object, s::Symbol; iscaller=true) = begin # iscaller is false for nested prototype access
    v = _storeof(obj)[s]
    v isa Function && return iscaller ? ((a...; k...) -> v(obj, a...; k...)) : v
    v
end
Base.setproperty!(obj::Object, s::Symbol, v) = (_storeof(obj)[s] = v)
Base.propertynames(obj::Object) = Tuple(keys(_storeof(obj)))
Base.iterate(obj::Object, state=0, propnames=propertynames(obj)) = begin
    i = state + firstindex(propnames)
    i > lastindex(propnames) && return nothing
    ((propnames[i] => getproperty(obj, propnames[i]; iscaller=false)), state+1)
end
Base.getindex(obj::Object, n) = getproperty(obj, Symbol(n))
Base.setindex!(obj::Object, x, n) = setproperty!(obj, Symbol(n), x)
Base.show(io::IO, obj::Object{UT,OT}) where {UT,OT} = begin
    store = _storeof(obj); props = getprops(store)
    print(io, "Object{",string(UT),", ", string(nameof(OT)), "}(\n    prototype: ", 
        replace(string(isnothing(getproto(store)) ? "none" : getproto(store)), "\n"=>"\n    "), ",\n    properties: ⟨", 
        replace(join(((v isa Object ? "\n" : "")*"$k = $v" for (k,v) ∈ zip(keys(props), values(props))), ", "), "\n"=>"\n    "), "⟩\n)")
end
Base.copy(obj::Object) = begin
    store = _storeof(obj)
    typeof(obj)(typeof(store)(getproto(store), copy(store.properties)))
end
Base.deepcopy(obj::Object) = begin
    store = _storeof(obj)
    typeof(obj)(typeof(store)(deepcopy(getproto(store)), copy(store.properties)))
end
Base.:<<(a::Object, b::Object) = (aproto = getfield(a, :store).prototype; isnothing(aproto) ? false : (aproto==b || aproto<<b))

# Object-to-Dictionary conversions
Base.convert(T::Type{<:AbstractDict}, obj::Object) = begin
    store = _storeof(obj); props = getprops(store)
    isnothing(getproto(store)) ? T(k=>v isa Object ? convert(T, v) : v for (k,v) ∈ zip(keys(props), values(props))) :
    merge(convert(T, getproto(store)), T(k=>v isa Object ? convert(T, v) : v for (k,v) ∈ zip(keys(props), values(props))))
end

"""
    getprototype(obj::Object)::Union{Object, Nothing}

Retrieves `obj`'s prototype object.
"""
getprototype(obj::Object) = getproto(_storeof(obj))

#zr