--!optimize 2
--!native

local first = {'', 'k', 'm', 'b'}
local firstset = {"", "U","D","T","Qd","Qn","Sx","Sp","Oc","No"}
local second   = {"", "De","Vt","Tg","qg","Qg","sg","Sg","Og","Ng"}
local third    = {"", "Ce","Du","Tr","Qa","Qi","Se","Si","Ot","Ni"}

local ZERO = buffer.create(12)
buffer.writei8(ZERO, 0, 0)
buffer.writef64(ZERO, 4, 0)
local One = buffer.create(12)
buffer.writei8(One, 0, 1)
buffer.writef64(One, 4, 0)
local NAN = buffer.create(12)
buffer.writei8(NAN, 0, -2)
buffer.writef64(NAN, 4, 0)
local INF = buffer.create(12)
buffer.writei8(INF, 0, 1)
buffer.writef64(INF, 4, 1/0)
local NegINF = buffer.create(12)
buffer.writei8(INF, 0, -1)
buffer.writef64(INF, 4, 1/0)

local module = {}

function module.ensure(val: any): buffer
	local t = type(val)
	if t == "buffer" then
		return val
	end
	local buff = buffer.create(12)
	if t == "number" then
		if val ~= val then
			buffer.copy(buff, 0, NAN, 0, 12)
		elseif val == 0 then
			buffer.copy(buff, 0, ZERO, 0, 12)
		else
			buffer.writei8(buff, 0, math.sign(val))
			buffer.writef64(buff, 4, math.log10(math.abs(val)))
		end
		return buff
	end
	if t == "string" then
		local e = string.find(val, "e")

		if e then
			local man = tonumber(string.sub(val, 1, e - 1))
			local exp = tonumber(string.sub(val, e + 1))
			if not man or not exp or man ~= man or exp ~= exp then
				buffer.copy(buff, 0, NAN, 0, 12)
			elseif man == 0 then
				buffer.copy(buff, 0, ZERO, 0, 12)
			else
				buffer.writei8(buff, 0, math.sign(man))
				buffer.writef64(buff, 4, math.log10(math.abs(man)) + exp)
			end
		else
			local num = tonumber(val)
			if not num or num ~= num then
				buffer.copy(buff, 0, NAN, 0, 12)
			elseif num == 0 then
				buffer.copy(buff, 0, ZERO, 0, 12)
			else
				buffer.writei8(buff, 0, math.sign(num))
				buffer.writef64(buff, 4, math.log10(math.abs(num)))
			end
		end
		return buff
	end
	error("Unsupported type")
end

function module.new(man: number, exp: number): buffer
	local out = buffer.create(12)
	if man == 0 then
		buffer.copy(out, 0, ZERO, 0, 12)
		return out
	end
	buffer.writei8(out, 0, math.sign(man))
	buffer.writef64(out, 4, math.log10(math.abs(man))+exp)
	return out
end

function module.fromNumber(val: number): buffer
	local buff = buffer.create(12)
	if typeof(val) ~= 'number' or val ~= val then
		buffer.copy(buff, 0, NAN, 0, 12)
		return buff
	end
	if val == 0 then
		buffer.copy(buff, 0, ZERO, 0, 12)
		return buff
	end
	buffer.writei8(buff, 0, math.sign(val))
	buffer.writef64(buff, 4, math.log10(math.abs(val)))
	return buff
end

function module.add(val1: any, val2: any): buffer
	val1, val2 = module.ensure(val1), module.ensure(val2)
	local sign1, log1 = buffer.readi8(val1, 0), buffer.readf64(val1, 4)
	local sign2, log2 = buffer.readi8(val2, 0), buffer.readf64(val2, 4)
	local out = buffer.create(12)
	if sign1 == -2 or sign2 == -2 then
		buffer.copy(out, 0, NAN, 0, 12)
		return out
	end
	if sign1 == 0 then return val2 end
	if sign2 == 0 then return val1 end
	local difference = log1 - log2
	if difference > 16 then return val1 end
	if difference < -16 then return val2 end
	if difference == 0 and sign1 ~= sign2 then
		buffer.copy(out, 0, ZERO, 0, 12)
		return out
	end
	local outSign, outExp
	if sign1 == sign2 then
		outSign = sign1
		outExp = log2 + math.log10(10^difference + 1)
	else
		if difference >= 0 then
			outSign = sign1
			outExp = log1 + math.log10(1 - 10^-difference)
		else
			outSign = -sign1
			outExp = log2 + math.log10(1 - 10^difference)
		end
	end
	buffer.writei8(out, 0, outSign)
	buffer.writef64(out, 4, outExp)
	return out
end

function module.sub(val1: any, val2: any): buffer
	val1, val2 = module.ensure(val1), module.ensure(val2)
	local sign1, log1 = buffer.readi8(val1, 0), buffer.readf64(val1, 4)
	local sign2, log2 = buffer.readi8(val2, 0), buffer.readf64(val2, 4)
	if sign1 == -2 or sign2 == -2 then
		buffer.copy(val1, 0, NAN, 0, 12)
		return val1
	end
	if sign1 == 0 then
		buffer.copy(val1, 0, val2, 0, 12)
		return val1
	elseif sign2 == 0 then
		buffer.copy(val1, 0, val1, 0, 12)
		return val1
	end
	local difference = log1 - log2
	if difference > 16 then
		buffer.copy(val1, 0, val1, 0, 12)
		return val1
	elseif difference < -16 then
		buffer.copy(val1, 0, val2, 0, 12)
		return val1
	elseif difference == 0 and sign1 == sign2 then
		buffer.copy(val1, 0, ZERO, 0, 12)
		return val1
	end
	local outSign, outExp
	if sign1 == sign2 then
		if difference >= 0 then
			outSign = sign1
			outExp = log1 + math.log10(1 - 10^-difference)
		else
			outSign = -sign1
			outExp = log2 + math.log10(1 - 10^difference)
		end
	else
		outSign = sign1
		outExp = log2 + math.log10(10^difference + 1)
	end
	buffer.writei8(val1, 0, outSign)
	buffer.writef64(val1, 4, outExp)
	return val1
end

-- acts like sub but maxes at 0 instead of -1 and so on
function module.subz(val1: any, val2: any): buffer
	local out = module.sub(val1, val2)
	if buffer.readi8(out, 0) < 0 then
		buffer.copy(out, 0, ZERO, 0, 12)
	end
	return out
end

function module.mul(val1: any, val2: any): buffer
	val1, val2 = module.ensure(val1), module.ensure(val2)
	local sign1, log1 = buffer.readi8(val1, 0), buffer.readf64(val1, 4)
	local sign2, log2 = buffer.readi8(val2, 0), buffer.readf64(val2, 4)
	if sign1 == -2 or sign2 == -2 then
		buffer.copy(val1, 0, NAN, 0, 12)
		return val1
	end
	if sign1 == 0 or sign2 == 0 then
		buffer.copy(val1, 0, ZERO, 0, 12)
		return val1
	end
	buffer.writei8(val1, 0, sign1 * sign2)
	buffer.writef64(val1, 4, log1 + log2)
	return val1
end

function module.div(val1: any, val2: any): buffer
	val1, val2 = module.ensure(val1), module.ensure(val2)
	local sign1, log1 = buffer.readi8(val1, 0), buffer.readf64(val1, 4)
	local sign2, log2 = buffer.readi8(val2, 0), buffer.readf64(val2, 4)
	if sign1 == -2 or sign2 == -2 then
		buffer.copy(val1, 0, NAN, 0, 12)
		return val1
	end
	if sign1 == 0 or sign2 == 0 then
		buffer.copy(val1, 0, ZERO, 0, 12)
		return val1
	end
	buffer.writei8(val1, 0, sign1 / sign2)
	buffer.writef64(val1, 4, log1 - log2)
	return val1
end

function module.pow(val1: any, val2: any): buffer
	val1, val2 = module.ensure(val1), module.ensure(val2)
	local sign1, log1 = buffer.readi8(val1, 0), buffer.readf64(val1, 4)
	local sign2, log2 = buffer.readi8(val2, 0), buffer.readf64(val2, 4)
	if sign1 == -2 or sign2 == -2 then
		buffer.copy(val1, 0, NAN, 0, 12)
		return val1
	end
	if sign1 == 0 then
		if sign2 == 0 then
			buffer.copy(val1, 0, ZERO, 0, 12)
		else
			buffer.copy(val1, 0, ZERO, 0, 12)
		end
		return val1
	end
	local power = 10^log2 * sign2
	local outSign = 1
	if sign1 == -1 then
		if power % 2 ~= 0 then
			outSign = -1
		end
	end
	buffer.writei8(val1, 0, outSign)
	buffer.writef64(val1, 4, log1 * power)
	return val1
end

function module.pow10(val: any): buffer
	val = module.ensure(val)
	local sign, log = buffer.readi8(val, 0), buffer.readf64(val, 4)
	if sign == -2 then
		buffer.copy(val, 0, NAN, 0, 12)
		return val
	end
	buffer.writei8(val, 0, 1)
	buffer.writef64(val, 4, sign*10^log)
	return val
end

function module.sqrt(val: any): buffer
	val = module.ensure(val)
	local sign, log = buffer.readi8(val, 0), buffer.readf64(val, 4)
	if sign < 0 then
		buffer.copy(val, 0, NAN, 0, 12)
		return val
	elseif sign == 0 then
		buffer.copy(val, 0, ZERO, 0, 12)
		return val
	end
	buffer.writei8(val, 0, 1)
	buffer.writef64(val, 4, 0.5*log)
	return val
end

function module.log10(val: any): buffer
	val = module.ensure(val)
	local sign, log = buffer.readi8(val, 0), buffer.readf64(val, 4)
	if sign <= 0 then
		buffer.copy(val, 0, NAN, 0, 12)
		return val
	end
	buffer.writei8(val, 0, math.sign(log))
	buffer.writef64(val, 4, math.log10(math.abs(log)))
	return val
end

function module.log(val1: any, val2: any): buffer
	val1 = module.ensure(val1)
	local sign1, log1 = buffer.readi8(val1, 0), buffer.readf64(val1, 4)
	if sign1 <= 0 then
		buffer.copy(val1, 0, NAN, 0, 12)
		return val1
	end
	local LN10 = 2.302585092994046
	local ln1 = log1 * LN10
	if val2 == nil then
		if ln1 == 0 then
			buffer.copy(val1, 0, ZERO, 0, 12)
			return val1
		end
		buffer.writei8(val1, 0, math.sign(ln1))
		buffer.writef64(val1, 4, math.log10(math.abs(ln1)))
		return val1
	end
	val2 = module.ensure(val2)
	local sign2, log2 = buffer.readi8(val2, 0), buffer.readf64(val2, 4)
	if sign2 <= 0 then
		buffer.copy(val1, 0, NAN, 0, 12)
		return val1
	end
	local ln2 = log2 * LN10
	if ln2 == 0 then
		buffer.copy(val1, 0, NAN, 0, 12)
		return val1
	end
	local result = ln1 / ln2
	if result == 0 then
		buffer.copy(val1, 0, ZERO, 0, 12)
		return val1
	end
	buffer.writei8(val1, 0, math.sign(result))
	buffer.writef64(val1, 4, math.log10(math.abs(result)))
	return val1
end

function module.exp(val: any): buffer
	val = module.ensure(val)
	local sign, log = buffer.readi8(val, 0), buffer.readf64(val, 4)
	if sign == -2 then
		buffer.copy(val, 0, NAN, 0, 12)
		return val
	end
	buffer.writei8(val, 0, 1)
	buffer.writef64(val, 4, 0.4342944819032518*10^log*sign)
	return val
end

function module.random(val1: any, val2: any): buffer
	if val1 == nil and val2 == nil then
		return module.fromNumber(math.random())
	end
	val1, val2 = module.ensure(val1), module.ensure(val2)
	local sign1, log1 = buffer.readi8(val1, 0), buffer.readf64(val1, 4)
	local sign2, log2 = buffer.readi8(val2, 0), buffer.readf64(val2, 4)
	if sign1 <= 0 or sign2 <= 0 then
		return module.fromNumber(math.random())
	end		
	buffer.writei8(val1, 0, 1)
	buffer.writef64(val1, 4, log1+math.random()*(log2-log1))
	return val1
end

function module.cmp(val1: any, val2: any): number
	val1, val2 = module.ensure(val1), module.ensure(val2)
	local sign1, exp1 = buffer.readi8(val1, 0), buffer.readf64(val1, 4)
	local sign2, exp2 = buffer.readi8(val2, 0), buffer.readf64(val2, 4)
	if sign1 ~= sign2 then
		return if sign1 > sign2 then 1 else -1
	end
	return if
		exp1 > exp2 then
		sign1
		elseif exp1 < exp2 then
		-1*sign1
		else
		(sign1 ~= -2) and 0 or -1
end

function module.eq(val1: any, val2: any): boolean
	return module.cmp(val1, val2) == 0
end

function module.le(val1: any, val2: any): boolean
	return module.cmp(val1, val2) == -1
end

function module.me(val1: any, val2: any): boolean
	return module.cmp(val1, val2) == 1
end

function module.leeq(val1: any, val2: any): boolean
	return module.cmp(val1, val2) ~= 1
end

function module.meeq(val1: any, val2: any): boolean
	return module.cmp(val1, val2) ~= -1
end

function module.min(...: any): buffer
	local count = select('#', ...)
	local min
	for i = 1, count do
		local val = select(i, ...)
		val = module.ensure(val)
		if not min then min = val end
		if module.cmp(val, min) == -1 then
			min = val
		end
	end
	return min
end

function module.max(...: any): buffer
	local count = select('#', ...)
	local max
	for i = 1, count do
		local val = select(i, ...)
		val = module.ensure(val)
		if not max then max = val end
		if module.cmp(val, max) == 1 then
			max = val
		end
	end
	return max
end

function module.floor(val: any): buffer
	val = module.ensure(val)
	local sign, log = buffer.readi8(val,0), buffer.readf64(val, 4)
	if sign == -2 then
		buffer.copy(val, 0, NAN, 0, 12)
		return val
	end
	if log >= 16 then
		buffer.copy(val, 0, val, 0, 12)
		return val
	end
	if sign == 0 or log < 0 then
		buffer.copy(val, 0, ZERO, 0, 12)
		return val
	end
	if sign == -1 then
		buffer.writei8(val, 0, -1)
		buffer.writef64(val, 4, math.log10(math.ceil(10^log)))
	end
	buffer.writei8(val, 0, 1)
	buffer.writef64(val, 4, math.log10(math.floor(10^log)))
	return val
end

function module.ceil(val: any): buffer
	val = module.ensure(val)
	local sign, log = buffer.readi8(val, 0), buffer.readf64(val, 4)
	if sign == -2 then
		buffer.copy(val, 0, NAN, 0, 12)
		return val
	end
	if log >= 16 then
		buffer.copy(val, 0, val, 0, 12)
		return val
	end
	if sign == 0 or log < 0 then
		buffer.copy(val, 0, ZERO, 0, 12)
		return val
	end
	if sign == -1 then
		buffer.writei8(val, 0, -1)
		buffer.writef64(val, 4, math.log10(math.floor(10^log)))
	end
	buffer.writei8(val, 0, 1)
	buffer.writef64(val, 4, math.log10(math.ceil(10^log)))
	return val
end

function module.round(val: any): buffer
	val = module.ensure(val)
	local sign, log = buffer.readi8(val, 0), buffer.readf64(val, 4)
	if sign == -2 then
		buffer.copy(val, 0, NAN, 0, 12)
		return val
	end
	if log >= 16 then
		buffer.copy(val, 0, val, 0, 12)
		return val
	end
	if sign == 0 or log < 0 then
		buffer.copy(val, 0, ZERO, 0, 12)
		return val
	end
	buffer.writei8(val, 0, sign)
	buffer.writef64(val, 4, math.log10(math.round(10^log)))
	return val
end

function module.mod(val1: any, val2: any): buffer
	val1, val2 = module.ensure(val1), module.ensure(val2)
	local sign1, exp1 = buffer.readi8(val1, 0), buffer.readf64(val1, 4)
	local sign2, exp2 = buffer.readi8(val2, 0), buffer.readf64(val2, 4)
	if sign1 == 0 then
		buffer.copy(val1, 0, ZERO, 0, 12)
		return val1
	end
	if sign2 == 0 then
		buffer.copy(val1, 0, NAN, 0, 12)
		return val1
	end
	if exp1 < exp2 then
		buffer.copy(val1, 0, val1, 0, 12)
		return val1
	end
	local divExp = exp1 - exp2
	local floorDiv = 10^divExp // 1
	local remVal = 10^exp1 - floorDiv * 10^exp2
	local remSign = math.sign(remVal)
	local remLog = math.log10(math.abs(remVal))
	buffer.writei8(val1, 0, remSign)
	buffer.writef64(val1, 4, remLog)
	return val1
end

function module.lbencode(val: any): number
	val = module.ensure(val)
	local sign, log = buffer.readi8(val, 0), buffer.readf64(val, 4)
	if sign == -2 or sign == 0 then
		return 0
	end
	local logAbs
	if log > 16 then
		logAbs = log
	else
		logAbs = math.log10(10^log+1)
	end
	if logAbs > 1.7976931348623157e308 then
		logAbs = 1.7976931348623157e308
	end
	if logAbs <= 0 then
		return 0
	end
	return (math.log10(logAbs + 1) + 1) * 4503599627370496 * sign
end

function module.lbdecode(encoded: number): buffer
	local out = buffer.create(12)
	if encoded == 0 then
		buffer.copy(out, 0, ZERO, 0, 12)
		return out
	end
	local sign = (encoded > 0) and 1 or -1
	local num = math.abs(encoded)
	local scaled = num / 4503599627370496
	local logPlus = 10^(scaled-1)-1
	local logVal
	if logPlus <= 0 then
		buffer.copy(out, 0, ZERO, 0, 12)
		return out
	end
	if logPlus > 10^16 then
		logVal = logPlus
	else
		logVal = math.log10(10^logPlus - 1)
	end
	buffer.writei8(out, 0, sign)
	buffer.writef64(out, 4, logVal)
	return out
end

function module.root(val1: any, val2: any): buffer
	val1, val2 = module.ensure(val1), module.ensure(val2)
	local sign1, log1 = buffer.readi8(val1, 0), buffer.readf64(val1, 4)
	local sign2, log2 = buffer.readi8(val2, 0), buffer.readf64(val2, 4)
	if sign2 <= 0 then
		buffer.copy(val1, 0, NAN, 0, 12)
		return val1
	elseif sign1 == 0 then
		buffer.copy(val1, 0, ZERO, 0, 12)
		return val1
	elseif sign1 < 0 and math.floor(sign2) % 2 == 0 then
		buffer.copy(val1, 0, NAN, 0, 12)
		return val1
	end
	buffer.writei8(val1, 0, 1)
	buffer.writef64(val1, 4, 1/(sign2*10^log2)*log1)
	return val1
end

function module.format(val: any, digits: number?, hyperAt: number?): string
	val = module.ensure(val)
	digits = digits or 2
	hyperAt = hyperAt or 2e20
	local sign, exp = buffer.readi8(val, 0), buffer.readf64(val, 4)
	if sign == -2 then return "NaN" end
	if sign == 0 then return "0" end
	if exp == math.huge then return sign > 0 and "Inf" or "-Inf" end
	local k = math.floor(exp / 3)
	local rem = exp % 3
	local man = 10^rem
	if exp >= hyperAt then
		local eexp = math.floor(math.log10(10^exp))
		local mant = 10^(exp - 10^eexp)
		return mant .. "e" .. module.format({1, eexp}, digits, hyperAt)
	end
	if exp >= 3e3 then
		local lf = exp % 3
		local m = math.floor(man * 10^lf) / 10^lf
		return m .. "e" .. exp
	end
	if exp >= 3 and exp < 6 then
		man = man * 10^3
		man = math.floor(man * 10^digits + 0.001) / 10^digits
		local str = tostring(man)
		local formatted = str:reverse():gsub("(%d%d%d)", "%1,"):reverse()
		formatted = formatted:gsub("^,", "")
		return formatted
	end
	if exp >= 6 then
		local k = math.floor(exp / 3)
		local rem = exp % 3
		local scaled = 10^rem
		local round = 10^digits
		scaled = math.floor(scaled * round + 0.001) / round
		if k <= 3 then
			return scaled .. first[k + 1]
		end
		local i = k - 1
		local a = i % 10
		local b = (i // 10) % 10
		local c = (i // 100) % 10
		return scaled .. firstset[a+1] .. second[b+1] .. third[c+1]
	end
	if exp < -3 then
		local index = math.floor(-exp / 3)
		local rem = -exp % 3
		local scaled = 10^rem
		local round = 10^digits
		scaled = math.floor(scaled * round + 0.001) / round
		if index <= 3 then
			return '1/' .. scaled .. first[index + 1]
		end
		local i = index - 1
		local a = i % 10
		local b = (i // 10) % 10
		local c = (i // 100) % 10
		return '1/' .. scaled .. firstset[a+1] .. second[b+1] .. third[c+1]
	end
	local scale = 10^exp * sign
	scale = math.floor(scale * 10^digits + 0.001) / 10^digits
	return tostring(scale)
end

function module.toStr(val: buffer): string
	local sign, log = buffer.readi8(val, 0), buffer.readf64(val, 4)
	if sign == 0 then return '0e0' elseif sign == -2 then return 'NaN' end
	if log == 1/0 then return 'Inf' end
	local exp = log//1
	local man = 10^(log-exp)
	if sign == -1 then man = -man end
	return man .. 'e' .. exp
end

function module.maxBuy(val1: any, val2: any, multi: any): (number, buffer)
	val1, val2, multi = module.ensure(val1), module.ensure(val2), module.ensure(multi)
	local s1, l1 = buffer.readi8(val1, 0), buffer.readf64(val1, 4)
	local s2, l2 = buffer.readi8(val2, 0), buffer.readf64(val2, 4)
	local sm, lm = buffer.readi8(multi, 0), buffer.readf64(multi, 4)
	local minLog = lm + math.log10(1 - 10^-lm)
	local divLog = l1 + minLog - l2
	local inLog = (divLog > 16)	and divLog or math.log10(10^divLog + 1)
	local totalAmount = math.floor(inLog / lm)
	local mpLog = totalAmount * lm
	local mpsLog = (mpLog > 16)	and mpLog or math.log10(10^mpLog - 1)
	buffer.writei8(val1, 0, s2)
	buffer.writef64(val1, 4, mpsLog - minLog + l2)
	return totalAmount, val1
end

function module.percent(val1: any, val2: any): string
	val1, val2 = module.ensure(val1), module.ensure(val2)
	local s1, l1 = buffer.readi8(val1, 0), buffer.readf64(val1, 4)
	local s2, l2 = buffer.readi8(val2, 0), buffer.readf64(val2, 4)
	if s1 == -2 or s2 == -2 or s2 == 0 then
		return "NaN%"
	elseif s1 == 0 then
		return "0%"
	end
	local sign = s1 / s2
	local log = l1 - l2 + 2
	if log >= 6 then
		local exp = math.floor(log)
		local man = 10^(log - exp)
		man = math.floor(man * 100 + 0.001) / 100
		return (sign < 0 and "-" or "") .. module.format(man..'e'..exp)
	end
	if log <= -4 then
		local invLog = -log
		local exp = math.floor(invLog)
		local man = 10^(invLog - exp)
		man = math.floor(man * 100 + 0.001) / 100
		return (sign < 0 and "-" or "") .. "1/".. module.format(man..'e'..exp)..'%'
	end
	local val = sign * 10^log
	val = math.floor(val * 100 + 0.001) / 100
	return tostring(val) .. "%"
end

type ScaleMode = 'linear'|'exp'|'sigmoid'

function expm1(x)
	if math.abs(x) < 1e-5 then
		return x + 0.5 * x * x
	end
	return math.exp(x) - 1
end

function module.scaleCurve(val1: any, base: any, exp: any, mode: ScaleMode): buffer
	val1, base, exp = module.ensure(val1), module.ensure(base), module.ensure(exp)
	local s1, l1 = buffer.readi8(val1, 0), buffer.readf64(val1, 4)
	local s2, l2 = buffer.readi8(base, 0), buffer.readf64(base, 4)
	local s3, l3 = buffer.readi8(exp, 0),  buffer.readf64(exp, 4)
	if l1 <= l2 then
		buffer.writei8(val1, 0, 1)
		buffer.writef64(val1, 4, 0)
		return val1
	end
	local diffLog
	local delta = (l2-l1)
	if l1 - l2 > 16 then
		diffLog = l1
	else
		local stable = -expm1(delta*2.302585092994046)
		diffLog = l1+math.log10(stable)
	end
	local tLog = diffLog - l2
	if mode == "linear" then
		if tLog > 16 then
			buffer.writei8(val1, 0, 1)
			buffer.writef64(val1, 4, tLog)
		else
			buffer.writei8(val1, 0, 1)
			buffer.writef64(val1, 4, math.log10(10^tLog + 1))
		end
		return val1
	end
	if mode == "exp" then
		local exVal = s3 * 10^l3
		local powLog = tLog * exVal
		if powLog > 16 then
			buffer.writei8(val1, 0, 1)
			buffer.writef64(val1, 4, powLog)
		else
			buffer.writei8(val1, 0, 1)
			buffer.writef64(val1, 4, math.log10(10^powLog + 1))
		end
		return val1
	end
	if mode == "sigmoid" then
		if tLog > 2 then
			buffer.writei8(val1, 0, 1)
			buffer.writef64(val1, 4, tLog)
			return val1
		end
		local t = 10^tLog
		local sig = 1 / (1 + math.exp(-t))
		local result = t * sig
		buffer.writei8(val1, 0, 1)
		buffer.writef64(val1, 4, math.log10(result))
		return val1
	end

	local exVal = s3 * 10^l3
	local powLog = tLog * exVal
	if powLog > 16 then
		buffer.writei8(val1, 0, 1)
		buffer.writef64(val1, 4, powLog)
	else
		buffer.writei8(val1, 0, 1)
		buffer.writef64(val1, 4, math.log10(10^powLog + 1))
	end
	return val1
end

function module.progress(val1: any, goal: any, modes: ScaleMode)
	val1, goal = module.ensure(val1), module.ensure(goal)
	local s1, l1 = buffer.readi8(val1, 0), buffer.readf64(val1, 4)
	local s2, l2 = buffer.readi8(goal, 0), buffer.readf64(goal, 4)
	if l2 <= 0 then
		buffer.writei8(val1, 0, 1)
		buffer.writef64(val1, 4, 0)
		return val1
	end
	local ratio
	if s1 == 0 then
		ratio = 0
	else
		ratio = s1 / s2 * 10^(l1 - l2)
	end
	if ratio < 0 then ratio = 0 elseif ratio > 1 then ratio = 1 end
	local scale
	modes = modes or 'linear'
	if modes == 'linear' then
		scale = ratio ^1.1
	elseif modes == 'exp' then
		scale = ratio ^2
	elseif modes == 'sigmoid' then
		scale = 1/(1+math.exp(-6*(ratio-0.5)))
	else
		scale = ratio
	end
	if scale == 0 then
		buffer.copy(val1, 0, ZERO,0 ,12)
	else
		buffer.writei8(val1, 0, 1)
		buffer.writef64(val1, 4, math.log10(math.abs(scale)))
	end
	return val1
end

function module.imod(val1: any, val2: any): buffer
	val1, val2 = module.ensure(val1), module.ensure(val2)
	local s1, l1 = buffer.readi8(val1, 0), buffer.readf64(val1, 4)
	local s2, l2 = buffer.readi8(val2, 0), buffer.readf64(val2, 4)
	if s2 == 0 then
		buffer.copy(val1, 0, NAN, 0, 12)
		return val1
	end
	if l1 < l2 or (l1 == l2 and s1 < s2) then
		return val1
	end
	local diff = l1-l2
	local div = math.floor(10^diff*(s1/s2)+0.001)
	if div == 0 then return val1 end
	local fact = div*s2/s1*10^(l2-l1)
	local rems, remlog
	if fact >= 1 then
		buffer.copy(val1, 0, ZERO, 0, 12)
		return val1
	else
		rems = s1
		remlog = l1+math.log10(1-fact)
		buffer.writei8(val1, 0, rems)
		buffer.writef64(val1, 4, remlog)
	end
	return val1
end

function module.intdiv(val1: any, val2: any): buffer
	val1, val2 = module.ensure(val1), module.ensure(val2)
	local sign1, log1 = buffer.readi8(val1, 0), buffer.readf64(val1, 4)
	local sign2, log2 = buffer.readi8(val2, 0), buffer.readf64(val2, 4)
	if sign1 == -2 or sign2 == -2 then
		buffer.copy(val1, 0, NAN, 0, 12)
		return val1
	end
	if sign1 == 0 or sign2 == 0 then
		buffer.copy(val1, 0, ZERO, 0, 12)
		return val1
	end
	local sign = sign1/sign2
	local log = log1-log2
	if log < 0 then
		buffer.copy(val1, 0, ZERO, 0, 12)
		return val1
	end
	if log >= 16 then
		buffer.writei8(val1, 0, sign)
		buffer.writef64(val1, 4, log)
		return val1
	end
	local diff = 10^log
	if sign == -1 then
		diff = -diff
		diff = math.floor(diff)
	else
		diff = math.floor(diff)
	end
	if diff == 0 then
		buffer.copy(val1, 0, ZERO, 0, 12)
		return val1
	end
	buffer.writei8(val1, 0, math.sign(diff))
	buffer.writef64(val1, 4, math.log10(math.abs(diff)))
	return val1
end

return module
