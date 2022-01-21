#!/bin/bash

source venv/bin/activate

yamllint -sc yamllint.yaml .

ansible-lint -p
