# vigilantmarks_api

Server-side FiveM resource for using the [Vigilant Marks API](https://vigilantmarks.com/apidocumentation) from Lua.

The API key is read from a server convar so it does not need to be committed in
the resource files.

Marked players are those where their post report for a mark has been verified.

## Install

1. Copy `vigilantmarks_api` into your FiveM server resources folder.
2. Add this to `server.cfg`:

```cfg
set vigilantmarks_api_key "YOUR_API_KEY"
ensure vigilantmarks_api
```

Optional:

```cfg
set vigilantmarks_base_url "https://vigilantmarks.com"
```

## Lookup Examples

Check a connected player by their FiveM identifiers:

```lua
exports.vigilantmarks_api:CheckPlayer(source, function(response)
  if not response.ok then
    print(("Vigilant Marks error: %s"):format(response.error or "unknown error"))
    return
  end

  if response.data.exists then
    print(("Player has %s verified mark(s)."):format(#response.data.marks))
  else
    print("Player has no verified marks.")
  end
end)
```

Check one or more identifiers manually:

```lua
exports.vigilantmarks_api:CheckIdentifiers({
  discord = "123456789012345678",
  fivem = "123456",
  license = "abcdef123456"
}, function(response)
  if response.ok and response.data.exists then
    for _, mark in ipairs(response.data.marks) do
      print(("[%s] %s - %s"):format(mark.risk, mark.reason or "No reason", mark.post))
    end
  end
end)
```

Shortcut helpers are also available:

```lua
exports.vigilantmarks_api:CheckFiveM("123456", callback)
exports.vigilantmarks_api:CheckDiscord("123456789012345678", callback)
exports.vigilantmarks_api:CheckLicense("abcdef123456", callback)
exports.vigilantmarks_api:CheckSteam("110000112345678", callback)
exports.vigilantmarks_api:CheckXbox("000900000000000", callback)
```

## Publish Examples

Publishing requires an API key that has approved publishing access on Vigilant
Marks.

```lua
exports.vigilantmarks_api:PublishReport({
  message = "Cheating evidence from my server.",
  fivem = "123456",
  discord = "123456789012345678",
  imageUrls = {
    "https://example.com/evidence.png"
  },
  videoLinks = {}
}, function(response)
  if response.ok then
    print(("Report published: %s"):format(response.data.link))
  else
    print(("Publish failed: %s"):format(response.error or "unknown error"))
  end
end)
```

Publish a report for the current player identifiers:

```lua
exports.vigilantmarks_api:PublishPlayerReport(source, "Trolling evidence.", {
  videos = { "https://example.com/clip.mp4" }
}, function(response)
  print(response.ok and response.data.link or response.error)
end)
```

## Class-like Usage

Inside the resource runtime you can use the shared object:

```lua
VigilantMarks:checkPlayer(source, function(response)
  -- response.ok, response.status, response.data, response.error
end)
```

Or get it from another server-side resource:

```lua
local vm = exports.vigilantmarks_api:GetClient()

vm:isMarked({ fivem = "123456" }, function(exists, marks, response)
  if exists then
    print(("Marked: %s"):format(#marks))
  end
end)
```

## Function Reference

### Exports for Other Resources

Use these from another server-side FiveM resource with
`exports.vigilantmarks_api:<FunctionName>(...)`.

#### `GetClient()`

Returns the shared `VigilantMarks` client object.

Use this when you prefer class-like syntax instead of calling exports directly.

```lua
local vm = exports.vigilantmarks_api:GetClient()
vm:checkFiveM("123456", function(response)
  print(response.ok)
end)
```

#### `CheckIdentifiers(identifiers, callback)`

Checks Vigilant Marks for one or more identifiers.

Accepted identifier keys:

- `discord` or `discordId`
- `fivem` or `fivemLicense`
- `license` or `inGameLicense`
- `steam` or `steamLicense`
- `xbox`, `live`, or `xboxLicense`

The function normalizes values like `fivem:123456` into `123456` before sending
the request.

```lua
exports.vigilantmarks_api:CheckIdentifiers({
  discord = "123456789012345678",
  fivem = "fivem:123456",
  license = "license:abcdef"
}, function(response)
  if response.ok and response.data.exists then
    print("At least one mark was found.")
  end
end)
```

#### `CheckPlayer(playerId, callback)`

Reads the identifiers of an online FiveM player with `GetPlayerIdentifiers`,
converts them to the Vigilant Marks API format, and checks if any verified mark
exists for that player.

This is the easiest method to use when you already have a FiveM server ID such
as `source`.

```lua
exports.vigilantmarks_api:CheckPlayer(source, function(response)
  if response.ok and response.data.exists then
    print("This player is listed on Vigilant Marks.")
  end
end)
```

#### `CheckFiveM(fivemLicense, callback)`

Checks a single FiveM identifier.

You can pass either `123456` or `fivem:123456`; the prefix is removed
automatically.

```lua
exports.vigilantmarks_api:CheckFiveM("fivem:123456", callback)
```

#### `CheckDiscord(discordId, callback)`

Checks a single Discord user ID.

You can pass either `123456789012345678` or
`discord:123456789012345678`.

```lua
exports.vigilantmarks_api:CheckDiscord("123456789012345678", callback)
```

#### `CheckLicense(inGameLicense, callback)`

Checks a single GTA/FiveM `license:` identifier.

You can pass either the raw license value or a value with the `license:` prefix.

```lua
exports.vigilantmarks_api:CheckLicense("license:abcdef123456", callback)
```

#### `CheckSteam(steamLicense, callback)`

Checks a single Steam identifier.

You can pass either the raw Steam value or a value with the `steam:` prefix.

```lua
exports.vigilantmarks_api:CheckSteam("steam:110000112345678", callback)
```

#### `CheckXbox(xboxLicense, callback)`

Checks a single Xbox Live identifier.

You can pass `xbox:...`, `live:...`, or the raw value.

```lua
exports.vigilantmarks_api:CheckXbox("live:000900000000000", callback)
```

#### `IsMarked(identifiers, callback)`

Convenience wrapper around `CheckIdentifiers`.

Instead of making you inspect `response.data.exists`, it passes three values to
the callback:

- `exists`: `true` when at least one verified mark was found.
- `marks`: the mark list, or an empty table.
- `response`: the full response object.

```lua
exports.vigilantmarks_api:IsMarked({ fivem = "123456" }, function(exists, marks, response)
  if exists then
    print(("Found %s mark(s)."):format(#marks))
  elseif not response.ok then
    print(response.error)
  end
end)
```

#### `GetHighestRisk(marks)`

Returns the highest risk found in a list of marks returned by the API.

Risk order:

```text
LOW < MEDIUM < HIGH
```

Returns:

- `risk`: highest risk value.
- `mark`: the mark object that produced that risk.
- `score`: numeric score, where `LOW = 1`, `MEDIUM = 2`, `HIGH = 3`.

```lua
exports.vigilantmarks_api:CheckFiveM("123456", function(response)
  if response.ok and response.data.exists then
    local risk, mark = exports.vigilantmarks_api:GetHighestRisk(response.data.marks)
    print(risk, mark and mark.post)
  end
end)
```

#### `RiskMeetsMinimum(risk, minimumRisk)`

Checks whether one risk is equal to or higher than a configured threshold.

```lua
local shouldAct = exports.vigilantmarks_api:RiskMeetsMinimum("HIGH", "MEDIUM")
-- true
```

#### `MarksMeetMinimumRisk(marks, minimumRisk)`

Checks whether the highest risk in a marks list meets the selected threshold.

Returns:

- `allowed`: `true` when the highest mark risk meets the threshold.
- `risk`: highest risk value.
- `mark`: highest-risk mark.

```lua
exports.vigilantmarks_api:CheckPlayer(source, function(response)
  if response.ok and response.data.exists then
    local allowed, risk, mark =
      exports.vigilantmarks_api:MarksMeetMinimumRisk(response.data.marks, "HIGH")

    if allowed then
      print(("High-risk player found: %s"):format(mark.post))
    end
  end
end)
```

#### `PublishReport(report, callback)`

Publishes a new report/post through the Vigilant Marks API.

This requires an API key with approved publishing access. The report must
include:

- `message`: required text, 1-200 characters.
- at least one identifier: `discord`, `fivem`, `license`, `steam`, or `xbox`.
- `imageUrls`: optional table of image URLs.
- `videoLinks`: optional table of video URLs.

Aliases `images` and `videos` are accepted and converted to `imageUrls` and
`videoLinks`.

```lua
exports.vigilantmarks_api:PublishReport({
  message = "Cheating evidence from my server.",
  fivem = "123456",
  discord = "123456789012345678",
  images = { "https://example.com/evidence.png" },
  videos = {}
}, function(response)
  if response.ok then
    print(response.data.link)
  else
    print(response.error)
  end
end)
```

#### `PublishPlayerReport(playerId, message, evidence, callback)`

Builds a report using the identifiers of an online player, then publishes it.

Parameters:

- `playerId`: FiveM server ID, usually `source`.
- `message`: report text.
- `evidence`: optional table with `imageUrls`, `images`, `videoLinks`, or
  `videos`.
- `callback`: receives the standard response object.

```lua
exports.vigilantmarks_api:PublishPlayerReport(source, "Trolling evidence.", {
  videos = { "https://example.com/clip.mp4" }
}, function(response)
  print(response.ok and response.data.link or response.error)
end)
```

#### `GetPlayerVigilantIdentifiers(playerId)`

Returns the player's identifiers in the format used by the Vigilant Marks API,
without making an HTTP request.

This is useful if you want to inspect, log, cache, or modify the identifiers
before checking or publishing.

```lua
local identifiers = exports.vigilantmarks_api:GetPlayerVigilantIdentifiers(source)
print(json.encode(identifiers))
```

### Client Object Methods

These methods are available on the object returned by `GetClient()` and on the
shared `VigilantMarks` object inside this resource.

#### `VigilantMarksClient:new(options)`

Creates a new client instance.

`options` can override the values from `config.lua`, such as `BaseUrl`,
`ApiKey`, `RequestTimeoutMs`, or `Debug`.

```lua
local customClient = VigilantMarksClient:new({
  BaseUrl = "https://vigilantmarks.com",
  ApiKey = "YOUR_API_KEY",
  Debug = true
})
```

Most servers should use the shared client instead of creating new instances.

#### `setApiKey(apiKey)`

Changes the API key used by the client and returns the client itself.

This is useful for advanced setups where the key is loaded dynamically.

```lua
local vm = exports.vigilantmarks_api:GetClient()
vm:setApiKey("NEW_API_KEY")
```

#### `setBaseUrl(baseUrl)`

Changes the API base URL and returns the client itself.

Useful for testing against a staging or local Vigilant Marks deployment.

```lua
vm:setBaseUrl("http://localhost:3000")
```

#### `log(...)`

Prints debug output only when `Debug = true` in `config.lua` or in the client
options.

You normally do not need to call this directly.

#### `normalizeIdentifiers(identifiers)`

Converts flexible identifier keys and prefixed values into the exact API fields.

Example input:

```lua
{
  fivem = "fivem:123456",
  license = "license:abcdef"
}
```

Example output:

```lua
{
  fivemLicense = "123456",
  inGameLicense = "abcdef"
}
```

#### `getPlayerIdentifiers(playerId)`

Reads identifiers from FiveM's `GetPlayerIdentifiers(playerId)` and returns a
normalized table ready for Vigilant Marks.

It maps:

- `discord:` to `discordId`
- `fivem:` to `fivemLicense`
- `license:` to `inGameLicense`
- `steam:` to `steamLicense`
- `live:` to `xboxLicense`

#### `buildQuery(params)`

Builds the query string used by `GET /api/v1/marks`.

You normally do not call this directly; `checkIdentifiers` uses it internally.

#### `request(method, path, options, callback)`

Low-level HTTP wrapper around FiveM's `PerformHttpRequest`.

It handles:

- `Authorization: Bearer <api key>`
- JSON request bodies.
- JSON response parsing.
- timeout handling.
- normalized success/error response shape.

Use this only if Vigilant Marks adds another endpoint and you want to call it
before a dedicated helper exists.

```lua
vm:request("GET", "/api/v1/marks", {
  query = { fivem = "123456" }
}, callback)
```

#### `checkIdentifiers(identifiers, callback)`

Object-method version of the `CheckIdentifiers` export.

Checks one or more identifiers and returns the standard response object.

#### `checkPlayer(playerId, callback)`

Object-method version of the `CheckPlayer` export.

Reads identifiers from an online player and checks Vigilant Marks.

#### `checkFiveM(fivemLicense, callback)`

Object-method version of the `CheckFiveM` export.

Checks one FiveM ID.

#### `checkDiscord(discordId, callback)`

Object-method version of the `CheckDiscord` export.

Checks one Discord ID.

#### `checkLicense(inGameLicense, callback)`

Object-method version of the `CheckLicense` export.

Checks one `license:` identifier.

#### `checkSteam(steamLicense, callback)`

Object-method version of the `CheckSteam` export.

Checks one Steam identifier.

#### `checkXbox(xboxLicense, callback)`

Object-method version of the `CheckXbox` export.

Checks one Xbox Live identifier.

#### `isMarked(identifiers, callback)`

Object-method version of the `IsMarked` export.

Returns simplified callback values: `exists`, `marks`, and `response`.

#### `getHighestRisk(marks)`

Object-method version of the `GetHighestRisk` export.

Finds the highest risk in a marks list.

#### `riskMeetsMinimum(risk, minimumRisk)`

Object-method version of the `RiskMeetsMinimum` export.

Checks one risk against a minimum threshold.

#### `marksMeetMinimumRisk(marks, minimumRisk)`

Object-method version of the `MarksMeetMinimumRisk` export.

Checks a full marks list against a minimum threshold.

#### `normalizeReport(report)`

Converts a flexible report table into the JSON body expected by
`POST /api/v1/marks/posts/publish`.

It normalizes identifiers, trims the `message`, and converts `images`/`videos`
aliases into `imageUrls`/`videoLinks`.

#### `publishReport(report, callback)`

Object-method version of the `PublishReport` export.

Validates that a message and at least one identifier exist, then publishes the
report.

#### `publishPlayerReport(playerId, message, evidence, callback)`

Object-method version of the `PublishPlayerReport` export.

Reads the player's identifiers, adds your report message and evidence URLs, then
publishes the report.

## Optional Join Check

In `config.lua`, you can enable automatic checks during `playerConnecting`.
Default behavior is safe: it checks nothing and kicks nobody until enabled.

```lua
CheckOnPlayerConnecting = true
KickOnMarkedPlayer = true
KickMinimumRisk = "HIGH"
KickMessage = "Your account is listed on Vigilant Marks."
```

`KickMinimumRisk` controls which marked players are kicked:

- `LOW`: kick any marked player.
- `MEDIUM`: kick only `MEDIUM` or `HIGH` risk players.
- `HIGH`: kick only `HIGH` risk players.

The kick message supports placeholders:

```lua
KickMessage = "Your account is listed on Vigilant Marks. Risk: {risk}. Post: {post}"
```

Available placeholders:

- `{risk}`
- `{reason}`
- `{post}`

## Response Shape

Every API wrapper callback receives:

```lua
{
  ok = true or false,
  status = 200,
  data = {},      -- decoded JSON when available
  body = "...",   -- raw body
  headers = {},
  error = nil,    -- string when ok is false
  details = nil,
  endpoint = "https://vigilantmarks.com/api/..."
}
```
