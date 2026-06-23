#!/bin/bash

mkdir libs
pip install --target=./libs requests pyyaml elasticsearch elastic_transport dataclasses
cleanpy ./
