# DC Stash Builder

<p align="center">
  <strong>Création et gestion de coffres directement en jeu pour les serveurs FiveM ESX.</strong>
</p>

<p align="center">
  <img alt="FiveM" src="https://img.shields.io/badge/FiveM-Cerulean-orange">
  <img alt="Framework" src="https://img.shields.io/badge/Framework-ESX-blue">
  <img alt="Lua" src="https://img.shields.io/badge/Langage-Lua-2C2D72">
  <img alt="Version" src="https://img.shields.io/badge/Version-1.4.0-brightgreen">
</p>

**DC Stash Builder** permet aux administrateurs de créer, modifier, déplacer et supprimer des coffres sans éditer de fichier de configuration ni redémarrer le serveur. Les coffres sont sauvegardés en base de données et synchronisés automatiquement avec les joueurs.

## Fonctionnalités

- création de coffres directement à la position de l’administrateur ;
- interface de configuration avec `ox_lib` ;
- interactions en jeu avec `ox_target` ;
- stockage persistant avec `oxmysql` ;
- modification, déplacement et suppression des coffres existants ;
- nombre d’emplacements, poids maximal et distance configurables ;
- sélection de plusieurs métiers avec un grade minimal différent pour chacun ;
- trois modes d’accès : public, métier ou personnel ;
- synchronisation automatique des zones pour tous les joueurs ;
- détection automatique de l’inventaire configuré ;
- prise en charge de `ox_inventory` ;
- prise en charge de la version récente de `qs-inventory` via son export serveur `RegisterStash` ;
- validation des données, contrôle de proximité et limitation des appels côté serveur ;
- commandes et téléportation réservées aux groupes administrateurs autorisés.

## Modes d’accès

| Mode | Fonctionnement |
|---|---|
| Public | Tous les joueurs peuvent ouvrir le coffre. |
| Métier | Seuls les métiers et grades configurés peuvent l’ouvrir. |
| Personnel | Chaque joueur possède un contenu distinct dans le même coffre. |

Les autorisations d’ouverture sont toujours vérifiées côté serveur.

## Prérequis

- [ESX Legacy](https://github.com/esx-framework/esx_core)
- [ox_lib](https://github.com/communityox/ox_lib)
- [ox_target](https://github.com/communityox/ox_target)
- [oxmysql](https://github.com/communityox/oxmysql)
- [ox_inventory](https://github.com/communityox/ox_inventory) ou une version compatible de `qs-inventory`
- OneSync recommandé pour le contrôle de proximité côté serveur

## Installation

1. Téléchargez ou clonez cette ressource dans le dossier `resources` de votre serveur.
2. Importez [`sql/dc_stashes.sql`](sql/dc_stashes.sql) dans votre base de données.
3. Modifiez [`config.lua`](config.lua) selon vos besoins.
4. Ajoutez les ressources à votre `server.cfg` dans cet ordre :

```cfg
ensure oxmysql
ensure ox_lib
ensure es_extended
ensure ox_target
ensure ox_inventory
ensure DC_Stashbuilder
```

Si vous utilisez `qs-inventory`, démarrez-le à la place de `ox_inventory` et définissez l’inventaire correspondant dans la configuration.

## Configuration

### Groupes administrateurs

Seuls les groupes ESX déclarés ici peuvent créer, modifier ou supprimer des coffres :

```lua
Config.AllowedGroups = {
    admin = true,
    superadmin = true
}
```

### Valeurs par défaut

```lua
Config.DefaultSlots = 50
Config.DefaultWeight = 100000 -- grammes
Config.DefaultDistance = 2.0
```

Les limites réellement appliquées côté serveur sont personnalisables avec `Config.Limits`. `Config.ServerDistanceTolerance` ajoute une petite marge au contrôle de proximité afin d’éviter les refus dus à la latence.

### Inventaire

```lua
-- Valeurs disponibles : 'auto', 'ox' ou 'qs'
Config.Inventory = 'auto'
```

Avec `auto`, `ox_inventory` est utilisé en priorité lorsque les deux inventaires sont démarrés.

Pour `qs-inventory`, `Config.QSStashPrefix` définit le préfixe appliqué aux identifiants de coffres. Conservez la valeur `Stash_` sauf si votre version utilise une autre convention.

### Commandes

```lua
Config.Commands = {
    create = 'stashcreate',
    manage = 'managestash'
}
```

| Commande | Description |
|---|---|
| `/stashcreate` | Ouvre le formulaire de création à la position actuelle. |
| `/managestash` | Affiche la liste des coffres et leurs actions de gestion. |

## Utilisation

### Créer un coffre

1. Placez-vous à l’endroit souhaité.
2. Exécutez `/stashcreate`.
3. Choisissez un identifiant unique et un label.
4. Configurez les emplacements, le poids et la distance d’interaction.
5. Sélectionnez le mode d’accès et, si nécessaire, les métiers autorisés.
6. Validez le formulaire.

Pour appliquer un grade différent à certains métiers, utilisez le format suivant :

```text
police:2, ambulance:0
```

Les métiers sans règle personnalisée utilisent le grade par défaut du formulaire.

### Gérer les coffres

La commande `/managestash` permet de :

- modifier les paramètres d’un coffre ;
- déplacer le coffre à votre position actuelle ;
- vous téléporter jusqu’au coffre ;
- supprimer sa définition.

> La suppression d’un coffre retire sa définition et sa zone d’interaction. Le contenu enregistré par l’inventaire n’est pas supprimé automatiquement.

## Structure

```text
DC_Stashbuilder/
├── client/
│   └── main.lua
├── server/
│   └── main.lua
├── sql/
│   └── dc_stashes.sql
├── config.lua
├── fxmanifest.lua
└── README.md
```

## Dépannage

### Les zones n’apparaissent pas

- vérifiez que `ox_target` et `ox_lib` sont démarrés avant la ressource ;
- vérifiez que la table `dc_stashes` existe ;
- consultez la console serveur pour repérer une erreur SQL ou d’inventaire.

### Le coffre ne s’ouvre pas

- vérifiez la valeur de `Config.Inventory` ;
- contrôlez que l’inventaire sélectionné est bien démarré ;
- pour un coffre de métier, vérifiez le nom exact du métier ESX et le grade du joueur.

### L’intégration qs-inventory ne fonctionne pas

Cette ressource cible l’API récente utilisant l’export serveur `RegisterStash(source, stashId, slots, weight)`. Les anciennes éditions de `qs-inventory` peuvent utiliser une signature différente : vérifiez la documentation correspondant précisément à votre version.

## Contribution

Les signalements de bugs et les propositions d’amélioration sont les bienvenus. Pour une contribution importante, ouvrez d’abord une issue afin de présenter votre idée.

## MIT Licence

## Auteur

Développé par **DellieCode**.
