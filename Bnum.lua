--!optimize 2
--!native

local bcreate = buffer.create
local bcopy = buffer.copy
local breadi8 = buffer.readi8
local breadf64 = buffer.readf64
local bwritei8 = buffer.writei8
local bwritef64 = buffer.writef64
local byte = string.byte

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
local MAX_SAFE_INTEGER = 9007199254740991
local MAX_SAFE_LOG10 = 15.954589770191003
local LOG10_2 = 0.3010299956639812

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
	VERSION = "1.2.1",
	STORAGE_VERSION = 1,
	SIZE = SIZE,
}

local function writeRaw(out: buffer, s: number, l: number): buffer
	bwritei8(out, SIGN_OFFSET, s)
	bwritef64(out, LOG_OFFSET, l)
	return out
end

local function makeFast(s: number, l: number): buffer
	local out = bcreate(SIZE)
	bwritei8(out, SIGN_OFFSET, s)
	bwritef64(out, LOG_OFFSET, l)
	return out
end

local function setRaw(out: buffer, s: number, l: number): buffer
	if s == NAN_SIGN or l ~= l then
		return writeRaw(out, NAN_SIGN, 0)
	end
	if s == 0 or l == -huge then
		return writeRaw(out, 0, 0)
	end
	return writeRaw(out, if s < 0 then -1 else 1, l)
end

local function makeRaw(s: number, l: number): buffer
	local out = bcreate(SIZE)
	return setRaw(out, s, l)
end

local function cloneRaw(src: buffer): buffer
	local out = bcreate(SIZE)
	bcopy(out, 0, src, 0, SIZE)
	return out
end

local function fromFiniteNumber(n: number): buffer
	if n == 0 then
		return makeFast(0, 0)
	end
	return makeFast(if n < 0 then -1 else 1, log10(abs(n)))
end

local function cmpRaw(a: buffer, b: buffer): number
	local sa = breadi8(a, SIGN_OFFSET)
	local sb = breadi8(b, SIGN_OFFSET)
	if sa == NAN_SIGN or sb == NAN_SIGN then
		return 0
	end
	if sa ~= sb then
		return if sa > sb then 1 else -1
	end
	if sa == 0 then
		return 0
	end

	local la = breadf64(a, LOG_OFFSET)
	local lb = breadf64(b, LOG_OFFSET)
	if la > lb then return sa end
	if la < lb then return -sa end
	return 0
end

local function addRaw(out: buffer, a: buffer, b: buffer): buffer
	local s1 = breadi8(a, SIGN_OFFSET)
	local s2 = breadi8(b, SIGN_OFFSET)
	if s1 == NAN_SIGN or s2 == NAN_SIGN then
		return writeRaw(out, NAN_SIGN, 0)
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
			return writeRaw(out, NAN_SIGN, 0)
		end
		if l1 == huge then
			return writeRaw(out, s1, huge)
		end
		return writeRaw(out, s2, huge)
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
		return writeRaw(out, 0, 0)
	end

	if s1 == s2 then
		if d >= 0 then
			return writeRaw(out, s1, l1 + log10(1 + 10 ^ (-d)))
		end
		return writeRaw(out, s1, l2 + log10(1 + 10 ^ d))
	end

	if d > 0 then
		return writeRaw(out, s1, l1 + log10(1 - 10 ^ (-d)))
	end
	if d < 0 then
		return writeRaw(out, s2, l2 + log10(1 - 10 ^ d))
	end
	return writeRaw(out, 0, 0)
end

local function subRaw(out: buffer, a: buffer, b: buffer): buffer
	local s1 = breadi8(a, SIGN_OFFSET)
	local s2 = breadi8(b, SIGN_OFFSET)
	if s1 == NAN_SIGN or s2 == NAN_SIGN then
		return writeRaw(out, NAN_SIGN, 0)
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
			return writeRaw(out, NAN_SIGN, 0)
		end
		if l1 == huge then
			return writeRaw(out, s1, huge)
		end
		return writeRaw(out, -s2, huge)
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
		return writeRaw(out, 0, 0)
	end

	if s1 ~= s2 then
		if d >= 0 then
			return writeRaw(out, s1, l1 + log10(1 + 10 ^ (-d)))
		end
		return writeRaw(out, s1, l2 + log10(1 + 10 ^ d))
	end

	if d > 0 then
		return writeRaw(out, s1, l1 + log10(1 - 10 ^ (-d)))
	end
	if d < 0 then
		return writeRaw(out, -s1, l2 + log10(1 - 10 ^ d))
	end
	return writeRaw(out, 0, 0)
end

local function mulRaw(out: buffer, a: buffer, b: buffer): buffer
	local s1 = breadi8(a, SIGN_OFFSET)
	local s2 = breadi8(b, SIGN_OFFSET)
	if s1 == NAN_SIGN or s2 == NAN_SIGN then
		return writeRaw(out, NAN_SIGN, 0)
	end
	if s1 == 0 or s2 == 0 then
		if breadf64(a, LOG_OFFSET) == huge or breadf64(b, LOG_OFFSET) == huge then
			return writeRaw(out, NAN_SIGN, 0)
		end
		return writeRaw(out, 0, 0)
	end
	return writeRaw(out, s1 * s2, breadf64(a, LOG_OFFSET) + breadf64(b, LOG_OFFSET))
end

local function divRaw(out: buffer, a: buffer, b: buffer): buffer
	local s1 = breadi8(a, SIGN_OFFSET)
	local s2 = breadi8(b, SIGN_OFFSET)
	if s1 == NAN_SIGN or s2 == NAN_SIGN then
		return writeRaw(out, NAN_SIGN, 0)
	end
	if s2 == 0 then
		if s1 == 0 then
			return writeRaw(out, NAN_SIGN, 0)
		end
		return writeRaw(out, s1, huge)
	end
	if s1 == 0 then
		return writeRaw(out, 0, 0)
	end
	local l1 = breadf64(a, LOG_OFFSET)
	local l2 = breadf64(b, LOG_OFFSET)
	if l2 == huge then
		if l1 == huge then return writeRaw(out, NAN_SIGN, 0) end
		return writeRaw(out, 0, 0)
	end
	return writeRaw(out, s1 * s2, l1 - l2)
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

local suffixFractionText = table.create(100)
suffixFractionText[0] = ""
for i = 1, 99 do
	if i % 10 == 0 then
		suffixFractionText[i] = "." .. tostring(i // 10)
	elseif i < 10 then
		suffixFractionText[i] = ".0" .. tostring(i)
	else
		suffixFractionText[i] = "." .. tostring(i)
	end
end

local suffixFastText = table.create(1000)
for i = 100, 999 do
	local whole = i // 100
	local frac = i - whole * 100
	if frac == 0 then
		suffixFastText[i] = tostring(whole)
	else
		suffixFastText[i] = tostring(whole) .. suffixFractionText[frac]
	end
end

local function suffixHundredthsText(value100: number): string
	local whole = value100 // 100
	local frac = value100 - whole * 100
	if frac == 0 then return tostring(whole) end
	return tostring(whole) .. suffixFractionText[frac]
end

local function suffixTruncated100(n: number): number
	return floor(n * 100 + 1e-10)
end

local function compactExponentText(exponent: number): string
	if exponent < 1000 then
		return tostring(floor(exponent))
	end

	local decimalExponent = floor(log10(exponent))
	local group = decimalExponent // 3
	local suffix = suffixCache[group]

	if suffix == nil then
		return tostring(floor(exponent))
	end

	local scaled = exponent / (10 ^ (group * 3))
	local value100 = suffixTruncated100(scaled)
	return suffixHundredthsText(value100) .. suffix
end

local function pow10MinusOne(logValue: number): number
	local x = logValue * 2.302585092994046
	if abs(x) < 1e-5 then
		return x + 0.5 * x * x + x * x * x / 6
	end
	return expm(x) - 1
end

local function log10OnePlusPow10(logValue: number): number
	if logValue > DOMINANCE then
		return logValue
	end

	local x = 10 ^ logValue
	if x == 0 then
		return 0
	end
	if x < 1e-8 then
		return (x - 0.5 * x * x) * LOG10_E
	end
	return log10(1 + x)
end

function module.ensure(val: any): buffer
	local t = type(val)
	if t == "buffer" then
		if buffer.len(val) < SIZE then
			error("Invalid Bnum buffer: expected at least " .. tostring(SIZE) .. " bytes", 2)
		end
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

module.clone = cloneRaw

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
	local out = bcreate(SIZE)
	if type(val) ~= "number" or val ~= val then
		bwritei8(out, SIGN_OFFSET, NAN_SIGN)
		bwritef64(out, LOG_OFFSET, 0)
		return out
	end
	if val == huge then
		bwritei8(out, SIGN_OFFSET, 1)
		bwritef64(out, LOG_OFFSET, huge)
		return out
	end
	if val == -huge then
		bwritei8(out, SIGN_OFFSET, -1)
		bwritef64(out, LOG_OFFSET, huge)
		return out
	end
	if val == 0 then
		bwritei8(out, SIGN_OFFSET, 0)
		bwritef64(out, LOG_OFFSET, 0)
		return out
	end
	bwritei8(out, SIGN_OFFSET, if val < 0 then -1 else 1)
	bwritef64(out, LOG_OFFSET, log10(abs(val)))
	return out
end

function module.fromString(val: string): buffer
	local len = #val
	local c1 = byte(val, 1)
	local sciSign = 1
	local digit = -1
	local expStart = 0

	if c1 ~= nil then
		local c2 = byte(val, 2)

		if c1 >= 48 and c1 <= 57 then
			if c2 == 101 or c2 == 69 then
				digit = c1 - 48
				expStart = 3
			end
		elseif c1 == 45 or c1 == 43 then
			local c3 = byte(val, 3)

			if c2 ~= nil
				and c2 >= 48
				and c2 <= 57
				and (c3 == 101 or c3 == 69)
			then
				digit = c2 - 48
				sciSign = if c1 == 45 then -1 else 1
				expStart = 4
			end
		end
	end

	if expStart ~= 0 then
		local i = expStart
		local exponentSign = 1
		local c = byte(val, i)

		if c == 43 then
			i += 1
		elseif c == 45 then
			exponentSign = -1
			i += 1
		end

		local valid = i <= len
		local exponent = 0

		while valid and i <= len do
			c = byte(val, i)

			if c == nil or c < 48 or c > 57 then
				valid = false
				break
			end

			exponent = exponent * 10 + c - 48
			i += 1
		end

		if valid then
			exponent *= exponentSign

			local out = bcreate(SIZE)

			if digit == 0 then
				bwritei8(out, SIGN_OFFSET, 0)
				bwritef64(out, LOG_OFFSET, 0)
				return out
			end

			bwritei8(out, SIGN_OFFSET, sciSign)

			if digit == 1 then
				bwritef64(out, LOG_OFFSET, exponent)
			else
				bwritef64(
					out,
					LOG_OFFSET,
					log10(digit) + exponent
				)
			end

			return out
		end
	end

	local e = find(val, "e", 1, true)
	if e == nil then
		e = find(val, "E", 1, true)
	end
	if e ~= nil then
		local man = tonumber(sub(val, 1, e - 1))
		local exponent = tonumber(sub(val, e + 1))

		local out = bcreate(SIZE)

		if man == nil
			or exponent == nil
			or man ~= man
			or exponent ~= exponent
		then
			bwritei8(out, SIGN_OFFSET, NAN_SIGN)
			bwritef64(out, LOG_OFFSET, 0)
			return out
		end

		if man == 0 then
			bwritei8(out, SIGN_OFFSET, 0)
			bwritef64(out, LOG_OFFSET, 0)
			return out
		end

		local magnitude = abs(man)
		local resultLog = exponent

		if magnitude ~= 1 then
			resultLog += log10(magnitude)
		end

		bwritei8(
			out,
			SIGN_OFFSET,
			if man < 0 then -1 else 1
		)

		bwritef64(
			out,
			LOG_OFFSET,
			resultLog
		)

		return out
	end
	local n = tonumber(val)

	if n ~= nil then
		local out = bcreate(SIZE)

		if n ~= n then
			bwritei8(out, SIGN_OFFSET, NAN_SIGN)
			bwritef64(out, LOG_OFFSET, 0)
			return out
		end

		if n == huge then
			bwritei8(out, SIGN_OFFSET, 1)
			bwritef64(out, LOG_OFFSET, huge)
			return out
		end

		if n == -huge then
			bwritei8(out, SIGN_OFFSET, -1)
			bwritef64(out, LOG_OFFSET, huge)
			return out
		end

		if n == 0 then
			bwritei8(out, SIGN_OFFSET, 0)
			bwritef64(out, LOG_OFFSET, 0)
			return out
		end

		bwritei8(
			out,
			SIGN_OFFSET,
			if n < 0 then -1 else 1
		)

		bwritef64(
			out,
			LOG_OFFSET,
			log10(abs(n))
		)

		return out
	end
	
	local out = bcreate(SIZE)

	if val == "NaN" or val == "nan" then
		bwritei8(out, SIGN_OFFSET, NAN_SIGN)
		bwritef64(out, LOG_OFFSET, 0)
		return out
	end

	if val == "Inf"
		or val == "inf"
		or val == "+Inf"
		or val == "+inf"
	then
		bwritei8(out, SIGN_OFFSET, 1)
		bwritef64(out, LOG_OFFSET, huge)
		return out
	end

	if val == "-Inf" or val == "-inf" then
		bwritei8(out, SIGN_OFFSET, -1)
		bwritef64(out, LOG_OFFSET, huge)
		return out
	end

	bwritei8(out, SIGN_OFFSET, NAN_SIGN)
	bwritef64(out, LOG_OFFSET, 0)
	return out
end

function module.addBuffer(a: buffer, b: buffer, out: buffer?): buffer
	local o = out or bcreate(SIZE)
	local s1 = breadi8(a, SIGN_OFFSET)
	local s2 = breadi8(b, SIGN_OFFSET)
	if s1 == NAN_SIGN or s2 == NAN_SIGN then
		bwritei8(o, SIGN_OFFSET, NAN_SIGN); bwritef64(o, LOG_OFFSET, 0); return o
	end
	if s1 == 0 then bcopy(o, 0, b, 0, SIZE); return o end
	if s2 == 0 then bcopy(o, 0, a, 0, SIZE); return o end

	local l1 = breadf64(a, LOG_OFFSET)
	local l2 = breadf64(b, LOG_OFFSET)
	if l1 == huge or l2 == huge then
		if l1 == huge and l2 == huge and s1 ~= s2 then
			bwritei8(o, SIGN_OFFSET, NAN_SIGN); bwritef64(o, LOG_OFFSET, 0); return o
		end
		if l1 == huge then bwritei8(o, SIGN_OFFSET, s1); bwritef64(o, LOG_OFFSET, huge); return o end
		bwritei8(o, SIGN_OFFSET, s2); bwritef64(o, LOG_OFFSET, huge); return o
	end

	local d = l1 - l2
	if d > DOMINANCE then bcopy(o, 0, a, 0, SIZE); return o end
	if d < -DOMINANCE then bcopy(o, 0, b, 0, SIZE); return o end
	if d == 0 and s1 ~= s2 then
		bwritei8(o, SIGN_OFFSET, 0); bwritef64(o, LOG_OFFSET, 0); return o
	end

	local signOut: number
	local logOut: number
	if s1 == s2 then
		signOut = s1
		if d >= 0 then logOut = l1 + log10(1 + 10 ^ (-d))
		else logOut = l2 + log10(1 + 10 ^ d) end
	elseif d > 0 then
		signOut = s1
		logOut = l1 + log10(1 - 10 ^ (-d))
	elseif d < 0 then
		signOut = s2
		logOut = l2 + log10(1 - 10 ^ d)
	else
		signOut = 0
		logOut = 0
	end
	bwritei8(o, SIGN_OFFSET, signOut)
	bwritef64(o, LOG_OFFSET, logOut)
	return o
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
	local out = bcreate(SIZE)
	local s1 = breadi8(val1, SIGN_OFFSET)
	local s2 = breadi8(val2, SIGN_OFFSET)

	if s1 == NAN_SIGN or s2 == NAN_SIGN then
		bwritei8(out, SIGN_OFFSET, NAN_SIGN); bwritef64(out, LOG_OFFSET, 0); return out
	end
	if s1 == 0 then bcopy(out, 0, val2, 0, SIZE); return out end
	if s2 == 0 then bcopy(out, 0, val1, 0, SIZE); return out end

	local l1 = breadf64(val1, LOG_OFFSET)
	local l2 = breadf64(val2, LOG_OFFSET)
	if l1 == huge or l2 == huge then
		if l1 == huge and l2 == huge and s1 ~= s2 then
			bwritei8(out, SIGN_OFFSET, NAN_SIGN); bwritef64(out, LOG_OFFSET, 0); return out
		end
		if l1 == huge then bwritei8(out, SIGN_OFFSET, s1); bwritef64(out, LOG_OFFSET, huge); return out end
		bwritei8(out, SIGN_OFFSET, s2); bwritef64(out, LOG_OFFSET, huge); return out
	end

	local d = l1 - l2
	if d > DOMINANCE then bcopy(out, 0, val1, 0, SIZE); return out end
	if d < -DOMINANCE then bcopy(out, 0, val2, 0, SIZE); return out end
	if d == 0 and s1 ~= s2 then
		bwritei8(out, SIGN_OFFSET, 0); bwritef64(out, LOG_OFFSET, 0); return out
	end

	local signOut: number
	local logOut: number
	if s1 == s2 then
		signOut = s1
		if d >= 0 then logOut = l1 + log10(1 + 10 ^ (-d))
		else logOut = l2 + log10(1 + 10 ^ d) end
	elseif d > 0 then
		signOut = s1
		logOut = l1 + log10(1 - 10 ^ (-d))
	elseif d < 0 then
		signOut = s2
		logOut = l2 + log10(1 - 10 ^ d)
	else
		signOut = 0
		logOut = 0
	end
	bwritei8(out, SIGN_OFFSET, signOut)
	bwritef64(out, LOG_OFFSET, logOut)
	return out
end

function module.sub(val1: buffer, val2: buffer): buffer
	local out = bcreate(SIZE)
	local s1 = breadi8(val1, SIGN_OFFSET)
	local s2 = breadi8(val2, SIGN_OFFSET)

	if s1 == NAN_SIGN or s2 == NAN_SIGN then
		bwritei8(out, SIGN_OFFSET, NAN_SIGN); bwritef64(out, LOG_OFFSET, 0); return out
	end
	if s2 == 0 then bcopy(out, 0, val1, 0, SIZE); return out end
	if s1 == 0 then
		bcopy(out, 0, val2, 0, SIZE)
		bwritei8(out, SIGN_OFFSET, -s2)
		return out
	end

	local l1 = breadf64(val1, LOG_OFFSET)
	local l2 = breadf64(val2, LOG_OFFSET)
	if l1 == huge or l2 == huge then
		if l1 == huge and l2 == huge and s1 == s2 then
			bwritei8(out, SIGN_OFFSET, NAN_SIGN); bwritef64(out, LOG_OFFSET, 0); return out
		end
		if l1 == huge then bwritei8(out, SIGN_OFFSET, s1); bwritef64(out, LOG_OFFSET, huge); return out end
		bwritei8(out, SIGN_OFFSET, -s2); bwritef64(out, LOG_OFFSET, huge); return out
	end

	local d = l1 - l2
	if d > DOMINANCE then bcopy(out, 0, val1, 0, SIZE); return out end
	if d < -DOMINANCE then
		bcopy(out, 0, val2, 0, SIZE)
		bwritei8(out, SIGN_OFFSET, -s2)
		return out
	end
	if d == 0 and s1 == s2 then
		bwritei8(out, SIGN_OFFSET, 0); bwritef64(out, LOG_OFFSET, 0); return out
	end

	local signOut: number
	local logOut: number
	if s1 ~= s2 then
		signOut = s1
		if d >= 0 then logOut = l1 + log10(1 + 10 ^ (-d))
		else logOut = l2 + log10(1 + 10 ^ d) end
	elseif d > 0 then
		signOut = s1
		logOut = l1 + log10(1 - 10 ^ (-d))
	elseif d < 0 then
		signOut = -s1
		logOut = l2 + log10(1 - 10 ^ d)
	else
		signOut = 0
		logOut = 0
	end
	bwritei8(out, SIGN_OFFSET, signOut)
	bwritef64(out, LOG_OFFSET, logOut)
	return out
end

function module.subz(val1: buffer, val2: buffer): buffer
	local a = module.sub(val1, val2)
	if breadi8(a, SIGN_OFFSET) < 0 then
		return setRaw(a, 0, 0)
	end
	return a
end

function module.mul(val1: buffer, val2: buffer): buffer
	local out = bcreate(SIZE)
	local s1 = breadi8(val1, SIGN_OFFSET)
	local s2 = breadi8(val2, SIGN_OFFSET)
	if s1 == NAN_SIGN or s2 == NAN_SIGN then
		bwritei8(out, SIGN_OFFSET, NAN_SIGN); bwritef64(out, LOG_OFFSET, 0); return out
	end
	if s1 == 0 or s2 == 0 then
		if breadf64(val1, LOG_OFFSET) == huge or breadf64(val2, LOG_OFFSET) == huge then
			bwritei8(out, SIGN_OFFSET, NAN_SIGN); bwritef64(out, LOG_OFFSET, 0); return out
		end
		bwritei8(out, SIGN_OFFSET, 0); bwritef64(out, LOG_OFFSET, 0); return out
	end
	bwritei8(out, SIGN_OFFSET, s1 * s2)
	bwritef64(out, LOG_OFFSET, breadf64(val1, LOG_OFFSET) + breadf64(val2, LOG_OFFSET))
	return out
end

function module.div(val1: buffer, val2: buffer): buffer
	local out = bcreate(SIZE)
	local s1 = breadi8(val1, SIGN_OFFSET)
	local s2 = breadi8(val2, SIGN_OFFSET)
	if s1 == NAN_SIGN or s2 == NAN_SIGN then
		bwritei8(out, SIGN_OFFSET, NAN_SIGN); bwritef64(out, LOG_OFFSET, 0); return out
	end
	if s2 == 0 then
		if s1 == 0 then
			bwritei8(out, SIGN_OFFSET, NAN_SIGN); bwritef64(out, LOG_OFFSET, 0); return out
		end
		bwritei8(out, SIGN_OFFSET, s1); bwritef64(out, LOG_OFFSET, huge); return out
	end
	if s1 == 0 then
		bwritei8(out, SIGN_OFFSET, 0); bwritef64(out, LOG_OFFSET, 0); return out
	end
	local l1 = breadf64(val1, LOG_OFFSET)
	local l2 = breadf64(val2, LOG_OFFSET)
	if l2 == huge then
		if l1 == huge then
			bwritei8(out, SIGN_OFFSET, NAN_SIGN); bwritef64(out, LOG_OFFSET, 0); return out
		end
		bwritei8(out, SIGN_OFFSET, 0); bwritef64(out, LOG_OFFSET, 0); return out
	end
	bwritei8(out, SIGN_OFFSET, s1 * s2)
	bwritef64(out, LOG_OFFSET, l1 - l2)
	return out
end

local function powRaw(out: buffer, a: buffer, b: buffer): buffer
	local s1 = breadi8(a, SIGN_OFFSET)
	local s2 = breadi8(b, SIGN_OFFSET)

	if s1 == NAN_SIGN or s2 == NAN_SIGN then
		return writeRaw(out, NAN_SIGN, 0)
	end
	if s2 == 0 then
		return writeRaw(out, 1, 0)
	end
	if s1 == 0 then
		if s2 < 0 then
			return writeRaw(out, 1, huge)
		end
		return writeRaw(out, 0, 0)
	end

	local l1 = breadf64(a, LOG_OFFSET)
	local l2 = breadf64(b, LOG_OFFSET)
	local power = s2 * 10 ^ l2

	if power ~= power then
		return writeRaw(out, NAN_SIGN, 0)
	end

	local outSign = 1
	if s1 < 0 then
		if power == huge or power == -huge then
			return writeRaw(out, NAN_SIGN, 0)
		end

		local nearest = round(power)
		if abs(power - nearest) > 1e-10 then
			return writeRaw(out, NAN_SIGN, 0)
		end

		if nearest % 2 ~= 0 then
			outSign = -1
		end
	end

	if l1 == 0 then
		return writeRaw(out, outSign, 0)
	end

	local resultLog = l1 * power
	if resultLog ~= resultLog then return writeRaw(out, NAN_SIGN, 0) end
	if resultLog == -huge then return writeRaw(out, 0, 0) end
	return writeRaw(out, outSign, resultLog)
end

function module.pow(val1: buffer, val2: buffer): buffer
	local out = bcreate(SIZE)
	local s1 = breadi8(val1, SIGN_OFFSET)
	local s2 = breadi8(val2, SIGN_OFFSET)
	if s1 == NAN_SIGN or s2 == NAN_SIGN then
		bwritei8(out, SIGN_OFFSET, NAN_SIGN); bwritef64(out, LOG_OFFSET, 0); return out
	end
	if s2 == 0 then
		bwritei8(out, SIGN_OFFSET, 1); bwritef64(out, LOG_OFFSET, 0); return out
	end
	if s1 == 0 then
		bwritei8(out, SIGN_OFFSET, if s2 < 0 then 1 else 0)
		bwritef64(out, LOG_OFFSET, if s2 < 0 then huge else 0)
		return out
	end

	local l1 = breadf64(val1, LOG_OFFSET)
	local power = s2 * 10 ^ breadf64(val2, LOG_OFFSET)
	if power ~= power then
		bwritei8(out, SIGN_OFFSET, NAN_SIGN); bwritef64(out, LOG_OFFSET, 0); return out
	end

	local outSign = 1
	if s1 < 0 then
		if power == huge or power == -huge then
			bwritei8(out, SIGN_OFFSET, NAN_SIGN); bwritef64(out, LOG_OFFSET, 0); return out
		end
		local nearest = round(power)
		if abs(power - nearest) > 1e-10 then
			bwritei8(out, SIGN_OFFSET, NAN_SIGN); bwritef64(out, LOG_OFFSET, 0); return out
		end
		if nearest % 2 ~= 0 then outSign = -1 end
	end

	if l1 == 0 then
		bwritei8(out, SIGN_OFFSET, outSign)
		bwritef64(out, LOG_OFFSET, 0)
		return out
	end

	local resultLog = l1 * power
	if resultLog ~= resultLog then
		bwritei8(out, SIGN_OFFSET, NAN_SIGN); bwritef64(out, LOG_OFFSET, 0); return out
	end
	if resultLog == -huge then
		bwritei8(out, SIGN_OFFSET, 0); bwritef64(out, LOG_OFFSET, 0); return out
	end
	bwritei8(out, SIGN_OFFSET, outSign)
	bwritef64(out, LOG_OFFSET, resultLog)
	return out
end

function module.poweq(val1: buffer, val2: buffer): buffer
	return powRaw(val1, val1, val2)
end

function module.pow10(val: buffer): buffer
	local s = breadi8(val, SIGN_OFFSET)
	if s == NAN_SIGN then return makeFast(NAN_SIGN, 0) end
	if s == 0 then return makeFast(1, 0) end
	local l = breadf64(val, LOG_OFFSET)
	if l == huge then
		if s > 0 then return makeFast(1, huge) end
		return makeFast(0, 0)
	end
	local resultLog = s * 10 ^ l
	if resultLog == -huge then return makeFast(0, 0) end
	return makeFast(1, resultLog)
end

function module.sqrt(val: buffer): buffer
	local out = bcreate(SIZE)
	local s = breadi8(val, SIGN_OFFSET)
	if s == NAN_SIGN or s < 0 then
		bwritei8(out, SIGN_OFFSET, NAN_SIGN); bwritef64(out, LOG_OFFSET, 0); return out
	end
	if s == 0 then
		bwritei8(out, SIGN_OFFSET, 0); bwritef64(out, LOG_OFFSET, 0); return out
	end
	bwritei8(out, SIGN_OFFSET, 1)
	bwritef64(out, LOG_OFFSET, breadf64(val, LOG_OFFSET) * 0.5)
	return out
end

function module.log10(val: buffer): buffer
	local out = bcreate(SIZE)
	local s = breadi8(val, SIGN_OFFSET)
	if s <= 0 then
		bwritei8(out, SIGN_OFFSET, NAN_SIGN); bwritef64(out, LOG_OFFSET, 0); return out
	end
	local l = breadf64(val, LOG_OFFSET)
	if l == 0 then
		bwritei8(out, SIGN_OFFSET, 0); bwritef64(out, LOG_OFFSET, 0); return out
	end
	if l == huge then
		bwritei8(out, SIGN_OFFSET, 1); bwritef64(out, LOG_OFFSET, huge); return out
	end
	bwritei8(out, SIGN_OFFSET, if l < 0 then -1 else 1)
	bwritef64(out, LOG_OFFSET, log10(abs(l)))
	return out
end

function module.log(val1: buffer, val2: buffer?): buffer
	local s1 = breadi8(val1, SIGN_OFFSET)
	if s1 <= 0 then return makeFast(NAN_SIGN, 0) end
	local l1 = breadf64(val1, LOG_OFFSET)
	if val2 == nil then
		local result = l1 * 2.302585092994046
		if result == 0 then return makeFast(0, 0) end
		if result ~= result then return makeFast(NAN_SIGN, 0) end
		return makeFast(if result < 0 then -1 else 1, log10(abs(result)))
	end
	local s2 = breadi8(val2, SIGN_OFFSET)
	if s2 <= 0 then return makeFast(NAN_SIGN, 0) end
	local l2 = breadf64(val2, LOG_OFFSET)
	if l2 == 0 then return makeFast(NAN_SIGN, 0) end
	local result = l1 / l2
	if result ~= result then return makeFast(NAN_SIGN, 0) end
	if result == 0 then return makeFast(0, 0) end
	return makeFast(if result < 0 then -1 else 1, log10(abs(result)))
end

module.ln = module.log

function module.exp(val: buffer): buffer
	local s = breadi8(val, SIGN_OFFSET)
	if s == NAN_SIGN then return makeFast(NAN_SIGN, 0) end
	if s == 0 then return makeFast(1, 0) end
	local l = breadf64(val, LOG_OFFSET)
	if l == huge then
		if s > 0 then return makeFast(1, huge) end
		return makeFast(0, 0)
	end
	local resultLog = LOG10_E * s * 10 ^ l
	if resultLog == -huge then return makeFast(0, 0) end
	return makeFast(1, resultLog)
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
	local s1 = breadi8(a, SIGN_OFFSET)
	local s2 = breadi8(b, SIGN_OFFSET)
	if s1 == NAN_SIGN or s2 == NAN_SIGN then
		return cloneRaw(NAN)
	end
	if cmpRaw(a, b) > 0 then
		a, b = b, a
		s1, s2 = s2, s1
	end
	if s1 == s2 and s1 ~= 0 then
		local l1 = breadf64(a, LOG_OFFSET)
		local l2 = breadf64(b, LOG_OFFSET)
		if l1 > 308.25471555991675 or l2 > 308.25471555991675 then
			local l = l1 + random() * (l2 - l1)
			return makeRaw(s1, l)
		end
	end
	local n1 = module.toNumber(a)
	local n2 = module.toNumber(b)
	if n1 == -huge or n2 == huge or n1 ~= n1 or n2 ~= n2 then
		return cloneRaw(NAN)
	end
	local r = random()
	return fromFiniteNumber(n1 * (1 - r) + n2 * r)
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
	if s1 == NAN_SIGN or s2 == NAN_SIGN then return false end
	if s1 ~= s2 then return s1 < s2 end
	if s1 == 0 then return false end
	local l1 = breadf64(val1, LOG_OFFSET)
	local l2 = breadf64(val2, LOG_OFFSET)
	return if s1 > 0 then l1 < l2 else l1 > l2
end

function module.me(val1: buffer, val2: buffer): boolean
	local s1 = breadi8(val1, SIGN_OFFSET)
	local s2 = breadi8(val2, SIGN_OFFSET)
	if s1 == NAN_SIGN or s2 == NAN_SIGN then return false end
	if s1 ~= s2 then return s1 > s2 end
	if s1 == 0 then return false end
	local l1 = breadf64(val1, LOG_OFFSET)
	local l2 = breadf64(val2, LOG_OFFSET)
	return if s1 > 0 then l1 > l2 else l1 < l2
end

function module.leeq(val1: buffer, val2: buffer): boolean
	local s1 = breadi8(val1, SIGN_OFFSET)
	local s2 = breadi8(val2, SIGN_OFFSET)
	if s1 == NAN_SIGN or s2 == NAN_SIGN then return false end
	if s1 ~= s2 then return s1 < s2 end
	if s1 == 0 then return true end
	local l1 = breadf64(val1, LOG_OFFSET)
	local l2 = breadf64(val2, LOG_OFFSET)
	return if s1 > 0 then l1 <= l2 else l1 >= l2
end

function module.meeq(val1: buffer, val2: buffer): boolean
	local s1 = breadi8(val1, SIGN_OFFSET)
	local s2 = breadi8(val2, SIGN_OFFSET)
	if s1 == NAN_SIGN or s2 == NAN_SIGN then return false end
	if s1 ~= s2 then return s1 > s2 end
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
	if breadi8(best, SIGN_OFFSET) == NAN_SIGN then return cloneRaw(NAN) end
	for i = 2, count do
		local v = select(i, ...)
		if breadi8(v, SIGN_OFFSET) == NAN_SIGN then return cloneRaw(NAN) end
		if cmpRaw(v, best) < 0 then best = v end
	end
	return cloneRaw(best)
end

function module.max(...: buffer): buffer
	local count = select('#', ...)
	if count == 0 then return cloneRaw(NAN) end
	local best = select(1, ...)
	if breadi8(best, SIGN_OFFSET) == NAN_SIGN then return cloneRaw(NAN) end
	for i = 2, count do
		local v = select(i, ...)
		if breadi8(v, SIGN_OFFSET) == NAN_SIGN then return cloneRaw(NAN) end
		if cmpRaw(v, best) > 0 then best = v end
	end
	return cloneRaw(best)
end

function module.floor(val: buffer): buffer
	local s = breadi8(val, SIGN_OFFSET)
	if s == NAN_SIGN then return makeFast(NAN_SIGN, 0) end
	if s == 0 then return makeFast(0, 0) end
	local l = breadf64(val, LOG_OFFSET)
	if l == huge or l >= 16 then return makeFast(s, l) end
	if l < 0 then
		if s < 0 then return makeFast(-1, 0) end
		return makeFast(0, 0)
	end
	local n = 10 ^ l
	local v = if s < 0 then -ceil(n) else floor(n)
	if v == 0 then return makeFast(0, 0) end
	return makeFast(if v < 0 then -1 else 1, log10(abs(v)))
end

function module.ceil(val: buffer): buffer
	local s = breadi8(val, SIGN_OFFSET)
	if s == NAN_SIGN then return makeFast(NAN_SIGN, 0) end
	if s == 0 then return makeFast(0, 0) end
	local l = breadf64(val, LOG_OFFSET)
	if l == huge or l >= 16 then return makeFast(s, l) end
	if l < 0 then
		if s > 0 then return makeFast(1, 0) end
		return makeFast(0, 0)
	end
	local n = 10 ^ l
	local v = if s < 0 then -floor(n) else ceil(n)
	if v == 0 then return makeFast(0, 0) end
	return makeFast(if v < 0 then -1 else 1, log10(abs(v)))
end

function module.round(val: buffer): buffer
	local s = breadi8(val, SIGN_OFFSET)
	if s == NAN_SIGN then return makeFast(NAN_SIGN, 0) end
	if s == 0 then return makeFast(0, 0) end
	local l = breadf64(val, LOG_OFFSET)
	if l == huge or l >= 16 then return makeFast(s, l) end
	local n = round(s * 10 ^ l)
	if n == 0 then return makeFast(0, 0) end
	return makeFast(if n < 0 then -1 else 1, log10(abs(n)))
end

function module.mod(val1: buffer, val2: buffer): buffer
	local s1 = breadi8(val1, SIGN_OFFSET)
	local s2 = breadi8(val2, SIGN_OFFSET)
	if s1 == NAN_SIGN or s2 == NAN_SIGN or s2 == 0 then return makeFast(NAN_SIGN, 0) end
	if s1 == 0 then return makeFast(0, 0) end
	local l1 = breadf64(val1, LOG_OFFSET)
	local l2 = breadf64(val2, LOG_OFFSET)
	local d = l1 - l2
	if d < 0 then return makeFast(s1, l1) end
	if d > 15 then return makeFast(NAN_SIGN, 0) end
	local q = floor((s1 / s2) * 10 ^ d)
	local factor = 1 - q * (s2 / s1) * 10 ^ (-d)
	if factor == 0 then return makeFast(0, 0) end
	return makeFast(if s1 * factor < 0 then -1 else 1, l1 + log10(abs(factor)))
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
	local s1 = breadi8(val1, SIGN_OFFSET)
	local s2 = breadi8(val2, SIGN_OFFSET)
	if s1 == NAN_SIGN or s2 <= 0 then return makeFast(NAN_SIGN, 0) end
	if s1 == 0 then return makeFast(0, 0) end
	local l2 = breadf64(val2, LOG_OFFSET)
	if l2 == huge then return makeFast(1, 0) end
	local degree = 10 ^ l2
	local outSign = 1
	if s1 < 0 then
		if degree == huge then return makeFast(NAN_SIGN, 0) end
		local nearest = round(degree)
		if abs(degree - nearest) > 1e-10 or nearest % 2 == 0 then return makeFast(NAN_SIGN, 0) end
		outSign = -1
	end
	return makeFast(outSign, breadf64(val1, LOG_OFFSET) / degree)
end

function module.toNumber(val: buffer): number
	local s = breadi8(val, SIGN_OFFSET)
	if s == NAN_SIGN then return 0 / 0 end
	if s == 0 then return 0 end

	local l = breadf64(val, LOG_OFFSET)
	if l == huge or l > 308.25471555991675 then
		return if s < 0 then -huge else huge
	end
	if l < -324 then
		return 0
	end
	return s * 10 ^ l
end

function module.isFloat(val: buffer): boolean
	local s = breadi8(val, SIGN_OFFSET)
	if s == NAN_SIGN then return false end
	if s == 0 then return true end
	local l = breadf64(val, LOG_OFFSET)
	return l ~= huge and l <= 308.25471555991675
end

function module.isFinite(val: buffer): boolean
	local s = breadi8(val, SIGN_OFFSET)
	return s ~= NAN_SIGN and breadf64(val, LOG_OFFSET) ~= huge
end

function module.neg(val: buffer): buffer
	local s = breadi8(val, SIGN_OFFSET)
	if s == NAN_SIGN then return makeFast(NAN_SIGN, 0) end
	if s == 0 then return makeFast(0, 0) end
	return makeFast(-s, breadf64(val, LOG_OFFSET))
end

function module.recip(val: buffer): buffer
	local s = breadi8(val, SIGN_OFFSET)
	if s == NAN_SIGN then return makeFast(NAN_SIGN, 0) end
	if s == 0 then return makeFast(1, huge) end
	local l = breadf64(val, LOG_OFFSET)
	if l == huge then return makeFast(0, 0) end
	return makeFast(s, -l)
end

function module.cbrt(val: buffer): buffer
	local s = breadi8(val, SIGN_OFFSET)
	if s == NAN_SIGN then return makeFast(NAN_SIGN, 0) end
	if s == 0 then return makeFast(0, 0) end
	return makeFast(s, breadf64(val, LOG_OFFSET) / 3)
end

function module.powf(val: buffer, power: number): buffer
	local out = bcreate(SIZE)
	local s = breadi8(val, SIGN_OFFSET)
	if s == NAN_SIGN or power ~= power then
		bwritei8(out, SIGN_OFFSET, NAN_SIGN); bwritef64(out, LOG_OFFSET, 0); return out
	end
	if power == 0 then
		bwritei8(out, SIGN_OFFSET, 1); bwritef64(out, LOG_OFFSET, 0); return out
	end
	if s == 0 then
		if power < 0 then
			bwritei8(out, SIGN_OFFSET, 1); bwritef64(out, LOG_OFFSET, huge)
		else
			bwritei8(out, SIGN_OFFSET, 0); bwritef64(out, LOG_OFFSET, 0)
		end
		return out
	end

	local outSign = 1
	if s < 0 then
		if power == huge or power == -huge then
			bwritei8(out, SIGN_OFFSET, NAN_SIGN); bwritef64(out, LOG_OFFSET, 0); return out
		end
		local nearest = round(power)
		if abs(power - nearest) > 1e-10 then
			bwritei8(out, SIGN_OFFSET, NAN_SIGN); bwritef64(out, LOG_OFFSET, 0); return out
		end
		if nearest % 2 ~= 0 then outSign = -1 end
	end

	local resultLog = breadf64(val, LOG_OFFSET) * power
	if resultLog ~= resultLog then
		bwritei8(out, SIGN_OFFSET, NAN_SIGN); bwritef64(out, LOG_OFFSET, 0); return out
	end
	if resultLog == -huge then
		bwritei8(out, SIGN_OFFSET, 0); bwritef64(out, LOG_OFFSET, 0); return out
	end
	bwritei8(out, SIGN_OFFSET, outSign)
	bwritef64(out, LOG_OFFSET, resultLog)
	return out
end

function module.log2(val: buffer): buffer
	local s = breadi8(val, SIGN_OFFSET)
	if s <= 0 then return makeFast(NAN_SIGN, 0) end
	local l = breadf64(val, LOG_OFFSET)
	if l == 0 then return makeFast(0, 0) end
	if l == huge then return makeFast(1, huge) end
	local result = l / LOG10_2
	return makeFast(if result < 0 then -1 else 1, log10(abs(result)))
end

function module.toSuffix(val: buffer): string
	local s = breadi8(val, SIGN_OFFSET)
	if s == NAN_SIGN then return "NaN" end
	if s == 0 then return "0" end

	local l = breadf64(val, LOG_OFFSET)
	if l == huge then return if s < 0 then "-Inf" else "Inf" end

	if l >= 3 then
		if l < 3000 then
			local whole = floor(l)
			local k = whole // 3
			local suffix = suffixCache[k]
			if l == whole then
				local body = suffixExactMantissa[whole % 3 + 1] .. suffix
				return if s < 0 then "-" .. body else body
			end

			local value100 = floor(10 ^ (l - k * 3) * 100 + 1e-10)
			local text = suffixFastText[value100]
			if text == nil then
				local w = value100 // 100
				local frac = value100 - w * 100
				if frac == 0 then text = tostring(w)
				else text = tostring(w) .. suffixFractionText[frac] end
			end
			local body = text .. suffix
			return if s < 0 then "-" .. body else body
		end

		local exponent = floor(l)
		if l == exponent then
			local body = "1e" .. tostring(exponent)
			return if s < 0 then "-" .. body else body
		end
		local value100 = floor(10 ^ (l - exponent) * 100 + 1e-10)
		local text = suffixFastText[value100]
		if text == nil then
			local w = value100 // 100
			local frac = value100 - w * 100
			if frac == 0 then text = tostring(w)
			else text = tostring(w) .. suffixFractionText[frac] end
		end
		local body = text .. "e" .. tostring(exponent)
		return if s < 0 then "-" .. body else body
	end

	if l >= -2 then
		local value100 = floor(10 ^ l * 100 + 1e-10)
		if value100 == 0 then return "0" end
		local text = suffixFastText[value100]
		if text == nil then
			local w = value100 // 100
			local frac = value100 - w * 100
			if frac == 0 then text = tostring(w)
			else text = tostring(w) .. suffixFractionText[frac] end
		end
		return if s < 0 then "-" .. text else text
	end

	if l >= -3 then
		local value1000 = floor(10 ^ l * 1000 + 1e-10)
		if value1000 <= 0 then return "0" end
		local body = tostring(value1000 / 1000)
		return if s < 0 then "-" .. body else body
	end

	if l > -3000 then
		local inv = -l
		local whole = floor(inv)
		local k = whole // 3
		local suffix = suffixCache[k]
		if inv == whole then
			local body = "1/" .. suffixExactMantissa[whole % 3 + 1] .. suffix
			return if s < 0 then "-" .. body else body
		end
		local value100 = floor(10 ^ (inv - k * 3) * 100 + 1e-10)
		local text = suffixFastText[value100]
		if text == nil then
			local w = value100 // 100
			local frac = value100 - w * 100
			if frac == 0 then text = tostring(w)
			else text = tostring(w) .. suffixFractionText[frac] end
		end
		local body = "1/" .. text .. suffix
		return if s < 0 then "-" .. body else body
	end

	local exponent = floor(l)
	local value100 = floor(10 ^ (l - exponent) * 100 + 1e-10)
	local text = suffixFastText[value100]
	if text == nil then
		local w = value100 // 100
		local frac = value100 - w * 100
		if frac == 0 then text = tostring(w)
		else text = tostring(w) .. suffixFractionText[frac] end
	end
	local body = text .. "e" .. tostring(exponent)
	return if s < 0 then "-" .. body else body
end

function module.toESuffix(val: buffer, switchAt: number?): string
	local s = breadi8(val, SIGN_OFFSET)
	local l = breadf64(val, LOG_OFFSET)

	if s == NAN_SIGN then return "NaN" end
	if s == 0 then return "0" end
	if l == huge then return if s < 0 then "-Inf" else "Inf" end

	local threshold = switchAt or 1000
	if threshold ~= threshold then threshold = 1000 end
	if threshold < 3 then threshold = 3 end

	if l < threshold then
		return module.toSuffix(val)
	end

	local prefix = if s < 0 then "-" else ""
	local exponent = floor(l)
	local mantissa100 = suffixTruncated100(10 ^ (l - exponent))
	local exponentText = compactExponentText(exponent)

	if mantissa100 == 100 then
		return prefix .. "E" .. exponentText
	end

	return prefix .. suffixHundredthsText(mantissa100) .. "E" .. exponentText
end

function module.format(val: buffer, digits: number?, hyperAt: number?): string
	local s = breadi8(val, SIGN_OFFSET)
	local l = breadf64(val, LOG_OFFSET)

	if s == NAN_SIGN then return "NaN" end
	if s == 0 then return "0" end
	if l == huge then return if s < 0 then "-Inf" else "Inf" end

	local d = digits

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
	if s == NAN_SIGN then return "NaN" end
	if s == 0 then return "0e0" end
	local l = breadf64(val, LOG_OFFSET)
	if l == huge then return if s > 0 then "Inf" else "-Inf" end
	local exponent = floor(l)
	local man = 10 ^ (l - exponent)
	if s < 0 then return "-" .. tostring(man) .. "e" .. tostring(exponent) end
	return tostring(man) .. "e" .. tostring(exponent)
end

module.toString = module.toStr

local function geometricTotalFromCount(
	costLog: number,
	multiplierLog: number,
	multiplierMinusOneLog: number,
	amount: number
): buffer
	if amount <= 0 then
		return cloneRaw(ZERO)
	end

	if multiplierLog == 0 then
		return makeRaw(1, costLog + log10(amount))
	end

	local mpLog = amount * multiplierLog
	if mpLog == huge then
		return cloneRaw(INF)
	end

	local mpMinusOneLog
	if mpLog > DOMINANCE then
		mpMinusOneLog = mpLog
	else
		local v = pow10MinusOne(mpLog)
		if v <= 0 then
			return cloneRaw(ZERO)
		end
		mpMinusOneLog = log10(v)
	end

	return makeRaw(1, costLog + mpMinusOneLog - multiplierMinusOneLog)
end

local function maxBuyCore(funds: buffer, cost: buffer, multiplier: buffer): (number, number, buffer)
	local sf = breadi8(funds, SIGN_OFFSET)
	local sc = breadi8(cost, SIGN_OFFSET)
	local sm = breadi8(multiplier, SIGN_OFFSET)

	if sf == NAN_SIGN or sc == NAN_SIGN or sm == NAN_SIGN then
		return 0, -huge, cloneRaw(NAN)
	end
	if sf <= 0 then
		return 0, -huge, cloneRaw(ZERO)
	end
	if sc <= 0 or sm <= 0 then
		return 0, -huge, cloneRaw(NAN)
	end
	if cmpRaw(funds, cost) < 0 then
		return 0, -huge, cloneRaw(ZERO)
	end

	local lf = breadf64(funds, LOG_OFFSET)
	local lc = breadf64(cost, LOG_OFFSET)
	local lm = breadf64(multiplier, LOG_OFFSET)
	if lm == huge then
		return 1, 0, cloneRaw(cost)
	end
	if lm == 0 then
		local ratioLog = lf - lc
		if ratioLog < 0 then
			return 0, -huge, cloneRaw(ZERO)
		end

		if ratioLog <= MAX_SAFE_LOG10 then
			local amount = floor(10 ^ ratioLog + 1e-9)
			if amount <= 0 then
				return 0, -huge, cloneRaw(ZERO)
			end

			local total = makeRaw(1, lc + log10(amount))
			while amount > 0 and cmpRaw(total, funds) > 0 do
				amount -= 1
				if amount <= 0 then
					return 0, -huge, cloneRaw(ZERO)
				end
				total = makeRaw(1, lc + log10(amount))
			end

			local nextAmount = amount + 1
			if nextAmount <= MAX_SAFE_INTEGER then
				local nextTotal = makeRaw(1, lc + log10(nextAmount))
				if cmpRaw(nextTotal, funds) <= 0 then
					amount = nextAmount
					total = nextTotal
				end
			end

			return amount, log10(amount), total
		end

		local amount = if ratioLog > 308.25471555991675 then huge else floor(10 ^ ratioLog)
		return amount, ratioLog, cloneRaw(funds)
	end

	if lm < 0 then
		return 0, -huge, cloneRaw(NAN)
	end

	local mMinusOne = pow10MinusOne(lm)
	if mMinusOne <= 0 or mMinusOne ~= mMinusOne then
		return 0, -huge, cloneRaw(NAN)
	end

	local mMinusOneLog = log10(mMinusOne)
	local xLog = lf + mMinusOneLog - lc
	local onePlusXLog = log10OnePlusPow10(xLog)

	if onePlusXLog ~= onePlusXLog or onePlusXLog <= 0 then
		return 0, -huge, cloneRaw(ZERO)
	end

	local estimated = onePlusXLog / lm
	if estimated ~= estimated or estimated < 1 then
		return 0, -huge, cloneRaw(ZERO)
	end

	if estimated <= MAX_SAFE_INTEGER then
		local amount = floor(estimated)
		if amount <= 0 then
			return 0, -huge, cloneRaw(ZERO)
		end

		local total = geometricTotalFromCount(lc, lm, mMinusOneLog, amount)

		while amount > 0 and cmpRaw(total, funds) > 0 do
			amount -= 1
			if amount <= 0 then
				return 0, -huge, cloneRaw(ZERO)
			end
			total = geometricTotalFromCount(lc, lm, mMinusOneLog, amount)
		end

		local nextAmount = amount + 1
		if nextAmount <= MAX_SAFE_INTEGER then
			local nextTotal = geometricTotalFromCount(lc, lm, mMinusOneLog, nextAmount)
			if cmpRaw(nextTotal, funds) <= 0 then
				amount = nextAmount
				total = nextTotal
			end
		end

		return amount, log10(amount), total
	end

	local amount = if estimated == huge then huge else estimated
	local amountLog = log10(onePlusXLog) - log10(lm)
	local total = if lf == huge then cloneRaw(INF) else cloneRaw(funds)
	return amount, amountLog, total
end

function module.maxBuy(val1: buffer, val2: buffer, multi: buffer): (number, buffer)
	local amount, _, totalCost = maxBuyCore(val1, val2, multi)
	return amount, totalCost
end

function module.maxBuyBnum(val1: buffer, val2: buffer, multi: buffer): (buffer, buffer)
	local amount, amountLog, totalCost = maxBuyCore(val1, val2, multi)
	if amount <= 0 then
		return cloneRaw(ZERO), totalCost
	end
	if amount ~= huge and amount <= MAX_SAFE_INTEGER then
		return fromFiniteNumber(amount), totalCost
	end
	return makeRaw(1, amountLog), totalCost
end

function module.canAfford(funds: buffer, cost: buffer): boolean
	if breadi8(funds, SIGN_OFFSET) == NAN_SIGN or breadi8(cost, SIGN_OFFSET) == NAN_SIGN then
		return false
	end
	return cmpRaw(funds, cost) >= 0
end

function module.bulkCost(cost: buffer, multiplier: buffer, amount: buffer): buffer
	local sc = breadi8(cost, SIGN_OFFSET)
	local sm = breadi8(multiplier, SIGN_OFFSET)
	local sa = breadi8(amount, SIGN_OFFSET)

	if sc == NAN_SIGN or sm == NAN_SIGN or sa == NAN_SIGN then
		return cloneRaw(NAN)
	end
	if sa == 0 then
		return cloneRaw(ZERO)
	end
	if sc <= 0 or sm <= 0 or sa < 0 then
		return cloneRaw(NAN)
	end

	local lc = breadf64(cost, LOG_OFFSET)
	local lm = breadf64(multiplier, LOG_OFFSET)
	local la = breadf64(amount, LOG_OFFSET)

	if lm == 0 then
		return makeRaw(1, lc + la)
	end
	if lm < 0 then
		return cloneRaw(NAN)
	end

	local amountValue
	if la > 308.25471555991675 then
		amountValue = huge
	else
		amountValue = 10 ^ la
	end

	local mpLog
	if amountValue == huge then
		mpLog = huge
	else
		mpLog = amountValue * lm
	end

	if mpLog == huge then
		return cloneRaw(INF)
	end

	local mMinusOne = pow10MinusOne(lm)
	if mMinusOne <= 0 or mMinusOne ~= mMinusOne then
		return cloneRaw(NAN)
	end

	local mpMinusOneLog
	if mpLog > DOMINANCE then
		mpMinusOneLog = mpLog
	else
		local v = pow10MinusOne(mpLog)
		if v <= 0 then return cloneRaw(ZERO) end
		mpMinusOneLog = log10(v)
	end

	return makeRaw(1, lc + mpMinusOneLog - log10(mMinusOne))
end

function module.bulkCostNumber(cost: buffer, multiplier: buffer, amount: number): buffer
	if amount ~= amount or amount < 0 then
		return cloneRaw(NAN)
	end
	if amount == huge then
		return cloneRaw(INF)
	end

	amount = floor(amount)
	if amount <= 0 then
		return cloneRaw(ZERO)
	end

	return module.bulkCost(cost, multiplier, fromFiniteNumber(amount))
end

function module.maxBuyLimited(
	funds: buffer,
	cost: buffer,
	multiplier: buffer,
	limit: number
): (number, buffer)
	if limit ~= limit or limit <= 0 then
		return 0, cloneRaw(ZERO)
	end

	limit = floor(limit)
	if limit <= 0 then
		return 0, cloneRaw(ZERO)
	end

	local affordable, fullCost = module.maxBuy(funds, cost, multiplier)
	if affordable <= 0 then
		return 0, fullCost
	end

	if affordable <= limit then
		return affordable, fullCost
	end

	return limit, module.bulkCostNumber(cost, multiplier, limit)
end

function module.nextCost(cost: buffer, multiplier: buffer, owned: buffer): buffer
	local sc = breadi8(cost, SIGN_OFFSET)
	local sm = breadi8(multiplier, SIGN_OFFSET)
	local so = breadi8(owned, SIGN_OFFSET)

	if sc == NAN_SIGN or sm == NAN_SIGN or so == NAN_SIGN then
		return cloneRaw(NAN)
	end
	if sc <= 0 or sm <= 0 or so < 0 then
		return cloneRaw(NAN)
	end
	if so == 0 then
		return cloneRaw(cost)
	end

	local lc = breadf64(cost, LOG_OFFSET)
	local lm = breadf64(multiplier, LOG_OFFSET)
	if lm == 0 then
		return cloneRaw(cost)
	end

	local lo = breadf64(owned, LOG_OFFSET)
	if lo > 308.25471555991675 then
		if lm > 0 then return cloneRaw(INF) end
		return cloneRaw(ZERO)
	end

	local ownedValue = 10 ^ lo
	local resultLog = lc + ownedValue * lm
	if resultLog == huge then return cloneRaw(INF) end
	if resultLog == -huge then return cloneRaw(ZERO) end
	return makeRaw(1, resultLog)
end

function module.nextCostNumber(cost: buffer, multiplier: buffer, owned: number): buffer
	if owned ~= owned or owned < 0 then
		return cloneRaw(NAN)
	end
	if owned == 0 then
		return cloneRaw(cost)
	end

	local sc = breadi8(cost, SIGN_OFFSET)
	local sm = breadi8(multiplier, SIGN_OFFSET)
	if sc <= 0 or sm <= 0 then
		return cloneRaw(NAN)
	end

	local lm = breadf64(multiplier, LOG_OFFSET)
	if lm == 0 then return cloneRaw(cost) end
	if owned == huge then
		return if lm > 0 then cloneRaw(INF) else cloneRaw(ZERO)
	end

	local resultLog = breadf64(cost, LOG_OFFSET) + owned * lm
	if resultLog == huge then return cloneRaw(INF) end
	if resultLog == -huge then return cloneRaw(ZERO) end
	return makeRaw(1, resultLog)
end

function module.buyMax(funds: buffer, cost: buffer, multiplier: buffer): (number, buffer, buffer)
	local amount, totalCost = module.maxBuy(funds, cost, multiplier)
	if amount <= 0 then
		return amount, totalCost, cloneRaw(funds)
	end

	local remaining = cloneRaw(funds)
	subRaw(remaining, remaining, totalCost)
	if breadi8(remaining, SIGN_OFFSET) < 0 then
		setRaw(remaining, 0, 0)
	end
	return amount, totalCost, remaining
end

function module.buyMaxLimited(
	funds: buffer,
	cost: buffer,
	multiplier: buffer,
	limit: number
): (number, buffer, buffer)
	local amount, totalCost = module.maxBuyLimited(funds, cost, multiplier, limit)
	if amount <= 0 then
		return amount, totalCost, cloneRaw(funds)
	end

	local remaining = cloneRaw(funds)
	subRaw(remaining, remaining, totalCost)
	if breadi8(remaining, SIGN_OFFSET) < 0 then
		setRaw(remaining, 0, 0)
	end

	return amount, totalCost, remaining
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


function module.linear(base: buffer, increment: buffer, level: buffer): buffer
	local product = bcreate(SIZE)
	mulRaw(product, increment, level)
	return addRaw(product, base, product)
end

function module.linearNumber(base: buffer, increment: buffer, level: number): buffer
	if level ~= level then
		return cloneRaw(NAN)
	end
	if level == 0 then
		return cloneRaw(base)
	end
	local product = bcreate(SIZE)
	if level == huge or level == -huge then
		setRaw(product, if level > 0 then breadi8(increment, SIGN_OFFSET) else -breadi8(increment, SIGN_OFFSET), huge)
	else
		local si = breadi8(increment, SIGN_OFFSET)
		if si == NAN_SIGN then return cloneRaw(NAN) end
		if si == 0 then return cloneRaw(base) end
		setRaw(product, si * signm(level), breadf64(increment, LOG_OFFSET) + log10(abs(level)))
	end
	return addRaw(product, base, product)
end

function module.softCap(val: buffer, cap: buffer, power: buffer): buffer
	local sv = breadi8(val, SIGN_OFFSET)
	local sc = breadi8(cap, SIGN_OFFSET)
	local sp = breadi8(power, SIGN_OFFSET)
	if sv == NAN_SIGN or sc == NAN_SIGN or sp == NAN_SIGN then
		return cloneRaw(NAN)
	end
	if sv <= 0 or sc <= 0 then
		return cloneRaw(NAN)
	end
	if cmpRaw(val, cap) <= 0 then
		return cloneRaw(val)
	end
	if sp == 0 then
		return cloneRaw(cap)
	end

	local lp = breadf64(power, LOG_OFFSET)
	if lp == huge then
		return if sp > 0 then cloneRaw(INF) else cloneRaw(ZERO)
	end

	local p = sp * 10 ^ lp
	local resultLog = breadf64(cap, LOG_OFFSET)
		+ (breadf64(val, LOG_OFFSET) - breadf64(cap, LOG_OFFSET)) * p

	return makeRaw(1, resultLog)
end

function module.milestoneCount(val: buffer, step: buffer): buffer
	local out = cloneRaw(val)
	return module.intdiv(out, step)
end

function module.milestone(val: buffer, step: buffer, bonus: buffer): buffer
	if breadi8(step, SIGN_OFFSET) <= 0 then
		return cloneRaw(NAN)
	end

	local count = module.milestoneCount(val, step)
	local scaled = mulRaw(count, count, bonus)
	return addRaw(bcreate(SIZE), ONE, scaled)
end

function module.scaleCurve(val1: buffer, base: buffer, exponent: buffer, mode: ScaleMode): buffer
	local a = cloneRaw(val1)
	local b = base
	local e = exponent
	local s1 = breadi8(a, SIGN_OFFSET)
	local s2 = breadi8(b, SIGN_OFFSET)
	if s1 == NAN_SIGN or s2 == NAN_SIGN then return setRaw(a, NAN_SIGN, 0) end
	if s1 <= 0 or s2 <= 0 then return setRaw(a, 1, 0) end
	if mode ~= "linear" and mode ~= "exp" and mode ~= "sigmoid" then return setRaw(a, NAN_SIGN, 0) end
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
	if se == NAN_SIGN then return setRaw(a, NAN_SIGN, 0) end
	local le = breadf64(e, LOG_OFFSET)
	local exVal = if se == 0 then 0 else se * 10 ^ le
	local powLog = tLog * exVal
	if powLog > 16 then return setRaw(a, 1, powLog) end
	return setRaw(a, 1, log10(10 ^ powLog + 1))
end

function module.progress(val1: buffer, goal: buffer, modes: ScaleMode): buffer
	local a = cloneRaw(val1)
	local g = goal
	local s1 = breadi8(a, SIGN_OFFSET)
	local s2 = breadi8(g, SIGN_OFFSET)
	if s1 == NAN_SIGN or s2 == NAN_SIGN then return setRaw(a, NAN_SIGN, 0) end
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
		local low = 1 / (1 + expm(3))
		local high = 1 / (1 + expm(-3))
		local raw = 1 / (1 + expm(-6 * (ratio - 0.5)))
		scale = (raw - low) / (high - low)
	else
		return setRaw(a, NAN_SIGN, 0)
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
	local s1 = breadi8(val1, SIGN_OFFSET)
	local s2 = breadi8(val2, SIGN_OFFSET)
	if s1 == NAN_SIGN or s2 == NAN_SIGN or s2 == 0 then return makeFast(NAN_SIGN, 0) end
	if s1 == 0 then return makeFast(0, 0) end
	local s = s1 * s2
	local l = breadf64(val1, LOG_OFFSET) - breadf64(val2, LOG_OFFSET)
	if l == -huge then return makeFast(0, 0) end
	if l >= 16 then return makeFast(s, l) end
	local q = s * 10 ^ l
	local n = floor(q)
	if n == 0 then return makeFast(0, 0) end
	return makeFast(if n < 0 then -1 else 1, log10(abs(n)))
end

function module.clamp(val1: buffer, minVal: buffer, maxVal: buffer): buffer
	local mn = minVal
	local mx = maxVal
	if breadi8(val1, SIGN_OFFSET) == NAN_SIGN or breadi8(mn, SIGN_OFFSET) == NAN_SIGN or breadi8(mx, SIGN_OFFSET) == NAN_SIGN then
		return cloneRaw(NAN)
	end
	if cmpRaw(mn, mx) > 0 then mn, mx = mx, mn end
	if cmpRaw(val1, mn) < 0 then return cloneRaw(mn) end
	if cmpRaw(val1, mx) > 0 then return cloneRaw(mx) end
	return cloneRaw(val1)
end

function module.dynamicCost(cost: buffer, owned: buffer, scale: buffer, method: 'exp' | 'linear' | 'hybrid'): buffer
	local c = cloneRaw(cost)
	local o = owned
	local s = scale
	local sc = breadi8(c, SIGN_OFFSET)
	local so = breadi8(o, SIGN_OFFSET)
	local ss = breadi8(s, SIGN_OFFSET)
	if sc == NAN_SIGN or so == NAN_SIGN or ss == NAN_SIGN or sc <= 0 or so < 0 or ss <= 0 then
		return setRaw(c, NAN_SIGN, 0)
	end
	if method ~= 'exp' and method ~= 'linear' and method ~= 'hybrid' then
		return setRaw(c, NAN_SIGN, 0)
	end

	local lc = breadf64(c, LOG_OFFSET)
	local lo = breadf64(o, LOG_OFFSET)
	local ls = breadf64(s, LOG_OFFSET)
	local ownedValue = if so == 0 then 0 elseif lo > 308.25471555991675 then huge else 10 ^ lo

	if method == 'exp' then
		if so == 0 or ls == 0 then return c end
		return setRaw(c, 1, lc + ownedValue * ls)
	end

	local linearLog
	if so == 0 then
		linearLog = -huge
	else
		linearLog = ls + lo
	end
	if method == 'linear' then
		if linearLog == -huge then return c end
		local d = linearLog - lc
		if d > DOMINANCE then return setRaw(c, 1, linearLog) end
		if d < -DOMINANCE then return c end
		if d >= 0 then return setRaw(c, 1, linearLog + log10(1 + 10 ^ (-d))) end
		return setRaw(c, 1, lc + log10(1 + 10 ^ d))
	end

	local expLog
	if so == 0 or ls == 0 then
		expLog = lc
	else
		expLog = lc + ownedValue * ls
	end
	if expLog ~= expLog then return setRaw(c, NAN_SIGN, 0) end
	if linearLog == -huge then return setRaw(c, 1, expLog) end
	if expLog == -huge then return setRaw(c, 1, linearLog) end
	if expLog == huge then return setRaw(c, 1, huge) end
	local d = linearLog - expLog
	if d > DOMINANCE then return setRaw(c, 1, linearLog) end
	if d < -DOMINANCE then return setRaw(c, 1, expLog) end
	if d >= 0 then return setRaw(c, 1, linearLog + log10(1 + 10 ^ (-d))) end
	return setRaw(c, 1, expLog + log10(1 + 10 ^ d))
end

function module.abs(val: buffer): buffer
	local s = breadi8(val, SIGN_OFFSET)
	if s == NAN_SIGN then return makeFast(NAN_SIGN, 0) end
	if s == 0 then return makeFast(0, 0) end
	return makeFast(1, breadf64(val, LOG_OFFSET))
end

function module.eta(curr: buffer, goal: buffer, rate: buffer): buffer
	local c = cloneRaw(curr)
	local g = goal
	local r = rate
	local sc = breadi8(c, SIGN_OFFSET)
	local sg = breadi8(g, SIGN_OFFSET)
	local sr = breadi8(r, SIGN_OFFSET)
	if sc == NAN_SIGN or sg == NAN_SIGN or sr == NAN_SIGN then return setRaw(c, NAN_SIGN, 0) end
	if sr <= 0 then return setRaw(c, 1, huge) end
	if cmpRaw(c, g) >= 0 or sg <= 0 then return setRaw(c, 0, 0) end

	local lg = breadf64(g, LOG_OFFSET)
	local diffLog
	if sc <= 0 then
		if sc == 0 then
			diffLog = lg
		else
			local lc = breadf64(c, LOG_OFFSET)
			local d = lc - lg
			if d > DOMINANCE then diffLog = lc else diffLog = lg + log10(1 + 10 ^ d) end
		end
	else
		local lc = breadf64(c, LOG_OFFSET)
		local d = lc - lg
		if d < -DOMINANCE then
			diffLog = lg
		elseif d >= 0 then
			return setRaw(c, 0, 0)
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

function module.isValid(val: any): boolean
	if type(val) ~= "buffer" or buffer.len(val) < SIZE then return false end
	local s = breadi8(val, SIGN_OFFSET)
	local l = breadf64(val, LOG_OFFSET)
	if s ~= NAN_SIGN and s ~= -1 and s ~= 0 and s ~= 1 then return false end
	if l ~= l then return false end
	if s == NAN_SIGN then return l == 0 end
	if s == 0 then return l == 0 end
	return l ~= -huge
end

function module.isBnum(val: any): boolean
	return type(val) == "buffer" and buffer.len(val) >= SIZE
end

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
function module.compat.powf(a: any, power: number): buffer
	return module.powf(module.ensure(a), power)
end
function module.compat.sqrt(a: any): buffer
	return module.sqrt(module.ensure(a))
end
function module.compat.log10(a: any): buffer
	return module.log10(module.ensure(a))
end
function module.compat.abs(a: any): buffer
	return module.abs(module.ensure(a))
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
function module.compat.toESuffix(a: any, switchAt: number?): string
	return module.toESuffix(module.ensure(a), switchAt)
end

function module.compat.maxBuy(funds: any, cost: any, multiplier: any): (number, buffer)
	return module.maxBuy(module.ensure(funds), module.ensure(cost), module.ensure(multiplier))
end
function module.compat.maxBuyBnum(funds: any, cost: any, multiplier: any): (buffer, buffer)
	return module.maxBuyBnum(module.ensure(funds), module.ensure(cost), module.ensure(multiplier))
end
function module.compat.maxBuyLimited(funds: any, cost: any, multiplier: any, limit: number): (number, buffer)
	return module.maxBuyLimited(module.ensure(funds), module.ensure(cost), module.ensure(multiplier), limit)
end
function module.compat.buyMaxLimited(funds: any, cost: any, multiplier: any, limit: number): (number, buffer, buffer)
	return module.buyMaxLimited(module.ensure(funds), module.ensure(cost), module.ensure(multiplier), limit)
end
function module.compat.bulkCost(cost: any, multiplier: any, amount: any): buffer
	return module.bulkCost(module.ensure(cost), module.ensure(multiplier), module.ensure(amount))
end
function module.compat.nextCost(cost: any, multiplier: any, owned: any): buffer
	return module.nextCost(module.ensure(cost), module.ensure(multiplier), module.ensure(owned))
end
function module.compat.linear(base: any, increment: any, level: any): buffer
	return module.linear(module.ensure(base), module.ensure(increment), module.ensure(level))
end
function module.compat.softCap(val: any, cap: any, power: any): buffer
	return module.softCap(module.ensure(val), module.ensure(cap), module.ensure(power))
end
function module.compat.milestone(val: any, step: any, bonus: any): buffer
	return module.milestone(module.ensure(val), module.ensure(step), module.ensure(bonus))
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

module.maxBuyBig = module.maxBuyBnum
module.maxBuyCapped = module.maxBuyLimited
module.buyMaxCapped = module.buyMaxLimited
module.toExponentSuffix = module.toESuffix
module.toExtendedSuffix = module.toESuffix
module.totalCost = module.bulkCost
module.costAt = module.nextCost

return module
