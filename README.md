# Bnum v1.2.0

A high-performance big-number library for Roblox/Luau built around a compact **12-byte `buffer` representation**.

Bnum is designed for simulator, incremental, clicker, economy, leaderboard, and other Roblox systems that need values far beyond normal floating-point display ranges without turning every math operation into string arithmetic.

```text
Version:         1.2.0
Storage Version: 1
Buffer Size:     12 bytes
Representation:  sign × 10^logMagnitude
```

---

## Highlights

- 12-byte buffer-backed numbers
- Extremely large and tiny values
- Buffer-native hot-path API
- Allocating, reusable-buffer, and in-place arithmetic
- Fast comparisons
- Scientific parsing and serialization
- Compact suffix notation
- New exponent-suffix notation
- Geometric Max Buy
- Limited Max Buy / Buy 1 / Buy 2 / Buy 10 support
- Bulk cost and next-cost helpers
- Soft caps, milestones, scaling, progress, ETA, and dynamic costs
- Ordered leaderboard encoding helpers
- NaN and infinity support
- Compatibility layer for numbers and strings
- Built-in microbenchmark helper
- `--!optimize 2`
- `--!native`

---

# Table of Contents

1. [Installation](#installation)
2. [Quick Start](#quick-start)
3. [How Bnum Stores Numbers](#how-bnum-stores-numbers)
4. [The v1.2 Buffer-Native Rule](#the-v12-buffer-native-rule)
5. [Mutation Rules](#mutation-rules)
6. [Creating Bnums](#creating-bnums)
7. [Arithmetic](#arithmetic)
8. [Fast Buffer API](#fast-buffer-api)
9. [In-Place Math](#in-place-math)
10. [Comparisons](#comparisons)
11. [Roots, Powers, and Logs](#roots-powers-and-logs)
12. [Formatting](#formatting)
13. [`toSuffix()`](#tosuffix)
14. [`toESuffix()`](#toesuffix)
15. [`format()`](#format)
16. [Serialization](#serialization)
17. [Conversion and Inspection](#conversion-and-inspection)
18. [Max Buy and Upgrade Systems](#max-buy-and-upgrade-systems)
19. [Bulk Cost and Next Cost](#bulk-cost-and-next-cost)
20. [Limited Buy Buttons](#limited-buy-buttons)
21. [Economy Helpers](#economy-helpers)
22. [Ordered Leaderboard Encoding](#ordered-leaderboard-encoding)
23. [Compatibility API](#compatibility-api)
24. [Simulator Example](#simulator-example)
25. [Saving Player Data](#saving-player-data)
26. [Performance Guidelines](#performance-guidelines)
27. [Built-In Benchmark](#built-in-benchmark)
28. [API Reference](#api-reference)
29. [v1.2.0 Changes](#v126-changes)
30. [Recommended Project Pattern](#recommended-project-pattern)

---

# Installation

Create a ModuleScript named `Bnum` in `ReplicatedStorage`.

```text
ReplicatedStorage
└── Bnum
```

Require it:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Bnum = require(ReplicatedStorage:WaitForChild("Bnum"))
```

Check the loaded version:

```lua
print(Bnum.VERSION)
-- 1.2.0
```

Bnum itself uses:

```lua
--!optimize 2
--!native
```

---

# Quick Start

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Bnum = require(ReplicatedStorage:WaitForChild("Bnum"))

local Coins = Bnum.fromNumber(1_000)
local Reward = Bnum.fromNumber(250)

Bnum.addeq(Coins, Reward)

print(Bnum.toSuffix(Coins))
print(Bnum.toString(Coins))
```

Example output:

```text
1.25k
1.25e3
```

---

# How Bnum Stores Numbers

A Bnum is a 12-byte Roblox `buffer`.

Conceptually:

```text
value = sign × 10^logMagnitude
```

The buffer stores:

```text
Offset 0: sign
Offset 4: base-10 logarithmic magnitude
```

The public size is:

```lua
print(Bnum.SIZE)
-- 12
```

Examples:

```text
1000
sign = 1
logMagnitude = 3

-1000
sign = -1
logMagnitude = 3

1e1000
sign = 1
logMagnitude = 1000
```

This is why multiplication and division can be extremely cheap:

```text
multiply -> add logarithms
divide   -> subtract logarithms
```

Bnum also has dedicated representations for:

```text
Zero
NaN
+Infinity
-Infinity
```

---

# The v1.2 Buffer-Native Rule

The core v1.2 API expects **Bnum buffers**.

Convert values at the edge of your system:

```lua
local Coins = Bnum.fromString("1e100")
local Reward = Bnum.fromNumber(250)
```

Then keep using buffers:

```lua
Bnum.addeq(Coins, Reward)
```

Avoid repeatedly converting normal values inside hot loops.

Less efficient:

```lua
for _ = 1, 100000 do
	local Result = Bnum.compat.add("1e100", 250)
end
```

Preferred:

```lua
local A = Bnum.fromString("1e100")
local B = Bnum.fromNumber(250)

for _ = 1, 100000 do
	local Result = Bnum.add(A, B)
end
```

The compatibility API is still available when convenience matters more than raw hot-path performance.

---

# Mutation Rules

This is one of the most important parts of Bnum.

Some APIs allocate a new result.

Other APIs intentionally mutate the first Bnum argument to reduce allocations.

## Allocating example

`add()` returns a new buffer:

```lua
local A = Bnum.fromNumber(100)
local B = Bnum.fromNumber(50)

local Result = Bnum.add(A, B)

print(Bnum.toSuffix(A))
-- 100

print(Bnum.toSuffix(Result))
-- 150
```

## Mutating example

`mul()` reuses the first buffer:

```lua
local Value = Bnum.fromNumber(100)
local Multiplier = Bnum.fromNumber(2)

Bnum.mul(Value, Multiplier)

print(Bnum.toSuffix(Value))
-- 200
```

If you need to preserve the original:

```lua
local Original = Bnum.fromNumber(100)
local Multiplier = Bnum.fromNumber(2)

local Result = Bnum.mul(
	Bnum.clone(Original),
	Multiplier
)

print(Bnum.toSuffix(Original))
-- 100

print(Bnum.toSuffix(Result))
-- 200
```

## Common mutating APIs

Treat these as mutating their first Bnum argument:

```text
sub
subz
mul
div
pow
pow10
sqrt
log10
log
ln
exp
floor
ceil
round
mod
imod
root
neg
recip
cbrt
powf
log2
intdiv
scaleCurve
progress
dynamicCost
abs
eta
```

The explicit `*eq` functions also mutate:

```text
addeq
subeq
muleq
diveq
```

## APIs that may return an existing input

These are not guaranteed to return a fresh clone:

```text
min
max
clamp
softCap
```

If ownership matters, clone the result:

```lua
local SafeResult = Bnum.clone(
	Bnum.max(A, B)
)
```

---

# Creating Bnums

## `fromNumber()`

Convert a regular Luau number:

```lua
local A = Bnum.fromNumber(1000)
local B = Bnum.fromNumber(-250)
local C = Bnum.fromNumber(0)
```

---

## `fromString()`

Use strings for scientific values:

```lua
local A = Bnum.fromString("1e100")
local B = Bnum.fromString("2.5e250")
local C = Bnum.fromString("-7.5e500")
```

Special values:

```lua
local NaN = Bnum.fromString("NaN")
local Inf = Bnum.fromString("Inf")
local NegativeInf = Bnum.fromString("-Inf")
```

---

## `new()`

`new(mantissa, exponent)` represents:

```text
mantissa × 10^exponent
```

Example:

```lua
local Thousand = Bnum.new(1, 3)
local Value = Bnum.new(1.25, 6)

print(Bnum.toSuffix(Thousand))
-- 1k

print(Bnum.toSuffix(Value))
-- 1.25m
```

Important:

```lua
Bnum.new(1, 3)
```

means:

```text
1 × 10^3
= 1000
= 1k
```

It does **not** mean the number `3`.

---

## `ensure()`

`ensure()` accepts:

```text
buffer
number
string
```

Example:

```lua
local A = Bnum.ensure(1000)
local B = Bnum.ensure("1e100")
local C = Bnum.ensure(A)
```

If the value is already a buffer, the same buffer is returned.

Alias:

```lua
Bnum.coerce
```

Use `ensure()` at API boundaries, not repeatedly in hot math loops.

---

## `clone()`

Create an independent copy:

```lua
local Original = Bnum.fromString("1e100")
local Copy = Bnum.clone(Original)

Bnum.muleq(Copy, Bnum.fromNumber(2))

print(Bnum.toSuffix(Original))
print(Bnum.toSuffix(Copy))
```

---

# Arithmetic

## Addition

```lua
local A = Bnum.fromNumber(100)
local B = Bnum.fromNumber(25)

local Result = Bnum.add(A, B)

print(Bnum.toSuffix(Result))
-- 125
```

`add()` allocates a new result.

---

## Subtraction

```lua
local A = Bnum.fromNumber(100)
local B = Bnum.fromNumber(25)

Bnum.sub(A, B)

print(Bnum.toSuffix(A))
-- 75
```

`sub()` mutates `A`.

---

## Zero-Clamped Subtraction

`subz()` prevents a negative result:

```lua
local Health = Bnum.fromNumber(50)
local Damage = Bnum.fromNumber(100)

Bnum.subz(Health, Damage)

print(Bnum.toSuffix(Health))
-- 0
```

---

## Multiplication

```lua
local Value = Bnum.fromNumber(100)
local Multiplier = Bnum.fromNumber(3)

Bnum.mul(Value, Multiplier)

print(Bnum.toSuffix(Value))
-- 300
```

---

## Division

```lua
local Value = Bnum.fromNumber(100)
local Divisor = Bnum.fromNumber(4)

Bnum.div(Value, Divisor)

print(Bnum.toSuffix(Value))
-- 25
```

---

## Integer Division

```lua
local Value = Bnum.fromNumber(17)
local Divisor = Bnum.fromNumber(5)

Bnum.intdiv(Value, Divisor)

print(Bnum.toSuffix(Value))
-- 3
```

---

## Modulo

```lua
local Value = Bnum.fromNumber(17)
local Divisor = Bnum.fromNumber(5)

Bnum.mod(Value, Divisor)

print(Bnum.toSuffix(Value))
-- 2
```

Alias:

```lua
Bnum.imod(Value, Divisor)
```

---

# Fast Buffer API

Bnum exposes lower-level reusable-buffer operations for allocation-sensitive code.

Available:

```text
addBuffer
subBuffer
mulBuffer
divBuffer
cmpBuffer
```

## Allocate automatically

```lua
local A = Bnum.fromNumber(100)
local B = Bnum.fromNumber(25)

local Result = Bnum.addBuffer(A, B)
```

## Reuse an output buffer

```lua
local A = Bnum.fromNumber(100)
local B = Bnum.fromNumber(25)

local Out = buffer.create(Bnum.SIZE)

Bnum.addBuffer(A, B, Out)

print(Bnum.toSuffix(Out))
-- 125
```

Reuse it:

```lua
local Out = buffer.create(Bnum.SIZE)

for _ = 1, 100000 do
	Bnum.mulBuffer(A, B, Out)
end
```

This avoids creating a new output buffer for each operation.

---

# In-Place Math

The `*eq` APIs write directly into the first buffer.

Available:

```text
addeq
subeq
muleq
diveq
```

Example:

```lua
local Coins = Bnum.fromNumber(100)
local Reward = Bnum.fromNumber(25)

Bnum.addeq(Coins, Reward)

print(Bnum.toSuffix(Coins))
-- 125
```

Multiplication:

```lua
local Damage = Bnum.fromNumber(100)
local Multiplier = Bnum.fromNumber(2)

Bnum.muleq(Damage, Multiplier)

print(Bnum.toSuffix(Damage))
-- 200
```

Use these when mutation is intentional.

---

# Comparisons

```lua
local A = Bnum.fromNumber(100)
local B = Bnum.fromNumber(250)

print(Bnum.cmp(A, B))
-- -1

print(Bnum.eq(A, B))
-- false

print(Bnum.lt(A, B))
-- true

print(Bnum.gt(A, B))
-- false

print(Bnum.lte(A, B))
-- true

print(Bnum.gte(A, B))
-- false
```

`cmp()` returns:

```text
-1 -> A < B
 0 -> A == B
 1 -> A > B
```

Aliases:

```text
cmp      compare
le       lt
me       gt
leeq     lte
meeq     gte
```

For new code, these names are easier to read:

```text
lt
gt
lte
gte
```

---

## `min()` and `max()`

```lua
local A = Bnum.fromNumber(10)
local B = Bnum.fromNumber(500)
local C = Bnum.fromNumber(25)

local Smallest = Bnum.min(A, B, C)
local Largest = Bnum.max(A, B, C)

print(Bnum.toSuffix(Smallest))
-- 10

print(Bnum.toSuffix(Largest))
-- 500
```

`min()` and `max()` return one of the supplied buffers.

---

# Roots, Powers, and Logs

## `pow()`

Both arguments are Bnums:

```lua
local Base = Bnum.fromNumber(10)
local Power = Bnum.fromNumber(6)

Bnum.pow(Base, Power)

print(Bnum.toSuffix(Base))
-- 1m
```

The first buffer is mutated.

Negative-base behavior is handled for integer exponents:

```lua
local A = Bnum.fromNumber(-1)

Bnum.pow(A, Bnum.fromNumber(3))

print(Bnum.toSuffix(A))
-- -1
```

A non-real fractional power becomes NaN:

```lua
local A = Bnum.fromNumber(-1)

Bnum.pow(A, Bnum.fromNumber(0.5))

print(Bnum.isNaN(A))
-- true
```

---

## `powf()`

Use a normal Luau number as the exponent:

```lua
local Value = Bnum.fromNumber(9)

Bnum.powf(Value, 0.5)

print(Bnum.toSuffix(Value))
-- 3
```

This is useful when the exponent itself does not need to be a Bnum.

---

## `pow10()`

```lua
local Exponent = Bnum.fromNumber(100)

Bnum.pow10(Exponent)

print(Bnum.toString(Exponent))
-- 1e100
```

---

## `sqrt()`

```lua
local Value = Bnum.fromNumber(144)

Bnum.sqrt(Value)

print(Bnum.toSuffix(Value))
-- 12
```

---

## `cbrt()`

Cube roots support negative values:

```lua
local Value = Bnum.fromNumber(-125)

Bnum.cbrt(Value)

print(Bnum.toSuffix(Value))
-- -5
```

---

## `root()`

```lua
local Value = Bnum.fromNumber(256)
local Degree = Bnum.fromNumber(4)

Bnum.root(Value, Degree)

print(Bnum.toSuffix(Value))
-- 4
```

---

## `recip()`

Reciprocal:

```lua
local Value = Bnum.fromNumber(8)

Bnum.recip(Value)

print(Bnum.format(Value, 4))
-- 0.125
```

---

## `neg()`

Negate in place:

```lua
local Value = Bnum.fromNumber(500)

Bnum.neg(Value)

print(Bnum.toSuffix(Value))
-- -500
```

---

## `log10()`

```lua
local Value = Bnum.fromNumber(1000)

Bnum.log10(Value)

print(Bnum.toSuffix(Value))
-- 3
```

---

## `log2()`

```lua
local Value = Bnum.fromNumber(1024)

Bnum.log2(Value)

print(Bnum.toSuffix(Value))
-- 10
```

---

## Natural Log

```lua
local Value = Bnum.fromNumber(10)

Bnum.ln(Value)

print(Bnum.format(Value))
```

`ln` is an alias of `log` when no base is supplied.

---

## Custom Base Log

```lua
local Value = Bnum.fromNumber(1000)
local Base = Bnum.fromNumber(10)

Bnum.log(Value, Base)

print(Bnum.toSuffix(Value))
-- 3
```

---

## `exp()`

```lua
local Value = Bnum.fromNumber(2)

Bnum.exp(Value)

print(Bnum.format(Value))
```

---

# Formatting

Bnum v1.2.0 has three main display systems:

| Function | Main purpose | Decimal behavior |
|---|---|---|
| `toSuffix()` | Fast compact values | Truncates to 2 decimals |
| `toESuffix()` | Extreme exponent notation | Truncates to 2 decimals |
| `format()` | General-purpose formatting | Rounds using requested precision |

This distinction is intentional.

---

# `toSuffix()`

`toSuffix()` is the main compact formatter for gameplay UI.

```lua
local Coins = Bnum.fromString("1.25e6")

print(Bnum.toSuffix(Coins))
-- 1.25m
```

## v1.2.0 truncation behavior

`toSuffix()` does **not** round up to the next displayed hundredth.

Examples:

```text
1e3        -> 1k
1.1e3      -> 1.1k
1.10e3     -> 1.1k
1.2e3      -> 1.2k
1.20e3     -> 1.2k
1.02e3     -> 1.02k
1.09e3     -> 1.09k
1.095e3    -> 1.09k
1.099e3    -> 1.09k
1.999e3    -> 1.99k
999.995e3  -> 999.99k
```

That means:

```lua
print(Bnum.toSuffix(Bnum.fromString("1.095e3")))
-- 1.09k
```

and only once the actual value reaches the next displayed step:

```lua
print(Bnum.toSuffix(Bnum.fromString("1.1e3")))
-- 1.1k
```

Unnecessary zeroes are removed:

```text
1.10k -> 1.1k
1.20k -> 1.2k
```

Meaningful zeroes are kept:

```text
1.02k -> 1.02k
```

---

## Large suffixes

Bnum generates extended suffixes for logarithmic magnitudes below the normal suffix cutoff.

Examples begin with:

```text
k
m
b
...
```

At extremely large magnitudes beyond the standard suffix range, `toSuffix()` falls back to scientific-style output.

If you want compressed exponent notation instead, use `toESuffix()`.

---

## Tiny values

`toSuffix()` also handles tiny values.

Examples may use reciprocal-style notation once values become sufficiently small:

```lua
local Tiny = Bnum.fromString("1e-6")

print(Bnum.toSuffix(Tiny))
```

---

# `toESuffix()`

`toESuffix()` is new in v1.2.0.

It behaves like `toSuffix()` below a configurable decimal-exponent threshold.

By default:

```text
switchAt = 1000
```

Once the value reaches that exponent, the exponent itself is compacted using suffix notation.

## Basic examples

```text
1e1000      -> E1k
1e1020      -> E1.02k
1e1095      -> E1.09k
1e1200      -> E1.2k
1e1999      -> E1.99k
1e1000000   -> E1m
```

Usage:

```lua
local Value = Bnum.fromString("1e1000")

print(Bnum.toESuffix(Value))
-- E1k
```

---

## Mantissa + E suffix

The mantissa is kept when needed:

```text
1.2e1000    -> 1.2E1k
1.02e1000   -> 1.02E1k
1.095e1000  -> 1.09E1k
```

Example:

```lua
local Value = Bnum.fromString("1.2e1000")

print(Bnum.toESuffix(Value))
-- 1.2E1k
```

---

## Before the switch point

Values below the threshold use normal suffix formatting:

```lua
local Value = Bnum.fromString("1.2e6")

print(Bnum.toESuffix(Value))
-- 1.2m
```

---

## Custom switch point

Signature:

```lua
Bnum.toESuffix(value, switchAt?)
```

Example:

```lua
local Value = Bnum.fromString("1e100")

print(Bnum.toESuffix(Value, 100))
-- E100
```

---

## Aliases

```lua
Bnum.toExponentSuffix
Bnum.toExtendedSuffix
```

These point to `toESuffix()`.

Recommended name for new code:

```lua
Bnum.toESuffix(Value)
```

---

# `format()`

`format()` is the flexible general formatter.

```lua
local Value = Bnum.fromNumber(123456)

print(Bnum.format(Value))
-- 123,456
```

Unlike `toSuffix()`, `format()` uses normal rounding behavior.

Specify precision:

```lua
print(Bnum.format(Value, 0))
print(Bnum.format(Value, 1))
print(Bnum.format(Value, 2))
print(Bnum.format(Value, 4))
```

Optional scientific/hyper cutoff:

```lua
print(
	Bnum.format(
		Bnum.fromString("1e1000"),
		2,
		100
	)
)
```

Use:

```text
toSuffix   -> compact gameplay UI
toESuffix  -> extreme-value compact UI
format     -> configurable/general formatting
```

---

# Serialization

## `toStr()` / `toString()`

Convert a Bnum into scientific text:

```lua
local Value = Bnum.fromString("1.25e100")

local Saved = Bnum.toString(Value)

print(Saved)
-- 1.25e100
```

`toString` is an alias of:

```lua
Bnum.toStr
```

Round trip:

```lua
local Original = Bnum.fromString("7.5e250")

local Saved = Bnum.toString(Original)
local Restored = Bnum.fromString(Saved)

print(Bnum.eq(Original, Restored))
-- true
```

Special output:

```text
Zero      -> 0e0
NaN       -> NaN
Infinity  -> Inf
-Infinity -> -Inf
```

---

# Conversion and Inspection

## `toNumber()`

Convert back to a normal Luau number:

```lua
local Value = Bnum.fromNumber(125)

print(Bnum.toNumber(Value))
-- 125
```

Normal floating-point range still applies.

Very large values become infinity:

```lua
local HugeValue = Bnum.fromString("1e1000")

print(Bnum.toNumber(HugeValue))
-- inf
```

Extremely tiny values can underflow to zero.

`isFloat()` tells you whether the Bnum is finite and does not exceed the normal-number overflow limit used by Bnum. Extremely tiny values can still underflow to zero when converted with `toNumber()`.

---

## `isFloat()`

```lua
local Value = Bnum.fromString("1e100")

print(Bnum.isFloat(Value))
-- true
```

A huge Bnum:

```lua
local Value = Bnum.fromString("1e1000")

print(Bnum.isFloat(Value))
-- false
```

---

## `isFinite()`

```lua
print(
	Bnum.isFinite(
		Bnum.fromString("1e1000")
	)
)
-- true
```

Infinity:

```lua
print(
	Bnum.isFinite(
		Bnum.fromString("Inf")
	)
)
-- false
```

---

## Inspection helpers

```lua
local Value = Bnum.fromNumber(-500)

print(Bnum.sign(Value))
print(Bnum.exponent(Value))
print(Bnum.isNaN(Value))
print(Bnum.isZero(Value))
print(Bnum.isPositive(Value))
print(Bnum.isNegative(Value))
print(Bnum.isBnum(Value))
```

Available:

```text
sign
exponent
isNaN
isZero
isPositive
isNegative
isFinite
isFloat
isBnum
```

`exponent()` returns Bnum's internal base-10 logarithmic magnitude.

---

# Max Buy and Upgrade Systems

Bnum v1.2.0 includes a geometric Max Buy system.

It is designed for costs following:

```text
currentCost
currentCost × multiplier
currentCost × multiplier²
currentCost × multiplier³
...
```

Example:

```text
Current Cost = 100
Multiplier   = 10

100
1,000
10,000
100,000
...
```

---

## `maxBuy()`

Signature:

```lua
Bnum.maxBuy(
	funds,
	currentCost,
	multiplier
)
```

Returns:

```text
amount: number
totalCost: Bnum
```

Example:

```lua
local Money = Bnum.fromString("1e20")

local CurrentCost = Bnum.fromString("1e12")
local CostIncrease = Bnum.fromNumber(10)

local Amount, TotalCost = Bnum.maxBuy(
	Money,
	CurrentCost,
	CostIncrease
)

print("Can Buy:", Amount)
print("Total Cost:", Bnum.toSuffix(TotalCost))
```

`maxBuy()` does not subtract money automatically.

It calculates how many consecutive geometric upgrades can be afforded.

---

## Current owned count

Suppose:

```text
Base Cost      = 100
Cost Increase  = x10
Owned Upgrades = 10
```

Get the price of the next upgrade:

```lua
local BaseCost = Bnum.new(1, 2)
local CostIncrease = Bnum.fromNumber(10)
local UpgradeCount = 10

local CurrentCost = Bnum.nextCostNumber(
	BaseCost,
	CostIncrease,
	UpgradeCount
)

print(Bnum.toString(CurrentCost))
-- 1e12
```

The next prices are:

```text
Owned 10 -> next cost 1e12
Owned 11 -> next cost 1e13
Owned 12 -> next cost 1e14
```

Then:

```lua
local Amount, TotalCost = Bnum.maxBuy(
	Money,
	CurrentCost,
	CostIncrease
)
```

`Amount` is the number of **additional upgrades** that can be purchased.

If:

```text
Current owned = 10
Amount        = 2
```

then:

```lua
UpgradeCount += Amount
```

becomes:

```text
10 + 2 = 12 owned upgrades
```

---

## Max Buy assumption

`maxBuy()` assumes a pure geometric progression.

This works:

```text
cost(x) = baseCost × multiplier^x
```

If your cost function includes additional jumps such as:

```lua
100 * (1.6 ^ x) * (2 ^ math.floor(x / 10))
```

then the multiplier changes at milestone boundaries.

A single geometric `maxBuy()` call cannot model those extra jumps across the entire range.

For those systems, calculate in milestone-safe batches or build a custom purchase loop.

---

# Bulk Cost and Next Cost

## `nextCost()`

Bnum owned count:

```lua
local BaseCost = Bnum.fromNumber(100)
local Multiplier = Bnum.fromNumber(10)
local Owned = Bnum.fromNumber(10)

local Cost = Bnum.nextCost(
	BaseCost,
	Multiplier,
	Owned
)

print(Bnum.toSuffix(Cost))
```

---

## `nextCostNumber()`

Normal number owned count:

```lua
local Cost = Bnum.nextCostNumber(
	BaseCost,
	Multiplier,
	10
)
```

This is usually convenient when upgrade counts are ordinary integers.

Formula:

```text
nextCost = baseCost × multiplier^owned
```

Alias:

```lua
Bnum.costAt
```

---

## `bulkCost()`

Calculate the total cost of several geometric purchases:

```lua
local CurrentCost = Bnum.fromNumber(100)
local Multiplier = Bnum.fromNumber(2)
local Amount = Bnum.fromNumber(3)

local Total = Bnum.bulkCost(
	CurrentCost,
	Multiplier,
	Amount
)

print(Bnum.toSuffix(Total))
```

For:

```text
100
200
400
```

the result is:

```text
700
```

Alias:

```lua
Bnum.totalCost
```

---

## `bulkCostNumber()`

Use a normal number for the amount:

```lua
local Total = Bnum.bulkCostNumber(
	CurrentCost,
	Multiplier,
	3
)
```

v1.2.0 treats purchase counts as whole upgrades.

For example:

```lua
Bnum.bulkCostNumber(
	CurrentCost,
	Multiplier,
	2.9
)
```

is treated as:

```text
2 purchases
```

---

## `canAfford()`

```lua
if Bnum.canAfford(Money, CurrentCost) then
	print("Can buy")
end
```

---

# Limited Buy Buttons

Bnum v1.2.5 introduced limited Max Buy support and v1.2.0 keeps it intact.

This is useful for:

```text
Buy 1
Buy 2
Buy 10
Buy 25
Buy Max
```

---

## `maxBuyLimited()`

```lua
local Amount, TotalCost = Bnum.maxBuyLimited(
	Money,
	CurrentCost,
	CostIncrease,
	2
)
```

Even if the player can afford 8 upgrades:

```text
Affordable = 8
Limit      = 2
Result     = 2
```

The returned `TotalCost` is recalculated for exactly those 2 upgrades.

Alias:

```lua
Bnum.maxBuyCapped
```

---

## `buyMax()`

Returns:

```text
amount
totalCost
remainingMoney
```

Example:

```lua
local Amount, TotalCost, Remaining = Bnum.buyMax(
	Money,
	CurrentCost,
	CostIncrease
)

if Amount > 0 then
	Money = Remaining
	UpgradeCount += Amount
end
```

The original money buffer is not directly spent by the function.

A remaining-money buffer is returned.

---

## `buyMaxLimited()`

This is the cleanest API for a capped purchase button:

```lua
local Amount, TotalCost, Remaining = Bnum.buyMaxLimited(
	Money,
	CurrentCost,
	CostIncrease,
	2
)

if Amount > 0 then
	UpgradeCount += Amount
	Money = Remaining
end
```

Complete example:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Bnum = require(ReplicatedStorage.Bnum)

local Money = Bnum.fromString("1e20")

local UpgradeCount = 10
local MaxPurchase = 2

local BaseCost = Bnum.new(1, 2)
local CostIncrease = Bnum.fromNumber(10)

local CurrentCost = Bnum.nextCostNumber(
	BaseCost,
	CostIncrease,
	UpgradeCount
)

local Amount, TotalCost, Remaining = Bnum.buyMaxLimited(
	Money,
	CurrentCost,
	CostIncrease,
	MaxPurchase
)

if Amount > 0 then
	UpgradeCount += Amount
	Money = Remaining
end

print("Bought:", Amount)
print("Upgrade Count:", UpgradeCount)
print("Spent:", Bnum.toSuffix(TotalCost))
print("Money:", Bnum.toSuffix(Money))
```

If Max Buy says the player can afford 8 but the button limit is 2:

```text
Actually Bought: 2
Upgrade Count:   12
```

Alias:

```lua
Bnum.buyMaxCapped
```

---

## `maxBuyBnum()`

Normal `maxBuy()` returns the purchase count as a Luau number.

For extreme purchase counts, use:

```lua
local Amount, TotalCost = Bnum.maxBuyBnum(
	Money,
	CurrentCost,
	CostIncrease
)
```

Here `Amount` is itself a Bnum.

Alias:

```lua
Bnum.maxBuyBig
```

---

# Economy Helpers

## Linear scaling

Bnum count version:

```lua
local Base = Bnum.fromNumber(100)
local Increment = Bnum.fromNumber(25)
local Level = Bnum.fromNumber(10)

local Result = Bnum.linear(
	Base,
	Increment,
	Level
)

print(Bnum.toSuffix(Result))
-- 350
```

Normal-number level:

```lua
local Result = Bnum.linearNumber(
	Base,
	Increment,
	10
)
```

Formula:

```text
base + increment × level
```

---

## Soft Cap

```lua
local Value = Bnum.fromString("1e8")
local Cap = Bnum.fromString("1e6")
local Power = Bnum.fromNumber(0.5)

local Result = Bnum.softCap(
	Value,
	Cap,
	Power
)

print(Bnum.toSuffix(Result))
```

Values at or below the cap are returned unchanged.

Values above the cap are compressed using the supplied power.

---

## Milestones

Count reached milestones:

```lua
local Value = Bnum.fromNumber(275)
local Step = Bnum.fromNumber(100)

local Count = Bnum.milestoneCount(
	Value,
	Step
)

print(Bnum.toSuffix(Count))
-- 2
```

Calculate a milestone bonus multiplier:

```lua
local Bonus = Bnum.fromNumber(0.25)

local Multiplier = Bnum.milestone(
	Value,
	Step,
	Bonus
)

print(Bnum.format(Multiplier))
-- 1.5
```

Formula:

```text
1 + milestoneCount × bonus
```

---

## Dynamic Cost

Supported methods:

```text
exp
linear
hybrid
```

Example:

```lua
local BaseCost = Bnum.fromNumber(100)
local Owned = Bnum.fromNumber(25)
local Scale = Bnum.fromNumber(1.15)

local Cost = Bnum.dynamicCost(
	Bnum.clone(BaseCost),
	Owned,
	Scale,
	"exp"
)

print(Bnum.toSuffix(Cost))
```

`dynamicCost()` mutates its first argument.

Clone the base cost if you need to keep it.

---

## Scale Curve

Supported modes:

```text
linear
exp
sigmoid
```

Example:

```lua
local Value = Bnum.fromNumber(1000)
local Base = Bnum.fromNumber(100)
local Exponent = Bnum.fromNumber(2)

local Result = Bnum.scaleCurve(
	Bnum.clone(Value),
	Base,
	Exponent,
	"exp"
)

print(Bnum.format(Result))
```

---

## Progress

```lua
local Current = Bnum.fromNumber(750)
local Goal = Bnum.fromNumber(1000)

local Progress = Bnum.progress(
	Bnum.clone(Current),
	Goal,
	"linear"
)

print(Bnum.toNumber(Progress))
```

Modes:

```text
linear
exp
sigmoid
```

---

## Percent

```lua
local Current = Bnum.fromNumber(25)
local Maximum = Bnum.fromNumber(100)

print(Bnum.percent(Current, Maximum))
-- 25%
```

The result is a string.

---

## ETA

```lua
local Current = Bnum.fromNumber(250)
local Goal = Bnum.fromNumber(1000)
local Rate = Bnum.fromNumber(50)

local ETA = Bnum.eta(
	Bnum.clone(Current),
	Goal,
	Rate
)

print(Bnum.toSuffix(ETA))
```

`eta()` mutates the first argument supplied to it.

If the rate is not positive, the result becomes infinity.

---

# Rounding

```lua
local Value = Bnum.fromNumber(12.75)

local Floored = Bnum.floor(Bnum.clone(Value))
local Ceiled = Bnum.ceil(Bnum.clone(Value))
local Rounded = Bnum.round(Bnum.clone(Value))

print(Bnum.toSuffix(Floored))
-- 12

print(Bnum.toSuffix(Ceiled))
-- 13

print(Bnum.toSuffix(Rounded))
-- 13
```

---

# `modf()`

Split integer and fractional portions:

```lua
local Value = Bnum.fromNumber(12.75)

local Integer, Fraction = Bnum.modf(Value)

print(Bnum.toSuffix(Integer))
-- 12

print(Bnum.format(Fraction, 4))
-- 0.75
```

---

# `clamp()`

```lua
local Value = Bnum.fromNumber(150)
local Minimum = Bnum.fromNumber(0)
local Maximum = Bnum.fromNumber(100)

local Result = Bnum.clamp(
	Value,
	Minimum,
	Maximum
)

print(Bnum.toSuffix(Result))
-- 100
```

`clamp()` can return one of the supplied buffers.

---

# Random Bnums

No arguments:

```lua
local Value = Bnum.random()
```

Positive range:

```lua
local Minimum = Bnum.fromNumber(1)
local Maximum = Bnum.fromString("1e100")

local Value = Bnum.random(
	Minimum,
	Maximum
)
```

Bnum interpolates positive ranged values in logarithmic space.

---

# Ordered Leaderboard Encoding

Bnum includes numeric leaderboard encoding helpers:

```text
lbencode
lbdecode
encodeData
```

## Encode

```lua
local Coins = Bnum.fromString("1e500")

local Encoded = Bnum.lbencode(Coins)

print(Encoded)
```

## Decode

```lua
local Restored = Bnum.lbdecode(Encoded)

print(Bnum.toSuffix(Restored))
```

---

## `encodeData()`

```lua
local Coins = Bnum.fromString("1e100")

local Encoded = Bnum.encodeData(Coins)
```

With an old encoded score:

```lua
local Encoded = Bnum.encodeData(
	Coins,
	PreviousEncodedScore
)
```

If the old encoded score is greater, `encodeData()` keeps the old value.

This can be useful for highest-score style leaderboards.

---

# Compatibility API

The compatibility namespace accepts normal numbers and strings and converts them with `ensure()`.

Example:

```lua
local Result = Bnum.compat.add(
	100,
	"2.5e3"
)

print(Bnum.toSuffix(Result))
```

Available:

```text
compat.add
compat.sub
compat.mul
compat.div
compat.pow
compat.cmp
compat.eq
compat.format

compat.toESuffix

compat.maxBuy
compat.maxBuyBnum
compat.maxBuyLimited
compat.buyMaxLimited

compat.bulkCost
compat.nextCost

compat.linear
compat.softCap
compat.milestone
```

Example:

```lua
local Amount, Total = Bnum.compat.maxBuy(
	"1e20",
	"1e12",
	10
)

print(Amount)
print(Bnum.toSuffix(Total))
```

For performance-sensitive code, convert once and use the direct buffer-native API instead.

---

# Simulator Example

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Bnum = require(ReplicatedStorage:WaitForChild("Bnum"))

local Coins = Bnum.fromNumber(0)
local ClickPower = Bnum.fromNumber(1)
local Multiplier = Bnum.fromNumber(2)

local function Click()
	Bnum.addeq(Coins, ClickPower)

	print(
		"Coins:",
		Bnum.toSuffix(Coins)
	)
end

local function UpgradeClickPower()
	Bnum.muleq(
		ClickPower,
		Multiplier
	)

	print(
		"Click Power:",
		Bnum.toSuffix(ClickPower)
	)
end

for _ = 1, 10 do
	Click()
end

UpgradeClickPower()
Click()
```

---

# Extreme Simulator Display Example

Use `toSuffix()` for normal gameplay values:

```lua
local Coins = Bnum.fromString("1.095e3")

print(Bnum.toSuffix(Coins))
-- 1.09k
```

Use `toESuffix()` once values become extreme:

```lua
Coins = Bnum.fromString("1.2e1000")

print(Bnum.toESuffix(Coins))
-- 1.2E1k
```

A UI helper:

```lua
local function DisplayNumber(Value: buffer): string
	return Bnum.toESuffix(Value)
end
```

Because `toESuffix()` already falls back to `toSuffix()` before exponent 1000, one formatter can handle both normal and extreme progression.

---

# Leaderstats Example

For a display-only value, keep the actual Bnum in your server-side data and expose formatted text separately.

```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bnum = require(
	ReplicatedStorage:WaitForChild("Bnum")
)

Players.PlayerAdded:Connect(function(Player)
	local Leaderstats = Instance.new("Folder")
	Leaderstats.Name = "leaderstats"
	Leaderstats.Parent = Player

	local CoinsDisplay = Instance.new("StringValue")
	CoinsDisplay.Name = "Coins"
	CoinsDisplay.Parent = Leaderstats

	local Coins = Bnum.fromString("1e250")

	CoinsDisplay.Value = Bnum.toSuffix(Coins)
end)
```

For extreme-value games:

```lua
CoinsDisplay.Value = Bnum.toESuffix(Coins)
```

---

# Saving Player Data

A readable serialization pattern:

```lua
local Coins = Bnum.fromString("4.25e300")

local SavedCoins = Bnum.toString(Coins)
```

Restore:

```lua
local Coins = Bnum.fromString(SavedCoins)
```

Player-data example:

```lua
local Data = {
	Coins = Bnum.toString(Coins),
	Power = Bnum.toString(Power),
}
```

Loading:

```lua
local Coins = Bnum.fromString(Data.Coins)
local Power = Bnum.fromString(Data.Power)
```

Keeping serialization at the data boundary means gameplay math remains buffer-native.

---

# Performance Guidelines

For the best Bnum performance:

1. Convert normal values once.
2. Keep Bnum values as buffers during gameplay.
3. Avoid `ensure()` in tight loops.
4. Avoid the compatibility layer in hot loops.
5. Use `addeq`, `subeq`, `muleq`, and `diveq` when mutation is intended.
6. Reuse `addBuffer`, `subBuffer`, `mulBuffer`, and `divBuffer` output buffers when useful.
7. Use `clone()` only when you actually need an independent value.
8. Use direct comparisons such as `eq`, `lt`, `gt`, `lte`, and `gte`.
9. Use `toSuffix()` for compact UI.
10. Use `toESuffix()` when one formatter needs to cover normal and extreme values.
11. Avoid formatting every frame unless the displayed value actually changed.
12. Keep save/load conversion outside gameplay math loops.

---

# Built-In Benchmark

Bnum includes a small microbenchmark helper.

```lua
local Results = Bnum.benchmark(100_000)

for Name, NsPerOperation in Results do
	print(
		Name,
		NsPerOperation,
		"ns/op"
	)
end
```

Current built-in measurements include:

```text
fromNumber
addReuse
mulReuse
cmp
```

The built-in benchmark is a microbenchmark, not a complete game-performance test.

Benchmark in the same Roblox environment and workload you care about before drawing conclusions from small timing differences.

---

# API Reference

## Metadata

```lua
Bnum.VERSION
Bnum.STORAGE_VERSION
Bnum.SIZE
```

Current values:

```text
VERSION         = "1.2.0"
STORAGE_VERSION = 1
SIZE            = 12
```

---

## Construction

```text
ensure(value)
coerce(value)

clone(value)

new(mantissa, exponent)

fromNumber(number)
fromString(string)
```

---

## Conversion

```text
toNumber(value)

toStr(value)
toString(value)
```

---

## Arithmetic

```text
add(a, b)

sub(a, b)
subz(a, b)

mul(a, b)
div(a, b)

pow(a, b)
powf(value, numberPower)
pow10(value)

sqrt(value)
cbrt(value)
root(value, degree)

recip(value)
neg(value)
abs(value)

mod(a, b)
imod(a, b)
intdiv(a, b)
```

---

## Fast Buffer Operations

```text
addBuffer(a, b, out?)
subBuffer(a, b, out?)
mulBuffer(a, b, out?)
divBuffer(a, b, out?)

cmpBuffer(a, b)
```

---

## In-Place Operations

```text
addeq(a, b)
subeq(a, b)
muleq(a, b)
diveq(a, b)
```

---

## Logs

```text
log10(value)
log2(value)

log(value, base?)
ln(value)

exp(value)
```

---

## Comparison

```text
cmp(a, b)
compare(a, b)

eq(a, b)

le(a, b)
me(a, b)
leeq(a, b)
meeq(a, b)

lt(a, b)
gt(a, b)
lte(a, b)
gte(a, b)

min(...)
max(...)
```

---

## Rounding

```text
floor(value)
ceil(value)
round(value)
modf(value)
```

---

## Formatting

```text
toSuffix(value)

toESuffix(value, switchAt?)
toExponentSuffix(value, switchAt?)
toExtendedSuffix(value, switchAt?)

format(value, digits?, hyperAt?)

percent(value, maximum)
```

---

## Inspection

```text
sign(value)
exponent(value)

isNaN(value)
isZero(value)
isPositive(value)
isNegative(value)

isFloat(value)
isFinite(value)
isBnum(value)
```

---

## Random

```text
random()
random(minimum, maximum)
```

---

## Leaderboard Encoding

```text
lbencode(value)
lbdecode(encoded)

encodeData(newValue, oldEncoded?)
```

---

## Purchase / Max Buy

```text
canAfford(funds, cost)

nextCost(cost, multiplier, owned)
nextCostNumber(cost, multiplier, ownedNumber)

bulkCost(cost, multiplier, amount)
bulkCostNumber(cost, multiplier, amountNumber)

maxBuy(funds, currentCost, multiplier)
maxBuyBnum(funds, currentCost, multiplier)

maxBuyLimited(
	funds,
	currentCost,
	multiplier,
	limit
)

buyMax(
	funds,
	currentCost,
	multiplier
)

buyMaxLimited(
	funds,
	currentCost,
	multiplier,
	limit
)
```

Aliases:

```text
maxBuyBig     -> maxBuyBnum
maxBuyCapped  -> maxBuyLimited
buyMaxCapped  -> buyMaxLimited

totalCost     -> bulkCost
costAt        -> nextCost
```

---

## Economy / Scaling

```text
linear(base, increment, level)
linearNumber(base, increment, levelNumber)

softCap(value, cap, power)

milestoneCount(value, step)
milestone(value, step, bonus)

scaleCurve(value, base, exponent, mode)
progress(value, goal, mode)

dynamicCost(cost, owned, scale, method)

eta(current, goal, rate)

clamp(value, minimum, maximum)
```

Scale modes:

```text
linear
exp
sigmoid
```

Dynamic cost methods:

```text
exp
linear
hybrid
```

---

## Compatibility

```text
compat.add
compat.sub
compat.mul
compat.div
compat.pow

compat.cmp
compat.eq

compat.format
compat.toESuffix

compat.maxBuy
compat.maxBuyBnum
compat.maxBuyLimited
compat.buyMaxLimited

compat.bulkCost
compat.nextCost

compat.linear
compat.softCap
compat.milestone
```

---

# v1.2.0 Changes

## New exponent-suffix formatter

Added:

```lua
Bnum.toESuffix()
```

Examples:

```text
1e1000     -> E1k
1e1020     -> E1.02k
1e1200     -> E1.2k
1e1000000  -> E1m
```

Aliases:

```text
toExponentSuffix
toExtendedSuffix
```

---

## `toSuffix()` now truncates

v1.2.0 changed compact suffix display to truncation.

Before the intended v1.2.0 behavior:

```text
1.095e3 -> 1.1k
```

Current behavior:

```text
1.095e3 -> 1.09k
```

This prevents the displayed number from visually advancing before the underlying value reaches that point.

---

## Trailing zero cleanup

```text
1.10k -> 1.1k
1.20k -> 1.2k
```

while preserving meaningful zeros:

```text
1.02k -> 1.02k
```

---

## Whole upgrade counts

`bulkCostNumber()` now floors normal-number purchase amounts.

```text
2.9 purchases -> 2 purchases
```

This keeps upgrade buying integer-based.

---

## v1.2.5 fixes retained

v1.2.0 includes the previous fixes for:

- verified Max Buy affordability boundaries
- flat-cost Max Buy handling
- negative-one power sign behavior
- `maxBuyLimited()`
- `buyMaxLimited()`
- limited-purchase total-cost recalculation

---

# Migration from Older Bnum Releases

## From pre-v1.2 style

Do not rely on every core operation accepting arbitrary strings/numbers.

Instead of repeatedly doing:

```lua
local Result = Bnum.compat.mul(
	"1e100",
	2
)
```

prefer:

```lua
local Value = Bnum.fromString("1e100")
local Multiplier = Bnum.fromNumber(2)

Bnum.mul(Value, Multiplier)
```

---

## From v1.2.5

The main visible change is `toSuffix()`.

If your UI expected rounded compact suffixes:

```text
1.095k -> 1.1k
```

that is no longer the behavior.

v1.2.0 intentionally displays:

```text
1.095k -> 1.09k
```

Use `format()` when rounded display behavior is desired.

---

## Extreme values

If you previously used:

```lua
Bnum.toSuffix(Value)
```

and want compressed exponent notation after `1e1000`, switch to:

```lua
Bnum.toESuffix(Value)
```

Because `toESuffix()` uses `toSuffix()` below its threshold, it can often replace separate normal/extreme formatting logic.

---

# Recommended Project Pattern

## 1. Convert when loading

```lua
local Coins = Bnum.fromString(SavedCoins)
```

## 2. Keep gameplay values as Bnums

```lua
Bnum.addeq(Coins, Reward)
Bnum.muleq(Coins, Multiplier)
```

## 3. Only format for display

```lua
CoinsLabel.Text = Bnum.toESuffix(Coins)
```

## 4. Serialize when saving

```lua
SavedCoins = Bnum.toString(Coins)
```

This keeps string conversion and type checking away from the gameplay hot path.

---

# Full Upgrade Button Example

This combines the v1.2.0 purchase APIs into one practical pattern.

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Bnum = require(ReplicatedStorage.Bnum)

local Money = Bnum.fromString("1e20")

local UpgradeCount = 10

local BaseCost = Bnum.fromNumber(100)
local CostIncrease = Bnum.fromNumber(10)

local function GetCurrentCost(): buffer
	return Bnum.nextCostNumber(
		BaseCost,
		CostIncrease,
		UpgradeCount
	)
end

local function BuyAmount(MaxAmount: number)
	local CurrentCost = GetCurrentCost()

	local Amount, TotalCost, Remaining = Bnum.buyMaxLimited(
		Money,
		CurrentCost,
		CostIncrease,
		MaxAmount
	)

	if Amount <= 0 then
		return
	end

	UpgradeCount += Amount
	Money = Remaining

	print("Bought:", Amount)
	print("Owned:", UpgradeCount)
	print("Spent:", Bnum.toSuffix(TotalCost))
	print("Money:", Bnum.toESuffix(Money))
	print("Next Cost:", Bnum.toESuffix(GetCurrentCost()))
end

BuyAmount(2)
```

If the player owns 10 upgrades and can afford 8:

```text
BuyAmount(2)
```

only purchases:

```text
2
```

so:

```text
10 owned + 2 bought = 12 owned
```

---

# Version

```text
Bnum v1.2.0
Storage Version 1
12-byte buffer representation
```
