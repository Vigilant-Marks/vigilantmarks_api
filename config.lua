VigilantMarksConfig = {
  BaseUrl = GetConvar("vigilantmarks_base_url", "https://vigilantmarks.com"),
  ApiKey = GetConvar("vigilantmarks_api_key", ""),

  RequestTimeoutMs = 10000,
  Debug = false,

  -- Optional join-time check. Keep disabled until you decide your server policy.
  CheckOnPlayerConnecting = false,
  KickOnMarkedPlayer = false,
  KickMinimumRisk = GetConvar("vigilantmarks_kick_minimum_risk", "HIGH"), -- LOW, MEDIUM, HIGH
  KickMessage = "Your account is listed on Vigilant Marks. Risk level: {risk}.",

  -- Optional admin test command: /vmcheck [serverId]
  EnableTestCommand = false
}
