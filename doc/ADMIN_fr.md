Les comptes et les passkeys vivent dans openGym (pas d'identité LDAP/SSO).
La permission YunoHost décide qui atteint la page — ne pas ouvrir `visitors`
sauf si vous voulez une inscription anonyme. Données : le dossier de données
de l'application, en fichiers simples.

## Réglages notables

- **Médias des exercices** — l'installeur peut télécharger une fois le jeu de
  données d'illustrations (~350 Mo, question à l'installation). Sans lui
  l'application fonctionne mais affiche les exercices sans image. Les images
  sont (c) GymVisual, utilisées sous les conditions du jeu de données.
- **Comptes** — le premier compte créé dans l'application en devient
  l'administrateur (`FIRST_USER_ADMIN=1`). La permission YunoHost sur l'URL
  (défaut : `all_users`) est une porte d'accès, pas l'identité applicative ;
  les inscriptions peuvent être verrouillées par codes d'invitation dans les
  réglages admin d'openGym.

## Mises à jour

Les mises à jour montent `version` et `sources.main` (URL et sha256)
ensemble. La sauvegarde standard YunoHost suffit : utilisateurs, envois, secret
de session et clés VAPID sont des fichiers simples sous le dossier de données.
