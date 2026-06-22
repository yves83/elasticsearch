#!/bin/bash

# Download Python Lib Modules
pip install --target=./libs elasticsearch

# Download Azure Copy Tools
wget https://aka.ms/downloadazcopy-v10-linux -O download.tgz &&
tar zxvf download.tgz &&
find ./ -type f -name azcopy -exec mv {} ./ \; &&
rm -rf azcopy_* download.tgz
