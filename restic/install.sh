#!/bin/bash

wget https://github.com/restic/restic/releases/download/v0.17.1/restic_0.17.1_linux_amd64.bz2
sudo apt install -y bzip2
bunzip2 restic_0.17.1_linux_amd64.bz2
chmod +x restic_0.17.1_linux_amd64
sudo cp restic_0.17.1_linux_amd64 /usr/local/bin/restic

restic generate --bash-completion restic.bash
source restic.bash
