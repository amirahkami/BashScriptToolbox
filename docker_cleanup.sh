#!/bin/bash

# Remove all unused images (both dangling and unreferenced). Images still tied
# to any (running or stopped) container are not removed. (-a == --all)
docker image prune -a --force

# Remove all unused local volumes. With "-a/--all", this includes *named* volumes,
# not just anonymous ones. Use with caution if you store DB/data in named volumes.
docker volume prune -a --force  

# Remove all unused BuildKit cache entries (layers, etc.). "-a" targets all unused
# cache, not just dangling. This will force future builds to rebuild more layers.
docker builder prune -a  --force