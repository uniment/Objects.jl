# Objects.jl

Static, Mutable, and Dynamic Objects with Prototype Inheritance and Method Membership

This project is currently in "toy" phase. Play with it and let me know what you think. Prototype inheritance is fun!

## Installation

To install from GitHub:

```julia
] add https://github.com/uniment/Objects.jl
```

## About

`Objects` implements an object type `Object`. Instances of `Object` have properties that can be casually and easily created, changed, and accessed using dot-syntax.

In addition, `Object`s can inherit traits from each other through prototype inheritance. [Prototype inheritance](https://en.wikipedia.org/wiki/Prototype-based_programming) is a simple and common object inheritance model most widely known for its use in JavaScript and Lua.

Object-specific methods can also be inherited, overridden, and extended. Type inferencing can be used for polymorphism.

Three different types of `Object` are provided: `Static`, `Mutable`, and `Dynamic`. If left unspecified, the default is `Mutable`. While `Dynamic` objects can be changed arbitrarily at will, `Static` objects cannot be changed after creation. `Mutable` objects have properties that can be changed after creation, but new properties cannot be added and property types cannot be changed.

## Constructing Objects

```julia
    Object{[Param]}([Type]; kwargs...)
    Object{[Param]}([ObjectType,] props::AbstractDict[, Val(:r)])
    Object{[Param]}([ObjectType,] props::Generator)
    Object{[Param]}([ObjectType,] obj::Object...)
    Object{[Param]}([ObjectType,] obj::Any) 
```

### Initialize and use `Object`s

```julia
mut = Object(x=1, y=2)          # default is mutable
mut.x + mut.y                   # 3
mut.x = 2
mut.x + mut.y                   # 4
mut.z = 3                       # error
```

### Dynamic and static object types

```julia
dyn = Object(Dynamic, x=1, y=2)
dyn.z = 3                       # can change anything at any time
dyn.x + dyn.y + dyn.z           # 6

stc=Object(Static, x=1, y=2)    # can't be changed at all after creation
stc.x = 2                       # error
```

`Dynamic` is very easy and casual to use, but unfortunately low-performance due to type instability.

### Nested structures

```julia
obj = Object(
    a = [1,2,3],
    b = Object(
        c = "Hello!",
        d = Object()
    )
)
obj.b.c                         # "Hello!"
```

### Unpacking Dictionaries

Recursive with argument `Val(:r)` 

```julia
using TOML
cfg = Object(TOML.parsefile("config.toml"), Val(:r))
```

### Generating Objects

```julia
obj = Object((k,i^2) for (i,k) ∈ enumerate((:a,:b,:c,:d)))
obj.a, obj.b, obj.c, obj.d
```

### Splatting Objects

Flattens inheritance chain and copies object

```julia
newObj = Object(obj...)
(obj...,) == (newObj...,)       # true
obj == newObj                   # false
```

### Changing Object Type

Keep object structure and values, but change the object type between `Dynamic`, `Mutable`, or `Static`.

```julia
obj = Object(Mutable, a=1, b=2) # Mutable is the default
dyno = Object(Dynamic, obj)
dyno.c = 3
locked = Object(Static, dyno)
```

### Modeling Objects off Arbitrary Objects

If it can be accessed with `.` dot syntax, it can be turned into an `Object`.

```julia
struct MyStruct
    a
    b
end
instance = MyStruct(3.14, "Hi there")
obj = Object(instance)
```

## Member Methods

An `Object` can have member-specific methods:

```julia
obj = Object(Dynamic, a=2)
computefunc = function(this, b) this.a * b end
obj.compute = computefunc
obj.compute(3)                  #-> 6
```

Calling `obj.compute` passes `obj` in as the first argument.

Implementation-wise, accessing `obj.compute` yields an closure which captures `obj` and passes it as the first argument to `computefunc`.

### Method Argument Polymorphism

```julia
obj = Object(a=1, b=2, func = let
    function f(this) this.a + this.b end
    function f(this, x::Int) this.a + x end
    function f(this, x::Float64) x end
end)
obj.func()                      # 3
obj.func(5)
obj.func(2.5)
```

### Storing Functions

If it's desired for an object to store a function for later retrieval, then store a reference to it with `Ref` and to access it use the dereferencing syntax `[]`:

```julia
obj = Object(storedfunc = Ref(computefunc))
obj.storedfunc[]                # retrieves the function with no closure
```

### Note

Because every function has a different type signature, you cannot mutate the member methods of `Mutable` `Object`s. To change only a few methods but keep the other properties and methods, use splatting or inheritance. 

## Inheritance

```julia
    (proto::Object)([ObjectType;] props...)
    (proto::Object)([ObjectType,] obj::Object...) 
```

Every `Object` instance is a functor; calling it creates a new `Object` for which it is a prototype. Extra keyword arguments specify the object's own properties. Alternatively, splat in another object's properties.

```julia
obj = Object(a=1, b=2)
newObj = obj(b=3, c=4)
(obj.a, obj.b)                  # (1, 2)
(newObj.a, newObj.b, newObj.c)  # (1, 3, 4)
obj.a = 2
(newObj.a, newObj.b, newObj.c)  # (2, 3, 4)
```

Implementation-wise, `newObj` stores a reference to its prototype `obj`; all properties and methods of `obj` are accessible to `newObj`, and any changes to `obj` will be reflected by `newObj`.

Note that because these `Object`s are `Mutable`, any properties not declared as "own" properties cannot be changed. This means that `newObj.a` cannot be changed, since it was never declared as its own property, and it will always reflect `obj.a`. To make arbitrary changes use `Dynamic` objects.

Because inheriting objects store a reference to their prototype, it is possible to build inheritance chains where traits are replicated and pass through many inheriting objects.

### Multiple Inheritance

```julia
parent = Object(firstname="Kevin", lastname = "Smith", hobby="Fishing")
friend = Object(hobby="Skiing")
child  = parent(friend...)(firstname="Catherine")

child.firstname, child.lastname, child.hobby    
# from self, inherited from parent, and adopted from friend
```

### Breaking Inheritance

To create a new independent object with the same properties but breaking the inheritance chain, splat the object:

```julia
libertine = Object(newObj...)
```

## Type Dispatch

`Object`s have a second type parameter to allow specialized methods for multiple dispatch. For example:

```julia
a = Object{:pos}(x=5)
b = Object{:neg}(x=5)
g(obj::Object{:pos}) =  obj.x^2
g(obj::Object{:neg}) = -obj.x^2

g(a), g(b)                      # (25, -25)
```

This method behavior automatically extends to inheriting objects, as long as they maintain the same type parameterization signature.

```julia
g(a(x=2)), g(b(x=2))            # (4, -4)
```

To break type while inheriting other traits:

```julia
aneg = Object{:neg}(a)
```

### Method Object Type Polymorphism

```julia
traits = Object(age=0, name="", punish = let 
    function f(this::Object{:child}) "stand in corner for $(this.age) minutes" end
    function f(this::Object{:teen}) "scold sternly for $(this.age) seconds" end
    function f(this::Object{:adult}) "express disappointment for $(this.age) years" end
end)
tommy = Object{:child}(traits)(name="tommy", age=5)
jeff  = Object{:adult}(traits)(name="jeff", age=25)
tommy.punish(), jeff.punish()
```

### Method Specialization using Type Hierarchy

```julia
# type hierarchy
abstract type Animal end
abstract type Human <: Animal end
abstract type Child <: Human end

# prototypes
const Prototypes = Object(Dynamic)
Prototypes.Animal = Object{Animal}(Static, eyes=2, legs=4, size=:large)
Prototypes.Human = Object{Human}(Prototypes.Animal)(Static, legs=2, artificial_legs=0, size=:medium)
Prototypes.Child = Object{Child}(Prototypes.Human...)(Static, size=:small)

# constructors
Animal(a...; kw...) = Prototypes.Animal(Dynamic, a...; kw...)
Human(a...; kw...) = Prototypes.Human(Dynamic, a...; kw...)
Child(a...; kw...) = Prototypes.Child(Dynamic, a...; kw...)

# defining a method extends naturally to subtypes
getspeed(animal::Object{<:Animal}) = animal.legs

getspeed(Animal())                                  #->4

joe = Human(legs=1);                                # lost in a tragic automobile accident
getspeed(joe)                                       #-> 1

joe.artificial_legs = 1                             # modern technology
getspeed(person::Object{<:Human}) = person.legs + person.artificial_legs
getspeed(joe)                                       #-> 2

```

Notice that type hierarchy is defined using a different system than that which defines inheritance.