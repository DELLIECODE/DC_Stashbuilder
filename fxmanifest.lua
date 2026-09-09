fx_version 'cerulean'
game 'gta5'

author 'DELLIECODE'
description 'In-game Stash Builder (admin create) with ox_lib menu + job/public access'
version '1.4.0'

shared_scripts {
  '@ox_lib/init.lua',
  'config.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/main.lua'
}


client_scripts { 'client/main.lua' }

dependencies {
  'ox_target',
  'ox_lib',
  'oxmysql',
  'es_extended'
}
