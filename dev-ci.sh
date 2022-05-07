#!/bin/bash

yamllint -sc .yamllint .

ansible-lint -p
