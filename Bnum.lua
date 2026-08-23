--!optimize 2
--!native

local bcreate = buffer.create
local bcopy = buffer.copy
local breadi8 = buffer.readi8
local breadf64 = buffer.readf64
local bwritei8 = buffer.writei8
local bwritef64 = buffer.writef64

local abs = math.abs
local ceil = math.ceil
local expm = math.exp
local floor = math.floor
local huge = math.huge
local log10 = math.log10
local random = math.random
local round = math.round
local signm = math.sign

local find = string.find
local sub = string.sub
local tonumber = tonumber
local tostring = tostring
local type = type

local SIZE = 12
local SIGN_OFFSET = 0
local LOG_OFFSET = 4
local NAN_SIGN = -2
local DOMINANCE = 16
local LOG10_E = 0.4342944819032518
local LB_SCALE = 4503599627370496

local firstset = {"", "U", "D", "T", "Qd", "Qn", "Sx", "Sp", "Oc", "No"}
local second = {"", "De", "Vt", "Tg", "qg", "Qg", "sg", "Sg", "Og", "Ng"}
local third = {"", "Ce", "Du", "Tr", "Qa", "Qi", "Se", "Si", "Ot", "Ni"}

local ZERO = bcreate(SIZE)
bwritei8(ZERO, SIGN_OFFSET, 0)
bwritef64(ZERO, LOG_OFFSET, 0)

local ONE = bcreate(SIZE)
bwritei8(ONE, SIGN_OFFSET, 1)
bwritef64(ONE, LOG_OFFSET, 0)

local NAN = bcreate(SIZE)
bwritei8(NAN, SIGN_OFFSET, NAN_SIGN)
bwritef64(NAN, LOG_OFFSET, 0)

local INF = bcreate(SIZE)
bwritei8(INF, SIGN_OFFSET, 1)
bwritef64(INF, LOG_OFFSET, huge)

local NEG_INF = bcreate(SIZE)
bwritei8(NEG_INF, SIGN_OFFSET, -1)
bwritef64(NEG_INF, LOG_OFFSET, huge)

local module = {
	VERSION = "1.1.0",
	STORAGE_VERSION = 1,
	SIZE = SIZE,
}

local function setRaw(out: buffer, s: number, l: number): buffer
	bwritei8(out, SIGN_OFFSET, s)
	bwritef64(out, LOG_OFFSET, l)
	return out
end

local function makeRaw(s: number, l: number): buffer
	local out = bcreate(SIZE)
	bwritei8(out, SIGN_OFFSET, s)
	bwritef64(out, LOG_OFFSET, l)
	return out
end

local function cloneRaw(src: buffer): buffer
	local out = bcreate(SIZE)
	bcopy(out, 0, src, 0, SIZE)
	return out
end

local function fromFiniteNumber(n: number): buffer
	if n == 0 then
		return makeRaw(0, 0)
	end
	return makeRaw(signm(n), log10(abs(n)))
end

local function cmpRaw(a: buffer, b: buffer): number
	local sa = breadi8(a, SIGN_OFFSET)
	local sb = breadi8(b, SIGN_OFFSET)
	if sa ~= sb then
		return if sa > sb then 1 else -1
	end

	local la = breadf64(a, LOG_OFFSET)
	local lb = breadf64(b, LOG_OFFSET)
	if la > lb then return sa end
	if la < lb then return -sa end
	return if sa == NAN_SIGN then -1 else 0
end

local function addRaw(out: buffer, a: buffer, b: buffer): buffer
	local s1 = breadi8(a, SIGN_OFFSET)
	local s2 = breadi8(b, SIGN_OFFSET)
	if s1 == NAN_SIGN or s2 == NAN_SIGN then
		return setRaw(out, NAN_SIGN, 0)
	end
	if s1 == 0 then
		bcopy(out, 0, b, 0, SIZE)
		return out
	end
	if s2 == 0 then
		bcopy(out, 0, a, 0, SIZE)
		return out
	end

	local l1 = breadf64(a, LOG_OFFSET)
	local l2 = breadf64(b, LOG_OFFSET)
	if l1 == huge or l2 == huge then
		if l1 == huge and l2 == huge and s1 ~= s2 then
			return setRaw(out, NAN_SIGN, 0)
		end
		if l1 == huge then
			return setRaw(out, s1, huge)
		end
		return setRaw(out, s2, huge)
	end

	local d = l1 - l2
	if d > DOMINANCE then
		bcopy(out, 0, a, 0, SIZE)
		return out
	end
	if d < -DOMINANCE then
		bcopy(out, 0, b, 0, SIZE)
		return out
	end
	if d == 0 and s1 ~= s2 then
		return setRaw(out, 0, 0)
	end

	if s1 == s2 then
		if d >= 0 then
			return setRaw(out, s1, l1 + log10(1 + 10 ^ (-d)))
		end
		return setRaw(out, s1, l2 + log10(1 + 10 ^ d))
	end

	if d > 0 then
		return setRaw(out, s1, l1 + log10(1 - 10 ^ (-d)))
	end
	if d < 0 then
		return setRaw(out, s2, l2 + log10(1 - 10 ^ d))
	end
	return setRaw(out, 0, 0)
end

local function subRaw(out: buffer, a: buffer, b: buffer): buffer
	local s1 = breadi8(a, SIGN_OFFSET)
	local s2 = breadi8(b, SIGN_OFFSET)
	if s1 == NAN_SIGN or s2 == NAN_SIGN then
		return setRaw(out, NAN_SIGN, 0)
	end
	if s2 == 0 then
		bcopy(out, 0, a, 0, SIZE)
		return out
	end
	if s1 == 0 then
		bcopy(out, 0, b, 0, SIZE)
		bwritei8(out, SIGN_OFFSET, -s2)
		return out
	end

	local l1 = breadf64(a, LOG_OFFSET)
	local l2 = breadf64(b, LOG_OFFSET)
	if l1 == huge or l2 == huge then
		if l1 == huge and l2 == huge and s1 == s2 then
			return setRaw(out, NAN_SIGN, 0)
		end
		if l1 == huge then
			return setRaw(out, s1, huge)
		end
		return setRaw(out, -s2, huge)
	end

	local d = l1 - l2
	if d > DOMINANCE then
		bcopy(out, 0, a, 0, SIZE)
		return out
	end
	if d < -DOMINANCE then
		bcopy(out, 0, b, 0, SIZE)
		bwritei8(out, SIGN_OFFSET, -s2)
		return out
	end
	if d == 0 and s1 == s2 then
		return setRaw(out, 0, 0)
	end

	if s1 ~= s2 then
		if d >= 0 then
			return setRaw(out, s1, l1 + log10(1 + 10 ^ (-d)))
		end
		return setRaw(out, s1, l2 + log10(1 + 10 ^ d))
	end

	if d > 0 then
		return setRaw(out, s1, l1 + log10(1 - 10 ^ (-d)))
	end
	if d < 0 then
		return setRaw(out, -s1, l2 + log10(1 - 10 ^ d))
	end
	return setRaw(out, 0, 0)
end

local function mulRaw(out: buffer, a: buffer, b: buffer): buffer
	local s1 = breadi8(a, SIGN_OFFSET)
	local s2 = breadi8(b, SIGN_OFFSET)
	if s1 == NAN_SIGN or s2 == NAN_SIGN then
		return setRaw(out, NAN_SIGN, 0)
	end
	if s1 == 0 or s2 == 0 then
		local l1 = breadf64(a, LOG_OFFSET)
		local l2 = breadf64(b, LOG_OFFSET)
		if l1 == huge or l2 == huge then
			return setRaw(out, NAN_SIGN, 0)
		end
		return setRaw(out, 0, 0)
	end
	return setRaw(out, s1 * s2, breadf64(a, LOG_OFFSET) + breadf64(b, LOG_OFFSET))
end

local function divRaw(out: buffer, a: buffer, b: buffer): buffer
	local s1 = breadi8(a, SIGN_OFFSET)
	local s2 = breadi8(b, SIGN_OFFSET)
	if s1 == NAN_SIGN or s2 == NAN_SIGN then
		return setRaw(out, NAN_SIGN, 0)
	end
	if s2 == 0 then
		if s1 == 0 then
			return setRaw(out, NAN_SIGN, 0)
		end
		return setRaw(out, s1, huge)
	end
	if s1 == 0 then
		return setRaw(out, 0, 0)
	end
	local l1 = breadf64(a, LOG_OFFSET)
	local l2 = breadf64(b, LOG_OFFSET)
	if l1 == huge and l2 == huge then
		return setRaw(out, NAN_SIGN, 0)
	end
	return setRaw(out, s1 * s2, l1 - l2)
end

local suffixCache = table.create(1000)
suffixCache[0] = ""
suffixCache[1] = "k"
suffixCache[2] = "m"
suffixCache[3] = "b"
for k = 4, 999 do
	local i = k - 1
	suffixCache[k] = firstset[i % 10 + 1] .. second[(i // 10) % 10 + 1] .. third[(i // 100) % 10 + 1]
end

local suffixExactMantissa = {"1", "10", "100"}


local function roundedNumber(n: number, digits: number): number
	local p = 10 ^ digits
	return floor(n * p + 0.5) / p
end

function module.ensure(val: any): buffer
	local t = type(val)
	if t == "buffer" then
		return val
	end
	if t == "number" then
		if val ~= val then
			return cloneRaw(NAN)
		end
		if val == huge then
			return cloneRaw(INF)
		end
		if val == -huge then
			return cloneRaw(NEG_INF)
		end
		return fromFiniteNumber(val)
	end
	if t == "string" then
		if val == "NaN" or val == "nan" then
			return cloneRaw(NAN)
		end
		if val == "Inf" or val == "inf" or val == "+Inf" or val == "+inf" then
			return cloneRaw(INF)
		end
		if val == "-Inf" or val == "-inf" then
			return cloneRaw(NEG_INF)
		end
		local e = find(val, "e", 1, true) or find(val, "E", 1, true)
		if e then
			local man = tonumber(sub(val, 1, e - 1))
			local exponent = tonumber(sub(val, e + 1))
			if not man or not exponent or man ~= man or exponent ~= exponent then
				return cloneRaw(NAN)
			end
			if man == 0 then
				return cloneRaw(ZERO)
			end
			return makeRaw(signm(man), log10(abs(man)) + exponent)
		end
		local n = tonumber(val)
		if not n or n ~= n then
			return cloneRaw(NAN)
		end
		if n == huge then return cloneRaw(INF) end
		if n == -huge then return cloneRaw(NEG_INF) end
		return fromFiniteNumber(n)
	end
	error("Unsupported type: " .. t, 2)
end

module.coerce = module.ensure

function module.clone(val: buffer): buffer
	return cloneRaw(val)
end

function module.new(man: number, exponent: number): buffer
	if man ~= man or exponent ~= exponent then
		return cloneRaw(NAN)
	end
	if man == 0 then
		return cloneRaw(ZERO)
	end
	return makeRaw(signm(man), log10(abs(man)) + exponent)
end

function module.fromNumber(val: number): buffer
	if type(val) ~= "number" or val ~= val then
		return cloneRaw(NAN)
	end
	if val == huge then return cloneRaw(INF) end
	if val == -huge then return cloneRaw(NEG_INF) end
	return fromFiniteNumber(val)
end

function module.fromString(val: string): buffer
	if val == "NaN" or val == "nan" then return cloneRaw(NAN) end
	if val == "Inf" or val == "inf" or val == "+Inf" or val == "+inf" then return cloneRaw(INF) end
	if val == "-Inf" or val == "-inf" then return cloneRaw(NEG_INF) end
	local e = find(val, "e", 1, true) or find(val, "E", 1, true)
	if e then
		local man = tonumber(sub(val, 1, e - 1))
		local exponent = tonumber(sub(val, e + 1))
		if not man or not exponent or man ~= man or exponent ~= exponent then return cloneRaw(NAN) end
		if man == 0 then return cloneRaw(ZERO) end
		return makeRaw(signm(man), log10(abs(man)) + exponent)
	end
	local n = tonumber(val)
	if not n or n ~= n then return cloneRaw(NAN) end
	if n == huge then return cloneRaw(INF) end
	if n == -huge then return cloneRaw(NEG_INF) end
	return fromFiniteNumber(n)
end

function module.addBuffer(a: buffer, b: buffer, out: buffer?): buffer
	return addRaw(out or bcreate(SIZE), a, b)
end

function module.subBuffer(a: buffer, b: buffer, out: buffer?): buffer
	return subRaw(out or bcreate(SIZE), a, b)
end

function module.mulBuffer(a: buffer, b: buffer, out: buffer?): buffer
	return mulRaw(out or bcreate(SIZE), a, b)
end

function module.divBuffer(a: buffer, b: buffer, out: buffer?): buffer
	return divRaw(out or bcreate(SIZE), a, b)
end

module.cmpBuffer = cmpRaw

function module.addeq(a: buffer, b: buffer): buffer
	return addRaw(a, a, b)
end

function module.subeq(a: buffer, b: buffer): buffer
	return subRaw(a, a, b)
end

function module.muleq(a: buffer, b: buffer): buffer
	return mulRaw(a, a, b)
end

function module.diveq(a: buffer, b: buffer): buffer
	return divRaw(a, a, b)
end

function module.add(val1: buffer, val2: buffer): buffer
	local a = val1
	local b = val2
	return addRaw(bcreate(SIZE), a, b)
end

function module.sub(val1: buffer, val2: buffer): buffer
	local a = val1
	local b = val2
	return subRaw(a, a, b)
end

function module.subz(val1: buffer, val2: buffer): buffer
	local a = module.sub(val1, val2)
	if breadi8(a, SIGN_OFFSET) < 0 then
		return setRaw(a, 0, 0)
	end
	return a
end

function module.mul(val1: buffer, val2: buffer): buffer
	local a = val1
	local b = val2
	return mulRaw(a, a, b)
end

function module.div(val1: buffer, val2: buffer): buffer
	local a = val1
	local b = val2
	return divRaw(a, a, b)
end

function module.pow(val1: buffer, val2: buffer): buffer
	local a = val1
	local b = val2
	local s1 = breadi8(a, SIGN_OFFSET)
	local s2 = breadi8(b, SIGN_OFFSET)
	if s1 == NAN_SIGN or s2 == NAN_SIGN then
		return setRaw(a, NAN_SIGN, 0)
	end
	if s2 == 0 then
		return setRaw(a, 1, 0)
	end
	if s1 == 0 then
		if s2 < 0 then
			return setRaw(a, 1, huge)
		end
		return setRaw(a, 0, 0)
	end

	local l1 = breadf64(a, LOG_OFFSET)
	local l2 = breadf64(b, LOG_OFFSET)
	if l1 == 0 then
		return setRaw(a, 1, 0)
	end
	local power = s2 * 10 ^ l2
	local outSign = 1
	if s1 < 0 then
		if power ~= power or power == huge or power == -huge then
			return setRaw(a, NAN_SIGN, 0)
		end
		local nearest = round(power)
		if abs(power - nearest) > 1e-10 then
			return setRaw(a, NAN_SIGN, 0)
		end
		if nearest % 2 ~= 0 then
			outSign = -1
		end
	end
	local resultLog = l1 * power
	if resultLog ~= resultLog then return setRaw(a, NAN_SIGN, 0) end
	if resultLog == -huge then return setRaw(a, 0, 0) end
	return setRaw(a, outSign, resultLog)
end

function module.pow10(val: buffer): buffer
	local a = val
	local s = breadi8(a, SIGN_OFFSET)
	if s == NAN_SIGN then
		return setRaw(a, NAN_SIGN, 0)
	end
	if s == 0 then
		return setRaw(a, 1, 0)
	end
	local l = breadf64(a, LOG_OFFSET)
	if l == huge then
		if s > 0 then
			return setRaw(a, 1, huge)
		end
		return setRaw(a, 0, 0)
	end
	return setRaw(a, 1, s * 10 ^ l)
end

function module.sqrt(val: buffer): buffer
	local a = val
	local s = breadi8(a, SIGN_OFFSET)
	if s == NAN_SIGN or s < 0 then
		return setRaw(a, NAN_SIGN, 0)
	end
	if s == 0 then
		return setRaw(a, 0, 0)
	end
	return setRaw(a, 1, breadf64(a, LOG_OFFSET) * 0.5)
end

function module.log10(val: buffer): buffer
	local a = val
	local s = breadi8(a, SIGN_OFFSET)
	if s <= 0 then
		return setRaw(a, NAN_SIGN, 0)
	end
	local l = breadf64(a, LOG_OFFSET)
	if l == 0 then
		return setRaw(a, 0, 0)
	end
	if l == huge then
		return setRaw(a, 1, huge)
	end
	return setRaw(a, signm(l), log10(abs(l)))
end

function module.log(val1: buffer, val2: buffer?): buffer
	local a = val1
	local s1 = breadi8(a, SIGN_OFFSET)
	if s1 <= 0 then
		return setRaw(a, NAN_SIGN, 0)
	end
	local l1 = breadf64(a, LOG_OFFSET)
	if val2 == nil then
		local result = l1 * 2.302585092994046
		if result == 0 then return setRaw(a, 0, 0) end
		return setRaw(a, signm(result), log10(abs(result)))
	end
	local b = val2
	local s2 = breadi8(b, SIGN_OFFSET)
	if s2 <= 0 then
		return setRaw(a, NAN_SIGN, 0)
	end
	local l2 = breadf64(b, LOG_OFFSET)
	if l2 == 0 then
		return setRaw(a, NAN_SIGN, 0)
	end
	local result = l1 / l2
	if result == 0 then return setRaw(a, 0, 0) end
	return setRaw(a, signm(result), log10(abs(result)))
end

module.ln = module.log

function module.exp(val: buffer): buffer
	local a = val
	local s = breadi8(a, SIGN_OFFSET)
	if s == NAN_SIGN then
		return setRaw(a, NAN_SIGN, 0)
	end
	if s == 0 then
		return setRaw(a, 1, 0)
	end
	local l = breadf64(a, LOG_OFFSET)
	if l == huge then
		if s > 0 then return setRaw(a, 1, huge) end
		return setRaw(a, 0, 0)
	end
	return setRaw(a, 1, LOG10_E * s * 10 ^ l)
end

function module.random(val1: buffer?, val2: buffer?): buffer
	if val1 == nil and val2 == nil then
		return fromFiniteNumber(random())
	end
	if val2 == nil then
		val2 = val1
		val1 = ZERO
	end
	local a = val1 :: buffer
	local b = val2 :: buffer
	if cmpRaw(a, b) > 0 then
		a, b = b, a
	end
	local s1 = breadi8(a, SIGN_OFFSET)
	local s2 = breadi8(b, SIGN_OFFSET)
	if s1 <= 0 or s2 <= 0 then
		return fromFiniteNumber(random())
	end
	local l1 = breadf64(a, LOG_OFFSET)
	local l2 = breadf64(b, LOG_OFFSET)
	return makeRaw(1, l1 + random() * (l2 - l1))
end

module.cmp = cmpRaw

function module.eq(val1: buffer, val2: buffer): boolean
	local s1 = breadi8(val1, SIGN_OFFSET)
	local s2 = breadi8(val2, SIGN_OFFSET)
	if s1 ~= s2 or s1 == NAN_SIGN then return false end
	if s1 == 0 then return true end
	return breadf64(val1, LOG_OFFSET) == breadf64(val2, LOG_OFFSET)
end

function module.le(val1: buffer, val2: buffer): boolean
	local s1 = breadi8(val1, SIGN_OFFSET)
	local s2 = breadi8(val2, SIGN_OFFSET)
	if s1 ~= s2 then return s1 < s2 end
	if s1 == NAN_SIGN then return false end
	if s1 == 0 then return false end
	local l1 = breadf64(val1, LOG_OFFSET)
	local l2 = breadf64(val2, LOG_OFFSET)
	return if s1 > 0 then l1 < l2 else l1 > l2
end

function module.me(val1: buffer, val2: buffer): boolean
	local s1 = breadi8(val1, SIGN_OFFSET)
	local s2 = breadi8(val2, SIGN_OFFSET)
	if s1 ~= s2 then return s1 > s2 end
	if s1 == NAN_SIGN then return false end
	if s1 == 0 then return false end
	local l1 = breadf64(val1, LOG_OFFSET)
	local l2 = breadf64(val2, LOG_OFFSET)
	return if s1 > 0 then l1 > l2 else l1 < l2
end

function module.leeq(val1: buffer, val2: buffer): boolean
	local s1 = breadi8(val1, SIGN_OFFSET)
	local s2 = breadi8(val2, SIGN_OFFSET)
	if s1 ~= s2 then return s1 < s2 end
	if s1 == NAN_SIGN then return false end
	if s1 == 0 then return true end
	local l1 = breadf64(val1, LOG_OFFSET)
	local l2 = breadf64(val2, LOG_OFFSET)
	return if s1 > 0 then l1 <= l2 else l1 >= l2
end

function module.meeq(val1: buffer, val2: buffer): boolean
	local s1 = breadi8(val1, SIGN_OFFSET)
	local s2 = breadi8(val2, SIGN_OFFSET)
	if s1 ~= s2 then return s1 > s2 end
	if s1 == NAN_SIGN then return false end
	if s1 == 0 then return true end
	local l1 = breadf64(val1, LOG_OFFSET)
	local l2 = breadf64(val2, LOG_OFFSET)
	return if s1 > 0 then l1 >= l2 else l1 <= l2
end

module.lt = module.le
module.gt = module.me
module.lte = module.leeq
module.gte = module.meeq
module.compare = module.cmp

function module.min(...: buffer): buffer
	local count = select('#', ...)
	if count == 0 then return cloneRaw(NAN) end
	local best = select(1, ...)
	for i = 2, count do
		local v = select(i, ...)
		if cmpRaw(v, best) < 0 then best = v end
	end
	return best
end

function module.max(...: buffer): buffer
	local count = select('#', ...)
	if count == 0 then return cloneRaw(NAN) end
	local best = select(1, ...)
	for i = 2, count do
		local v = select(i, ...)
		if cmpRaw(v, best) > 0 then best = v end
	end
	return best
end

function module.floor(val: buffer): buffer
	local a = val
	local s = breadi8(a, SIGN_OFFSET)
	if s == NAN_SIGN then return setRaw(a, NAN_SIGN, 0) end
	if s == 0 then return a end
	local l = breadf64(a, LOG_OFFSET)
	if l == huge or l >= 16 then return a end
	if l < 0 then
		if s < 0 then return setRaw(a, -1, 0) end
		return setRaw(a, 0, 0)
	end
	local n = 10 ^ l
	local v = if s < 0 then -ceil(n) else floor(n)
	if v == 0 then return setRaw(a, 0, 0) end
	return setRaw(a, signm(v), log10(abs(v)))
end

function module.ceil(val: buffer): buffer
	local a = val
	local s = breadi8(a, SIGN_OFFSET)
	if s == NAN_SIGN then return setRaw(a, NAN_SIGN, 0) end
	if s == 0 then return a end
	local l = breadf64(a, LOG_OFFSET)
	if l == huge or l >= 16 then return a end
	if l < 0 then
		if s > 0 then return setRaw(a, 1, 0) end
		return setRaw(a, 0, 0)
	end
	local n = 10 ^ l
	local v = if s < 0 then -floor(n) else ceil(n)
	if v == 0 then return setRaw(a, 0, 0) end
	return setRaw(a, signm(v), log10(abs(v)))
end

function module.round(val: buffer): buffer
	local a = val
	local s = breadi8(a, SIGN_OFFSET)
	if s == NAN_SIGN then return setRaw(a, NAN_SIGN, 0) end
	if s == 0 then return a end
	local l = breadf64(a, LOG_OFFSET)
	if l == huge or l >= 16 then return a end
	local n = round(s * 10 ^ l)
	if n == 0 then return setRaw(a, 0, 0) end
	return setRaw(a, signm(n), log10(abs(n)))
end

function module.mod(val1: buffer, val2: buffer): buffer
	local a = val1
	local b = val2
	local s1 = breadi8(a, SIGN_OFFSET)
	local s2 = breadi8(b, SIGN_OFFSET)
	if s1 == NAN_SIGN or s2 == NAN_SIGN or s2 == 0 then
		return setRaw(a, NAN_SIGN, 0)
	end
	if s1 == 0 then return a end
	local l1 = breadf64(a, LOG_OFFSET)
	local l2 = breadf64(b, LOG_OFFSET)
	local d = l1 - l2
	if d < 0 then return a end
	if d > 15 then
		return setRaw(a, NAN_SIGN, 0)
	end
	local q = floor((s1 / s2) * 10 ^ d)
	local factor = 1 - q * (s2 / s1) * 10 ^ (-d)
	if factor == 0 then return setRaw(a, 0, 0) end
	return setRaw(a, signm(s1 * factor), l1 + log10(abs(factor)))
end

function module.lbencode(val: buffer): number
	local a = val
	local s = breadi8(a, SIGN_OFFSET)
	if s == NAN_SIGN or s == 0 then return 0 end
	local l = breadf64(a, LOG_OFFSET)
	if l == huge then
		return s * huge
	end
	local logAbs
	if l > 16 then
		logAbs = l
	else
		logAbs = log10(10 ^ l + 1)
	end
	if logAbs <= 0 then return 0 end
	return (log10(logAbs + 1) + 1) * LB_SCALE * s
end

function module.lbdecode(encoded: number): buffer
	if encoded ~= encoded then return cloneRaw(NAN) end
	if encoded == 0 then return cloneRaw(ZERO) end
	if encoded == huge then return cloneRaw(INF) end
	if encoded == -huge then return cloneRaw(NEG_INF) end
	local s = if encoded > 0 then 1 else -1
	local scaled = abs(encoded) / LB_SCALE
	local logPlus = 10 ^ (scaled - 1) - 1
	if logPlus <= 0 then return cloneRaw(ZERO) end
	local l
	if logPlus > 16 then
		l = logPlus
	else
		local inner = 10 ^ logPlus - 1
		if inner <= 0 then return cloneRaw(ZERO) end
		l = log10(inner)
	end
	return makeRaw(s, l)
end

function module.root(val1: buffer, val2: buffer): buffer
	local a = val1
	local b = val2
	local s1 = breadi8(a, SIGN_OFFSET)
	local s2 = breadi8(b, SIGN_OFFSET)
	if s1 == NAN_SIGN or s2 <= 0 then return setRaw(a, NAN_SIGN, 0) end
	if s1 == 0 then return setRaw(a, 0, 0) end
	local l2 = breadf64(b, LOG_OFFSET)
	if l2 == huge then return setRaw(a, 1, 0) end
	local degree = 10 ^ l2
	local outSign = 1
	if s1 < 0 then
		if degree == huge then return setRaw(a, NAN_SIGN, 0) end
		local nearest = round(degree)
		if abs(degree - nearest) > 1e-10 or nearest % 2 == 0 then
			return setRaw(a, NAN_SIGN, 0)
		end
		outSign = -1
	end
	return setRaw(a, outSign, breadf64(a, LOG_OFFSET) / degree)
end

function module.toSuffix(val: buffer): string
	local s = breadi8(val, SIGN_OFFSET)
	local l = breadf64(val, LOG_OFFSET)

	if s == NAN_SIGN then return "NaN" end
	if s == 0 then return "0" end
	if l == huge then return if s < 0 then "-Inf" else "Inf" end

	if l >= 3 and l < 3000 then
		local whole = floor(l)
		local k = whole // 3
		local body

		if l == whole then
			body = suffixExactMantissa[whole % 3 + 1] .. suffixCache[k]
		else
			local scaled = floor(10 ^ (l - k * 3) * 100 + 0.5) * 0.01
			if scaled >= 1000 then
				k += 1
				if k >= 1000 then
					body = "1e" .. tostring(k * 3)
				else
					body = "1" .. suffixCache[k]
				end
			else
				body = tostring(scaled) .. suffixCache[k]
			end
		end

		return if s < 0 then "-" .. body else body
	end

	if l >= 3000 then
		local exponent = floor(l)
		local mantissa
		if l == exponent then
			mantissa = "1"
		else
			local m = floor(10 ^ (l - exponent) * 100 + 0.5) * 0.01
			if m >= 10 then
				m = 1
				exponent += 1
			end
			mantissa = tostring(m)
		end
		local body = mantissa .. "e" .. tostring(exponent)
		return if s < 0 then "-" .. body else body
	end

	if l >= -3 then
		return tostring(round(s * 10 ^ l * 100) * 0.01)
	end

	if l > -3000 then
		local inv = -l
		local whole = floor(inv)
		local k = whole // 3
		local body

		if inv == whole then
			body = "1/" .. suffixExactMantissa[whole % 3 + 1] .. suffixCache[k]
		else
			local scaled = floor(10 ^ (inv - k * 3) * 100 + 0.5) * 0.01
			if scaled >= 1000 then
				k += 1
				if k >= 1000 then
					body = "1e-" .. tostring(k * 3)
				else
					body = "1/1" .. suffixCache[k]
				end
			else
				body = "1/" .. tostring(scaled) .. suffixCache[k]
			end
		end

		return if s < 0 then "-" .. body else body
	end

	local exponent = floor(l)
	local mantissa = floor(10 ^ (l - exponent) * 100 + 0.5) * 0.01
	if mantissa >= 10 then
		mantissa = 1
		exponent += 1
	end
	local body = tostring(mantissa) .. "e" .. tostring(exponent)
	return if s < 0 then "-" .. body else body
end

function module.format(val: buffer, digits: number?, hyperAt: number?): string
	local s = breadi8(val, SIGN_OFFSET)
	local l = breadf64(val, LOG_OFFSET)

	if s == NAN_SIGN then return "NaN" end
	if s == 0 then return "0" end
	if l == huge then return if s < 0 then "-Inf" else "Inf" end

	local d = digits

	-- Default format is the hot path. Keep it almost as lean as toSuffix().
	if (d == nil or d == 2) and hyperAt == nil then
		if l >= 6 and l < 3000 then
			local whole = floor(l)
			local k = whole // 3
			local body

			if l == whole then
				body = suffixExactMantissa[whole % 3 + 1] .. suffixCache[k]
			else
				local scaled = floor(10 ^ (l - k * 3) * 100 + 0.5) * 0.01
				if scaled >= 1000 then
					k += 1
					if k >= 1000 then
						body = "1e" .. tostring(k * 3)
					else
						body = "1" .. suffixCache[k]
					end
				else
					body = tostring(scaled) .. suffixCache[k]
				end
			end

			return if s < 0 then "-" .. body else body
		end

		if l >= 3 and l < 6 then
			local n = floor(10 ^ l * 100 + 0.5) * 0.01
			if n >= 1000000 then
				return if s < 0 then "-1m" else "1m"
			end
			local str = tostring(n)
			local cut = if n < 10000 then 1 elseif n < 100000 then 2 else 3
			local body = sub(str, 1, cut) .. "," .. sub(str, cut + 1)
			return if s < 0 then "-" .. body else body
		end

		if l >= -3 then
			return tostring(round(s * 10 ^ l * 100) * 0.01)
		end
	end

	local precision
	if d == nil or d == 2 then
		precision = 100
	elseif d == 0 then
		precision = 1
	elseif d == 1 then
		precision = 10
	elseif d == 3 then
		precision = 1000
	elseif d == 4 then
		precision = 10000
	else
		precision = 10 ^ d
	end

	if l >= 6 then
		if hyperAt ~= nil and l >= hyperAt then
			local body = "1e" .. tostring(floor(l))
			return if s < 0 then "-" .. body else body
		end

		if l < 3000 then
			local whole = floor(l)
			local k = whole // 3
			local scaled
			if l == whole and precision == 100 then
				local body = suffixExactMantissa[whole % 3 + 1] .. suffixCache[k]
				return if s < 0 then "-" .. body else body
			else
				scaled = floor(10 ^ (l - k * 3) * precision + 0.5) / precision
			end
			if scaled >= 1000 then
				k += 1
				if k >= 1000 then
					local body = "1e" .. tostring(k * 3)
					return if s < 0 then "-" .. body else body
				end
				local body = "1" .. suffixCache[k]
				return if s < 0 then "-" .. body else body
			end
			local body = tostring(scaled) .. suffixCache[k]
			return if s < 0 then "-" .. body else body
		end

		if hyperAt == nil and l >= 2e20 then
			local body = "1e" .. tostring(floor(l))
			return if s < 0 then "-" .. body else body
		end

		local exponent = floor(l)
		local mantissa = floor(10 ^ (l - exponent) * precision + 0.5) / precision
		if mantissa >= 10 then
			mantissa = 1
			exponent += 1
		end
		local body = tostring(mantissa) .. "e" .. tostring(exponent)
		return if s < 0 then "-" .. body else body
	end

	if l >= 3 then
		local n = floor(10 ^ l * precision + 0.5) / precision
		if n >= 1000000 then
			local body = "1m"
			return if s < 0 then "-" .. body else body
		end
		local str = tostring(n)
		local cut = if n < 10000 then 1 elseif n < 100000 then 2 else 3
		local body = sub(str, 1, cut) .. "," .. sub(str, cut + 1)
		return if s < 0 then "-" .. body else body
	end

	if l >= -3 then
		return tostring(round(s * 10 ^ l * precision) / precision)
	end

	if l > -3000 then
		local inv = -l
		local k = floor(inv / 3)
		local scaled = floor(10 ^ (inv - k * 3) * precision + 0.5) / precision
		if scaled >= 1000 then
			k += 1
			if k >= 1000 then
				local body = "1e-" .. tostring(k * 3)
				return if s < 0 then "-" .. body else body
			end
			local body = "1/1" .. suffixCache[k]
			return if s < 0 then "-" .. body else body
		end
		local body = "1/" .. tostring(scaled) .. suffixCache[k]
		return if s < 0 then "-" .. body else body
	end

	local exponent = floor(l)
	local mantissa = floor(10 ^ (l - exponent) * precision + 0.5) / precision
	if mantissa >= 10 then
		mantissa = 1
		exponent += 1
	end
	local body = tostring(mantissa) .. "e" .. tostring(exponent)
	return if s < 0 then "-" .. body else body
end

function module.toStr(val: buffer): string
	local s = breadi8(val, SIGN_OFFSET)
	local l = breadf64(val, LOG_OFFSET)
	if s == NAN_SIGN then return "NaN" end
	if s == 0 then return "0e0" end
	if l == huge then return if s > 0 then "Inf" else "-Inf" end
	local exponent = floor(l)
	local man = 10 ^ (l - exponent)
	if s < 0 then man = -man end
	return tostring(man) .. "e" .. tostring(exponent)
end

module.toString = module.toStr

function module.maxBuy(val1: buffer, val2: buffer, multi: buffer): (number, buffer)
	local funds = val1
	local cost = val2
	local multiplier = multi
	local sf = breadi8(funds, SIGN_OFFSET)
	local sc = breadi8(cost, SIGN_OFFSET)
	local sm = breadi8(multiplier, SIGN_OFFSET)
	if sf <= 0 or sc <= 0 or sm <= 0 then
		return 0, setRaw(funds, 0, 0)
	end
	local lf = breadf64(funds, LOG_OFFSET)
	local lc = breadf64(cost, LOG_OFFSET)
	local lm = breadf64(multiplier, LOG_OFFSET)
	if cmpRaw(funds, cost) < 0 then
		return 0, setRaw(funds, 0, 0)
	end
	if abs(lm) < 1e-15 then
		local ratioLog = lf - lc
		if ratioLog >= 15 then
			return floor(10 ^ 15), cloneRaw(funds)
		end
		local count = floor(10 ^ ratioLog)
		if count <= 0 then return 0, setRaw(funds, 0, 0) end
		return count, makeRaw(1, lc + log10(count))
	end
	if lm < 0 then
		return 0, setRaw(funds, NAN_SIGN, 0)
	end
	local mMinusOneLog = lm + log10(1 - 10 ^ (-lm))
	local xLog = lf + mMinusOneLog - lc
	local onePlusXLog = if xLog > 16 then xLog else log10(1 + 10 ^ xLog)
	local totalAmount = floor(onePlusXLog / lm)
	if totalAmount <= 0 then return 0, setRaw(funds, 0, 0) end
	local mpLog = totalAmount * lm
	local mpMinusOneLog = if mpLog > 16 then mpLog else log10(10 ^ mpLog - 1)
	return totalAmount, makeRaw(1, lc + mpMinusOneLog - mMinusOneLog)
end

function module.percent(val1: buffer, val2: buffer): string
	local a = val1
	local b = val2
	local s1 = breadi8(a, SIGN_OFFSET)
	local s2 = breadi8(b, SIGN_OFFSET)
	if s1 == NAN_SIGN or s2 == NAN_SIGN or s2 == 0 then return "NaN%" end
	if s1 == 0 then return "0%" end
	local s = s1 * s2
	local l = breadf64(a, LOG_OFFSET) - breadf64(b, LOG_OFFSET) + 2
	local prefix = if s < 0 then "-" else ""
	if l >= 6 then
		return prefix .. module.format(makeRaw(1, l), 2) .. "%"
	end
	if l <= -4 then
		return prefix .. "1/" .. module.format(makeRaw(1, -l), 2) .. "%"
	end
	return tostring(roundedNumber(s * 10 ^ l, 2)) .. "%"
end

type ScaleMode = 'linear' | 'exp' | 'sigmoid'

local function expm1(x: number): number
	if abs(x) < 1e-5 then
		return x + 0.5 * x * x
	end
	return expm(x) - 1
end

function module.scaleCurve(val1: buffer, base: buffer, exponent: buffer, mode: ScaleMode): buffer
	local a = val1
	local b = base
	local e = exponent
	local s1 = breadi8(a, SIGN_OFFSET)
	local s2 = breadi8(b, SIGN_OFFSET)
	if s1 <= 0 or s2 <= 0 then return setRaw(a, 1, 0) end
	local l1 = breadf64(a, LOG_OFFSET)
	local l2 = breadf64(b, LOG_OFFSET)
	if l1 <= l2 then return setRaw(a, 1, 0) end
	local delta = l2 - l1
	local diffLog
	if l1 - l2 > 16 then
		diffLog = l1
	else
		local stable = -expm1(delta * 2.302585092994046)
		diffLog = l1 + log10(stable)
	end
	local tLog = diffLog - l2
	if mode == "linear" then
		if tLog > 16 then return setRaw(a, 1, tLog) end
		return setRaw(a, 1, log10(10 ^ tLog + 1))
	end
	if mode == "sigmoid" then
		if tLog > 2 then return setRaw(a, 1, tLog) end
		local t = 10 ^ tLog
		local sig = 1 / (1 + expm(-t))
		local result = t * sig
		return setRaw(a, 1, log10(result))
	end
	local se = breadi8(e, SIGN_OFFSET)
	local le = breadf64(e, LOG_OFFSET)
	local exVal = if se == 0 then 0 else se * 10 ^ le
	local powLog = tLog * exVal
	if powLog > 16 then return setRaw(a, 1, powLog) end
	return setRaw(a, 1, log10(10 ^ powLog + 1))
end

function module.progress(val1: buffer, goal: buffer, modes: ScaleMode): buffer
	local a = val1
	local g = goal
	local s1 = breadi8(a, SIGN_OFFSET)
	local s2 = breadi8(g, SIGN_OFFSET)
	if s2 <= 0 then return setRaw(a, 0, 0) end
	local ratio = 0
	if s1 > 0 then
		local d = breadf64(a, LOG_OFFSET) - breadf64(g, LOG_OFFSET)
		if d >= 0 then
			ratio = 1
		elseif d > -324 then
			ratio = 10 ^ d
		end
	end
	modes = modes or 'linear'
	local scale
	if modes == 'linear' then
		scale = ratio ^ 1.1
	elseif modes == 'exp' then
		scale = ratio ^ 2
	elseif modes == 'sigmoid' then
		scale = 1 / (1 + expm(-6 * (ratio - 0.5)))
	else
		scale = ratio
	end
	if scale <= 0 then return setRaw(a, 0, 0) end
	return setRaw(a, 1, log10(scale))
end

function module.modf(val: buffer): (buffer, buffer)
	local a = val
	local s = breadi8(a, SIGN_OFFSET)
	local l = breadf64(a, LOG_OFFSET)
	if s == NAN_SIGN then return cloneRaw(NAN), cloneRaw(NAN) end
	if s == 0 then return cloneRaw(ZERO), cloneRaw(ZERO) end
	if l == huge or l >= 15 then return cloneRaw(a), cloneRaw(ZERO) end
	local n = s * 10 ^ l
	local integer = if n >= 0 then floor(n) else ceil(n)
	local fraction = n - integer
	return fromFiniteNumber(integer), fromFiniteNumber(fraction)
end

function module.encodeData(new: buffer, old: number?): number
	local encoded = module.lbencode(new)
	if old ~= nil and old > encoded then
		return old
	end
	return encoded
end

function module.imod(val1: buffer, val2: buffer): buffer
	return module.mod(val1, val2)
end

function module.intdiv(val1: buffer, val2: buffer): buffer
	local a = val1
	local b = val2
	local s1 = breadi8(a, SIGN_OFFSET)
	local s2 = breadi8(b, SIGN_OFFSET)
	if s1 == NAN_SIGN or s2 == NAN_SIGN or s2 == 0 then
		return setRaw(a, NAN_SIGN, 0)
	end
	if s1 == 0 then return setRaw(a, 0, 0) end
	local s = s1 * s2
	local l = breadf64(a, LOG_OFFSET) - breadf64(b, LOG_OFFSET)
	if l >= 16 then return setRaw(a, s, l) end
	local q = s * 10 ^ l
	local n = floor(q)
	if n == 0 then return setRaw(a, 0, 0) end
	return setRaw(a, signm(n), log10(abs(n)))
end

function module.clamp(val1: buffer, minVal: buffer, maxVal: buffer): buffer
	local a = val1
	local mn = minVal
	local mx = maxVal
	if cmpRaw(mn, mx) > 0 then mn, mx = mx, mn end
	if cmpRaw(a, mn) < 0 then return mn end
	if cmpRaw(a, mx) > 0 then return mx end
	return a
end

function module.dynamicCost(cost: buffer, owned: buffer, scale: buffer, method: 'exp' | 'linear' | 'hybrid'): buffer
	local c = cost
	local o = owned
	local s = scale
	local sc = breadi8(c, SIGN_OFFSET)
	local so = breadi8(o, SIGN_OFFSET)
	local ss = breadi8(s, SIGN_OFFSET)
	if sc <= 0 or so < 0 or ss <= 0 then return setRaw(c, NAN_SIGN, 0) end
	local lc = breadf64(c, LOG_OFFSET)
	local lo = breadf64(o, LOG_OFFSET)
	local ls = breadf64(s, LOG_OFFSET)
	local ownedValue = if so == 0 then 0 else 10 ^ lo
	if method == 'exp' then
		return setRaw(c, 1, lc + ownedValue * ls)
	end
	local linearLog
	if so == 0 then
		linearLog = -huge
	else
		linearLog = ls + lo
	end
	if method == 'linear' then
		if linearLog == -huge then return setRaw(c, 1, lc) end
		local d = linearLog - lc
		if d > 16 then return setRaw(c, 1, linearLog) end
		if d < -16 then return setRaw(c, 1, lc) end
		if d >= 0 then return setRaw(c, 1, linearLog + log10(1 + 10 ^ (-d))) end
		return setRaw(c, 1, lc + log10(1 + 10 ^ d))
	end
	local expLog = lc + ownedValue * ls
	if linearLog == -huge then return setRaw(c, 1, expLog) end
	local d = linearLog - expLog
	if d > 16 then return setRaw(c, 1, linearLog) end
	if d < -16 then return setRaw(c, 1, expLog) end
	if d >= 0 then return setRaw(c, 1, linearLog + log10(1 + 10 ^ (-d))) end
	return setRaw(c, 1, expLog + log10(1 + 10 ^ d))
end

function module.abs(val: buffer): buffer
	local a = val
	local s = breadi8(a, SIGN_OFFSET)
	if s == NAN_SIGN then return a end
	if s < 0 then bwritei8(a, SIGN_OFFSET, -s) end
	return a
end

function module.eta(curr: buffer, goal: buffer, rate: buffer): buffer
	local c = curr
	local g = goal
	local r = rate
	if breadi8(r, SIGN_OFFSET) <= 0 then return setRaw(c, 1, huge) end
	if cmpRaw(c, g) >= 0 then return setRaw(c, 0, 0) end
	local sg = breadi8(g, SIGN_OFFSET)
	if sg <= 0 then return setRaw(c, 0, 0) end
	local sc = breadi8(c, SIGN_OFFSET)
	local lg = breadf64(g, LOG_OFFSET)
	local diffLog
	if sc <= 0 then
		if sc == 0 then
			diffLog = lg
		else
			local lc = breadf64(c, LOG_OFFSET)
			local d = lc - lg
			if d > 16 then diffLog = lc else diffLog = lg + log10(1 + 10 ^ d) end
		end
	else
		local lc = breadf64(c, LOG_OFFSET)
		local d = lc - lg
		if d < -16 then
			diffLog = lg
		else
			diffLog = lg + log10(1 - 10 ^ d)
		end
	end
	return setRaw(c, 1, diffLog - breadf64(r, LOG_OFFSET))
end



function module.sign(val: buffer): number
	return breadi8(val, SIGN_OFFSET)
end

function module.exponent(val: buffer): number
	return breadf64(val, LOG_OFFSET)
end

function module.isNaN(val: buffer): boolean
	return breadi8(val, SIGN_OFFSET) == NAN_SIGN
end

function module.isZero(val: buffer): boolean
	return breadi8(val, SIGN_OFFSET) == 0
end

function module.isPositive(val: buffer): boolean
	return breadi8(val, SIGN_OFFSET) == 1
end

function module.isNegative(val: buffer): boolean
	return breadi8(val, SIGN_OFFSET) == -1
end

function module.isBnum(val: any): boolean
	return type(val) == "buffer" and buffer.len(val) >= SIZE
end

-- v1.1 hot-path rule:
-- Core math functions accept Bnum buffers directly and never call ensure().
-- Use module.ensure()/fromNumber()/fromString() at API boundaries only.
module.compat = {}

function module.compat.add(a: any, b: any): buffer
	return module.add(module.ensure(a), module.ensure(b))
end
function module.compat.sub(a: any, b: any): buffer
	return module.sub(module.ensure(a), module.ensure(b))
end
function module.compat.mul(a: any, b: any): buffer
	return module.mul(module.ensure(a), module.ensure(b))
end
function module.compat.div(a: any, b: any): buffer
	return module.div(module.ensure(a), module.ensure(b))
end
function module.compat.pow(a: any, b: any): buffer
	return module.pow(module.ensure(a), module.ensure(b))
end
function module.compat.cmp(a: any, b: any): number
	return module.cmp(module.ensure(a), module.ensure(b))
end
function module.compat.eq(a: any, b: any): boolean
	return module.eq(module.ensure(a), module.ensure(b))
end
function module.compat.format(a: any, digits: number?, hyperAt: number?): string
	return module.format(module.ensure(a), digits, hyperAt)
end

function module.benchmark(iterations: number?): {[string]: number}
	iterations = iterations or 100000
	if iterations < 1 then iterations = 1 end
	local a = module.fromNumber(12345.678)
	local b = module.fromNumber(987.654)
	local out = bcreate(SIZE)
	local clock = os.clock
	local result = {}

	local t = clock()
	for _ = 1, iterations do
		module.fromNumber(12345.678)
	end
	result.fromNumber = (clock() - t) / iterations * 1e9

	t = clock()
	for _ = 1, iterations do
		addRaw(out, a, b)
	end
	result.addReuse = (clock() - t) / iterations * 1e9

	t = clock()
	for _ = 1, iterations do
		mulRaw(out, a, b)
	end
	result.mulReuse = (clock() - t) / iterations * 1e9

	t = clock()
	local sink = 0
	for _ = 1, iterations do
		sink += cmpRaw(a, b)
	end
	result.cmp = (clock() - t) / iterations * 1e9
	if sink == huge then result._sink = sink end
	return result
end

return module
