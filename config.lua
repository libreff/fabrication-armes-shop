Config = {}

Config.Inventory = 'acn_inventory'

Config.Commands = {
    creator = 'armescreator'
}

Config.AdminGroups = {
    admin = true,
    superadmin = true,
    owner = true,
    fondateur = true,
    responsable = true
}

Config.Creator = {
    raycastDistance = 35.0,
    raycastFlags = 497,
    rotationStep = 5.0,
    previewAlpha = 165
}

Config.Interaction = {
    targetDistance = 2.2,
    serverValidationDistance = 4.0
}

Config.Defaults = {
    voyanteModel = 'a_f_o_soucent_02',
    baronneModel = 'a_f_y_business_04',
    moneyItem = 'money_item',
    schemaItem = 'schémassnspistol',
    schemaPrice = 15000
}

Config.Voice = {
    skipCommand = 'armes_skip_voice',
    skipKey = 'SPACE',
    skipLabel = 'ESPACE',
    completionTolerance = 3,
    durations = {
        voyante_intro = 3,
        voyante_joueur_oui = 11,
        voyante_joueur_non = 23,
        baronne_intro = 98,
        baronne_achat_schema_sns = 60,
        baronne_sans_achat = 15
    }
}

Config.Locale = {
    voyanteTarget = 'Parler à la Voyante',
    baronneTarget = 'Parler à la Baronne',
    noPermission = "Vous n'avez pas la permission ESX nécessaire.",
    creatorSaved = 'Configuration sauvegardée.',
    creatorDeleted = 'PNJ supprimé du créateur.',
    creatorRaycast = '[E] Valider  |  [←/→] Rotation  |  [Retour] Annuler',
    purchaseSuccess = 'Le schéma SNS Pistol a été ajouté à votre inventaire.',
    purchaseFailed = 'Achat impossible.',
    inventoryFull = "Vous n'avez pas assez de place dans votre inventaire.",
    tooFar = 'Vous êtes trop loin de la Baronne.'
}
