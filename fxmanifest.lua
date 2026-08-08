fx_version 'cerulean'
game 'gta5'

author 'La Quica'
description "Fabrication d'armes Shop - Voyante et Baronne"
version '1.0.0'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_script 'client/main.lua'
server_script 'server/main.lua'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'web/audio/*.mp3'
}

dependencies {
    'es_extended',
    'ox_lib',
    'ox_target',
    'acn_inventory'
}
