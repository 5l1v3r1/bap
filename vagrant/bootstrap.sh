#!/usr/bin/env bash

apt-get update
apt-get install -y ocaml ocaml-native-compilers ocaml-findlib camlidl binutils-dev automake libcamomile-ocaml-dev otags libpcre3-dev camlp4-extra bison flex zlib1g-dev libgmp3-dev g++ libtool make

echo 0 > /proc/sys/kernel/yama/ptrace_scope

cd /vagrant
./autogen.sh
./configure
make test