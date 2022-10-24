"""
    Object{[Param]}([ObjectType]; props...)

Create a structured `Object` with properties specified by the keyword arguments `props`. Object type can be specified by `ObjectType`, and additional type parameters can be specified by `Param`.

`ObjectType` can be `Static`, `Mutable`, or `Dynamic`, depending on performance needs. If not specified, default is `Mutable`.

`Param` is optional and does not affect `Object` behavior, but can be used to leverage Julia's type inference engine.

    Object{[Param]}([ObjectType,] props::AbstractDict[, Val(:r)])

Create an `Object` from a dictionary. Add argument `Val(:r)` for recursion.

    Object{[Param]}([ObjectType,] props::Generator)

Create an `Object` from a generator. The generator must produce key,value pairs.

    Object{[Param]}([ObjectType,] obj::Any)

Create an `Object` from an arbitrary composite type.    

    Object{[Param]}([ObjectType,] props::Object)

Convert an `Object` from one set of `ObjectType` and `Param` to another. 

    Object{[Param]}([ObjectType,] obj::Object...)

Splat and flatten the contents of `obj` to create an independent object with the same properties.

    (proto::Object)([ObjectType;] props...)

Every `Object` is a functor. Call to create a new object which inherits the properties of a prototype object `proto`, with own properties specified by the keyword arguments `props`. Changes which occur to `proto` are reflected in the new object, except for those which are overridden by `props`.

    (proto::Object)([ObjectType,] obj::Object...)

Using `proto` as a prototype, create a new object whose own properties are the same as `obj`. Note that `obj` is splatted and flattened before its properties are incorporated in the new object.

    obj.meth = function(this) #=...=# end
    obj.meth()

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
# using keyword arguments
Object{UT}(OT::Type{<:ObjectType}; kwargs...) where {UT} = Object{UT}(OT(nothing, kwargs))
Object(OT::Type{<:ObjectType}; kwargs...) = Object{Nothing}(OT(nothing, kwargs))
Object{UT}(; kwargs...) where {UT} = Object{UT}(DEFAULT_OBJECT_TYPE(nothing, kwargs))
Object(; kwargs...) = Object{Nothing}(; kwargs...)
# using splatted arguments (either tuples of pairs, or named tuples)
Object{UT}(OT::Type{<:ObjectType}, args::Pair...) where {UT} = Object{UT}(OT(nothing, args))
Object(OT::Type{<:ObjectType}, args::Pair...) = Object{Nothing}(OT(nothing, args))
Object{UT}(args::Pair...) where {UT} = Object{UT}(DEFAULT_OBJECT_TYPE(nothing, args))
Object(args::Pair...) = Object{Nothing}(args...)
# dict or generator
ArgType = Union{AbstractDict{Symbol,<:Any},Base.Generator}
Object{UT}(OT::Type{<:ObjectType}, args::ArgType) where {UT} = Object{UT}(OT(nothing, NamedTuple(args)))
Object(OT::Type{<:ObjectType}, args::ArgType) = Object{Nothing}(OT(nothing, NamedTuple(args)))
Object{UT}(args::ArgType) where {UT} = Object{UT}(DEFAULT_OBJECT_TYPE(nothing, NamedTuple(args)))
Object(args::ArgType) = Object{Nothing}(DEFAULT_OBJECT_TYPE(nothing, NamedTuple(args)))
# recursive dict
ArgType = AbstractDict{Symbol,<:Any}
Object{UT}(OT::Type{<:ObjectType}, args::ArgType, ::Val{:r}) where {UT} = 
    Object{UT}(OT(nothing, NamedTuple(k => v isa ArgType ? Object{UT}(OT, v, Val(:r)) : v for (k,v) ∈ args)))
Object(OT::Type{<:ObjectType}, args::ArgType, ::Val{:r}) = 
    Object{Nothing}(OT(nothing, NamedTuple(k => v isa ArgType ? Object(OT, v, Val(:r)) : v for (k,v) ∈ args)))
Object{UT}(args::ArgType, ::Val{:r}) where {UT} =
     Object{UT}(DEFAULT_OBJECT_TYPE(nothing, NamedTuple(k => v isa ArgType ? Object{UT}(v, Val(:r)) : v for (k,v) ∈ args)))
Object(args::ArgType, ::Val{:r}) = Object{Nothing}(args, Val(:r))
# dict with arbitrary keys (just convert dict and call above functions)
ArgType = AbstractDict{String,<:Any}
Object{UT}(OT::Type{<:ObjectType}, args::ArgType) where {UT} = Object{UT}(OT, Dict{Symbol,Any}(Symbol(k)=>v for (k,v) ∈ args))
Object(OT::Type{<:ObjectType}, args::ArgType) = Object{Nothing}(OT, Dict{Symbol,Any}(Symbol(k)=>v for (k,v) ∈ args))
Object{UT}(args::ArgType) where {UT} = Object{UT}(DEFAULT_OBJECT_TYPE, Dict{Symbol,Any}(Symbol(k)=>v for (k,v) ∈ args))
Object(args::ArgType) = Object{Nothing}(DEFAULT_OBJECT_TYPE, Dict(Symbol{Symbol,Any}(k)=>v for (k,v) ∈ args))
Object{UT}(OT::Type{<:ObjectType}, args::ArgType, ::Val{:r}) where {UT} = 
    Object{UT}(OT, Dict{Symbol,Any}(Symbol(k)=>v for (k,v) ∈ args), Val(:r))
Object(OT::Type{<:ObjectType}, args::ArgType, ::Val{:r}) = 
    Object{Nothing}(OT, Dict{Symbol,Any}(Symbol(k)=>v for (k,v) ∈ args), Val(:r))
Object{UT}(args::ArgType, ::Val{:r}) where {UT} =
     Object{UT}(DEFAULT_OBJECT_TYPE, Dict{Symbol,Any}(Symbol(k)=>v for (k,v) ∈ args), Val(:r))
Object(args::ArgType, ::Val{:r}) = Object{Nothing}(args, Val(:r))

# fill this in

# user-custom objects
Object{UT}(OT::Type{<:ObjectType}, obj) where {UT} = 
    Object{UT}(OT(nothing, NamedTuple(k => getproperty(obj,k) for k ∈ propertynames(obj))))
Object(OT::Type{<:ObjectType}, obj) =
    Object{Nothing}(OT(nothing, NamedTuple(k => getproperty(obj,k) for k ∈ propertynames(obj))))
Object{UT}(obj) where {UT} = 
    Object{UT}(DEFAULT_OBJECT_TYPE(nothing, NamedTuple(k => getproperty(obj,k) for k ∈ propertynames(obj))))
Object(obj) = Object{Nothing}(obj)

_storeof(obj::Object) = getfield(obj, :store)

# object type conversion
Object{UTnew}(OTnew::Type{<:ObjectType}, obj::Object) where UTnew = 
    Object{UTnew}(OTnew(getproto(_storeof(obj)), getprops(_storeof(obj))))
Object(OTnew::Type{<:ObjectType}, obj::Object{UT,OT}) where {UT,OT} = 
    Object{UT}(OTnew(getproto(_storeof(obj)), getprops(_storeof(obj))))
Object{UTnew}(obj::Object{UT,OT}) where {UTnew,UT,OT} = 
    Object{UTnew}(OT.name.wrapper(getproto(_storeof(obj)), getprops(_storeof(obj))))
Object(obj::Object) = obj

# dis how we make bebbies
(prototype::Object{UT})(OT::Type{<:ObjectType}; kwargs...) where {UT} = Object{UT}(OT(prototype, kwargs))
(prototype::Object{UT,OT})(; kwargs...) where {UT,OT} = Object{UT}(OT.name.wrapper(prototype, kwargs))
(prototype::Object{UT})(OT::Type{<:ObjectType}, args...) where {UT} = Object{UT}(OT(prototype, args))
(prototype::Object{UT,OT})(args...) where {UT,OT} = Object{UT}(OT.name.wrapper(prototype, args))

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
Base.show(io::IO, obj::Object) = begin
    store = _storeof(obj)
    print(io, "Object{",string(typeof(obj).parameters[1]),"}", replace(string(typeof(obj).parameters[2].name),"typename"=>""), "(\nprototype: ", 
        replace(string(isnothing(getproto(store)) ? "none" : string(getproto(store))), "\n"=>"\n    "), ",\nproperties: ⟨", 
        replace(string(getprops(store)), "NamedTuple"=>"", "\n"=>"\n    ")[2:end-1], "⟩\n)")
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
    isnothing(getproto(store)) ? T(k=>v for (k,v) ∈ zip(keys(props), values(props))) :
    merge(convert(T, getproto(store)), T(k=>v for (k,v) ∈ zip(keys(props), values(props))))
end
Base.convert(T::Type{<:AbstractDict}, obj::Object, ::Val{:r}) = begin
    store = _storeof(obj); props = getprops(store)
    isnothing(getproto(store)) ? T(k=>v isa Object ? convert(T, v, Val(:r)) : v for (k,v) ∈ zip(keys(props), values(props))) :
    merge(convert(T, getproto(store)), T(k=>v isa Object ? convert(T, v, Val(:r)) : v for (k,v) ∈ zip(keys(props), values(props))))
end

#zr