# Objects.jl

Dynamic, Static, and Mutable Objects with Composition, Template Replication, Prototype Inheritance, Method Membership, and Type Tagging for Julia (whew!)

Play with it and see what you think. Prototype inheritance is fun!

Implementation and interface unstable. This is experimental; consider it a fancy digital toy for now. 

## Installation

To install from GitHub:

```julia
] add https://github.com/uniment/Objects.jl
```

and of course,
```julia
using Objects
```

## About

Instances of `Object` have properties that can be casually and easily created and composed, and then accessed and changed using dot-syntax.

Once an `Object` has been carved into the desired form, it can serve as a "template" for replication, using efficient construction techniques to create clones with the same datatypes but with custom values.

In addition, `Object`s can inherit traits from other `Object`s through prototype inheritance. [Prototype inheritance](https://en.wikipedia.org/wiki/Prototype-based_programming) is a simple object inheritance model most widely known for its use in JavaScript and Lua. These `Object`s behave similarly to JavaScript's `Object`s, but with the benefits of strict inferred typing and immutability when desired.

Object-specific methods can be inherited, overridden, and extended. Objects can also be tagged with optional types, allowing multiple dispatch to implement polymorphism.

## Why

Composing objects on an ad-hoc basis, instead of architecting classes and hierarchies up-front, can be a very efficient workflow: especially when experimenting on a new project, or when sculpting and customizing complex objects.

It's also just fun. Nobody likes `ERROR: invalid redefinition of constant MyStruct`. (ikik revise.jl)

## Object Storage Types

Three subtypes of `Object` storage are provided: `Dynamic`, `Static`, and `Mutable`.

- Dynamic: maximum flexibility—properties can be added or changed at any time, arbitrarily.
- Static: maximum performance—after construction, properties cannot be changed.
- Mutable: happy medium—properties can be changed at any time, but they cannot be added and their types cannot change.

If left unspecified, the default is `Mutable`. 

## Interface

```julia
# constructing from scratch
    Object{[TypeTag]}([StorageType] [; kwargs...])
# changing type ("converting")
    Object{[TypeTag]}([StorageType,] obj::Object [; kwargs...])
    Object{[TypeTag]}([StorageType,] obj::Any [; kwargs...])
    Object{[TypeTag]}([StorageType,] props::AbstractDict [; kwargs...])
# constructing from template
    (template::Object)([; props...])
# prototype inheritance
    Prototype{[TypeTag]}([StorageType,] proto::Object [; kwargs...])
```

## Composing Objects

Syntax:
```julia
    Object{[TypeTag]}([StorageType] [; kwargs...])
```

Easy.

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

For `Mutable` objects, you can't change property types or add new ones after object construction:

```julia
mut.x = 2.5                     # error
mut.x = "hello"                 # error
mut.z = 3                       # error
```

Add type argument of `Static`, `Mutable`, or `Dynamic` to specify object type.

```julia
dyn = Object(Dynamic, x=1, y=2) # can change anything at any time
dyn.z = 3                       
dyn.x + dyn.y + dyn.z           # 6

stc = Object(Static, x=1, y=2)  # can't change anything after creation
stc.x = 2                       # error
```

`Dynamic` is very easy and casual to use, but unfortunately type instability causes lower performance. Good for hacking and playing, throwing stuff together before worrying about formalizing, but not so good for efficient runtime. 

`Dynamic` flexibility can also be dangerous when incorporated into large complicated inheritance structures; once things begin settling down and getting sorted out, start moving structures to `Mutable` or `Static`, or create composite types with `struct`.

### Nested structures

As easy as JSON.

```julia
obj = Object(
    a = [1,2,3],
    b = Object(
        c = "Hello!",
        d = Dict(string(k)=>Char(k) for k = 1:255)
    )
)
@show obj.b.c                   # "Hello!"
```

### Splatting Dictionaries, Generators, and Objects

Iterable collections should be splatted into keyword arguments. Later arguments override earlier ones.

Dictionaries:

```julia
obj = Object(; a=2, Dict(:a=>1, :b=>2)..., b=3)
```

Generators:

```julia
messages = Object(; ((Symbol(name) => "Hello, $name") for name ∈ ["Joe", "Sally", "Mark"])..., Mark="G'day, Mark")
@show messages.Mark
```

Other `Object`s:

```julia
obj = Object(a=1, b=2)
newObj = Object(; obj...)
@show (obj...,) == (newObj...,) # true
@show obj == newObj             # false
@show Dict(obj...)              # splat `obj` into a dictionary (as regular args, not keyword)
```


### Modeling Objects off Arbitrary Composite Types

Syntax:

```julia
    Object{[TypeTag]}([StorageType,] obj::Any [; kwargs...])
```

If its properties are accessible with `.` dot syntax, then it can be `Object`ified.

```julia
struct Test1 a; b end
test1 = Test1('🐢', "Hello")
obj1 = Object(test1)
```

Unfortunately, changes to an `Object`ified mutable struct won't be reflected:

```julia
mutable struct Test2 a; b end
test2 = Test2('🐢', "Hola")
obj2 = Object(test2)
test2.a = '🐇'
obj2.a ≠ test2.a
```
Maybe that can be changed one day, that could be cool idk

You can add and override parameters by splatting in more or with keyword arguments:

```julia
obj3 = Object(test1; Dict(:b=>'🐢')..., c='🐢')
@show (obj3...,)                # turtles all the way down
```

`Object`ifying arbitrary composite types is not recursive, for hopefully obvious reasons.


### Recursive Dictionary Object Construction

Syntax:
```julia
    Object{[TypeTag]}([StorageType,] props::AbstractDict [; kwargs..
```

If a dictionary is not splatted, then it will be assumed that it is being used to hold a hierarchical structure with nested dictionaries. A new `Object` will be created recursively, with each nested dictionary being represented as a nested `Object`.

```julia
using TOML
config = Object(TOML.parsefile("config.toml"))
```

The inverse recursive operation can be performed with
```julia
convert(Dict, config)
```

Note that splatting is not recursive; these are special methods for converting between nested dictionaries and `Object`s.


## Copying Object into New Type and Tag

Syntax:

```julia
    Object{[TypeTag]}([StorageType,] obj::Object [; kwargs...])
```

Keep same property values and prototype, but change the object type between `Dynamic`, `Mutable`, or `Static`.

```julia
obj = Object(Mutable, a=1, b=2) # `Mutable` is the default, chosen explicitly here
dyno = Object(Dynamic, obj)     # Create `Dynamic` from `Mutable`
dyno.c = 3
locked = Object(Static, dyno)   # Create `Static` from `Dynamic`
```

## Destructuring Objects

`Object`s can be destructured like any other object with properties:
```julia
obj = Object(x=1, y=2, z=3)
let (; x, y) = obj
    @show x + y
end
```

## Member Method Encapsulation

An `Object` can have member-specific methods:

```julia
obj = Object(Dynamic, a=2)
computefunc = function(self, b) self.a * b end
obj.compute = computefunc
@show obj.compute(3)            # 6
```

Calling `obj.compute` passes `obj` in as the first argument.

Implementation-wise, accessing `obj.compute` yields a closure which captures `obj` and passes it as the first argument to `computefunc`.

### Method Argument Polymorphism

Use the `let` keyword to create local scope to define the flavors of a function, and make it a property of the object. Outside that local scope, the name given to the polymorphic function is invalid.

```julia
obj = Object(a=1, b=2, 
    func = let
        function f(self) self.a + self.b end
        function f(self, x::Int) self.a + x end
        function f(self, x::Float64) x end
    end
)
@show obj.func()                # 3
@show obj.func(5)               # 6
@show obj.func(2.5)             # 2.5
```

Of course, you can make the method have global scope too, if desired.

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

To change some functions but keep the other properties and methods, either use splatting or inheritance to construct a wholly new object, or use a `Dynamic` object type (like the example with `computefunc` above). 

## Constructing from Templates

Syntax:
```julia
    (template::Object)([; props...])
```

Every `Object` instance is a functor, and calling it creates a new `Object` for which it serves as a template. Example:
```julia
Template = Object(Static, a=0.0, b=0.0)
obj = Template(a=2.5)
@show ownpropertynames(obj)
```

The newly constructed object has exactly the same property names and types as the template; any that are not specified assume default values as specified by the template. Attempting to add properties or change their type will result in errors.

For example:

```julia
obj = Template(a=1)
@show obj.a                     # 1.0, not 1
Template(c=1)                   # error
```

So notice that unlike the other construction techniques, using a template is much more restrictive. Compared with other composition techniques it comes with speed and type stability benefits though.

See bottom for some benchmarking.

## Prototype Inheritance

Syntax:
```julia
    Prototype{[TypeTag]}([StorageType,] proto::Object [; kwargs...])
```

Create an object using `proto` as a prototype. The new object defaults to the same type as its prototype, unless otherwise specified. Think of it like the prototype is picking up new tricks and being repackaged into a new object.

```julia
obj = Object(a=1, b=2)              # original object
@show obj.a, obj.b                  # (1, 2)
newObj = Prototype(obj, b=3, c=4)   # newObj inherits a and b, and overrides b
@show newObj.a, newObj.b, newObj.c  # (1, 3, 4)
obj.a, obj.b = 2, 1                 # change in obj.a passes through to newObj, obj.b does not
@show newObj.a, newObj.b, newObj.c  # (2, 3, 4)
newNewObj = Prototype(newObj, c=5, d=6)
@show [newNewObj[s] for s ∈ (:a,:b,:c,:d)]    # [2, 3, 5, 6]
```

Implementation-wise, `newObj` stores a reference to its prototype `obj`; all properties and methods of `obj` are accessible to `newObj`, and any changes to `obj` will be reflected by `newObj`. `newNewObj` stores a reference to `newObj`.

Note that because these `Object`s are the default `Mutable`, any properties not declared as "own" properties cannot be changed. This means that `newObj.a` cannot be changed, since it was never declared as its own property, and it will always reflect `obj.a`. To make arbitrary changes use `Dynamic` objects instead, and to lock `obj` from changing use a `Static` object instead.

Because prototypes are inherited by storing a reference, it is possible to build inheritance chains where traits are replicated and pass through many inheriting objects.

### Fun Note

You can make an object which is *somewhat* static, and *somewhat* mutable, using inheritance:
```julia
a = Object(Static, a=1)
b = Prototype(Mutable, a, b=2)
c = Prototype(Static, b, c=3)
@show (c...,)
```
Object `c` has three accessible properties: `c.a`, `c.b`, and `c.c`. Among these, only `c.b` is mutable by changing `b.b`.
```julia
b.b = 0
@show (c...,)
```

### Multiple Inheritance

Strictly speaking, multiple inheritance isn't implemented. But it's easy to splat objects together to compose a new object that takes traits from multiple objects.

```julia
parent = Object(firstname="Jeanette", lastname="Smith", hobby="Fishing")
friend = Object(hobby="Skiing")
child  = Prototype(parent; friend..., firstname="Kevin")

@show child.firstname, child.lastname, child.hobby    
# from self, inherited from parent, and adopted from friend
```

Inheritance comes primarily from parent, but friend's preferences get splatted in and override parent's.

Changes in `parent.lastname` are reflected in `child`, but changes in `friend.hobby` are not.

### Breaking Inheritance by Splatting Objects

To create a new independent object with the same properties but breaking the inheritance chain, splat the object:

```julia
libertine = Object(; child...)    # free Kevin from Jeanette
```

Try this:

```julia
a = Object(i=1, j=2);
b = Object(j=3, k=4);
c = Object(k=5, l=6);
d = Object(l=7, m=8);
e = Object(m=9, n=10);

@show x = Prototype(Prototype(Prototype(Prototype(a; b...); c...); d...); e...)
@show y = Object(; a..., b..., c..., d..., e...) # objects splatted later override earlier objects
@show z = Object(; x...)
@show Dict(x) == Dict(y)
```

### Design Pattern: Setting Prototype and Default Traits

Typically, you want objects of a certain class to share common behaviors and perhaps some set of properties, and to have a remaining set of personalizable traits that are instance-specific and possibly mutable.

The shared behaviors can obviously be included using a prototype.

As for the traits, defaults can be splatted in as a template, and then further overridden on an instance-by-instance basis. They can serve as placeholders, setting a) which traits will be personalized, b) reasonable defaults, and c) what datatypes they will hold. Example:

```julia
Person = Object(
    arms=2, 
    legs=2, 
    talk=function(self) self.age > 5 ? :loud : :quiet end,
    traits = Object(Static, 
        age=0,      # years
        height=0.0, # centimeters
        siblings=0, # 
        name=""
    )
)

amy = Prototype(Person; Person.traits..., name="Amy") # Amy hasn't been born yet and currently only has a name
amy.height = 45.5; # Amy has now been born, but is still zero years old
@show amy
@show amy.talk()
```

The type of `Person.traits` doesn't matter here because it's just splatted in, other than for how quickly it can be splatted.

Notice how `Person.traits` serves as a placeholder to set default personal values and their types. This allows `Mutable` instances to have their personalizable traits updated after construction, and `Static` instances can have default values for traits that might otherwise be left unspecified.

Additional note when using `Mutable` and `Static` types: the resulting object type matters because when the object is passed to a function, the function is compiled to that type. When using the same prototype and default traits, the object type is fully consistent (even down to the argument ordering!). This means that functions that have been compiled for one instance, don't have to be recompiled for additional instances.

```julia
joe = Prototype(Person; Person.traits..., name="Joe", age=45, siblings=3)
@show joe.talk()
@show typeof(joe)
@show typeof(joe) == typeof(amy)
```

**a note**

After a mutable `Object` has been constructed, its property types must remain consistent. However, arbitrary property types can be set during construction. *This applies to overridden types too*. For example, if `joe`'s `age` is set to `45.5`, then it overrides what was an `Int` by default with a floating point number, and `joe`'s type is no longer the same as `amy`'s.

This will usually not cause problems of functionality, but it can cause the functions to be recompiled for different data types.

One can also create objects with the same properties, but in different orders, and these will also cause functions to be recompiled.

Thankfully, in the cases where it actually matters (i.e. lots of repetition), chances are that the objects will be created systematically and will have a single ordering anyway. So it's not a big deal.

It's fun to see though, that although something like ordering of keyword arguments doesn't matter to the programmer, it matters to the computer. That's why `struct`s have a specific ordering, and force the programmer to follow a single ordering. Most of the time it doesn't matter, and `Object`s free the programmer to be so whimsical, but on the occasion when it does matter...

### Design Pattern: Adapters

use ur imaginatino oy


## Type Tagging for Multiple Dispatch

`Object`s have an optional type tag which doesn't affect `Object` behavior per se, but allows methods to specialize on multiple dispatch. This tag can be a `Type`, a `Symbol`, a `Tuple`, a number... anything for which `isbits` evaluates to true. For example:

```julia
a = Object{:pos}(x=5)
b = Object{:neg}(x=5)
g(obj::Object{:pos}) =  obj.x^2
g(obj::Object{:neg}) = -obj.x^2

@show g(a), g(b)                # (25, -25)
```

This type tag is automatically inherited.

```julia
@show g(Prototype(a,x=2)), g(Prototype(b,x=2))      # (4, -4)
```

The type tag can also be changed.

To change type while *inheriting* traits (i.e., using `a` as a prototype):
```julia
a_neg = Object{:neg}(Prototype(a))
```

To change type while *copying* traits (i.e., copying `a`'s properties and keeping `a`'s prototype):

```julia
a_neg = Object{:neg}(a)
```

To change type while *flattening* traits (i.e., copying `a`'s properties and any from `a`'s prototype):

```julia
a_neg = Object{:neg}(; a...)
```

When unspecified, the type tag default is `Nothing`.

### Object Type Method Polymorphism

Methods can behave differently depending on the tag type of their caller:

```julia
traits = Object(age=0, name="", punish = let 
    function f(self::Object{:child}) "stand in corner for $(self.age) minutes" end
    function f(self::Object{:teen}) "scold sternly for $(self.age) seconds" end
    function f(self::Object{:adult}) "express disappointment for $(self.age) years" end
end)
tommy = Prototype(Object{:child}(traits); name="tommy", age=5)
jeff  = Prototype(Object{:adult}(traits); name="jeff", age=25)
@show tommy.punish(), jeff.punish()
```

### Method Specialization using Type Hierarchy

Type tags, when types are used, can be given hierarchy.

```julia
# type hierarchy
abstract type Animal end
abstract type Human <: Animal end
abstract type Dog <: Animal end

# prototypes
const Prototypes = Object(Dynamic)
Prototypes.Animal = Object{Animal}(; eyes=2, legs=4, size=:large)
Prototypes.Human = Prototype{Human}(Prototypes.Animal; legs=2, artificial_legs=0, size=:medium)
Prototypes.Dog = Prototype{Dog}(Prototypes.Animal; size=:small)

# defining a method extends naturally to subtypes
getspeed(animal::Object{<:Animal}) = animal.legs
# defining a method for the human subtype
getspeed(person::Object{<:Human}) = person.legs + person.artificial_legs

let (; Animal, Human, Dog) = Prototypes
    sparky = Dog()          
    @show getspeed(sparky)          # 4

    joe = Human(legs=1);   # lost in a tragic automobile accident
    @show getspeed(joe)             # 1

    joe.artificial_legs = 1         # modern technology
    @show getspeed(joe)             # 2
end
```

Notice that the path for objects to inherit traits (prototype inheritance) is separate from the path of obtaining type hierarchy (type tagging), so there's flexibility for an object to adopt traits from any other type. It's like a coal miner learning how to code, if that's even possible.

## Interface

```julia
    getprototype(obj::Object)::Union{Object, Nothing}
```
Gets `obj`'s prototype object. 

Unlike JavaScript, an object's prototype cannot be changed (so there's no `setprototype!` function).


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
obj = Object(a=1, b=2, h = this -> this.a + this.b)
somevar = obj.h
@show somevar()                     # 3
```

Same when destructuring an object:
```julia
(; h) = obj
@show h()                           # 3
```

But when splatting an object, the original function is given (because we want to be able to splat the function into new objects as a member method)
```julia
Dict(obj...)[:h]()                  # error
@show Dict(obj...)[:h](obj)         # 3
```

## More

The type of an `Object`'s properties, and how they are stored, is encoded in its second type parameter. For example, try this:

```julia
@show typeof(Object(Dynamic; a=1, b=2))
@show typeof(Object(Static;  a=1, b=2))
@show typeof(Object(Mutable; a=1, b=2))
```

If you want to test for objects with specific properties, but disregarding the tag type, you can do something like this:
```julia
obj1 = Object{1}(a=1, b=2)
obj2 = Object{2}(a=2, b=1)
@show obj2 isa typeof(obj1)         # false
T = Object{<:Any, typeof(obj1).parameters[2]}
@show obj2 isa T                    # true
```

This will check that `obj1` and `obj2` have exactly the same arguments in the same order, and are both `Mutable`. Here's something that just checks to see if an object is `Dynamic` or not:

```julia
obj2 isa Object{<:Any, <:Dynamic}   # false
```

This allows you to make different implementations depending on how the `Object` is represented internally. I don't know why you would want to, but you can.

How can you filter for `Object`s that store a specific set of parameter names, or with specific types, but disregarding their order or whether they're `Dynamic` or `Static`? It's possible, but unless the type language becomes even more expressive than it already is, is probably a waste of time.



Here's a performance comparison for static objects:

```julia
using BenchmarkTools
Template = Object(Static, a=0.0, b=0.0)
struct Test a::Float64; b::Float64 end
@btime sum(x->x.a, (Template(a=rand(), b=rand()) for i=1:100_000))                  # 10ms  - Template Construction
@btime sum(x->x.a, Object(Static; Template..., a=rand(), b=rand()) for i=1:100_000) # 200ms - Splatting Composition
@btime sum(x->x.a, Object(Static; a=rand(), b=rand()) for i=1:100_000)              # 420μs - No Composition
@btime sum(x->x.a, (Test(rand(), rand()) for i=1:100_000))                          # 420μs - Specialized Struct
```

Using `Object` here is currently about 20x slower than the `struct`. It's a lot faster than it used to be, but still not where it could be imo. 

Mutable objects have similar performance (try it):

```julia
Template = Object(Mutable, a=0.0, b=0.0)
mutable struct TestMut a::Float64; b::Float64 end
@btime sum(x->x.a, (Template(a=rand(), b=rand()) for i=1:100_000))      # 10ms
@btime sum(x->x.a, Object(; Template..., a=rand(), b=rand()) for i=1:100_000)   # 266ms
@btime sum(x->x.a, Object(; a=rand(), b=rand()) for i=1:100_000)        # 21ms - remarkably slow atm
@btime sum(x->x.a, (TestMut(rand(), rand()) for i=1:100_000))           # 600μs
```

zr