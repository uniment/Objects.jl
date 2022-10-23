# dynamic objects with prototype inheritance

#module Objects
#export Object, getprototype, setprototype!, keys, values, free, lock!


begin
"""
`Object`: Objects with prototype inheritance.

    obj = Object(T::Type)

Create an empty, uninitialized `Object` with no parent object to inherit from.

Properties can be introduced dynamically with `obj.name=val`, `obj[:name]=val`, or `obj["name"]=val`. They can be accessed with `obj.name`, `obj[:name]`, or `obj["name"]`.

The `T` argument specifies the type that `obj` can contain. Set `T` to `Any` for fully dynamic behavior. Example:

    obj = Object(Any)

Other types can be chosen for performance at the expense of flexibility.

    obj = Object([T::Type;] props...)
    obj = Object([T::Type,] props::Pair...)
    obj = Object([T::Type,] props::AbstractDict)

Create an `Object` whose properties are `props`. The dictionary keys must be `Symbol` or `String`. If no type `T` is given, then it is selected automatically as the minimum set of value types in `props`. As before, setting `T` to `Any` provides the greatest dynamism and flexibility at the expense of performance. Example:

    obj = Object(
        a = [1, 2, 3],
        b = true,
        c = Object(Real, x=1, y=2, z=3)
    )

Note that objects can be nested readily.

    obj = Object([T::Type,] props::AbstractDict, Val(:r))

Unroll dictionary `props` into an `Object` recursively. Any nested dictionaries will be recursively converted into nested `Object`s. Great for reading config files, e.g. `using TOML; cfg = Object(TOML.parsefile("config.ini"), Val(:r)))`

    obj.meth = function(this, args...; kwargs...) [...] end
    obj.meth(args...; kwargs...)

Define a member method `meth` that belongs to `obj`. Calling `obj.meth` passes `obj` as the first argument to `meth`.

Note that the type of `obj` must be sufficiently broad to allow methods to be stored as properties. Example:

    obj = Object(Any, a=2)
    obj.meth = function(this, b) this.a*b end
    obj.meth(3) #-> 6

Note that accessing `obj.meth` yields an anonymous function that has captured `obj`. If it is desired to *store* a function which is not going to be called as a method of `obj`, then use `obj.func = Ref( ... )` and access it with `obj.func[]`. 

    newObj = obj([T::Type;] [newProps...])
    newObj = obj([T::Type,] [newProps::Pair...])
    newObj = obj([T::Type,] [newProps::AbstractDict])

`obj` is a functor, and calling `obj()` creates a new `Object`. The newly created `Object` inherits from `obj`; `obj` is said to be a *prototype* for `newObj`, and any properties and methods of `obj` are made available to `newObj`. Calling `newObj.meth` passes `newObj` as a first argument. Example:

    newObj = obj(a=3, b=4)
    newObj.meth(3) #-> 9
    obj.meth(3) #-> 6 still
    newObj.meth(newObj.b) #-> 12

In addition to inheriting properties and methods from `obj`, `newObj` has its own properties as specified by `newProps`. Any own properties that share the same name as inherited properties will override them when accessing `newObj`.

The newly created object `newObj` is also a functor and can serve as a prototype for creating new inheritor objects. Hence the camelCase.

Note that executing `Object` member methods is not (I think) as efficient as using multiple dispatch to call methods specialized on concrete types. It is instead most useful when `Object`s' individual behavior can differ on an instance-by-instance basis.

    Object{T::Type,P}( [...] )
    Object(T::Type, P, [...] )

Create a dynamic `Object` specialized by optional parameter `P`. `P` can be a `Type`, or it can be a bits type (such as a boolean, an integer, etc.).

This can be used for specializing methods for multiple dispatch. Example:

```julia
a = Object(Int, :pos, x=5)
b = Object(Int, :neg, x=5)
g(obj::Object{T,:pos} where T) =  obj.x^2
g(obj::Object{T,:neg} where T) = -obj.x^2

julia> g(a)
25

julia> g(b)
-25
```

It can also be used for defining type hierarchies which specify specialized methods and method inheritance for dispatch. Example:

```julia
# type hierarchy
abstract type Animal end
abstract type Human <: Animal end
abstract type Child <: Human end

# prototypes
const Prototypes = Object(Object)
Prototypes.Animal = Object(Any, Animal; eyes=2, legs=4, size=:large)
Prototypes.Human = Prototypes.Animal(Any, Human; legs=2, artificial_legs=0, size=:medium)
Prototypes.Child = Prototypes.Human(Any, Child; size=:small)

# unionalls for defining type-specialized methods
const AnimalType = Object{T,P} where {T,P<:Animal}
const HumanType = Object{T,P} where {T,P<:Human}
const ChildType = Object{T,P} where {T,P<:Child}

# constructors
Animal(a...; kw...) = Prototypes.Animal(a...; kw...)
Human(a...; kw...) = Prototypes.Human(a...; kw...)
Child(a...; kw...) = Prototypes.Child(a...; kw...)

# defining a method extends naturally to subtypes
getspeed(animal::AnimalType) = animal.legs

julia> getspeed(Animal())
4

julia> joe = Human(legs=1); # lost in a tragic automobile accident

julia> getspeed(joe)
1

julia> joe.artificial_legs = 1 # modern technology
1

julia> getspeed(person::HumanType) = person.legs + person.artificial_legs;

julia> getspeed(joe) 
2

julia> emily = Child(eyes=1); emily.eyes  # it was all fun and games until she poked her eye out
1

julia> emily
Object{Any, Child}(
prototype: Object{Any, Child}(
    prototype: Object{Any, Human}(
        prototype: Object{Any, Animal}(
            prototype: none,
            properties: ⟨:legs => 4, :eyes => 2, :size => :large⟩
            lock=false),
        properties: ⟨:legs => 2, :artificial_legs => 0, :size => :medium⟩
        lock=false),
    properties: ⟨:size => :small,⟩
    lock=false),
properties: ⟨:eyes => 1,⟩
lock=false)
```
Notice that emily inherits traits from all `Human`, `Animal`, and `Child` parameterized `Object`s. A type hierarchy system is optional and not necessary to inherit traits, but is useful for specializing subtype methods for multiple dispatch. 

Notice that `Object`s can inherit from each other yet not be considered different types; keeping the type system separate from the inheritance system can be interesting.

"""
mutable struct Object{T,P}
    prototype::Object
    properties::Dict{Symbol,T}
    lock::Bool

    # default constructors
    Object{T,P}(proto::Object{PT}, props::Dict{Symbol, T}, lock) where {T,P,PT<:T} = new{T,P}(proto, props, lock)
    Object{T,P}(proto::Object{PT}, props::Dict{Symbol, T}) where {T,P,PT<:T} = new{T,P}(proto, props, false)
    Object(proto::Object{PT}, props::Dict{Symbol, PT}) where {PT} = typeof(proto)(proto, props, false)

    # when no prototype is provided: self-referential (instead of `nothing`) for type stability
    Object{T,P}(props::Dict{Symbol, T}) where {T,P} = begin
        obj=new{T,P}()
        setfield!(obj, :prototype, obj)
        setfield!(obj, :properties, props)
        setfield!(obj, :lock, false)
        obj
    end
end

_clean_dict(d::AbstractDict{S,T}) where {S<:Union{Symbol,String},T} =
    (d isa AbstractDict{Symbol,T} where T) ? Dict{Symbol,T}(d) : Dict{Symbol,T}(Symbol.(keys(d)) .=> values(d))
const ParamType=Union{Type,Symbol,Bool,Integer,AbstractFloat,Char}

# constructors
Object{T,P}(proto::Object, props::AbstractDict{Union{Symbol,String},PP}) where {T,P,PP<:P} = 
    Object{T,P}(proto, Dict{Symbol,T}(_clean_dict(props)))
Object(proto::Object{T}, props::AbstractDict) where {T} = 
    typeof(proto)(proto, Dict{Symbol,T}(_clean_dict(props)))
Object{T,P}(props::AbstractDict) where {T,P} = Object{T,P}(Dict{Symbol,T}(_clean_dict(props)))
Object{T}(props::AbstractDict) where {T} = Object{T,Any}(props)
Object(props::AbstractDict) = Object{typeof(props).parameters[2]}(_clean_dict(props))
Object(::Type{T}, props::AbstractDict) where {T} = Object{T}(props)
Object(::Type{T}, P::ParamType, props::AbstractDict) where {T} = Object{T,P}(props)
#Object{T}() where {T} = Object{T, Any}(Dict{Symbol, T}()) <- this doesn't work (it's defeated by the next line)
Object(; props...) = Object(Dict(props))
Object(::Type{T}; props...) where {T} = Object{T}(; props...)
Object(::Type{T}, P::ParamType; kwargs...) where {T} = Object{T,P}(; kwargs...)
Object{T}(; props...) where T = Object{T}(Dict{Symbol,T}(props))
Object{T,P}(; props...) where {T,P} = Object{T,P}(Dict{Symbol,T}(props))
Object(props::Pair...) = Object(Dict(props...))
Object(::Type{T}, props::Pair...) where {T} = Object{T}(Dict(props))
Object(::Type{T}, P::ParamType, props::Pair...) where {T} = Object{T,P}(Dict(props))

# type conversions
Object(obj::Object) = obj
Object{T,P}(obj::Object) where {T,P} = begin
    typeof(obj) == Object{T,P} && return obj
    proto = getfield(obj, :prototype)
    proto == obj && return Object{T,P}(Dict{Symbol,T}(getfield(obj, :properties)))
    typeof(proto).parameters[1] <: T && return Object{T,P}(proto, getfield(obj, :properties))
    throw(error("prototype with type $(typeof(proto).parameters[1]) is not a subtype of $T"))
end
Object{T}(obj::Object) where {T} = Object{T,typeof(obj).parameters[2]}(obj)
Object(::Type{T}, P::ParamType, obj::Object) where {T} = Object{T,P}(obj)
Object(::Type{T}, obj::Object) where {T} = Object{T}(obj)

# recursive dictionary unwrappers
Object(props::AbstractDict, ::Val{:r}) = begin
    props = _clean_dict(props)
    Object(Dict(k => typeof(v) <: AbstractDict ? Object(v, Val(:r)) : v for (k,v) ∈ props))
end
Object{T}(props::AbstractDict, ::Val{:r}) where {T} = begin
    props = _clean_dict(props)
    Object{T}(Dict{Symbol,T}(k => typeof(v) <: AbstractDict ? Object{T}(v, Val(:r)) : v for (k,v) ∈ props))
end
Object(::Type{T}, props::AbstractDict, ::Val{:r}) where {T} = Object{T}(props, Val(:r))
Object{T,P}(props::AbstractDict, ::Val{:r}) where {T,P} = begin
    props = _clean_dict(props)
    Object{T,P}(Dict{Symbol,T}(k => typeof(v) <: AbstractDict ? Object{T,T}(v, Val(:r)) : v for (k,v) ∈ props))
end
Object(::Type{T}, P::ParamType, props::AbstractDict, ::Val{:r}) where {T} = Object{T,P}(props, Val(:r))

# functor to create an inheriting object
(obj::Object)(::Type{T}, P::ParamType, props::Dict{Symbol,T}) where {T} = Object{T,P}(obj, props)
(obj::Object)(::Type{T}, P::ParamType, props::AbstractDict) where {T} = obj(T, P, Dict{Symbol,T}(_clean_dict(props)))
(obj::Object)(::Type{T}, P::ParamType, props::Pair...) where {T} = obj(T, P, Dict{Symbol,T}(_clean_dict(Dict(props))))
(obj::Object)(::Type{T}, P::ParamType; props...) where {T} = obj(T, P, Dict{Symbol,T}(props))
(obj::Object)(::Type{T}, props::AbstractDict) where {T} = obj(T, typeof(obj).parameters[2], props)
(obj::Object)(::Type{T}, props::Pair...) where {T} = obj(T, typeof(obj).parameters[2], Dict(props...))
(obj::Object)(::Type{T}; props...) where {T} = obj(T, typeof(obj).parameters[2], Dict(props))
#(obj::Object)(props::Dict{Symbol,T}) where {T} = typeof(obj)(obj, props) # <-- Doublecheck this
(obj::Object)(props::Dict{Symbol,T}) where {T} = begin
    NT = typejoin(typeof(obj).parameters[1], typeof(props).parameters[2])
    Object{NT,typeof(obj).parameters[2]}(obj, Dict{Symbol,NT}(props))
end
(obj::Object)(props::AbstractDict{String,T}) where T = obj(_clean_dict(props))
(obj::Object)(props::Pair...) = obj(Dict(props...))
(obj::Object)(; props...) = obj(Dict(props))

# property getters and setters
Base.getproperty(obj::Object{T}, n::Symbol; callerobj=obj) where {T} = begin
    props = getfield(obj, :properties)
    if n ∈ keys(props)
        # for passing callerobj as the first argument to object methods
        (typeof(props[n])<:Function) && return (args...; kwargs...) -> props[n](callerobj, args...; kwargs...)
        return props[n]
    end
    proto = getfield(obj, :prototype)
    proto == obj && return throw(error("type $(typeof(obj)) has no field $n"))
    getproperty(proto, n; callerobj=obj)
end::T
Base.setproperty!(obj::Object{T}, n::Symbol, x) where {T} = begin
    getfield(obj, :lock) && throw(error("object is locked"))
    getfield(obj, :properties)[n] = x
end::T
Base.getindex(obj::Object{T}, n::Union{Symbol, String}) where {T} = getproperty(obj, Symbol(n))::T
Base.setindex!(obj::Object{T}, x, n::Union{Symbol, String}) where {T} = setproperty!(obj, Symbol(n), x)::T
Base.propertynames(obj::Object) = begin
    props = Tuple(keys(getfield(obj, :properties)))
    proto = getfield(obj, :prototype)
    proto == obj && return props
    Tuple(union(props, propertynames(proto)))
end

# other base methods
Base.show(io::IO, obj::Object) = begin
    proto, props, lock = getfield.(Ref(obj), (:prototype, :properties, :lock))
    print(io, summary(obj), "(\nprototype: ", 
        replace(string(proto==obj ? "none" : proto), "\n"=>"\n    "), 
        ",\nproperties: ⟨", replace(string(Tuple(k=>v for (k,v) ∈ props))[2:end-1], "\n"=>"\n    "), "⟩\nlock=$lock)")
end
Base.copy(obj::Object) = (getfield(obj, :prototype) == obj ? 
    typeof(obj)(getfield(obj, :properties)) :
    typeof(obj)(getfield(obj, :prototype), getfield(obj, :properties)))::typeof(obj)
Base.deepcopy(obj::Object) = (getfield(obj, :prototype) == obj ?
    typeof(obj)(copy(getfield(obj, :properties))) :
    typeof(obj)(deepcopy(getfield(obj, :prototype)), copy(getfield(obj, :properties))))::typeof(obj)
# check if b is a prototype of a; check is recursive
"""
<<(a::Object, b::Object)

Checks if a inherits from b (recursively). Example:

julia> b = Object();

julia> a = b();

julia> a<<b
true

julia> b<<a
false
"""
Base.:<<(a::Object, b::Object) = (aproto = getfield(a, :prototype); aproto==a ? false : (aproto==b || aproto<b))
Base.Dict(obj::Object) = getfield(obj, :properties)
# this is not the desired behavior: it flattens, rather than creating nested `Dict`s:
Base.Dict(obj::Object, ::Val{:r}) = Dict(k => typeof(v)<:Object ? Dict(v, Val(:r)) : v for (k,v) ∈ getfield(obj, :properties))

# type `Object` interface methods
getprototype(object::Object) = getfield(object, :prototype)
setprototype!(object::Object, prototype::Object) = begin
    getfield(object, :lock) && error("object is locked")
    typeof(prototype).parameters[1] <: typeof(object).parameters[1] || 
        throw(error("the prototype's value type must be a subtype of the inheritor's value type"))
    prototype << object && throw(error("new prototype must not inherit from object"))
    setfield!(object, :prototype, prototype)
    object
end
setprototype!(object::Object, Nothing) = begin setfield!(object, :prototype, object); object end
Base.keys(obj::Object) = begin
    error("not implemented yet!")
end
Base.values(obj::Object) = begin
    error("not implemented yet!")
end
free(obj::Object) = typeof(obj)(typeof(getfield(obj, :properties))(k=>obj[k] for k ∈ propertynames(obj)))
lock!(obj::Object) = begin
    setfield!(obj, :lock, true)
    obj
end
# zr
end
