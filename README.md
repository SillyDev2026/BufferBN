# Bnum v1.1.0

A high-performance big-number library for Roblox/Luau built around a compact 12-byte `buffer` representation.

Bnum stores a number as:

```text
sign × 10^logMagnitude
```

Instead of keeping the full decimal value in a normal Lua number, Bnum stores the sign and the base-10 logarithm of the magnitude. This makes it practical to work with values far beyond ordinary floating-point display ranges while keeping the representation small and fast.

Bnum v1.1.0 is designed around direct buffer-native calls. Core math functions do not call `ensure()` internally, which keeps hot-path overhead low.

---

## Features

- 12-byte `buffer` representation
- Fast arithmetic and comparisons
- Buffer reuse and in-place math APIs
- Scientific and suffix formatting
- Extended suffix generation
- OrderedDataStore encoding/decoding
- Large-number economy helpers
- Progress, scaling, ETA, and dynamic cost helpers
- NaN and infinity handling
- Explicit compatibility API for numbers and strings
- Built-in microbenchmark helper
- `--!native`
- `--!optimize 2`

---

## Requirements

Bnum v1.1.0 uses Roblox's `buffer` API and is intended for Luau in Roblox.

```lua
--!optimize 2
--!native
```

Recommended ModuleScript name:

```text
ReplicatedStorage
└── Bnum
```

Then require it with:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Bnum = require(ReplicatedStorage:WaitForChild("Bnum"))
```

---

## Quick Start

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Bnum = require(ReplicatedStorage:WaitForChild("Bnum"))

local coins = Bnum.fromNumber(1_000)
local reward = Bnum.fromNumber(250)

coins = Bnum.add(coins, reward)

print(Bnum.format(coins))
print(Bnum.toSuffix(coins))
print(Bnum.toStr(coins))
```

Example output:

```text
1,250
1250
1.25e3
```

---

# Important: Buffer-Native API

Bnum v1.2+ intentionally separates conversion from math.

Core operations expect Bnum buffers:

```lua
local a = Bnum.fromNumber(100)
local b = Bnum.fromNumber(25)

local result = Bnum.add(a, b)
```

Do not repeatedly pass normal numbers into hot-path math.

Instead of:

```lua
-- Not the v1.2 hot-path style
local result = Bnum.compat.add(100, 25)
```

prefer:

```lua
local a = Bnum.fromNumber(100)
local b = Bnum.fromNumber(25)

local result = Bnum.add(a, b)
```

Use `ensure()`, `fromNumber()`, or `fromString()` at system boundaries, then keep values as Bnum buffers internally.

---

# Mutation Rules

Performance is a priority in v1.1.0, so some functions intentionally reuse the first input buffer.

This matters.

## Allocating operation

`add()` creates a new output buffer:

```lua
local a = Bnum.fromNumber(100)
local b = Bnum.fromNumber(50)

local result = Bnum.add(a, b)

print(Bnum.format(a))      -- 100
print(Bnum.format(result)) -- 150
```

## Mutating operations

Several operations reuse and modify the first input buffer:

```lua
local value = Bnum.fromNumber(100)
local multiplier = Bnum.fromNumber(2)

value = Bnum.mul(value, multiplier)

print(Bnum.format(value)) -- 200
```

If you need to preserve the original value, clone it first:

```lua
local original = Bnum.fromNumber(100)
local multiplier = Bnum.fromNumber(2)

local result = Bnum.mul(Bnum.clone(original), multiplier)

print(Bnum.format(original)) -- 100
print(Bnum.format(result))   -- 200
```

As a general rule, treat these as mutating their first Bnum argument:

```text
sub
subz
mul
div
pow
pow10
sqrt
log10
log / ln
exp
root
floor
ceil
round
mod / imod
intdiv
scaleCurve
progress
dynamicCost
abs
eta
```

Use `clone()` whenever the original first argument must remain unchanged.

---

# Creating Bnums

## `fromNumber`

Convert a regular Luau number:

```lua
local coins = Bnum.fromNumber(1_000_000)
local negative = Bnum.fromNumber(-250)
local zero = Bnum.fromNumber(0)
```

---

## `fromString`

Useful for scientific notation and values that are easier to express as text:

```lua
local value = Bnum.fromString("1e100")
local another = Bnum.fromString("2.5e250")
local negative = Bnum.fromString("-7.5e50")
```

Special strings are also supported:

```lua
local nan = Bnum.fromString("NaN")
local inf = Bnum.fromString("Inf")
local negativeInf = Bnum.fromString("-Inf")
```

---

## `new`

`new(mantissa, exponent)` represents:

```text
mantissa × 10^exponent
```

Example:

```lua
local thousand = Bnum.new(1, 3)
local millionAndQuarter = Bnum.new(1.25, 6)

print(Bnum.format(thousand))          -- 1,000
print(Bnum.toSuffix(millionAndQuarter)) -- 1.25m
```

---

## `ensure`

`ensure()` accepts a Bnum buffer, number, or string.

```lua
local a = Bnum.ensure(1000)
local b = Bnum.ensure("2.5e100")
local c = Bnum.ensure(a)
```

For an existing Bnum buffer, it returns that same buffer.

Use this mainly at API boundaries rather than inside tight loops.

`coerce` is an alias:

```lua
local value = Bnum.coerce("1e500")
```

---

## `clone`

Create an independent 12-byte copy:

```lua
local original = Bnum.fromNumber(500)
local copy = Bnum.clone(original)

Bnum.muleq(copy, Bnum.fromNumber(2))

print(Bnum.format(original)) -- 500
print(Bnum.format(copy))     -- 1,000
```

---

# Arithmetic

Create your inputs once:

```lua
local a = Bnum.fromNumber(100)
local b = Bnum.fromNumber(25)
```

## Addition

```lua
local result = Bnum.add(a, b)

print(Bnum.format(result)) -- 125
```

`add()` allocates a new result.

---

## Subtraction

```lua
local result = Bnum.sub(Bnum.clone(a), b)

print(Bnum.format(result)) -- 75
```

`sub()` mutates its first argument.

---

## Zero-Clamped Subtraction

`subz()` prevents the result from becoming negative.

```lua
local health = Bnum.fromNumber(50)
local damage = Bnum.fromNumber(100)

health = Bnum.subz(health, damage)

print(Bnum.format(health)) -- 0
```

---

## Multiplication

```lua
local coins = Bnum.fromNumber(100)
local multiplier = Bnum.fromNumber(3)

coins = Bnum.mul(coins, multiplier)

print(Bnum.format(coins)) -- 300
```

---

## Division

```lua
local value = Bnum.fromNumber(100)
local divisor = Bnum.fromNumber(4)

value = Bnum.div(value, divisor)

print(Bnum.format(value)) -- 25
```

---

## Power

Both arguments are Bnums:

```lua
local base = Bnum.fromNumber(10)
local power = Bnum.fromNumber(6)

local result = Bnum.pow(base, power)

print(Bnum.toSuffix(result)) -- 1m
```

For negative bases, fractional powers that are not real produce NaN.

---

## Power of Ten

```lua
local exponent = Bnum.fromNumber(100)

local value = Bnum.pow10(exponent)

print(Bnum.toStr(value))
```

---

## Square Root

```lua
local value = Bnum.fromNumber(144)

value = Bnum.sqrt(value)

print(Bnum.format(value)) -- 12
```

---

## Root

```lua
local value = Bnum.fromNumber(256)
local degree = Bnum.fromNumber(4)

value = Bnum.root(value, degree)

print(Bnum.format(value)) -- 4
```

---

## Modulo

```lua
local value = Bnum.fromNumber(17)
local divisor = Bnum.fromNumber(5)

value = Bnum.mod(value, divisor)

print(Bnum.format(value)) -- 2
```

Alias:

```lua
Bnum.imod(value, divisor)
```

---

## Integer Division

```lua
local value = Bnum.fromNumber(17)
local divisor = Bnum.fromNumber(5)

value = Bnum.intdiv(value, divisor)

print(Bnum.format(value)) -- 3
```

---

# Fast Buffer API

For systems doing very large numbers of operations, Bnum exposes direct reusable-buffer functions.

```lua
local a = Bnum.fromNumber(100)
local b = Bnum.fromNumber(25)

local out = buffer.create(Bnum.SIZE)

Bnum.addBuffer(a, b, out)

print(Bnum.format(out)) -- 125
```

Available functions:

```text
addBuffer
subBuffer
mulBuffer
divBuffer
cmpBuffer
```

If `out` is omitted, the arithmetic buffer functions allocate one:

```lua
local result = Bnum.mulBuffer(a, b)
```

For maximum control, reuse a scratch buffer:

```lua
local scratch = buffer.create(Bnum.SIZE)

for _ = 1, 1000 do
	Bnum.mulBuffer(a, b, scratch)
end
```

---

# In-Place Math

The `*eq` functions write the result directly into the first buffer.

```lua
local coins = Bnum.fromNumber(100)
local gain = Bnum.fromNumber(25)

Bnum.addeq(coins, gain)

print(Bnum.format(coins)) -- 125
```

Available:

```text
addeq
subeq
muleq
diveq
```

Example:

```lua
local damage = Bnum.fromNumber(100)
local multiplier = Bnum.fromNumber(2)

Bnum.muleq(damage, multiplier)

print(Bnum.format(damage)) -- 200
```

Use these in hot loops when mutation is expected.

---

# Comparisons

```lua
local a = Bnum.fromNumber(100)
local b = Bnum.fromNumber(250)

print(Bnum.cmp(a, b)) -- -1
print(Bnum.eq(a, b))  -- false
print(Bnum.lt(a, b))  -- true
print(Bnum.gt(a, b))  -- false
print(Bnum.lte(a, b)) -- true
print(Bnum.gte(a, b)) -- false
```

`cmp()` returns:

```text
-1  a < b
 0  a == b
 1  a > b
```

Aliases:

```text
cmp      compare
le       lt
me       gt
leeq     lte
meeq     gte
```

For new code, the `lt`, `gt`, `lte`, and `gte` aliases are usually clearer.

---

## Min / Max

```lua
local a = Bnum.fromNumber(10)
local b = Bnum.fromNumber(500)
local c = Bnum.fromNumber(25)

local smallest = Bnum.min(a, b, c)
local largest = Bnum.max(a, b, c)

print(Bnum.format(smallest)) -- 10
print(Bnum.format(largest))  -- 500
```

`min()` and `max()` return one of the existing input buffers rather than cloning it.

---

# Rounding

```lua
local value = Bnum.fromNumber(12.75)

local floored = Bnum.floor(Bnum.clone(value))
local ceiled = Bnum.ceil(Bnum.clone(value))
local rounded = Bnum.round(Bnum.clone(value))

print(Bnum.format(floored)) -- 12
print(Bnum.format(ceiled))  -- 13
print(Bnum.format(rounded)) -- 13
```

---

# Logarithms

## Base 10

```lua
local value = Bnum.fromNumber(1000)

value = Bnum.log10(value)

print(Bnum.format(value)) -- 3
```

---

## Natural Log

```lua
local value = Bnum.fromNumber(10)

value = Bnum.ln(value)

print(Bnum.format(value))
```

`ln` is an alias of `log` when no base is supplied.

---

## Custom Base

```lua
local value = Bnum.fromNumber(1000)
local base = Bnum.fromNumber(10)

value = Bnum.log(value, base)

print(Bnum.format(value)) -- 3
```

---

## Exponential

```lua
local value = Bnum.fromNumber(2)

value = Bnum.exp(value)

print(Bnum.format(value))
```

---

# Formatting

Bnum intentionally separates the dedicated fast suffix formatter from the more flexible generic formatter.

## `toSuffix`

Use `toSuffix()` for hot UI paths:

```lua
local coins = Bnum.fromNumber(1_250_000)

print(Bnum.toSuffix(coins))
```

Example:

```text
1.25m
```

Large suffixes are generated from Bnum's extended suffix system.

Very large values beyond the suffix range fall back to scientific notation.

Tiny values can use reciprocal-style formatting.

Example:

```lua
local tiny = Bnum.fromString("1e-6")

print(Bnum.toSuffix(tiny))
```

Example output:

```text
1/1m
```

---

## `format`

`format()` is the general-purpose formatter.

```lua
local value = Bnum.fromNumber(123456)

print(Bnum.format(value))
```

Example:

```text
123,456
```

For large values:

```lua
local value = Bnum.fromString("1.2345e250")

print(Bnum.format(value))
```

Example:

```text
123.45...
```

The exact suffix/body depends on the value and requested precision.

Specify decimal precision:

```lua
print(Bnum.format(value, 2))
print(Bnum.format(value, 3))
print(Bnum.format(value, 4))
```

Optional hyper/scientific cutoff:

```lua
print(Bnum.format(value, 2, 1e9))
```

Use:

```text
toSuffix()  when display speed is the priority
format()    when you need the full formatting behavior
```

---

# Storage Strings

Use `toStr()` / `toString()` when you want a scientific string representation.

```lua
local value = Bnum.fromString("1.25e100")

local encoded = Bnum.toStr(value)

print(encoded)
```

`toString` is an alias:

```lua
local encoded = Bnum.toString(value)
```

You can restore it with:

```lua
local restored = Bnum.fromString(encoded)
```

Example round trip:

```lua
local original = Bnum.fromString("7.5e250")
local serialized = Bnum.toStr(original)
local restored = Bnum.fromString(serialized)

print(Bnum.eq(original, restored))
```

---

# OrderedDataStore Encoding

Roblox OrderedDataStores require numeric sortable values.

Bnum provides:

```text
lbencode
lbdecode
```

Example:

```lua
local coins = Bnum.fromString("1e500")

local orderedValue = Bnum.lbencode(coins)

print(orderedValue)
```

Restore it:

```lua
local restored = Bnum.lbdecode(orderedValue)

print(Bnum.toSuffix(restored))
```

This encoding is intended for ranking/leaderboard use.

For normal persistent player data, storing a Bnum string or your own serialized representation may be easier to inspect.

---

## `encodeData`

`encodeData(new, old?)` returns the encoded leaderboard value.

If an `old` encoded number is supplied and it is greater than the new encoded value, the old value is preserved.

```lua
local coins = Bnum.fromString("1e100")

local encoded = Bnum.encodeData(coins)
```

With an existing score:

```lua
local encoded = Bnum.encodeData(coins, previousEncodedScore)
```

---

# Inspection

```lua
local value = Bnum.fromNumber(-500)

print(Bnum.sign(value))
print(Bnum.exponent(value))
print(Bnum.isNegative(value))
print(Bnum.isPositive(value))
print(Bnum.isZero(value))
print(Bnum.isNaN(value))
print(Bnum.isBnum(value))
```

Available:

```text
sign
exponent
isNaN
isZero
isPositive
isNegative
isBnum
```

`exponent()` returns the internal base-10 logarithmic magnitude, not a normal scientific-notation exponent field.

---

# Absolute Value

`abs()` mutates the supplied buffer.

```lua
local value = Bnum.fromNumber(-500)

Bnum.abs(value)

print(Bnum.format(value)) -- 500
```

Preserve the original with:

```lua
local positive = Bnum.abs(Bnum.clone(value))
```

---

# Clamp

```lua
local value = Bnum.fromNumber(150)
local minimum = Bnum.fromNumber(0)
local maximum = Bnum.fromNumber(100)

local clamped = Bnum.clamp(value, minimum, maximum)

print(Bnum.format(clamped)) -- 100
```

`clamp()` may return one of the existing input buffers.

---

# Split Integer / Fraction

```lua
local value = Bnum.fromNumber(12.75)

local integer, fraction = Bnum.modf(value)

print(Bnum.format(integer))  -- 12
print(Bnum.format(fraction)) -- 0.75
```

---

# Random Bnums

No arguments:

```lua
local value = Bnum.random()
```

For positive ranges:

```lua
local minimum = Bnum.fromNumber(1)
local maximum = Bnum.fromString("1e100")

local value = Bnum.random(minimum, maximum)
```

Bnum interpolates positive ranged random values in logarithmic space, making it useful when the range spans many orders of magnitude.

---

# Game Economy Helpers

Bnum includes helpers aimed at simulator, incremental, and economy systems.

---

## Max Buy

Calculate how many geometric-price purchases can be afforded.

```lua
local funds = Bnum.fromString("1e12")
local baseCost = Bnum.fromNumber(100)
local multiplier = Bnum.fromNumber(1.15)

local amount, totalCost = Bnum.maxBuy(
	Bnum.clone(funds),
	baseCost,
	multiplier
)

print("Can buy:", amount)
print("Total cost:", Bnum.toSuffix(totalCost))
```

Using a clone for `funds` is recommended if the original value must always be preserved.

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
local baseCost = Bnum.fromNumber(100)
local owned = Bnum.fromNumber(25)
local scale = Bnum.fromNumber(1.15)

local nextCost = Bnum.dynamicCost(
	Bnum.clone(baseCost),
	owned,
	scale,
	"exp"
)

print(Bnum.toSuffix(nextCost))
```

Because `dynamicCost()` reuses its first argument, clone the base cost when it must remain unchanged.

---

## Scale Curve

Modes:

```text
linear
exp
sigmoid
```

Example:

```lua
local value = Bnum.fromNumber(1000)
local base = Bnum.fromNumber(100)
local exponent = Bnum.fromNumber(2)

local scaled = Bnum.scaleCurve(
	Bnum.clone(value),
	base,
	exponent,
	"exp"
)

print(Bnum.format(scaled))
```

---

## Progress

```lua
local current = Bnum.fromNumber(750)
local goal = Bnum.fromNumber(1000)

local progress = Bnum.progress(
	Bnum.clone(current),
	goal,
	"linear"
)

print(Bnum.percent(progress, Bnum.fromNumber(1)))
```

Available modes:

```text
linear
exp
sigmoid
```

---

## Percent

`percent()` returns a string including `%`.

```lua
local current = Bnum.fromNumber(25)
local maximum = Bnum.fromNumber(100)

print(Bnum.percent(current, maximum))
```

Example:

```text
25%
```

---

## ETA

Estimate remaining time-like units from a current value, goal, and rate.

```lua
local current = Bnum.fromNumber(250)
local goal = Bnum.fromNumber(1000)
local rate = Bnum.fromNumber(50)

local eta = Bnum.eta(
	Bnum.clone(current),
	goal,
	rate
)

print(Bnum.format(eta))
```

`eta()` reuses the first input buffer.

---

# Compatibility API

v1.1.0 keeps flexible number/string conversion out of the normal hot path.

If convenience matters more than raw performance:

```lua
local result = Bnum.compat.add(100, "2.5e3")

print(Bnum.format(result))
```

Available compatibility helpers:

```text
compat.add
compat.sub
compat.mul
compat.div
compat.pow
compat.cmp
compat.eq
compat.format
```

Example:

```lua
local result = Bnum.compat.mul("1e100", 2)

print(Bnum.toStr(result))
```

The compatibility layer internally calls `ensure()`.

For performance-sensitive code, convert values once and use the buffer-native API.

---

# Simulator Example

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Bnum = require(ReplicatedStorage:WaitForChild("Bnum"))

local coins = Bnum.fromNumber(0)
local clickPower = Bnum.fromNumber(1)
local multiplier = Bnum.fromNumber(2)

local function click()
	Bnum.addeq(coins, clickPower)
	print("Coins:", Bnum.toSuffix(coins))
end

local function buyMultiplier()
	Bnum.muleq(clickPower, multiplier)
	print("Click Power:", Bnum.toSuffix(clickPower))
end

for _ = 1, 10 do
	click()
end

buyMultiplier()
click()
```

---

# Leaderstats Example

Roblox `NumberValue` cannot represent the full practical range of Bnum values.

For display-only leaderstats, use a `StringValue`:

```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bnum = require(ReplicatedStorage:WaitForChild("Bnum"))

Players.PlayerAdded:Connect(function(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local coinsLabel = Instance.new("StringValue")
	coinsLabel.Name = "Coins"
	coinsLabel.Parent = leaderstats

	local coins = Bnum.fromString("1e250")

	coinsLabel.Value = Bnum.toSuffix(coins)
end)
```

Keep the actual Bnum in your server-side data model and use the StringValue only as the displayed representation.

---

# Saving Example

A simple readable save format:

```lua
local value = Bnum.fromString("4.25e300")

local saved = Bnum.toStr(value)
```

Load it again:

```lua
local restored = Bnum.fromString(saved)
```

For a player-data table:

```lua
local data = {
	Coins = Bnum.toStr(coins),
	Power = Bnum.toStr(clickPower),
}
```

Restore:

```lua
local coins = Bnum.fromString(data.Coins)
local clickPower = Bnum.fromString(data.Power)
```

---

# Performance Guidelines

For the best performance:

1. Convert numbers and strings once.
2. Keep Bnum values as buffers internally.
3. Avoid `ensure()` in tight loops.
4. Use `toSuffix()` for frequently refreshed UI.
5. Use `format()` when you need its general formatting behavior.
6. Use `addeq`, `subeq`, `muleq`, and `diveq` when mutation is safe.
7. Reuse output buffers with `addBuffer`, `subBuffer`, `mulBuffer`, and `divBuffer` when appropriate.
8. Use `clone()` before mutating a value that must be preserved.
9. Prefer direct comparisons such as `eq`, `lt`, `gt`, `lte`, and `gte`.

---

# v1.1.0 Benchmark Snapshot

Example results from a Roblox Studio FULL benchmark run:

```text
Scored common comparisons: 31
Bnum v1.1.0 wins:          31
FoundForces wins:           0
Geometric mean:             Bnum v1.1.0 ~1.817x faster
```

Selected results:

| Operation | Bnum v1.1.0 | FoundForces | Relative result |
|---|---:|---:|---:|
| `cmp` | 36.160 ns | 41.629 ns | Bnum 1.151x |
| `eq` | 30.238 ns | 59.030 ns | Bnum 1.952x |
| `mul` | 43.855 ns | 71.622 ns | Bnum 1.633x |
| `div` | 44.580 ns | 72.704 ns | Bnum 1.631x |
| `sqrt` | 31.654 ns | 65.135 ns | Bnum 2.058x |
| `root` | 54.749 ns | 137.026 ns | Bnum 2.503x |
| `lbencode` | 71.703 ns | 213.011 ns | Bnum 2.971x |
| `toSuffix ~1e250` | 140.136 ns | 150.069 ns | Bnum 1.071x |
| `toSuffix ~1e2500` | 140.766 ns | 154.173 ns | Bnum 1.095x |

Benchmark results depend on hardware, Roblox Studio/runtime state, native compilation, and workload. Use the included benchmark tools to measure performance in your own project.

---

# Built-In Benchmark

Bnum includes a small benchmark helper:

```lua
local results = Bnum.benchmark(100_000)

for name, ns in results do
	print(name, ns, "ns/op")
end
```

It currently measures core operations such as:

```text
fromNumber
addReuse
mulReuse
cmp
```

Use the full comparison benchmark for more detailed profiling.

---

# API Reference

## Construction

```text
ensure(value)
coerce(value)
clone(value)
new(mantissa, exponent)
fromNumber(number)
fromString(string)
```

## Arithmetic

```text
add(a, b)
sub(a, b)
subz(a, b)
mul(a, b)
div(a, b)
pow(a, b)
pow10(value)
sqrt(value)
root(value, degree)
mod(a, b)
imod(a, b)
intdiv(a, b)
abs(value)
```

## Buffer / In-Place

```text
addBuffer(a, b, out?)
subBuffer(a, b, out?)
mulBuffer(a, b, out?)
divBuffer(a, b, out?)
cmpBuffer(a, b)

addeq(a, b)
subeq(a, b)
muleq(a, b)
diveq(a, b)
```

## Logs

```text
log10(value)
log(value, base?)
ln(value)
exp(value)
```

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

## Rounding

```text
floor(value)
ceil(value)
round(value)
modf(value)
```

## Formatting

```text
toSuffix(value)
format(value, digits?, hyperAt?)
toStr(value)
toString(value)
percent(a, b)
```

## Encoding

```text
lbencode(value)
lbdecode(number)
encodeData(value, old?)
```

## Inspection

```text
sign(value)
exponent(value)
isNaN(value)
isZero(value)
isPositive(value)
isNegative(value)
isBnum(value)
```

## Utility / Economy

```text
random(min?, max?)
clamp(value, min, max)

maxBuy(funds, cost, multiplier)
scaleCurve(value, base, exponent, mode)
progress(value, goal, mode)
dynamicCost(cost, owned, scale, method)
eta(current, goal, rate)
```

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
```

## Metadata

```lua
print(Bnum.VERSION)         -- "1.1.0"
print(Bnum.STORAGE_VERSION) -- 1
print(Bnum.SIZE)            -- 12
```

---

# Migration Notes for v1.2+

The biggest API rule introduced by the v1.2 line is:

> Core math functions operate directly on Bnum buffers and do not automatically coerce every argument.

Old convenience-style code:

```lua
local result = Bnum.compat.add(100, "1e6")
```

Recommended v1.1.0 code:

```lua
local a = Bnum.fromNumber(100)
local b = Bnum.fromString("1e6")

local result = Bnum.add(a, b)
```

This removes repeated type checking and conversion overhead from the hot path.

---

# Recommended Project Pattern

Convert at the edge:

```lua
local coins = Bnum.fromString(savedCoins)
```

Operate with Bnums:

```lua
Bnum.addeq(coins, reward)
Bnum.muleq(coins, multiplier)
```

Display only when needed:

```lua
coinsLabel.Text = Bnum.toSuffix(coins)
```

Serialize only when saving:

```lua
savedCoins = Bnum.toStr(coins)
```

That pattern keeps conversion and string work away from gameplay math.

---

# Version

```text
Bnum v1.1.0
Storage Version 1
Buffer Size 12 bytes
```

