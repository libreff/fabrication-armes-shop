# Fabrication d'armes Shop

Boutique clandestine immersive pour ESX utilisant `ox_lib`, `ox_target` et `acn_inventory`.

## Installation

1. Placez `fabrication_armes_shop` dans les ressources du serveur.
2. Vérifiez l'existence de `money_item` et `schémassnspistol` dans `acn_inventory`.
3. Ajoutez `ensure fabrication_armes_shop` au `server.cfg`.
4. Utilisez `/gunshopcreator` avec un groupe ESX autorisé.

## Créateur

Le créateur permet de placer ou replacer la Voyante et la Baronne au raycast, choisir leurs modèles, régler leur rotation, les supprimer et modifier le prix ainsi que les identifiants des items.

- `E` : valider le placement.
- Flèches gauche/droite : régler la rotation.
- Retour arrière : annuler.

Les réglages sont sauvegardés dans `data/config.json`. La progression des voix obligatoires est sauvegardée par licence dans `data/voices.json`.

## Voix

La première écoute de chaque voix est obligatoire. À partir de la deuxième écoute, le joueur peut la passer avec `ESPACE` par défaut. La touche est configurable dans `Config.Voice` et dans les paramètres de touches FiveM.
