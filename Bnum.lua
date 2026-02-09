--!optimize 2
--!native
local first = {'k', 'm', 'b'}
local firstset = {"U","D","T","Qd","Qn","Sx","Sp","Oc","No"}
local second = {"", "De","Vt","Tg","qg","Qg","sg","Sg","Og","Ng"}
local third = {"", "Ce","Du","Tr","Qa","Qi","Se","Si","Ot","Ni"}
local BN = {}

local log10 = math.log10
local abs = math.abs

-- constants
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

-- testing dont use only works on format
function BN.new(man: number, exp: number): buffer
	local out = buffer.create(12)
	if man == 0 then
		buffer.copy(out, 0, ZERO, 0, 12)
		return out
	end
	buffer.writei8(out, 0, man>0 and 1 or -1)
	buffer.writef64(out, 4, math.log10(man)+exp)
	return out
end

function BN.toStr(val: any): string
	local buff
	if type(val) == "buffer" then
		buff = val
	else
		buff = buffer.create(12)
		local n
		if type(val) == "string" then
			local s = val:lower()
			if s == "inf" then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff, 0, ZERO, 0, 12)
					else
						local sign = man > 0 and 1 or -1
						buffer.writei8(buff, 0, sign)
						buffer.writef64(buff, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val) == "number" then
			n = val
		else
			buffer.copy(buff, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				buffer.writei8(buff, 0, n > 0 and 1 or -1)
				buffer.writef64(buff, 4, log10(abs(n)))
			end
		end
	end
	local sign = buffer.readi8(buff, 0)
	local logVal = buffer.readf64(buff, 4)
	if sign == 0 then return "0e0" end
	if sign == -2 then return "NaN" end
	if logVal == 1/0 then return "inf" end
	local exp = logVal//1
	local man = 10^(logVal - exp)
	if sign == -1 then man = -man end
	return man .. "e" .. exp
end

function BN.fromNumber(val: number): buffer
	local out = buffer.create(12)
	if type(val) ~= 'number' then
		buffer.copy(out, 0, NAN, 0, 12)
		return out
	elseif val == 0 then
		buffer.copy(out, 0, ZERO, 0, 12)
		return out
	elseif val ~= val then		
		buffer.copy(out, 0, NAN, 0, 12)
	end
	buffer.writei8(out, 0, val>0 and 1 or -1)
	buffer.writef64(out, 4, math.log10(val>= 0 and val or -val))
	return out
end

function BN.toNumber(val: any): number
	local buff
	if type(val) == "buffer" then
		buff = val
	else
		buff = buffer.create(12)
		local n
		if type(val) == "string" then
			local s = val:lower()
			if s == "inf" then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff, 0, ZERO, 0, 12)
					else
						local sign = man > 0 and 1 or -1
						buffer.writei8(buff, 0, sign)
						buffer.writef64(buff, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		end
		if n then
			if n ~= n then
				buffer.copy(buff, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				buffer.writei8(buff, 0, n > 0 and 1 or -1)
				buffer.writef64(buff, 4, log10(abs(n)))
			end
		end
	end
	local sign, log = buffer.readi8(buff, 0), buffer.readf64(buff, 4)
	local num = sign * (10^log)
	if num < 2^52 then
		return ((num*100+0.001)/100)//1
	end
	return num
end

function BN.add(val1: any, val2: any): buffer
	local buff1
	if type(val1) == "buffer" then
		buff1 = val1
	else
		buff1 = buffer.create(12)
		local n
		if type(val1) == "string" then
			local s = val1:lower()
			if s == "inf" then
				buffer.copy(buff1, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff1, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff1, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff1, 0, man > 0 and 1 or -1)
						buffer.writef64(buff1, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val1) == "number" then
			n = val1
		else
			buffer.copy(buff1, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff1, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff1, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff1, 0, INF, 0, 12)
			else
				buffer.writei8(buff1, 0, n > 0 and 1 or -1)
				buffer.writef64(buff1, 4, log10(abs(n)))
			end
		end
	end
	local buff2
	if type(val2) == "buffer" then
		buff2 = val2
	else
		buff2 = buffer.create(12)
		local n
		if type(val2) == "string" then
			local s = val2:lower()
			if s == "inf" then
				buffer.copy(buff2, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff2, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff2, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff2, 0, man > 0 and 1 or -1)
						buffer.writef64(buff2, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val2) == "number" then
			n = val2
		else
			buffer.copy(buff2, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff2, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff2, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff2, 0, INF, 0, 12)
			else
				buffer.writei8(buff2, 0, n > 0 and 1 or -1)
				buffer.writef64(buff2, 4, log10(abs(n)))
			end
		end
	end
	local sign1, exp1 = buffer.readi8(buff1, 0), buffer.readf64(buff1, 4)
	local sign2, exp2 = buffer.readi8(buff2, 0), buffer.readf64(buff2, 4)
	if sign1 == -2 or sign2 == -2 then
		local out = buffer.create(12)
		buffer.copy(out, 0, NAN, 0, 12)
		return out
	end
	if sign1 == 0 then return buff2 elseif sign2 == 0 then return buff1 end
	local diff = exp1 - exp2
	if diff > 16 then return buff1 elseif diff < -16 then return buff2 end
	if diff == 0 and sign1 ~= sign2 then
		local out = buffer.create(12)
		buffer.copy(out, 0, ZERO, 0, 12)
		return out
	end
	local out = buffer.create(12)
	if sign1 == sign2 then
		buffer.writei8(out, 0, sign1)
		buffer.writef64(out, 4, log10(10^(diff) + 1) + exp2)
	end
	if diff >= 0 then
		buffer.writei8(out, 0, sign1)
		buffer.writef64(out, 4, exp1 + log10(1 - 10^(-diff)))
	end
	buffer.writei8(out, 0, sign2)
	buffer.writef64(out, 4, exp2 + log10(1 - 10^(diff)))
	return out
end

function BN.sub(val1: any, val2: any): buffer
	local buff1
	if type(val1) == "buffer" then
		buff1 = val1
	else
		buff1 = buffer.create(12)
		local n
		if type(val1) == "string" then
			local s = val1:lower()
			if s == "inf" then
				buffer.copy(buff1, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff1, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff1, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff1, 0, man > 0 and 1 or -1)
						buffer.writef64(buff1, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val1) == "number" then
			n = val1
		else
			buffer.copy(buff1, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff1, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff1, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff1, 0, INF, 0, 12)
			else
				buffer.writei8(buff1, 0, n > 0 and 1 or -1)
				buffer.writef64(buff1, 4, log10(abs(n)))
			end
		end
	end
	local buff2
	if type(val2) == "buffer" then
		buff2 = buffer.create(12)
		local sign2 = buffer.readi8(val2, 0)
		local log2  = buffer.readf64(val2, 4)
		buffer.writei8(buff2, 0, -sign2)
		buffer.writef64(buff2, 4, log2)
	else
		buff2 = buffer.create(12)
		local n
		if type(val2) == "string" then
			local s = val2:lower()
			if s == "inf" then
				buffer.copy(buff2, 0, INF, 0, 12)
				buffer.writei8(buff2, 0, -1)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff2, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff2, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff2, 0, man > 0 and -1 or 1)
						buffer.writef64(buff2, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val2) == "number" then
			n = val2
		else
			buffer.copy(buff2, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff2, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff2, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff2, 0, INF, 0, 12)
				buffer.writei8(buff2, 0, -1)
			else
				buffer.writei8(buff2, 0, n > 0 and -1 or 1)
				buffer.writef64(buff2, 4, log10(abs(n)))
			end
		end
	end
	local sign1 = buffer.readi8(buff1, 0)
	local exp1  = buffer.readf64(buff1, 4)
	local sign2 = buffer.readi8(buff2, 0)
	local exp2  = buffer.readf64(buff2, 4)
	if sign1 == -2 or sign2 == -2 then
		local out = buffer.create(12)
		buffer.copy(out, 0, NAN, 0, 12)
		return out
	end
	if sign1 == 0 then return buff2 end
	if sign2 == 0 then return buff1 end
	local diff = exp1 - exp2
	if diff > 16 then return buff1 end
	if diff < -16 then return buff2 end
	if diff == 0 and sign1 ~= sign2 then
		local out = buffer.create(12)
		buffer.copy(out, 0, ZERO, 0, 12)
		return out
	end
	local out = buffer.create(12)
	if sign1 == sign2 then
		buffer.writei8(out, 0, sign1)
		buffer.writef64(out, 4, log10(10^(diff) + 1) + exp2)
	else
		if diff >= 0 then
			buffer.writei8(out, 0, sign1)
			buffer.writef64(out, 4, exp1 + log10(1 - 10^(-diff)))
		else
			buffer.writei8(out, 0, sign2)
			buffer.writef64(out, 4, exp2 + log10(1 - 10^(diff)))
		end
	end
	return out
end

function BN.mul(val1: any, val2: any): buffer
	local buff1
	if type(val1) == "buffer" then
		buff1 = val1
	else
		buff1 = buffer.create(12)
		local n
		if type(val1) == "string" then
			local s = val1:lower()
			if s == "inf" then
				buffer.copy(buff1, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff1, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff1, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff1, 0, man > 0 and 1 or -1)
						buffer.writef64(buff1, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val1) == "number" then
			n = val1
		else
			buffer.copy(buff1, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff1, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff1, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff1, 0, INF, 0, 12)
			else
				buffer.writei8(buff1, 0, n > 0 and 1 or -1)
				buffer.writef64(buff1, 4, log10(abs(n)))
			end
		end
	end
	local buff2
	if type(val2) == "buffer" then
		buff2 = val2
	else
		buff2 = buffer.create(12)
		local n
		if type(val2) == "string" then
			local s = val2:lower()
			if s == "inf" then
				buffer.copy(buff2, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff2, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff2, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff2, 0, man > 0 and 1 or -1)
						buffer.writef64(buff2, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val2) == "number" then
			n = val2
		else
			buffer.copy(buff2, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff2, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff2, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff2, 0, INF, 0, 12)
			else
				buffer.writei8(buff2, 0, n > 0 and 1 or -1)
				buffer.writef64(buff2, 4, log10(abs(n)))
			end
		end
	end
	local sign1 = buffer.readi8(buff1, 0)
	local sign2 = buffer.readi8(buff2, 0)
	if sign1 == -2 or sign2 == -2 then
		buffer.copy(buffer.create(12), 0, NAN, 0, 12)
	end
	if sign1 == 0 or sign2 == 0 then
		buffer.copy(buffer.create(12), 0, ZERO, 0, 12)
	end
	local out = buffer.create(12)
	buffer.writei8(out, 0, sign1*sign2)
	buffer.writef64(out, 4, buffer.readf64(buff1, 4) + buffer.readf64(buff2, 4))
	return out
end

function BN.div(val1: any, val2: any): buffer
	local buff1
	if type(val1) == "buffer" then
		buff1 = val1
	else
		buff1 = buffer.create(12)
		local n
		if type(val1) == "string" then
			local s = val1:lower()
			if s == "inf" then
				buffer.copy(buff1, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff1, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff1, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff1, 0, man > 0 and 1 or -1)
						buffer.writef64(buff1, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val1) == "number" then
			n = val1
		else
			buffer.copy(buff1, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff1, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff1, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff1, 0, INF, 0, 12)
			else
				buffer.writei8(buff1, 0, n > 0 and 1 or -1)
				buffer.writef64(buff1, 4, log10(abs(n)))
			end
		end
	end
	local buff2
	if type(val2) == "buffer" then
		buff2 = val2
	else
		buff2 = buffer.create(12)
		local n
		if type(val2) == "string" then
			local s = val2:lower()
			if s == "inf" then
				buffer.copy(buff2, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff2, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff2, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff2, 0, man > 0 and 1 or -1)
						buffer.writef64(buff2, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val2) == "number" then
			n = val2
		else
			buffer.copy(buff2, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff2, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff2, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff2, 0, INF, 0, 12)
			else
				buffer.writei8(buff2, 0, n > 0 and 1 or -1)
				buffer.writef64(buff2, 4, log10(abs(n)))
			end
		end
	end
	local sign1 = buffer.readi8(buff1, 0)
	local sign2 = buffer.readi8(buff2, 0)
	if sign1 == -2 or sign2 == -2 then
		buffer.copy(buffer.create(12), 0, NAN, 0, 12)
	end
	if sign1 == 0 or sign2 == 0 then
		buffer.copy(buffer.create(12), 0, ZERO, 0, 12)
	end
	local out = buffer.create(12)
	buffer.writei8(out, 0, sign1*sign2)
	buffer.writef64(out, 4, buffer.readf64(buff1, 4) - buffer.readf64(buff2, 4))
	return out
end

function BN.intdiv(val1: any, val2: any): buffer
	return BN.floor(BN.div(val1, val2))
end

function BN.isFloat(val: any)
	return buffer.readf64(val, 4) <= 308.2304489213783 and math.abs(buffer.readi8(val, 0)) <= 1
end

function BN.pow(val1: any, val2: any): buffer
	local buff1
	if type(val1) == "buffer" then
		buff1 = val1
	else
		buff1 = buffer.create(12)
		local n
		if type(val1) == "string" then
			local s = val1:lower()
			if s == "inf" then
				buffer.copy(buff1, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff1, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff1, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff1, 0, man > 0 and 1 or -1)
						buffer.writef64(buff1, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val1) == "number" then
			n = val1
		else
			buffer.copy(buff1, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff1, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff1, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff1, 0, INF, 0, 12)
			else
				buffer.writei8(buff1, 0, n > 0 and 1 or -1)
				buffer.writef64(buff1, 4, log10(abs(n)))
			end
		end
	end
	local buff2
	if type(val2) == "buffer" then
		buff2 = val2
	else
		buff2 = buffer.create(12)
		local n
		if type(val2) == "string" then
			local s = val2:lower()
			if s == "inf" then
				buffer.copy(buff2, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff2, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff2, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff2, 0, man > 0 and 1 or -1)
						buffer.writef64(buff2, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val2) == "number" then
			n = val2
		else
			buffer.copy(buff2, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff2, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff2, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff2, 0, INF, 0, 12)
			else
				buffer.writei8(buff2, 0, n > 0 and 1 or -1)
				buffer.writef64(buff2, 4, log10(abs(n)))
			end
		end
	end
	local sign1, log1 = buffer.readi8(buff1, 0), buffer.readf64(buff1, 4)
	local sign2, log2 = buffer.readi8(buff2, 0), buffer.readf64(buff2, 4)
	local out = buffer.create(12)
	if sign1 == -2 or sign2 == -2 then
		buffer.copy(out, 0, NAN, 0, 12)
		return out
	end
	if sign1 == 0 then
		if sign2 == 0 then
			buffer.writei8(out, 0, 1)
			buffer.writef64(out, 4, 0)
			return out
		else
			buffer.copy(out, 0, ZERO, 0, 12)
			return out
		end
	end
	if sign2 == 0 then
		buffer.writei8(out, 0, 1)
		buffer.writef64(out, 4, 0)
		return out
	end
	local numericExponent = 10^log2 * sign2
	if sign1 == -1 then
		if numericExponent % 1 ~= 0 then
			buffer.copy(out, 0, NAN, 0, 12)
			return out
		end
		buffer.writei8(out, 0, (numericExponent % 2 == 1) and -1 or 1)
	else
		buffer.writei8(out, 0, 1)
	end
	buffer.writef64(out, 4, log1 * numericExponent)
	return out
end

function BN.pow10(val: any): buffer
	local buff
	if type(val) == "buffer" then
		buff = val
	else
		buff = buffer.create(12)
		local n
		if type(val) == "string" then
			local s = val:lower()
			if s == "inf" then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff, 0, ZERO, 0, 12)
					else
						local sign = man > 0 and 1 or -1
						buffer.writei8(buff, 0, sign)
						buffer.writef64(buff, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val) == "number" then
			n = val
		else
			buffer.copy(buff, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				buffer.writei8(buff, 0, n > 0 and 1 or -1)
				buffer.writef64(buff, 4, log10(abs(n)))
			end
		end
	end
	local sign, log = buffer.readi8(buff, 0), buffer.readf64(buff, 4)
	local out = buffer.create(12)
	if sign == -2 then
		buffer.copy(out, 0, NAN, 0, 12)
		return out
	end
	if sign == 0 then
		buffer.copy(out, 0, ZERO, 0, 12)
		return out
	elseif log == 1/0 then
		buffer.copy(out, 0, INF, 0, 12)
		return out
	end
	buffer.writei8(out, 0, 1)
	buffer.writef64(out, 4, sign*10^log)
	return out
end

function BN.sqrt(val: any): buffer
	local buff
	if type(val) == "buffer" then
		buff = val
	else
		buff = buffer.create(12)
		local n
		if type(val) == "string" then
			local s = val:lower()
			if s == "inf" then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff, 0, ZERO, 0, 12)
					else
						local sign = man > 0 and 1 or -1
						buffer.writei8(buff, 0, sign)
						buffer.writef64(buff, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val) == "number" then
			n = val
		else
			buffer.copy(buff, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				buffer.writei8(buff, 0, n > 0 and 1 or -1)
				buffer.writef64(buff, 4, log10(abs(n)))
			end
		end
	end
	local sign, log = buffer.readi8(buff, 0), buffer.readf64(buff, 4)
	local out = buffer.create(12)
	if sign < 0 then
		buffer.copy(out, 0, NAN, 0, 12)
		return out
	elseif sign == 0 then
		buffer.copy(out, 0, ZERO, 0, 12)
		return out
	end
	buffer.writei8(out, 0, 1)
	buffer.writef64(out, 4, 0.5*log)
	return out
end

function BN.root(val1: any, val2: any): buffer
	local buff1
	if type(val1) == "buffer" then
		buff1 = val1
	else
		buff1 = buffer.create(12)
		local n
		if type(val1) == "string" then
			local s = val1:lower()
			if s == "inf" then
				buffer.copy(buff1, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff1, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff1, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff1, 0, man > 0 and 1 or -1)
						buffer.writef64(buff1, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val1) == "number" then
			n = val1
		else
			buffer.copy(buff1, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff1, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff1, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff1, 0, INF, 0, 12)
			else
				buffer.writei8(buff1, 0, n > 0 and 1 or -1)
				buffer.writef64(buff1, 4, log10(abs(n)))
			end
		end
	end
	local buff2
	if type(val2) == "buffer" then
		buff2 = val2
	else
		buff2 = buffer.create(12)
		local n
		if type(val2) == "string" then
			local s = val2:lower()
			if s == "inf" then
				buffer.copy(buff2, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff2, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff2, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff2, 0, man > 0 and 1 or -1)
						buffer.writef64(buff2, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val2) == "number" then
			n = val2
		else
			buffer.copy(buff2, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff2, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff2, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff2, 0, INF, 0, 12)
			else
				buffer.writei8(buff2, 0, n > 0 and 1 or -1)
				buffer.writef64(buff2, 4, log10(abs(n)))
			end
		end
	end
	local out = buffer.create(12)
	local sign1, log1 = buffer.readi8(buff1, 0), buffer.readf64(buff1, 4)
	local sign2, log2 = buffer.readi8(buff2, 0), buffer.readf64(buff2, 4)
	if sign1 == -2 then
		buffer.copy(out, 0, NAN,0, 12)
		return out
	end
	if sign2 == 0 or sign1 < 0 then
		buffer.copy(out, 0, NAN, 0, 12)
		return out
	elseif sign1 == 0 then
		buffer.copy(out, 0, ZERO, 0, 12)
		return out
	end
	buffer.writei8(out, 0, 1)
	buffer.writef64(out,4,  1/(sign2*10^log2) * log1)
	return out 
end

function BN.cmp(val1: any, val2: any): number
	local buff1
	if type(val1) == "buffer" then
		buff1 = val1
	else
		buff1 = buffer.create(12)
		local n
		if type(val1) == "string" then
			local s = val1:lower()
			if s == "inf" then
				buffer.copy(buff1, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff1, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff1, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff1, 0, man > 0 and 1 or -1)
						buffer.writef64(buff1, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val1) == "number" then
			n = val1
		else
			buffer.copy(buff1, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff1, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff1, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff1, 0, INF, 0, 12)
			else
				buffer.writei8(buff1, 0, n > 0 and 1 or -1)
				buffer.writef64(buff1, 4, log10(abs(n)))
			end
		end
	end
	local buff2
	if type(val2) == "buffer" then
		buff2 = val2
	else
		buff2 = buffer.create(12)
		local n
		if type(val2) == "string" then
			local s = val2:lower()
			if s == "inf" then
				buffer.copy(buff2, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff2, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff2, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff2, 0, man > 0 and 1 or -1)
						buffer.writef64(buff2, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val2) == "number" then
			n = val2
		else
			buffer.copy(buff2, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff2, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff2, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff2, 0, INF, 0, 12)
			else
				buffer.writei8(buff2, 0, n > 0 and 1 or -1)
				buffer.writef64(buff2, 4, log10(abs(n)))
			end
		end
	end
	local sign1, sign2 = buffer.readi8(buff1, 0), buffer.readi8(buff2, 0)
	local log1, log2 = buffer.readi8(buff1, 4), buffer.readi8(buff2, 4)
	if sign1 ~= log2 then
		return if sign1 > sign2 then 1 else -1
	end
	return if
		log1 > log2 then
		sign1
		elseif log1 < log2 then
		-1 * sign1
		else
		(sign1 ~= -2) and 0 or -1
end

function BN.eq(val1: any, val2: any): boolean
	return BN.cmp(val1, val2) == 0
end

function BN.le(val1: any, val2: any): boolean
	return BN.cmp(val1, val2) == -1
end

function BN.me(val1: any, val2: any): boolean
	return BN.cmp(val1, val2) == 1
end

function BN.leeq(val1: any, val2: any): boolean
	return BN.cmp(val1, val2) ~= 1
end

function BN.meeq(val1: any, val2: any): boolean
	return BN.cmp(val1, val2) ~= -1
end

function BN.log10(val: any): buffer
	local buff
	if type(val) == "buffer" then
		buff = val
	else
		buff = buffer.create(12)
		local n
		if type(val) == "string" then
			local s = val:lower()
			if s == "inf" then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff, 0, ZERO, 0, 12)
					else
						local sign = man > 0 and 1 or -1
						buffer.writei8(buff, 0, sign)
						buffer.writef64(buff, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val) == "number" then
			n = val
		else
			buffer.copy(buff, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				buffer.writei8(buff, 0, n > 0 and 1 or -1)
				buffer.writef64(buff, 4, log10(abs(n)))
			end
		end
	end
	local sign, log = buffer.readi8(buff, 0), buffer.readf64(buff, 4)
	local out = buffer.create(12)
	if sign ~= 1 then
		buffer.copy(out, 0, NAN, 0, 12)
		return out
	end
	buffer.writei8(out, 0, math.sign(log))
	buffer.writef64(out, 4, math.log10(log))
	return out
end

function BN.log(val1: any, val2: any): buffer
	local buff1
	if type(val1) == "buffer" then
		buff1 = val1
	else
		buff1 = buffer.create(12)
		local n
		if type(val1) == "string" then
			local s = val1:lower()
			if s == "inf" then
				buffer.copy(buff1, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff1, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff1, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff1, 0, man > 0 and 1 or -1)
						buffer.writef64(buff1, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val1) == "number" then
			n = val1
		else
			buffer.copy(buff1, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff1, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff1, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff1, 0, INF, 0, 12)
			else
				buffer.writei8(buff1, 0, n > 0 and 1 or -1)
				buffer.writef64(buff1, 4, log10(abs(n)))
			end
		end
	end
	local out = buffer.create(12)
	local sign1, log1 = buffer.readi8(buff1, 0), buffer.readf64(buff1, 4)
	if not val2 then
		if log1 == 0 then
			buffer.copy(out, 0, ZERO, 0, 12)
			return out
		end
		local v = log1/0.4342944819032518
		buffer.writei8(out, 0, math.sign(log1))
		buffer.writef64(out, 4, math.log10(math.abs(v)))
		return out
	else
		local buff2
		if type(val2) == "buffer" then
			buff2 = val2
		else
			buff2 = buffer.create(12)
			local n
			if type(val2) == "string" then
				local s = val2:lower()
				if s == "inf" then
					buffer.copy(buff2, 0, INF, 0, 12)
				else
					local ePos = string.find(s, "e", 1, true)
					if ePos then
						local man = tonumber(string.sub(s, 1, ePos-1))
						local exp = tonumber(string.sub(s, ePos+1))
						if not man or not exp or man ~= man then
							buffer.copy(buff2, 0, NAN, 0, 12)
						elseif man == 0 then
							buffer.copy(buff2, 0, ZERO, 0, 12)
						else
							buffer.writei8(buff2, 0, man > 0 and 1 or -1)
							buffer.writef64(buff2, 4, log10(abs(man)) + exp)
						end
					else
						n = tonumber(s)
					end
				end
			elseif type(val2) == "number" then
				n = val2
			else
				buffer.copy(buff2, 0, NAN, 0, 12)
			end
			if n then
				if n ~= n then
					buffer.copy(buff2, 0, NAN, 0, 12)
				elseif n == 0 then
					buffer.copy(buff2, 0, ZERO, 0, 12)
				elseif n == 1/0 or n == -1/0 then
					buffer.copy(buff2, 0, INF, 0, 12)
				else
					buffer.writei8(buff2, 0, n > 0 and 1 or -1)
					buffer.writef64(buff2, 4, log10(abs(n)))
				end
			end
		end
		local sign2, log2 = buffer.readi8(buff2, 0), buffer.readf64(buff2, 4)
		if sign1 <= 0 or sign2 <= 0 or log2 == 0 then
			buffer.copy(out, 0, NAN, 0, 12)
			return out
		end
		local v = log1 / log2
		if v == 0 then
			buffer.copy(out, 0, ZERO, 0, 12)
			return out
		end
		buffer.writei8(out, 0, v > 0 and 1 or -1)
		buffer.writef64(out, 4, math.log10(math.abs(v)))
		return out
	end
end

function BN.exp(val: any): buffer
	local buff
	if type(val) == "buffer" then
		buff = val
	else
		buff = buffer.create(12)
		local n
		if type(val) == "string" then
			local s = val:lower()
			if s == "inf" then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff, 0, ZERO, 0, 12)
					else
						local sign = man > 0 and 1 or -1
						buffer.writei8(buff, 0, sign)
						buffer.writef64(buff, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val) == "number" then
			n = val
		else
			buffer.copy(buff, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				buffer.writei8(buff, 0, n > 0 and 1 or -1)
				buffer.writef64(buff, 4, log10(abs(n)))
			end
		end
	end
	local sign, log = buffer.readi8(buff, 0), buffer.readf64(buff, 4)
	local out = buffer.create(12)
	if sign == -2 then
		buffer.copy(out, 0, NAN, 0, 12)
		return out
	end
	buffer.writei8(out, 0, 1)
	buffer.writef64(out, 4,  0.4342944819032518 * 10^log * sign)
	return out
end

function BN.random(val1: any, val2: any): buffer
	local buff1
	if type(val1) == "buffer" then
		buff1 = val1
	else
		buff1 = buffer.create(12)
		local n
		if type(val1) == "string" then
			local s = val1:lower()
			if s == "inf" then
				buffer.copy(buff1, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff1, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff1, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff1, 0, man > 0 and 1 or -1)
						buffer.writef64(buff1, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val1) == "number" then
			n = val1
		else
			buffer.copy(buff1, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff1, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff1, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff1, 0, INF, 0, 12)
			else
				buffer.writei8(buff1, 0, n > 0 and 1 or -1)
				buffer.writef64(buff1, 4, log10(abs(n)))
			end
		end
	end
	local buff2
	if type(val2) == "buffer" then
		buff2 = val2
	else
		buff2 = buffer.create(12)
		local n
		if type(val2) == "string" then
			local s = val2:lower()
			if s == "inf" then
				buffer.copy(buff2, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff2, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff2, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff2, 0, man > 0 and 1 or -1)
						buffer.writef64(buff2, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val2) == "number" then
			n = val2
		else
			buffer.copy(buff2, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff2, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff2, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff2, 0, INF, 0, 12)
			else
				buffer.writei8(buff2, 0, n > 0 and 1 or -1)
				buffer.writef64(buff2, 4, log10(abs(n)))
			end
		end
	end
	local sign1, sign2 = buffer.readi8(buff1, 0), buffer.readi8(buff2, 0)
	local log1, log2 = buffer.readi8(buff1, 4), buffer.readi8(buff2, 4)
	local out = buffer.create(12)
	if sign1 == -2 or sign2 == -2 then
		buffer.copy(out, 0, NAN, 0, 12)
		return out
	end
	return BN.add(BN.mul(BN.sub(val2, val1), math.random()), val1)
end

function BN.min(...: any): buffer
	local out = nil
	local n = select('#', ...)
	for i = 1, n do
		local val = select(i, ...)
		local buff
		if type(val) == "buffer" then
			buff = val
		else
			buff = buffer.create(12)
			local n
			if type(val) == "string" then
				local s = val:lower()
				if s == "inf" then
					buffer.copy(buff, 0, INF, 0, 12)
				else
					local ePos = string.find(s, "e", 1, true)
					if ePos then
						local man = tonumber(string.sub(s, 1, ePos-1))
						local exp = tonumber(string.sub(s, ePos+1))
						if not man or not exp or man ~= man then
							buffer.copy(buff, 0, NAN, 0, 12)
						elseif man == 0 then
							buffer.copy(buff, 0, ZERO, 0, 12)
						else
							local sign = man > 0 and 1 or -1
							buffer.writei8(buff, 0, sign)
							buffer.writef64(buff, 4, log10(abs(man)) + exp)
						end
					else
						n = tonumber(s)
					end
				end
			elseif type(val) == "number" then
				n = val
			else
				buffer.copy(buff, 0, NAN, 0, 12)
			end
			if n then
				if n ~= n then
					buffer.copy(buff, 0, NAN, 0, 12)
				elseif n == 0 then
					buffer.copy(buff, 0, ZERO, 0, 12)
				elseif n == 1/0 or n == -1/0 then
					buffer.copy(buff, 0, INF, 0, 12)
				else
					buffer.writei8(buff, 0, n > 0 and 1 or -1)
					buffer.writef64(buff, 4, log10(abs(n)))
				end
			end
		end
		if not out then
			out = buff
		else
			if BN.cmp(buff, out) == -1 then
				out = buff
			end
		end
	end
	return out
end

function BN.max(...: any): buffer
	local out = nil
	local n = select('#', ...)
	for i = 1, n do
		local val = select(i, ...)
		local buff
		if type(val) == "buffer" then
			buff = val
		else
			buff = buffer.create(12)
			local n
			if type(val) == "string" then
				local s = val:lower()
				if s == "inf" then
					buffer.copy(buff, 0, INF, 0, 12)
				else
					local ePos = string.find(s, "e", 1, true)
					if ePos then
						local man = tonumber(string.sub(s, 1, ePos-1))
						local exp = tonumber(string.sub(s, ePos+1))
						if not man or not exp or man ~= man then
							buffer.copy(buff, 0, NAN, 0, 12)
						elseif man == 0 then
							buffer.copy(buff, 0, ZERO, 0, 12)
						else
							local sign = man > 0 and 1 or -1
							buffer.writei8(buff, 0, sign)
							buffer.writef64(buff, 4, log10(abs(man)) + exp)
						end
					else
						n = tonumber(s)
					end
				end
			elseif type(val) == "number" then
				n = val
			else
				buffer.copy(buff, 0, NAN, 0, 12)
			end
			if n then
				if n ~= n then
					buffer.copy(buff, 0, NAN, 0, 12)
				elseif n == 0 then
					buffer.copy(buff, 0, ZERO, 0, 12)
				elseif n == 1/0 or n == -1/0 then
					buffer.copy(buff, 0, INF, 0, 12)
				else
					buffer.writei8(buff, 0, n > 0 and 1 or -1)
					buffer.writef64(buff, 4, log10(abs(n)))
				end
			end
		end
		if not out then
			out = buff
		else
			if BN.cmp(buff, out) == 1 then
				out = buff
			end
		end
	end
	return out
end

function BN.floor(val: any): buffer
	local buff
	if type(val) == "buffer" then
		buff = val
	else
		buff = buffer.create(12)
		local n
		if type(val) == "string" then
			local s = val:lower()
			if s == "inf" then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff, 0, ZERO, 0, 12)
					else
						local sign = man > 0 and 1 or -1
						buffer.writei8(buff, 0, sign)
						buffer.writef64(buff, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val) == "number" then
			n = val
		else
			buffer.copy(buff, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				buffer.writei8(buff, 0, n > 0 and 1 or -1)
				buffer.writef64(buff, 4, log10(abs(n)))
			end
		end
	end
	local sign, log = buffer.readi8(buff, 0), buffer.readf64(buff, 4)
	local out = buffer.create(12)
	if sign == -2 then
		buffer.copy(out, 0, NAN, 0, 12)
		return out
	end
	if sign == 0 or log < 0 then
		buffer.copy(out, 0, ZERO, 0, 12)
		return out
	end
	if log >= 16 then
		buffer.copy(out, 0, buff, 0, 12)
		return out
	end
	if sign == -1 then
		local val = 10^log
		val = (val==val//1) and val or (val//1+1)
		buffer.writei8(out, 0, -1)
		buffer.writef64(out, 4, math.log10(val))
	end
	local val = 10^log
	val = val//1
	buffer.writei8(out, 0, 1)
	buffer.writef64(out, 4, math.log10(val))
	return out
end

function BN.ceil(val: any): buffer
	local buff
	if type(val) == "buffer" then
		buff = val
	else
		buff = buffer.create(12)
		local n
		if type(val) == "string" then
			local s = val:lower()
			if s == "inf" then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff, 0, ZERO, 0, 12)
					else
						local sign = man > 0 and 1 or -1
						buffer.writei8(buff, 0, sign)
						buffer.writef64(buff, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val) == "number" then
			n = val
		else
			buffer.copy(buff, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				buffer.writei8(buff, 0, n > 0 and 1 or -1)
				buffer.writef64(buff, 4, log10(abs(n)))
			end
		end
	end
	local sign, log = buffer.readi8(buff, 0), buffer.readf64(buff, 4)
	local out = buffer.create(12)
	if sign == -2 then
		buffer.copy(out, 0, NAN, 0, 12)
		return out
	end
	if sign == 0 or log < 0 then
		buffer.copy(out, 0, ZERO, 0, 12)
		return out
	end
	if log >= 16 then
		buffer.copy(out, 0, buff, 0, 12)
		return out
	end
	if sign == -1 then
		local val = 10^log
		val = val//1
		buffer.writei8(out, 0, -1)
		buffer.writef64(out, 4, math.log10(val))
		return out
	end
	local val = 10^log
	val = (val==val//1) and val or (val//1+1)
	buffer.writei8(out, 0, 1)
	buffer.writef64(out, 4, math.log10(val))
	return out
end

function BN.round(val: any): buffer
	local buff
	if type(val) == "buffer" then
		buff = val
	else
		buff = buffer.create(12)
		local n
		if type(val) == "string" then
			local s = val:lower()
			if s == "inf" then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff, 0, ZERO, 0, 12)
					else
						local sign = man > 0 and 1 or -1
						buffer.writei8(buff, 0, sign)
						buffer.writef64(buff, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val) == "number" then
			n = val
		else
			buffer.copy(buff, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				buffer.writei8(buff, 0, n > 0 and 1 or -1)
				buffer.writef64(buff, 4, log10(abs(n)))
			end
		end
	end
	local sign, log = buffer.readi8(buff, 0), buffer.readf64(buff, 4)
	local out = buffer.create(12)
	if sign == -2 then
		buffer.copy(out, 0, NAN, 0, 12)
		return out
	end
	if sign == 0 or log < 0 then
		buffer.copy(out, 0, ZERO, 0, 12)
		return out
	end
	if log >= 16 then
		buffer.copy(out, 0, buff, 0, 12)
		return out
	end
	if sign == 0 then
		local val = 10^log
		val = val//1
		buffer.writei8(out, 0, -1)
		buffer.writef64(out, 4, math.log10(val))
		return out
	end
	local val = 10^log
	val = math.round(val)
	buffer.writei8(out, 0, sign)
	buffer.writef64(out, 4, math.log10(val))
	return out
end

function BN.mod(val1: any, val2: any): buffer
	local buff1
	if type(val1) == "buffer" then
		buff1 = val1
	else
		buff1 = buffer.create(12)
		local n
		if type(val1) == "string" then
			local s = val1:lower()
			if s == "inf" then
				buffer.copy(buff1, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff1, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff1, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff1, 0, man > 0 and 1 or -1)
						buffer.writef64(buff1, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val1) == "number" then
			n = val1
		else
			buffer.copy(buff1, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff1, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff1, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff1, 0, INF, 0, 12)
			else
				buffer.writei8(buff1, 0, n > 0 and 1 or -1)
				buffer.writef64(buff1, 4, log10(abs(n)))
			end
		end
	end
	local buff2
	if type(val2) == "buffer" then
		buff2 = val2
	else
		buff2 = buffer.create(12)
		local n
		if type(val2) == "string" then
			local s = val2:lower()
			if s == "inf" then
				buffer.copy(buff2, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff2, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff2, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff2, 0, man > 0 and 1 or -1)
						buffer.writef64(buff2, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val2) == "number" then
			n = val2
		else
			buffer.copy(buff2, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff2, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff2, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff2, 0, INF, 0, 12)
			else
				buffer.writei8(buff2, 0, n > 0 and 1 or -1)
				buffer.writef64(buff2, 4, log10(abs(n)))
			end
		end
	end
	local out = buffer.create(12)
	local sign1, log1 = buffer.readi8(buff1, 0), buffer.readf64(buff1, 4)
	local sign2, log2 = buffer.readi8(buff2, 0), buffer.readf64(buff2, 4)
	if sign1 == -2 or sign2 == -2 or sign2 == 0 then
		buffer.copy(out, 0, NAN, 0, 12)
		return out
	end
	if sign1 == 0 then
		buffer.copy(out, 0, ZERO, 0, 12)
		return out
	end
	local divSign = sign1 * sign2
	local divLog = log1-log2
	local floor = (10^divLog)//1
	if floor == 0 then
		buffer.copy(out, 0, buff1, 0, 12)
		return out
	end
	local resSign = 1
	local remLog = math.log10(floor * 10^ log2)
	if remLog > log1 then
		buffer.copy(out, 0, buff1, 0, 12)
		return out
	end
	local rem = log1 + math.log10(1 - 10^(remLog - log1))
	buffer.writei8(out, 0, resSign)
	buffer.writef64(out, 4, rem)
	return out
end

function BN.lbencode(val: any): number
	local buff
	if type(val) == "buffer" then
		buff = val
	else
		buff = buffer.create(12)
		local n
		if type(val) == "string" then
			local s = val:lower()
			if s == "inf" then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff, 0, ZERO, 0, 12)
					else
						local sign = man > 0 and 1 or -1
						buffer.writei8(buff, 0, sign)
						buffer.writef64(buff, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val) == "number" then
			n = val
		else
			buffer.copy(buff, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				buffer.writei8(buff, 0, n > 0 and 1 or -1)
				buffer.writef64(buff, 4, log10(abs(n)))
			end
		end
	end
	local sign, log = buffer.readi8(buff, 0), buffer.readf64(buff, 4)
	if sign == -2 or sign == 0 then
		return 0
	end
	local logAbs
	if log > 16 then
		logAbs = log
	else
		logAbs = log10(10^log+1)
	end
	if logAbs > 1.7976931348623157e308 then
		logAbs = 1.7976931348623157e308
	end
	if logAbs <= 0 then
		return 0
	end
	return (math.log10(logAbs + 1) + 1) * 4503599627370496 * sign
end

function BN.lbdecode(encoded: number): buffer
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
		logVal = log10(10^logPlus - 1)
	end
	buffer.writei8(out, 0, sign)
	buffer.writef64(out, 4, logVal)
	return out
end

function BN.format(val: any, digits: number?, hyperAt: number?): string
	local buff
	if type(val) == "buffer" then
		buff = val
	else
		buff = buffer.create(12)
		local n
		if type(val) == "string" then
			local s = val:lower()
			if s == "inf" then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff, 0, man > 0 and 1 or -1)
						buffer.writef64(buff, 4, math.log10(math.abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val) == "number" then
			n = val
		else
			buffer.copy(buff, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				buffer.writei8(buff, 0, n > 0 and 1 or -1)
				buffer.writef64(buff, 4, math.log10(math.abs(n)))
			end
		end
	end
	digits = digits or 2
	hyperAt = hyperAt or 2e20
	local sign = buffer.readi8(buff, 0)
	local exp  = buffer.readf64(buff, 4)
	if sign == -2 then return "NaN" end
	if sign == 0 then return "0" end
	if exp == math.huge then return sign > 0 and "Inf" or "-Inf" end
	if exp < 3 then
		local scale = 10^exp * sign
		scale = math.floor(scale * 10^digits + 0.001) / 10^digits
		return tostring(scale)
	end
	local rexp = (exp-3)//3
	local rem  = exp % 3
	local man  = 10^rem
	local scaled = man
	scaled = math.floor(scaled * 10^digits +  0.001) / 10^digits
	if exp >= hyperAt then
		local eexp = (math.log10(exp))//1
		local new = BN.new(exp/10^eexp, eexp)
		return scaled .. "e" .. BN.format(new, digits, hyperAt)
	end
	if rexp < 3 then
		return scaled .. first[rexp + 1]
	end
	local i = rexp - 1
	local a = i % 10
	local b = (i // 10) % 10
	local c = (i // 100) % 10
	return scaled .. firstset[a + 1] .. second[b + 1] .. third[c + 1]
end

function BN.modf(val: any): (buffer, buffer)
	local buff
	if type(val) == "buffer" then
		buff = val
	else
		buff = buffer.create(12)
		local n
		if type(val) == "string" then
			local s = val:lower()
			if s == "inf" then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff, 0, man > 0 and 1 or -1)
						buffer.writef64(buff, 4, math.log10(math.abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val) == "number" then
			n = val
		else
			buffer.copy(buff, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				buffer.writei8(buff, 0, n > 0 and 1 or -1)
				buffer.writef64(buff, 4, math.log10(math.abs(n)))
			end
		end
	end
	local sign, log = buffer.readi8(buff, 0), buffer.readf64(buff, 4)
	local int, frac = buffer.create(12), buffer.create(12)
	if log ~= log then
		buffer.copy(int, 0, NAN, 0, 12)
		buffer.copy(frac, 0, NAN, 0, 12)
		return int, frac
	end
	if log == math.huge then
		buffer.copy(int, 0, buff, 0, 12)
		buffer.copy(frac, 0, ZERO, 0, 12)
		return int, frac
	end
	if log < 0 then
		buffer.copy(int, 0, ZERO, 0, 12)
		buffer.copy(frac, 0, buff, 0, 12)
		return int, frac
	end
	buffer.copy(int, 0, buff, 0, 12)
	buffer.copy(frac, 0, ZERO, 0, 12)
	return int, frac
end

function BN.encodeData(val: any, old: any): number
	local new = BN.lbencode(val)
	if old then
		local oldData = BN.lbdecode(old)
		local newData = BN.lbdecode(new)
		if BN.cmp(old, new) > 0 then
			return old
		end
	end
	return new
end

function BN.fmod(val1: any, val2: any): buffer
	local buff1
	if type(val1) == "buffer" then
		buff1 = val1
	else
		buff1 = buffer.create(12)
		local n
		if type(val1) == "string" then
			local s = val1:lower()
			if s == "inf" then
				buffer.copy(buff1, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff1, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff1, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff1, 0, man > 0 and 1 or -1)
						buffer.writef64(buff1, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val1) == "number" then
			n = val1
		else
			buffer.copy(buff1, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff1, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff1, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff1, 0, INF, 0, 12)
			else
				buffer.writei8(buff1, 0, n > 0 and 1 or -1)
				buffer.writef64(buff1, 4, log10(abs(n)))
			end
		end
	end
	local buff2
	if type(val2) == "buffer" then
		buff2 = val2
	else
		buff2 = buffer.create(12)
		local n
		if type(val2) == "string" then
			local s = val2:lower()
			if s == "inf" then
				buffer.copy(buff2, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff2, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff2, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff2, 0, man > 0 and 1 or -1)
						buffer.writef64(buff2, 4, log10(abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val2) == "number" then
			n = val2
		else
			buffer.copy(buff2, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff2, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff2, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff2, 0, INF, 0, 12)
			else
				buffer.writei8(buff2, 0, n > 0 and 1 or -1)
				buffer.writef64(buff2, 4, log10(abs(n)))
			end
		end
	end
	local sign1, log1 = buffer.readi8(buff1, 0), buffer.readf64(buff1, 4)
	local sign2, log2 = buffer.readi8(buff2, 0), buffer.readf64(buff2, 4)
	local out = buffer.create(12)
	if log2 ~= log2 or log2 == math.huge or sign2 == 0 then
		buffer.copy(out, 0, NAN, 0, 12)
		return out
	end
	if sign1 == 0 or log1 ~= log1 then
		buffer.copy(out, 0, ZERO, 0, 12)
		return out
	end
	if log1 == log2 then
		buffer.copy(out, 0, ZERO, 0, 12)
		return out
	end
	local diff = log1 - log2
	if diff <= 15 then
		local n1 = 10^(log1 - math.floor(log1))
		local n2 = 10^(log2 - math.floor(log2))
		local ratio = (10^diff) % 1
		local rem = n1 * ratio * 10^math.floor(log2)
		if rem == 0 then
			buffer.copy(out, 0, ZERO, 0, 12)
		else
			local rLog = math.log10(rem)
			buffer.writei8(out, 0, sign1)
			buffer.writef64(out, 4, rLog)
		end
		return out
	end
	local int = (diff)//1
	local frac = diff - int
	if frac == 0 then
		buffer.copy(out, 0, ZERO, 0, 12)
		return out
	end
	local rlog = log2 + frac
	buffer.writei8(out, 0, sign1)
	buffer.writef64(out, 4, rlog)
	return out
end

function BN.clamp(val1: any, min: any, max: any): buffer
	local buff1
	if type(val1) == "buffer" then
		buff1 = val1
	else
		buff1 = buffer.create(12)
		local n
		if type(val1) == "string" then
			local s = val1:lower()
			if s == "inf" then
				buffer.copy(buff1, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff1, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff1, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff1, 0, man > 0 and 1 or -1)
						buffer.writef64(buff1, 4, math.log10(math.abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val1) == "number" then
			n = val1
		else
			buffer.copy(buff1, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff1, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff1, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff1, 0, INF, 0, 12)
			else
				buffer.writei8(buff1, 0, n > 0 and 1 or -1)
				buffer.writef64(buff1, 4, math.log10(math.abs(n)))
			end
		end
	end
	local buffMin
	if type(min) == "buffer" then
		buffMin = min
	else
		buffMin = buffer.create(12)
		local n
		if type(min) == "string" then
			local s = min:lower()
			if s == "inf" then
				buffer.copy(buffMin, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buffMin, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buffMin, 0, ZERO, 0, 12)
					else
						buffer.writei8(buffMin, 0, man > 0 and 1 or -1)
						buffer.writef64(buffMin, 4, math.log10(math.abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(min) == "number" then
			n = min
		else
			buffer.copy(buffMin, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buffMin, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buffMin, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buffMin, 0, INF, 0, 12)
			else
				buffer.writei8(buffMin, 0, n > 0 and 1 or -1)
				buffer.writef64(buffMin, 4, math.log10(math.abs(n)))
			end
		end
	end
	local buffMax
	if type(max) == "buffer" then
		buffMax = max
	else
		buffMax = buffer.create(12)
		local n
		if type(max) == "string" then
			local s = max:lower()
			if s == "inf" then
				buffer.copy(buffMax, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buffMax, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buffMax, 0, ZERO, 0, 12)
					else
						buffer.writei8(buffMax, 0, man > 0 and 1 or -1)
						buffer.writef64(buffMax, 4, math.log10(math.abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(max) == "number" then
			n = max
		else
			buffer.copy(buffMax, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buffMax, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buffMax, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buffMax, 0, INF, 0, 12)
			else
				buffer.writei8(buffMax, 0, n > 0 and 1 or -1)
				buffer.writef64(buffMax, 4, math.log10(math.abs(n)))
			end
		end
	end
	local signX, logX = buffer.readi8(buff1, 0), buffer.readf64(buff1, 4)
	local signMin, logMin = buffer.readi8(buffMin, 0), buffer.readf64(buffMin, 4)
	local signMax, logMax = buffer.readi8(buffMax, 0), buffer.readf64(buffMax, 4)
	local cmpMin
	if signX ~= signMin then
		cmpMin = signX > signMin and 1 or -1
	else
		if signX >= 0 then
			cmpMin = logX > logMin and 1 or (logX < logMin and -1 or 0)
		else
			cmpMin = logX < logMin and 1 or (logX > logMin and -1 or 0)
		end
	end
	if cmpMin < 0 then return buffMin end
	local cmpMax
	if signX ~= signMax then
		cmpMax = signX > signMax and 1 or -1
	else
		if signX >= 0 then
			cmpMax = logX > logMax and 1 or (logX < logMax and -1 or 0)
		else
			cmpMax = logX < logMax and 1 or (logX > logMax and -1 or 0)
		end
	end
	if cmpMax > 0 then return buffMax end
	return buff1
end

function BN.abs(val: any): buffer
	local buff
	if type(val) == "buffer" then
		buff = val
	else
		buff = buffer.create(12)
		local n
		if type(val) == "string" then
			local s = val:lower()
			if s == "inf" then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff, 0, man > 0 and 1 or -1)
						buffer.writef64(buff, 4, math.log10(math.abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val) == "number" then
			n = val
		else
			buffer.copy(buff, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				buffer.writei8(buff, 0, n > 0 and 1 or -1)
				buffer.writef64(buff, 4, math.log10(math.abs(n)))
			end
		end
	end
	local out =  buffer.create(12)
	local sign, log = buffer.readi8(buff, 0), buffer.readf64(buff, 4)
	buffer.writei8(out, 0, 1)
	buffer.writef64(out, 4, log)
	return out
end

function BN.cbrt(val: any): buffer
	local buff
	if type(val) == "buffer" then
		buff = val
	else
		buff = buffer.create(12)
		local n
		if type(val) == "string" then
			local s = val:lower()
			if s == "inf" then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff, 0, man > 0 and 1 or -1)
						buffer.writef64(buff, 4, math.log10(math.abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val) == "number" then
			n = val
		else
			buffer.copy(buff, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				buffer.writei8(buff, 0, n > 0 and 1 or -1)
				buffer.writef64(buff, 4, math.log10(math.abs(n)))
			end
		end
	end
	local sign = buffer.readi8(buff, 0)
	local log = buffer.readf64(buff, 4)
	local out = buffer.create(12)
	buffer.writei8(out, 0, sign)
	buffer.writef64(out, 4, log/3)
	return out
end

function BN.maxBuy(val1: number, val2: number, multi: number)
	local min = BN.sub(multi, 1)
	local currMul = BN.mul(val1, min)
	local currdiv = BN.div(currMul, val2)
	local inLog = BN.add(currdiv, 1)
	local totalAmount = BN.floor(BN.log(inLog, multi))
	local multiPow = BN.pow(multi, totalAmount)
	local multiPowSub = BN.sub(multiPow, 1)
	local totalDiv = BN.div(multiPowSub, min)
	local totalCost = BN.mul(totalDiv, val2)
	return totalAmount, totalCost
end

function BN.percent(val1: any, val2: any): string
	local result =  BN.mul(BN.div(val1, val2), 100)
	return BN.format(BN.clamp(result, 0, 100)) .. '%'
end

function BN.linear(base: any, add: any, level: number): buffer
	return BN.add(base , BN.mul(add, level))
end

function BN.softCap(val: any, cap: any, pow: any): buffer
	if BN.cmp(val, cap) <= 0 then
		return val
	end
	return BN.mul(cap, BN.pow(BN.div(val, cap), pow))
end

function BN.milestone(val: any, step: any, bonus: any): buffer
	return BN.add(1, BN.mul(step, BN.intdiv(val, step)))
end

function BN.eta(curr: any, goal: any, rate: any): buffer
	if BN.leeq(rate, 0) then
		return INF
	end
	return BN.div(BN.sub(goal, curr), rate)
end

function BN.isZero(val: any): boolean
	return buffer.readi8(val, 0) == 0
end

function BN.dynamicCost(cost: any, owned: any, scale: any, methods: 'exp'|'linear'|'hybrid'): buffer
	if methods == 'exp' then return BN.mul(cost, BN.pow(scale, owned)) end
	if methods == 'linear' then return BN.add(cost, BN.mul(scale, owned)) end
	if methods == 'hybrid' then return BN.add(BN.mul(cost, BN.pow(scale, owned)), BN.mul(scale, owned)) end
	return cost
end

function BN.neg(val: any): buffer
	local buff
	if type(val) == "buffer" then
		buff = val
	else
		buff = buffer.create(12)
		local n
		if type(val) == "string" then
			local s = val:lower()
			if s == "inf" then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff, 0, man > 0 and 1 or -1)
						buffer.writef64(buff, 4, math.log10(math.abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val) == "number" then
			n = val
		else
			buffer.copy(buff, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				buffer.writei8(buff, 0, n > 0 and 1 or -1)
				buffer.writef64(buff, 4, math.log10(math.abs(n)))
			end
		end
	end
	local sign = buffer.readi8(buff, 0)
	local log = buffer.readf64(buff, 4)
	local out = buffer.create(12)
	if sign == 0 then
		buffer.copy(out, 0, NAN, 0, 12)
		return out
	end
	buffer.writei8(out, 0, -sign)
	buffer.writef64(out, 4, log)
	return out
end

type ScaleMode = 'linear'|'exp'|'dynamic'|'sigmoid'
type ScaleCurve = 'linear'|'exp'|'sigmoid'

function BN.scaleCurve(val1: any, base: any, exp: any, mode: ScaleMode): buffer
	local diff = BN.sub(val1, base)
	diff = BN.max(diff, 0)
	if BN.isZero(diff) then
		return BN.fromNumber(1)
	end
	local t = BN.div(diff, base)
	if mode == 'linear' then
		return BN.add(1, t)
	elseif mode == 'exp' then
		return BN.add(1, BN.pow(t, exp))
	elseif mode == 'sigmoid' then
		return BN.add(1, BN.div(1, BN.add(1, BN.exp(BN.neg(t)))))
	end
	return BN.add(1, BN.pow(t, exp))
end

function BN.progress(curr: any, goal: any, modes: ScaleMode?): buffer
	if BN.leeq(goal, 0) then return 1 end
	local ratio = BN.div(curr, goal)
	ratio = BN.clamp(ratio, 0, 1)
	if not modes or modes == 'linear' then
		return BN.pow(ratio, 1.1)
	elseif modes == 'exp' then
		return BN.pow(ratio, 2)
	elseif modes == 'dynamic' then
		return BN.mul(ratio, BN.sub(3, BN.mul(ratio, 2)))
	elseif modes == 'sigmoid' then
		local k = 6
		return BN.div(1, BN.add(1, BN.exp(BN.mul(-k, BN.sub(ratio, 0.5)))))
	end
	return ratio
end

function BN.imod(val1: any, val2: any): buffer
	return BN.sub(val1, BN.mul(BN.intdiv(val1, val2), val2))
end

function BN.timeConvert(val: any): string
	if BN.leeq(val, 0) then return "0s"	end
	local year = 365*24*60*60
	local units = {
		{name = 'Ga', seconds = year*1e9},
		{name = 'Ma', seconds = year*1e6},
		{ name = 'mi', seconds = year*1000},
		{ name = "c", seconds = year * 100 },
		{ name = "dc", seconds = year * 10 },
		{ name = "yr", seconds = year },
		{ name = "mo", seconds = 30*24*60*60 },
		{ name = "w", seconds = 7*24*60*60 },
		{ name = "d", seconds = 24*60*60 },
		{ name = "h", seconds = 3600 },
		{ name = "m", seconds = 60 },
		{ name = "s", seconds = 1 },
	}
	local s = ""
	for _, unit in ipairs(units) do
		local amount
		if unit.seconds > 1 then
			amount = BN.intdiv(val, unit.seconds)
			val = BN.imod(val, unit.seconds)
		else
			amount = val
		end
		if not BN.isZero(amount)then
			s ..= BN.format(amount) .. unit.name .. ":"
		end
	end
	if s == '' then
		s = '0s'
	else
		s = s:sub(1, -2)
	end
	return s
end

function BN.toScience(val: any): string
	local buff
	if type(val) == "buffer" then
		buff = val
	else
		buff = buffer.create(12)
		local n
		if type(val) == "string" then
			local s = val:lower()
			if s == "inf" then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				local ePos = string.find(s, "e", 1, true)
				if ePos then
					local man = tonumber(string.sub(s, 1, ePos-1))
					local exp = tonumber(string.sub(s, ePos+1))
					if not man or not exp or man ~= man then
						buffer.copy(buff, 0, NAN, 0, 12)
					elseif man == 0 then
						buffer.copy(buff, 0, ZERO, 0, 12)
					else
						buffer.writei8(buff, 0, man > 0 and 1 or -1)
						buffer.writef64(buff, 4, math.log10(math.abs(man)) + exp)
					end
				else
					n = tonumber(s)
				end
			end
		elseif type(val) == "number" then
			n = val
		else
			buffer.copy(buff, 0, NAN, 0, 12)
		end
		if n then
			if n ~= n then
				buffer.copy(buff, 0, NAN, 0, 12)
			elseif n == 0 then
				buffer.copy(buff, 0, ZERO, 0, 12)
			elseif n == 1/0 or n == -1/0 then
				buffer.copy(buff, 0, INF, 0, 12)
			else
				buffer.writei8(buff, 0, n > 0 and 1 or -1)
				buffer.writef64(buff, 4, math.log10(math.abs(n)))
			end
		end
	end
	local sign, log = buffer.readi8(buff, 0), buffer.readf64(buff, 4)
	return sign .. 'e' .. log
end

return BN
