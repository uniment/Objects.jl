# Ideas to explore

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