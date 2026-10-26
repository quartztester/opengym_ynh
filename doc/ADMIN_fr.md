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

## Connexion SSO depuis le portail (bascule du panneau de config, désactivée par défaut)

Panneau de configuration → *Connexion SSO portail* → activer. Les utilisateurs
authentifiés au portail qui ouvrent `https://<domaine>/ynh-sso-login` arrivent
directement dans leur profil openGym ; avec la provisioning automatique, le
profil est créé à la première visite via l'API d'invitation de l'application.
Activer la fonction bascule aussi `PASSWORD_LOGIN` de l'application (désactivé
par défaut amont) ; le mot de passe initial partagé sert de preuve dans les
réglages — chaque utilisateur doit ensuite ajouter son propre passkey. Les
profils existants (créés via la connexion propre à l'application avant
l'activation) sont repris par nom exact à la première visite.

Le point de fabrication du cookie ne répond que si SSOwat a injecté à la fois
l'identité `YNH_USER` et la preuve Basic-Auth pour cette URI exacte (permission
dédiée auth_header ; la permission principale reste sans injection). Le code
est entièrement côté paquet (une location nginx, un fichier lua et une petite
unité systemd de surveillance des ACL, sous le nom de l'application) — le code
d'openGym n'est jamais patché, les mises à jour amont ne peuvent pas entrer en
conflit. L'application réécrit ses fichiers de données en mode 0600 à chaque
sauvegarde ; une unité systemd path réouvre le masque ACL dont la route a
besoin juste après chaque écriture. Si un futur changement de format de cookie
cassait la route SSO, la connexion par passkey continuerait de fonctionner.

À retenir : le PREMIER compte créé — par SSO ou à la main — devient
administrateur (`FIRST_USER_ADMIN`). Pour confier l'administration à un
utilisateur du portail précis, faites-le s'inscrire d'abord via la connexion
propre à l'application ; quiconque passe par l'SSO avant lui deviendra
propriétaire.
