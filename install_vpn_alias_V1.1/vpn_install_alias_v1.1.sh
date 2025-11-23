#!/bin/bash

# ─────────────────────────────────────────────────────────────────────────────
# Install + Configure Stunnel + Start OpenVPN (sans modifier le .ovpn)
# Respecte l'ordre : install → stunnel OK → openvpn → vérifs
# Place ce script dans le même dossier que ton .ovpn
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"

# Utilisateur / HOME réels, que le script soit lancé avec ou sans sudo
if [ -n "${SUDO_USER-}" ] && [ "$SUDO_USER" != "root" ]; then
  REAL_USER="$SUDO_USER"
  REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
else
  REAL_USER="${USER:-$(id -un)}"
  REAL_HOME="${HOME:-$(getent passwd "$REAL_USER" | cut -d: -f6)}"
fi

export REAL_USER REAL_HOME


# Vars (modifie si besoin)
REMOTE_HOST="82.22.7.32"
REMOTE_PORT="443"
LOCAL_LISTEN_PORT="1194"
STUNNEL_LOG_DIR="/var/log/stunnel4"
STUNNEL_PID_DIR="/run/stunnel4"
OVPN_LOG="/var/log/openvpn_client.log"

# ── Affichage (cosmétique, sans impact fonctionnel) ──────────────────────────
: "${QUIET:=0}"      # 1 = moins de blabla
: "${NO_COLOR:=0}"   # 1 = pas de couleurs (ex: CI)
: "${USE_ICONS:=1}"  # 0 = pas d’emojis

is_tty() { [ -t 1 ]; }
if [ "$NO_COLOR" -eq 1 ] || ! is_tty; then
  C_BOLD=""; C_RED=""; C_GRN=""; C_YLW=""; C_BLU=""; C_RST=""
else
  C_BOLD="$(printf '\033[1m')"; C_RST="$(printf '\033[0m')"
  C_RED="$(printf '\033[31m')"; C_GRN="$(printf '\033[32m')"
  C_YLW="$(printf '\033[33m')"; C_BLU="$(printf '\033[34m')"
fi
i_ok="✅"; i_err="❌"; i_inf="ℹ️ "; i_wrn="⚠️"
[ "$USE_ICONS" -eq 1 ] || { i_ok="[OK]"; i_err="[ERREUR]"; i_inf="[INFO]"; i_wrn="[AVERT]"; }

section()  { [ "$QUIET" -eq 0 ] && printf "\n%b==>%b %s\n" "$C_BOLD" "$C_RST" "$*"; }
log_ok()   { printf "%b%s%b %s\n" "$C_GRN" "$i_ok" "$C_RST" "$*"; }
log_err()  { printf "%b%s%b %s\n" "$C_RED" "$i_err" "$C_RST" "$*"; }
log_warn() { printf "%b%s%b %s\n" "$C_YLW" "$i_wrn" "$C_RST" "$*"; }
log_info() { [ "$QUIET" -eq 0 ] && printf "%b%s%b %s\n" "$C_BLU" "$i_inf" "$C_RST" "$*"; }

# ─────────────────────────────────────────────────────────────────────────────
section "Nettoyage des interfaces TUN"
for i in $(ip -o link show | awk -F': ' '{print $2}' | grep -E '^tun[0-9]+'); do
  log_info "Suppression ${i}"
  sudo ip link delete "$i" 2>/dev/null || true
done

section "Dépendances (openvpn, stunnel4, curl)"
missing=()
dpkg -s openvpn  >/dev/null 2>&1 || missing+=("openvpn")
dpkg -s stunnel4 >/dev/null 2>&1 || missing+=("stunnel4")
command -v curl   >/dev/null 2>&1 || missing+=("curl")

if [ "${#missing[@]}" -gt 0 ]; then
  log_info "Installation manquante : ${missing[*]}"
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get -qq update < /dev/null
  if ! sudo apt-get -y -qq \
      -o=Dpkg::Use-Pty=0 \
      -o=Acquire::Retries=2 \
      --no-install-recommends install "${missing[@]}" \
      < /dev/null > /tmp/vpn_install_deps.log 2>&1; then
        log_err "Échec d'installation. Voir : /tmp/vpn_install_deps.log"
        exit 1
  fi
  log_ok "Paquets installés : ${missing[*]}"
else
  log_ok "Déjà présents : openvpn, stunnel4, curl"
fi

section "Configuration stunnel (client)"
sudo install -d -o stunnel4 -g stunnel4 -m 0755 "$STUNNEL_PID_DIR"
sudo install -d -o stunnel4 -g stunnel4 -m 0750 "$STUNNEL_LOG_DIR"

echo 'ENABLED=1' | sudo tee /etc/default/stunnel4 >/dev/null

sudo fuser -k "${LOCAL_LISTEN_PORT}"/tcp 2>/dev/null || true

sudo tee /etc/stunnel/stunnel.conf >/dev/null <<EOF
setuid = stunnel4
setgid = stunnel4
pid = ${STUNNEL_PID_DIR}/stunnel4.pid

client = yes
foreground = no
debug = info
output = ${STUNNEL_LOG_DIR}/client.log

[openvpn]
accept  = 127.0.0.1:${LOCAL_LISTEN_PORT}
connect = ${REMOTE_HOST}:${REMOTE_PORT}
verify = 0
EOF

sudo systemctl daemon-reload
sudo systemctl unmask stunnel4 2>/dev/null || true
sudo update-rc.d stunnel4 defaults >/dev/null 2>&1 || true
sudo service stunnel4 restart || sudo service stunnel4 start

section "Vérifications stunnel"
for i in {1..20}; do
  if ss -ltn 2>/dev/null | grep -q "127\.0\.0\.1:${LOCAL_LISTEN_PORT}"; then
    log_ok "Port local 127.0.0.1:${LOCAL_LISTEN_PORT} en écoute"
    break
  fi
  sleep 1
  if [ "$i" -eq 20 ]; then
    log_err "127.0.0.1:${LOCAL_LISTEN_PORT} non détecté"
    [ -f "${STUNNEL_LOG_DIR}/client.log" ] && sudo tail -n 80 "${STUNNEL_LOG_DIR}/client.log" || true
    # pas de exit 1 → on continue, openvpn échouera peut-être mais le script finit
  fi
done

command -v nc >/dev/null 2>&1 && nc -vzn "${REMOTE_HOST}" "${REMOTE_PORT}" || true

section "Détection du fichier client OpenVPN (.ovpn)"
OVPN="$(ls -1t "${SCRIPT_DIR}"/*.ovpn 2>/dev/null | head -n1 || true)"
if [ -z "${OVPN}" ]; then
  log_err "Aucun .ovpn trouvé dans ${SCRIPT_DIR}"
  exit 1
fi
log_ok "Fichier détecté : ${OVPN}"

section "Patch .ovpn (désactivation directives Windows)"
sudo find "${SCRIPT_DIR}" -maxdepth 1 -type f -name "$(basename "${OVPN}").bak.*" -print -delete 2>/dev/null || true
sudo cp -a "${OVPN}" "${OVPN}.bak.$(date +%Y%m%d%H%M%S)"
sudo sed -i -E \
  -e 's/^[[:space:]]*ignore-unknown-option block-outside-dns.*/;# auto-disabled for Linux: &/I' \
  -e 's/^[[:space:]]*setenv opt block-outside-dns.*/;# auto-disabled for Linux: &/I' \
  -e 's/^[[:space:]]*explicit-exit-notify.*/;# auto-disabled for Linux: &/I' \
  "${OVPN}"
log_ok "Patch appliqué (backup créé)"

section "Démarrage d'OpenVPN"

# Préparation du fichier de log (sans faire planter le script)
if ! sudo touch "$OVPN_LOG" >/dev/null 2>&1 || ! sudo chmod 640 "$OVPN_LOG" >/dev/null 2>&1; then
  log_warn "Impossible de préparer le fichier de log $OVPN_LOG (permissions ?)"
fi

# Démarrage OpenVPN sans laisser set -e tuer le script
if ! sudo openvpn --config "${OVPN}" --daemon --log "$OVPN_LOG"; then
  log_err "Échec du démarrage OpenVPN. Voir les logs : $OVPN_LOG"
  sudo tail -n 40 "$OVPN_LOG" || true
else
  # Attendre la création d'une interface tunX (jusqu'à 30s)
  TUN_IF=""
  for i in {1..30}; do
    TUN_IF="$(ip -o link show | awk -F': ' '/tun[0-9]+/ {print $2; exit}')"
    if [ -n "${TUN_IF:-}" ] && ip link show "${TUN_IF}" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if [ -n "${TUN_IF:-}" ] && ip link show "${TUN_IF}" >/dev/null 2>&1; then
    VPN_IP="$(ip -4 addr show dev "${TUN_IF}" | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)"
    if [ -n "${VPN_IP}" ]; then
      log_ok  "Interface VPN : ${TUN_IF}"
      log_info "IP interne : ${VPN_IP}"
    else
      log_warn "Interface ${TUN_IF} détectée, mais pas d'IP v4"
    fi
  else
    log_err "Le VPN n'a pas démarré correctement (pas d'interface tunX)"

    # Vérifie si OpenVPN a renvoyé une erreur connue
    if grep -qi "AUTH_FAILED" "$OVPN_LOG"; then
      echo "❌ Raison : Erreur d'authentification (login / mot de passe incorrect)."
    elif grep -qi "TLS" "$OVPN_LOG"; then
      echo "❌ Raison : Problème TLS (certificat, clé ou négociation)."
    elif grep -qi "Connection refused" "$OVPN_LOG"; then
      echo "❌ Raison : Le serveur refuse la connexion (mauvais port ou stunnel KO)."
    elif grep -qi "RESOLVE" "$OVPN_LOG"; then
      echo "❌ Raison : Impossible de résoudre l'adresse du serveur (DNS)."
    elif grep -qi "network unreachable" "$OVPN_LOG"; then
      echo "❌ Raison : Réseau inaccessible (route, firewall, interface down)."
    else
      echo "❌ Raison : Inconnue — affichage des 40 dernières lignes ci-dessous."
    fi

    sudo tail -n 40 "$OVPN_LOG" || true
    # pas de exit 1 -> on continue pour créer les aliases
  fi
fi


# IP publique (via le tunnel si la route par défaut passe par tunX)
PUB_IP="$(curl -s -4 https://ifconfig.me || true)"
[ -n "${PUB_IP}" ] && log_info "IP publique : ${PUB_IP}"

section "Post-install : Aliases Bash & Zsh (idempotent)"
set +u
ALIAS_DIR="$REAL_HOME/.config/shell"
ALIAS_ENV="$ALIAS_DIR/vpnctl.env"
ALIAS_FILE="$ALIAS_DIR/aliases-vpn.sh"
set -u

# Création du répertoire d'aliases avec le bon propriétaire
sudo install -d -o "$REAL_USER" -g "$REAL_USER" -m 700 "$ALIAS_DIR"

# 1) Environnement VPN
cat >"$ALIAS_ENV" <<EOF
# --- vpnctl.env (auto) ---
VPN_CONF="$(readlink -f "${OVPN}")"
OVPN_LOG="${OVPN_LOG}"
STUNNEL_SERVICE="stunnel4"
EOF
sudo chown "$REAL_USER:$REAL_USER" "$ALIAS_ENV"
sudo chmod 600 "$ALIAS_ENV"

# 2) Script d'alias
cat >"$ALIAS_FILE" <<'EOF'
# --- aliases-vpn.sh (auto) ---
[ -f "$HOME/.config/shell/vpnctl.env" ] && . "$HOME/.config/shell/vpnctl.env"

_vpn_require_conf() {
  if [ -z "${VPN_CONF:-}" ]; then
    echo "❌ VPN_CONF non défini. Ex: export VPN_CONF=\"$HOME/mon.ovpn\""
    return 1
  fi
}

_vpn_running() {
  [ -n "${VPN_CONF:-}" ] && pgrep -fa "openvpn.*--config[= ]${VPN_CONF}" >/dev/null 2>&1
}

_vpn_start_proc() { sudo openvpn --config "$VPN_CONF" --daemon ${OVPN_LOG:+--log "$OVPN_LOG"}; }
_vpn_stop_proc()  { pgrep -f "openvpn.*--config[= ]${VPN_CONF}" >/dev/null 2>&1 \
                      && sudo pkill -f "openvpn.*--config[= ]${VPN_CONF}" \
                      || sudo pkill -x openvpn >/dev/null 2>&1 || true; }

vpn-start()   { _vpn_require_conf || return 1;
                [ -n "${STUNNEL_SERVICE:-}" ] && { sudo service "$STUNNEL_SERVICE" restart >/dev/null 2>&1 || sudo service "$STUNNEL_SERVICE" start >/dev/null 2>&1 || true; }
                _vpn_running && echo "ℹ️  OpenVPN déjà démarré" || { _vpn_start_proc && echo "✅ VPN démarré"; }
                sleep 2; command -v curl >/dev/null 2>&1 && { echo -n "IP publique: "; curl -s -4 https://ifconfig.me; echo; }; }

vpn-stop()    { _vpn_require_conf || return 1; _vpn_stop_proc && echo "🛑 VPN arrêté"; }
vpn-restart() { _vpn_require_conf || return 1; _vpn_stop_proc;
                [ -n "${STUNNEL_SERVICE:-}" ] && { sudo service "$STUNNEL_SERVICE" restart >/dev/null 2>&1 || true; }
                _vpn_start_proc && echo "🔄 VPN redémarré";
                sleep 2; command -v curl >/dev/null 2>&1 && { echo -n "IP publique: "; curl -s -4 https://ifconfig.me; echo; }; }

vpn-status()  { _vpn_require_conf || return 1;
                echo "=== stunnel ==="; [ -n "${STUNNEL_SERVICE:-}" ] && (service "$STUNNEL_SERVICE" status 2>/dev/null || true | sed -n '1,12p') || echo "(stunnel non configuré)";
                echo; echo "=== openvpn ==="; _vpn_running && echo "✔️  actif pour: $VPN_CONF" || echo "✖️  non détecté pour: $VPN_CONF";
                echo; echo "=== réseau ==="; ip -brief addr show | awk '/^tun[0-9]+/ {print "IF:",$1,"→",$3}';
                command -v curl >/dev/null 2>&1 && { echo -n "IP publique: "; curl -s -4 https://ifconfig.me; echo; }; }

stunnel-start()  { [ -n "${STUNNEL_SERVICE:-}" ] && sudo service "$STUNNEL_SERVICE" start  && echo "✅ stunnel démarré"  || echo "stunnel non configuré"; }
stunnel-stop()   { [ -n "${STUNNEL_SERVICE:-}" ] && sudo service "$STUNNEL_SERVICE" stop   && echo "🛑 stunnel arrêté"   || echo "stunnel non configuré"; }
stunnel-status() { [ -n "${STUNNEL_SERVICE:-}" ] && service "$STUNNEL_SERVICE" status --full | sed -n '1,20p' || echo "stunnel non configuré"; }
# --- fin aliases-vpn.sh ---
EOF
sudo chown "$REAL_USER:$REAL_USER" "$ALIAS_FILE"
sudo chmod 644 "$ALIAS_FILE"

# 3) Sourcing dans les RC du bon user
for RC in "$REAL_HOME/.bashrc" "$REAL_HOME/.zshrc"; do
  [ -f "$RC" ] || sudo -u "$REAL_USER" touch "$RC"
  if ! grep -Fq "$ALIAS_FILE" "$RC"; then
    printf '\n# VPN aliases (auto)\n[ -f "%s" ] && . "%s"\n' "$ALIAS_FILE" "$ALIAS_FILE" | sudo tee -a "$RC" >/dev/null
    sudo chown "$REAL_USER:$REAL_USER" "$RC"
  fi
done

PROFILE="$REAL_HOME/.profile"
if [ -f "$REAL_HOME/.bashrc" ]; then
  grep -Fq '.bashrc' "$PROFILE" 2>/dev/null || {
    printf '\n# Source .bashrc si shell de login\n[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"\n' | sudo tee -a "$PROFILE" >/dev/null
    sudo chown "$REAL_USER:$REAL_USER" "$PROFILE"
  }
fi

log_ok "Aliases installés pour $REAL_USER (Bash & Zsh)"
[ "$QUIET" -eq 0 ] && {
  printf "%s\n" "   ▶ vpn-start     → démarre stunnel + openvpn"
  printf "%s\n" "   ▶ vpn-stop      → arrête openvpn"
  printf "%s\n" "   ▶ vpn-restart   → redémarre stunnel + openvpn"
  printf "%s\n" "   ▶ vpn-status    → état du VPN + IP + interface tun"
  printf "%s\n" ""
  printf "%s\n" "   ▶ stunnel-start → démarre stunnel"
  printf "%s\n" "   ▶ stunnel-stop  → arrête stunnel"
  printf "%s\n" "   ▶ stunnel-status→ état de stunnel"
  printf "%s\n" ""
  log_info "Recharge : 'source ~/.bashrc' (bash) ou 'source ~/.zshrc' (zsh) pour $REAL_USER"
}

section "Terminé"
