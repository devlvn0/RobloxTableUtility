--[[

Name: Table
Authors: devlvn
Created: 12/12/2025
Description: Library for some useful table functions, like joining tables

Version: 1.0.0

]]

-- Libraries
local Signal = require(script.Parent.Signal)
local assert = require(script.Parent.Assert)

-- Table
local tFuncs = {}

-- Adds multiple tables together
function tFuncs.SimpleJoinTables<T>(...): T
	local tables = {...}
	local replacementTable = {}
	
	for key, value in tables[1] do
		replacementTable[key] = value
	end
	table.remove(tables,1)

	for _, joinTable: {[any]: any} in tables do
		for index: any, value: any in joinTable do
			if replacementTable[index] then
				warn(`Joined table key {index} already exists. {replacementTable[index]} -> {value} \n {debug.info(2, "s")}:{debug.info(2, "l")}`)
				continue
			end

			replacementTable[index] = value
		end
	end

	return replacementTable
end

@[deprecated {use = "SimpleJoinTables"}]
function tFuncs.JoinTables<T>(...): T
	return tFuncs.SimpleJoinTables(...)
end

-- Adds multiple tables together, with more options than simple join tables
function tFuncs.AdvancedJoinTables(): {[string]: ()->()}
	local tables = {}
	local joined = false

	return {
		AddTables = function(...: {}): ()
			assert(joined == false, "Tables were already joined together.", 2)

			for _, t in {...} do
				table.insert(tables, t)
			end
		end,
		RemoveTables = function(...: number): ()
			assert(joined == false, "Tables were already joined together.", 2)

			for _, tn in {...} do
				tables[tn] = nil
			end
		end,
		GetTables = function(): {[number]: {any}}
			assert(joined == false, "Tables were already joined together.", 2)

			return table.clone(tables)
		end,
		JoinTables = function(recursive: boolean?, recursionLevels: number?, overwriteData: boolean?)
			assert(joined == false, "Tables were already joined together.", 2)

			recursive = if recursive ~= nil then recursive else false
			recursionLevels = recursionLevels or -1
			overwriteData = if overwriteData ~= nil then overwriteData else false

			local replacementTable = {}

			local function recursiveTableJoinComponent(t1: {}, t2: {}, recursionLevel: number): ()
				for key: any, value: any in t2 do
					if not t1[key] then
						t1[key] = value
						continue
					end

					if recursive and (recursionLevels < 0 or recursionLevel <= recursionLevels) and typeof(value) == "table" then
						recursiveTableJoinComponent(t1[key], t2[key], recursionLevel+1)
						continue
					end
					if overwriteData then
						t1[key] = value
						continue
					end

					warn(`Key {key} was skipped, key already exists in first table`)
				end
			end

			for key, value in tables[1] do
				replacementTable[key] = value
			end
			table.remove(tables, 1)

			for i, joinTable: {[any]: any} in tables do
				recursiveTableJoinComponent(replacementTable, joinTable, 0)
				table.remove(tables, i)
			end

			joined = true
			return replacementTable
		end,
	}
end

-- Combines multiple tables to one, without keeping the indices
function tFuncs.ConcatTables<T>(...): T
	local replacementTable = {}
	
	for _, t in {...} do
		for _, value in t do
			table.insert(replacementTable, value)
		end
	end
	
	return replacementTable
end

-- Finds and returns the first index where the provided value appears
function tFuncs.FindFirstInTable<T,V,K>(t: T, value: V): K?
	for tindex, tvalue in t do
		if tvalue ~= value then
			continue
		end 

		return tindex
	end
end

-- Works like table.insert, but without bypassing meta functions
function tFuncs.TableInsert<T,V>(t: T, value: V): ()
	local function recursiveFind(pos: number)
		if t[pos] then
			recursiveFind(pos+1)
		end

		t[pos] = value
	end

	return recursiveFind(1)
end

-- Works like the # operator on tables, but with counting nun-numeric indices as well
function tFuncs.CountValues<T>(t: T): number?
	if t == nil then
		return
	end

	local c = 0
	for _, t in t do
		c += 1
	end

	return c
end

-- Sets multiple values in a table to nil, without defining a index value
function tFuncs.FindAndRemoveFromTable<T>(t: T, ...): ()
	for _, removeItem: any in {...} do
		local itemIndex: any = tFuncs.FindFirstInTable(t, removeItem)
		if itemIndex then
			t[itemIndex] = nil
		end
	end
end

-- Main function of this is to have a table that fires a signal once a variable was changed
function tFuncs.CreateNoticeableTable<T, M>(t: T?, metaAddition: M?): ({}, Signal.Signal)
	local proxy = newproxy(true)
	local meta = getmetatable(proxy)
	local data = t or {}

	local updateSignal, fireSignal = Signal.new()

	if t then
		for index, value in data do
			if typeof(value) ~= "table" then
				continue
			end

			local tab, sig = tFuncs.CreateNoticeableTable(value)
			data[index] = tab
			sig:Connect(function(cind: string, ...)
				fireSignal(`{index}.{cind}`, ...) -- ADD A CHECK HERE THAT PREVENTS CONNECTING A SIGNAL TO A TABLE CYCLE REFERENCE
			end)
		end
	end

	if metaAddition then
		for i,v in metaAddition do
			meta[i] = v
		end
	end

	meta.__index = function<T,K,V>(self: T, index: K): V
		return data[index]
	end
	meta.__newindex = function<T,K,V>(self: T, index: K, value: V): ()
		value = if metaAddition and metaAddition["__newindex"] ~= nil then metaAddition.__newindex(self, index, value) else value

		local signal
		if typeof(value) == "table" then 
			value, signal = tFuncs.CreateNoticeableTable(value) 
		end

		if signal then
			signal:Connect(function(cind: string, ...)
				fireSignal(`{index}.{cind}`, ...) -- ADD A CHECK HERE THAT PREVENTS CONNECTING A SIGNAL TO A TABLE CYCLE REFERENCE
			end)
		end

		fireSignal(index, value, data[index])

		data[index] = value
	end
	meta.__iter = function<T,K,V>(self: T): (<T,K>(self: T, lastIndex: K) -> any, T, number)
		local keys = {}
		local vals = {}

		for index: K, val: V in data do
			table.insert(keys, index)
			vals[index] = val
		end

		local nextIndex = 1

		return function<T,K>(self: T, lastIndex: K): any
			local thisIndex = nextIndex
			nextIndex += 1

			if thisIndex <= #keys then
				return keys[thisIndex], vals[keys[thisIndex]]
			end
			return nil
		end, self, 0 
	end
	meta.__len = function(): number
		local c = 0

		local function recursiveCount(pos: number)
			if t[pos] then
				c += 1
				recursiveCount(pos+1)
			end

			return c
		end

		return recursiveCount(0)
	end
	meta.__tostring = function(): string
		-- Issues with C stack overflow, when there are multiple non-default tables stacked in each other
		--local function tableToString<T>(t: T): string
		--	local returnString = "{"
		--	local num = 0
		--	for key, value in t do
		--		if num > 0 then
		--			returnString = returnString..", "
		--		end
				
		--		if typeof(value) == "string" then
		--			value = `"{value}"`
		--		elseif typeof(value) == "number" then
		--			value = `{value}`
		--		elseif typeof(value) == "table" then
		--			value = tableToString(value)
		--		else
		--			value = tostring(value)
		--		end
				
		--		if typeof(key) == "string" then
		--			returnString = returnString..`["{key}"] = {value}`
		--		elseif typeof(key) == "number" then
		--			returnString = returnString..`[{key}] = {value}`
		--		else
		--			returnString = returnString..`[{tostring(key)}] = {value}`
		--		end
				
		--		num += 1
		--	end
		--	return returnString.."}"
		--end
		
		return tostring(data) --tableToString(data)
	end
	meta.__metatable = "The metatable is locked"

	return proxy, updateSignal
end

return tFuncs