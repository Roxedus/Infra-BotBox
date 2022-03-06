#!/bin/bash

source venv/bin/activate

yamllint -sc .yamllint .

ansible-lint -p
