#!/bin/bash
# Runs ON the device (as mobile). installer.sh copies this, the TrollDecrypt
# .deb and the dotfiles/ folder into ~/ first. Assumes Sileo is installed.
set -u

# --- packages ---------------------------------------------------------------
sudo apt install -y \
    re.frida.server \
    sqlite3 \
    openssh \
    curl \
    vim \
    unzip \
    git \
    ellekit \
    preferenceloader \
    findutils \
    com.tigisoftware.filza \
    essential \
    gpgv \
    darwintools \
    file-cmds \
    grep \
    less \
    dpkg \
    coreutils \
    ca-certificates \
    zsh \
    "$HOME"/com.fiore.trolldecrypt_1.2.4_iphoneos-arm64.deb

# --- upgrade everything -----------------------------------------------------
sudo apt update -o Acquire::AllowInsecureRepositories=true && \
    sudo apt \
    -o Acquire::AllowInsecureRepositories=true \
    -o Acquire::AllowDowngradeToInsecureRepositories=true \
    --allow-unauthenticated \
    upgrade -y

# --- zsh + oh-my-zsh + powerlevel10k ----------------------------------------
# git on a rootless jailbreak needs to be told where the CA bundle lives,
# otherwise the https clones below fail with a certificate error.
for ca in /var/jb/etc/ssl/certs/cacert.pem /etc/ssl/certs/cacert.pem; do
    if [ -f "$ca" ]; then git config --global http.sslCAInfo "$ca"; break; fi
done

# Unattended: don't switch shells or launch zsh mid-script, keep our own .zshrc.
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi
P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
if [ ! -d "$P10K_DIR" ]; then
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
fi

# Drop in the dotfiles shipped with the repo (backing up whatever was there).
install_dotfile() {   # install_dotfile <src> <dest>
    [ -f "$1" ] || { echo "!! missing $1 (did installer.sh copy dotfiles/?)"; return 1; }
    if [ -f "$2" ] && ! cmp -s "$1" "$2"; then cp "$2" "$2.bak"; fi
    cp "$1" "$2"
    echo ">> installed $2"
}
install_dotfile "$HOME/dotfiles/zshrc"    "$HOME/.zshrc"
install_dotfile "$HOME/dotfiles/p10k.zsh" "$HOME/.p10k.zsh"

# Make zsh the login shell for ssh sessions.
ZSH_BIN="$(command -v zsh)"
if [ -n "$ZSH_BIN" ] && [ "${SHELL:-}" != "$ZSH_BIN" ]; then
    if command -v chsh >/dev/null 2>&1; then
        sudo chsh -s "$ZSH_BIN" "$USER" || true
    fi
    # Rootless jailbreaks keep their own passwd; patch it if chsh didn't take.
    for pw in /var/jb/etc/passwd /etc/passwd; do
        if [ -f "$pw" ] && grep -qE "^$USER:.*:/bin/sh$" "$pw"; then
            sudo sed -i.bak -E "s#^($USER:.*):/bin/sh\$#\1:$ZSH_BIN#" "$pw"
        fi
    done
fi

echo
echo ">> Done. Reconnect over ssh to get the zsh + powerlevel10k prompt."
