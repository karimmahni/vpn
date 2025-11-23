Installation du Service VPN (stunnel + OpenVPN)
1. Objectif

Ce document décrit la procédure d’installation automatisée du service vpn.service, basé sur :

un script local (vpn_install_alias_v1.1.sh)

une configuration OpenVPN (.ovpn) située dans le même dossier

un installeur (install_vpn_service.sh) qui crée, configure et active le service systemd.

L’ensemble permet de déployer le VPN sur n’importe quel poste Linux de manière standardisée.

2. Prérequis

Système Linux Debian/Ubuntu

Accès root (sudo)

Paquets installés :

openvpn

stunnel4 (si utilisé dans le script)

systemd (par défaut sur Debian/Ubuntu)

3. Fichiers nécessaires

Placer dans un même dossier (exemple : /opt/scripts/):

vpn_install_alias_v1.1.sh

<configuration>.ovpn

install_vpn_service.sh (script installeur)

Exemple d’arborescence :

/opt/scripts/
 ├── vpn_install_alias_v1.1.sh
 ├── client.ovpn
 └── install_vpn_service.sh

4. Installation
Étape 1 : Donner les permissions
sudo chmod +x /opt/scripts/install_vpn_service.sh
sudo chmod +x /opt/scripts/vpn_install_alias_v1.1.sh

Étape 2 : Lancer l’installation
cd /opt/scripts
sudo ./install_vpn_service.sh

Étape 3 : Répondre aux questions

Lorsque le script demande :

Chemin complet du script VPN :


répondre :

/opt/scripts/vpn_install_alias_v1.1.sh


L’installeur :

détecte automatiquement le fichier .ovpn dans le dossier,

génère /etc/systemd/system/vpn.service,

effectue un reset propre de tout ancien service VPN,

active et démarre automatiquement le nouveau service.

5. Vérification

Pour vérifier le statut du service :

systemctl status vpn.service


Pour voir si OpenVPN tourne :

ps aux | grep openvpn

6. Commandes utilisateur (aliases)

Une fois le script d’installation exécuté, les commandes suivantes deviennent disponibles dans la session utilisateur :

vpn-start      → démarre stunnel + OpenVPN
vpn-stop       → arrête le VPN
vpn-restart    → redémarre VPN + stunnel
vpn-status     → affiche l’état du VPN, de l’IP et de l’interface tun
stunnel-start  → démarre stunnel
stunnel-stop   → arrête stunnel
stunnel-status → état de stunnel


Pour activer les alias dans la session :

source ~/.bashrc    # ou ~/.zshrc selon le shell utilisé

7. Désinstallation

Pour retirer proprement le service :

sudo systemctl stop vpn.service
sudo systemctl disable vpn.service
sudo rm /etc/systemd/system/vpn.service
sudo systemctl daemon-reload

8. Support

En cas de problème :

Consulter les logs du service :

journalctl -u vpn.service -xe


Vérifier que le .ovpn est valide et fonctionnel.

Vérifier que le script vpn_install_alias_v1.1.sh est exécutable et fonctionnel.
