# Objects.jl

Dynamic, Static, and Mutable Objects with Prototype Inheritance, Method Membership, and Type Tagging for Julia

Play with it and see what you think. Prototype inheritance is fun!

Implementation and interface subject to change per user input.

## Installation

To install from GitHub:

```julia
] add https://github.com/uniment/Objects.jl
```

## About

The `Objects` module implements a type `Object`. Instances of `Object` have properties that can be casually and easily created, accessed, and changed using dot-syntax.

In addition, `Object`s can inherit traits from each other through prototype inheritance. [Prototype inheritance](https://en.wikipedia.org/wiki/Prototype-based_programming) is a simple object inheritance model most widely known for its use in JavaScript and Lua. These `Object`s behave similarly to JavaScript `Object`s.

Object-specific methods can also be inherited, overridden, and extended. Type inference can be used for polymorphism.

Three subtypes of `Object` are provided: `Static`, `Mutable`, and `Dynamic`.

- Dynamic: maximum flexibility—properties can be added or changed at any time, arbitrarily.
- Static: maximum performance—after creation, properties cannot be changed.
- Mutable: happy medium—properties can be changed at any time, but they cannot be added and their types cannot change.

If left unspecified, the default is `Mutable`. 

## Constructing Fresh Objects

Syntax:

```julia
    Object{[TypeTag]}([ObjectType]; kwargs...)
    Object{[TypeTag]}([ObjectType,] props::AbstractDict[, Val(:r)])
    Object{[TypeTag]}([ObjectType,] props::Generator)
    Object{[TypeTag]}([ObjectType,] obj::Any) 
```

### Initialize and use `Object`s

```julia
mut = Object(x=1, y=2)          # default type is `Mutable`
mut.x + mut.y                   # 3
mut.x = 2
mut.x + mut.y                   # 4
```

Can also access with `[]` syntax:

```julia
@show mut.x
@show mut[:x]
@show mut["x"]
```

### Dynamic and static object types

For `Mutable` objects, can't change property types or add new ones after object construction:

```julia
mut.x = 2.5                     # error
mut.x = "hello"                 # error
mut.z = 3                       # error
```

this is because

```julia
mut isa Object{T,<:Mutable} where T
```

Add type argument of `Static`, `Mutable`, or `Dynamic` to specify object type.

```julia
dyn = Object(Dynamic, x=1, y=2)
dyn.z = 3                       # can change anything at any time
dyn.x + dyn.y + dyn.z           # 6

stc = Object(Static, x=1, y=2)  # can't change anything after creation
stc.x = 2                       # error
```

`Dynamic` is very easy and casual to use, but unfortunately low-performance due to type instability.

### Nested structures

As easy as JSON.

```julia
obj = Object(
    a = [1,2,3],
    b = Object(
        c = "Hello!",
        d = Object()
    )
)
@show obj.b.c                   # "Hello!"
```

### Unpacking Dictionaries

Recursive flag argument `Val(:r)` 

```julia
using TOML
cfg = Object(TOML.parsefile("config.toml"), Val(:r))
```

### Generating Objects

```julia
messages = Object((Symbol(name),"Hello, $name") for name ∈ ["Joe", "Sally", "Mark"]) # can also use (k=>v) pairs
@show messages.Mark
```

### Modeling `Object`s off Arbitrary Composite Types

If its properties are accessible with `.` dot syntax, then it can be `Object`ified.

```julia
struct MyStruct
    a
    b
end
instance = MyStruct(3.14, "Hi there")
obj = Object(instance)
```

## Changing Object Type and Tag

Syntax:

```julia
    Object{[TypeTag]}([ObjectType,] (obj::Object)...)
```

Keep same property values and prototype, but change the object type between `Dynamic`, `Mutable`, or `Static`.

```julia
obj = Object(Mutable, a=1, b=2) # `Mutable` is the default, chosen explicitly here
dyno = Object(Dynamic, obj)     # Create `Dynamic` from `Mutable`
dyno.c = 3
locked = Object(Static, dyno)   # Create `Static` from `Dynamic`
```

### Destructuring Objects

`Object`s can be destructured like any other object with properties:
```julia
obj = Object(x=1, y=2, z=3)
let (; x, y) = obj
    #= do stuff with locally scoped definitions of x and y =#
end
```


## Member Method Encapsulation

An `Object` can have member-specific methods:

```julia
obj = Object(Dynamic, a=2)
computefunc = function(this, b) this.a * b end
obj.compute = computefunc
@show obj.compute(3)            # 6
```

Calling `obj.compute` passes `obj` in as the first argument.

Implementation-wise, accessing `obj.compute` yields a closure which captures `obj` and passes it as the first argument to `computefunc`.

### Method Argument Polymorphism

```julia
obj = Object(a=1, b=2, 
    func = let
        function f(this) this.a + this.b end
        function f(this, x::Int) this.a + x end
        function f(this, x::Float64) x end
    end
)
@show obj.func()                # 3
@show obj.func(5)               # 6
@show obj.func(2.5)             # 2.5
```

### Storing Functions

If it's desired for an object to store a function for later retrieval, then store a reference to it with `Ref` and access it with dereferencing syntax `[]`:

```julia
obj = Object(storedfunc = Ref(x -> x^2))
f = obj.storedfunc[]            # retrieves the function as-is
@show f(5)                      # 25
```

**Note**

Because every function has a different type signature, you cannot mutate the member methods of `Mutable` `Object`s. And because `Ref` also carries the referenced object's type signature, you can't mutate references to functions either.

```julia
obj.storedfunc[] = x -> x^3     # error
```

To change some functions but keep the other properties and methods, either use splatting or inheritance, or use a `Dynamic` object type (like the example with `computefunc` above). 

## Inheritance

Syntax:

```julia
    (proto::Object)([ObjectType;] props...)
    (proto::Object)([ObjectType,] (obj::Object)...) 
```

Every `Object` instance is a functor, and calling it creates a new `Object` for which it is a prototype. Extra keyword arguments specify the new object's own properties. Alternatively, splat in another object.

The new object has the same type as its prototype, unless otherwise specified. Think of it like the prototype is picking up new tricks and being repackaged into a new object.

```julia
obj = Object(a=1, b=2)              # original object
@show obj.a, obj.b                  # (1, 2)
newObj = obj(b=3, c=4)              # newObj inherits a and b, and overrides b
@show newObj.a, newObj.b, newObj.c  # (1, 3, 4)
obj.a, obj.b = 2, 1                 # change in obj.a passes through to newObj, obj.b does not
@show newObj.a, newObj.b, newObj.c  # (2, 3, 4)
newNewObj = newObj(c=5, d=6)
@show [newNewObj[s] for s ∈ (:a,:b,:c,:d)]    # [2, 3, 5, 6]
```

Implementation-wise, `newObj` stores a reference to its prototype `obj`; all properties and methods of `obj` are accessible to `newObj`, and any changes to `obj` will be reflected by `newObj`. `newNewObj` stores a reference to `newObj`.

Note that because these `Object`s are the default `Mutable`, any properties not declared as "own" properties cannot be changed. This means that `newObj.a` cannot be changed, since it was never declared as its own property, and it will always reflect `obj.a`. To make arbitrary changes use `Dynamic` objects instead, and to lock `obj` from changing use a `Static` object instead.

Because prototypes are inherited by storing a reference, it is possible to build inheritance chains where traits are replicated and pass through many inheriting objects.

### Multiple Inheritance

Strictly speaking, multiple inheritance isn't implemented. But you can splat objects together to compose a new object.

```julia
parent = Object(firstname="Julia", lastname="Smith", hobby="Fishing")
friend = Object(hobby="Skiing")
child  = parent(friend...)(firstname="Kevin")

@show child.firstname, child.lastname, child.hobby    
# from self, inherited from parent, and adopted from friend
```

Inheritance comes primarily from parent, but friend's preferences get splatted in and override parent's.

Changes in `parent.lastname` are reflected in `child`, but changes in `friend.hobby` are not.

### Splatting Objects

To create a new independent object with the same properties but breaking the inheritance chain, splat the object:

```julia
libertine = Object(child...)    # free Kevin
```

another example:

```julia
obj = Object(a=1, b=2)
newObj = Object(obj...)
@show (obj...,) == (newObj...,) # true
@show obj == newObj             # false
@show Dict(obj...)              # splat into a dictionary
```

Try this:

```julia
a = Object(i=1, j=2);
b = Object(j=3, k=4);
c = Object(k=5, l=6);
d = Object(l=7, m=8);
e = Object(m=9, n=10);

@show x = a(b...)(c...)(d...)(e...)
@show y = Object(a..., b..., c..., d..., e...) # objects splatted later override earlier objects
@show z = Object(x...)
@show Dict(x) == Dict(y)
```

## Type Tagging for Type Dispatch

`Object`s have a type tag which doesn't affect `Object` behavior per se, but allows methods to specialize on multiple dispatch. This tag can be a `Type`, a `Symbol`, a `Tuple`, a number... anything for which `isbits` evaluates to true. For example:

```julia
a = Object{:pos}(x=5)
b = Object{:neg}(x=5)
g(obj::Object{:pos}) =  obj.x^2
g(obj::Object{:neg}) = -obj.x^2

@show g(a), g(b)                # (25, -25)
```

This type tag is automatically inherited.

```julia
@show g(a(x=2)), g(b(x=2))      # (4, -4)
```

To change type while *copying* other traits, keeping same prototype:

```julia
a_neg = Object{:neg}(a)
```

To change type while *inheriting* other traits:
```julia
a_neg = Object{:neg}(a())
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
@show tommy.punish(), jeff.punish()
```

### Method Specialization using Type Hierarchy

```julia
# type hierarchy
abstract type Animal end
abstract type Human <: Animal end
abstract type Dog <: Animal end

# prototypes
const Prototypes = Object(Dynamic)
Prototypes.Animal = Object{Animal}(Static, eyes=2, legs=4, size=:large)
Prototypes.Human = Object{Human}(Prototypes.Animal)(Static, legs=2, artificial_legs=0, size=:medium)
Prototypes.Dog = Object{Dog}(Prototypes.Animal)(Static, size=:small)

# defining a method extends naturally to subtypes
getspeed(animal::Object{<:Animal}) = animal.legs
# defining a method for the human subtype
getspeed(person::Object{<:Human}) = person.legs + person.artificial_legs

let (; Animal, Human, Dog) = Prototypes
    sparky = Dog()          
    @show getspeed(sparky)          # 4

    joe = Human(Dynamic, legs=1);   # lost in a tragic automobile accident
    @show getspeed(joe)             # 1

    joe.artificial_legs = 1         # modern technology
    @show getspeed(joe)             # 2
end
```

Notice that type hierarchy is defined using a different system than that which defines inheritance.

## Performance Tip

Obviously `Static` will be fastest at runtime and `Dynamic` slowest. Because accessing elements from a `Dynamic` object is type-unstable, calling functions on their values can be slow.

If using `Dynamic` objects is desired anyway, their performance can be helped by adding type assertions whenever their values are being fed into performance-critical functions.
```julia
obj = Object(Dynamic, a=1, b=2)
f(x) = x.a + 1
@code_warntype f(obj)               # output is type-unstable
g(x) = x.a::Int + 1   
@code_warntype g(obj)               # output is type-stable
```

## Quirks

When accessing a member method, a closure is returned which captures the object and passes it as a first argument:
```julia
obj = Object(a=1, b=2, f=this->this.a+this.b)
somevar = obj.f
@show somevar()                     # 3
```

Same when destructuring an object:
```julia
(; f) = obj
@show f()                           # 3
```

But when splatting an object, the original function is given (because we want to be able to splat the function into new objects as a member method)
```julia
Dict(obj...)[:f]()                  # error
@show Dict(obj...)[:f](Object(a=1, b=2))    # 3
```

zr