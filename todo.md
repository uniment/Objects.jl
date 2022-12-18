Start thread on parsing weirdnesses

if true  :hi  else  :bye  end
[1 - 2] [1-2] [1 -2]
@show(1 - 2) @show(1-2) @show(1 -2)
@show 1 - 2  @show 1-2  @show 1 -2
x = true; if x  -1  else  2  end





Another bug:
ft(o::T) = T.types          # type-stable
ft(o::T) = fieldtypes(T)    # type-unstable




Record bug:
julia> :(if Int <: Int  :hey  else  :ho  end)
:(if Int <: Int:hey
  else
      #= REPL[25]:1 =#
      :ho
  end)

This isn't a bug. Just a weird consequence of parsing rules that you only run into for generated functions, where symbols and expressions get their `:` stolen for a Colon.

This is funny though:

julia> :(if(Int <: Int)  :hey  else  :ho  end)
:(if (Int <: Int):hey
  else
      #= REPL[32]:1 =#
      :ho
  end)

julia> :(if(Int <: Int)  (:hey)  else  :ho  end)
ERROR: syntax: space before "(" not allowed in "Int <: Int (" at REPL[31]:1

This is what you want:

julia> :(if Int <: Int;  :hey  else  :ho  end)
:(if Int <: Int
      #= REPL[33]:1 =#
      :hey
  else
      #= REPL[33]:1 =#
      :ho
  end)

Hah:
julia> if true  :hey  else  :ho  end
ERROR: UndefVarError: hey not defined

julia> if true  (:hey)  else  :ho  end
ERROR: syntax: space before "(" not allowed in "true (" at REPL[42]:1

julia> if true;  :hey  else  :ho  end
:hey







Record bug:

julia> f(arr1, arr2) = map(i->arr1[i], arr2)
f (generic function with 1 method)

julia> f([1,2,3], [1,2,3])
3-element Vector{Int64}:
 1
 2
 3

julia> @generated f(arr1, arr2) = :( map(i->arr1[i], arr2) )
f (generic function with 1 method)

julia> f([1,2,3], [1,2,3])
ERROR: The function body AST defined by this @generated function is not pure. This likely means it contains a closure, a comprehension or a generator.

julia> @generated f(arr1, arr2) = :( map(let arr1=arr1; i->arr1[i] end, arr2) )
f (generic function with 1 method)

julia> f([1,2,3],[1,2,3])
ERROR: The function body AST defined by this @generated function is not pure. This likely means it contains a closure, a comprehension or a generator.




This causes error: ERROR: MethodError: no method matching isless(::Type{Nothing}, ::Type{Nothing})
@generated _prop_hygiene(dynamic::D, static, mutable) where D = begin
    dynhygiene = if D <: Nothing  :dynamic
    else quote
        let dyn = DynamicStorage(dynamic)
            dkeys = filter(k->k ∉ keys(m) && k ∉ keys(s), keys(dyn))
            DynamicStorage(map(k->k=>dyn[k], dkeys))
        end
    end end
    quote
        s, m = NamedTuple(static), _mutable_hygiene(NamedTuple(mutable))
        skeys = filter(!Base.Fix2(∈, keys(m)), keys(s))
        s = NamedTuple{skeys, Tuple{map(Base.Fix1(getfield, getpropertytypes(s)), skeys)...}}(map(Base.Fix1(getfield, s), skeys))
        d = $dynhygiene 
        (d, s, m)
    end
end

This causes error: ERROR: The function body AST defined by this @generated function is not pure. This likely means it contains a closure, a comprehension or a generator.
@generated _prop_hygiene(dynamic::D, static, mutable) where D = begin
    if D <: Nothing  dynhygiene = :dynamic
    else dynhygiene = quote
        let dyn = DynamicStorage(dynamic)
            dkeys = filter(k->k ∉ keys(m) && k ∉ keys(s), keys(dyn))
            DynamicStorage(map(k->k=>dyn[k], dkeys))
        end
    end end
    quote
        s, m = NamedTuple(static), _mutable_hygiene(NamedTuple(mutable))
        skeys = filter(!Base.Fix2(∈, keys(m)), keys(s))
        s = NamedTuple{skeys, Tuple{map(Base.Fix1(getfield, getpropertytypes(s)), skeys)...}}(map(Base.Fix1(getfield, s), skeys))
        d = $dynhygiene 
        (d, s, m)
    end
end





Code to bugger your environment

julia> for n ∈ rand(1:100_000, 100)  s=Symbol("#$n#$(n+1)"); eval(:( $s = 0 ))  end

julia> x->x^2
ERROR: cannot declare #13#14 constant; it already has a value





julia> h() = begin
           a = true
           function f end
           if rand(Bool)
               function f() end
           else
               function f(x) end
           end
           f
       end
h (generic function with 1 method)

julia> h()
ERROR: UndefVarError: f not defined





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