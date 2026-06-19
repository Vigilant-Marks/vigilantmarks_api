local RESOURCE_NAME = GetCurrentResourceName()

---@class VigilantMarksClient
---@field baseUrl string
---@field apiKey string
---@field timeoutMs number
---@field debug boolean
---@field config table
VigilantMarksClient = {}
VigilantMarksClient.__index = VigilantMarksClient

---@alias VigilantMarksResponse table
--- Standard response returned by the HTTP wrappers.
--- Main fields: ok, status, data, body, headers, error, details, endpoint.

---@alias VigilantMarksCallback fun(response: VigilantMarksResponse)
--- Standard callback used by API methods.

---@alias VigilantMarksIsMarkedCallback fun(exists: boolean, marks: table, response: VigilantMarksResponse)
--- Simplified callback used by isMarked/IsMarked.

local IDENTIFIER_FIELDS = {
  "discordId",
  "xboxLicense",
  "fivemLicense",
  "inGameLicense",
  "steamLicense"
}

local IDENTIFIER_ALIASES = {
  discord = "discordId",
  discordId = "discordId",
  discordid = "discordId",
  xbox = "xboxLicense",
  live = "xboxLicense",
  xboxLicense = "xboxLicense",
  xboxlicense = "xboxLicense",
  fivem = "fivemLicense",
  fivemLicense = "fivemLicense",
  fivemlicense = "fivemLicense",
  license = "inGameLicense",
  inGameLicense = "inGameLicense",
  ingamelicense = "inGameLicense",
  steam = "steamLicense",
  steamLicense = "steamLicense",
  steamlicense = "steamLicense"
}

local RISK_SCORES = {
  LOW = 1,
  MEDIUM = 2,
  HIGH = 3
}

local function shallowMerge(base, override)
  local merged = {}

  for key, value in pairs(base or {}) do
    merged[key] = value
  end

  for key, value in pairs(override or {}) do
    merged[key] = value
  end

  return merged
end

local function trim(value)
  if value == nil then return nil end
  return tostring(value):match("^%s*(.-)%s*$")
end

local function stripTrailingSlash(value)
  value = trim(value) or ""
  return value:gsub("/+$", "")
end

local function isBlank(value)
  value = trim(value)
  return value == nil or value == ""
end

local function cleanIdentifierValue(value)
  value = trim(value)
  if isBlank(value) then return nil end

  local key, raw = value:match("^([^:]+):(.+)$")
  if key and raw then
    local normalizedKey = key:lower()
    if IDENTIFIER_ALIASES[normalizedKey] then
      return trim(raw)
    end
  end

  return value
end

local function urlEncode(value)
  value = tostring(value or "")
  value = value:gsub("\n", "\r\n")
  value = value:gsub("([^%w%-_%.~])", function(char)
    return string.format("%%%02X", string.byte(char))
  end)
  return value
end

local function hasAnyIdentifier(payload)
  for _, key in ipairs(IDENTIFIER_FIELDS) do
    if not isBlank(payload[key]) then
      return true
    end
  end

  return false
end

local function normalizeArray(value)
  if type(value) == "table" then
    return value
  end

  return {}
end

local function safeJsonDecode(body)
  if body == nil or body == "" then
    return nil
  end

  local ok, decoded = pcall(json.decode, body)
  if not ok then
    return nil
  end

  return decoded
end

local function normalizeRisk(risk)
  risk = trim(risk)
  if not risk then return nil end

  risk = risk:upper()
  if RISK_SCORES[risk] then
    return risk
  end

  return nil
end

local function formatKickMessage(template, risk, mark)
  local message = template or "Your account is listed on Vigilant Marks."
  local reason = mark and mark.reason or "No reason provided."
  local post = mark and mark.post or "Unavailable"

  message = message:gsub("{risk}", risk or "UNKNOWN")
  message = message:gsub("{reason}", reason)
  message = message:gsub("{post}", post)

  return message
end

--- Creates a new Vigilant Marks client instance.
--- Uses VigilantMarksConfig and lets options override selected values.
--- Most servers should use the shared VigilantMarks instance.
---@param options table|nil Optional config: BaseUrl, ApiKey, RequestTimeoutMs, Debug.
---@return VigilantMarksClient client New instance ready to call the API.
function VigilantMarksClient:new(options)
  local config = shallowMerge(VigilantMarksConfig or {}, options or {})
  local client = setmetatable({}, self)

  client.config = config
  client.baseUrl = stripTrailingSlash(config.BaseUrl)
  client.apiKey = trim(config.ApiKey) or ""
  client.timeoutMs = tonumber(config.RequestTimeoutMs) or 10000
  client.debug = config.Debug == true

  return client
end

--- Sets or replaces the API key used by this instance.
--- Useful when loading the key dynamically instead of from server.cfg.
---@param apiKey string|nil New API key.
---@return VigilantMarksClient self Same instance, for chaining.
function VigilantMarksClient:setApiKey(apiKey)
  self.apiKey = trim(apiKey) or ""
  return self
end

--- Sets or replaces the Vigilant Marks API base URL.
--- Useful for test, staging, or local development environments.
---@param baseUrl string Base URL, for example https://vigilantmarks.com.
---@return VigilantMarksClient self Same instance, for chaining.
function VigilantMarksClient:setBaseUrl(baseUrl)
  self.baseUrl = stripTrailingSlash(baseUrl)
  return self
end

--- Prints debug messages only when Debug is true.
--- Does not call the API; this is only for server-side diagnostics.
---@param ... any Values to print in console.
function VigilantMarksClient:log(...)
  if self.debug then
    print(("[VigilantMarks:%s]"):format(RESOURCE_NAME), ...)
  end
end

--- Converts identifier keys and values to the Vigilant Marks API format.
--- Accepts convenient aliases such as discord, fivem, license, steam, xbox/live.
--- Also removes prefixes such as fivem:, discord:, license:, steam:, and live:.
---@param identifiers table|nil Table with raw or already-normalized identifiers.
---@return table identifiers Normalized table with discordId, fivemLicense, inGameLicense, steamLicense, xboxLicense.
function VigilantMarksClient:normalizeIdentifiers(identifiers)
  local normalized = {}

  for key, value in pairs(identifiers or {}) do
    local targetKey = IDENTIFIER_ALIASES[key] or IDENTIFIER_ALIASES[tostring(key):lower()]
    if targetKey then
      local cleaned = cleanIdentifierValue(value)
      if cleaned then
        normalized[targetKey] = cleaned
      end
    end
  end

  return normalized
end

--- Reads the FiveM identifiers of an online player and converts them for the API.
--- Uses GetPlayerIdentifiers(playerId), so this only works server-side.
---@param playerId number FiveM server ID of the player, often source.
---@return table identifiers Normalized identifiers found on the player.
function VigilantMarksClient:getPlayerIdentifiers(playerId)
  local output = {}

  for _, identifier in ipairs(GetPlayerIdentifiers(playerId) or {}) do
    local key, value = identifier:match("^([^:]+):(.+)$")
    if key and value then
      local targetKey = IDENTIFIER_ALIASES[key:lower()]
      if targetKey and isBlank(output[targetKey]) then
        output[targetKey] = cleanIdentifierValue(identifier)
      end
    end
  end

  return output
end

--- Builds the query string for GET /api/v1/marks.
--- Normalizes parameters first and only includes present identifiers.
---@param params table Identifier parameters.
---@return string query Query string without the leading question mark.
function VigilantMarksClient:buildQuery(params)
  local parts = {}
  local normalized = self:normalizeIdentifiers(params)

  for _, key in ipairs(IDENTIFIER_FIELDS) do
    local value = normalized[key]
    if not isBlank(value) then
      parts[#parts + 1] = ("%s=%s"):format(key, urlEncode(value))
    end
  end

  return table.concat(parts, "&")
end

--- Generic HTTP method used internally by all other methods.
--- Adds Authorization Bearer, handles JSON, timeouts, and normalized errors.
--- You can use it to call new endpoints before a dedicated helper exists.
---@param method string HTTP method, for example GET or POST.
---@param path string API path, for example /api/v1/marks.
---@param options table|nil Options: query for GET, body for JSON POST.
---@param callback VigilantMarksCallback|nil Callback with standard response.
function VigilantMarksClient:request(method, path, options, callback)
  options = options or {}
  callback = callback or function() end

  if isBlank(self.baseUrl) then
    callback({
      ok = false,
      status = 0,
      error = "Missing Vigilant Marks base URL."
    })
    return
  end

  if isBlank(self.apiKey) then
    callback({
      ok = false,
      status = 0,
      error = "Missing Vigilant Marks API key. Set vigilantmarks_api_key in server.cfg."
    })
    return
  end

  local query = ""
  if options.query then
    query = self:buildQuery(options.query)
  end

  local endpoint = self.baseUrl .. path
  if query ~= "" then
    endpoint = endpoint .. "?" .. query
  end

  local body = nil
  local headers = {
    ["Accept"] = "application/json",
    ["Authorization"] = "Bearer " .. self.apiKey
  }

  if options.body ~= nil then
    body = json.encode(options.body)
    headers["Content-Type"] = "application/json"
  end

  local completed = false

  if self.timeoutMs > 0 then
    SetTimeout(self.timeoutMs, function()
      if completed then return end
      completed = true

      callback({
        ok = false,
        status = 0,
        error = "Request timed out.",
        endpoint = endpoint
      })
    end)
  end

  self:log(method, endpoint)

  PerformHttpRequest(endpoint, function(statusCode, responseBody, responseHeaders, errorData)
    if completed then return end
    completed = true
    statusCode = tonumber(statusCode) or 0

    local data = safeJsonDecode(responseBody)
    local ok = statusCode >= 200 and statusCode < 300
    local errorMessage = nil

    if not ok then
      if type(data) == "table" and data.error then
        errorMessage = data.error
      elseif errorData and errorData ~= "" then
        errorMessage = errorData
      else
        errorMessage = ("HTTP %s"):format(statusCode)
      end
    end

    callback({
      ok = ok,
      status = statusCode,
      data = data,
      body = responseBody,
      headers = responseHeaders,
      error = errorMessage,
      details = type(data) == "table" and data.details or nil,
      endpoint = endpoint
    })
  end, method, body, headers)
end

--- Checks whether verified marks exist for one or more identifiers.
--- Requires at least one valid identifier.
---@param identifiers table Identifiers to check.
---@param callback VigilantMarksCallback|nil Callback with standard response.
function VigilantMarksClient:checkIdentifiers(identifiers, callback)
  callback = callback or function() end

  local normalized = self:normalizeIdentifiers(identifiers)

  if not hasAnyIdentifier(normalized) then
    callback({
      ok = false,
      status = 400,
      error = "At least one identifier is required."
    })
    return
  end

  self:request("GET", "/api/v1/marks", {
    query = normalized
  }, callback)
end

--- Checks an online player using their FiveM identifiers automatically.
--- This is the easiest method when you already have the player's server ID.
---@param playerId number FiveM server ID of the player.
---@param callback VigilantMarksCallback|nil Callback with standard response.
function VigilantMarksClient:checkPlayer(playerId, callback)
  self:checkIdentifiers(self:getPlayerIdentifiers(playerId), callback)
end

--- Checks a single FiveM ID.
--- Accepts either a clean value or a value with the fivem: prefix.
---@param fivemLicense string FiveM ID to check.
---@param callback VigilantMarksCallback|nil Callback with standard response.
function VigilantMarksClient:checkFiveM(fivemLicense, callback)
  self:checkIdentifiers({ fivemLicense = fivemLicense }, callback)
end

--- Checks a single Discord ID.
--- Accepts either a clean value or a value with the discord: prefix.
---@param discordId string Discord ID to check.
---@param callback VigilantMarksCallback|nil Callback with standard response.
function VigilantMarksClient:checkDiscord(discordId, callback)
  self:checkIdentifiers({ discordId = discordId }, callback)
end

--- Checks a single FiveM/GTA license: identifier.
--- Accepts either a clean value or a value with the license: prefix.
---@param inGameLicense string License identifier to check.
---@param callback VigilantMarksCallback|nil Callback with standard response.
function VigilantMarksClient:checkLicense(inGameLicense, callback)
  self:checkIdentifiers({ inGameLicense = inGameLicense }, callback)
end

--- Checks a single Steam identifier.
--- Accepts either a clean value or a value with the steam: prefix.
---@param steamLicense string Steam identifier to check.
---@param callback VigilantMarksCallback|nil Callback with standard response.
function VigilantMarksClient:checkSteam(steamLicense, callback)
  self:checkIdentifiers({ steamLicense = steamLicense }, callback)
end

--- Checks a single Xbox Live identifier.
--- Accepts a clean value, xbox:, or live:.
---@param xboxLicense string Xbox Live identifier to check.
---@param callback VigilantMarksCallback|nil Callback with standard response.
function VigilantMarksClient:checkXbox(xboxLicense, callback)
  self:checkIdentifiers({ xboxLicense = xboxLicense }, callback)
end

--- Simplified version of checkIdentifiers.
--- Instead of returning the full response as the first value, it returns:
--- exists, marks, response.
---@param identifiers table Identifiers to check.
---@param callback VigilantMarksIsMarkedCallback|nil Simplified callback.
function VigilantMarksClient:isMarked(identifiers, callback)
  callback = callback or function() end

  self:checkIdentifiers(identifiers, function(response)
    local exists = response.ok and response.data and response.data.exists == true
    local marks = exists and response.data.marks or {}
    callback(exists, marks, response)
  end)
end

--- Returns the highest risk found in a marks list.
--- Risk order is LOW < MEDIUM < HIGH.
---@param marks table|nil Marks returned by the Vigilant Marks API.
---@return string|nil risk Highest risk value, or nil when no valid risk exists.
---@return table|nil mark Mark object that produced the highest risk.
---@return number score Numeric risk score.
function VigilantMarksClient:getHighestRisk(marks)
  local highestRisk = nil
  local highestMark = nil
  local highestScore = 0

  for _, mark in ipairs(marks or {}) do
    local risk = normalizeRisk(mark.risk)
    local score = risk and RISK_SCORES[risk] or 0

    if score > highestScore then
      highestRisk = risk
      highestMark = mark
      highestScore = score
    end
  end

  return highestRisk, highestMark, highestScore
end

--- Checks whether one risk is equal to or higher than a minimum risk.
---@param risk string|nil Risk to test.
---@param minimumRisk string|nil Minimum accepted risk. Defaults to LOW.
---@return boolean allowed True when risk meets or exceeds the minimum.
function VigilantMarksClient:riskMeetsMinimum(risk, minimumRisk)
  risk = normalizeRisk(risk)
  minimumRisk = normalizeRisk(minimumRisk) or "LOW"

  if not risk then
    return false
  end

  return RISK_SCORES[risk] >= RISK_SCORES[minimumRisk]
end

--- Checks whether the highest risk in a marks list meets a minimum risk.
---@param marks table|nil Marks returned by the Vigilant Marks API.
---@param minimumRisk string|nil Minimum accepted risk. Defaults to LOW.
---@return boolean allowed True when the highest mark risk meets or exceeds the minimum.
---@return string|nil risk Highest risk value.
---@return table|nil mark Highest-risk mark.
function VigilantMarksClient:marksMeetMinimumRisk(marks, minimumRisk)
  local highestRisk, highestMark = self:getHighestRisk(marks)
  return self:riskMeetsMinimum(highestRisk, minimumRisk), highestRisk, highestMark
end

--- Normalizes a report before publishing.
--- Converts identifiers and images/videos aliases into imageUrls/videoLinks.
---@param report table|nil Raw report.
---@return table payload JSON body ready for POST /api/v1/marks/posts/publish.
function VigilantMarksClient:normalizeReport(report)
  report = report or {}

  local payload = self:normalizeIdentifiers(report)
  payload.message = trim(report.message)
  payload.imageUrls = normalizeArray(report.imageUrls or report.images)
  payload.videoLinks = normalizeArray(report.videoLinks or report.videos)

  return payload
end

--- Publishes a new report/post to Vigilant Marks.
--- Requires a valid API key with approved publish access.
--- The report must include message and at least one identifier.
---@param report table Report with message, identifiers, imageUrls/images, and videoLinks/videos.
---@param callback VigilantMarksCallback|nil Callback with standard response.
function VigilantMarksClient:publishReport(report, callback)
  callback = callback or function() end

  local payload = self:normalizeReport(report)

  if isBlank(payload.message) then
    callback({
      ok = false,
      status = 400,
      error = "message is required."
    })
    return
  end

  if not hasAnyIdentifier(payload) then
    callback({
      ok = false,
      status = 400,
      error = "At least one identifier is required."
    })
    return
  end

  self:request("POST", "/api/v1/marks/posts/publish", {
    body = payload
  }, callback)
end

--- Publishes a report using an online player's identifiers automatically.
--- Combines getPlayerIdentifiers(playerId), message, and evidence into one payload.
---@param playerId number FiveM server ID of the player.
---@param message string Report text.
---@param evidence table|function|nil Optional evidence: imageUrls/images, videoLinks/videos. Can be the callback when no evidence is provided.
---@param callback VigilantMarksCallback|nil Callback with standard response.
function VigilantMarksClient:publishPlayerReport(playerId, message, evidence, callback)
  if type(evidence) == "function" then
    callback = evidence
    evidence = {}
  end

  evidence = evidence or {}
  callback = callback or function() end

  local report = self:getPlayerIdentifiers(playerId)
  report.message = message
  report.imageUrls = evidence.imageUrls or evidence.images or {}
  report.videoLinks = evidence.videoLinks or evidence.videos or {}

  self:publishReport(report, callback)
end

--- Shared instance used by exports and available inside this resource.
VigilantMarks = VigilantMarksClient:new()

--- Export: returns the shared client instance.
--- Use this for class-like syntax from other resources.
exports("GetClient", function()
  return VigilantMarks
end)

--- Export: checks one or more manual identifiers.
---@param identifiers table Identifiers to check.
---@param callback VigilantMarksCallback|nil Callback with standard response.
exports("CheckIdentifiers", function(identifiers, callback)
  VigilantMarks:checkIdentifiers(identifiers, callback)
end)

--- Export: checks an online player from their FiveM identifiers.
---@param playerId number FiveM server ID of the player.
---@param callback VigilantMarksCallback|nil Callback with standard response.
exports("CheckPlayer", function(playerId, callback)
  VigilantMarks:checkPlayer(playerId, callback)
end)

--- Export: checks a single FiveM ID.
---@param fivemLicense string FiveM ID.
---@param callback VigilantMarksCallback|nil Callback with standard response.
exports("CheckFiveM", function(fivemLicense, callback)
  VigilantMarks:checkFiveM(fivemLicense, callback)
end)

--- Export: checks a single Discord ID.
---@param discordId string Discord ID.
---@param callback VigilantMarksCallback|nil Callback with standard response.
exports("CheckDiscord", function(discordId, callback)
  VigilantMarks:checkDiscord(discordId, callback)
end)

--- Export: checks a single license identifier.
---@param inGameLicense string License identifier.
---@param callback VigilantMarksCallback|nil Callback with standard response.
exports("CheckLicense", function(inGameLicense, callback)
  VigilantMarks:checkLicense(inGameLicense, callback)
end)

--- Export: checks a single Steam identifier.
---@param steamLicense string Steam identifier.
---@param callback VigilantMarksCallback|nil Callback with standard response.
exports("CheckSteam", function(steamLicense, callback)
  VigilantMarks:checkSteam(steamLicense, callback)
end)

--- Export: checks a single Xbox Live identifier.
---@param xboxLicense string Xbox Live identifier.
---@param callback VigilantMarksCallback|nil Callback with standard response.
exports("CheckXbox", function(xboxLicense, callback)
  VigilantMarks:checkXbox(xboxLicense, callback)
end)

--- Export: checks identifiers and returns a simplified callback.
---@param identifiers table Identifiers to check.
---@param callback VigilantMarksIsMarkedCallback|nil Callback with exists, marks, response.
exports("IsMarked", function(identifiers, callback)
  VigilantMarks:isMarked(identifiers, callback)
end)

--- Export: returns the highest risk found in a marks list.
---@param marks table|nil Marks returned by the Vigilant Marks API.
---@return string|nil risk Highest risk value.
---@return table|nil mark Highest-risk mark.
---@return number score Numeric risk score.
exports("GetHighestRisk", function(marks)
  return VigilantMarks:getHighestRisk(marks)
end)

--- Export: checks whether risk is equal to or higher than minimumRisk.
---@param risk string|nil Risk to test.
---@param minimumRisk string|nil Minimum accepted risk.
---@return boolean allowed True when risk meets or exceeds the minimum.
exports("RiskMeetsMinimum", function(risk, minimumRisk)
  return VigilantMarks:riskMeetsMinimum(risk, minimumRisk)
end)

--- Export: checks whether a marks list has at least one risk at minimumRisk or higher.
---@param marks table|nil Marks returned by the Vigilant Marks API.
---@param minimumRisk string|nil Minimum accepted risk.
---@return boolean allowed True when the highest mark risk meets or exceeds the minimum.
---@return string|nil risk Highest risk value.
---@return table|nil mark Highest-risk mark.
exports("MarksMeetMinimumRisk", function(marks, minimumRisk)
  return VigilantMarks:marksMeetMinimumRisk(marks, minimumRisk)
end)

--- Export: publishes a report/post through the API.
---@param report table Report with message and at least one identifier.
---@param callback VigilantMarksCallback|nil Callback with standard response.
exports("PublishReport", function(report, callback)
  VigilantMarks:publishReport(report, callback)
end)

--- Export: publishes a report using an online player's identifiers.
---@param playerId number FiveM server ID of the player.
---@param message string Report text.
---@param evidence table|function|nil Optional evidence or callback.
---@param callback VigilantMarksCallback|nil Callback with standard response.
exports("PublishPlayerReport", function(playerId, message, evidence, callback)
  VigilantMarks:publishPlayerReport(playerId, message, evidence, callback)
end)

--- Export: returns the player's normalized identifiers without calling the API.
---@param playerId number FiveM server ID of the player.
---@return table identifiers Normalized identifiers.
exports("GetPlayerVigilantIdentifiers", function(playerId)
  return VigilantMarks:getPlayerIdentifiers(playerId)
end)

if VigilantMarks.config.EnableTestCommand then
  RegisterCommand("vmcheck", function(source, args)
    local target = tonumber(args[1]) or source

    if target <= 0 then
      print("[VigilantMarks] Usage from console: vmcheck <serverId>")
      return
    end

    VigilantMarks:checkPlayer(target, function(response)
      if not response.ok then
        print(("[VigilantMarks] Check failed for %s: %s"):format(target, response.error or "unknown error"))
        return
      end

      if response.data and response.data.exists then
        local count = response.data.marks and #response.data.marks or 0
        print(("[VigilantMarks] %s is marked. Marks: %s"):format(target, count))
      else
        print(("[VigilantMarks] %s has no verified marks."):format(target))
      end
    end)
  end, true)
end

if VigilantMarks.config.CheckOnPlayerConnecting then
  AddEventHandler("playerConnecting", function(_, _, deferrals)
    local playerId = source

    deferrals.defer()
    Citizen.Wait(0)
    deferrals.update("Checking Vigilant Marks...")

    VigilantMarks:checkPlayer(playerId, function(response)
      if not response.ok then
        VigilantMarks:log("Join check failed:", response.error or "unknown error")
        deferrals.done()
        return
      end

      if response.data and response.data.exists and VigilantMarks.config.KickOnMarkedPlayer then
        local shouldKick, highestRisk, highestMark = VigilantMarks:marksMeetMinimumRisk(
          response.data.marks,
          VigilantMarks.config.KickMinimumRisk
        )

        if shouldKick then
          deferrals.done(formatKickMessage(VigilantMarks.config.KickMessage, highestRisk, highestMark))
          return
        end

        VigilantMarks:log(
          "Join check found marks but risk did not meet kick threshold:",
          highestRisk or "UNKNOWN",
          "minimum:",
          VigilantMarks.config.KickMinimumRisk or "LOW"
        )
        deferrals.done()
        return
      end

      deferrals.done()
    end)
  end)
end
