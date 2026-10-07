#! /bin/bash 

# Assumes Seileo Installed: Install Packages
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
    dbkg \ 
    coreutils \ 
    ca-certificates \
    zsh \
    git \
    ~/tmp/com.fiore.trolldecrypt_1.2.4_iphoneos-arm64.deb

# Upgrade Stuff on Device:
sudo apt update -o Acquire::AllowInsecureRepositories=true && \
    sudo apt \ 
    -o Acquire::AllowInsecureRepositories=true \
    -o Acquire::AllowDowngradeToInsecureRepositories=true \
    --allow-unauthenticated \
    upgrade -y 


# ZSH + Terminal Rice:
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
# Open ~/.zshrc, find the line that sets ZSH_THEME, and change its value to "powerlevel10k/powerlevel10k".
# ^ Need a script that does this... 
