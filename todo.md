Create new function for dynamic type checks

proptypes(o::Object) -> returns Union{} of all property types, including those of dynamic objects
e.g. (if proptypes(my_obj) <: proptypes(template_type))
returns Prop{>:Union{Prop{:a,Int}, Prop{:b, Number}}} etc.

change indexable to dynamic

Change default constructor to use kwargs only, and use var"#stuff#" to make hard to access
Make default constructor as easy to use as `object`, so that it's not necessary anymore

Object[dynprops]((proto1,), staticprops; mutableprops...)












# Ideas to explore



Macros for generating types?

TypeScript has: @type, @keyof, 


For annotating property names and types:
struct Pr{name,T} end
Pr{n}(::Type{T}) where {n,T} = Pr{n,T}()
x = Foo{Union{Pr{:a,Int}, Pr{:b,Float64}}}()
proptype(::Foo{T}) where T = T
y = Foo{Union{Pr{:a,Int}, Pr{:b,Float64}, Pr{:c,String}}}()
y isa Foo{>:proptype(x)}
foowithprops(::Foo{T}) where T = Foo{>:T}
y isa foowithprops(x)
y isa foo
foowithmutable()

For annotating object param types:
@object(a::Number=5, b::Float64=2)


object(UserType, (a=1,b=2); c=3, d=4)
Object{UT}(objs::Object...; prototype=nothing, static=nothing, mutable=nothing, dynamic=nothing)



object(:static; props...) # :static, :mutable, or :dynamic; default mutable
object((a=1, b=2); c=3, d=4)

myObject(a=1, b=2, c=3, d=4) # construct a fresh object, constrained by old object

Add type-parameterization that reflects the variable names and types




- Store prototype as `var"#prototype#"`
- Make objects actually dynamic; and only static or mutable for properties that were set at construction time
-  (this allows any object to be molded like clay, and then used as a template for faster clones.)
- How do we decide which items should be static vs mutable?
- How about numbered indices? Should we store a tuple? Or maybe an array?
- Symbol indices should work like dot-access.
- How about string indices?

Every object has its:
- Prototype (var"#prototype#")
- Static part (NamedTuple var"#static#")
- Mutable part (Ref NamedTuple var"#mutable#")
- Dynamic part (var"#dynamic#")

Object constructor:
Object{UT}(prototype, static::NamedTuple, mutable::NamedTuple, dynamic::blah)


object function:
object(; kwargs...)



Some macros for inspecting objects
@inspect obj
@inspect obj.prop

remember to add equality comparison
also: approx comparison?? (to see if two objects implement the same properties of the same types)


Maybe:
obj = Object(
    a=1,
    b=2
)
# a and b are static? or mutable?

obj.c = 3 # .c is dynamic

obj() # creates a new object w/ .a, .b, and .c all mutable? static?




- Use an ordered dict for Dynamic object type? YES. IMPLEMENT THIS. check OrderedCollections.jl
- allow Dynamic, Static, and Mutable to be AbstractTypes instead of structs (to reduce interference with other packages), since currently the user never interacts with these data structures directly?
- Check out other methods that JavaScript has and consider implementing them https://www.tektutorialshub.com/javascript/hasownproperty-in-javascript/
- should it be possible to set arbitrary objects as prototypes? 🤔
- Mull over objects.jl for "OT.name.wrapper" vs. "getfield(parentmodule(OT), nameof(OT))".

# Things to do

- Make Tests


## some lessons learned during this project
- tracking types to maintain type stability is a challenge but improves performance massively
- once a variable loses its type stability, the type instability can explode through successive functions until the entire body of code is slow
-  (think of it like the `missing` datatype, but for data types.)
- for speed, defer to using generators operating on iterators instead of specific data structures when possible (to avoid rearranging data)
- instead of `k ∉ keys && do_something()`, use `k ∈ keys || do_something()` (more performant)


Do something with this sjit:

## Insanely More

Let's get crazy with the type system...
```julia
abstract type A{V,W,X,Y,Z} end
abstract type B{V,W,X,Y,Z} <: A{V,W,X,Y,Z} end
abstract type C{V,W,X,Y,Z} <: B{V,W,X,Y,Z} end
abstract type D{V,W,X,Y,Z} <: C{V,W,X,Y,Z} end
abstract type E{V,W,X,Y,Z} <: D{V,W,X,Y,Z} end
```
Okay, what can we do? Hmm...

Note that
```julia
C{A}{B} == C{A, B}                          # true
```
The way this works is, if we set up a condition like
```julia
U{V,W,X,Y,Z} <: C{<:C,<:C,<:C,<:C,<:C}
```
where `U`,`V`,`X`,`Y`, and `Z` are all separate types in the range of `A` to `E`, then they must all be simultaneously subtypes of `C` (i.e., either `C`, `D`, or `E`) in order for the expression to be true. In other words, the true region is a hyper-rectangle formed by the intersection of these regions.

For example:

```julia
julia> [X{Y} <:C{<:C} for X ∈ (A, B, C, D, E), Y ∈ (A, B, C, D, E)]
5×5 Matrix{Bool}:
 0  0  0  0  0
 0  0  0  0  0
 0  0  1  1  1
 0  0  1  1  1
 0  0  1  1  1

#true for these entries:
 C{C}
 D{C}
 E{C}
 C{D}
 D{D}
 E{D}
 C{E}
 D{E}
 E{E}
```
You can also run 
```julia
[X{Y{Z}} <:C{<:C{<:C}} for X ∈ (A, B, C, D, E), Y ∈ (A, B, C, D, E), Z ∈ (A, B, C, D, E)]
```
to the same effect, namely X, Y, and Z must simultaneously be C, D, or E. Interestingly,
```julia
[X{Y{Z}} <:C{<:C{<:C}} for X ∈ (A, B, C, D, E), Y ∈ (A, B, C, D, E), Z ∈ (A, B, C, D, E)] ==
    [X{Y,Z} <:C{<:C,<:C} for X ∈ (A, B, C, D, E), Y ∈ (A, B, C, D, E), Z ∈ (A, B, C, D, E)]
```
so there's no point telling them apart.

If the LHS has any less TypeVars than the right, then it's always false. If it has more, then the extra typevar doesn't make a difference.


ok so now what?

You can gate behavior on the intersection of many simultaneous conditions. Each condition can be:

equality: 