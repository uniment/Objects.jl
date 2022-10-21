# Objects.jl

Dynamic Objects with Prototype Inheritance and Method Membership

## Installation

To install from GitHub:

```julia
] add https://github.com/uniment/Objects.jl
```

## About

`Objects` implements a dynamic object type `Object`. Instances of `Object` have properties that can be casually and easily created, changed, and accessed using dot-syntax.

In addition, `Object`s can inherit traits from each other through prototype inheritance. To the uninitiated, [prototype inheritance](https://en.wikipedia.org/wiki/Prototype-based_programming) is a simple and common object inheritance model most widely known for its use in JavaScript and Lua.

Object-specific methods can also be inherited, overridden, and extended.

## Basic Usage

An `Object` can be initialized, modified, and used like so:

```julia
obj = Object(Any)                                   # initialize empty Object
obj.a = 1
obj.b = 2
obj.a + obj.b == 3                                  #-> true
```

Specifying the datatype is necessary when initializing an empty `Object`. If an `Object` is initialized with properties, then specifying the datatype is optional:

```julia
typeof(Object(; a=1, b=2))                          #-> Object{Int64, Any}
typeof(Object(; a=1, b=2.0))                        #-> Object{Real, Any}
typeof(Object(Any; a=1, b=2))                       #-> Object{Any, Any}
```

Using the `Any` type provides maximum flexibility and dynamic behavior at the expense of performance. Attempting to assign an unsupported type will cause an error:

```julia
obj = Object(Number; a=1, b=2)
obj.c = π                                           #-> π = 3.1415926535897...
obj.d = "Hello, world!"                             #-> MethodError: Cannot `convert` an object of type String to an object of type Number
```

Alternatively, `Object`s can be initialized with `Pair`s or `Dict`s:

```julia
# these are all the same:
Object(; a=1, b=2)
Object(Dict("a"=>1, "b"=>2))
Object(Dict(:a=>1, :b=>2))
Object(:a=>1, :b=>2)
```

Creating nested structures is easy and natural:

```julia
obj = Object(;
    a = [1, 2, 3],
    b = true,
    c = Object(;
        x=1, y=2, z=3
    )
)
obj.c.z                                             #-> 3
```

If a dictionary represents a nested structure, such as from a config file, then `Object` can be called with the argument `Val(:r)` to unpack the diectionary recursively:

```julia
using TOML
cfg = Object(TOML.parsefile("config.toml"), Val(:r))
```

## Member Methods
An `Object` can have member-specific methods:

```julia
obj = Object(Any, a=2)
computefunc = function(this, b) this.a * b end
obj.compute = computefunc
obj.compute(3)                                      #-> 6
```

`obj.compute` is a member method of `obj`, and calling it passes `obj` in as the first argument.

Implementation-wise, accessing `obj.compute` yields an anonymous function which captures the object `obj`, and passes it as the first argument to `computefunc`. In other words:

```julia
obj.compute ≠ computefunc                           #-> true
computefunc(obj, 3) == obj.compute(3)               #-> true
```

If it's desired for an object to store a function for later retrieval, then store a reference to it with `Ref` and to access it use the dereferencing syntax `[]`:

```julia
obj.storedfunc = Ref(computefunc)
obj.storedfunc[] == computefunc                     #-> true
```

## Inheritance
Every `Object` instance is a functor, and calling it creates a new `Object` for which it is a prototype. For example:

```julia
newObj = obj(; a=3, b=4)
newObj.compute(3)                                   #-> 9
obj.compute(3)                                      #-> 6 (still)
newObj.compute(newObj.b)                            #-> 12
```

Three points of note:
1. `newObj` inherits properties and methods such as `a` and `compute` from its prototype `obj`. Calling the inherited method now acts on `newObj` instead of `obj`.
2. `newObj` overrides the inherited property `obj.a==2` with its own value `newObj.a==3`.
3. `newObj` extends a new property `b` which does not exist in its prototype.

Implementation-wise, `newObj` stores a reference to its prototype `obj`; all properties and methods of `obj` are accessible to `newObj`, and any changes to `obj` will be reflected by `newObj`. For example:

```julia
obj.c = 5
newObj.c                                            #-> 5
```

Just like inherited properties, inherited methods can be overridden on an instance-by-instance basis. For example:
```julia
newObj2 = obj()
newObj2.compute = function(this, b) this.a^b end
newObj2.compute(3)                                  #-> 8
obj.compute(3)                                      #-> 6 (still)
```

Because inheriting objects store a reference to their prototype, it is possible to build inheritance chains where traits are replicated across many inheriting objects.

## Type Dispatch

`Object`s have a second type parameter to allow specialized methods for multiple dispatch. For example:

```julia
a = Object(Int, :pos, x=5)
b = Object(Int, :neg, x=5)
g(obj::Object{T,:pos} where T) =  obj.x^2
g(obj::Object{T,:neg} where T) = -obj.x^2

g(a)                                                #->  25
g(b)                                                #-> -25
```

This method behavior automatically extends to all inheriting objects, as long as they maintain the same type parameterization signature.

It can even be used for type hierarchies (gentle reminder that these are usually less performant than proper `struct`s):

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

getspeed(Animal())                                  #->4

joe = Human(legs=1);                                # lost in a tragic automobile accident
getspeed(joe)                                       #-> 1

joe.artificial_legs = 1                             # modern technology
getspeed(person::HumanType) = person.legs + person.artificial_legs
getspeed(joe)                                       #-> 2

emily = Child(eyes=1)                               # it was all fun and games until she poked her eye out
emily.eyes                                          #-> 1
```

## Interface Methods
The following methods are currently provided:
```julia
Dict(obj)                           # converts `obj`'s own properties to a dictionary
Dict(obj, Val(:r))                  # converts `obj`'s own properties with nested `Object`s to nested dictionaries recursively
getprototype(obj)                   # self-explanatory
setprototype!(obj, proto)           # sets `proto` as `obj`'s prototype to inherit from.
setprototype!(obj, nothing)         # removes `obj`'s prototype
obj<<proto                          # returns `true` if `proto` is a prototype to `obj` (recursive)
free(obj)                           # replicates `obj` as an independent object which doesn't inherit from any prototype
lock!(obj)                          # locks `obj` and prevents any further changes
```

## The Good and Bad

In comparison to declaring `struct` composite types, using `Object` is faster, easier, and more casual. It's often more natural to focus on building out a single object instance and then simply make other objects that inherit its traits, compared to architecting upfront the proper data structure that a class of such objects should have.

Furthermore, there are cases where it's desired for individual instances to have different properties and methods than the broader class to which they belong, and dynamic objects with inheritance make this easy. A common critique is that it's *too* easy.

However, `Object`s are much less performant than `struct`s, especially when carrying abstract types such as `Any`.

`Objects` are more customizable and easier to think through, but slower; properties and behaviors can be individualized to specific instances. `struct`s are faster but less customizable and require more deliberation; the same properties and behaviors must be common to all members of the type.

What are `Object`s good for? Brainstorming and rapid development. Once an idea has been worked out, and the extra performance is needed, the data structure can be changed to a `struct`.

zr