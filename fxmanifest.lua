fx_version "cerulean"
game "gta5"
lua54 "yes"

author "Vigilant Marks"
description "Server-side FiveM wrapper for the Vigilant Marks API"
version "1.0.0"

server_only "yes"

server_scripts {
  "config.lua",
  "server/vigilantmarks.lua"
}
