#!/usr/bin/env bash
set -euo pipefail

# Auto-élévation en root si nécessaire
if [[ $EUID -ne 0 ]]; then
    echo "Élévation des privilèges requise. Relance du script avec sudo..."
    exec sudo -E bash "$0" "$@"
fi

echo "=== Installation / mise à jour du service vpn.service ==="

# Demande du chemin vers le script VPN
read -rp "Chemin complet du script VPN (ex: /opt/scripts/vpn_install_alias_v1.sh) : " VPN_SCRIPT

if [[ ! -f "$VPN_SCRIPT" ]]; then
    echo "Erreur : fichier introuvable : $VPN_SCRIPT"
    exit 1
fi

chmod +x "$VPN_SCRIPT"

# Suppression automatique des sudo pour compatibilité systemd
sed -i 's/\<sudo\>[[:space:]]\{1,\}//g' "$VPN_SCRIPT"
echo "→ Nettoyage effectué : suppression des sudo dans le script VPN."

SCRIPT_DIR="$(dirname "$VPN_SCRIPT")"

echo "→ Script détecté : $VPN_SCRIPT"
echo "→ Dossier        : $SCRIPT_DIR"

# Détection des fichiers .ovpn dans le même dossier
shopt -s nullglob
ovpn_files=("$SCRIPT_DIR"/*.ovpn)
shopt -u nullglob

OVPN_CONFIG=""

if (( ${#ovpn_files[@]} == 0 )); then
    echo "⚠ Aucun fichier .ovpn détecté dans : $SCRIPT_DIR"
    echo "   Le service sera créé sans variable OVPN_CONFIG."
elif (( ${#ovpn_files[@]} == 1 )); then
    OVPN_CONFIG="${ovpn_files[0]}"
    echo "→ Fichier .ovpn détecté : $OVPN_CONFIG"
else
    echo "Plusieurs fichiers .ovpn détectés dans : $SCRIPT_DIR"
    select f in "${ovpn_files[@]}"; do
        if [[ -n "$f" ]]; then
            OVPN_CONFIG="$f"
            echo "→ Fichier .ovpn sélectionné : $OVPN_CONFIG"
            break
        fi
    done
fi

SERVICE_FILE="/etc/systemd/system/vpn.service"

echo
echo "=== Reset de l'ancien service vpn.service (si présent) ==="
if systemctl list-unit-files | grep -q '^vpn.service'; then
    systemctl stop vpn.service 2>/dev/null || true
    systemctl disable vpn.service 2>/dev/null || true
fi

echo
echo "=== Création de $SERVICE_FILE ==="

EXTRA_ENV=""
if [[ -n "$OVPN_CONFIG" ]]; then
    EXTRA_ENV="Environment=OVPN_CONFIG=$OVPN_CONFIG"
fi

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=VPN alias/setup script
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=$SCRIPT_DIR
ExecStart=/bin/bash -e $VPN_SCRIPT
RemainAfterExit=yes
User=root
Group=root
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
$EXTRA_ENV

[Install]
WantedBy=multi-user.target
EOF

echo "→ Fichier systemd généré : $SERVICE_FILE"

echo
echo "=== Reload / enable / start du service ==="
systemctl daemon-reload
systemctl enable vpn.service
systemctl start vpn.service

echo
echo "=== Statut du service ==="
systemctl status vpn.service --no-pager || true

echo
echo "Installation terminée."
echo "Aliases et VPN seront gérés par : vpn.service"
