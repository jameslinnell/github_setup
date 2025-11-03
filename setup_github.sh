#!/bin/bash

set -e

# Detect operating system
echo "Detecting operating system..."
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS=$ID
else
  echo "Unsupported operating system. Exiting."
  exit 1
fi

# Install necessary packages
echo "Installing required packages..."
case $OS in
arch)
  sudo pacman -Sy --needed git gnupg openssh github-cli --noconfirm
  ;;
ubuntu)
  sudo apt update && sudo apt install -y git gnupg openssh-client gh
  ;;
*)
  echo "Unsupported operating system: $OS. Exiting."
  exit 1
  ;;
esac

# Configure Git (prompting for user input)
echo "Configuring Git..."
read -p "Enter your Git username: " git_username
read -p "Enter your Git email: " git_email
git config --global user.name "$git_username"
git config --global user.email "$git_email"
git config --global init.defaultBranch main

# Generate SSH key
echo "Generating SSH key..."
ssh_key_path="$HOME/.ssh/id_ed25519"
if [[ -f "$ssh_key_path" ]]; then
  echo "SSH key already exists at $ssh_key_path."
else
  ssh-keygen -t ed25519 -C "$git_email" -f "$ssh_key_path" -N ""
  eval "$(ssh-agent -s)"
  ssh-add "$ssh_key_path"
  echo "SSH key generated."
fi

# Authenticate with GitHub CLI using a Personal Access Token
echo "Authenticating with GitHub CLI..."
read -sp "Enter your GitHub Personal Access Token (PAT): " github_pat
echo
echo "$github_pat" | gh auth login --with-token

# Add SSH key to GitHub
echo "Uploading SSH key to GitHub..."
ssh_pub_key=$(cat "$ssh_key_path.pub")
gh ssh-key add "$ssh_key_path.pub" --title "$(hostname)-$(date +%Y%m%d)"

# Generate GPG key
echo "Generating GPG key..."
gpg --batch --full-generate-key <<EOF
%no-protection
Key-Type: eddsa
Key-Curve: ed25519
Key-Usage: sign
Subkey-Type: ecdh
Subkey-Curve: cv25519
Subkey-Usage: encrypt
Name-Real: $git_username
Name-Email: $git_email
Expire-Date: 0
EOF

# gpg_key_id=$(gpg --list-keys --with-colons | grep '^pub' | cut -d: -f5 | head -n 1)
gpg_key_id=$(gpg --list-keys --with-colons | awk -F: '/^pub/ {print $5 ":" $6}' | sort -t: -k2 -n | tail -n 1 | cut -d: -f1)
echo "GPG key ID: $gpg_key_id"

# Export GPG public key and upload it to GitHub
echo "Uploading GPG key to GitHub..."
gpg --armor --export "$gpg_key_id" | gh gpg-key add -

# Configure Git to use the GPG key
echo "Configuring Git to use GPG key..."
git config --global user.signingkey "$gpg_key_id"
git config --global commit.gpgSign true

# Summary
echo "Setup complete!"
echo "Git configured for user: $git_username <$git_email>"
echo "SSH key added to GitHub: $ssh_pub_key"
echo "GPG key added to GitHub and configured: $gpg_key_id"
