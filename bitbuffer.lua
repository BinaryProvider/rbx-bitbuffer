--[[
==========================================================================
==                                	API                                 ==

Constructor: BitBuffer.Create()

Read/Write pairs for reading data from or writing data to the BitBuffer:
	BitBuffer:WriteUnsigned(bitWidth, value)
	BitBuffer:ReadUnsigned(bitWidth)
		Read / Write an unsigned value with a given number of bits. The
		value must be a positive integer. For instance, if bitWidth is
		4, then there will be 4 magnitude bits, for a value in the
		range [0, 2^4-1] = [0, 15]

	BitBuffer:WriteSigned(bitWidth, value)
	BitBuffer:ReadSigned(bitWidth)
		Read / Write a a signed value with a given number of bits. For
		instance, if bitWidth is 4 then there will be 1 sign bit and
		3 magnitude bits, a value in the range [-2^3+1, 2^3-1] = [-7, 7]

	BitBuffer:WriteFloat(mantissaBitWidth, exponentBitWidth, value)
	BitBuffer:ReadFloat(mantissaBitWidth, exponentBitWidth)
		Read / Write a floating point number with a given mantissa and
		exponent size in bits.

	BitBuffer:WriteFloat32(value)
	BitBuffer:ReadFloat32()
	BitBuffer:WriteFloat64(value)
	BitBuffer:ReadFloat64()
		Read and write the common types of floating point number that
		are used in code. If you want to 100% accurately save an
		arbitrary Lua number, then you should use the Float64 format. If
		your number is known to be smaller, or you want to save space
		and don't need super high precision, then a Float32 will often
		suffice. For instance, the Transparency of an object will do
		just fine as a Float32.

	BitBuffer:WriteBool(value)
	BitBuffer:ReadBool()
		Read / Write a boolean (true / false) value. Takes one bit worth
		of space to store.

	BitBuffer:WriteString(str)
	BitBuffer:ReadString()
		Read / Write a variable length string. The string may contain
		embedded nulls. Only 7 bits / character will be used if the
		string contains no non-printable characters (greater than 0x80).

	BitBuffer:WriteBrickColor(color)
	BitBuffer:ReadBrickColor()
		Read / Write a roblox BrickColor. Provided as an example of
		reading / writing a derived data type.

	BitBuffer:WriteRotation(cframe)
	BitBuffer:ReadRotation()
		Read / Write the rotation part of a given CFrame. Encodes the
		rotation in question into 64bits, which is a good size to get
		a pretty dense packing, but still while having errors well within
		the threshold that Roblox uses for stuff like MakeJoints()
		detecting adjacency. Will also perfectly reproduce rotations which
		are orthagonally aligned, or inverse-power-of-two rotated on only
		a single axix. For other rotations, the results may not be
		perfectly stable through read-write cycles (if you read/write an
		arbitrary rotation thousands of times there may be detectable
		"drift")

From/To pairs for dumping out the BitBuffer to another format:
	BitBuffer:ToString()
	BitBuffer:FromString(str)
		Will replace / dump out the contents of the buffer to / from
		a binary chunk encoded as a Lua string. This string is NOT
		suitable for storage in the Roblox DataStores, as they do
		not handle non-printable characters well.

	BitBuffer:ToBase64()
	BitBuffer:FromBase64(str)
		Will replace / dump out the contents of the buffer to / from
		a set of Base64 encoded data, as a Lua string. This string
		only consists of Base64 printable characters, so it is
		ideal for storage in Roblox DataStores.

Buffer / Position Manipulation
	BitBuffer:ResetPtr()
		Will Reset the point in the buffer that is being read / written
		to back to the start of the buffer.

	BitBuffer:Reset()
		Will reset the buffer to a clean state, with no contents.

Example Usage:
	local function SaveToBuffer(buffer, userData)
		buffer:WriteString(userData.HeroName)
		buffer:WriteUnsigned(14, userData.Score) --> 14 bits -> [0, 2^14-1] -> [0, 16383]
		buffer:WriteBool(userData.HasDoneSomething)
		buffer:WriteUnsigned(10, #userData.ItemList) --> [0, 1023]
		for _, itemInfo in pairs(userData.ItemList) do
			buffer:WriteString(itemInfo.Identifier)
			buffer:WriteUnsigned(10, itemInfo.Count) --> [0, 1023]
		end
	end
	local function LoadFromBuffer(buffer, userData)
		userData.HeroName = buffer:ReadString()
		userData.Score = buffer:ReadUnsigned(14)
		userData.HasDoneSomething = buffer:ReadBool()
		local itemCount = buffer:ReadUnsigned(10)
		for i = 1, itemCount do
			local itemInfo = {}
			itemInfo.Identifier = buffer:ReadString()
			itemInfo.Count = buffer:ReadUnsigned(10)
			table.insert(userData.ItemList, itemInfo)
		end
	end
	--...
	local buff = BitBuffer.Create()
	SaveToBuffer(buff, someUserData)
	myDataStore:SetAsync(somePlayer.userId, buff:ToBase64())
	--...
	local data = myDataStore:GetAsync(somePlayer.userId)
	local buff = BitBuffer.Create()
	buff:FromBase64(data)
	LoadFromBuffer(buff, someUserData)
--]]

BitBuffer = {
	create = function(self)
		return BitBuffer.new();
	end;
};

BitBuffer.__index = {

	toBase = function(self, n, b)
		n = math.floor(n);
		if not b or b == 10 then return tostring(n) end;
		local digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
		local t = {};
		local sign = "";
		if n < 0 then
			sign = "-";
			n = -n;
		end;
		repeat
				local d = (n % b) + 1;
				n = math.floor(n / b);
				table.insert(t, 1, digits:sub(d, d));
		until n == 0;
		return sign..table.concat(t, "");
	end;

	resetPtr = function(self)
		self.mBitPtr = 0;
	end;

	reset = function(self)
		self.mBitBuffer = {};
		self.mBitPtr = 0;
	end;

	setDebug = function(self, state)
		self.mDebug = state;
	end;

	fromString = function(self, str)
		self:reset();
		for i = 1, #str do
			local ch = str:sub(i, i):byte();
			for i = 1, 8 do
				self.mBitPtr = self.mBitPtr + 1;
				self.mBitBuffer[self.mBitPtr] = ch % 2;
				ch = math.floor(ch / 2);
			end;
		end;
		self.mBitPtr = 0;
	end;

	toString = function(self)
		local str = "";
		local accum = 0;
		local pow = 0;
		for i = 1, math.ceil((#self.mBitBuffer) / 8)*8 do
			accum = accum + self.PowerOfTwo[pow]*(self.mBitBuffer[i] or 0);
			pow = pow + 1;
			if pow >= 8 then
				str = str..string.char(accum);
				accum = 0;
				pow = 0;
			end;
		end;
		return str;
	end;

	fromBase64 = function(self, str)
		self:reset();
		for i = 1, #str do
			local ch = self.Base64ToNumber[str:sub(i, i)];
			assert(ch, "Bad character: 0x"..self:toBase(str:sub(i, i):byte(), 16));
			for i = 1, 6 do
				self.mBitPtr = self.mBitPtr + 1;
				self.mBitBuffer[self.mBitPtr] = ch % 2;
				ch = math.floor(ch / 2);
			end
			assert(ch == 0, "Character value 0x"..self:toBase(self.Base64ToNumber[str:sub(i, i)], 16).." too large");
		end;
		self:resetPtr();
	end;

	toBase64 = function(self)
		local strtab = {};
		local accum = 0;
		local pow = 0;
		for i = 1, math.ceil((#self.mBitBuffer) / 6)*6 do
			accum = accum + self.PowerOfTwo[pow]*(self.mBitBuffer[i] or 0);
			pow = pow + 1;
			if pow >= 6 then
				table.insert(strtab, self.NumberToBase64[accum]);
				accum = 0;
				pow = 0;
			end;
		end;
		return table.concat(strtab);
	end;

	dump = function(self)
		local str = "";
		local str2 = "";
		local accum = 0;
		local pow = 0;
		for i = 1, math.ceil((#self.mBitBuffer) / 8)*8 do
			str2 = str2..(self.mBitBuffer[i] or 0);
			accum = accum + self.PowerOfTwo[pow]*(self.mBitBuffer[i] or 0);
			--print(pow..": +"..PowerOfTwo[pow].."*["..(self.mBitBuffer[i] or 0).."] -> "..accum);
			pow = pow + 1;
			if pow >= 8 then
				str2 = str2.." ";
				str = str.."0x"..self:toBase(accum, 16).." ";
				accum = 0;
				pow = 0;
			end;
		end;
		print("Bytes:", str);
		print("Bits:", str2);
	end;

	writeUnsigned = function(self, w, value, printoff)
		assert(w, "Bad arguments to BitBuffer::writeUnsigned (Missing BitWidth)");
		assert(value, "Bad arguments to BitBuffer::writeUnsigned (Missing Value)");
		assert(value >= 0, "Negative value to BitBuffer::writeUnsigned");
		assert(math.floor(value) == value, "Non-integer value to BitBuffer::writeUnsigned");
		if self.mDebug and not printoff then
			print("writeUnsigned["..w.."]:", value);
		end;
		-- Store LSB first
		for i = 1, w do
			self:writeBit(value % 2);
			value = math.floor(value / 2);
		end;
		assert(value == 0, "Value "..tostring(value).." has width greater than "..w.."bits");
	end;

	readUnsigned = function(self, w, printoff)
		local value = 0;
		for i = 1, w do
			value = value + self:readBit() * self.PowerOfTwo[i-1];
		end;
		if self.mDebug and not printoff then
			print("readUnsigned["..w.."]:", value);
		end;
		return value;
	end;

	writeSigned = function(self, w, value)
		assert(w and value, "Bad arguments to BitBuffer::writeSigned (Did you forget a bitWidth?)");
		assert(math.floor(value) == value, "Non-integer value to BitBuffer::writeSigned");
		if self.mDebug then
			print("writeSigned["..w.."]:", value);
		end;
		-- Write sign
		if value < 0 then
			self:writeBit(1);
			value = -value;
		else
			self:writeBit(0);
		end;
		-- Write value
		self:writeUnsigned(w-1, value, true);
	end;

	readSigned = function(self, w)
		-- Read sign
		local sign = (-1)^self:readBit();
		-- Read value
		local value = self:readUnsigned(w-1, true);
		if self.mDebug then
			print("readSigned["..w.."]:", sign*value);
		end;
		return sign*value;
	end;

	writeString = function(self, s)
		-- First check if it's a 7 or 8 bit width of string
		local bitWidth = 7;
		for i = 1, #s do
			if s:sub(i, i):byte() > 127 then
				bitWidth = 8;
				break;
			end;
		end;

		-- Write the bit width flag
		if bitWidth == 7 then
			self:writeBool(false);
		else
			self:writeBool(true); -- wide chars
		end;

		-- Now write out the string, terminated with "0x10, 0b0"
		-- 0x10 is encoded as "0x10, 0b1"
		for i = 1, #s do
			local ch = s:sub(i, i):byte();
			if ch == 0x10 then
				self:writeUnsigned(bitWidth, 0x10);
				self:writeBool(true);
			else
				self:writeUnsigned(bitWidth, ch);
			end;
		end;
		
		-- Write terminator
		self:writeUnsigned(bitWidth, 0x10);
		self:writeBool(false);
	end;

	readString = function(self)
		-- Get bit width
		local bitWidth;
		if self:readBool() then
			bitWidth = 8;
		else
			bitWidth = 7;
		end;
		
		-- Loop
		local str = "";
		while true do
			local ch = self:readUnsigned(bitWidth);
			if ch == 0x10 then
				local flag = self:readBool();
				if flag then
					str = str..string.char(0x10);
				else
					break;
				end;
			else
				str = str..string.char(ch);
			end;
		end;
		return str;
	end;

	writeBool = function(self, v)
		if self.mDebug then
			print("writeBool[1]:", v and "1" or "0");
		end;
		if v then
			self:writeUnsigned(1, 1, true);
		else
			self:writeUnsigned(1, 0, true);
		end;
	end;

	readBool = function(self)
		local v = (self:readUnsigned(1, true) == 1);
		if self.mDebug then
			print("readBool[1]:", v and "1" or "0");
		end;
		return v;
	end;

	writeFloat = function(self, wfrac, wexp, f)
		assert(wfrac and wexp and f);

		-- Sign
		local sign = 1;
		if f < 0 then
			f = -f;
			sign = -1;
		end;

		-- Decompose
		local mantissa, exponent = math.frexp(f);
		if exponent == 0 and mantissa == 0 then
			self:writeUnsigned(wfrac + wexp + 1, 0);
			return;
		else
			mantissa = ((mantissa - 0.5)/0.5 * self.PowerOfTwo[wfrac]);
		end;

		-- Write sign
		if sign == -1 then
			self:writeBool(true);
		else
			self:writeBool(false);
		end;

		-- Write mantissa
		mantissa = math.floor(mantissa + 0.5); -- Not really correct, should round up/down based on the parity of |wexp|
		self:writeUnsigned(wfrac, mantissa);

		-- Write exponent
		local maxExp = self.PowerOfTwo[wexp-1]-1;
		if exponent > maxExp then
			exponent = maxExp;
		end;
		if exponent < -maxExp then
			exponent = -maxExp;
		end;
		self:writeSigned(wexp, exponent);
	end;

	readFloat = function(self, wfrac, wexp)
		assert(wfrac and wexp);

		-- Read sign
		local sign = 1;
		if self:readBool() then
			sign = -1;
		end;

		-- Read mantissa
		local mantissa = self:readUnsigned(wfrac);

		-- Read exponent
		local exponent = self:readSigned(wexp);
		if exponent == 0 and mantissa == 0 then
			return 0;
		end;

		-- Convert mantissa
		mantissa = mantissa / self.PowerOfTwo[wfrac] * 0.5 + 0.5;

		-- Output
		return sign * math.ldexp(mantissa, exponent);
	end;

	writeFloat32 = function(self, f)
		self:writeFloat(23, 8, f);
	end;

	readFloat32 = function(self)
		return self:readFloat(23, 8);
	end;

	writeFloat64 = function(self, f)
		self:writeFloat(52, 11, f);
	end;

	readFloat64 = function(self)
		return self:readFloat(52, 11);
	end;

	writeBrickColor = function(self, b)
		local pnum = self.BrickColorToNumber[b.Number];
		if not pnum then
			warn("Attempt to serialize non-pallete BrickColor `"..tostring(b).."` (#"..b.Number.."), using Light Stone Grey instead.");
			pnum = self.BrickColorToNumber[BrickColor.new(1032).Number];
		end;
		self:writeUnsigned(6, pnum);
	end;

	readBrickColor = function(self)
		return self.NumberToBrickColor[self:readUnsigned(6)];
	end;

	writeRotation = function(self, cf)
		local lookVector = cf.lookVector;
		local azumith = math.atan2(-lookVector.X, -lookVector.Z);
		local ybase = (lookVector.X^2 + lookVector.Z^2)^0.5;
		local elevation = math.atan2(lookVector.Y, ybase);
		local withoutRoll = CFrame.new(cf.p) * CFrame.Angles(0, azumith, 0) * CFrame.Angles(elevation, 0, 0);
		local x, y, z = (withoutRoll:inverse()*cf):toEulerAnglesXYZ();
		local roll = z;
		-- Atan2 -> in the range [-pi, pi] 
		azumith   = self.round((azumith   /  math.pi   ) * (2^21-1));
		roll      = self.round((roll      /  math.pi   ) * (2^20-1));
		elevation = self.round((elevation / (math.pi/2)) * (2^20-1));
		--
		self:writeSigned(22, azumith);
		self:writeSigned(21, roll);
		self:writeSigned(21, elevation);
	end;

	readRotation = function(self)
		local azumith   = self:readSigned(22);
		local roll      = self:readSigned(21);
		local elevation = self:readSigned(21);
		--
		azumith =    math.pi    * (azumith / (2^21-1));
		roll =       math.pi    * (roll    / (2^20-1));
		elevation = (math.pi/2) * (elevation / (2^20-1));
		--
		local rot = CFrame.Angles(0, azumith, 0);
		rot = rot * CFrame.Angles(elevation, 0, 0);
		rot = rot * CFrame.Angles(0, 0, roll);
		--
		return rot;
	end;

	round = function(self, n)
		return math.floor(n + 0.5);
	end;

	writeBit = function(self, v)
		self.mBitPtr = self.mBitPtr + 1;
		self.mBitBuffer[self.mBitPtr] = v;
	end;

	readBit = function(self, v)
		self.mBitPtr = self.mBitPtr + 1;
		return self.mBitBuffer[self.mBitPtr];
	end;
};

BitBuffer.new = function(...)
	return BitBuffer.constructor(setmetatable({}, BitBuffer), ...);
end;

BitBuffer.constructor = function(self, ...)
	self.mBitPtr = 0;
	self.mBitBuffer = {};
	self.mDebug = false;

	self.PowerOfTwo = {};
	for i = 0, 64 do
		self.PowerOfTwo[i] = 2^i;
	end;

	self.NumberToBase64 = {};
	self.Base64ToNumber = {};

	local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
	for i = 1, #chars do
		local ch = chars:sub(i, i);
		self.NumberToBase64[i-1] = ch;
		self.Base64ToNumber[ch] = i-1;
	end;

	self.BrickColorToNumber = {};
	self.NumberToBrickColor = {};

	for i = 0, 63 do
		local color = BrickColor.palette(i);
		self.BrickColorToNumber[color.Number] = i;
		self.NumberToBrickColor[i] = color;
	end;

	return self;

end;

return BitBuffer;