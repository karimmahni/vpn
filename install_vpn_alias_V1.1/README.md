openvpn-stunnel-installer (v1.1)



Script d’installation automatisée permettant de :



Installer OpenVPN, Stunnel4 et les dépendances nécessaires



Configurer Stunnel en mode client (TLS/SSL → port 443)



Lancer OpenVPN sans modifier le fichier .ovpn d’origine



Établir un tunnel TLS entre la machine client et le serveur VPN



Créer automatiquement des alias shell (vpn-start, vpn-stop, vpn-status, etc.)



Assurer un fonctionnement cohérent avec ou sans sudo



Générer les alias dans le HOME réel de l’utilisateur, même si le script est exécuté via sudo



Fonctionnalités principales



Compatible Debian / Ubuntu



Ne modifie pas définitivement le fichier .ovpn (patch réversible + backup auto)



Installation automatique des dépendances (openvpn, stunnel4, curl)



Configuration complète de Stunnel en mode client TLS



Démarrage OpenVPN en daemon + logs dédiés



Détection des erreurs OpenVPN (AUTH, TLS, refus de connexion, DNS, réseau…)



Création d’alias Bash et Zsh :



vpn-start



vpn-stop



vpn-restart



vpn-status



stunnel-start



stunnel-stop



stunnel-status



Gestion correcte des permissions via REAL\_USER / REAL\_HOME



Support de PAM (sudo -v) lorsque lancé sans sudo



1\. Prérequis

Élément	Détail

OS	Debian / Ubuntu (APT + systemd)

Droits	L’utilisateur doit appartenir au groupe sudo

Fichier VPN	Un fichier .ovpn présent dans le même répertoire que le script

Connectivité	Accès au port 443 du serveur VPN

Recommandé	dos2unix si le script provient de Windows

Shell	Bash ou Zsh

2\. Installation



Placer le script dans le même dossier que votre fichier .ovpn.



Si le script provient de Windows

sudo apt install dos2unix -y

dos2unix vpn\_install\_alias\_v1.1.sh



Rendre le script exécutable

chmod +x vpn\_install\_alias\_v1.1.sh



Exécution recommandée

sudo ./vpn\_install\_alias\_v1.1.sh



Ou en mode utilisateur (PAM demandera le mot de passe au début)

./vpn\_install\_alias\_v1.1.sh





Le script utilisera automatiquement sudo uniquement lorsque nécessaire et générera les alias dans le HOME réel de l’utilisateur, y compris en exécution via sudo.



3\. Alias générés automatiquement



Une fois l’installation terminée, les commandes suivantes deviennent disponibles :



Commande	Action

vpn-start	Démarre Stunnel + OpenVPN

vpn-stop	Arrête uniquement OpenVPN

vpn-restart	Redémarre Stunnel + OpenVPN

vpn-status	Affiche l’état du tunnel TLS, d’OpenVPN, l’IP publique et l’interface tun

stunnel-start	Démarre Stunnel

stunnel-stop	Arrête Stunnel

stunnel-status	Affiche l’état du service Stunnel



Les alias sont stockés dans :



~/.config/shell/aliases-vpn.sh





Et chargés automatiquement via :



~/.bashrc



~/.zshrc



4\. Fonctionnement interne

4.1 Détection de l’utilisateur réel



Le script identifie l’utilisateur final, quel que soit le mode d’exécution :



Exécution directe



Exécution via sudo



Appel depuis un environnement automatisé



Variables utilisées :



REAL\_USER



REAL\_HOME



4.2 Installation des dépendances



Le script vérifie la présence de :



openvpn



stunnel4



curl



et installe automatiquement les paquets manquants via APT.



4.3 Configuration de Stunnel



Génération automatique du fichier : /etc/stunnel/stunnel.conf



Activation du service



Vérification du port local : 127.0.0.1:1194



4.4 Démarrage d’OpenVPN



Utilise le fichier .ovpn d’origine



Génère un log dédié : /var/log/openvpn\_client.log



Détecte automatiquement l’interface tunX



Analyse les erreurs possibles :



AUTH\_FAILED



TLS handshake error



Connection refused



DNS resolve error



Network unreachable



4.5 Création d’alias



Création du dossier : ~/.config/shell/



Permissions adaptées (600 / 644)



Chargement automatique dans :



.bashrc



.zshrc



Compatible login-shell via .profile



5\. Désinstallation



Supprimer les alias :



rm -rf ~/.config/shell

sed -i '/aliases-vpn.sh/d' ~/.bashrc 2>/dev/null

sed -i '/aliases-vpn.sh/d' ~/.zshrc 2>/dev/null





Supprimer OpenVPN + Stunnel :



sudo apt remove --purge openvpn stunnel4 -y

sudo rm -rf /etc/stunnel /var/log/stunnel4 /run/stunnel4



6\. Notes



Non compatible avec CentOS, Arch, macOS ou Windows.



Le fichier .ovpn n’est jamais modifié définitivement (backup automatique).



Les logs se trouvent dans :



/var/log/stunnel4/



/var/log/openvpn\_client.log

